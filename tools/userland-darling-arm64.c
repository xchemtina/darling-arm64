typedef int pid_t;
typedef long ssize_t;
typedef unsigned long size_t;

extern char** environ;
extern int close(int fd);
extern int dup2(int source, int destination);
extern int execve(const char* path, char* const arguments[], char* const environment[]);
extern void _exit(int status) __attribute__((noreturn));
extern pid_t fork(void);
extern int grantpt(int fd);
extern int ioctl(int fd, unsigned long request, ...);
extern int open(const char* path, int flags, ...);
extern int pipe(int descriptors[2]);
extern int posix_openpt(int flags);
extern int ptsname_r(int fd, char* buffer, size_t length);
extern ssize_t read(int fd, void* buffer, size_t length);
extern int setenv(const char* name, const char* value, int overwrite);
extern pid_t setsid(void);
extern int unlink(const char* path);
extern int unlockpt(int fd);
extern pid_t waitpid(pid_t pid, int* status, int options);
extern ssize_t write(int fd, const void* buffer, size_t length);

enum {
	O_RDONLY_VALUE = 0x0000,
	O_WRONLY_VALUE = 0x0001,
	O_RDWR_VALUE = 0x0002,
	O_CREAT_VALUE = 0x0200,
	O_TRUNC_VALUE = 0x0400,
	O_NOCTTY_VALUE = 0x00020000,
	TIOCSWINSZ_VALUE = 0x80087467,
};

struct winsize {
	unsigned short rows;
	unsigned short columns;
	unsigned short xpixel;
	unsigned short ypixel;
};

static int last_wait_status;

static size_t string_length(const char* string)
{
	size_t length = 0;
	while (string[length])
		++length;
	return length;
}

static int bytes_equal(const char* left, const char* right, size_t length)
{
	for (size_t index = 0; index < length; ++index) {
		if (left[index] != right[index])
			return 0;
	}
	return 1;
}

static int contains_bytes(const char* buffer, size_t length, const char* marker)
{
	size_t marker_length = string_length(marker);
	if (marker_length > length)
		return 0;
	for (size_t offset = 0; offset + marker_length <= length; ++offset) {
		if (bytes_equal(buffer + offset, marker, marker_length))
			return 1;
	}
	return 0;
}

static int exited_with(int status, int expected)
{
	return (status & 0x7f) == 0 && ((status >> 8) & 0xff) == expected;
}

static void write_number(int value)
{
	char reversed[16];
	char buffer[16];
	int count = 0;
	int length = 0;
	do {
		reversed[count++] = (char)('0' + value % 10);
		value /= 10;
	} while (value && count < (int)sizeof(reversed));
	while (count)
		buffer[length++] = reversed[--count];
	write(2, buffer, (size_t)length);
}

static int write_all(int fd, const char* buffer, size_t length)
{
	while (length > 0) {
		ssize_t written = write(fd, buffer, length);
		if (written <= 0)
			return 0;
		buffer += written;
		length -= (size_t)written;
	}
	return 1;
}

static ssize_t read_all(int fd, char* buffer, size_t capacity)
{
	size_t used = 0;
	while (used < capacity) {
		ssize_t received = read(fd, buffer + used, capacity - used);
		if (received == 0)
			break;
		if (received < 0)
			return -1;
		used += (size_t)received;
	}
	return (ssize_t)used;
}

static int write_file(const char* path, const char* contents)
{
	int fd = open(path, O_WRONLY_VALUE | O_CREAT_VALUE | O_TRUNC_VALUE, 0600);
	if (fd < 0)
		return 0;
	int passed = write_all(fd, contents, string_length(contents));
	return close(fd) == 0 && passed;
}

static ssize_t read_file(const char* path, char* buffer, size_t capacity)
{
	int fd = open(path, O_RDONLY_VALUE);
	if (fd < 0)
		return -1;
	ssize_t received = read_all(fd, buffer, capacity);
	close(fd);
	return received;
}

