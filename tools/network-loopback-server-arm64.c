#include <arpa/inet.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int main(void)
{
	static const char expected[] = "GET /stage9 HTTP/1.1\r\n";
	static const char reply[] =
		"HTTP/1.1 200 OK\r\n"
		"Content-Length: 15\r\n"
		"Connection: close\r\n"
		"\r\n"
		"stage9-http-ok\n";
	int listener = socket(AF_INET, SOCK_STREAM, 0);
	if (listener < 0)
		return 10;
	int reuse = 1;
	setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
	struct sockaddr_in address;
	memset(&address, 0, sizeof(address));
	address.sin_family = AF_INET;
	address.sin_port = htons(39091);
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	if (bind(listener, (struct sockaddr*)&address, sizeof(address)) != 0 ||
		listen(listener, 1) != 0)
		return 11;
	static const char ready[] = "ready\n";
	write(1, ready, sizeof(ready) - 1);
	int client = accept(listener, NULL, NULL);
	if (client < 0)
		return 12;
	char request[512];
	ssize_t count = read(client, request, sizeof(request));
	if (count < (ssize_t)(sizeof(expected) - 1) ||
		memcmp(request, expected, sizeof(expected) - 1) != 0)
		return 13;
	if (write(client, reply, sizeof(reply) - 1) != (ssize_t)(sizeof(reply) - 1))
		return 14;
	close(client);
	close(listener);
	return 0;
}
