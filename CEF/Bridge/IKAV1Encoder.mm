#import "IKAV1Encoder.h"
#include <EbSvtAv1Enc.h>
#include <EbSvtAv1ErrorCodes.h>
#include <cstring>

@implementation IKAV1Packet
- (instancetype)initWithData:(NSData *)data pts:(int64_t)pts key:(BOOL)key {
  if ((self = [super init])) { _data = data; _pts = pts; _keyFrame = key; }
  return self;
}
@end

@implementation IKAV1Encoder {
  EbComponentType *_handle;
  int _width, _height;
  BOOL _sentAny, _finished;
  NSMutableArray<IKAV1Packet *> *_packets;
}

static NSError *Failure(NSString *what, EbErrorType code) {
  return [NSError errorWithDomain:@"IKAV1Encoder" code:code
                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"AV1 encoder: %@ (%d)", what, code]}];
}

- (nullable instancetype)initWithWidth:(int)width height:(int)height timescale:(int)timescale
                          frameDuration:(int)frameDuration lowPower:(BOOL)lowPower error:(NSError **)error {
  if (!(self = [super init])) return nil;
  if (width < 16 || height < 16 || width > 4096 || height > 2304 || (width | height) & 1 || timescale <= 0 || frameDuration <= 0) {
    if (error) *error = Failure(@"unsupported frame size or rate", EB_ErrorBadParameter);
    return nil;
  }
  _width = width; _height = height;
  _packets = [NSMutableArray array];
  EbSvtAv1EncConfiguration config;
  memset(&config, 0, sizeof(config));
  EbErrorType status = svt_av1_enc_init_handle(&_handle, &config);
  if (status != EB_ErrorNone) { if (error) *error = Failure(@"init handle", status); _handle = nullptr; return nil; }
  // Measured on 720p X video against preset 11 / qp 30: about half the CPU, SSIM 0.981 instead of 0.986 (X's
  // own H.264 is the reference), and a quarter smaller, which also eases Chromium's decoding.
  config.enc_mode = 12;                        // fast real-time preset
  config.source_width = width;
  config.source_height = height;
  config.encoder_bit_depth = 8;
  config.frame_rate_numerator = timescale;
  config.frame_rate_denominator = frameDuration;
  config.pred_structure = LOW_DELAY;           // one packet out per frame in, no reordering
  config.rate_control_mode = SVT_AV1_RC_MODE_CQP_OR_CRF;
  config.qp = 35;                              // close to transparent at the bitrates X serves
  config.look_ahead_distance = 0;
  config.intra_period_length = -1;
  config.rtc = true;                          // real-time tuning for the fast presets
  config.enable_tf = 0;
  config.level_of_parallelism = lowPower ? 1 : 0;  // 1: fewest threads, least overhead; 0: every core
  status = svt_av1_enc_set_parameter(_handle, &config);
  if (status == EB_ErrorNone) status = svt_av1_enc_init(_handle);
  if (status != EB_ErrorNone) {
    if (error) *error = Failure(@"configure", status);
    svt_av1_enc_deinit_handle(_handle); _handle = nullptr;
    return nil;
  }
  EbBufferHeaderType *header = nullptr;
  status = svt_av1_enc_stream_header(_handle, &header);
  if (status != EB_ErrorNone || !header) {
    if (error) *error = Failure(@"sequence header", status);
    svt_av1_enc_deinit(_handle); svt_av1_enc_deinit_handle(_handle); _handle = nullptr;
    return nil;
  }
  _sequenceHeader = [NSData dataWithBytes:header->p_buffer length:header->n_filled_len];
  svt_av1_enc_stream_header_release(header);
  return self;
}

- (BOOL)sendLuma:(const uint8_t *)luma cb:(const uint8_t *)cb cr:(const uint8_t *)cr
      lumaStride:(int)lumaStride chromaStride:(int)chromaStride pts:(int64_t)pts {
  if (!_handle || _finished) return NO;
  EbSvtIOFormat planes;
  memset(&planes, 0, sizeof(planes));
  planes.luma = const_cast<uint8_t *>(luma);
  planes.cb = const_cast<uint8_t *>(cb);
  planes.cr = const_cast<uint8_t *>(cr);
  planes.y_stride = lumaStride;
  planes.cb_stride = chromaStride;
  planes.cr_stride = chromaStride;
  EbBufferHeaderType input;
  memset(&input, 0, sizeof(input));
  input.size = sizeof(input);
  input.p_buffer = reinterpret_cast<uint8_t *>(&planes);
  input.n_filled_len = lumaStride * _height + chromaStride * (_height / 2) * 2;
  input.pts = pts;
  input.pic_type = _sentAny ? EB_AV1_INVALID_PICTURE : EB_AV1_KEY_PICTURE;
  _sentAny = YES;
  if (svt_av1_enc_send_picture(_handle, &input) != EB_ErrorNone) return NO;
  // Low delay gives exactly one packet per frame, and get_packet always waits in that mode: take it now,
  // so the encoder's queues never fill while frames keep coming.
  return [self collectOne] != nil;
}

/// Takes the next packet (waiting for it). Returns @YES at the end of the stream, @NO for a frame, nil on error.
- (NSNumber *)collectOne {
  EbBufferHeaderType *output = nullptr;
  if (svt_av1_enc_get_packet(_handle, &output, _finished ? 1 : 0) != EB_ErrorNone || !output) return nil;
  const BOOL last = (output->flags & EB_BUFFERFLAG_EOS) != 0;
  if (output->n_filled_len > 0) {
    const BOOL key = output->pic_type == EB_AV1_KEY_PICTURE || output->pic_type == EB_AV1_INTRA_ONLY_PICTURE;
    [_packets addObject:[[IKAV1Packet alloc] initWithData:[NSData dataWithBytes:output->p_buffer length:output->n_filled_len]
                                                      pts:output->pts key:key]];
  }
  svt_av1_enc_release_out_buffer(&output);
  return @(last);
}

- (NSArray<IKAV1Packet *> *)finish {
  if (!_handle || _finished) return [_packets copy];
  _finished = YES;
  EbBufferHeaderType end;
  memset(&end, 0, sizeof(end));
  end.size = sizeof(end);
  end.flags = EB_BUFFERFLAG_EOS;
  svt_av1_enc_send_picture(_handle, &end);
  // Drain until the encoder confirms the end of the stream, even when no frame was sent.
  for (int guard = 0; guard < 1000; guard++) {
    NSNumber *last = [self collectOne];
    if (!last || last.boolValue) break;
  }
  return [_packets copy];
}

- (void)dealloc {
  // SVT-AV1 only shuts down cleanly after the end of the stream has been signalled and drained.
  if (_handle && !_finished) (void)[self finish];
  if (_handle) { svt_av1_enc_deinit(_handle); svt_av1_enc_deinit_handle(_handle); }
}
@end