static int run_captured(char* const arguments[], const char* input,
		char* output, size_t capacity, int expected_status, ssize_t* output_length)
{
	int input_pipe[2];
	int output_pipe[2];
	int status = 0;
	if (pipe(input_pipe) != 0 || pipe(output_pipe) != 0)
		return 0;

	pid_t child = fork();
	if (child == 0) {
		close(input_pipe[1]);
		close(output_pipe[0]);
		if (dup2(input_pipe[0], 0) < 0 || dup2(output_pipe[1], 1) < 0)
			_exit(126);
		close(input_pipe[0]);
		close(output_pipe[1]);
		execve(arguments[0], arguments, environ);
		_exit(127);
	}
	if (child < 0)
		return 0;

	close(input_pipe[0]);
	close(output_pipe[1]);
	if (input && !write_all(input_pipe[1], input, string_length(input))) {
		close(input_pipe[1]);
		close(output_pipe[0]);
		return 0;
	}
	close(input_pipe[1]);
	*output_length = read_all(output_pipe[0], output, capacity);
	close(output_pipe[0]);
	pid_t waited = waitpid(child, &status, 0);
	last_wait_status = status;
	return *output_length >= 0 && waited == child && exited_with(status, expected_status);
}

static int run_pty(char* const arguments[], const char* input,
		const char* expected_output)
{
	char slave_name[128];
	char output[32768];
	int status = 0;
	int master = posix_openpt(O_RDWR_VALUE | O_NOCTTY_VALUE);
	if (master < 0 || grantpt(master) != 0 || unlockpt(master) != 0 ||
			ptsname_r(master, slave_name, sizeof(slave_name)) != 0)
		return 0;

	struct winsize size = { 24, 80, 0, 0 };
	if (ioctl(master, TIOCSWINSZ_VALUE, &size) != 0)
		return 0;

	pid_t child = fork();
	if (child == 0) {
		if (setsid() < 0)
			_exit(125);
		int slave = open(slave_name, O_RDWR_VALUE);
		if (slave < 0)
			_exit(124);
		close(master);
		if (dup2(slave, 0) < 0 || dup2(slave, 1) < 0 || dup2(slave, 2) < 0)
			_exit(123);
		if (slave > 2)
			close(slave);
		setenv("TERM", "xterm", 1);
		execve(arguments[0], arguments, environ);
		_exit(127);
	}
	if (child < 0)
		return 0;

	if (!write_all(master, input, string_length(input))) {
		close(master);
		return 0;
	}
	ssize_t received = read_all(master, output, sizeof(output));
	close(master);
	if (waitpid(child, &status, 0) != child || !exited_with(status, 0))
		return 0;
	return received >= 0 && (!expected_output ||
		contains_bytes(output, (size_t)received, expected_output));
}

static int fail(const char* message, int status)
{
	write(2, message, string_length(message));
	return status;
}

static void passed(const char* phase)
{
	write(2, phase, string_length(phase));
}

