#import <Foundation/Foundation.h>

#import "common.h"

#if __has_include(<CommonCrypto/CommonDigest.h>)
#import <CommonCrypto/CommonDigest.h>
#define GSWS_SHA1_DIGEST_LENGTH CC_SHA1_DIGEST_LENGTH
static void
GSWSSHA1Bytes(const void *bytes, size_t length, uint8_t digest[GSWS_SHA1_DIGEST_LENGTH])
{
  CC_SHA1(bytes, (CC_LONG)length, digest);
}
#elif __has_include(<openssl/sha.h>)
#include <openssl/sha.h>
#define GSWS_SHA1_DIGEST_LENGTH SHA_DIGEST_LENGTH
static void
GSWSSHA1Bytes(const void *bytes, size_t length, uint8_t digest[GSWS_SHA1_DIGEST_LENGTH])
{
  SHA1(bytes, length, digest);
}
#else
#error "A SHA1 implementation is required for the websocket handshake"
#endif

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

typedef NS_ENUM(uint8_t, GSWSOpcode) {
  GSWSOpcodeContinuation = 0x0,
  GSWSOpcodeText = 0x1,
  GSWSOpcodeBinary = 0x2,
  GSWSOpcodeClose = 0x8,
  GSWSOpcodePing = 0x9,
  GSWSOpcodePong = 0xA,
};

typedef struct {
  int clientFD;
  uint32_t maxDelayMs;
  uint32_t fragmentChancePercent;
} GSWSConnectionThreadArgs;

typedef struct {
  pthread_mutex_t mutex;
  uint64_t acceptedConnections;
  uint64_t validatedRequests;
  uint64_t sentResponses;
  uint64_t fragmentedResponses;
  uint64_t largeResponses;
  uint64_t pingFrames;
  uint64_t closeFrames;
  uint64_t protocolFailures;
} GSWSServerStats;

static volatile sig_atomic_t GSWSServerStopRequested = 0;
static NSString *const GSWSWebSocketGUID =
  @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

static void
GSWSServerHandleSignal(int signo)
{
  (void)signo;
  GSWSServerStopRequested = 1;
}

static void
Fail(NSString *message)
{
  fprintf(stderr, "%s\n", [message UTF8String]);
  exit(1);
}

static BOOL
ReadExact(int fd, void *buffer, size_t length)
{
  uint8_t *bytes;
  size_t offset;

  bytes = buffer;
  offset = 0;
  while (offset < length)
    {
      ssize_t count;

      count = read(fd, bytes + offset, length - offset);
      if (count <= 0)
        {
          return NO;
        }
      offset += (size_t)count;
    }
  return YES;
}

static BOOL
WriteAll(int fd, const void *buffer, size_t length)
{
  const uint8_t *bytes;
  size_t offset;

  bytes = buffer;
  offset = 0;
  while (offset < length)
    {
      ssize_t count;

      count = write(fd, bytes + offset, length - offset);
      if (count <= 0)
        {
          return NO;
        }
      offset += (size_t)count;
    }
  return YES;
}

static NSData *
ReadHTTPRequest(int fd)
{
  NSMutableData *data;
  uint8_t byte;

  data = [NSMutableData data];
  while (YES)
    {
      if (!ReadExact(fd, &byte, 1))
        {
          return nil;
        }
      [data appendBytes: &byte length: 1];
      if ([data length] >= 4)
        {
          const uint8_t *bytes;
          NSUInteger len;

          bytes = [data bytes];
          len = [data length];
          if (bytes[len - 4] == '\r' && bytes[len - 3] == '\n'
              && bytes[len - 2] == '\r' && bytes[len - 1] == '\n')
            {
              return data;
            }
        }
    }
}

static NSString *
HeaderValue(NSString *request, NSString *headerName)
{
  NSString *needle;
  NSArray<NSString *> *lines;

  needle = [headerName stringByAppendingString: @":"];
  lines = [request componentsSeparatedByString: @"\r\n"];
  for (NSString *line in lines)
    {
      if ([line length] > [needle length]
          && [[line substringToIndex: [needle length]]
                caseInsensitiveCompare: needle] == NSOrderedSame)
        {
          return [[line substringFromIndex: [needle length]]
            stringByTrimmingCharactersInSet:
              [NSCharacterSet whitespaceCharacterSet]];
        }
    }
  return nil;
}

