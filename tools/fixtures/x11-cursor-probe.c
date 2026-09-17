#include <X11/Xlib.h>
#include <X11/Xcursor/Xcursor.h>
#include <X11/extensions/Xfixes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int printCursorSignature(Display *display)
{
	XFixesCursorImage *image = XFixesGetCursorImage(display);
	if (image == NULL)
		return 3;
	uint64_t hash = UINT64_C(1469598103934665603);
	for (size_t index = 0; index < (size_t)image->width * image->height; ++index) {
		hash ^= image->pixels[index] & UINT32_MAX;
		hash *= UINT64_C(1099511628211);
	}
	printf("%ux%u+%u+%u:%016llx\n", image->width, image->height,
		image->xhot, image->yhot, (unsigned long long)hash);
	XFree(image);
	return 0;
}

int main(int argc, char **argv)
{
	Display *display = XOpenDisplay(NULL);
	if (display == NULL)
		return 2;

	int status = 0;
	if (argc == 2 && strcmp(argv[1], "--current") == 0) {
		status = printCursorSignature(display);
	} else if (argc == 3 && strcmp(argv[1], "--reference") == 0) {
		Window window = XCreateSimpleWindow(display, DefaultRootWindow(display),
			0, 0, 32, 32, 0, 0, 0);
		Cursor cursor = XcursorLibraryLoadCursor(display, argv[2]);
		if (cursor == None) {
			XDestroyWindow(display, window);
			XCloseDisplay(display);
			return 4;
		}
		XDefineCursor(display, window, cursor);
		XMapRaised(display, window);
		XWarpPointer(display, None, window, 0, 0, 0, 0, 1, 1);
		XSync(display, False);
		status = printCursorSignature(display);
		XFreeCursor(display, cursor);
		XDestroyWindow(display, window);
	} else if (argc == 2 && strcmp(argv[1], "--grab") == 0) {
		int result = XGrabPointer(display, DefaultRootWindow(display), False,
			PointerMotionMask, GrabModeAsync, GrabModeAsync, None, None,
			CurrentTime);
		printf("%d\n", result);
		if (result == GrabSuccess)
			XUngrabPointer(display, CurrentTime);
		XSync(display, False);
	} else {
		XCloseDisplay(display);
		return 2;
	}

	XCloseDisplay(display);
	return status;
}
