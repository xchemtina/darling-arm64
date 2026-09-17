typedef unsigned long size_t;
typedef unsigned long pthread_key_t;
typedef unsigned int sigset_t;
typedef struct _opaque_pthread_t* pthread_t;

typedef struct {
	long signature;
	char opaque[56];
} pthread_mutex_t;

typedef struct {
	long signature;
	char opaque[40];
} pthread_cond_t;

typedef struct {
	long signature;
	char opaque[8];
} pthread_once_t;

typedef struct {
	void* stack;
	size_t size;
	int flags;
} stack_t;

extern int pthread_cancel(pthread_t thread);
extern int pthread_cond_signal(pthread_cond_t* condition);
extern int pthread_cond_wait(pthread_cond_t* condition, pthread_mutex_t* mutex);
extern int pthread_create(pthread_t* thread, const void* attributes,
		void* (*start_routine)(void*), void* argument);
extern int pthread_detach(pthread_t thread);
extern void* pthread_getspecific(pthread_key_t key);
extern int pthread_join(pthread_t thread, void** value);
extern int pthread_key_create(pthread_key_t* key, void (*destructor)(void*));
extern int pthread_key_delete(pthread_key_t key);
extern int pthread_mutex_lock(pthread_mutex_t* mutex);
extern int pthread_mutex_unlock(pthread_mutex_t* mutex);
extern int pthread_once(pthread_once_t* once, void (*routine)(void));
extern int pthread_setspecific(pthread_key_t key, const void* value);
extern int pthread_sigmask(int operation, const sigset_t* set, sigset_t* old_set);
extern int sigaltstack(const stack_t* stack, stack_t* old_stack);
extern long write(int fd, const void* buffer, size_t length);

#define MUTEX_INITIALIZER { 0x32AAABA7, { 0 } }
#define RECURSIVE_MUTEX_INITIALIZER { 0x32AAABA2, { 0 } }
#define COND_INITIALIZER { 0x3CB0B1BB, { 0 } }
#define ONCE_INITIALIZER { 0x30B1BCBA, { 0 } }

static pthread_mutex_t counter_mutex = MUTEX_INITIALIZER;
static pthread_mutex_t recursive_mutex = RECURSIVE_MUTEX_INITIALIZER;
static pthread_mutex_t detached_mutex = MUTEX_INITIALIZER;
static pthread_cond_t detached_condition = COND_INITIALIZER;
static pthread_mutex_t cancel_mutex = MUTEX_INITIALIZER;
static pthread_cond_t cancel_condition = COND_INITIALIZER;
static pthread_once_t once_control = ONCE_INITIALIZER;
static pthread_key_t tls_key;
static int counter;
static int detached_done;
static int cancel_ready;
static int destructor_count;
static int once_count;
static char alternate_stacks[2][32768];

static int fail(const char* message, size_t length, int status)
{
	write(2, message, length);
	return status;
}

static void* return_worker(void* argument)
{
	return argument;
}

static void* counter_worker(void* argument)
{
	(void)argument;
	for (int iteration = 0; iteration < 1000; ++iteration) {
		if (pthread_mutex_lock(&counter_mutex) != 0)
			return (void*)1;
		++counter;
		if (pthread_mutex_unlock(&counter_mutex) != 0)
			return (void*)2;
	}
	return 0;
}

static void* detached_worker(void* argument)
{
	(void)argument;
	pthread_mutex_lock(&detached_mutex);
	detached_done = 1;
	pthread_cond_signal(&detached_condition);
	pthread_mutex_unlock(&detached_mutex);
	return 0;
}

static void tls_destructor(void* value)
{
	static const char message[] = "pthread-smoke: TLS destructor\n";
	write(2, message, sizeof(message) - 1);
	if (value == (void*)0x7654)
		__atomic_add_fetch(&destructor_count, 1, __ATOMIC_RELAXED);
}

static void* tls_worker(void* argument)
{
	(void)argument;
	if (pthread_setspecific(tls_key, (void*)0x7654) != 0)
		return (void*)1;
	if (pthread_getspecific(tls_key) != (void*)0x7654)
		return (void*)2;
	return 0;
}

static void once_routine(void)
{
	__atomic_add_fetch(&once_count, 1, __ATOMIC_RELAXED);
}

static void* once_worker(void* argument)
{
	(void)argument;
	return (void*)(long)pthread_once(&once_control, once_routine);
}

