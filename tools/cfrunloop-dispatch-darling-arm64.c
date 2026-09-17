typedef unsigned long size_t;
typedef unsigned long long dispatch_time_t;
typedef struct dispatch_queue_s* dispatch_queue_t;
typedef const struct __CFRunLoop* CFRunLoopRef;

extern void dispatch_after_f(dispatch_time_t when, dispatch_queue_t queue,
		void* context, void (*function)(void*));
extern void dispatch_async_f(dispatch_queue_t queue, void* context, void (*function)(void*));
extern dispatch_queue_t dispatch_get_global_queue(long priority, unsigned long flags);
extern dispatch_time_t dispatch_time(dispatch_time_t when, long long delta);
extern CFRunLoopRef CFRunLoopGetMain(void);
extern void CFRunLoopRun(void);
extern void CFRunLoopStop(CFRunLoopRef run_loop);
extern void* pthread_self(void);
extern long write(int fd, const void* buffer, size_t length);
extern struct dispatch_queue_s _dispatch_main_q;

static CFRunLoopRef main_run_loop;
static void* main_thread;
static int callback_ran;
static int callback_on_main_thread;
static int timed_out;

static void main_queue_callback(void* context)
{
	(void)context;
	callback_ran = 1;
	callback_on_main_thread = pthread_self() == main_thread;
	CFRunLoopStop(main_run_loop);
}

static void timeout_callback(void* context)
{
	(void)context;
	timed_out = 1;
	CFRunLoopStop(main_run_loop);
}

int main(void)
{
	static const char success[] = "Darling ARM64 CFRunLoop dispatch integration passed\n";
	main_thread = pthread_self();
	main_run_loop = CFRunLoopGetMain();
	if (!main_run_loop)
		return 10;

	dispatch_after_f(dispatch_time(0, 2000000000LL),
			dispatch_get_global_queue(0, 0), 0, timeout_callback);
	dispatch_async_f(&_dispatch_main_q, 0, main_queue_callback);
	CFRunLoopRun();

	if (timed_out || !callback_ran)
		return 11;
	if (!callback_on_main_thread)
		return 12;
	write(2, success, sizeof(success) - 1);
	return 0;
}
