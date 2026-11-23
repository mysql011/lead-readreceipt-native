#import "GRRHookRegistry.h"
#import "GRRMessageContext.h"
#import "GRRNetwork.h"
#import "GRRStorage.h"
#import "GRRVisibilityTracker.h"
#import "GRRUI.h"
#import <substrate.h>
#import <objc/runtime.h>

static NSMutableDictionary<NSString *, NSValue *> *GRROriginalIMP = nil;
static NSMutableDictionary<NSString *, NSString *> *GRRKindMap = nil;
static NSMutableArray<NSString *> *GRRInstalled = nil;
static NSMutableArray<NSString *> *GRRFailed = nil;

static NSString *GRRKey(Class cls, SEL cmd) {
    return [NSString stringWithFormat:@"%@|%@", NSStringFromClass(cls), NSStringFromSelector(cmd)];
}

static IMP GRROriginalFor(id receiver, SEL cmd) {
    NSString *selectorName = NSStringFromSelector(cmd);
    NSString *exact = GRRKey([receiver class], cmd);
    NSValue *value = GRROriginalIMP[exact];
    if (!value) {
        for (NSString *key in GRROriginalIMP) {
            if ([key hasSuffix:[NSString stringWithFormat:@"|%@", selectorName]]) {
                value = GRROriginalIMP[key];
                break;
            }
        }
    }
    return value ? (IMP)value.pointerValue : NULL;
}

static NSString *GRRKindFor(id receiver, SEL cmd) {
    NSString *selectorName = NSStringFromSelector(cmd);
    NSString *kind = GRRKindMap[GRRKey([receiver class], cmd)];
    if (kind) return kind;
    for (NSString *key in GRRKindMap) {
        if ([key hasSuffix:[NSString stringWithFormat:@"|%@", selectorName]]) return GRRKindMap[key];
    }
    return nil;
}

static UIView *GRRFindView(id receiver, id arg1, id arg2) {
    if ([receiver isKindOfClass:[UIView class]]) return (UIView *)receiver;
    if ([arg1 isKindOfClass:[UIView class]]) return (UIView *)arg1;
    if ([arg2 isKindOfClass:[UIView class]]) return (UIView *)arg2;
    if ([receiver respondsToSelector:@selector(view)]) {
        id view = [receiver performSelector:@selector(view)];
        if ([view isKindOfClass:[UIView class]]) return (UIView *)view;
    }
    return nil;
}

static NSString *GRRReceiptCommand(NSString *text) {
    if (!text.length) return nil;
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*/receipt\\s+(on|off)\\b"
                                                                        options:NSRegularExpressionCaseInsensitive
                                                                          error:&error];
    if (!regex) return nil;
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match || match.numberOfRanges < 2) return nil;
    return [text substringWithRange:[match rangeAtIndex:1]].lowercaseString;
}

static BOOL GRRHandleGroupCommand(id receiver, GRRMessageInfo *info) {
    NSString *command = GRRReceiptCommand(info.text);
    if (!command) return NO;

    id adminValue = [GRRMessageContext valueForKeyPaths:@[@"sender.isAdmin", @"from.isAdmin",
                                                          @"sender.isChannelAdmin", @"isAdmin",
                                                          @"isGroupAdmin", @"isChannelAdmin"]
                                               onObject:receiver];
    BOOL isAdmin = [adminValue respondsToSelector:@selector(boolValue)] ? [adminValue boolValue] : NO;
    if (!isAdmin) {
        [[GRRStorage shared] logAction:@"groupSwitch" code:403 chatId:info.chatId msgId:info.msgId detail:@"not-admin"];
        return YES;
    }

    BOOL enabled = [command isEqualToString:@"on"];
    [[GRRStorage shared] setGroup:info.chatId off:!enabled];
    if (!enabled) {
        [[GRRUI shared] removeFootersForChat:info.chatId];
        [[GRRVisibilityTracker shared] untrackChat:info.chatId];
    }
    [[GRRNetwork shared] groupSwitch:info.chatId enabled:enabled operatorUserId:info.senderId completion:^(BOOL success) {
        [[GRRStorage shared] logAction:@"groupSwitch" code:success ? 200 : 0
                               chatId:info.chatId msgId:info.msgId detail:command];
    }];
    return YES;
}

