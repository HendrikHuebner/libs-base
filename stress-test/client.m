#import <Foundation/Foundation.h>

#import "common.h"

#ifdef GNUSTEP
extern NSString *GSWebSocketTaskLockProfileSnapshot(void) __attribute__((weak_import));
#endif

typedef NS_ENUM(NSUInteger, GSWSSlotState) {
  GSWSSlotStateEmpty = 0,
  GSWSSlotStateConnecting = 1,
  GSWSSlotStateOpen = 2,
  GSWSSlotStateClosing = 3,
  GSWSSlotStateClosed = 4,
};

typedef NS_ENUM(NSUInteger, GSWSFailureBucket) {
  GSWSFailureBucketProtocolMismatch = 0,
  GSWSFailureBucketPayloadMismatch = 1,
  GSWSFailureBucketOrderingMismatch = 2,
  GSWSFailureBucketUnexpectedCallbackAfterReuse = 3,
  GSWSFailureBucketExpectedCloseCancellation = 4,
  GSWSFailureBucketTimeout = 5,
};

static NSString *
GSWSFailureBucketName(GSWSFailureBucket bucket)
{
  switch (bucket)
    {
      case GSWSFailureBucketProtocolMismatch:
        return @"PROTOCOL_MISMATCH";
      case GSWSFailureBucketPayloadMismatch:
        return @"PAYLOAD_MISMATCH";
      case GSWSFailureBucketOrderingMismatch:
        return @"ORDERING_MISMATCH";
      case GSWSFailureBucketUnexpectedCallbackAfterReuse:
        return @"UNEXPECTED_CALLBACK_AFTER_REUSE";
      case GSWSFailureBucketExpectedCloseCancellation:
        return @"EXPECTED_CLOSE_CANCELLATION";
      case GSWSFailureBucketTimeout:
        return @"TIMEOUT";
    }
}

@interface GSWSRequestLedgerEntry : NSObject
@property(nonatomic, assign) GSWSHeaderV1 requestHeader;
@property(nonatomic, assign) GSWSHeaderV1 expectedResponseHeader;
@property(nonatomic, strong) NSData *requestPayload;
@property(nonatomic, strong) NSData *expectedResponsePayload;
@property(nonatomic, strong) NSData *encodedMessageData;
@property(nonatomic, assign) BOOL sendCompleted;
@property(nonatomic, assign) BOOL receiveCompleted;
@property(nonatomic, assign) BOOL canceledByClose;
@property(nonatomic, assign) BOOL timeoutReported;
@property(nonatomic, assign) uint64_t createdAtMs;
@property(nonatomic, assign) uint64_t dispatchedAtMs;
@property(nonatomic, assign) uint64_t sentAtMs;
@property(nonatomic, assign) uint64_t receivedAtMs;
@end

@implementation GSWSRequestLedgerEntry
@end

@interface GSWSStats : NSObject
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, assign) uint64_t creates;
@property(nonatomic, assign) uint64_t opens;
@property(nonatomic, assign) uint64_t sends;
@property(nonatomic, assign) uint64_t sendCompletions;
@property(nonatomic, assign) uint64_t receives;
@property(nonatomic, assign) uint64_t receiveCompletions;
@property(nonatomic, assign) uint64_t pings;
@property(nonatomic, assign) uint64_t pongCompletions;
@property(nonatomic, assign) uint64_t closes;
@property(nonatomic, assign) uint64_t closeCallbacks;
@property(nonatomic, assign) uint64_t validatedLargeResponses;
@property(nonatomic, assign) uint64_t expectedCloseCancellations;
@property(nonatomic, assign) uint64_t completedRequestCount;
@property(nonatomic, assign) uint64_t totalQueueToSendMs;
@property(nonatomic, assign) uint64_t maxQueueToSendMs;
@property(nonatomic, assign) uint64_t totalQueueBeforeDispatchMs;
@property(nonatomic, assign) uint64_t maxQueueBeforeDispatchMs;
@property(nonatomic, assign) uint64_t totalDispatchToSendMs;
@property(nonatomic, assign) uint64_t maxDispatchToSendMs;
@property(nonatomic, assign) uint64_t totalRoundTripMs;
@property(nonatomic, assign) uint64_t maxRoundTripMs;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *failures;
@property(nonatomic, strong) NSMutableArray<NSString *> *failureDetails;
- (void)incrementKey:(NSString *)key;
- (void)recordFailure:(GSWSFailureBucket)bucket detail:(NSString *)detail
              countIt:(BOOL)countIt;
@end

@implementation GSWSStats

- (instancetype)init
{
  self = [super init];
  if (self != nil)
    {
      _lock = [[NSLock alloc] init];
      _failures = [[NSMutableDictionary alloc] init];
      _failureDetails = [[NSMutableArray alloc] init];
    }
  return self;
}

- (void)incrementKey:(NSString *)key
{
  [_lock lock];
  _failures[key] = @([_failures[key] unsignedLongLongValue] + 1ULL);
  [_lock unlock];
}

- (void)recordFailure:(GSWSFailureBucket)bucket detail:(NSString *)detail
              countIt:(BOOL)countIt
{
  NSString *bucketName;

  bucketName = GSWSFailureBucketName(bucket);
  [_lock lock];
  if (countIt)
    {
      _failures[bucketName] = @([_failures[bucketName] unsignedLongLongValue] + 1ULL);
    }
  if ([_failureDetails count] < 100)
    {
      [_failureDetails addObject:
        [NSString stringWithFormat: @"[%@] %@", bucketName, detail]];
    }
  [_lock unlock];
}

@end

@class GSWSHarnessController;

@interface GSWSSlot : NSObject
@property(nonatomic, weak) GSWSHarnessController *controller;
@property(nonatomic, assign) NSUInteger slotID;
@property(nonatomic, assign) GSWSSlotState state;
@property(nonatomic, strong) NSURLSessionWebSocketTask *task;
@property(nonatomic, assign) uint64_t connHi;
@property(nonatomic, assign) uint64_t connLo;
@property(nonatomic, assign) uint64_t epoch;
@property(nonatomic, assign) uint64_t nextRequestSeq;
@property(nonatomic, assign) uint64_t nextPingID;
@property(nonatomic, assign) uint64_t nextExpectedPongID;
@property(nonatomic, assign) BOOL receiveInFlight;
@property(nonatomic, assign) BOOL closeRecorded;
@property(nonatomic, assign) BOOL closedByHarness;
@property(nonatomic, assign) uint64_t lastSeq;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, GSWSRequestLedgerEntry *> *requests;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *pendingResponseOrder;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *pendingPings;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *pendingSendOrder;
@property(nonatomic, assign) BOOL sendInFlight;
@property(nonatomic, strong) NSUUID *connectionUUID;
@property(nonatomic, strong) NSData *closeReason;
@property(nonatomic, strong) NSDate *lastStateChange;
@property(nonatomic, strong) NSLock *lock;
@end

@implementation GSWSSlot

- (instancetype)init
{
  self = [super init];
  if (self != nil)
    {
      _state = GSWSSlotStateEmpty;
      _nextRequestSeq = 1;
      _nextPingID = 1;
      _nextExpectedPongID = 1;
      _requests = [[NSMutableDictionary alloc] init];
      _pendingResponseOrder = [[NSMutableArray alloc] init];
      _pendingPings = [[NSMutableArray alloc] init];
      _pendingSendOrder = [[NSMutableArray alloc] init];
      _lock = [[NSLock alloc] init];
      _lastStateChange = [NSDate date];
    }
  return self;
}