int main(void)
{
	static const char cat_path[] = "/private/var/tmp/stage6-cat.txt";
	static const char vim_path[] = "/private/var/tmp/stage6-vim.txt";
	static const char interactive_vim_path[] = "/private/var/tmp/stage6-vim-interactive.txt";
	static const char cat_contents[] = "cat-line-one\ncat-line-two\n";
	char output[4096];
	ssize_t output_length = 0;
	int null_fd = open("/dev/null", O_RDWR_VALUE);
	if (null_fd < 0 || (null_fd != 0 && dup2(null_fd, 0) < 0) ||
			(null_fd != 1 && dup2(null_fd, 1) < 0))
		return fail("Stage 6 standard descriptor setup failed\n", 9);
	if (null_fd > 1)
		close(null_fd);

	if (!write_file(cat_path, cat_contents))
		return fail("Stage 6 fixture creation failed\n", 10);
	char* cat_arguments[] = { "/bin/cat", (char*)cat_path, 0 };
	if (!run_captured(cat_arguments, 0, output, sizeof(output), 0, &output_length) ||
			output_length != (ssize_t)(sizeof(cat_contents) - 1) ||
			!bytes_equal(output, cat_contents, sizeof(cat_contents) - 1))
		return fail("Darwin cat failed\n", 11);
	passed("userland-smoke: cat\n");

	char* shell_arguments[] = {
		"/bin/sh", "-c",
		"value='shell words'; printf '%s\\n' \"$value\"; "
		"printf 'pipe-data\\n' | /bin/cat; "
		"result=$(printf 'substitution-ok'); "
		"printf '%s\\n' \"$result\"; exit 7",
		0
	};
	static const char shell_output[] = "shell words\npipe-data\nsubstitution-ok\n";
	int shell_ran = run_captured(shell_arguments, 0, output, sizeof(output), 7, &output_length);
	if (output_length > 0)
		write(2, output, (size_t)output_length);
	if (!shell_ran)
	{
		write(2, "shell wait status=", 18);
		write_number(last_wait_status);
		write(2, "\n", 1);
		return fail("Darwin sh/env pipeline execution failed\n", 12);
	}
	if (output_length != (ssize_t)(sizeof(shell_output) - 1) ||
			!bytes_equal(output, shell_output, sizeof(shell_output) - 1))
		return fail("Darwin sh/env pipeline output failed\n", 12);
	passed("userland-smoke: scripted shell\n");

	char* env_arguments[] = {
		"/usr/bin/env", "-i", "TOKEN=env-ok", "/bin/sh", "-c",
		"printf '%s\\n' \"$TOKEN\"", 0
	};
	static const char env_output[] = "env-ok\n";
	if (!run_captured(env_arguments, 0, output, sizeof(output), 0, &output_length) ||
			output_length != (ssize_t)(sizeof(env_output) - 1) ||
			!bytes_equal(output, env_output, sizeof(env_output) - 1))
		return fail("Darwin env execution failed\n", 13);
	passed("userland-smoke: env\n");

	char* vim_quit_arguments[] = {
		"/usr/bin/vim", "-Nu", "NONE", "-n", "-es", "-c", "qa!", 0
	};
	if (!run_captured(vim_quit_arguments, 0, output, sizeof(output), 0, &output_length))
		return fail("Darwin Vim startup failed\n", 14);
	passed("userland-smoke: Vim startup\n");

	if (!write_file(vim_path, "alpha\nsecond line\n"))
		return fail("Vim fixture creation failed\n", 15);
	char* vim_read_arguments[] = {
		"/usr/bin/vim", "-Nu", "NONE", "-n", "-es", "-c", "qa!",
		(char*)vim_path, 0
	};
	if (!run_captured(vim_read_arguments, 0, output, sizeof(output), 0, &output_length))
		return fail("Darwin Vim file read failed\n", 16);
	passed("userland-smoke: Vim file read\n");
	char* vim_batch_arguments[] = {
		"/usr/bin/vim", "-Nu", "NONE", "-n", "-es",
		"-c", "set noswapfile", "-c", "%s/alpha/beta/", "-c", "wq",
		(char*)vim_path, 0
	};
	if (!run_captured(vim_batch_arguments, 0, output, sizeof(output), 0, &output_length))
		return fail("Darwin Vim batch execution failed\n", 17);
	output_length = read_file(vim_path, output, sizeof(output));
	static const char vim_contents[] = "beta\nsecond line\n";
	if (output_length != (ssize_t)(sizeof(vim_contents) - 1) ||
			!bytes_equal(output, vim_contents, sizeof(vim_contents) - 1))
		return fail("Darwin Vim batch edit failed\n", 18);
	passed("userland-smoke: Vim batch\n");

	char* interactive_shell_arguments[] = { "/bin/sh", "-i", 0 };
	if (!run_pty(interactive_shell_arguments,
			"printf 'interactive-shell-ok\\n'\nexit\n", "interactive-shell-ok"))
		return fail("Darwin interactive shell failed\n", 19);
	passed("userland-smoke: interactive shell\n");

	unlink(interactive_vim_path);
	char* interactive_vim_arguments[] = {
		"/usr/bin/vim", "-Nu", "NONE", "-n", (char*)interactive_vim_path, 0
	};
	if (!run_pty(interactive_vim_arguments, "iinteractive-vim-ok\033:wq\r", 0))
		return fail("Darwin interactive Vim session failed\n", 20);
	output_length = read_file(interactive_vim_path, output, sizeof(output));
	static const char interactive_vim_contents[] = "interactive-vim-ok\n";
	if (output_length != (ssize_t)(sizeof(interactive_vim_contents) - 1) ||
			!bytes_equal(output, interactive_vim_contents,
				sizeof(interactive_vim_contents) - 1))
		return fail("Darwin interactive Vim edit failed\n", 21);
	passed("userland-smoke: interactive Vim\n");

	unlink(cat_path);
	unlink(vim_path);
	unlink(interactive_vim_path);
	static const char success[] = "Darling ARM64 userland smoke passed\n";
	write(2, success, sizeof(success) - 1);
	return 0;
}
