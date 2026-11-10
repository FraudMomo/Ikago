#import "IKCEFAudio.h"
#import "IKCEFAudioInternal.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#include <atomic>
#include <cmath>
#include <map>
#include <memory>
#include <mutex>
#include <vector>
#include <mach/mach_time.h>

namespace {
constexpr int kBands = 5;

constexpr int kFFT = 512;
/// Band edges in Hz, where voices and most instruments live: low voice and bass lines, voice fundamentals, the body
/// of chords and vowels, then the formants and presence that make speech and melody readable. No sub-bass or air.
constexpr double kEdges[kBands + 1] = {120, 250, 500, 1000, 2000, 4000};
/// The wave shows this many dB below the recent loudest band, so quiet and loud tracks both move.
constexpr double kRange = 30;

double NowMicroseconds() {
  static mach_timebase_info_data_t base = [] { mach_timebase_info_data_t b; mach_timebase_info(&b); return b; }();
  return double(mach_absolute_time()) * base.numer / base.denom / 1000.0;
}

/// One page's sound: a single-producer (CEF's audio thread), single-consumer (the render thread) ring of stereo frames.
struct Stream {
  int sampleRate = 48000;
  int channels = 2;
  std::vector<float> left, right;
  size_t capacity = 0;
  std::atomic<uint64_t> written{0}, read{0};
  std::atomic<bool> playing{false}, muted{false};
  /// Frames held back before playback starts (and after a dry spell): enough to ride out one late packet.
  uint64_t prefill = 0;
  std::atomic<float> levels[kBands];
  /// The loudest band's level lately, in dB (CEF's audio thread only): follows peaks at once, sinks ~6 dB a second.
  double peak = -60;
  std::atomic<double> lastPacket{0};
  AVAudioSourceNode *node = nil;
  // Levels, on CEF's audio thread only.
  std::vector<float> history = std::vector<float>(kFFT, 0);
  std::vector<float> window = std::vector<float>(kFFT, 0);
  vDSP_DFT_Setup dft = nullptr;
  ~Stream() { if (dft) vDSP_DFT_DestroySetup(dft); }
};

/// Measurements for `latencyReport` (the `--cef-smoke-audio` probe); relaxed atomics, written from three threads.
struct Stats {
  std::atomic<double> arrival{0}, maxArrival{0}, buffered{0};
  std::atomic<long> samples{0}, renders{0}, underruns{0};
};

std::atomic<bool> captureEnabled{false};
std::mutex lock;
std::map<int, std::shared_ptr<Stream>> streams;
/// Ikago's mute per page, kept apart from streams: a page muted before it plays must start muted.
std::map<int, bool> mutedBrowsers;
Stats stats;
AVAudioEngine *engine;

AVAudioEngine *Engine() {
  if (!engine) {
    engine = [[AVAudioEngine alloc] init];
    [NSNotificationCenter.defaultCenter addObserverForName:AVAudioEngineConfigurationChangeNotification
        object:engine queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
      // A new output device: the engine stopped itself. Start it again if anything is still playing.
      std::lock_guard<std::mutex> guard(lock);
      if (!streams.empty()) [engine startAndReturnError:nil];
    }];
  }
  return engine;
}

void Analyze(Stream &s, const float **data, int frames) {
  // Slide the newest mono samples into the window, then read the bands' energy from one real DFT.
  int keep = std::max(0, kFFT - frames);
  memmove(s.history.data(), s.history.data() + (kFFT - keep), keep * sizeof(float));
  int start = std::max(0, frames - kFFT);
  for (int i = start; i < frames; i++) {
    float sample = data[0][i];
    if (s.channels > 1) sample = 0.5f * (sample + data[1][i]);
    s.history[keep + (i - start)] = sample;
  }
  if (!s.dft) {
    s.dft = vDSP_DFT_zrop_CreateSetup(nullptr, kFFT, vDSP_DFT_FORWARD);
    vDSP_hann_window(s.window.data(), kFFT, vDSP_HANN_NORM);
  }
  float windowed[kFFT], even[kFFT / 2], odd[kFFT / 2], re[kFFT / 2], im[kFFT / 2];
  vDSP_vmul(s.history.data(), 1, s.window.data(), 1, windowed, 1, kFFT);
  for (int i = 0; i < kFFT / 2; i++) { even[i] = windowed[2 * i]; odd[i] = windowed[2 * i + 1]; }
  vDSP_DFT_Execute(s.dft, even, odd, re, im);
  double binHz = double(s.sampleRate) / kFFT;
  double db[kBands], loudest = -120;
  for (int band = 0; band < kBands; band++) {
    int lo = std::max(1, int(kEdges[band] / binHz)), hi = std::min(kFFT / 2 - 1, int(kEdges[band + 1] / binHz));
    double energy = 0;
    for (int bin = lo; bin <= hi; bin++) energy += double(re[bin]) * re[bin] + double(im[bin]) * im[bin];
    // Higher bands carry less energy in voice and music; a gentle tilt keeps them in the picture.
    db[band] = 10 * log10(energy / std::max(1, hi - lo + 1) + 1e-12) + band * 3;
    loudest = std::max(loudest, db[band]);
  }
  double seconds = double(frames) / s.sampleRate;
  s.peak = std::max(loudest, std::max(s.peak - 6 * seconds, -70.0));
  for (int band = 0; band < kBands; band++) {
    // Silence stays flat: below -80 dB nothing is playing worth drawing.
    float level = loudest < -80 ? 0 : float(std::clamp((db[band] - (s.peak - kRange)) / kRange, 0.0, 1.0));
    float old = s.levels[band].load(std::memory_order_relaxed);
    // Quick to rise, slower to fall, and never all the way in one packet: calm, readable motion.
    float next = level > old ? old + (level - old) * 0.55f : old + (level - old) * 0.12f;
    s.levels[band].store(next, std::memory_order_relaxed);
  }
}

