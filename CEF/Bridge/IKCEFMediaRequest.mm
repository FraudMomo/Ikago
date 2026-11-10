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
