#include <objc/NSObject.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <dispatch/dispatch.h>

extern long write(int fd, const void* buffer, unsigned long length);
extern void* objc_autoreleasePoolPush(void);
extern void objc_autoreleasePoolPop(void* context);
extern void objc_destroyWeak(id* location);

static int initialized;
static int deallocated;
static int category_called;

@protocol Stage7Protocol
- (long)value;
@end

@interface Stage7Object : NSObject <Stage7Protocol> {
	long _value;
}
@property(nonatomic) long value;
- (long)add:(long)left to:(long)right;
@end

@implementation Stage7Object
@synthesize value = _value;

+ (void)initialize
{
	if (self == [Stage7Object class])
		++initialized;
}

- (long)add:(long)left to:(long)right
{
	return _value + left + right;
}

- (void)dealloc
{
	++deallocated;
	[super dealloc];
}
@end

@interface Stage7Object (Stage7Category)
- (long)categoryValue;
@end

@implementation Stage7Object (Stage7Category)
- (long)categoryValue
{
	category_called = 1;
	return self.value + 1;
}
@end

@interface Stage7Child : Stage7Object
@end

@implementation Stage7Child
- (long)add:(long)left to:(long)right
{
	return [super add:left to:right] + 100;
}
@end

static long dynamic_value(id self, SEL command)
{
	(void)self;
	(void)command;
	return 73;
}

static long forwarded_sum(id self, SEL command, long left, long right)
{
	(void)self;
	(void)command;
	return left + right + 9;
}

static int fail(const char* message, int status)
{
	unsigned long length = 0;
	while (message[length])
		++length;
	write(2, message, length);
	return status;
}

int main(void)
{
	static const char entered[] = "objc-smoke: entered main\n";
	write(2, entered, sizeof(entered) - 1);
	void* pool = objc_autoreleasePoolPush();
	static const char pooled[] = "objc-smoke: autorelease pool\n";
	write(2, pooled, sizeof(pooled) - 1);
	Class child_class = objc_getClass("Stage7Child");
	if (!child_class)
		return fail("Objective-C static class registration failed\n", 9);
	Stage7Child* object = [[child_class alloc] init];
	if (!object || initialized != 1)
		return fail("Objective-C class initialization failed\n", 10);

	object.value = 7;
	if (object.value != 7 || [object add:2 to:3] != 112)
		return fail("Objective-C method dispatch failed\n", 11);
	if (![object conformsToProtocol:@protocol(Stage7Protocol)] ||
			[object categoryValue] != 8 || !category_called)
		return fail("Objective-C protocol/category failed\n", 12);

	Class dynamic = objc_allocateClassPair([NSObject class], "Stage7Dynamic", 0);
	SEL dynamic_selector = sel_registerName("dynamicValue");
	if (!dynamic || !class_addMethod(dynamic, dynamic_selector,
			(IMP)dynamic_value, "q@:"))
		return fail("Objective-C dynamic class construction failed\n", 13);
	objc_registerClassPair(dynamic);
	id dynamic_object = [[dynamic alloc] init];
	long (*send_long)(id, SEL) = (void*)objc_msgSend;
	if (send_long(dynamic_object, dynamic_selector) != 73)
		return fail("Objective-C dynamic class dispatch failed\n", 14);
	[dynamic_object release];

	objc_setForwardHandler((void*)forwarded_sum, (void*)forwarded_sum);
	SEL missing_selector = sel_registerName("missingAdd:to:");
	long (*send_forwarded)(id, SEL, long, long) = (void*)objc_msgSend;
	if (send_forwarded(object, missing_selector, 4, 5) != 18)
		return fail("Objective-C message forwarding failed\n", 15);

	int caught = 0;
	int finalized = 0;
	@try {
		@throw object;
	} @catch (Stage7Object* exception) {
		caught = exception == object;
	} @finally {
		finalized = 1;
	}
	if (!caught || !finalized)
		return fail("Objective-C exception handling failed\n", 16);

	__block long dispatched_value = 0;
	dispatch_queue_t queue = dispatch_queue_create("stage7.object.queue", 0);
	dispatch_sync(queue, ^{
		dispatched_value = [object add:1 to:1];
	});
	dispatch_release(queue);
	if (dispatched_value != 109)
		return fail("Objective-C block/dispatch interaction failed\n", 17);

	id weak = nil;
	objc_storeWeak(&weak, object);
	if (objc_loadWeak(&weak) != object)
		return fail("Objective-C weak load failed\n", 18);
	[object autorelease];
	objc_autoreleasePoolPop(pool);
	if (weak != nil || deallocated != 1)
		return fail("Objective-C weak/autorelease lifecycle failed\n", 19);
	objc_destroyWeak(&weak);

	static const char success[] = "Darling ARM64 Objective-C smoke passed\n";
	write(2, success, sizeof(success) - 1);
	return 0;
}
