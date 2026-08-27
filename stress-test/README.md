# Apple Foundation Binary WebSocket Stress Harness

This directory contains a standalone macOS harness that validates a binary
WebSocket request/response protocol against Apple's `NSURLSessionWebSocketTask`.

Files:

- `common.h` / `common.m`: fixed-size binary header, payload generation, hashing,
  and message encoding helpers.
- `server.m`: low-level RFC6455 server with random delay and fragmentation.
- `client.m`: Apple Foundation client with worker threads, slot reuse, request
  ledgers, ping ordering checks, and failure buckets.

Build:

```sh
make
```

Run a smoke test:

```sh
./ws-stress-server-apple 19090 50 30
./ws-stress-client-apple 19090 2 4 12 1
```

Arguments:

- Server: `port maxDelayMs fragmentChancePercent`
- Client: `port workers slots durationSeconds delegateQueueConcurrency`

Notes:

- `delegateQueueConcurrency=1` is the default and uses a serial delegate queue.
- Larger values, such as `8`, make the delegate queue concurrent and are useful
  when comparing callback scheduling behavior across Apple Foundation and
  GNUstep.

The client exits `0` when the smoke run sees no counted failures and exercises
create, send, receive, ping, close, and at least one response `>= 64 KiB`.
