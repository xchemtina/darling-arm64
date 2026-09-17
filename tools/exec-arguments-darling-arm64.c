typedef unsigned long size_t;

extern char** environ;
extern char* getenv(const char* name);
extern int execve(const char* path, char* const arguments[], char* const environment[]);
extern long write(int fd, const void* buffer, size_t length);

static size_t string_length(const char* string)
{
	size_t length = 0;
	while (string[length])
		++length;
	return length;
}

int main(void)
{
	char* path = getenv("DARLING_EXEC_PATH");
	if (!path || path[0] != '/') {
		static const char message[] = "DARLING_EXEC_PATH must be absolute\n";
		write(2, message, sizeof(message) - 1);
		return 64;
	}

	char* arguments[10];
	arguments[0] = path;
	int count = 1;
	static const char* names[] = {
		"DARLING_EXEC_ARG1", "DARLING_EXEC_ARG2", "DARLING_EXEC_ARG3",
		"DARLING_EXEC_ARG4", "DARLING_EXEC_ARG5", "DARLING_EXEC_ARG6",
		"DARLING_EXEC_ARG7", "DARLING_EXEC_ARG8"
	};
	for (size_t index = 0; index < sizeof(names) / sizeof(names[0]); ++index) {
		char* argument = getenv(names[index]);
		if (!argument)
			break;
		arguments[count++] = argument;
	}
	arguments[count] = 0;
	execve(path, arguments, environ);

	static const char prefix[] = "exec failed: ";
	write(2, prefix, sizeof(prefix) - 1);
	write(2, path, string_length(path));
	write(2, "\n", 1);
	return 126;
}
