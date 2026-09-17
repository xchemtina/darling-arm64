#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTask.h>

extern long write(int fd, const void* buffer, unsigned long length);
extern int usleep(unsigned int usec);

static int handler_called;

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
	@autoreleasepool {
		NSTask* task = [[[NSTask alloc] init] autorelease];
		NSPipe* pipe = [NSPipe pipe];
		[task setLaunchPath:@"/bin/sh"];
		[task setArguments:[NSArray arrayWithObjects:@"-c", @"printf foundation-task-ok", nil]];
		[task setStandardOutput:pipe];
		[task setTerminationHandler:^(NSTask* finishedTask) {
			if ([finishedTask terminationStatus] == 0)
				++handler_called;
		}];
		[task launch];
		[task waitUntilExit];

		NSData* taskData = [[pipe fileHandleForReading] readDataToEndOfFile];
		NSString* taskOutput = [[[NSString alloc] initWithData:taskData
			encoding:NSUTF8StringEncoding] autorelease];
		if ([task terminationStatus] != 0 || handler_called != 1 ||
			![taskOutput isEqualToString:@"foundation-task-ok"])
			return fail("Foundation NSTask/pipe/handler failed\n", 10);

		NSTask* asyncTask = [[[NSTask alloc] init] autorelease];
		[asyncTask setLaunchPath:@"/bin/sh"];
		[asyncTask setArguments:[NSArray arrayWithObjects:@"-c", @"exit 7", nil]];
		__block int asyncStatus = -1;
		[asyncTask launch];
		[asyncTask setTerminationHandler:^(NSTask* finishedTask) {
			asyncStatus = [finishedTask terminationStatus];
		}];
		for (int attempt = 0; attempt < 5000 && asyncStatus < 0; ++attempt)
			usleep(1000);
		if (asyncStatus != 7)
			return fail("Foundation asynchronous NSTask handler failed\n", 11);

		static const char success[] = "Darling ARM64 Foundation task smoke passed\n";
		write(2, success, sizeof(success) - 1);
	}
	return 0;
}