static NSString *
WebSocketAcceptForKey(NSString *key)
{
  NSString *combined;
  NSData *input;
  uint8_t digest[GSWS_SHA1_DIGEST_LENGTH];
  NSData *digestData;

  combined = [key stringByAppendingString: GSWSWebSocketGUID];
  input = [combined dataUsingEncoding: NSUTF8StringEncoding];
  GSWSSHA1Bytes([input bytes], [input length], digest);
  digestData = [NSData dataWithBytes: digest length: sizeof(digest)];
  return [digestData base64EncodedStringWithOptions: 0];
}

static BOOL
SendFrame(int fd, GSWSOpcode opcode, BOOL final, const uint8_t *payload,
          uint64_t payloadLength)
{
  uint8_t header[10];
  size_t headerLength;

  headerLength = 0;
  header[headerLength++] = (final ? 0x80 : 0x00) | (opcode & 0x0f);
  if (payloadLength <= 125)
    {
      header[headerLength++] = (uint8_t)payloadLength;
    }
  else if (payloadLength <= UINT16_MAX)
    {
      uint16_t shortLen;

      shortLen = htons((uint16_t)payloadLength);
      header[headerLength++] = 126;
      memcpy(header + headerLength, &shortLen, sizeof(shortLen));
      headerLength += sizeof(shortLen);
    }
  else
    {
      int idx;

      header[headerLength++] = 127;
      for (idx = 7; idx >= 0; idx--)
        {
          header[headerLength++] = (uint8_t)((payloadLength >> (idx * 8)) & 0xff);
        }
    }

  if (!WriteAll(fd, header, headerLength))
    {
      return NO;
    }
  if (payloadLength > 0
      && !WriteAll(fd, payload, (size_t)payloadLength))
    {
      return NO;
    }
  return YES;
}

static BOOL
ReadFrame(int fd, GSWSOpcode *opcodeOut, BOOL *finalOut, NSData **payloadOut)
{
  uint8_t firstTwo[2];
  uint8_t maskingKey[4];
  uint64_t payloadLength;
  NSMutableData *payload;
  uint8_t *bytes;
  BOOL masked;

  if (!ReadExact(fd, firstTwo, sizeof(firstTwo)))
    {
      return NO;
    }

  *finalOut = (firstTwo[0] & 0x80) != 0;
  *opcodeOut = (GSWSOpcode)(firstTwo[0] & 0x0f);
  masked = (firstTwo[1] & 0x80) != 0;
  payloadLength = (uint64_t)(firstTwo[1] & 0x7f);
  if (payloadLength == 126)
    {
      uint16_t shortLen;

      shortLen = 0;
      if (!ReadExact(fd, &shortLen, sizeof(shortLen)))
        {
          return NO;
        }
      payloadLength = ntohs(shortLen);
    }
  else if (payloadLength == 127)
    {
      uint8_t longLenBytes[8];
      NSUInteger idx;

      payloadLength = 0;
      if (!ReadExact(fd, longLenBytes, sizeof(longLenBytes)))
        {
          return NO;
        }
      for (idx = 0; idx < sizeof(longLenBytes); idx++)
        {
          payloadLength = (payloadLength << 8) | longLenBytes[idx];
        }
    }

  if (masked)
    {
      if (!ReadExact(fd, maskingKey, sizeof(maskingKey)))
        {
          return NO;
        }
    }

  payload = [NSMutableData dataWithLength: (NSUInteger)payloadLength];
  bytes = [payload mutableBytes];
  if (payloadLength > 0 && !ReadExact(fd, bytes, (size_t)payloadLength))
    {
      return NO;
    }
  if (masked)
    {
      uint64_t idx;

      for (idx = 0; idx < payloadLength; idx++)
        {
          bytes[idx] ^= maskingKey[idx % 4];
        }
    }
  *payloadOut = payload;
  return YES;
}

static BOOL
ReceiveMessage(int fd, GSWSOpcode *messageOpcodeOut, NSData **payloadOut,
               BOOL *sawCloseOut, uint64_t *pingCountOut)
{
  NSMutableData *assembled;
  BOOL hasMessageOpcode;
  GSWSOpcode messageOpcode;

  assembled = [NSMutableData data];
  hasMessageOpcode = NO;
  messageOpcode = GSWSOpcodeContinuation;
  while (YES)
    {
      GSWSOpcode frameOpcode;
      BOOL final;
      NSData *framePayload;

      framePayload = nil;
      if (!ReadFrame(fd, &frameOpcode, &final, &framePayload))
        {
          return NO;
        }
      if (frameOpcode == GSWSOpcodePing)
        {
          (*pingCountOut)++;
          if (!SendFrame(fd, GSWSOpcodePong, YES, [framePayload bytes],
                         [framePayload length]))
            {
              return NO;
            }
          continue;
        }
      if (frameOpcode == GSWSOpcodeClose)
        {
          *sawCloseOut = YES;
          *payloadOut = framePayload;
          return YES;
        }
      if (frameOpcode == GSWSOpcodeText || frameOpcode == GSWSOpcodeBinary)
        {
          if (hasMessageOpcode)
            {
              return NO;
            }
          hasMessageOpcode = YES;
          messageOpcode = frameOpcode;
        }
      else if (frameOpcode != GSWSOpcodeContinuation || !hasMessageOpcode)
        {
          return NO;
        }

      [assembled appendData: framePayload];
      if (final)
        {
          *messageOpcodeOut = messageOpcode;
          *payloadOut = assembled;
          *sawCloseOut = NO;
          return YES;
        }
    }
}

