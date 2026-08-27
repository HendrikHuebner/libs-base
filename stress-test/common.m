#import "common.h"

#include <arpa/inet.h>

NSString *const GSWSProtocolErrorDomain = @"GSWSProtocolErrorDomain";

static uint64_t
GSWSByteSwap64(uint64_t value)
{
  return __builtin_bswap64(value);
}

static uint64_t
GSWSHostToBig64(uint64_t value)
{
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
  return GSWSByteSwap64(value);
#else
  return value;
#endif
}

static uint64_t
GSWSBigToHost64(uint64_t value)
{
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
  return GSWSByteSwap64(value);
#else
  return value;
#endif
}

uint64_t
GSWSNowMilliseconds(void)
{
  struct timeval tv;

  gettimeofday(&tv, NULL);
  return (uint64_t)tv.tv_sec * 1000ULL + (uint64_t)(tv.tv_usec / 1000);
}

uint64_t
GSWSSplitMix64Next(uint64_t *state)
{
  uint64_t z;

  *state += 0x9e3779b97f4a7c15ULL;
  z = *state;
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
  z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
  return z ^ (z >> 31);
}

uint64_t
GSWSFNV1a64(const void *bytes, size_t length)
{
  const uint8_t *cursor;
  uint64_t hash;
  size_t idx;

  cursor = bytes;
  hash = 1469598103934665603ULL;
  for (idx = 0; idx < length; idx++)
    {
      hash ^= (uint64_t)cursor[idx];
      hash *= 1099511628211ULL;
    }
  return hash;
}

NSData *
GSWSGeneratePayload(uint64_t connHi, uint64_t connLo, uint64_t epoch,
                    uint64_t seq, uint64_t seed, uint32_t length)
{
  NSMutableData *data;
  uint8_t *bytes;
  uint64_t state;
  uint64_t word;
  uint32_t offset;
  uint32_t idx;

  data = [NSMutableData dataWithLength: length];
  bytes = (uint8_t *)[data mutableBytes];
  state = seed ^ connHi ^ (connLo << 1) ^ (epoch * 0x517cc1b727220a95ULL)
    ^ (seq * 0x6eed0e9da4d94a4fULL) ^ (uint64_t)length;
  offset = 0;
  while (offset < length)
    {
      word = GSWSSplitMix64Next(&state);
      for (idx = 0; idx < 8 && offset < length; idx++, offset++)
        {
          bytes[offset] = (uint8_t)((word >> (idx * 8)) & 0xff);
        }
    }

  return data;
}

uint64_t
GSWSHashPayload(NSData *payload)
{
  return GSWSFNV1a64([payload bytes], [payload length]);
}

NSData *
GSWSEncodeHeader(const GSWSHeaderV1 *header)
{
  GSWSHeaderV1 networkHeader;

  networkHeader.magic = htonl(header->magic);
  networkHeader.version = htons(header->version);
  networkHeader.type = htons(header->type);
  networkHeader.conn_hi = GSWSHostToBig64(header->conn_hi);
  networkHeader.conn_lo = GSWSHostToBig64(header->conn_lo);
  networkHeader.epoch = GSWSHostToBig64(header->epoch);
  networkHeader.seq = GSWSHostToBig64(header->seq);
  networkHeader.reply_to = GSWSHostToBig64(header->reply_to);
  networkHeader.worker_id = htonl(header->worker_id);
  networkHeader.slot_id = htonl(header->slot_id);
  networkHeader.payload_len = htonl(header->payload_len);
  networkHeader.payload_kind = htonl(header->payload_kind);
  networkHeader.payload_seed = GSWSHostToBig64(header->payload_seed);
  networkHeader.payload_hash = GSWSHostToBig64(header->payload_hash);

  return [NSData dataWithBytes: &networkHeader length: sizeof(networkHeader)];
}

