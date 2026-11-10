#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One encoded AV1 temporal unit.
@interface IKAV1Packet : NSObject
@property(nonatomic, readonly) NSData *data;
@property(nonatomic, readonly) int64_t pts;
@property(nonatomic, readonly) BOOL keyFrame;
@end

/// A small, real-time AV1 encoder (SVT-AV1, BSD + AOM royalty-free patent licence) for the Chromium media
/// translation layer: H.264 frames decoded by macOS become AV1 that Chromium plays itself. One instance
/// encodes one independent run of frames that starts with a key frame, then is finished and discarded.
@interface IKAV1Encoder : NSObject
/// `lowPower`: as few threads as possible (the least work in total, for segments that aren't needed yet); otherwise
/// every core, for the lowest delay. Both produce the same stream.
- (nullable instancetype)initWithWidth:(int)width height:(int)height timescale:(int)timescale
                          frameDuration:(int)frameDuration lowPower:(BOOL)lowPower error:(NSError **)error;
/// The AV1 sequence header OBU, for the MP4 'av1C' box. The same for every encoder with equal settings.
@property(nonatomic, readonly) NSData *sequenceHeader;
/// Sends one 8-bit 4:2:0 planar frame. The first frame becomes a key frame.
- (BOOL)sendLuma:(const uint8_t *)luma cb:(const uint8_t *)cb cr:(const uint8_t *)cr
      lumaStride:(int)lumaStride chromaStride:(int)chromaStride pts:(int64_t)pts;
/// Ends the run and returns every packet, in order.
- (NSArray<IKAV1Packet *> *)finish;
@end

NS_ASSUME_NONNULL_END