@end

@interface GSWSHarnessController : NSObject <NSURLSessionWebSocketDelegate>
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, assign) NSUInteger workerCount;
@property(nonatomic, assign) NSUInteger slotCount;
@property(nonatomic, assign) NSTimeInterval duration;
@property(nonatomic, assign) NSInteger delegateQueueConcurrency;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSOperationQueue *delegateQueue;
@property(nonatomic, strong) NSMutableArray<GSWSSlot *> *slots;
@property(nonatomic, strong) GSWSStats *stats;
@property(nonatomic, strong) NSLock *taskMapLock;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, GSWSSlot *> *taskMap;
@property(nonatomic, assign) BOOL stopRequested;
@property(nonatomic, strong) NSMutableArray<NSThread *> *workers;
@property(nonatomic, assign) BOOL pingsEnabled;
@property(nonatomic, assign) BOOL cancelsEnabled;
- (instancetype)initWithURL:(NSURL *)url
                workerCount:(NSUInteger)workerCount
                  slotCount:(NSUInteger)slotCount
                   duration:(NSTimeInterval)duration
   delegateQueueConcurrency:(NSInteger)delegateQueueConcurrency;
- (int)run;
- (void)recordFailure:(GSWSFailureBucket)bucket
               slotID:(NSUInteger)slotID
                epoch:(uint64_t)epoch
               detail:(NSString *)detail
              countIt:(BOOL)countIt;
- (void)startReceiveOnSlot:(GSWSSlot *)slot
                      task:(NSURLSessionWebSocketTask *)task
                     epoch:(uint64_t)epoch;
- (void)ensureReceiveScheduledForSlot:(GSWSSlot *)slot;
- (void)drainSendQueueForSlot:(GSWSSlot *)slot;
- (void)markSlotTransportFailed:(GSWSSlot *)slot
                          epoch:(uint64_t)epoch
                         bucket:(GSWSFailureBucket)bucket
                         detail:(NSString *)detail;
@end

static NSString *
GSWSSlotStateName(GSWSSlotState state)
{
  switch (state)
    {
      case GSWSSlotStateEmpty: return @"EMPTY";
      case GSWSSlotStateConnecting: return @"CONNECTING";
      case GSWSSlotStateOpen: return @"OPEN";
      case GSWSSlotStateClosing: return @"CLOSING";
      case GSWSSlotStateClosed: return @"CLOSED";
    }
}

@implementation GSWSHarnessController

- (instancetype)initWithURL:(NSURL *)url
                workerCount:(NSUInteger)workerCount
                  slotCount:(NSUInteger)slotCount
                   duration:(NSTimeInterval)duration
   delegateQueueConcurrency:(NSInteger)delegateQueueConcurrency
{
  NSUInteger idx;

  self = [super init];
  if (self != nil)
    {
      _url = url;
      _workerCount = workerCount;
      _slotCount = slotCount;
      _duration = duration;
      _delegateQueueConcurrency = MAX((NSInteger)1, delegateQueueConcurrency);
      _stats = [[GSWSStats alloc] init];
      _delegateQueue = [[NSOperationQueue alloc] init];
      [_delegateQueue setMaxConcurrentOperationCount: _delegateQueueConcurrency];
      _taskMapLock = [[NSLock alloc] init];
      _taskMap = [[NSMutableDictionary alloc] init];
      _workers = [[NSMutableArray alloc] init];
      _pingsEnabled = YES;
      _cancelsEnabled = YES;
      _slots = [[NSMutableArray alloc] initWithCapacity: slotCount];
      for (idx = 0; idx < slotCount; idx++)
        {
          GSWSSlot *slot;

          slot = [[GSWSSlot alloc] init];
          slot.slotID = idx;
          slot.controller = self;
          [_slots addObject: slot];
        }
    }
  return self;
}

- (void)recordFailure:(GSWSFailureBucket)bucket
               slotID:(NSUInteger)slotID
                epoch:(uint64_t)epoch
               detail:(NSString *)detail
              countIt:(BOOL)countIt
{
  NSString *fullDetail;

  fullDetail = [NSString stringWithFormat: @"slot=%lu epoch=%llu %@",
                                      (unsigned long)slotID,
                                      (unsigned long long)epoch,
                                      detail];
  [_stats recordFailure: bucket detail: fullDetail countIt: countIt];
  NSLog(@"%@", fullDetail);
}

- (GSWSSlot *)randomSlotPassing:(BOOL (^)(GSWSSlot *slot))predicate
{
  NSMutableArray<GSWSSlot *> *matches;
  GSWSSlot *slot;

  matches = [NSMutableArray array];
  for (slot in _slots)
    {
      if (predicate(slot))
        {
          [matches addObject: slot];
        }
    }
  if ([matches count] == 0)
    {
      return nil;
    }
  return matches[arc4random_uniform((uint32_t)[matches count])];
}

- (void)registerTask:(NSURLSessionWebSocketTask *)task forSlot:(GSWSSlot *)slot
{
  [_taskMapLock lock];
  _taskMap[@([task taskIdentifier])] = slot;
  [_taskMapLock unlock];
}

- (void)unregisterTask:(NSURLSessionWebSocketTask *)task
{
  [_taskMapLock lock];
  [_taskMap removeObjectForKey: @([task taskIdentifier])];
  [_taskMapLock unlock];
}

- (void)createTaskInSlot:(GSWSSlot *)slot workerID:(NSUInteger)workerID
{
  NSURLSessionWebSocketTask *task;
  NSURLSessionConfiguration *configuration;
  NSUUID *uuid;

  [slot.lock lock];
  if (!(slot.state == GSWSSlotStateEmpty || slot.state == GSWSSlotStateClosed))
    {
      [slot.lock unlock];
      return;
    }

  slot.epoch += 1;
  slot.connectionUUID = [NSUUID UUID];
  {
    uint64_t connHi;
    uint64_t connLo;

    GSWSUUIDToConnectionWords(slot.connectionUUID, &connHi, &connLo);
    slot.connHi = connHi;
    slot.connLo = connLo;
  }
  slot.state = GSWSSlotStateConnecting;
  slot.nextRequestSeq = 1;
  slot.nextPingID = 1;
  slot.nextExpectedPongID = 1;
  slot.receiveInFlight = NO;
  slot.closeRecorded = NO;
  slot.closedByHarness = NO;
  slot.lastSeq = 0;
  [slot.requests removeAllObjects];
  [slot.pendingResponseOrder removeAllObjects];
  [slot.pendingPings removeAllObjects];
  [slot.pendingSendOrder removeAllObjects];
  slot.sendInFlight = NO;
  slot.closeReason = nil;
  slot.lastStateChange = [NSDate date];
  [slot.lock unlock];

  configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
  configuration.timeoutIntervalForRequest = 30.0;
  configuration.timeoutIntervalForResource = 30.0;
#ifdef GNUSTEP
  configuration.HTTPMaximumConnectionsPerHost = 0;
#endif
  if (_session == nil)
    {
      _session = [NSURLSession sessionWithConfiguration: configuration
                                               delegate: self
                                          delegateQueue: _delegateQueue];
    }
  task = [_session webSocketTaskWithURL: _url];
  [task setMaximumMessageSize: GSWS_HEADER_SIZE + GSWS_MAX_PAYLOAD_LEN + 1024];

  [slot.lock lock];
  slot.task = task;
  [slot.lock unlock];
  [self registerTask: task forSlot: slot];
  [task resume];

  [_stats.lock lock];
  _stats.creates += 1;
  [_stats.lock unlock];

  uuid = slot.connectionUUID;
  NSLog(@"worker=%lu create slot=%lu conn=%@ epoch=%llu",
        (unsigned long)workerID,
        (unsigned long)slot.slotID,
        [uuid UUIDString],
        (unsigned long long)slot.epoch);
}

