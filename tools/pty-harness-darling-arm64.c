#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

extern char **environ;
static volatile sig_atomic_t saw_winch;
static int close_descriptors_before_exec;

static void handle_winch(int signal_number)
{
	(void)signal_number;
	saw_winch = 1;
}

static int contains(const char *data, size_t length, const char *needle)
{
	size_t needle_length = strlen(needle);
	for (size_t i = 0; i + needle_length <= length; ++i)
		if (memcmp(data + i, needle, needle_length) == 0)
			return 1;
	return 0;
}

static int write_all(int fd, const char *data, size_t length)
{
	while (length != 0) {
		ssize_t count = write(fd, data, length);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			return 0;
		data += count;
		length -= (size_t)count;
	}
	return 1;
}

static int open_pair(int *master, char *slave_name, size_t capacity)
{
	*master = posix_openpt(O_RDWR | O_NOCTTY);
	return *master >= 0 &&
		fcntl(*master, F_SETFD, fcntl(*master, F_GETFD) | FD_CLOEXEC) == 0 &&
		grantpt(*master) == 0 && unlockpt(*master) == 0 &&
		ptsname_r(*master, slave_name, capacity) == 0;
}

static pid_t spawn_shell(int master, const char *slave_name, const char *command)
{
	pid_t child = fork();
	if (child != 0)
		return child;
	if (setsid() < 0)
		_exit(120);
	int slave = open(slave_name, O_RDWR);
	if (slave < 0 || tcsetpgrp(slave, getpid()) != 0)
		_exit(121);
	close(master);
	if (dup2(slave, STDIN_FILENO) < 0 || dup2(slave, STDOUT_FILENO) < 0 ||
		dup2(slave, STDERR_FILENO) < 0)
		_exit(122);
	if (slave > STDERR_FILENO)
		close(slave);
	if (close_descriptors_before_exec) {
		int descriptor_limit = getdtablesize();
		for (int descriptor = STDERR_FILENO + 1; descriptor < descriptor_limit; ++descriptor)
			close(descriptor);
	}
	setenv("TERM", "xterm-256color", 1);
	char *const arguments[] = { "/bin/sh", "-c", (char *)command, NULL };
	execve(arguments[0], arguments, environ);
	_exit(127);
}

static int interactive_session(void)
{
	char slave_name[128];
	char output[32768];
	size_t used = 0;
	int master = -1;
	int status = 0;
	struct winsize initial = { 24, 80, 0, 0 };
	if (!open_pair(&master, slave_name, sizeof(slave_name)) ||
		ioctl(master, TIOCSWINSZ, &initial) != 0)
		return 0;

	int slave = open(slave_name, O_RDWR | O_NOCTTY);
	struct termios saved;
	if (slave < 0 || tcgetattr(slave, &saved) != 0) {
		close(master);
		return 0;
	}
	struct termios raw = saved;
	raw.c_lflag &= (tcflag_t)~(ICANON | ECHO);
	raw.c_cc[VMIN] = 1;
	raw.c_cc[VTIME] = 0;
	if (tcsetattr(slave, TCSANOW, &raw) != 0 || tcsetattr(slave, TCSANOW, &saved) != 0) {
		close(slave);
		close(master);
		return 0;
	}
	close(slave);

	const char *script =
		"echo PTY:READY:$0; read value; echo PTY:INPUT:$value; "
		"printf 'PTY:UTF8:é\\n'; exit 17";
	pid_t child = spawn_shell(master, slave_name, script);
	if (child <= 0) {
		close(master);
		return 0;
	}

	usleep(100000);
	struct winsize resized = { 37, 113, 0, 0 };
	struct winsize observed = { 0, 0, 0, 0 };
	if (ioctl(master, TIOCSWINSZ, &resized) != 0 ||
		ioctl(master, TIOCGWINSZ, &observed) != 0 || observed.ws_row != 37 ||
		observed.ws_col != 113) {
		close(master);
		return 0;
	}
	if (!write_all(master, "north-star\n", 11)) {
		close(master);
		return 0;
	}

	int child_waited = 0;
	for (int attempt = 0; attempt < 100 && used < sizeof(output); ++attempt) {
		fd_set readable;
		FD_ZERO(&readable);
		FD_SET(master, &readable);
		struct timeval timeout = { 0, 100000 };
		if (select(master + 1, &readable, NULL, NULL, &timeout) > 0) {
			ssize_t count = read(master, output + used, sizeof(output) - used);
			if (count > 0)
				used += (size_t)count;
		}
		if (waitpid(child, &status, WNOHANG) == child) {
			child_waited = 1;
			break;
		}
	}
	close(master);
	if ((!child_waited && waitpid(child, &status, 0) != child) || !WIFEXITED(status) ||
		WEXITSTATUS(status) != 17) {
		write(STDERR_FILENO, output, used);
		return 0;
	}
	int valid = contains(output, used, "PTY:READY:/bin/sh") &&
		contains(output, used, "PTY:INPUT:north-star") &&
		contains(output, used, "PTY:UTF8:é");
	if (!valid)
		write(STDERR_FILENO, output, used);
	return valid;
}

