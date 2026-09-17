extern long write(int fd, const void* buffer, unsigned long length);

#ifndef DARLING_SMOKE_EXIT_CODE
#define DARLING_SMOKE_EXIT_CODE 0
#endif

int main(void)
{
	static const char message[] = "hello from native Darling arm64\n";

	write(2, message, sizeof(message) - 1);
	return DARLING_SMOKE_EXIT_CODE;
}