- (void)sendOnSlot:(GSWSSlot *)slot workerID:(NSUInteger)workerID
{
  [self sendOnSlot: slot workerID: workerID payloadLength: GSWSRandomPayloadLength(60)];
}

- (void)sendOnSlot:(GSWSSlot *)slot
          workerID:(NSUInteger)workerID
       payloadLength:(uint32_t)payloadLength
{
  GSWSRequestLedgerEntry *entry;
  GSWSHeaderV1 requestHeader;
  GSWSHeaderV1 responseHeader;
  NSData *requestPayload;
  NSData *responsePayload;
  uint64_t seq;
  uint64_t nowMs;

  [slot.lock lock];
  if ((slot.state != GSWSSlotStateOpen
      && slot.state != GSWSSlotStateConnecting)
      || slot.task == nil)
    {
      [slot.lock unlock];
      return;
    }

  seq = slot.nextRequestSeq++;
  nowMs = GSWSNowMilliseconds();

  memset(&requestHeader, 0, sizeof(requestHeader));
  requestHeader.magic = GSWS_MAGIC;
  requestHeader.version = GSWS_VERSION;
  requestHeader.type = GSWSMessageTypeRequest;
  requestHeader.conn_hi = slot.connHi;
  requestHeader.conn_lo = slot.connLo;
  requestHeader.epoch = slot.epoch;
  requestHeader.seq = seq;
  requestHeader.reply_to = 0;
  requestHeader.worker_id = (uint32_t)workerID;
  requestHeader.slot_id = (uint32_t)slot.slotID;
  requestHeader.payload_len = payloadLength;
  requestHeader.payload_kind = GSWS_PAYLOAD_KIND_SYNTHETIC_V1;
  requestHeader.payload_seed = ((uint64_t)arc4random() << 32) | arc4random();

  requestPayload = GSWSGeneratePayload(requestHeader.conn_hi,
                                       requestHeader.conn_lo,
                                       requestHeader.epoch,
                                       requestHeader.seq,
                                       requestHeader.payload_seed,
                                       requestHeader.payload_len);
  requestHeader.payload_hash = GSWSHashPayload(requestPayload);

  memset(&responseHeader, 0, sizeof(responseHeader));
  responseHeader.magic = GSWS_MAGIC;
  responseHeader.version = GSWS_VERSION;
  responseHeader.type = GSWSMessageTypeResponse;
  responseHeader.conn_hi = requestHeader.conn_hi;
  responseHeader.conn_lo = requestHeader.conn_lo;
  responseHeader.epoch = requestHeader.epoch;
  responseHeader.seq = seq;
  responseHeader.reply_to = seq;
  responseHeader.worker_id = requestHeader.worker_id;
  responseHeader.slot_id = requestHeader.slot_id;
  responseHeader.payload_len = requestHeader.payload_len;
  responseHeader.payload_kind = GSWS_PAYLOAD_KIND_SYNTHETIC_V1;
  responseHeader.payload_seed = requestHeader.payload_seed ^ GSWS_RESPONSE_SEED_XOR;
  responsePayload = GSWSGeneratePayload(responseHeader.conn_hi,
                                        responseHeader.conn_lo,
                                        responseHeader.epoch,
                                        responseHeader.seq,
                                        responseHeader.payload_seed,
                                        responseHeader.payload_len);
  responseHeader.payload_hash = GSWSHashPayload(responsePayload);

  entry = [[GSWSRequestLedgerEntry alloc] init];
  entry.requestHeader = requestHeader;
  entry.expectedResponseHeader = responseHeader;
  entry.requestPayload = requestPayload;
  entry.expectedResponsePayload = responsePayload;
  entry.encodedMessageData = GSWSBuildMessageData(&requestHeader, requestPayload);
  entry.createdAtMs = nowMs;
  slot.requests[@(seq)] = entry;
  [slot.pendingResponseOrder addObject: @(seq)];
  [slot.pendingSendOrder addObject: @(seq)];
  slot.lastSeq = seq;
  NSLog(@"send-enqueue slot=%lu epoch=%llu seq=%llu len=%u queued=%lu",
        (unsigned long)slot.slotID,
        (unsigned long long)slot.epoch,
        (unsigned long long)seq,
        payloadLength,
        (unsigned long)[slot.pendingSendOrder count]);
  [slot.lock unlock];

  [_stats.lock lock];
  _stats.sends += 1;
  [_stats.lock unlock];
  [self drainSendQueueForSlot: slot];
}

- (BOOL)waitForSlotOpen:(GSWSSlot *)slot timeout:(NSTimeInterval)timeout
{
  NSDate *deadline;

  deadline = [NSDate dateWithTimeIntervalSinceNow: timeout];
  while ([[NSDate date] compare: deadline] == NSOrderedAscending)
    {
      [slot.lock lock];
      GSWSSlotState state = slot.state;
      [slot.lock unlock];
      if (state == GSWSSlotStateOpen)
        {
          return YES;
        }
      if (state == GSWSSlotStateClosed)
        {
          return NO;
        }
      [NSThread sleepForTimeInterval: 0.05];
    }
  return NO;
}

- (BOOL)slotCanExchangeMessages:(GSWSSlot *)slot
{
  BOOL ok;

  [slot.lock lock];
  ok = ((slot.state == GSWSSlotStateOpen
    || slot.state == GSWSSlotStateConnecting)
    && slot.task != nil);
  [slot.lock unlock];
  return ok;
}

