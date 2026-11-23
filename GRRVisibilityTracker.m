#import "GRRVisibilityTracker.h"
#import "GRRSettings.h"
#import "GRRStorage.h"
#import "GRRNetwork.h"
#import "GRRUI.h"

@interface GRRTrackedView : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic, strong) GRRMessageInfo *info;
@property (nonatomic, strong) NSDate *visibleSince;
@property (nonatomic, assign) BOOL reported;
@end
@implementation GRRTrackedView
@end

@interface GRRVisibilityTracker ()
@property (nonatomic, strong) NSMutableArray<GRRTrackedView *> *entries;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation GRRVisibilityTracker

+ (instancetype)shared {
    static GRRVisibilityTracker *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                                 target:self
                                               selector:@selector(tick)
                                               userInfo:nil
                                                repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)dealloc {
    [self.timer invalidate];
}

- (void)trackView:(UIView *)view info:(GRRMessageInfo *)info {
    if (!view || !info) return;
    [self untrackView:view];
    GRRTrackedView *entry = [[GRRTrackedView alloc] init];
    entry.view = view;
    entry.info = info;
    [self.entries addObject:entry];
    if (self.entries.count > 400) [self.entries removeObjectsInRange:NSMakeRange(0, self.entries.count - 400)];
}

- (void)untrackView:(UIView *)view {
    if (!view) return;
    NSMutableArray *remove = [NSMutableArray array];
    for (GRRTrackedView *entry in self.entries) {
        if (!entry.view || entry.view == view) [remove addObject:entry];
    }
    [self.entries removeObjectsInArray:remove];
}

- (void)untrackMessage:(NSString *)chatId msgId:(NSString *)msgId {
    NSMutableArray *remove = [NSMutableArray array];
    for (GRRTrackedView *entry in self.entries) {
        if ([entry.info.chatId isEqualToString:chatId] && [entry.info.msgId isEqualToString:msgId]) [remove addObject:entry];
    }
    [self.entries removeObjectsInArray:remove];
}

- (void)untrackChat:(NSString *)chatId {
    NSMutableArray *remove = [NSMutableArray array];
    for (GRRTrackedView *entry in self.entries) {
        if ([entry.info.chatId isEqualToString:chatId]) [remove addObject:entry];
    }
    [self.entries removeObjectsInArray:remove];
}

- (BOOL)isVisible:(UIView *)view {
    if (!view || view.hidden || view.window == nil) return NO;
    CGRect bounds = view.bounds;
    CGRect inWindow = [view convertRect:bounds toView:view.window];
    CGRect screen = view.window.bounds;
    if (!CGRectIntersectsRect(inWindow, screen)) return NO;
    CGFloat visibleHeight = CGRectGetHeight(CGRectIntersection(inWindow, screen));
    return visibleHeight >= CGRectGetHeight(bounds) * 0.5 && visibleHeight > 4;
}

- (void)tick {
    GRRSettings *settings = [GRRSettings shared];
    NSString *userId = [GRRNetwork shared].currentUserId;
    NSDate *now = [NSDate date];

    for (GRRTrackedView *entry in [self.entries copy]) {
        UIView *view = entry.view;
        if (!view) {
            [self.entries removeObject:entry];
            continue;
        }
        if (entry.reported || !settings.enabled || !settings.allowReport || !userId.length) {
            if (![self isVisible:view]) entry.visibleSince = nil;
            continue;
        }
        GRRMessageInfo *info = entry.info;
        if (![info isEligibleChat] || [[GRRStorage shared] isGroupOff:info.chatId]) {
            entry.visibleSince = nil;
            continue;
        }
        if ([info.senderId isEqualToString:userId]) {
            entry.visibleSince = nil;
            continue;
        }
        if (![[GRRStorage shared] isMessageEnabled:info.chatId msgId:info.msgId] ||
            [[GRRStorage shared] isReported:info.chatId msgId:info.msgId userId:userId]) {
            entry.visibleSince = nil;
            continue;
        }
        if ([self isVisible:view]) {
            if (!entry.visibleSince) entry.visibleSince = now;
            NSTimeInterval dwell = [now timeIntervalSinceDate:entry.visibleSince];
            if (dwell >= GRRDwellThreshold) {
                entry.reported = YES;
                [self report:info userId:userId];
            }
        } else {
            entry.visibleSince = nil;
        }
    }
}

- (void)report:(GRRMessageInfo *)info userId:(NSString *)userId {
    NSMutableDictionary *profile = [NSMutableDictionary dictionary];
    if (info.nickname.length) profile[@"nickname"] = info.nickname;
    if (info.avatarURL.length) profile[@"avatar"] = info.avatarURL;
    NSDictionary *body = @{
        @"chatId": info.chatId ?: @"",
        @"msgId": info.msgId ?: @"",
        @"userId": userId,
        @"readAt": @((long long)([[NSDate date] timeIntervalSince1970] * 1000)),
        @"profile": profile
    };
    [[GRRNetwork shared] reportBody:body completion:^(BOOL success) {
        if (success) {
            [[GRRStorage shared] markReported:info.chatId msgId:info.msgId userId:userId];
            [[GRRUI shared] refreshVisibleFooters];
        } else {
            [[GRRStorage shared] enqueueReport:body];
        }
    }];
}

@end
