#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
@class IKCEFPage;
/// Chromium services that need a Chrome-style browser. Every browser here stays hidden; Ikago draws its own UI.
NS_SWIFT_UI_ACTOR
@interface IKCEFNativeTools : NSObject
+ (nullable NSNumber *)openExtensionsForProfile:(NSString *)profile error:(NSError **)error;
+ (nullable NSNumber *)openSecurityForProfile:(NSString *)profile error:(NSError **)error;
+ (nullable NSNumber *)openPage:(NSURL *)url profile:(NSString *)profile error:(NSError **)error;
+ (nullable NSNumber *)openExtensionResource:(NSString *)identifier path:(NSString *)path profile:(NSString *)profile error:(NSError **)error;
/// Pages Chromium tries to open by itself, such as an extension's tabs.create.
+ (void)setForeignPageHandler:(nullable void (^)(NSURL *))handler;
/// The folder the extension manager's next Load Unpacked request should receive.
+ (void)setNextFolderSelection:(nullable NSString *)path;
+ (void)closeBrowser:(NSInteger)identifier;
+ (nullable NSWindow *)windowForBrowser:(NSInteger)identifier;
+ (NSArray<NSDictionary *> *)windows;
+ (void)closeAll;
/// Drives a hidden browser through the DevTools protocol.
+ (nullable IKCEFPage *)hiddenPageForWindow:(NSInteger)identifier;
@end
NS_ASSUME_NONNULL_END