- (void)drainSendQueueForSlot:(GSWSSlot *)slot
{
  NSURLSessionWebSocketTask *task;
  NSNumber *seqNumber;
  GSWSRequestLedgerEntry *entry;
  uint64_t epoch;
  uint64_t seq;

  [slot.lock lock];
  if ((slot.state != GSWSSlotStateOpen
      && slot.state != GSWSSlotStateConnecting)
      || slot.task == nil
      || slot.sendInFlight
      || [slot.pendingSendOrder count] == 0)
    {
      [slot.lock unlock];
      return;
    }
  seqNumber = [slot.pendingSendOrder objectAtIndex: 0];
  [slot.pendingSendOrder removeObjectAtIndex: 0];
  entry = slot.requests[seqNumber];
  if (entry == nil || entry.canceledByClose)
    {
      [slot.lock unlock];
      [self drainSendQueueForSlot: slot];
      return;
    }
  slot.sendInFlight = YES;
  task = slot.task;
  epoch = slot.epoch;
  seq = entry.requestHeader.seq;
  entry.dispatchedAtMs = GSWSNowMilliseconds();
  [slot.lock unlock];

  [task sendMessage: [[NSURLSessionWebSocketMessage alloc]
                       initWithData: entry.encodedMessageData]
  completionHandler:^(NSError * _Nullable error) {
    [slot.lock lock];
    if (slot.epoch != epoch)
      {
        slot.sendInFlight = NO;
        [slot.lock unlock];
        [self recordFailure: GSWSFailureBucketUnexpectedCallbackAfterReuse
                     slotID: slot.slotID
                      epoch: epoch
                     detail: [NSString stringWithFormat:
                       @"send completion after slot reuse seq=%llu",
                       (unsigned long long)seq]
                    countIt: YES];
        return;
      }
    slot.sendInFlight = NO;
    if (error != nil)
      {
        BOOL expectedClose;

        expectedClose = (slot.state == GSWSSlotStateClosing
          || slot.state == GSWSSlotStateClosed
          || entry.canceledByClose);
        [slot.lock unlock];
        if (expectedClose)
          {
            [_stats.lock lock];
            _stats.expectedCloseCancellations += 1;
            [_stats.lock unlock];
            [self recordFailure: GSWSFailureBucketExpectedCloseCancellation
                         slotID: slot.slotID
                          epoch: epoch
                         detail: [NSString stringWithFormat:
                           @"send canceled after close seq=%llu error=%@",
                           (unsigned long long)seq,
                           error]
                        countIt: NO];
          }
        else
          {
            [self markSlotTransportFailed: slot
                                    epoch: epoch
                                   bucket: GSWSFailureBucketProtocolMismatch
                                   detail: [NSString stringWithFormat:
                                     @"send failed seq=%llu error=%@",
                                     (unsigned long long)seq,
                                     error]];
          }
        return;
      }

    entry.sendCompleted = YES;
    entry.sentAtMs = GSWSNowMilliseconds();
    [slot.lock unlock];
    [_stats.lock lock];
    _stats.sendCompletions += 1;
    [_stats.lock unlock];
    NSLog(@"send-ok slot=%lu epoch=%llu seq=%llu len=%u",
          (unsigned long)slot.slotID,
          (unsigned long long)epoch,
          (unsigned long long)seq,
          entry.requestHeader.payload_len);
    [self ensureReceiveScheduledForSlot: slot];
    [self drainSendQueueForSlot: slot];
  }];
}

- (void)markSlotTransportFailed:(GSWSSlot *)slot
                          epoch:(uint64_t)epoch
                         bucket:(GSWSFailureBucket)bucket
                         detail:(NSString *)detail
{
  NSURLSessionWebSocketTask *task;
  NSArray<GSWSRequestLedgerEntry *> *entries;

  task = nil;
  [slot.lock lock];
  if (slot.epoch != epoch)
    {
      [slot.lock unlock];
      [self recordFailure: GSWSFailureBucketUnexpectedCallbackAfterReuse
                   slotID: slot.slotID
                    epoch: epoch
                   detail: [NSString stringWithFormat:
                     @"transport failure after reuse: %@",
                     detail]
                  countIt: YES];
      return;
    }
  if (slot.state == GSWSSlotStateClosed)
    {
      [slot.lock unlock];
      return;
    }
  slot.state = GSWSSlotStateClosed;
  slot.receiveInFlight = NO;
  slot.sendInFlight = NO;
  slot.closedByHarness = NO;
  task = slot.task;
  slot.task = nil;
  entries = [slot.requests allValues];
  for (GSWSRequestLedgerEntry *entry in entries)
    {
      entry.canceledByClose = YES;
    }
  [slot.pendingSendOrder removeAllObjects];
  [slot.lock unlock];

  if (task != nil)
    {
      [self unregisterTask: task];
      [task cancel];
    }
  [self recordFailure: bucket
               slotID: slot.slotID
                epoch: epoch
               detail: detail
              countIt: YES];
}

- (void)primeSmokeCoverage
{
  NSUInteger warmSlots;
  NSUInteger idx;

  warmSlots = MIN((NSUInteger)2, _slotCount);
  for (idx = 0; idx < warmSlots; idx++)
    {
      [self createTaskInSlot: _slots[idx] workerID: 9000 + idx];
    }
  for (idx = 0; idx < warmSlots; idx++)
    {
      GSWSSlot *slot;

      slot = _slots[idx];
      NSLog(@"prime slot=%lu state=%@ task=%@",
            (unsigned long)slot.slotID,
            GSWSSlotStateName(slot.state),
            slot.task);
      [self sendOnSlot: slot workerID: 9000 + idx payloadLength: 65536];
      [self ensureReceiveScheduledForSlot: slot];
      if (_pingsEnabled)
        {
          [self sendPingOnSlot: slot];
        }
    }
}

