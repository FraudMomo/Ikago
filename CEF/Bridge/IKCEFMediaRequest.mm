#import "IKCEFPageInternal.h"

@implementation IKCEFMediaRequest {
  CefRefPtr<CefMediaAccessCallback> _callback;
  uint32_t _permissions;
}
- (instancetype)initWithOrigin:(NSString *)origin permissions:(uint32_t)permissions
                     callback:(CefRefPtr<CefMediaAccessCallback>)callback {
  if ((self = [super init])) { _origin = [origin copy]; _permissions = permissions; _callback = callback; }
  return self;
}
- (BOOL)camera { return (_permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) != 0; }
- (BOOL)microphone { return (_permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) != 0; }
- (BOOL)resolved { return !_callback; }
- (void)resolve:(BOOL)allow {
  NSParameterAssert(NSThread.isMainThread);
  auto callback = _callback;
  _callback = nullptr;
  self.cancellationHandler = nil;
  if (!callback) return;
  if (allow) callback->Continue(_permissions); else callback->Cancel();
}
- (void)cancel {
  auto handler = self.cancellationHandler;
  [self resolve:NO];
  if (handler) handler();
}
- (void)dealloc { if (_callback) _callback->Cancel(); }
@end

@implementation IKCEFPermissionPrompt {
  CefRefPtr<CefPermissionPromptCallback> _callback;
  uint64_t _promptID;
}
- (uint64_t)promptID { return _promptID; }
- (instancetype)initWithOrigin:(NSString *)origin promptID:(uint64_t)promptID permissions:(uint32_t)permissions
                      callback:(CefRefPtr<CefPermissionPromptCallback>)callback {
  if ((self = [super init])) { _origin = [origin copy]; _promptID = promptID; _permissions = permissions; _callback = callback; }
  return self;
}
- (BOOL)resolved { return !_callback; }
- (void)resolve:(BOOL)allow {
  NSParameterAssert(NSThread.isMainThread);
  auto callback = _callback;
  _callback = nullptr;
  self.cancellationHandler = nil;
  if (callback) callback->Continue(allow ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DENY);
}
- (void)cancel {
  auto handler = self.cancellationHandler;
  [self resolve:NO];
  if (handler) handler();
}
- (void)abandon {
  _callback = nullptr;
  auto handler = self.cancellationHandler;
  self.cancellationHandler = nil;
  if (handler) handler();
}
- (void)dealloc { if (_callback) _callback->Continue(CEF_PERMISSION_RESULT_DENY); }
@end
