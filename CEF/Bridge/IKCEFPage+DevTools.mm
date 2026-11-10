#import "IKCEFPageInternal.h"
#include "include/cef_parser.h"
#include <climits>

@implementation IKCEFPage (DevTools)
- (void)devToolsMethod:(NSString *)method parameters:(NSDictionary *)parameters
           completion:(void (^)(NSDictionary *, NSError *))completion {
  [self devToolsMethod:method parameters:parameters survivingNavigation:NO completion:completion];
}
- (void)devToolsMethod:(NSString *)method parameters:(NSDictionary *)parameters survivingNavigation:(BOOL)survives
            completion:(void (^)(NSDictionary *, NSError *))completion {
  NSParameterAssert(NSThread.isMainThread);
  if (!self.ready) { completion(nil, IKCEFError(@"The CEF page is not ready.")); return; }
  NSError *error;
  NSData *json = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:&error];
  if (!json) { completion(nil, error); return; }
  auto value = CefParseJSON(std::string((const char *)json.bytes, json.length), JSON_PARSER_RFC);
  if (!value || value->GetType() != VTYPE_DICTIONARY) {
    completion(nil, IKCEFError(@"Invalid DevTools parameters.")); return;
  }
  if (_nextMessage == INT_MAX) {
    completion(nil, IKCEFError(@"DevTools request identifier limit reached.")); return;
  }
  int identifier = ++_nextMessage;
  _pending[@(identifier)] = [completion copy];
  if (survives) { if (!_survivors) _survivors = [NSMutableSet set]; [_survivors addObject:@(identifier)]; }
  int sent = _browser->GetHost()->ExecuteDevToolsMethod(identifier, method.UTF8String, value->GetDictionary());
  if (!sent) {
    [_pending removeObjectForKey:@(identifier)];
    [_survivors removeObject:@(identifier)];
    completion(nil, IKCEFError(@"CEF rejected the DevTools request."));
    return;
  }
  __weak IKCEFPage *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    IKCEFPage *page = weakSelf;
    if (!page) return;
    void (^pending)(NSDictionary *, NSError *) = page->_pending[@(identifier)];
    if (!pending) return;
    [page->_pending removeObjectForKey:@(identifier)];
    [page->_survivors removeObject:@(identifier)];
    pending(nil, IKCEFError(@"The page operation timed out."));
  });
}
- (void)methodResult:(int)identifier success:(BOOL)success data:(NSData *)data {
  void (^completion)(NSDictionary *, NSError *) = _pending[@(identifier)];
  if (!completion) return;
  [_pending removeObjectForKey:@(identifier)];
  [_survivors removeObject:@(identifier)];
  id result = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : @{};
  if (!success || ![result isKindOfClass:NSDictionary.class]) {
    NSString *message = [result isKindOfClass:NSDictionary.class] && [result[@"message"] isKindOfClass:NSString.class] ? result[@"message"] : nil;
    completion(nil, IKCEFError(message ?: @"The page could not complete the DevTools operation."));
  } else { completion(result, nil); }
}
- (void)invalidateRequests:(NSString *)reason {
  NSArray *media = [_mediaRequests copy];
  [_mediaRequests removeAllObjects];
  for (IKCEFMediaRequest *request in media) [request cancel];
  NSMutableArray *callbacks = [NSMutableArray array];
  for (NSNumber *identifier in _pending.allKeys) {
    if ([_survivors containsObject:identifier]) continue;
    [callbacks addObject:_pending[identifier]];
    [_pending removeObjectForKey:identifier];
  }
  for (void (^callback)(NSDictionary *, NSError *) in callbacks) callback(nil, IKCEFError(reason));
}
@end