- (void)validateReceivedMessageData:(NSData *)messageData
                            onSlot:(GSWSSlot *)slot
                             epoch:(uint64_t)epoch
{
  GSWSHeaderV1 responseHeader;
  NSData *payload;
  NSString *decodeError;
  NSNumber *expectedSeqNumber;
  GSWSRequestLedgerEntry *entry;

  decodeError = nil;
  payload = nil;
  if (!GSWSDecodeHeader(messageData, &responseHeader, &payload, &decodeError))
    {
      [self recordFailure: GSWSFailureBucketProtocolMismatch
                   slotID: slot.slotID
                    epoch: epoch
                   detail: [NSString stringWithFormat:
                     @"decode failure: %@ preview=%@",
                     decodeError,
                     GSWSPreviewData(messageData, 32)]
                  countIt: YES];
      return;
    }

  [slot.lock lock];
  if (slot.epoch != epoch)
    {
      [slot.lock unlock];
      [self recordFailure: GSWSFailureBucketUnexpectedCallbackAfterReuse
                   slotID: slot.slotID
                    epoch: epoch
                   detail: @"receive completion after slot reuse"
                  countIt: YES];
      return;
    }
  if ([slot.pendingResponseOrder count] == 0)
    {
      [slot.lock unlock];
      [self recordFailure: GSWSFailureBucketOrderingMismatch
                   slotID: slot.slotID
                    epoch: epoch
                   detail: [NSString stringWithFormat:
                     @"response reply_to=%llu arrived with no pending request",
                     (unsigned long long)responseHeader.reply_to]
                  countIt: YES];
      return;
    }
  expectedSeqNumber = [slot.pendingResponseOrder objectAtIndex: 0];
  entry = slot.requests[@(responseHeader.reply_to)];
  [slot.lock unlock];

  if (responseHeader.magic != GSWS_MAGIC
      || responseHeader.version != GSWS_VERSION
      || responseHeader.type != GSWSMessageTypeResponse
      || responseHeader.conn_hi != slot.connHi
      || responseHeader.conn_lo != slot.connLo
      || responseHeader.epoch != epoch)
    {
      [self recordFailure: GSWSFailureBucketProtocolMismatch
                   slotID: slot.slotID
                    epoch: epoch
                   detail: [NSString stringWithFormat:
                     @"response header mismatch type=%u conn=%@",
                     responseHeader.type,
                     GSWSDescribeConnection(responseHeader.conn_hi,
                                            responseHeader.conn_lo,
                                            responseHeader.epoch)]
                  countIt: YES];
      return;
    }

  if (entry == nil)
    {
      [self recordFailure: GSWSFailureBucketOrderingMismatch
                   slotID: slot.slotID
                    epoch: epoch
                   detail: [NSString stringWithFormat:
                     @"unexpected reply_to=%llu expected_front=%@",
                     (unsigned long long)responseHeader.reply_to,
                     expectedSeqNumber]
                  countIt: YES];
      return;
    }

  if ([expectedSeqNumber unsignedLongLongValue] != responseHeader.reply_to)
    {
      [self recordFailure: GSWSFailureBucketOrderingMismatch
                   slotID: slot.slotID
                    epoch: epoch
                   detail: [NSString stringWithFormat:
                     @"out-of-order reply_to=%llu expected=%@",
                     (unsigned long long)responseHeader.reply_to,
                     expectedSeqNumber]
                  countIt: YES];
      return;
    }
  if (!entry.sendCompleted)
    {
      [self recordFailure: GSWSFailureBucketOrderingMismatch
                   slotID: slot.slotID
                    epoch: epoch
                   detail: [NSString stringWithFormat:
                     @"response for unsent request seq=%llu",
                     (unsigned long long)responseHeader.reply_to]
                  countIt: YES];
      return;
    }
  if (entry.receiveCompleted)
    {
      [self recordFailure: GSWSFailureBucketOrderingMismatch
                   slotID: slot.slotID
                    epoch: epoch
                   detail: [NSString stringWithFormat:
                     @"duplicate response seq=%llu",
                     (unsigned long long)responseHeader.reply_to]
                  countIt: YES];
      return;
    }
  if (responseHeader.payload_len != entry.expectedResponseHeader.payload_len
      || responseHeader.payload_kind != entry.expectedResponseHeader.payload_kind
      || responseHeader.payload_seed != entry.expectedResponseHeader.payload_seed
      || responseHeader.payload_hash != entry.expectedResponseHeader.payload_hash
      || responseHeader.seq != entry.expectedResponseHeader.seq
      || responseHeader.reply_to != entry.expectedResponseHeader.reply_to)
    {
      [self recordFailure: GSWSFailureBucketProtocolMismatch
                   slotID: slot.slotID
                    epoch: epoch
                   detail: [NSString stringWithFormat:
                     @"response header fields mismatch seq=%llu",
                     (unsigned long long)responseHeader.reply_to]
                  countIt: YES];
      return;
    }

  if (![payload isEqualToData: entry.expectedResponsePayload]
      || GSWSHashPayload(payload) != responseHeader.payload_hash)
    {
      [self recordFailure: GSWSFailureBucketPayloadMismatch
                   slotID: slot.slotID
                    epoch: epoch
                   detail: [NSString stringWithFormat:
                     @"payload mismatch seq=%llu len=%u",
                     (unsigned long long)responseHeader.reply_to,
                     responseHeader.payload_len]
                  countIt: YES];
      return;
    }

  [slot.lock lock];
  entry.receiveCompleted = YES;
  entry.receivedAtMs = GSWSNowMilliseconds();
  [slot.pendingResponseOrder removeObjectAtIndex: 0];
  [slot.requests removeObjectForKey: @(responseHeader.reply_to)];
  [slot.lock unlock];

  [_stats.lock lock];
  _stats.receiveCompletions += 1;
  _stats.completedRequestCount += 1;
  if (entry.sentAtMs >= entry.createdAtMs)
    {
      uint64_t queueToSendMs;

      queueToSendMs = entry.sentAtMs - entry.createdAtMs;
      _stats.totalQueueToSendMs += queueToSendMs;
      if (queueToSendMs > _stats.maxQueueToSendMs)
        {
          _stats.maxQueueToSendMs = queueToSendMs;
        }
    }
  if (entry.dispatchedAtMs >= entry.createdAtMs)
    {
      uint64_t queueBeforeDispatchMs;

      queueBeforeDispatchMs = entry.dispatchedAtMs - entry.createdAtMs;
      _stats.totalQueueBeforeDispatchMs += queueBeforeDispatchMs;
      if (queueBeforeDispatchMs > _stats.maxQueueBeforeDispatchMs)
        {
          _stats.maxQueueBeforeDispatchMs = queueBeforeDispatchMs;
        }
    }
  if (entry.sentAtMs >= entry.dispatchedAtMs)
    {
      uint64_t dispatchToSendMs;

      dispatchToSendMs = entry.sentAtMs - entry.dispatchedAtMs;
      _stats.totalDispatchToSendMs += dispatchToSendMs;
      if (dispatchToSendMs > _stats.maxDispatchToSendMs)
        {
          _stats.maxDispatchToSendMs = dispatchToSendMs;
        }
    }
  if (entry.receivedAtMs >= entry.sentAtMs)
    {
      uint64_t roundTripMs;

      roundTripMs = entry.receivedAtMs - entry.sentAtMs;
      _stats.totalRoundTripMs += roundTripMs;
      if (roundTripMs > _stats.maxRoundTripMs)
        {
          _stats.maxRoundTripMs = roundTripMs;
        }
    }
  if (responseHeader.payload_len >= 65536)
    {
      _stats.validatedLargeResponses += 1;
    }
  [_stats.lock unlock];
  if (entry.canceledByClose)
    {
      NSLog(@"recv-after-close-valid slot=%lu epoch=%llu reply_to=%llu",
            (unsigned long)slot.slotID,
            (unsigned long long)epoch,
            (unsigned long long)responseHeader.reply_to);
    }
  NSLog(@"recv-ok slot=%lu epoch=%llu reply_to=%llu len=%u remaining=%lu",
        (unsigned long)slot.slotID,
        (unsigned long long)epoch,
        (unsigned long long)responseHeader.reply_to,
        responseHeader.payload_len,
        (unsigned long)[slot.pendingResponseOrder count]);
}

- (void)ensureReceiveScheduledForSlot:(GSWSSlot *)slot
{
  NSURLSessionWebSocketTask *task;
  uint64_t epoch;

  [slot.lock lock];
  if ((slot.state != GSWSSlotStateOpen
      && slot.state != GSWSSlotStateConnecting)
      || slot.receiveInFlight
      || [slot.pendingResponseOrder count] == 0
      || slot.task == nil)
    {
      [slot.lock unlock];
      return;
    }
  slot.receiveInFlight = YES;
  task = slot.task;
  epoch = slot.epoch;
  [slot.lock unlock];

  [self startReceiveOnSlot: slot task: task epoch: epoch];
}