static void
MaybeDelay(uint32_t maxDelayMs)
{
  if (maxDelayMs == 0)
    {
      return;
    }
  if (arc4random_uniform(100) < 20)
    {
      uint32_t delayMs;

      delayMs = arc4random_uniform(maxDelayMs + 1);
      usleep(delayMs * 1000);
    }
}

static BOOL
SendMessagePossiblyFragmented(int fd, NSData *messageData,
                              uint32_t fragmentChancePercent,
                              uint32_t maxDelayMs,
                              BOOL *didFragmentOut)
{
  const uint8_t *bytes;
  uint32_t length;

  *didFragmentOut = NO;
  bytes = [messageData bytes];
  length = (uint32_t)[messageData length];

  if (length > GSWS_HEADER_SIZE + 1
      && arc4random_uniform(100) < fragmentChancePercent)
    {
      uint32_t chunkCount;
      uint32_t offset;
      uint32_t remaining;
      uint32_t frameIndex;

      chunkCount = 2 + arc4random_uniform(4);
      offset = 0;
      remaining = length;
      *didFragmentOut = YES;
      for (frameIndex = 0; frameIndex < chunkCount; frameIndex++)
        {
          uint32_t chunkLength;
          BOOL final;
          GSWSOpcode opcode;

          final = (frameIndex + 1 == chunkCount);
          if (final)
            {
              chunkLength = remaining;
            }
          else
            {
              uint32_t minRemainingAfter;
              uint32_t maxChunk;

              minRemainingAfter = chunkCount - frameIndex - 1;
              maxChunk = remaining - minRemainingAfter;
              chunkLength = 1 + arc4random_uniform(maxChunk);
            }

          opcode = (frameIndex == 0) ? GSWSOpcodeBinary : GSWSOpcodeContinuation;
          if (!SendFrame(fd, opcode, final, bytes + offset, chunkLength))
            {
              return NO;
            }
          offset += chunkLength;
          remaining -= chunkLength;
          MaybeDelay(maxDelayMs);
        }
      return YES;
    }

  return SendFrame(fd, GSWSOpcodeBinary, YES, bytes, length);
}

static GSWSServerStats ServerStats;

static void
StatsIncrement(uint64_t *field)
{
  pthread_mutex_lock(&ServerStats.mutex);
  (*field)++;
  pthread_mutex_unlock(&ServerStats.mutex);
}

static NSData *
ClosePayload(uint16_t closeCode, NSData *reason)
{
  uint16_t netCode;
  NSMutableData *payload;

  netCode = htons(closeCode);
  payload = [NSMutableData dataWithBytes: &netCode length: sizeof(netCode)];
  if (reason != nil)
    {
      [payload appendData: reason];
    }
  return payload;
}

