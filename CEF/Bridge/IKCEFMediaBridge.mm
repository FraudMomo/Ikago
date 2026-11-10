#import "IKCEFMediaBridge.h"
#include "IKCEFMediaBridgeInternal.h"
#include "include/cef_parser.h"
#include "include/cef_resource_handler.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <map>
#include <os/log.h>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace {
using Translator = void (^)(NSString *, NSData *, BOOL, int, void (^)(NSData *));
struct Config {
  std::vector<std::string> hosts;
  Translator translator = nil;
};
std::shared_ptr<const Config> config = std::make_shared<Config>();
constexpr size_t kMaximumBody = 48 * 1024 * 1024, kMaximumPart = 1024 * 1024, kMaximumParts = 256;
const std::string kPath = "/__ikago_media__";
os_log_t Log() { static os_log_t log = os_log_create("app.ikago.browser", "media-translation"); return log; }

bool HostMatches(const std::string& host, const std::vector<std::string>& hosts) {
  for (const auto& allowed : hosts)
    if (host == allowed || (host.size() > allowed.size() && host.ends_with("." + allowed))) return true;
  return false;
}

std::string QueryValue(const std::string& query, const std::string& name) {
  size_t start = 0;
  while (start <= query.size()) {
    size_t end = query.find('&', start);
    if (end == std::string::npos) end = query.size();
    const std::string pair = query.substr(start, end - start);
    if (pair.rfind(name + "=", 0) == 0) return pair.substr(name.size() + 1);
    start = end + 1;
  }
  return "";
}

bool ValidStream(const std::string& id) {
  if (id.empty() || id.size() > 64) return false;
  for (char c : id) if (!isalnum(static_cast<unsigned char>(c)) && c != '-') return false;
  return true;
}

int Number(const std::string& text, int maximum) {
  if (text.empty() || text.size() > 9) return -1;
  int value = 0;
  for (char c : text) { if (c < '0' || c > '9') return -1; value = value * 10 + (c - '0'); }
  return value <= maximum ? value : -1;
}

/// base64url without padding → bytes; false on anything else.
bool Decode(const std::string& text, std::string& out) {
  if (text.size() > kMaximumPart * 4 / 3 + 4) return false;
  out.clear();
  out.reserve(text.size() * 3 / 4);
  uint32_t buffer = 0;
  int bits = 0;
  for (char c : text) {
    int v;
    if (c >= 'A' && c <= 'Z') v = c - 'A'; else if (c >= 'a' && c <= 'z') v = c - 'a' + 26;
    else if (c >= '0' && c <= '9') v = c - '0' + 52; else if (c == '-') v = 62; else if (c == '_') v = 63; else return false;
    buffer = (buffer << 6) | v;
    bits += 6;
    if (bits >= 8) { bits -= 8; out.push_back(static_cast<char>((buffer >> bits) & 0xFF)); }
  }
  return true;
}

/// Segments arrive in parts (service workers don't pass request bodies through), and are put back together here.
struct Assembly { std::vector<std::string> parts; size_t received = 0, bytes = 0; std::chrono::steady_clock::time_point started; };
std::mutex assemblyLock;
std::map<std::string, Assembly> assemblies;

/// Stores one part. Returns the whole segment once every part is in, an empty string while waiting, nil on error.
NSData *Assemble(const std::string& key, int part, int parts, std::string bytes, bool& failed) {
  std::lock_guard<std::mutex> guard(assemblyLock);
  failed = false;
  const auto now = std::chrono::steady_clock::now();
  std::erase_if(assemblies, [&](const auto& item) { return now - item.second.started > std::chrono::seconds(60); });
  if (assemblies.size() > 64 && !assemblies.contains(key)) { failed = true; return nil; }
  auto& assembly = assemblies[key];
  if (assembly.parts.empty()) { assembly.parts.resize(parts); assembly.started = now; }
  if (static_cast<int>(assembly.parts.size()) != parts || !assembly.parts[part].empty() || assembly.bytes + bytes.size() > kMaximumBody) {
    assemblies.erase(key); failed = true; return nil;
  }
  assembly.bytes += bytes.size();
  assembly.parts[part] = std::move(bytes);
  if (++assembly.received < assembly.parts.size()) return nil;
  NSMutableData *whole = [NSMutableData dataWithCapacity:assembly.bytes];
  for (const auto& piece : assembly.parts) [whole appendBytes:piece.data() length:piece.size()];
  assemblies.erase(key);
  return whole;
}

class NoCookies final : public CefCookieAccessFilter {
  bool CanSendCookie(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest>, const CefCookie&) override { return false; }
  bool CanSaveCookie(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest>, CefRefPtr<CefResponse>, const CefCookie&) override { return false; }
  IMPLEMENT_REFCOUNTING(NoCookies);
};