static void* cancel_worker(void* argument)
{
	(void)argument;
	pthread_mutex_lock(&cancel_mutex);
	cancel_ready = 1;
	pthread_cond_signal(&cancel_condition);
	for (;;)
		pthread_cond_wait(&cancel_condition, &cancel_mutex);
}

static void* signal_worker(void* argument)
{
	char* alternate_stack = alternate_stacks[(long)argument & 1];
	sigset_t set = 1U << (30 - 1);
	sigset_t observed = 0;
	stack_t stack = { alternate_stack, sizeof(alternate_stacks[0]), 0 };
	stack_t current = { 0, 0, 0 };

	if (pthread_sigmask(1, &set, 0) != 0)
		return (void*)1;
	if (pthread_sigmask(3, 0, &observed) != 0 || (observed & set) != set)
		return (void*)2;
	if (sigaltstack(&stack, 0) != 0)
		return (void*)3;
	if (sigaltstack(0, &current) != 0 || current.stack != alternate_stack || current.flags != 0)
		return (void*)4;
	return argument;
}

static int join_success(pthread_t thread, int status)
{
	void* result = 0;
	if (pthread_join(thread, &result) != 0 || result != 0)
		return status;
	return 0;
}

int main(void)
{
	static const char success[] = "Darling ARM64 pthread smoke passed\n";
	pthread_t first;
	pthread_t second;
	void* result = 0;

	if (pthread_create(&first, 0, return_worker, (void*)0x1234) != 0)
		return fail("pthread_create failed\n", 22, 10);
	if (pthread_join(first, &result) != 0 || result != (void*)0x1234)
		return fail("pthread_join failed\n", 20, 11);

	if (pthread_create(&first, 0, counter_worker, 0) != 0 ||
			pthread_create(&second, 0, counter_worker, 0) != 0)
		return 12;
	if (join_success(first, 13) != 0 || join_success(second, 14) != 0 || counter != 2000)
		return 15;
	if (pthread_mutex_lock(&recursive_mutex) != 0 ||
			pthread_mutex_lock(&recursive_mutex) != 0 ||
			pthread_mutex_unlock(&recursive_mutex) != 0 ||
			pthread_mutex_unlock(&recursive_mutex) != 0)
		return 16;

	if (pthread_key_create(&tls_key, tls_destructor) != 0)
		return 18;
	if (pthread_create(&first, 0, tls_worker, 0) != 0 || join_success(first, 19) != 0)
		return 19;
	if (destructor_count != 1 || pthread_key_delete(tls_key) != 0)
		return 20;

	if (pthread_create(&first, 0, once_worker, 0) != 0 ||
			pthread_create(&second, 0, once_worker, 0) != 0)
		return 21;
	if (join_success(first, 22) != 0 || join_success(second, 23) != 0 || once_count != 1)
		return 24;

	if (pthread_create(&first, 0, signal_worker, (void*)0x8888) != 0 ||
			pthread_create(&second, 0, signal_worker, (void*)0x8889) != 0)
		return 25;
	if (pthread_join(first, &result) != 0 || result != (void*)0x8888)
		return 26;
	if (pthread_join(second, &result) != 0 || result != (void*)0x8889)
		return 27;

	if (pthread_create(&first, 0, cancel_worker, 0) != 0)
		return 28;
	pthread_mutex_lock(&cancel_mutex);
	while (!cancel_ready)
		pthread_cond_wait(&cancel_condition, &cancel_mutex);
	pthread_mutex_unlock(&cancel_mutex);
	if (pthread_cancel(first) != 0 || pthread_join(first, &result) != 0 || result != (void*)1)
		return 29;

	for (int iteration = 0; iteration < 100; ++iteration) {
		void* expected = (void*)(long)(iteration + 1);
		if (pthread_create(&first, 0, return_worker, expected) != 0)
			return 30;
		if (pthread_join(first, &result) != 0 || result != expected)
			return 31;
	}

	if (pthread_create(&first, 0, detached_worker, 0) != 0 || pthread_detach(first) != 0)
		return 32;
	pthread_mutex_lock(&detached_mutex);
	while (!detached_done)
		pthread_cond_wait(&detached_condition, &detached_mutex);
	pthread_mutex_unlock(&detached_mutex);

	write(2, success, sizeof(success) - 1);
	return 0;
}