class Handler final : public CefAudioHandler {
 public:
  bool GetAudioParameters(CefRefPtr<CefBrowser>, CefAudioParameters& params) override {
    // False leaves Chromium's own playback untouched: no capture, no added delay, no wave.
    if (!captureEnabled.load()) return false;
    params.channel_layout = CEF_CHANNEL_LAYOUT_STEREO;
    params.sample_rate = int(lround([Engine().outputNode outputFormatForBus:0].sampleRate ?: 48000));
    // Small packets keep the added delay low: 256 frames is 5 ms at 48 kHz.
    params.frames_per_buffer = 256;
    return true;
  }
  void OnAudioStreamStarted(CefRefPtr<CefBrowser> browser, const CefAudioParameters& params, int channels) override {
    auto stream = std::make_shared<Stream>();
    stream->sampleRate = params.sample_rate;
    stream->channels = std::max(1, std::min(2, channels));
    stream->capacity = size_t(params.sample_rate);  // a second of sound
    stream->left.assign(stream->capacity, 0);
    stream->right.assign(stream->capacity, 0);
    stream->prefill = uint64_t(params.frames_per_buffer) * 1;  // one packet: no underruns measured
    for (auto &level : stream->levels) level.store(0);
    int identifier = browser->GetIdentifier();
    {
      std::lock_guard<std::mutex> guard(lock);
      stream->muted.store(mutedBrowsers[identifier]);
      streams[identifier] = stream;
    }
    std::weak_ptr<Stream> weak = stream;
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:params.sample_rate channels:2];
    stream->node = [[AVAudioSourceNode alloc] initWithFormat:format
        renderBlock:^OSStatus(BOOL *silence, const AudioTimeStamp *, AVAudioFrameCount frames, AudioBufferList *output) {
      auto s = weak.lock();
      float *l = (float *)output->mBuffers[0].mData, *r = (float *)output->mBuffers[1].mData;
      uint64_t w = s ? s->written.load(std::memory_order_acquire) : 0, rd = s ? s->read.load(std::memory_order_relaxed) : 0;
      uint64_t available = w - rd;
      if (s && !s->playing.load(std::memory_order_relaxed) && available >= s->prefill) s->playing.store(true);
      if (!s || !s->playing.load(std::memory_order_relaxed) || available < frames) {
        if (s && s->playing.load(std::memory_order_relaxed)) { s->playing.store(false); stats.underruns.fetch_add(1, std::memory_order_relaxed); }
        memset(l, 0, frames * sizeof(float)); memset(r, 0, frames * sizeof(float));
        *silence = YES;
        return noErr;
      }
      // Keep only what this render and one late packet need: a backlog (from the engine starting, or a stall) would
      // otherwise stay as delay for good.
      uint64_t keep = frames + s->prefill;
      if (available > keep + s->prefill) { rd = w - keep; available = keep; }
      stats.buffered.fetch_add(double(available) / s->sampleRate * 1000, std::memory_order_relaxed);
      stats.renders.fetch_add(1, std::memory_order_relaxed);
      bool mute = s->muted.load(std::memory_order_relaxed);
      for (AVAudioFrameCount i = 0; i < frames; i++) {
        size_t at = (rd + i) % s->capacity;
        l[i] = mute ? 0 : s->left[at]; r[i] = mute ? 0 : s->right[at];
      }
      s->read.store(rd + frames, std::memory_order_release);
      return noErr;
    }];
    AVAudioSourceNode *node = stream->node;
    dispatch_async(dispatch_get_main_queue(), ^{
      AVAudioEngine *e = Engine();
      [e attachNode:node];
      [e connect:node to:e.mainMixerNode format:format];
      if (!e.isRunning) [e startAndReturnError:nil];
    });
  }
  void OnAudioStreamPacket(CefRefPtr<CefBrowser> browser, const float **data, int frames, int64_t pts) override {
    std::shared_ptr<Stream> s;
    {
      std::lock_guard<std::mutex> guard(lock);
      auto found = streams.find(browser->GetIdentifier());
      if (found != streams.end()) s = found->second;
    }
    if (!s || frames <= 0) return;
    // pts is Chromium's TimeTicks in milliseconds, the same clock as mach_absolute_time.
    double late = NowMicroseconds() / 1000 - double(pts);
    stats.arrival.fetch_add(late, std::memory_order_relaxed); stats.samples.fetch_add(1, std::memory_order_relaxed);
    if (late > stats.maxArrival.load(std::memory_order_relaxed)) stats.maxArrival.store(late, std::memory_order_relaxed);
    uint64_t w = s->written.load(std::memory_order_relaxed), rd = s->read.load(std::memory_order_acquire);
    // A stalled output (no device) mustn't let the writer lap the reader: drop the oldest instead.
    if (w + frames - rd > s->capacity) s->read.store(w + frames - s->capacity, std::memory_order_release);
    for (int i = 0; i < frames; i++) {
      size_t at = (w + i) % s->capacity;
      s->left[at] = data[0][i];
      s->right[at] = s->channels > 1 ? data[1][i] : data[0][i];
    }
    s->written.store(w + frames, std::memory_order_release);
    s->lastPacket.store(NowMicroseconds(), std::memory_order_relaxed);
    Analyze(*s, data, frames);
  }
  void OnAudioStreamStopped(CefRefPtr<CefBrowser> browser) override { Remove(browser->GetIdentifier()); }
  void OnAudioStreamError(CefRefPtr<CefBrowser> browser, const CefString& message) override {
    NSLog(@"Ikago audio capture stopped: %s", message.ToString().c_str());
    Remove(browser->GetIdentifier());
  }

 private:
  static void Remove(int identifier) {
    std::shared_ptr<Stream> stream;
    {
      std::lock_guard<std::mutex> guard(lock);
      auto found = streams.find(identifier);
      if (found == streams.end()) return;
      stream = found->second;
      streams.erase(found);
    }
    AVAudioSourceNode *node = stream->node;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (node) [Engine() detachNode:node];
      std::lock_guard<std::mutex> guard(lock);
      if (streams.empty()) [Engine() stop];
    });
  }
  IMPLEMENT_REFCOUNTING(Handler);
};
}

