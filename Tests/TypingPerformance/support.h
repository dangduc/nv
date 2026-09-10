#import <mach/mach.h>
#import <mach/mach_time.h>

static BOOL Measuring;
static NSUInteger FullRefreshes, HeaderWrites, HighlightRequests;
static double TimeNow(void) {
    static mach_timebase_info_data_t scale;
    if (!scale.denom) mach_timebase_info(&scale);
    return mach_absolute_time() * (double)scale.numer / scale.denom / 1e9;
}
static void WaitForUI(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
static void Require(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"TypingBenchmarkFailure" format:@"%@", message];
}
static double MainCPU(void) {
    thread_basic_info_data_t info;
    mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
    mach_port_t thread = mach_thread_self();
    kern_return_t status = thread_info(thread, THREAD_BASIC_INFO, (thread_info_t)&info, &count);
    mach_port_deallocate(mach_task_self(), thread);
    Require(status == KERN_SUCCESS, @"main CPU clock is available");
    return info.user_time.seconds + info.system_time.seconds +
        (info.user_time.microseconds + info.system_time.microseconds) / 1e6;
}
static NSString *Fixture(NSUInteger size, BOOL longLine) {
    NSString *unit = longLine ? @"plain text diagnostic sample with repeated words and spaces. " :
        @"plain text diagnostic sample with repeated words and spaces.\n";
    NSMutableString *text = [NSMutableString string];
    while (text.length < size) [text appendString:unit];
    [text deleteCharactersInRange:NSMakeRange(size, text.length - size)];
    return text;
}
