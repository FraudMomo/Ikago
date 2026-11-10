#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NS_SWIFT_UI_ACTOR
@interface IKCEFSecurity : NSObject
+ (void)configure:(NSDictionary *)policy;
+ (NSDictionary *)snapshotForProfile:(NSString *)profile;
+ (void)setChangeHandler:(nullable void (^)(NSString *profile))handler;
+ (BOOL)setPreference:(NSString *)name value:(id)value profile:(NSString *)profile error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
