#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Chromium tabs' sound, played by Ikago itself.
///
/// CEF's audio handler hands Ikago each tab's PCM and mutes the tab's own output while it does (cef_audio_handler.h).
/// Ikago plays it through one AVAudioEngine, which needs no capture permission and shows no recording indicator, and
/// reads band levels from it for the media island's wave.
@interface IKCEFAudio : NSObject
/// Off by default. Read when a page starts playing sound: pages already playing keep their current route until they stop.
@property(class, atomic) BOOL enabled;
/// Five band levels, 0…1, of what a page is playing now; nil when it plays nothing.
+ (nullable NSArray<NSNumber *> *)levelsForBrowser:(int)browserID;
/// Added delay, measured: capture to arrival, waiting in the buffer, and the output's own latency (milliseconds).
+ (NSDictionary<NSString *, NSNumber *> *)latencyReport;
@end
NS_ASSUME_NONNULL_END
