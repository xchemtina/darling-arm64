typedef unsigned long size_t;
typedef long ssize_t;
typedef long off_t;

struct timeval {
	long tv_sec;
	int tv_usec;
};

extern int access(const char* path, int mode);
extern int close(int fd);
extern int fstat(int fd, void* status);
extern int getpid(void);
extern int gettimeofday(struct timeval* time, void* timezone);
extern int lstat(const char* path, void* status);
extern off_t lseek(int fd, off_t offset, int whence);
extern void* mmap(void* address, size_t length, int protection, int flags, int fd, off_t offset);
extern int munmap(void* address, size_t length);
extern int open(const char* path, int flags, ...);
extern ssize_t read(int fd, void* buffer, size_t length);
extern int unlink(const char* path);
extern ssize_t write(int fd, const void* buffer, size_t length);

static int fail(const char* message, size_t length, int status)
{
	write(2, message, length);
	return status;
}

int main(void)
{
	static const char path[] = "/private/var/tmp/darling-arm64-posix.txt";
	static const char payload[] = "darling-posix-data";
	static const char success[] = "Darling ARM64 POSIX smoke passed\n";
	char buffer[sizeof(payload)] = { 0 };
	long stat_buffer[32] = { 0 };
	struct timeval time = { 0 };
	int fd;

	if (getpid() <= 0)
		return fail("getpid failed\n", 14, 10);
	if (gettimeofday(&time, 0) != 0 || time.tv_sec <= 0)
		return fail("gettimeofday failed\n", 20, 11);

	fd = open(path, 0x0002 | 0x0200 | 0x0400, 0600);
	if (fd < 0)
		return fail("open failed\n", 12, 12);
	if (write(fd, payload, sizeof(payload)) != sizeof(payload))
		return fail("file write failed\n", 18, 13);
	if (fstat(fd, stat_buffer) != 0)
		return fail("fstat failed\n", 13, 14);
	if (lseek(fd, 0, 0) != 0)
		return fail("lseek failed\n", 13, 15);
	if (read(fd, buffer, sizeof(buffer)) != sizeof(buffer))
		return fail("read failed\n", 12, 16);
	for (size_t i = 0; i < sizeof(payload); ++i) {
		if (buffer[i] != payload[i])
			return fail("file data mismatch\n", 19, 17);
	}
	if (lseek(fd, 4096, 0) != 4096)
		return fail("file mmap seek failed\n", 22, 18);
	if (write(fd, payload, sizeof(payload)) != sizeof(payload))
		return fail("file mmap write failed\n", 23, 19);
	char* file_mapping = mmap(0, 4096, 0x1, 0x0002, fd, 4096);
	if (file_mapping == (void*)-1)
		return fail("file mmap failed\n", 17, 20);
	for (size_t i = 0; i < sizeof(payload); ++i) {
		if (file_mapping[i] != payload[i])
			return fail("file mmap mismatch\n", 19, 21);
	}
	if (munmap(file_mapping, 4096) != 0)
		return fail("file munmap failed\n", 19, 22);
	if (close(fd) != 0)
		return fail("close failed\n", 13, 23);
	if (access(path, 0) != 0)
		return fail("access failed\n", 14, 24);
	if (lstat(path, stat_buffer) != 0)
		return fail("lstat existing failed\n", 22, 25);
	if (unlink(path) != 0)
		return fail("unlink failed\n", 14, 26);
	if (lstat(path, stat_buffer) == 0)
		return fail("lstat missing succeeded\n", 24, 27);

	char* mapping = mmap(0, 4096, 0x1 | 0x2, 0x0002 | 0x1000, -1, 0);
	if (mapping == (void*)-1)
		return fail("mmap failed\n", 12, 28);
	mapping[0] = 'D';
	mapping[4095] = 'G';
	if (munmap(mapping, 4096) != 0)
		return fail("munmap failed\n", 14, 29);

	write(2, success, sizeof(success) - 1);
	return 0;
}
