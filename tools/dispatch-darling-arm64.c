typedef unsigned long size_t;
typedef unsigned long long dispatch_time_t;
typedef struct dispatch_queue_s* dispatch_queue_t;
typedef struct dispatch_group_s* dispatch_group_t;
typedef struct dispatch_semaphore_s* dispatch_semaphore_t;
typedef struct dispatch_source_s* dispatch_source_t;
typedef const struct dispatch_source_type_s* dispatch_source_type_t;
typedef long dispatch_once_t;

extern void dispatch_async_f(dispatch_queue_t queue, void* context, void (*function)(void*));
extern dispatch_queue_t dispatch_get_global_queue(long priority, unsigned long flags);
extern void* dispatch_get_specific(const void* key);
extern dispatch_group_t dispatch_group_create(void);
extern void dispatch_group_async_f(dispatch_group_t group, dispatch_queue_t queue,
		void* context, void (*function)(void*));
extern long dispatch_group_wait(dispatch_group_t group, dispatch_time_t timeout);
extern void dispatch_once_f(dispatch_once_t* predicate, void* context, void (*function)(void*));
extern dispatch_queue_t dispatch_queue_create(const char* label, const void* attributes);
extern void dispatch_queue_set_specific(dispatch_queue_t queue, const void* key,
		void* context, void (*destructor)(void*));
extern void dispatch_release(void* object);
extern void dispatch_resume(void* object);
extern dispatch_semaphore_t dispatch_semaphore_create(long value);
extern long dispatch_semaphore_signal(dispatch_semaphore_t semaphore);
extern long dispatch_semaphore_wait(dispatch_semaphore_t semaphore, dispatch_time_t timeout);
extern void dispatch_sync_f(dispatch_queue_t queue, void* context, void (*function)(void*));
extern dispatch_source_t dispatch_source_create(dispatch_source_type_t type,
		unsigned long handle, unsigned long mask, dispatch_queue_t queue);
extern void dispatch_source_cancel(dispatch_source_t source);
extern void dispatch_source_set_cancel_handler_f(dispatch_source_t source, void (*function)(void*));
extern void dispatch_source_set_event_handler_f(dispatch_source_t source, void (*function)(void*));
extern void dispatch_source_set_timer(dispatch_source_t source, dispatch_time_t start,
		unsigned long long interval, unsigned long long leeway);
extern dispatch_time_t dispatch_time(dispatch_time_t when, long long delta);
extern void dispatch_set_context(void* object, void* context);
extern void dispatch_main(void);
extern int close(int fd);
extern void exit(int status);
extern int pipe(int descriptors[2]);
extern long read(int fd, void* buffer, size_t length);
extern long write(int fd, const void* buffer, size_t length);

extern struct dispatch_source_type_s _dispatch_source_type_read;
extern struct dispatch_source_type_s _dispatch_source_type_timer;
extern struct dispatch_queue_s _dispatch_main_q;

#define DISPATCH_TIME_FOREVER (~(dispatch_time_t)0)

static int serial_value;
static int concurrent_value;
static int once_value;
static int specific_value;
static char specific_key;
static dispatch_semaphore_t serial_done;
static int source_events;
static int source_cancellations;

struct source_context {
	dispatch_source_t source;
	int fd;
	int kind;
};

static struct source_context read_context;
static struct source_context timer_context;

static int fail(const char* message, size_t length, int status)
{
	write(2, message, length);
	return status;
}

static void serial_first(void* context)
{
	(void)context;
	if (serial_value == 0)
		serial_value = 1;
}

static void serial_second(void* context)
{
	(void)context;
	if (serial_value == 1)
		serial_value = 2;
	dispatch_semaphore_signal(serial_done);
}

static void concurrent_work(void* context)
{
	(void)context;
	__atomic_add_fetch(&concurrent_value, 1, __ATOMIC_RELAXED);
}

static void once_work(void* context)
{
	int* value = context;
	++*value;
}

static void specific_work(void* context)
{
	if (dispatch_get_specific(&specific_key) == context)
		specific_value = 1;
}

