#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NS_SWIFT_UI_ACTOR
@interface IKCEFDownloads : NSObject
@property(class, nonatomic, readonly) IKCEFDownloads *shared;
@property(nonatomic, copy, nullable) NSString * _Nullable (^destinationHandler)(NSString *identifier, NSString *name, NSString *url, BOOL ephemeral);
@property(nonatomic, copy, nullable) void (^eventHandler)(NSDictionary *snapshot, void (^cancel)(void));
@end
NS_ASSUME_NONNULL_END