CefRefPtr<CefAudioHandler> IKCEFMakeAudioHandler() { return new Handler(); }

void IKCEFSetAudioMuted(int browserID, bool muted) {
  std::lock_guard<std::mutex> guard(lock);
  if (muted) mutedBrowsers[browserID] = true; else mutedBrowsers.erase(browserID);
  auto found = streams.find(browserID);
  if (found != streams.end()) found->second->muted.store(muted);
}

@implementation IKCEFAudio
+ (BOOL)enabled { return captureEnabled.load(); }
+ (void)setEnabled:(BOOL)enabled { captureEnabled.store(enabled); }
+ (NSArray<NSNumber *> *)levelsForBrowser:(int)browserID {
  std::shared_ptr<Stream> s;
  {
    std::lock_guard<std::mutex> guard(lock);
    auto found = streams.find(browserID);
    if (found == streams.end()) return nil;
    s = found->second;
  }
  // Nothing new for a moment (paused): let the bars settle instead of freezing mid-beat.
  bool stale = NowMicroseconds() - s->lastPacket.load() > 150000;
  NSMutableArray *levels = [NSMutableArray arrayWithCapacity:kBands];
  for (auto &level : s->levels) {
    if (stale) level.store(level.load() * 0.7f);
    [levels addObject:@(s->muted.load() ? 0 : level.load())];
  }
  return levels;
}
+ (NSDictionary<NSString *, NSNumber *> *)latencyReport {
  AVAudioEngine *e = Engine();
  double output = e.outputNode.presentationLatency * 1000;
  long samples = stats.samples.load(), renders = stats.renders.load();
  return @{@"arrival": @(samples ? stats.arrival.load() / samples : -1), @"maxArrival": @(stats.maxArrival.load()),
           @"buffered": @(renders ? stats.buffered.load() / renders : -1), @"output": @(output),
           @"packets": @(samples), @"underruns": @(stats.underruns.load())};
}
@end
