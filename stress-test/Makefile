CLANG := xcrun clang
CFLAGS := -fobjc-arc -Wall -Wextra -Werror -framework Foundation
SHELL := /bin/bash

GNUSTEP_MAKE_DIR := /Users/hhuebner/workspace/objc-workspace/libs-make
GNUSTEP_ENV := . $(GNUSTEP_MAKE_DIR)/GNUstep.sh >/dev/null 2>&1
GNUSTEP_CONFIG := sh $(GNUSTEP_MAKE_DIR)/gnustep-config
GNUSTEP_CC := clang
GNUSTEP_OBJC_FLAGS = $$(GNUSTEP_MAKEFILES=$(GNUSTEP_MAKE_DIR) $(GNUSTEP_CONFIG) --objc-flags) -fobjc-runtime=gnustep-2.2 -fobjc-arc
GNUSTEP_BASE_LIBS = $$(GNUSTEP_MAKEFILES=$(GNUSTEP_MAKE_DIR) $(GNUSTEP_CONFIG) --base-libs) -lgnustep-base
GNUSTEP_COMMON_FLAGS := -Wall -Wextra -Werror

PORT ?= 19090
SERVER_DELAY_MS ?= 50
SERVER_FRAGMENT_PERCENT ?= 30
CLIENT_WORKERS ?= 8
CLIENT_SLOTS ?= 32
CLIENT_DURATION ?= 30
CLIENT_DELEGATE_QUEUE_CONCURRENCY ?= 1

all: ws-stress-server-apple ws-stress-client-apple

ws-stress-server-apple: server.m common.m common.h
	$(CLANG) $(CFLAGS) -o $@ server.m common.m

ws-stress-client-apple: client.m common.m common.h
	$(CLANG) $(CFLAGS) -o $@ client.m common.m

ws-stress-server-gnustep: server.m common.m common.h
	$(GNUSTEP_ENV) && \
	$(GNUSTEP_CC) $(GNUSTEP_COMMON_FLAGS) $(GNUSTEP_OBJC_FLAGS) -o $@ server.m common.m $(GNUSTEP_BASE_LIBS) -lcrypto

ws-stress-client-gnustep: client.m common.m common.h
	$(GNUSTEP_ENV) && \
	$(GNUSTEP_CC) $(GNUSTEP_COMMON_FLAGS) $(GNUSTEP_OBJC_FLAGS) -o $@ client.m common.m $(GNUSTEP_BASE_LIBS) -ldispatch

gnustep: ws-stress-server-gnustep ws-stress-client-gnustep

run-server-apple: ws-stress-server-apple
	./ws-stress-server-apple $(PORT) $(SERVER_DELAY_MS) $(SERVER_FRAGMENT_PERCENT)

run-client-apple: ws-stress-client-apple
	./ws-stress-client-apple $(PORT) $(CLIENT_WORKERS) $(CLIENT_SLOTS) $(CLIENT_DURATION) $(CLIENT_DELEGATE_QUEUE_CONCURRENCY)

run-server-gnustep: ws-stress-server-gnustep
	./ws-stress-server-gnustep $(PORT) $(SERVER_DELAY_MS) $(SERVER_FRAGMENT_PERCENT)

run-client-gnustep: ws-stress-client-gnustep
	./ws-stress-client-gnustep $(PORT) $(CLIENT_WORKERS) $(CLIENT_SLOTS) $(CLIENT_DURATION) $(CLIENT_DELEGATE_QUEUE_CONCURRENCY)

clean:
	rm -f ws-stress-server-apple ws-stress-client-apple \
		ws-stress-server-gnustep ws-stress-client-gnustep

.PHONY: all clean gnustep \
	run-server-apple run-client-apple \
	run-server-gnustep run-client-gnustep
