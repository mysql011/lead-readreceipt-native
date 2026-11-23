#import "GRRFishhookBridge.h"
#import "GRRSettings.h"
#import "GRRStorage.h"
#if __has_include(<fishhook.h>)
#import <fishhook.h>
#define GRR_HAS_FISHHOOK 1
#else
#define GRR_HAS_FISHHOOK 0
#endif

static void (*GRROriginalNSLog)(NSString *format, ...) = NULL;

__attribute__((unused)) static void GRRHookedNSLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = format ? [[NSString alloc] initWithFormat:format arguments:arguments] : @"";
    va_end(arguments);

    if ([GRRSettings shared].captureHostLog && message.length) {
        NSString *detail = message.length > 200 ? [message substringToIndex:200] : message;
        [[GRRStorage shared] logAction:@"host" code:0 chatId:@"" msgId:@"" detail:detail];
    }
    if (GRROriginalNSLog) GRROriginalNSLog(@"%@", message);
}

@implementation GRRFishhookBridge

+ (void)install {
#if GRR_HAS_FISHHOOK
    struct rebinding rebinding;
    rebinding.name = "NSLog";
    rebinding.replacement = (void *)GRRHookedNSLog;
    rebinding.replaced = (void **)&GRROriginalNSLog;
    rebind_symbols(&rebinding, 1);
    [[GRRStorage shared] logAction:@"fishhook" code:200 chatId:@"" msgId:@"" detail:@"NSLog rebound"];
#else
    (void)GRROriginalNSLog;
    [[GRRStorage shared] logAction:@"fishhook" code:0 chatId:@"" msgId:@"" detail:@"header-missing-skipped"];
#endif
}

@end