static void GRRRunHook(id receiver, SEL cmd, id arg1, id arg2, id result) {
    NSString *kind = GRRKindFor(receiver, cmd);
    if (!kind) return;

    if ([kind isEqualToString:@"Identity"]) {
        NSString *userId = [[GRRNetwork shared] currentUserId] ?: @"";
        if (!userId.length) {
            id value = [GRRMessageContext valueForKeyPaths:@[@"id", @"userId", @"uid"] onObject:result];
            userId = [GRRMessageContext stringFromObject:value];
        }
        if (userId.length) [GRRNetwork shared].currentUserId = userId;
        return;
    }

    GRRMessageInfo *info = [GRRMessageContext resolveFromObject:arg1 ?: receiver];
    if (!info || !info.msgId.length) info = [GRRMessageContext resolveFromObject:receiver];
    if (!info) return;

    if ([kind isEqualToString:@"Render"]) {
        if (![info isEligibleChat]) return;
        if (GRRHandleGroupCommand(receiver, info)) return;
        UIView *view = GRRFindView(receiver, arg1, arg2);
        if (!view) return;
        [GRRMessageContext attach:info toView:view];
        [[GRRVisibilityTracker shared] trackView:view info:info];
        [[GRRUI shared] refreshFooterForView:view info:info];
        [[GRRNetwork shared] setHeartbeatChatId:info.chatId];
    } else if ([kind isEqualToString:@"LongPress"]) {
        [GRRMessageContext setCurrentMenuMessage:info];
        [[GRRUI shared] setCurrentMenuView:GRRFindView(receiver, arg1, arg2)];
    } else if ([kind isEqualToString:@"Menu"]) {
        [GRRMessageContext setCurrentMenuMessage:info];
        [[GRRUI shared] injectMenu];
    } else if ([kind isEqualToString:@"Delete"]) {
        [[GRRStorage shared] clearMessage:info.chatId msgId:info.msgId];
        [[GRRUI shared] removeFooterForMessage:info.chatId msgId:info.msgId];
        [[GRRVisibilityTracker shared] untrackMessage:info.chatId msgId:info.msgId];
        [[GRRNetwork shared] clearMessage:info.chatId msgId:info.msgId completion:nil];
    }
}

// 每种 replacement 保持与 plist 中 signature 一致的调用约定，保证转发给原实现不破坏宿主。
static void GRRHookVoid0(id self, SEL _cmd) {
    IMP original = GRROriginalFor(self, _cmd);
    if (original) ((void (*)(id, SEL))original)(self, _cmd);
    GRRRunHook(self, _cmd, nil, nil, nil);
}

static void GRRHookVoid1(id self, SEL _cmd, id arg1) {
    IMP original = GRROriginalFor(self, _cmd);
    if (original) ((void (*)(id, SEL, id))original)(self, _cmd, arg1);
    GRRRunHook(self, _cmd, arg1, nil, nil);
}

static void GRRHookVoid2(id self, SEL _cmd, id arg1, id arg2) {
    IMP original = GRROriginalFor(self, _cmd);
    if (original) ((void (*)(id, SEL, id, id))original)(self, _cmd, arg1, arg2);
    GRRRunHook(self, _cmd, arg1, arg2, nil);
}

static id GRRHookObj0(id self, SEL _cmd) {
    IMP original = GRROriginalFor(self, _cmd);
    id result = original ? ((id (*)(id, SEL))original)(self, _cmd) : nil;
    GRRRunHook(self, _cmd, nil, nil, result);
    return result;
}

static id GRRHookObj1(id self, SEL _cmd, id arg1) {
    IMP original = GRROriginalFor(self, _cmd);
    id result = original ? ((id (*)(id, SEL, id))original)(self, _cmd, arg1) : nil;
    GRRRunHook(self, _cmd, arg1, nil, result);
    return result;
}

static id GRRHookObj2(id self, SEL _cmd, id arg1, id arg2) {
    IMP original = GRROriginalFor(self, _cmd);
    id result = original ? ((id (*)(id, SEL, id, id))original)(self, _cmd, arg1, arg2) : nil;
    GRRRunHook(self, _cmd, arg1, arg2, result);
    return result;
}

