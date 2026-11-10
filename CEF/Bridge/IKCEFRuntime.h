#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
NS_SWIFT_UI_ACTOR
@protocol IKCEFApplicationDelegate <NSApplicationDelegate>
- (void)cefApplicationRequestsQuit NS_SWIFT_UI_ACTOR;
@end
/// Create before NSApplication.shared; must remain the application's class.
@interface IKCEFApplication : NSApplication
@property(nonatomic, weak, nullable) NSResponder *browserCommandTarget;
@property(nonatomic, copy, nullable) BOOL (^browserCommandWindowMatcher)(NSWindow *);
@end
NS_SWIFT_UI_ACTOR
@interface IKCEFRuntime : NSObject
/// Call once from main, then wait for completion before preparing any contexts.
/// helper is the bundled helper executable. Never points at a system browser.
+ (BOOL)startWithArgc:(int)argc argv:(char * _Nullable * _Nonnull)argv
                root:(NSURL *)root helper:(NSURL *)helper
               ready:(void (^)(void))ready error:(NSError **)error;
/// Requires every page to have completed OnBeforeClose, not just requested close.
+ (BOOL)shutdownWithError:(NSError **)error;
+ (void)runMessageLoop;
+ (void)quitMessageLoop;
@property(class, nonatomic, readonly) BOOL ready;
@property(class, nonatomic, readonly) BOOL canShutdown;
@end
NS_ASSUME_NONNULL_END