static void *
HandleConnection(void *context)
{
  GSWSConnectionThreadArgs *args;
  int clientFD;
  NSData *requestData;
  NSString *requestString;
  NSString *clientKey;
  NSString *acceptValue;
  NSString *responseString;
  uint64_t expectedRequestSeq;
  uint64_t nextResponseSeq;
  uint64_t pingCount;
  BOOL sawClose;

  @autoreleasepool
    {
      args = context;
      clientFD = args->clientFD;
      expectedRequestSeq = 1;
      nextResponseSeq = 1;
      pingCount = 0;
      sawClose = NO;

      requestData = ReadHTTPRequest(clientFD);
      if (requestData == nil)
        {
          StatsIncrement(&ServerStats.protocolFailures);
          close(clientFD);
          free(args);
          return NULL;
        }

      requestString = [[NSString alloc] initWithData: requestData
                                            encoding: NSUTF8StringEncoding];
      clientKey = HeaderValue(requestString, @"Sec-WebSocket-Key");
      if (clientKey == nil)
        {
          StatsIncrement(&ServerStats.protocolFailures);
          close(clientFD);
          free(args);
          return NULL;
        }

      acceptValue = WebSocketAcceptForKey(clientKey);
      responseString =
        [NSString stringWithFormat:
          @"HTTP/1.1 101 Switching Protocols\r\n"
          @"Upgrade: websocket\r\n"
          @"Connection: Upgrade\r\n"
          @"Sec-WebSocket-Accept: %@\r\n"
          @"\r\n",
          acceptValue];
      if (!WriteAll(clientFD, [responseString UTF8String],
                    strlen([responseString UTF8String])))
        {
          close(clientFD);
          free(args);
          return NULL;
        }

      while (!GSWSServerStopRequested)
        {
          GSWSOpcode opcode;
          NSData *messageData;
          GSWSHeaderV1 requestHeader;
          NSData *requestPayload;
          NSString *decodeError;
          NSData *expectedPayload;
          GSWSHeaderV1 responseHeader;
          NSData *responsePayload;
          NSData *responseMessage;
          BOOL didFragment;

          messageData = nil;
          decodeError = nil;
          requestPayload = nil;
          if (!ReceiveMessage(clientFD, &opcode, &messageData, &sawClose, &pingCount))
            {
              break;
            }
          if (sawClose)
            {
              NSData *closeData;

              StatsIncrement(&ServerStats.closeFrames);
              closeData = ClosePayload(1000, nil);
              SendFrame(clientFD, GSWSOpcodeClose, YES, [closeData bytes],
                        [closeData length]);
              break;
            }
          if (opcode != GSWSOpcodeBinary)
            {
              StatsIncrement(&ServerStats.protocolFailures);
              break;
            }
          if (!GSWSDecodeHeader(messageData, &requestHeader, &requestPayload,
                                &decodeError))
            {
              NSLog(@"server decode failure %@", decodeError);
              StatsIncrement(&ServerStats.protocolFailures);
              break;
            }
          if (requestHeader.magic != GSWS_MAGIC
              || requestHeader.version != GSWS_VERSION
              || requestHeader.type != GSWSMessageTypeRequest
              || requestHeader.payload_kind != GSWS_PAYLOAD_KIND_SYNTHETIC_V1)
            {
              StatsIncrement(&ServerStats.protocolFailures);
              break;
            }
          if (requestHeader.seq != expectedRequestSeq)
            {
              NSLog(@"server ordering mismatch conn=%@ expected=%llu got=%llu",
                    GSWSDescribeConnection(requestHeader.conn_hi,
                                           requestHeader.conn_lo,
                                           requestHeader.epoch),
                    (unsigned long long)expectedRequestSeq,
                    (unsigned long long)requestHeader.seq);
              StatsIncrement(&ServerStats.protocolFailures);
              break;
            }

          expectedPayload = GSWSGeneratePayload(requestHeader.conn_hi,
                                                requestHeader.conn_lo,
                                                requestHeader.epoch,
                                                requestHeader.seq,
                                                requestHeader.payload_seed,
                                                requestHeader.payload_len);
          if (![expectedPayload isEqualToData: requestPayload]
              || GSWSHashPayload(requestPayload) != requestHeader.payload_hash)
            {
              NSLog(@"server payload mismatch seq=%llu len=%u",
                    (unsigned long long)requestHeader.seq,
                    requestHeader.payload_len);
              StatsIncrement(&ServerStats.protocolFailures);
              break;
            }
          StatsIncrement(&ServerStats.validatedRequests);
          if (requestHeader.payload_len >= 65536)
            {
              StatsIncrement(&ServerStats.largeResponses);
            }

          memset(&responseHeader, 0, sizeof(responseHeader));
          responseHeader.magic = GSWS_MAGIC;
          responseHeader.version = GSWS_VERSION;
          responseHeader.type = GSWSMessageTypeResponse;
          responseHeader.conn_hi = requestHeader.conn_hi;
          responseHeader.conn_lo = requestHeader.conn_lo;
          responseHeader.epoch = requestHeader.epoch;
          responseHeader.seq = nextResponseSeq++;
          responseHeader.reply_to = requestHeader.seq;
          responseHeader.worker_id = requestHeader.worker_id;
          responseHeader.slot_id = requestHeader.slot_id;
          responseHeader.payload_len = requestHeader.payload_len;
          responseHeader.payload_kind = GSWS_PAYLOAD_KIND_SYNTHETIC_V1;
          responseHeader.payload_seed = requestHeader.payload_seed
            ^ GSWS_RESPONSE_SEED_XOR;
          responsePayload = GSWSGeneratePayload(responseHeader.conn_hi,
                                                responseHeader.conn_lo,
                                                responseHeader.epoch,
                                                responseHeader.seq,
                                                responseHeader.payload_seed,
                                                responseHeader.payload_len);
          responseHeader.payload_hash = GSWSHashPayload(responsePayload);
          responseMessage = GSWSBuildMessageData(&responseHeader, responsePayload);

          MaybeDelay(args->maxDelayMs);
          if (!SendMessagePossiblyFragmented(clientFD, responseMessage,
                                            args->fragmentChancePercent,
                                            args->maxDelayMs, &didFragment))
            {
              break;
            }
          if (didFragment)
            {
              StatsIncrement(&ServerStats.fragmentedResponses);
            }
          StatsIncrement(&ServerStats.sentResponses);
          expectedRequestSeq += 1;
        }

      pthread_mutex_lock(&ServerStats.mutex);
      ServerStats.pingFrames += pingCount;
      pthread_mutex_unlock(&ServerStats.mutex);
      close(clientFD);
      free(args);
    }

  return NULL;
}