- (void)startReceiveOnSlot:(GSWSSlot *)slot
                      task:(NSURLSessionWebSocketTask *)task
                     epoch:(uint64_t)epoch
{
  [_stats.lock lock];
  _stats.receives += 1;
  [_stats.lock unlock];

  [task receiveMessageWithCompletionHandler:
    ^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
      NSData *messageData;

      [slot.lock lock];
      if (slot.epoch != epoch)
        {
          slot.receiveInFlight = NO;
          [slot.lock unlock];
          [self recordFailure: GSWSFailureBucketUnexpectedCallbackAfterReuse
                       slotID: slot.slotID
                       epoch: epoch
                       detail: @"receive callback after slot reuse"
                      countIt: YES];
          return;
        }
      [slot.lock unlock];

      if (error != nil)
        {
          BOOL expectedClose;

          [slot.lock lock];
          slot.receiveInFlight = NO;
          [slot.lock unlock];
          [slot.lock lock];
          expectedClose = (slot.state == GSWSSlotStateClosing
            || slot.state == GSWSSlotStateClosed
            || slot.closedByHarness);
          [slot.lock unlock];
          if (expectedClose)
            {
              [_stats.lock lock];
              _stats.expectedCloseCancellations += 1;
              [_stats.lock unlock];
              [self recordFailure: GSWSFailureBucketExpectedCloseCancellation
                           slotID: slot.slotID
                            epoch: epoch
                           detail: [NSString stringWithFormat:
                             @"receive canceled by close error=%@",
                             error]
                          countIt: NO];
              return;
            }

          [self markSlotTransportFailed: slot
                                  epoch: epoch
                                 bucket: GSWSFailureBucketProtocolMismatch
                                 detail: [NSString stringWithFormat:
                                   @"receive failed error=%@",
                                   error]];
          return;
        }
      if (message == nil || [message type] != NSURLSessionWebSocketMessageTypeData)
        {
          [slot.lock lock];
          slot.receiveInFlight = NO;
          [slot.lock unlock];
          [self recordFailure: GSWSFailureBucketProtocolMismatch
                       slotID: slot.slotID
                        epoch: epoch
                       detail: @"receive yielded non-binary message"
                      countIt: YES];
          return;
        }

      messageData = [message data];
      [self validateReceivedMessageData: messageData onSlot: slot epoch: epoch];

      [slot.lock lock];
      if (slot.epoch != epoch
          || (slot.state != GSWSSlotStateOpen
              && slot.state != GSWSSlotStateConnecting)
          || slot.task == nil
          || [slot.pendingResponseOrder count] == 0)
        {
          slot.receiveInFlight = NO;
          [slot.lock unlock];
          return;
        }
      NSURLSessionWebSocketTask *nextTask = slot.task;
      [slot.lock unlock];
      [self startReceiveOnSlot: slot task: nextTask epoch: epoch];
    }];
}

- (void)sendPingOnSlot:(GSWSSlot *)slot
{
  NSURLSessionWebSocketTask *task;
  uint64_t epoch;
  uint64_t pingID;

  [slot.lock lock];
  if ((slot.state != GSWSSlotStateOpen
      && slot.state != GSWSSlotStateConnecting)
      || slot.task == nil)
    {
      [slot.lock unlock];
      return;
    }
  task = slot.task;
  epoch = slot.epoch;
  pingID = slot.nextPingID++;
  [slot.pendingPings addObject: @(pingID)];
  [slot.lock unlock];

  [_stats.lock lock];
  _stats.pings += 1;
  [_stats.lock unlock];

  [task sendPingWithPongReceiveHandler:^(NSError * _Nullable error) {
    NSNumber *front;

    [slot.lock lock];
    if (slot.epoch != epoch)
      {
        [slot.lock unlock];
        [self recordFailure: GSWSFailureBucketUnexpectedCallbackAfterReuse
                     slotID: slot.slotID
                      epoch: epoch
                     detail: [NSString stringWithFormat:
                       @"pong callback after slot reuse ping=%llu",
                       (unsigned long long)pingID]
                    countIt: YES];
        return;
      }

    front = [slot.pendingPings firstObject];
    if (front != nil && [front unsignedLongLongValue] == pingID)
      {
        [slot.pendingPings removeObjectAtIndex: 0];
      }
    [slot.lock unlock];

    if (error != nil)
      {
        [slot.lock lock];
        BOOL expectedClose = (slot.state == GSWSSlotStateClosing
          || slot.state == GSWSSlotStateClosed
          || slot.closedByHarness);
        [slot.lock unlock];

        if (expectedClose)
          {
            [_stats.lock lock];
            _stats.expectedCloseCancellations += 1;
            [_stats.lock unlock];
            [self recordFailure: GSWSFailureBucketExpectedCloseCancellation
                         slotID: slot.slotID
                          epoch: epoch
                         detail: [NSString stringWithFormat:
                           @"ping canceled by close ping=%llu error=%@",
                           (unsigned long long)pingID,
                           error]
                        countIt: NO];
            return;
          }

        [self recordFailure: GSWSFailureBucketProtocolMismatch
                     slotID: slot.slotID
                      epoch: epoch
                     detail: [NSString stringWithFormat:
                       @"ping failed ping=%llu error=%@",
                       (unsigned long long)pingID,
                       error]
                    countIt: YES];
        return;
      }

    if (front == nil || [front unsignedLongLongValue] != pingID)
      {
        [self recordFailure: GSWSFailureBucketOrderingMismatch
                     slotID: slot.slotID
                      epoch: epoch
                     detail: [NSString stringWithFormat:
                       @"pong callback out of order ping=%llu front=%@",
                       (unsigned long long)pingID,
                       front]
                    countIt: YES];
        return;
      }

    [_stats.lock lock];
    _stats.pongCompletions += 1;
    [_stats.lock unlock];
  }];
}

- (void)closeSlot:(GSWSSlot *)slot
{
  NSURLSessionWebSocketTask *task;
  NSData *reason;
  uint64_t epoch;
  NSArray<GSWSRequestLedgerEntry *> *entries;

  [slot.lock lock];
  if ((slot.state != GSWSSlotStateOpen && slot.state != GSWSSlotStateConnecting)
      || slot.task == nil)
    {
      [slot.lock unlock];
      return;
    }
  slot.state = GSWSSlotStateClosing;
  slot.closedByHarness = YES;
  task = slot.task;
  epoch = slot.epoch;
  reason = GSWSCloseReasonData(slot.connHi, slot.connLo, slot.epoch, slot.lastSeq);
  slot.closeReason = reason;
  entries = [slot.requests allValues];
  for (GSWSRequestLedgerEntry *entry in entries)
    {
      if (!entry.receiveCompleted)
        {
          entry.canceledByClose = YES;
        }
    }
  [slot.lock unlock];

  [_stats.lock lock];
  _stats.closes += 1;
  [_stats.lock unlock];

  [task cancelWithCloseCode: NSURLSessionWebSocketCloseCodeNormalClosure
                     reason: reason];
  NSLog(@"close requested slot=%lu epoch=%llu",
        (unsigned long)slot.slotID,
        (unsigned long long)epoch);
}

- (void)checkTimeouts
{
  uint64_t now;
  GSWSSlot *slot;

  now = GSWSNowMilliseconds();
  for (slot in _slots)
    {
      NSArray<NSNumber *> *keys;
      NSNumber *seqNumber;

      [slot.lock lock];
      if (slot.state == GSWSSlotStateClosing || slot.state == GSWSSlotStateClosed)
        {
          [slot.lock unlock];
          continue;
        }
      keys = [slot.requests allKeys];
      for (seqNumber in keys)
        {
          GSWSRequestLedgerEntry *entry;

          entry = slot.requests[seqNumber];
          if (entry == nil
              || entry.receiveCompleted
              || entry.canceledByClose
              || !entry.sendCompleted
              || entry.timeoutReported)
            {
              continue;
            }
          if (now >= entry.sentAtMs && now - entry.sentAtMs > 5000)
            {
              entry.timeoutReported = YES;
              [slot.lock unlock];
              [self recordFailure: GSWSFailureBucketTimeout
                           slotID: slot.slotID
                            epoch: slot.epoch
                           detail: [NSString stringWithFormat:
                             @"request timed out seq=%@ age_ms=%llu",
                             seqNumber,
                             (unsigned long long)(now - entry.sentAtMs)]
                          countIt: YES];
              [slot.lock lock];
            }
        }
      [slot.lock unlock];
    }
}

