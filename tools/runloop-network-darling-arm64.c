#include <CoreFoundation/CoreFoundation.h>

#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static char response[512];
static size_t response_length;
static int http_complete;
static int notification_count;
static int timer_count;
static int timed_out;

static int fail(const char* message, int status)
{
	write(2, message, strlen(message));
	return status;
}

static int contains(const char* haystack, size_t haystack_length, const char* needle)
{
	size_t needle_length = strlen(needle);
	if (needle_length > haystack_length)
		return 0;
	for (size_t i = 0; i + needle_length <= haystack_length; ++i) {
		if (memcmp(haystack + i, needle, needle_length) == 0)
			return 1;
	}
	return 0;
}

static void maybe_stop(void)
{
	if (http_complete && notification_count == 1 && timer_count >= 1)
		CFRunLoopStop(CFRunLoopGetCurrent());
}

static void notification_callback(CFNotificationCenterRef center, void* observer,
	CFNotificationName name, const void* object, CFDictionaryRef user_info)
{
	(void)center;
	(void)observer;
	(void)name;
	(void)object;
	(void)user_info;
	++notification_count;
	maybe_stop();
}

static void timer_callback(CFRunLoopTimerRef timer, void* info)
{
	(void)timer;
	(void)info;
	++timer_count;
	maybe_stop();
}

static void timeout_callback(CFRunLoopTimerRef timer, void* info)
{
	(void)timer;
	(void)info;
	timed_out = 1;
	CFRunLoopStop(CFRunLoopGetCurrent());
}

static void socket_callback(CFSocketRef socket_ref, CFSocketCallBackType type,
	CFDataRef address, const void* data, void* info)
{
	(void)address;
	(void)data;
	(void)info;
	if (type != kCFSocketReadCallBack)
		return;

	int fd = CFSocketGetNative(socket_ref);
	for (;;) {
		ssize_t count = read(fd, response + response_length,
			sizeof(response) - response_length);
		if (count > 0) {
			response_length += (size_t)count;
			if (contains(response, response_length, "\r\n\r\nstage9-http-ok\n")) {
				http_complete = 1;
				CFSocketDisableCallBacks(socket_ref, kCFSocketReadCallBack);
				CFNotificationCenterPostNotification(CFNotificationCenterGetLocalCenter(),
					CFSTR("DarlingStage9HTTPComplete"), NULL, NULL, true);
				maybe_stop();
				return;
			}
			if (response_length == sizeof(response)) {
				timed_out = 1;
				CFRunLoopStop(CFRunLoopGetCurrent());
				return;
			}
			continue;
		}
		if (count == 0) {
			timed_out = !http_complete;
			CFRunLoopStop(CFRunLoopGetCurrent());
			return;
		}
		if (errno == EAGAIN || errno == EWOULDBLOCK)
			return;
		timed_out = 1;
		CFRunLoopStop(CFRunLoopGetCurrent());
		return;
	}
}

int main(void)
{
	const char* service = getenv("DARLING_STAGE9_PORT");
	if (!service || !*service)
		return fail("Stage 9 loopback service was not configured\n", 10);

	struct addrinfo hints;
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_flags = AI_NUMERICSERV;
	struct addrinfo* addresses = NULL;
	if (getaddrinfo("localhost", service, &hints, &addresses) != 0)
		return fail("Stage 9 localhost DNS failed\n", 11);

	int client = -1;
	for (struct addrinfo* current = addresses; current; current = current->ai_next) {
		client = socket(current->ai_family, current->ai_socktype, current->ai_protocol);
		if (client >= 0 && connect(client, current->ai_addr, current->ai_addrlen) == 0)
			break;
		if (client >= 0)
			close(client);
		client = -1;
	}
	freeaddrinfo(addresses);
	if (client < 0)
		return fail("Stage 9 loopback connection failed\n", 12);

	int flags = fcntl(client, F_GETFL, 0);
	if (flags < 0 || fcntl(client, F_SETFL, flags | O_NONBLOCK) != 0)
		return fail("Stage 9 nonblocking socket failed\n", 13);

	CFSocketContext context = {0, NULL, NULL, NULL, NULL};
	CFSocketRef socket_ref = CFSocketCreateWithNative(kCFAllocatorDefault, client,
		kCFSocketReadCallBack, socket_callback, &context);
	if (!socket_ref)
		return fail("Stage 9 CFSocket creation failed\n", 14);
	CFSocketSetSocketFlags(socket_ref,
		CFSocketGetSocketFlags(socket_ref) | kCFSocketCloseOnInvalidate);
	CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, socket_ref, 0);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);

	CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL,
		notification_callback, CFSTR("DarlingStage9HTTPComplete"), NULL,
		CFNotificationSuspensionBehaviorDeliverImmediately);

	CFRunLoopTimerContext timer_context = {0, NULL, NULL, NULL, NULL};
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	CFRunLoopTimerRef timer = CFRunLoopTimerCreate(kCFAllocatorDefault, now + 0.01, 0,
		0, 0, timer_callback, &timer_context);
	CFRunLoopTimerRef timeout = CFRunLoopTimerCreate(kCFAllocatorDefault, now + 5.0, 0,
		0, 0, timeout_callback, &timer_context);
	CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopDefaultMode);
	CFRunLoopAddTimer(CFRunLoopGetCurrent(), timeout, kCFRunLoopDefaultMode);

	static const char request[] =
		"GET /stage9 HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
	if (write(client, request, sizeof(request) - 1) != (ssize_t)(sizeof(request) - 1))
		return fail("Stage 9 HTTP request write failed\n", 15);
	CFRunLoopRun();

	CFNotificationCenterRemoveObserver(CFNotificationCenterGetLocalCenter(), NULL,
		CFSTR("DarlingStage9HTTPComplete"), NULL);
	CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
	CFSocketInvalidate(socket_ref);
	CFRelease(timeout);
	CFRelease(timer);
	CFRelease(source);
	CFRelease(socket_ref);

	if (timed_out || !http_complete || notification_count != 1 || timer_count < 1)
		return fail("Stage 9 run-loop network contract failed\n", 16);

	static const char success[] = "Darling ARM64 run-loop network smoke passed\n";
	write(2, success, sizeof(success) - 1);
	return 0;
}
