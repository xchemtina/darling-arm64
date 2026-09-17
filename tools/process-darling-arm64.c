typedef int pid_t;
typedef long ssize_t;
typedef unsigned long size_t;

extern char** environ;
extern int close(int fd);
extern int dup2(int source, int destination);
extern int execve(const char* path, char* const arguments[], char* const environment[]);
extern void _exit(int status) __attribute__((noreturn));
extern int fcntl(int fd, int command, ...);
extern pid_t fork(void);
extern pid_t getpgid(pid_t pid);
extern pid_t getpid(void);
extern int kill(pid_t pid, int signal);
extern int mkfifo(const char* path, unsigned int mode);
extern int open(const char* path, int flags, ...);
extern int posix_openpt(int flags);
extern int grantpt(int fd);
extern int unlockpt(int fd);
extern int ptsname_r(int fd, char* buffer, size_t length);
extern int pipe(int descriptors[2]);
extern int posix_spawn(pid_t* pid, const char* path, const void* file_actions, const void* attributes, char* const arguments[], char* const environment[]);
extern ssize_t read(int fd, void* buffer, size_t length);
extern int setpgid(pid_t pid, pid_t group);
extern pid_t setsid(void);
extern pid_t getsid(pid_t pid);
extern pid_t tcgetpgrp(int fd);
extern int tcsetpgrp(int fd, pid_t group);
extern void (*signal(int signal, void (*handler)(int)))(int);
extern int unlink(const char* path);
extern pid_t waitpid(pid_t pid, int* status, int options);
extern ssize_t write(int fd, const void* buffer, size_t length);

enum {
	SIGINT_VALUE = 2,
	SIGPIPE_VALUE = 13,
	SIGTERM_VALUE = 15,
	SIGCHLD_VALUE = 20,
	SIGUSR1_VALUE = 30,
	F_GETFD_VALUE = 1,
	F_SETFD_VALUE = 2,
	FD_CLOEXEC_VALUE = 1,
	O_RDONLY_VALUE = 0x0000,
	O_WRONLY_VALUE = 0x0001,
	O_RDWR_VALUE = 0x0002,
	O_NONBLOCK_VALUE = 0x0004,
	O_CREAT_VALUE = 0x0200,
	O_TRUNC_VALUE = 0x0400,
	O_NOCTTY_VALUE = 0x00020000,
};

static volatile int handled_signal = 0;
static volatile int handled_sigchld = 0;

static size_t string_length(const char* string)
{
	size_t length = 0;
	while (string[length] != '\0')
		++length;
	return length;
}

static int strings_equal(const char* left, const char* right)
{
	size_t index = 0;
	while (left[index] != '\0' && right[index] != '\0') {
		if (left[index] != right[index])
			return 0;
		++index;
	}
	return left[index] == right[index];
}

static int bytes_equal(const char* left, const char* right, size_t length)
{
	for (size_t index = 0; index < length; ++index) {
		if (left[index] != right[index])
			return 0;
	}
	return 1;
}

static int parse_positive_integer(const char* string)
{
	int value = 0;
	if (*string == '\0')
		return -1;
	while (*string != '\0') {
		if (*string < '0' || *string > '9')
			return -1;
		value = value * 10 + (*string - '0');
		++string;
	}
	return value;
}

static void format_positive_integer(int value, char buffer[16])
{
	char reversed[16];
	int count = 0;
	int index = 0;

	do {
		reversed[count++] = (char)('0' + value % 10);
		value /= 10;
	} while (value != 0 && count < (int)sizeof(reversed));
	while (count > 0)
		buffer[index++] = reversed[--count];
	buffer[index] = '\0';
}

static int fail(const char* message, int status)
{
	write(2, message, string_length(message));
	return status;
}

static void announce(const char* message)
{
	write(2, message, string_length(message));
}

