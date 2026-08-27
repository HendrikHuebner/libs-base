#import <Foundation/Foundation.h>

#include <stdint.h>
#include <sys/time.h>

#define GSWS_MAGIC 0x47535731u
#define GSWS_VERSION 1u
#define GSWS_MAX_PAYLOAD_LEN (128u * 1024u)
#define GSWS_HEADER_SIZE 80u
#define GSWS_PAYLOAD_KIND_SYNTHETIC_V1 1u
#define GSWS_RESPONSE_SEED_XOR 0x9e3779b97f4a7c15ULL

typedef NS_ENUM(uint16_t, GSWSMessageType) {
  GSWSMessageTypeRequest = 1,
  GSWSMessageTypeResponse = 2,
};

typedef struct __attribute__((packed)) {
  uint32_t magic;
  uint16_t version;
  uint16_t type;
  uint64_t conn_hi;
  uint64_t conn_lo;
  uint64_t epoch;
  uint64_t seq;
  uint64_t reply_to;
  uint32_t worker_id;
  uint32_t slot_id;
  uint32_t payload_len;
  uint32_t payload_kind;
  uint64_t payload_seed;
  uint64_t payload_hash;
} GSWSHeaderV1;

FOUNDATION_EXPORT NSString *const GSWSProtocolErrorDomain;

FOUNDATION_EXPORT uint64_t GSWSNowMilliseconds(void);
FOUNDATION_EXPORT uint64_t GSWSSplitMix64Next(uint64_t *state);
FOUNDATION_EXPORT uint64_t GSWSFNV1a64(const void *bytes, size_t length);

FOUNDATION_EXPORT NSData *GSWSGeneratePayload(uint64_t connHi,
                                              uint64_t connLo,
                                              uint64_t epoch,
                                              uint64_t seq,
                                              uint64_t seed,
                                              uint32_t length);

FOUNDATION_EXPORT uint64_t GSWSHashPayload(NSData *payload);
FOUNDATION_EXPORT NSData *GSWSEncodeHeader(const GSWSHeaderV1 *header);
FOUNDATION_EXPORT BOOL GSWSDecodeHeader(NSData *messageData,
                                        GSWSHeaderV1 *headerOut,
                                        NSData **payloadOut,
                                        NSString **errorOut);

FOUNDATION_EXPORT NSData *GSWSBuildMessageData(const GSWSHeaderV1 *header,
                                               NSData *payload);
FOUNDATION_EXPORT NSUUID *GSWSUUIDFromConnectionWords(uint64_t hi, uint64_t lo);
FOUNDATION_EXPORT void GSWSUUIDToConnectionWords(NSUUID *uuid,
                                                 uint64_t *hiOut,
                                                 uint64_t *loOut);
FOUNDATION_EXPORT NSString *GSWSDescribeConnection(uint64_t hi, uint64_t lo,
                                                   uint64_t epoch);
FOUNDATION_EXPORT NSString *GSWSPreviewData(NSData *data, NSUInteger limit);
FOUNDATION_EXPORT NSData *GSWSCloseReasonData(uint64_t connHi,
                                              uint64_t connLo,
                                              uint64_t epoch,
                                              uint64_t lastSeq);
FOUNDATION_EXPORT uint32_t GSWSRandomPayloadLength(NSUInteger biasPercentSmall);
FOUNDATION_EXPORT uint32_t GSWSRandomUInt32Uniform(uint32_t upperBoundExclusive);