- (void)performWorkerIteration:(NSUInteger)workerID
{
  uint32_t roll;
  GSWSSlot *slot;

  roll = arc4random_uniform(1000);
  if (roll < 10)
    {
      slot = [self randomSlotPassing:^BOOL(GSWSSlot *candidate) {
        [candidate.lock lock];
        BOOL ok = (candidate.state == GSWSSlotStateEmpty
          || candidate.state == GSWSSlotStateClosed);
        [candidate.lock unlock];
        return ok;
      }];
      if (slot != nil)
        {
          [self createTaskInSlot: slot workerID: workerID];
          return;
        }
    }
  else if (roll < 110)
    {
      slot = [self randomSlotPassing:^BOOL(GSWSSlot *candidate) {
        [candidate.lock lock];
        BOOL ok = ((candidate.state == GSWSSlotStateOpen
          || candidate.state == GSWSSlotStateConnecting)
          && candidate.task != nil);
        [candidate.lock unlock];
        return ok;
      }];
      if (slot != nil)
        {
          [self sendOnSlot: slot workerID: workerID];
          return;
        }
    }
  else if (roll < 210)
    {
      slot = [self randomSlotPassing:^BOOL(GSWSSlot *candidate) {
        BOOL ok;

        [candidate.lock lock];
        ok = ((candidate.state == GSWSSlotStateOpen
          || candidate.state == GSWSSlotStateConnecting)
          && candidate.task != nil
          && !candidate.receiveInFlight
          && [candidate.pendingResponseOrder count] > 0);
        [candidate.lock unlock];
        return ok;
      }];
      if (slot != nil)
        {
          [self ensureReceiveScheduledForSlot: slot];
          return;
        }
    }
  else if (roll < 220)
    {
      if (!_pingsEnabled)
        {
          [NSThread sleepForTimeInterval: 0.02];
          return;
        }
      slot = [self randomSlotPassing:^BOOL(GSWSSlot *candidate) {
        [candidate.lock lock];
        BOOL ok = ((candidate.state == GSWSSlotStateOpen
          || candidate.state == GSWSSlotStateConnecting)
          && candidate.task != nil);
        [candidate.lock unlock];
        return ok;
      }];
      if (slot != nil)
        {
          [self sendPingOnSlot: slot];
          return;
        }
    }
  else if (roll < 225)
    {
      if (!_cancelsEnabled)
        {
          [NSThread sleepForTimeInterval: 0.02];
          return;
        }
      slot = [self randomSlotPassing:^BOOL(GSWSSlot *candidate) {
        [candidate.lock lock];
        BOOL ok = (candidate.state == GSWSSlotStateOpen
          || candidate.state == GSWSSlotStateConnecting);
        [candidate.lock unlock];
        return ok;
      }];
      if (slot != nil)
        {
          [self closeSlot: slot];
          return;
        }
    }

  {
    double randomUnit;
    double r;

    randomUnit = (double)arc4random() / (double)UINT32_MAX;
    r = MAX(0.01, randomUnit);
    [NSThread sleepForTimeInterval: 0.005 / r];
  }
}

- (void)workerMain:(NSNumber *)workerIDNumber
{
  NSUInteger workerID;

  workerID = [workerIDNumber unsignedIntegerValue];
  while (!_stopRequested)
    {
      @autoreleasepool
        {
          [self performWorkerIteration: workerID];
        }
    }
}

- (void)finishAllSlots
{
  GSWSSlot *slot;

  for (slot in _slots)
    {
      [self closeSlot: slot];
    }
}

- (BOOL)hasCountedFailures
{
  NSArray<NSString *> *names;
  NSString *name;

  names = @[
    GSWSFailureBucketName(GSWSFailureBucketProtocolMismatch),
    GSWSFailureBucketName(GSWSFailureBucketPayloadMismatch),
    GSWSFailureBucketName(GSWSFailureBucketOrderingMismatch),
    GSWSFailureBucketName(GSWSFailureBucketUnexpectedCallbackAfterReuse),
    GSWSFailureBucketName(GSWSFailureBucketTimeout),
  ];
  [_stats.lock lock];
  for (name in names)
    {
      if ([_stats.failures[name] unsignedLongLongValue] > 0)
        {
          [_stats.lock unlock];
          return YES;
        }
    }
  [_stats.lock unlock];
  return NO;
}

- (void)printSummary
{
  [_stats.lock lock];
  NSLog(@"summary creates=%llu opens=%llu sends=%llu send_ok=%llu receives=%llu "
        @"receive_ok=%llu pings=%llu pong_ok=%llu closes=%llu close_cb=%llu "
        @"large_ok=%llu expected_close_cancellations=%llu",
        (unsigned long long)_stats.creates,
        (unsigned long long)_stats.opens,
        (unsigned long long)_stats.sends,
        (unsigned long long)_stats.sendCompletions,
        (unsigned long long)_stats.receives,
        (unsigned long long)_stats.receiveCompletions,
        (unsigned long long)_stats.pings,
        (unsigned long long)_stats.pongCompletions,
        (unsigned long long)_stats.closes,
        (unsigned long long)_stats.closeCallbacks,
        (unsigned long long)_stats.validatedLargeResponses,
        (unsigned long long)_stats.expectedCloseCancellations);
  NSLog(@"latency-summary completed=%llu queue_to_send_avg_ms=%.3f "
        @"queue_to_send_max_ms=%llu queue_before_dispatch_avg_ms=%.3f "
        @"queue_before_dispatch_max_ms=%llu dispatch_to_send_avg_ms=%.3f "
        @"dispatch_to_send_max_ms=%llu round_trip_avg_ms=%.3f "
        @"round_trip_max_ms=%llu",
        (unsigned long long)_stats.completedRequestCount,
        _stats.completedRequestCount ? (double)_stats.totalQueueToSendMs / (double)_stats.completedRequestCount : 0.0,
        (unsigned long long)_stats.maxQueueToSendMs,
        _stats.completedRequestCount ? (double)_stats.totalQueueBeforeDispatchMs / (double)_stats.completedRequestCount : 0.0,
        (unsigned long long)_stats.maxQueueBeforeDispatchMs,
        _stats.completedRequestCount ? (double)_stats.totalDispatchToSendMs / (double)_stats.completedRequestCount : 0.0,
        (unsigned long long)_stats.maxDispatchToSendMs,
        _stats.completedRequestCount ? (double)_stats.totalRoundTripMs / (double)_stats.completedRequestCount : 0.0,
        (unsigned long long)_stats.maxRoundTripMs);
  NSLog(@"failure-counts %@", _stats.failures);
  if ([_stats.failureDetails count] > 0)
    {
      NSLog(@"failure-details %@", _stats.failureDetails);
    }
  [_stats.lock unlock];
}