/// Answers one part: an empty 200 while the segment is incomplete, the translated segment for the last part.
class Answer final : public CefResourceHandler {
 public:
  struct Part { std::string stream, key, data; int index, total; bool urgent; int fit; };
  Answer(Translator translator, Part part) : translator_(translator), stream_(part.stream), part_(std::move(part)) {}
  bool Open(CefRefPtr<CefRequest>, bool& handle_request, CefRefPtr<CefCallback> callback) override {
    // Here, not when the route is chosen: Open runs exactly once per request.
    std::string bytes;
    failed_ = !Decode(part_.data, bytes);
    part_.data.clear();
    if (!failed_) segment_ = Assemble(part_.key, part_.index, part_.total, std::move(bytes), failed_);
    if (failed_) os_log_error(Log(), "translation request malformed");
    if (failed_ || !segment_) {
      handle_request = true;
      if (!failed_) finish([NSData data]);
      return true;
    }
    handle_request = false;
    CefRefPtr<Answer> keep = this;
    NSString *stream = [NSString stringWithUTF8String:stream_.c_str()];
    Translator translator = translator_;
    NSData *segment = segment_;
    // The player waiting for it: now, on every core. Buffered ahead: background priority, which macOS keeps on the
    // efficiency cores, so scrolling and the page keep the performance cores.
    const BOOL urgent = part_.urgent;
    const int fit = part_.fit;
    dispatch_async(dispatch_get_global_queue(urgent ? QOS_CLASS_USER_INITIATED : QOS_CLASS_BACKGROUND, 0), ^{
      translator(stream, segment, urgent, fit, ^(NSData *result) {
        keep->finish(result);
        callback->Continue();
      });
    });
    return true;
  }
  void GetResponseHeaders(CefRefPtr<CefResponse> response, int64_t& length, CefString&) override {
    std::lock_guard<std::mutex> guard(lock_);
    response->SetStatus(result_ ? 200 : 500);
    response->SetStatusText(result_ ? "OK" : "Translation failed");
    response->SetMimeType("application/octet-stream");
    CefResponse::HeaderMap headers;
    headers.insert({"Cache-Control", "no-store"});
    headers.insert({"X-Content-Type-Options", "nosniff"});
    response->SetHeaderMap(headers);
    length = result_ ? result_.length : 0;
  }
  bool Read(void* out, int wanted, int& read, CefRefPtr<CefResourceReadCallback>) override {
    std::lock_guard<std::mutex> guard(lock_);
    read = 0;
    if (!result_ || offset_ >= result_.length || cancelled_) return false;
    const size_t count = std::min<size_t>(wanted, result_.length - offset_);
    memcpy(out, static_cast<const uint8_t *>(result_.bytes) + offset_, count);
    offset_ += count;
    read = static_cast<int>(count);
    return true;
  }
  void Cancel() override { std::lock_guard<std::mutex> guard(lock_); cancelled_ = true; }
 private:
  void finish(NSData *result) { std::lock_guard<std::mutex> guard(lock_); result_ = result; }
  Translator translator_;
  std::string stream_;
  Part part_;
  NSData *segment_ = nil;
  bool failed_ = false;
  std::mutex lock_;
  NSData *result_ = nil;
  size_t offset_ = 0;
  bool cancelled_ = false;
  IMPLEMENT_REFCOUNTING(Answer);
};

class Route final : public CefResourceRequestHandler {
 public:
  Route(Translator translator, Answer::Part part) : translator_(translator), part_(std::move(part)) {}
  CefRefPtr<CefResourceHandler> GetResourceHandler(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest>) override {
    return new Answer(translator_, part_);
  }
  CefRefPtr<CefCookieAccessFilter> GetCookieAccessFilter(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefRequest>) override {
    return new NoCookies();
  }
 private:
  Translator translator_;
  Answer::Part part_;
  IMPLEMENT_REFCOUNTING(Route);
};
}  // namespace

CefRefPtr<CefResourceRequestHandler> IKCEFMediaRoute(CefRefPtr<CefRequest> request, const CefString& initiator) {
  auto current = std::atomic_load(&config);
  if (!current->translator || request->GetMethod() != "GET") return nullptr;
  CefURLParts parts;
  if (!CefParseURL(request->GetURL(), parts)) return nullptr;
  const std::string scheme = CefString(&parts.scheme).ToString(), host = CefString(&parts.host).ToString(),
                    path = CefString(&parts.path).ToString(), query = CefString(&parts.query).ToString();
  if (scheme != "https" || path != kPath || !HostMatches(host, current->hosts)) return nullptr;
  // Chromium records which origin started the request; a page can't forge it. Only the site itself may ask.
  const std::string stream = QueryValue(query, "stream");
  const int seq = Number(QueryValue(query, "seq"), 1 << 30), part = Number(QueryValue(query, "part"), kMaximumParts - 1),
            total = Number(QueryValue(query, "parts"), kMaximumParts);
  if (initiator.ToString() != "https://" + host || !ValidStream(stream) || seq < 0 || part < 0 || total < 1 || part >= total) {
    os_log_error(Log(), "translation request refused");
    return nullptr;
  }
  const int fit = std::max(0, Number(QueryValue(query, "fit"), 16384));
  return new Route(current->translator, {stream, stream + ":" + std::to_string(seq), QueryValue(query, "data"), part, total,
                                         QueryValue(query, "urgent") != "0", fit});
}

@implementation IKCEFMediaBridge
+ (void)setHosts:(NSArray<NSString *> *)hosts translator:(void (^)(NSString *, NSData *, BOOL, int, void (^)(NSData *)))translator {
  auto next = std::make_shared<Config>();
  for (NSString *host in hosts) next->hosts.emplace_back(host.lowercaseString.UTF8String);
  next->translator = [translator copy];
  std::atomic_store(&config, std::shared_ptr<const Config>(next));
}
@end