static int signal_winch(void)
{
	int ready[2];
	int status = 0;
	if (pipe(ready) != 0)
		return 0;
	pid_t child = fork();
	if (child == 0) {
		close(ready[0]);
		signal(SIGWINCH, handle_winch);
		write(ready[1], "R", 1);
		close(ready[1]);
		for (int attempt = 0; attempt < 100 && !saw_winch; ++attempt)
			usleep(10000);
		_exit(saw_winch ? 0 : 1);
	}
	close(ready[1]);
	char marker;
	int ready_ok = read(ready[0], &marker, 1) == 1;
	close(ready[0]);
	if (!ready_ok || kill(child, SIGWINCH) != 0 || waitpid(child, &status, 0) != child)
		return 0;
	return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int multiple_session_eof(void)
{
	char first_slave[128];
	char second_slave[128];
	int first_master = -1;
	int second_master = -1;
	int first_status = 0;
	int second_status = 0;
	char output[4096];
	size_t used = 0;
	int first_eof = 0;
	int first_exception = 0;

	if (!open_pair(&first_master, first_slave, sizeof(first_slave)))
		return 0;
	pid_t first = spawn_shell(first_master, first_slave, "read value; exit 23");
	if (first <= 0 || !open_pair(&second_master, second_slave, sizeof(second_slave))) {
		close(first_master);
		return 0;
	}
	pid_t second = spawn_shell(second_master, second_slave,
		"read value; echo PTY:SECOND:$value; exit 24");
	if (second <= 0 || !write_all(first_master, "done\n", 5)) {
		close(first_master);
		close(second_master);
		return 0;
	}
	usleep(100000);

	for (int attempt = 0; attempt < 100 && !first_eof; ++attempt) {
		fd_set readable;
		fd_set exceptional;
		FD_ZERO(&readable);
		FD_ZERO(&exceptional);
		FD_SET(first_master, &readable);
		FD_SET(second_master, &readable);
		FD_SET(first_master, &exceptional);
		struct timeval timeout = { 0, 100000 };
		int maximum = first_master > second_master ? first_master : second_master;
		if (select(maximum + 1, &readable, NULL, &exceptional, &timeout) <= 0)
			continue;
		if (FD_ISSET(first_master, &exceptional))
			first_exception = 1;
		if (FD_ISSET(first_master, &readable)) {
			ssize_t count = read(first_master, output, sizeof(output));
			if (count == 0 || (count < 0 && errno == EIO))
				first_eof = 1;
			else if (count < 0 && errno != EAGAIN && errno != EINTR)
				break;
		}
	}
	int first_waited = waitpid(first, &first_status, WNOHANG) == first;
	int second_early = waitpid(second, NULL, WNOHANG);
	const char *failure = NULL;
	if (!first_eof)
		failure = "PTYHarness: first master did not report EOF\n";
	else if (!first_exception)
		failure = "PTYHarness: first master did not report exceptional EOF readiness\n";
	else if (!first_waited)
		failure = "PTYHarness: first child was not reapable\n";
	else if (!WIFEXITED(first_status) || WEXITSTATUS(first_status) != 23)
		failure = "PTYHarness: first child status was incorrect\n";
	else if (second_early != 0)
		failure = "PTYHarness: second child exited early\n";
	else if (!write_all(second_master, "alive\n", 6))
		failure = "PTYHarness: second master write failed\n";
	if (failure != NULL) {
		write(STDERR_FILENO, failure, strlen(failure));
		close(first_master);
		close(second_master);
		return 0;
	}

	for (int attempt = 0; attempt < 100 && used < sizeof(output); ++attempt) {
		fd_set readable;
		FD_ZERO(&readable);
		FD_SET(second_master, &readable);
		struct timeval timeout = { 0, 100000 };
		if (select(second_master + 1, &readable, NULL, NULL, &timeout) > 0) {
			ssize_t count = read(second_master, output + used, sizeof(output) - used);
			if (count > 0)
				used += (size_t)count;
		}
		if (waitpid(second, &second_status, WNOHANG) == second)
			break;
	}
	close(first_master);
	close(second_master);
	return WIFEXITED(second_status) && WEXITSTATUS(second_status) == 24 &&
		contains(output, used, "PTY:SECOND:alive");
}

static int spawn_cycles(int count)
{
	for (int cycle = 0; cycle < count; ++cycle) {
		char slave_name[128];
		int master = -1;
		int status = 0;
		if (!open_pair(&master, slave_name, sizeof(slave_name)))
			return 0;
		pid_t child = spawn_shell(master, slave_name, "exit 0");
		if (child <= 0 || waitpid(child, &status, 0) != child ||
			!WIFEXITED(status) || WEXITSTATUS(status) != 0)
			return 0;
		close(master);
	}
	return 1;
}

int main(void)
{
	close_descriptors_before_exec = getenv("PTY_HARNESS_CLOSE_DESCRIPTORS") != NULL;
	if (!interactive_session()) {
		const char *message = "PTYHarness: interactive session failed\n";
		write(STDERR_FILENO, message, strlen(message));
		return 1;
	}
	if (!signal_winch()) {
		const char *message = "PTYHarness: SIGWINCH delivery failed\n";
		write(STDERR_FILENO, message, strlen(message));
		return 2;
	}
	if (!multiple_session_eof()) {
		const char *message = "PTYHarness: multiple-session EOF failed\n";
		write(STDERR_FILENO, message, strlen(message));
		return 3;
	}
	if (!spawn_cycles(1000)) {
		const char *message = "PTYHarness: spawn cycle failed\n";
		write(STDERR_FILENO, message, strlen(message));
		return 4;
	}
	const char *message =
		"PTYHarness: interactive, resize, termios, UTF-8, multi-session EOF, and 1000 cycles passed\n";
	write(STDOUT_FILENO, message, strlen(message));
	return 0;
}