- (int)run
{
  NSDate *deadline;
  NSUInteger idx;

  [self primeSmokeCoverage];
  deadline = [NSDate dateWithTimeIntervalSinceNow: _duration];
  for (idx = 0; idx < _workerCount; idx++)
    {
      NSThread *thread;

      thread = [[NSThread alloc] initWithTarget: self
                                       selector: @selector(workerMain:)
                                         object: @(idx)];
      [_workers addObject: thread];
      [thread start];
    }

  while ([[NSDate date] compare: deadline] == NSOrderedAscending)
    {
      [NSThread sleepForTimeInterval: 0.25];
      [self checkTimeouts];
    }
  _stopRequested = YES;

  for (NSThread *thread in _workers)
    {
      while (![thread isFinished])
        {
          [NSThread sleepForTimeInterval: 0.05];
        }
    }

  [self finishAllSlots];
  [NSThread sleepForTimeInterval: 1.5];
  [self printSummary];
  if ([_session respondsToSelector: @selector(_workQueueProfileSnapshot)])
    {
      NSString *snapshot;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      snapshot = [_session performSelector: @selector(_workQueueProfileSnapshot)];
#pragma clang diagnostic pop
      NSLog(@"%@", snapshot);
    }
#ifdef GNUSTEP
  if (GSWebSocketTaskLockProfileSnapshot != NULL)
    {
      NSLog(@"%@", GSWebSocketTaskLockProfileSnapshot());
    }
#endif
  [_session finishTasksAndInvalidate];

  [_stats.lock lock];
  BOOL hasCreates = _stats.creates > 0;
  BOOL hasSends = _stats.sends > 0;
  BOOL hasReceives = _stats.receiveCompletions > 0;
  BOOL hasPings = (!_pingsEnabled) || (_stats.pongCompletions > 0);
  BOOL hasCloses = (!_cancelsEnabled) || (_stats.closes > 0);
  BOOL hasLarge = _stats.validatedLargeResponses > 0;
  [_stats.lock unlock];

  if (!hasCreates || !hasSends || !hasReceives || !hasPings || !hasCloses
      || !hasLarge)
    {
      NSLog(@"smoke-run did not exercise required categories "
            @"creates=%d sends=%d receives=%d pings=%d closes=%d large=%d",
            hasCreates, hasSends, hasReceives, hasPings, hasCloses, hasLarge);
      return 2;
    }
  return [self hasCountedFailures] ? 1 : 0;
}

- (void)URLSession:(NSURLSession *)session
  webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
  didOpenWithProtocol:(NSString *)protocol
{
  GSWSSlot *slot;

  (void)session;
  (void)protocol;

  [_taskMapLock lock];
  slot = _taskMap[@([webSocketTask taskIdentifier])];
  [_taskMapLock unlock];
  if (slot == nil)
    {
      return;
    }

  [slot.lock lock];
  if (slot.task != webSocketTask)
    {
      uint64_t epoch = slot.epoch;
      [slot.lock unlock];
      [self recordFailure: GSWSFailureBucketUnexpectedCallbackAfterReuse
                   slotID: slot.slotID
                    epoch: epoch
                   detail: @"didOpen callback for stale task"
                  countIt: YES];
      return;
    }
  slot.state = GSWSSlotStateOpen;
  slot.lastStateChange = [NSDate date];
  [slot.lock unlock];

  [_stats.lock lock];
  _stats.opens += 1;
  [_stats.lock unlock];
  NSLog(@"slot=%lu didOpen epoch=%llu protocol=%@",
        (unsigned long)slot.slotID,
        (unsigned long long)slot.epoch,
        protocol);
  [self drainSendQueueForSlot: slot];
  [self ensureReceiveScheduledForSlot: slot];
}

- (void)URLSession:(NSURLSession *)session
  webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
  didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode
  reason:(NSData *)reason
{
  GSWSSlot *slot;

  (void)session;

  [_taskMapLock lock];
  slot = _taskMap[@([webSocketTask taskIdentifier])];
  [_taskMapLock unlock];
  if (slot == nil)
    {
      return;
    }

  [slot.lock lock];
  if (slot.task != webSocketTask)
    {
      uint64_t epoch = slot.epoch;
      [slot.lock unlock];
      [self recordFailure: GSWSFailureBucketUnexpectedCallbackAfterReuse
                   slotID: slot.slotID
                    epoch: epoch
                   detail: @"didClose callback for stale task"
                  countIt: YES];
      return;
    }
  slot.state = GSWSSlotStateClosed;
  slot.task = nil;
  slot.closeRecorded = YES;
  slot.closeReason = reason;
  slot.lastStateChange = [NSDate date];
  [slot.lock unlock];
  [self unregisterTask: webSocketTask];

  [_stats.lock lock];
  _stats.closeCallbacks += 1;
  [_stats.lock unlock];
  NSLog(@"slot=%lu closed code=%ld state=%@",
        (unsigned long)slot.slotID,
        (long)closeCode,
        GSWSSlotStateName(slot.state));
}

- (void)URLSession:(NSURLSession *)session
  task:(NSURLSessionTask *)task
  didCompleteWithError:(NSError *)error
{
  GSWSSlot *slot;
  uint64_t epoch;
  NSString *detail;

  (void)session;

  if (error == nil || ![task isKindOfClass: [NSURLSessionWebSocketTask class]])
    {
      return;
    }

  [_taskMapLock lock];
  slot = _taskMap[@([task taskIdentifier])];
  [_taskMapLock unlock];
  if (slot == nil)
    {
      NSLog(@"task=%lu completed after unregister error=%@",
            (unsigned long)[task taskIdentifier],
            error);
      return;
    }

  [slot.lock lock];
  epoch = slot.epoch;
  BOOL expectedClose = (slot.state == GSWSSlotStateClosing
    || slot.state == GSWSSlotStateClosed
    || slot.closedByHarness);
  [slot.lock unlock];
  detail = [NSString stringWithFormat: @"task completed error=%@", error];
  NSLog(@"slot=%lu epoch=%llu %@",
        (unsigned long)slot.slotID,
        (unsigned long long)epoch,
        detail);
  if (expectedClose)
    {
      [_stats.lock lock];
      _stats.expectedCloseCancellations += 1;
      [_stats.lock unlock];
      [self recordFailure: GSWSFailureBucketExpectedCloseCancellation
                   slotID: slot.slotID
                    epoch: epoch
                   detail: detail
                  countIt: NO];
      return;
    }
  [self markSlotTransportFailed: slot
                          epoch: epoch
                         bucket: GSWSFailureBucketProtocolMismatch
                         detail: detail];
}

@end

int
main(int argc, const char *argv[])
{
  @autoreleasepool
    {
      uint16_t port;
      NSUInteger workerCount;
      NSUInteger slotCount;
      NSTimeInterval duration;
      NSInteger delegateQueueConcurrency;
      NSURL *url;
      GSWSHarnessController *controller;

      port = 19090;
      workerCount = 2;
      slotCount = 4;
      duration = 12.0;
      delegateQueueConcurrency = 1;

      if (argc > 1)
        {
          port = (uint16_t)strtoul(argv[1], NULL, 10);
        }
      if (argc > 2)
        {
          workerCount = (NSUInteger)strtoul(argv[2], NULL, 10);
        }
      if (argc > 3)
        {
          slotCount = (NSUInteger)strtoul(argv[3], NULL, 10);
        }
      if (argc > 4)
        {
          duration = strtod(argv[4], NULL);
        }
      if (argc > 5)
        {
          delegateQueueConcurrency = (NSInteger)strtol(argv[5], NULL, 10);
        }

      url = [NSURL URLWithString:
        [NSString stringWithFormat: @"ws://127.0.0.1:%hu/ws", port]];
      controller = [[GSWSHarnessController alloc] initWithURL: url
                                                  workerCount: workerCount
                                                    slotCount: slotCount
                                                     duration: duration
                                     delegateQueueConcurrency:
                                       delegateQueueConcurrency];
      return [controller run];
    }
}
