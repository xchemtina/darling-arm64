#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSJSONSerialization.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSPropertyList.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSValue.h>
#import <objc/message.h>

extern long write(int fd, const void* buffer, unsigned long length);
extern int memcmp(const void* left, const void* right, unsigned long length);
extern int unlink(const char* path);

static int notification_count;
static int timer_count;

static void mark(const char* message)
{
	unsigned long length = 0;
	while (message[length])
		++length;
	write(2, message, length);
}

static int fail(const char* message, int status)
{
	unsigned long length = 0;
	while (message[length])
		++length;
	write(2, message, length);
	return status;
}

@interface Stage8Observer : NSObject
- (void)received:(NSNotification*)notification;
- (void)timerFired:(NSTimer*)timer;
@end

@interface Stage8InvocationTarget : NSObject
- (long)add:(long)left to:(long)right;
@end

@implementation Stage8InvocationTarget
- (long)add:(long)left to:(long)right
{
	return left + right + 8;
}
@end

@interface Stage8Forwarder : NSObject
@end

@implementation Stage8Forwarder
- (NSMethodSignature*)methodSignatureForSelector:(SEL)selector
{
	if (selector == sel_registerName("forwardedAdd:to:"))
		return [NSMethodSignature signatureWithObjCTypes:"q@:qq"];
	return [super methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation*)invocation
{
	long left = 0;
	long right = 0;
	[invocation getArgument:&left atIndex:2];
	[invocation getArgument:&right atIndex:3];
	long result = left + right + 80;
	[invocation setReturnValue:&result];
}
@end

@implementation Stage8Observer
- (void)received:(NSNotification*)notification
{
	if ([[notification name] isEqualToString:@"Stage8Notification"])
		++notification_count;
}

- (void)timerFired:(NSTimer*)timer
{
	(void)timer;
	++timer_count;
}
@end

int main(void)
{
	@autoreleasepool {
		mark("foundation-smoke: entered main\n");

		mark("foundation-smoke: strings\n");
		NSString* string = [NSString stringWithFormat:@"darling-%d", 8];
		NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
		NSString* decoded = [[[NSString alloc] initWithData:data
			encoding:NSUTF8StringEncoding] autorelease];
		if (![decoded isEqualToString:@"darling-8"] || [data length] != 9)
			return fail("Foundation string/data failed\n", 10);

		mark("foundation-smoke: collections\n");
		NSArray* array = [NSArray arrayWithObjects:@"alpha", @"beta", nil];
		NSDictionary* dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
			array, @"items", [NSNumber numberWithInt:8], @"stage", nil];
		if ([array count] != 2 || [[dictionary objectForKey:@"stage"] intValue] != 8)
			return fail("Foundation collections failed\n", 11);

		mark("foundation-smoke: map table\n");
		NSObject* mapKey = [[[NSObject alloc] init] autorelease];
		NSObject* mapValue = [[[NSObject alloc] init] autorelease];
		NSMapTable* map = [[[NSMapTable alloc]
			initWithKeyOptions:NSPointerFunctionsStrongMemory
			valueOptions:NSPointerFunctionsStrongMemory
			capacity:16] autorelease];
		[map setObject:mapValue forKey:mapKey];
		if ([map count] != 1 || [map objectForKey:mapKey] != mapValue ||
			[[[map keyEnumerator] allObjects] count] != 1)
			return fail("Foundation strong map table failed\n", 23);

		mark("foundation-smoke: invocation\n");
		Stage8InvocationTarget* invocationTarget = [[[Stage8InvocationTarget alloc] init] autorelease];
		NSMethodSignature* signature = [invocationTarget methodSignatureForSelector:@selector(add:to:)];
		NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
		long left = 4;
		long right = 5;
		[invocation setTarget:invocationTarget];
		[invocation setSelector:@selector(add:to:)];
		[invocation setArgument:&left atIndex:2];
		[invocation setArgument:&right atIndex:3];
		[invocation invoke];
		long invocationResult = 0;
		[invocation getReturnValue:&invocationResult];
		if (invocationResult != 17)
			return fail("Foundation direct invocation failed\n", 21);

		Stage8Forwarder* forwarder = [[[Stage8Forwarder alloc] init] autorelease];
		SEL forwardedSelector = sel_registerName("forwardedAdd:to:");
		long (*sendForwarded)(id, SEL, long, long) = (void*)objc_msgSend;
		if (sendForwarded(forwarder, forwardedSelector, 6, 7) != 93)
			return fail("Foundation invocation forwarding failed\n", 22);

		mark("foundation-smoke: json\n");
		NSError* error = nil;
		NSData* json = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
		NSDictionary* jsonObject = [NSJSONSerialization JSONObjectWithData:json options:0 error:&error];
		if (!json || error || ![[jsonObject objectForKey:@"items"] isEqualToArray:array])
			return fail("Foundation JSON round trip failed\n", 12);

		mark("foundation-smoke: plist\n");
		NSData* plist = [NSPropertyListSerialization dataWithPropertyList:dictionary
			format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
		mark("foundation-smoke: plist encoded\n");
		NSDictionary* plistObject = [NSPropertyListSerialization propertyListWithData:plist
			options:NSPropertyListImmutable format:NULL error:&error];
		mark("foundation-smoke: plist decoded\n");
		if (!plist || error || [[plistObject objectForKey:@"stage"] intValue] != 8 ||
			![[plistObject objectForKey:@"items"] isEqualToArray:array])
			return fail("Foundation property-list round trip failed\n", 13);

		mark("foundation-smoke: files\n");
		NSString* path = @"/private/var/tmp/darling-stage8-foundation.txt";
		if (![data writeToFile:path options:0 error:&error])
			return fail("Foundation file write failed\n", 14);
		mark("foundation-smoke: file written\n");
		NSData* fileData = [NSData dataWithContentsOfFile:path options:0 error:&error];
		mark("foundation-smoke: file read\n");
		if ([fileData length] != [data length] ||
			memcmp([fileData bytes], [data bytes], [data length]) != 0)
			return fail("Foundation file-manager round trip failed\n", 15);
		mark("foundation-smoke: file compared\n");
		if (![[NSFileManager defaultManager] fileExistsAtPath:path] ||
			unlink([path fileSystemRepresentation]) != 0)
			return fail("Foundation file-manager existence/cleanup failed\n", 15);
		mark("foundation-smoke: file removed\n");

		mark("foundation-smoke: defaults\n");
		NSUserDefaults* defaults = [[[NSUserDefaults alloc]
			initWithSuiteName:@"org.darlinghq.stage8"] autorelease];
		[defaults setInteger:81 forKey:@"value"];
		if ([defaults integerForKey:@"value"] != 81)
			return fail("Foundation user defaults failed\n", 16);
		[defaults removeObjectForKey:@"value"];

		mark("foundation-smoke: notifications\n");
		Stage8Observer* observer = [[[Stage8Observer alloc] init] autorelease];
		NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
		[center addObserver:observer selector:@selector(received:)
			name:@"Stage8Notification" object:nil];
		[center postNotificationName:@"Stage8Notification" object:nil];
		[center removeObserver:observer];
		if (notification_count != 1)
			return fail("Foundation notification center failed\n", 17);

		mark("foundation-smoke: timer\n");
		NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
		NSTimer* timer = [NSTimer timerWithTimeInterval:1.0
			target:observer selector:@selector(timerFired:) userInfo:nil repeats:NO];
		[timer fire];
		if (!runLoop || timer_count != 1)
			return fail("Foundation timer/run loop failed\n", 18);

		mark("foundation-smoke: bundle\n");
		if (![NSBundle mainBundle] || ![[NSBundle mainBundle] bundlePath])
			return fail("Foundation main bundle failed\n", 20);

		static const char success[] = "Darling ARM64 Foundation smoke passed\n";
		write(2, success, sizeof(success) - 1);
	}
	return 0;
}