static void source_event(void* opaque)
{
	struct source_context* context = opaque;
	if (context->kind == 1) {
		char byte = 0;
		if (read(context->fd, &byte, 1) == 1 && byte == 'D')
			__atomic_add_fetch(&source_events, 1, __ATOMIC_RELAXED);
	} else {
		__atomic_add_fetch(&source_events, 1, __ATOMIC_RELAXED);
	}
	dispatch_source_cancel(context->source);
}

static void source_cancelled(void* opaque)
{
	struct source_context* context = opaque;
	if (context->fd >= 0)
		close(context->fd);
	dispatch_release(context->source);
	if (__atomic_add_fetch(&source_cancellations, 1, __ATOMIC_RELAXED) == 2) {
		static const char success[] = "Darling ARM64 dispatch smoke passed\n";
		if (source_events != 2)
			exit(20);
		write(2, success, sizeof(success) - 1);
		exit(0);
	}
}

int main(void)
{
	static const char foundation[] = "Darling ARM64 dispatch foundation passed\n";
	dispatch_queue_t serial_queue = dispatch_queue_create("darling.arm64.serial", 0);
	dispatch_queue_t concurrent_queue = dispatch_get_global_queue(0, 0);
	dispatch_group_t group = dispatch_group_create();
	dispatch_once_t once = 0;

	if (!serial_queue || !concurrent_queue || !group)
		return fail("dispatch object creation failed\n", 32, 10);
	serial_done = dispatch_semaphore_create(0);
	if (!serial_done)
		return 11;

	dispatch_async_f(serial_queue, 0, serial_first);
	dispatch_async_f(serial_queue, 0, serial_second);
	if (dispatch_semaphore_wait(serial_done, DISPATCH_TIME_FOREVER) != 0 || serial_value != 2)
		return 12;

	for (int index = 0; index < 16; ++index)
		dispatch_group_async_f(group, concurrent_queue, 0, concurrent_work);
	if (dispatch_group_wait(group, DISPATCH_TIME_FOREVER) != 0 || concurrent_value != 16)
		return 13;

	dispatch_once_f(&once, &once_value, once_work);
	dispatch_once_f(&once, &once_value, once_work);
	if (once_value != 1)
		return 14;

	dispatch_queue_set_specific(serial_queue, &specific_key, &specific_key, 0);
	dispatch_sync_f(serial_queue, &specific_key, specific_work);
	if (specific_value != 1)
		return 15;

	dispatch_release(serial_done);
	dispatch_release(group);
	dispatch_release(serial_queue);
	write(2, foundation, sizeof(foundation) - 1);

	int descriptors[2];
	if (pipe(descriptors) != 0)
		return 16;
	dispatch_queue_t main_queue = &_dispatch_main_q;
	read_context.source = dispatch_source_create(&_dispatch_source_type_read,
			(unsigned long)descriptors[0], 0, main_queue);
	read_context.fd = descriptors[0];
	read_context.kind = 1;
	timer_context.source = dispatch_source_create(&_dispatch_source_type_timer, 0, 0, main_queue);
	timer_context.fd = -1;
	timer_context.kind = 2;
	if (!read_context.source || !timer_context.source)
		return 17;

	dispatch_set_context(read_context.source, &read_context);
	dispatch_source_set_event_handler_f(read_context.source, source_event);
	dispatch_source_set_cancel_handler_f(read_context.source, source_cancelled);
	dispatch_set_context(timer_context.source, &timer_context);
	dispatch_source_set_event_handler_f(timer_context.source, source_event);
	dispatch_source_set_cancel_handler_f(timer_context.source, source_cancelled);
	dispatch_source_set_timer(timer_context.source, dispatch_time(0, 10000000),
			DISPATCH_TIME_FOREVER, 1000000);
	dispatch_resume(read_context.source);
	dispatch_resume(timer_context.source);
	if (write(descriptors[1], "D", 1) != 1 || close(descriptors[1]) != 0)
		return 18;
	dispatch_main();
}