static IMP GRRIMPForSignature(NSString *signature) {
    if ([signature isEqualToString:@"void0"]) return (IMP)GRRHookVoid0;
    if ([signature isEqualToString:@"void1"]) return (IMP)GRRHookVoid1;
    if ([signature isEqualToString:@"void2"]) return (IMP)GRRHookVoid2;
    if ([signature isEqualToString:@"obj0"]) return (IMP)GRRHookObj0;
    if ([signature isEqualToString:@"obj1"]) return (IMP)GRRHookObj1;
    if ([signature isEqualToString:@"obj2"]) return (IMP)GRRHookObj2;
    return NULL;
}

@interface GRRHookRegistry ()
@property (nonatomic, strong) NSArray<NSString *> *installedHooks;
@property (nonatomic, strong) NSArray<NSString *> *failedHooks;
@end

@implementation GRRHookRegistry

+ (instancetype)shared {
    static GRRHookRegistry *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        GRROriginalIMP = [NSMutableDictionary dictionary];
        GRRKindMap = [NSMutableDictionary dictionary];
        GRRInstalled = [NSMutableArray array];
        GRRFailed = [NSMutableArray array];
    }
    return self;
}

- (NSString *)plistPath {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"GRRHooks" ofType:@"plist"];
    if (path) return path;
    return @"/Library/Application Support/GroupReadReceipt/GRRHooks.plist";
}

- (Class)resolveClass:(NSString *)name isClassMethod:(BOOL *)isClassMethod {
    Class cls = objc_getClass(name.UTF8String);
    Method method = cls ? class_getInstanceMethod(cls, NSSelectorFromString(@"description")) : NULL;
    (void)method;
    if (cls) { *isClassMethod = NO; return cls; }
    Class meta = objc_getMetaClass(name.UTF8String);
    if (meta) { *isClassMethod = YES; return meta; }
    return Nil;
}

- (void)installEntry:(NSDictionary *)entry kind:(NSString *)kind {
    NSString *className = entry[@"class"];
    NSString *selectorName = entry[@"selector"];
    NSString *signature = entry[@"signature"] ?: @"void1";
    if (!className.length || !selectorName.length) return;

    BOOL isClassMethod = NO;
    Class cls = [self resolveClass:className isClassMethod:&isClassMethod];
    SEL selector = NSSelectorFromString(selectorName);
    IMP replacement = GRRIMPForSignature(signature);
    if (!cls || !selector || !replacement) {
        [GRRFailed addObject:[NSString stringWithFormat:@"%@ %@ (%@)", kind, className, selectorName]];
        return;
    }

    Method method = isClassMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    if (!method) {
        [GRRFailed addObject:[NSString stringWithFormat:@"%@ %@->%@ (selector missing)", kind, className, selectorName]];
        return;
    }

    NSString *key = GRRKey(cls, selector);
    IMP original = NULL;
    MSHookMessageEx(cls, selector, replacement, &original);
    if (original) GRROriginalIMP[key] = [NSValue valueWithPointer:original];
    GRRKindMap[key] = kind;
    [GRRInstalled addObject:[NSString stringWithFormat:@"%@ %@->%@", kind, className, selectorName]];
}

- (void)install {
    NSString *path = [self plistPath];
    NSDictionary *configuration = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!configuration) {
        [[GRRStorage shared] logAction:@"hook" code:404 chatId:@"" msgId:@"" detail:path];
        return;
    }
    for (NSString *kind in @[@"Identity", @"Render", @"LongPress", @"Menu", @"Delete"]) {
        NSArray *entries = configuration[kind];
        if (![entries isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *entry in entries) {
            if ([entry isKindOfClass:[NSDictionary class]]) [self installEntry:entry kind:kind];
        }
    }
    [[GRRStorage shared] logAction:@"hook" code:200 chatId:@"" msgId:@""
                            detail:[NSString stringWithFormat:@"installed=%lu failed=%lu",
                                    (unsigned long)GRRInstalled.count, (unsigned long)GRRFailed.count]];
}

- (NSArray<NSString *> *)installedHooks { return [GRRInstalled copy]; }
- (NSArray<NSString *> *)failedHooks { return [GRRFailed copy]; }

@end
