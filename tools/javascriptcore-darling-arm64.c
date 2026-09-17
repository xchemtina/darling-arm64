typedef const struct OpaqueJSContext* JSContextRef;
typedef struct OpaqueJSContext* JSGlobalContextRef;
typedef struct OpaqueJSString* JSStringRef;
typedef const struct OpaqueJSValue* JSValueRef;

extern JSGlobalContextRef JSGlobalContextCreate(void* global_object_class);
extern void JSGlobalContextRelease(JSGlobalContextRef context);
extern JSStringRef JSStringCreateWithUTF8CString(const char* string);
extern void JSStringRelease(JSStringRef string);
extern JSValueRef JSEvaluateScript(JSContextRef context, JSStringRef script,
	JSValueRef this_object, JSStringRef source_url, int starting_line_number,
	JSValueRef* exception);
extern double JSValueToNumber(JSContextRef context, JSValueRef value,
	JSValueRef* exception);

int main(void)
{
	JSGlobalContextRef context = JSGlobalContextCreate((void*)0);
	JSStringRef source = JSStringCreateWithUTF8CString("6 * 7");
	JSValueRef exception = (JSValueRef)0;
	JSValueRef value = JSEvaluateScript(context, source, (JSValueRef)0,
		(JSStringRef)0, 1, &exception);
	int passed = exception == (JSValueRef)0 && value != (JSValueRef)0
		&& JSValueToNumber(context, value, (JSValueRef*)0) == 42.0;

	JSStringRelease(source);
	JSGlobalContextRelease(context);
	return passed ? 0 : 1;
}