BOOL
GSWSDecodeHeader(NSData *messageData, GSWSHeaderV1 *headerOut,
                 NSData **payloadOut, NSString **errorOut)
{
  const GSWSHeaderV1 *networkHeader;
  GSWSHeaderV1 header;
  uint32_t payloadLength;

  if ([messageData length] < GSWS_HEADER_SIZE)
    {
      if (errorOut != NULL)
        {
          *errorOut = @"message shorter than fixed header";
        }
      return NO;
    }

  networkHeader = (const GSWSHeaderV1 *)[messageData bytes];
  header.magic = ntohl(networkHeader->magic);
  header.version = ntohs(networkHeader->version);
  header.type = ntohs(networkHeader->type);
  header.conn_hi = GSWSBigToHost64(networkHeader->conn_hi);
  header.conn_lo = GSWSBigToHost64(networkHeader->conn_lo);
  header.epoch = GSWSBigToHost64(networkHeader->epoch);
  header.seq = GSWSBigToHost64(networkHeader->seq);
  header.reply_to = GSWSBigToHost64(networkHeader->reply_to);
  header.worker_id = ntohl(networkHeader->worker_id);
  header.slot_id = ntohl(networkHeader->slot_id);
  header.payload_len = ntohl(networkHeader->payload_len);
  header.payload_kind = ntohl(networkHeader->payload_kind);
  header.payload_seed = GSWSBigToHost64(networkHeader->payload_seed);
  header.payload_hash = GSWSBigToHost64(networkHeader->payload_hash);

  payloadLength = header.payload_len;
  if (payloadLength > GSWS_MAX_PAYLOAD_LEN)
    {
      if (errorOut != NULL)
        {
          *errorOut = [NSString stringWithFormat:
            @"payload_len %u exceeds maximum %u",
            payloadLength,
            GSWS_MAX_PAYLOAD_LEN];
        }
      return NO;
    }

  if ([messageData length] != GSWS_HEADER_SIZE + payloadLength)
    {
      if (errorOut != NULL)
        {
          *errorOut = [NSString stringWithFormat:
            @"message length %lu does not match header payload_len %u",
            (unsigned long)[messageData length],
            payloadLength];
        }
      return NO;
    }

  if (headerOut != NULL)
    {
      *headerOut = header;
    }
  if (payloadOut != NULL)
    {
      *payloadOut = [messageData subdataWithRange:
        NSMakeRange(GSWS_HEADER_SIZE, payloadLength)];
    }
  return YES;
}

NSData *
GSWSBuildMessageData(const GSWSHeaderV1 *header, NSData *payload)
{
  NSMutableData *data;

  data = [NSMutableData dataWithData: GSWSEncodeHeader(header)];
  [data appendData: payload];
  return data;
}

NSUUID *
GSWSUUIDFromConnectionWords(uint64_t hi, uint64_t lo)
{
  uuid_t bytes;
  int idx;

  for (idx = 0; idx < 8; idx++)
    {
      bytes[idx] = (uint8_t)((hi >> ((7 - idx) * 8)) & 0xff);
      bytes[idx + 8] = (uint8_t)((lo >> ((7 - idx) * 8)) & 0xff);
    }
  return [[NSUUID alloc] initWithUUIDBytes: bytes];
}

void
GSWSUUIDToConnectionWords(NSUUID *uuid, uint64_t *hiOut, uint64_t *loOut)
{
  uuid_t bytes;
  uint64_t hi;
  uint64_t lo;
  int idx;

  [uuid getUUIDBytes: bytes];
  hi = 0;
  lo = 0;
  for (idx = 0; idx < 8; idx++)
    {
      hi = (hi << 8) | bytes[idx];
      lo = (lo << 8) | bytes[idx + 8];
    }
  if (hiOut != NULL)
    {
      *hiOut = hi;
    }
  if (loOut != NULL)
    {
      *loOut = lo;
    }
}

NSString *
GSWSDescribeConnection(uint64_t hi, uint64_t lo, uint64_t epoch)
{
  NSUUID *uuid;

  uuid = GSWSUUIDFromConnectionWords(hi, lo);
  return [NSString stringWithFormat: @"%@/epoch=%llu",
                                    [uuid UUIDString],
                                    (unsigned long long)epoch];
}

NSString *
GSWSPreviewData(NSData *data, NSUInteger limit)
{
  NSUInteger length;
  NSMutableString *string;
  const uint8_t *bytes;
  NSUInteger idx;

  length = MIN(limit, [data length]);
  string = [NSMutableString string];
  bytes = [data bytes];
  for (idx = 0; idx < length; idx++)
    {
      [string appendFormat: @"%02x", bytes[idx]];
      if (idx + 1 < length)
        {
          [string appendString: @" "];
        }
    }
  if ([data length] > length)
    {
      [string appendString: @" ..."];
    }
  return string;
}

NSData *
GSWSCloseReasonData(uint64_t connHi, uint64_t connLo, uint64_t epoch,
                    uint64_t lastSeq)
{
  NSString *reason;

  reason = [NSString stringWithFormat: @"GSWS1 conn=%@ epoch=%llu last_seq=%llu",
                                     [[GSWSUUIDFromConnectionWords(connHi, connLo)
                                       UUIDString] lowercaseString],
                                     (unsigned long long)epoch,
                                     (unsigned long long)lastSeq];
  return [reason dataUsingEncoding: NSUTF8StringEncoding];
}

uint32_t
GSWSRandomUInt32Uniform(uint32_t upperBoundExclusive)
{
  if (upperBoundExclusive == 0)
    {
      return 0;
    }
  return arc4random_uniform(upperBoundExclusive);
}

uint32_t
GSWSRandomPayloadLength(NSUInteger biasPercentSmall)
{
  uint32_t branch;

  branch = arc4random_uniform(100);
  if (branch < biasPercentSmall)
    {
      static const uint32_t interestingSizes[] = {
        0u, 1u, 125u, 126u, 127u, 1024u, 16384u, 65536u, 131072u
      };

      return interestingSizes[
        arc4random_uniform((uint32_t)(sizeof(interestingSizes)
          / sizeof(interestingSizes[0])))];
    }
  return arc4random_uniform(GSWS_MAX_PAYLOAD_LEN + 1u);
}