static int read_marker(int fd, const char* expected)
{
	char buffer[64];
	size_t expected_length = string_length(expected);
	ssize_t received = read(fd, buffer, sizeof(buffer));

	return received == (ssize_t)expected_length && bytes_equal(buffer, expected, expected_length);
}

static int exited_with(int status, int expected)
{
	return (status & 0x7f) == 0 && ((status >> 8) & 0xff) == expected;
}

static int killed_by(int status, int expected)
{
	int signal = status & 0x7f;
	return signal != 0 && signal != 0x7f && signal == expected;
}

static void signal_handler(int signal_number)
{
	if (signal_number == SIGUSR1_VALUE)
		handled_signal = 1;
	if (signal_number == SIGCHLD_VALUE)
		handled_sigchld = 1;
}

static int child_mode(int argc, char** argv)
{
	if (argc >= 2 && strings_equal(argv[1], "--exec-child")) {
		static const char marker[] = "exec-child\n";
		write(2, marker, sizeof(marker) - 1);
		return 23;
	}
	if (argc >= 3 && strings_equal(argv[1], "--cloexec-child")) {
		static const char marker[] = "cloexec-child\n";
		int fd = parse_positive_integer(argv[2]);
		if (fd < 0 || fcntl(fd, F_GETFD_VALUE) != -1)
			return 25;
		write(2, marker, sizeof(marker) - 1);
		return 24;
	}
	return -1;
}

static int test_handled_signal(void)
{
	void (*previous)(int) = signal(SIGUSR1_VALUE, signal_handler);
	if (previous == (void (*)(int))-1)
		return 0;
	if (kill(getpid(), SIGUSR1_VALUE) != 0)
		return 0;
	for (volatile int spin = 0; spin < 1000000 && !handled_signal; ++spin) {
	}
	signal(SIGUSR1_VALUE, previous);
	return handled_signal == 1;
}

static int test_fork_and_wait(void)
{
	static const char marker[] = "fork-child\n";
	int descriptors[2];
	int status = 0;
	pid_t child;

	if (pipe(descriptors) != 0)
		return 0;
	child = fork();
	if (child == 0) {
		close(descriptors[0]);
		write(descriptors[1], marker, sizeof(marker) - 1);
		close(descriptors[1]);
		_exit(17);
	}
	if (child < 0)
		return 0;
	close(descriptors[1]);
	int marker_ok = read_marker(descriptors[0], marker);
	close(descriptors[0]);
	if (!marker_ok || waitpid(child, &status, 0) != child || !exited_with(status, 17))
		return 0;
	return handled_sigchld == 1;
}

static int test_posix_spawn(void)
{
	char* arguments[] = { "/process-darling-arm64", "--exec-child", 0 };
	int status = 0;
	pid_t child = -1;

	if (posix_spawn(&child, arguments[0], 0, 0, arguments, environ) != 0)
		return 0;
	return waitpid(child, &status, 0) == child && exited_with(status, 23);
}

static int test_exec(void)
{
	static const char marker[] = "exec-child\n";
	char* arguments[] = { "/process-darling-arm64", "--exec-child", 0 };
	int descriptors[2];
	int status = 0;
	pid_t child;

	if (pipe(descriptors) != 0)
		return 0;
	child = fork();
	if (child == 0) {
		close(descriptors[0]);
		if (dup2(descriptors[1], 2) < 0)
			_exit(126);
		close(descriptors[1]);
		execve(arguments[0], arguments, environ);
		_exit(127);
	}
	if (child < 0)
		return 0;
	close(descriptors[1]);
	int marker_ok = read_marker(descriptors[0], marker);
	close(descriptors[0]);
	return marker_ok && waitpid(child, &status, 0) == child && exited_with(status, 23);
}