int
main(int argc, const char *argv[])
{
  int serverFD;
  int optionValue;
  uint16_t port;
  uint32_t maxDelayMs;
  uint32_t fragmentChancePercent;
  struct sockaddr_in address;
  struct sigaction action;

  port = 19090;
  maxDelayMs = 50;
  fragmentChancePercent = 30;
  if (argc > 1)
    {
      port = (uint16_t)strtoul(argv[1], NULL, 10);
    }
  if (argc > 2)
    {
      maxDelayMs = (uint32_t)strtoul(argv[2], NULL, 10);
    }
  if (argc > 3)
    {
      fragmentChancePercent = (uint32_t)strtoul(argv[3], NULL, 10);
    }

  memset(&ServerStats, 0, sizeof(ServerStats));
  pthread_mutex_init(&ServerStats.mutex, NULL);
  memset(&action, 0, sizeof(action));
  action.sa_handler = GSWSServerHandleSignal;
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);
  signal(SIGPIPE, SIG_IGN);

  serverFD = socket(AF_INET, SOCK_STREAM, 0);
  if (serverFD < 0)
    {
      Fail(@"Could not create server socket");
    }
  optionValue = 1;
  if (setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &optionValue,
                 sizeof(optionValue)) != 0)
    {
      Fail(@"Could not enable SO_REUSEADDR");
    }

  memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET;
  address.sin_port = htons(port);
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(serverFD, (struct sockaddr *)&address, sizeof(address)) != 0)
    {
      Fail([NSString stringWithFormat: @"Could not bind server socket errno=%d",
                                      errno]);
    }
  if (listen(serverFD, 16) != 0)
    {
      Fail(@"Could not listen on server socket");
    }

  NSLog(@"Server listening on ws://127.0.0.1:%hu/ws maxDelayMs=%u fragmentChance=%u",
        port,
        maxDelayMs,
        fragmentChancePercent);

  while (!GSWSServerStopRequested)
    {
      int clientFD;
      GSWSConnectionThreadArgs *args;
      pthread_t thread;

      clientFD = accept(serverFD, NULL, NULL);
      if (clientFD < 0)
        {
          if (errno == EINTR)
            {
              continue;
            }
          break;
        }

      StatsIncrement(&ServerStats.acceptedConnections);
      args = calloc(1, sizeof(*args));
      args->clientFD = clientFD;
      args->maxDelayMs = maxDelayMs;
      args->fragmentChancePercent = fragmentChancePercent;
      if (pthread_create(&thread, NULL, HandleConnection, args) != 0)
        {
          close(clientFD);
          free(args);
          continue;
        }
      pthread_detach(thread);
    }

  close(serverFD);
  pthread_mutex_lock(&ServerStats.mutex);
  NSLog(@"server-summary accepted=%llu validated=%llu sent=%llu fragmented=%llu "
        @"large=%llu pings=%llu closes=%llu protocol_failures=%llu",
        (unsigned long long)ServerStats.acceptedConnections,
        (unsigned long long)ServerStats.validatedRequests,
        (unsigned long long)ServerStats.sentResponses,
        (unsigned long long)ServerStats.fragmentedResponses,
        (unsigned long long)ServerStats.largeResponses,
        (unsigned long long)ServerStats.pingFrames,
        (unsigned long long)ServerStats.closeFrames,
        (unsigned long long)ServerStats.protocolFailures);
  pthread_mutex_unlock(&ServerStats.mutex);
  return ServerStats.protocolFailures == 0 ? 0 : 1;
}
