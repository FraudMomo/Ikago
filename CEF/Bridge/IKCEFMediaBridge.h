#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

/// The media translation layer's door into Ikago. A page on one of `hosts` sends a media segment as base64url parts in
/// GET requests to `/__ikago_media__?stream=&seq=&part=&parts=&data=` on its own origin (service workers don't pass
/// request bodies on); Ikago answers them itself (no network, no cookies) and returns the translated segment for the last.
/// `urgent=1` means the player is waiting for it (translated at once on every core); otherwise it runs at background
/// priority, which keeps it on the efficiency cores. `fit` is the video's shorter on-screen side in device pixels (0 if
/// unknown). The translator is called off the main thread; `done` may be called anywhere.
@interface IKCEFMediaBridge : NSObject
+ (void)setHosts:(NSArray<NSString *> *)hosts
      translator:(nullable void (^)(NSString *stream, NSData *body, BOOL urgent, int fit,
                                    void (^done)(NSData *_Nullable result)))translator;
@end

NS_ASSUME_NONNULL_END