static int test_close_on_exec(void)
{
	static const char marker[] = "cloexec-child\n";
	static const char path[] = "/private/var/tmp/darling-arm64-cloexec.txt";
	char descriptor_string[16];
	char* arguments[] = { "/process-darling-arm64", "--cloexec-child", descriptor_string, 0 };
	int output[2];
	int status = 0;
	int fd = open(path, O_RDWR_VALUE | O_CREAT_VALUE | O_TRUNC_VALUE, 0600);
	pid_t child;

	if (fd < 0 || fcntl(fd, F_SETFD_VALUE, FD_CLOEXEC_VALUE) != 0 || pipe(output) != 0)
		return 0;
	format_positive_integer(fd, descriptor_string);
	child = fork();
	if (child == 0) {
		close(output[0]);
		if (dup2(output[1], 2) < 0)
			_exit(126);
		close(output[1]);
		execve(arguments[0], arguments, environ);
		_exit(127);
	}
	if (child < 0)
		return 0;
	close(output[1]);
	int marker_ok = read_marker(output[0], marker);
	close(output[0]);
	close(fd);
	unlink(path);
	return marker_ok && waitpid(child, &status, 0) == child && exited_with(status, 24);
}

static int test_named_pipe(void)
{
	static const char path[] = "/private/var/tmp/darling-arm64-process.fifo";
	static const char marker[] = "fifo-data\n";
	char buffer[sizeof(marker)] = { 0 };
	int reader;
	int writer;

	unlink(path);
	if (mkfifo(path, 0600) != 0)
		return 0;
	reader = open(path, O_RDONLY_VALUE | O_NONBLOCK_VALUE);
	writer = open(path, O_WRONLY_VALUE | O_NONBLOCK_VALUE);
	if (reader < 0 || writer < 0)
		return 0;
	int passed = write(writer, marker, sizeof(marker) - 1) == sizeof(marker) - 1 &&
		read(reader, buffer, sizeof(buffer)) == sizeof(marker) - 1 &&
		bytes_equal(buffer, marker, sizeof(marker) - 1);
	close(writer);
	close(reader);
	unlink(path);
	return passed;
}

static int test_signal_termination(int signal_number)
{
	int status = 0;
	pid_t child = fork();
	if (child == 0) {
		for (;;) {
		}
	}
	if (child < 0)
		return 0;
	if (kill(child, signal_number) != 0)
		return 0;
	pid_t waited = waitpid(child, &status, 0);
	return waited == child && killed_by(status, signal_number);
}

static int test_session(void)
{
	int status = 0;
	pid_t child = fork();
	if (child == 0) {
		pid_t session = setsid();
		_exit(session == getpid() && getsid(0) == session ? 18 : 28);
	}
	return child > 0 && waitpid(child, &status, 0) == child && exited_with(status, 18);
}

static int test_foreground_terminal(void)
{
	int master = -1;
	int slave = -1;
	int status = 0;
	char slave_name[128];

	master = posix_openpt(O_RDWR_VALUE | O_NOCTTY_VALUE);
	if (master < 0) {
		announce("process-smoke: posix_openpt failed\n");
		return 0;
	}
	if (grantpt(master) != 0) {
		announce("process-smoke: grantpt failed\n");
		return 0;
	}
	if (unlockpt(master) != 0) {
		announce("process-smoke: unlockpt failed\n");
		return 0;
	}
	if (ptsname_r(master, slave_name, sizeof(slave_name)) != 0) {
		announce("process-smoke: ptsname_r failed\n");
		return 0;
	}
	slave = open(slave_name, O_RDWR_VALUE | O_NOCTTY_VALUE);
	if (slave < 0) {
		announce("process-smoke: PTY slave open failed\n");
		return 0;
	}
	announce("process-smoke: PTY allocated\n");
	pid_t child = fork();
	if (child == 0) {
		close(slave);
		pid_t session = setsid();
		pid_t process = getpid();
		if (session != process)
			_exit(51);
		slave = open(slave_name, O_RDWR_VALUE);
		if (slave < 0)
			_exit(52);
		close(master);
		if (tcsetpgrp(slave, process) != 0)
			_exit(53);
		if (tcgetpgrp(slave) != process)
			_exit(54);
		close(slave);
		_exit(19);
	}
	close(slave);
	if (child <= 0 || waitpid(child, &status, 0) != child) {
		close(master);
		return 0;
	}
	close(master);
	if (!exited_with(status, 19)) {
		char status_buffer[16];
		format_positive_integer((status >> 8) & 0xff, status_buffer);
		announce("process-smoke: PTY child status ");
		announce(status_buffer);
		announce("\n");
		return 0;
	}
	return 1;
}

static int test_sigpipe(void)
{
	int descriptors[2];
	int status = 0;
	pid_t child;

	if (pipe(descriptors) != 0)
		return 0;
	close(descriptors[0]);
	child = fork();
	if (child == 0) {
		signal(SIGPIPE_VALUE, (void (*)(int))0);
		write(descriptors[1], "x", 1);
		_exit(26);
	}
	if (child < 0)
		return 0;
	close(descriptors[1]);
	return waitpid(child, &status, 0) == child && killed_by(status, SIGPIPE_VALUE);
}

static int test_process_group(void)
{
	static const char ready[] = "ready\n";
	int descriptors[2];
	int status = 0;
	pid_t child;

	if (pipe(descriptors) != 0)
		return 0;
	child = fork();
	if (child == 0) {
		close(descriptors[0]);
		if (setpgid(0, 0) != 0)
			_exit(27);
		write(descriptors[1], ready, sizeof(ready) - 1);
		for (;;) {
		}
	}
	if (child < 0)
		return 0;
	close(descriptors[1]);
	int ready_ok = read_marker(descriptors[0], ready);
	close(descriptors[0]);
	if (!ready_ok || getpgid(child) != child || kill(child, SIGTERM_VALUE) != 0)
		return 0;
	return waitpid(child, &status, 0) == child && killed_by(status, SIGTERM_VALUE);
}

int main(int argc, char** argv)
{
	static const char success[] = "Darling ARM64 process smoke passed\n";
	int child_result = child_mode(argc, argv);
	if (child_result >= 0)
		return child_result;
	if (signal(SIGCHLD_VALUE, signal_handler) == (void (*)(int))-1)
		return fail("SIGCHLD handler setup failed\n", 29);

	announce("process-smoke: handled signal\n");
	if (!test_handled_signal())
		return fail("handled signal failed\n", 30);
	announce("process-smoke: fork/wait\n");
	if (!test_fork_and_wait())
		return fail("fork/wait failed\n", 31);
	announce("process-smoke: exec\n");
	if (!test_exec())
		return fail("exec failed\n", 32);
	announce("process-smoke: close-on-exec\n");
	if (!test_close_on_exec())
		return fail("close-on-exec failed\n", 33);
	announce("process-smoke: posix_spawn\n");
	if (!test_posix_spawn())
		return fail("posix_spawn failed\n", 34);
	announce("process-smoke: named pipe\n");
	if (!test_named_pipe())
		return fail("named pipe failed\n", 35);
	announce("process-smoke: session\n");
	if (!test_session())
		return fail("session failed\n", 36);
	announce("process-smoke: foreground terminal\n");
	if (!test_foreground_terminal())
		return fail("foreground terminal failed\n", 37);
	announce("process-smoke: SIGINT\n");
	if (!test_signal_termination(SIGINT_VALUE))
		return fail("SIGINT status failed\n", 38);
	announce("process-smoke: SIGTERM\n");
	if (!test_signal_termination(SIGTERM_VALUE))
		return fail("SIGTERM status failed\n", 39);
	announce("process-smoke: SIGPIPE\n");
	if (!test_sigpipe())
		return fail("SIGPIPE status failed\n", 40);
	announce("process-smoke: process group\n");
	if (!test_process_group())
		return fail("process group failed\n", 41);

	write(2, success, sizeof(success) - 1);
	return 0;
}
