#import "GRRNetwork.h"
#import "GRRSettings.h"
#import "GRRStorage.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

@interface GRRNetwork ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSTimer *flushTimer;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, assign) SCNetworkReachabilityRef reachability;
@property (nonatomic, copy) NSString *heartbeatChatId;
@end

static void GRRReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    if ((flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsConnectionRequired)) {
        [[GRRNetwork shared] flushQueue];
    }
}

@implementation GRRNetwork

+ (NSString *)currentUserIdSafe {
    return [GRRNetwork shared].currentUserId ?: @"";
}

+ (instancetype)shared {
    static GRRNetwork *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 10.0;
        configuration.timeoutIntervalForResource = 15.0;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (void)start {
    [self stop];
    NSTimeInterval interval = MAX(1.0, [GRRSettings shared].refreshInterval) * 4.0;
    self.flushTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                      target:self
                                                    selector:@selector(flushQueue)
                                                    userInfo:nil
                                                     repeats:YES];
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:GRRHeartbeatInterval
                                                          target:self
                                                        selector:@selector(sendHeartbeat)
                                                        userInfo:nil
                                                         repeats:YES];
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    self.reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zeroAddress);
    if (self.reachability) {
        SCNetworkReachabilityContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
        SCNetworkReachabilitySetCallback(self.reachability, GRRReachabilityCallback, &context);
        SCNetworkReachabilityScheduleWithRunLoop(self.reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    }
    [self flushQueue];
}

- (void)stop {
    [self.flushTimer invalidate]; self.flushTimer = nil;
    [self.heartbeatTimer invalidate]; self.heartbeatTimer = nil;
    if (self.reachability) {
        SCNetworkReachabilityUnscheduleFromRunLoop(self.reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        CFRelease(self.reachability);
        self.reachability = NULL;
    }
}

- (void)dealloc {
    [self stop];
}

- (void)setHeartbeatChatId:(NSString *)chatId {
    _heartbeatChatId = [chatId copy];
}

- (NSString *)encoded:(NSString *)value {
    return value ?: @"";
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path body:(NSDictionary *)body {
    GRRSettings *settings = [GRRSettings shared];
    NSString *base = [[settings backendURL] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSMutableString *urlString = [NSMutableString stringWithFormat:@"%@%@", base, path];
    if (body && [method isEqualToString:@"GET"]) {
        BOOL first = ![urlString containsString:@"?"];
        for (NSString *key in body) {
            NSString *encodedKey = [key stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            NSString *encodedValue = [[body[key] description] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            [urlString appendFormat:@"%@%@=%@", first ? @"?" : @"&", encodedKey, encodedValue ?: @""];
            first = NO;
        }
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                      timeoutInterval:10.0];
    request.HTTPMethod = method;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (settings.apiToken.length) {
        [request setValue:settings.apiToken forHTTPHeaderField:@"X-Api-Token"];
    }
    if (body && ![method isEqualToString:@"GET"]) {
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    }
    return request;
}

- (void)perform:(NSString *)method
           path:(NSString *)path
           body:(NSDictionary *)body
         chatId:(NSString *)chatId
          msgId:(NSString *)msgId
        attempt:(NSInteger)attempt
     completion:(void (^)(NSDictionary *data, NSError *error))completion {
    if (![GRRSettings shared].enabled) {
        if (completion) completion(nil, [NSError errorWithDomain:@"GRR" code:1 userInfo:@{NSLocalizedDescriptionKey: @"plugin-disabled"}]);
        return;
    }
    NSMutableURLRequest *request = [self requestWithMethod:method path:path body:body];
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        NSInteger code = http ? http.statusCode : (error ? error.code : 0);
        NSDictionary *json = nil;
        if (data) json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        BOOL ok = !error && http.statusCode >= 200 && http.statusCode < 300 && [json isKindOfClass:[NSDictionary class]] && [json[@"ok"] boolValue];
        [[GRRStorage shared] logAction:[NSString stringWithFormat:@"%@ %@", method, path]
                                  code:code
                                chatId:chatId
                                 msgId:msgId
                                detail:ok ? @"ok" : (json[@"error"] ?: (error.localizedDescription ?: @"fail"))];
        if (ok) {
            if (completion) completion(json, nil);
            return;
        }
        if (attempt < GRRMaxRetry) {
            dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * (attempt + 1) * NSEC_PER_SEC));
            dispatch_after(when, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self perform:method path:path body:body chatId:chatId msgId:msgId attempt:attempt + 1 completion:completion];
            });
            return;
        }
        NSError *finalError = error ?: [NSError errorWithDomain:@"GRR" code:code userInfo:@{NSLocalizedDescriptionKey: (json[@"error"] ?: @"HTTP_ERROR")}];
        if (completion) completion(nil, finalError);
    }];
    [task resume];
}

- (void)enableMessage:(NSString *)chatId
                msgId:(NSString *)msgId
          ownerUserId:(NSString *)ownerUserId
           completion:(void (^)(BOOL))completion {
    [self perform:@"POST" path:@"/api/message/enable"
             body:@{@"chatId": chatId ?: @"", @"msgId": msgId ?: @"", @"ownerUserId": ownerUserId ?: @""}
           chatId:chatId msgId:msgId attempt:0
       completion:^(NSDictionary *data, NSError *error) { if (completion) completion(!error); }];
}

- (void)clearMessage:(NSString *)chatId msgId:(NSString *)msgId completion:(void (^)(BOOL))completion {
    [self perform:@"POST" path:@"/api/message/clear"
             body:@{@"chatId": chatId ?: @"", @"msgId": msgId ?: @""}
           chatId:chatId msgId:msgId attempt:0
       completion:^(NSDictionary *data, NSError *error) { if (completion) completion(!error); }];
}

- (void)groupSwitch:(NSString *)chatId
            enabled:(BOOL)enabled
      operatorUserId:(NSString *)operatorUserId
         completion:(void (^)(BOOL))completion {
    [self perform:@"POST" path:@"/api/groupSwitch"
             body:@{@"chatId": chatId ?: @"", @"enabled": @(enabled), @"operatorUserId": operatorUserId ?: @"", @"isAdmin": @YES}
           chatId:chatId msgId:@"" attempt:0
       completion:^(NSDictionary *data, NSError *error) { if (completion) completion(!error); }];
}

- (void)presence:(NSString *)chatId userId:(NSString *)userId {
    if (!chatId.length || !userId.length) return;
    [self perform:@"POST" path:@"/api/presence"
             body:@{@"chatId": chatId, @"userId": userId}
           chatId:chatId msgId:@"" attempt:0
       completion:^(NSDictionary *data, NSError *error) { }];
}

- (void)sendHeartbeat {
    if (self.heartbeatChatId.length && self.currentUserId.length) {
        [self presence:self.heartbeatChatId userId:self.currentUserId];
    }
}

- (void)queryChatId:(NSString *)chatId
              msgId:(NSString *)msgId
         completion:(void (^)(NSArray<GRRReceipt *> *, NSUInteger))completion {
    [self perform:@"GET" path:@"/api/query" body:@{@"chatId": chatId ?: @"", @"msgId": msgId ?: @""}
           chatId:chatId msgId:msgId attempt:0
       completion:^(NSDictionary *data, NSError *error) {
        NSMutableArray *result = [NSMutableArray array];
        if (!error && [data[@"list"] isKindOfClass:[NSArray class]]) {
            for (NSDictionary *item in data[@"list"]) {
                GRRReceipt *receipt = [[GRRReceipt alloc] init];
                receipt.userId = [item[@"userId"] description] ?: @"";
                receipt.nickname = item[@"nickname"] ? [item[@"nickname"] description] : receipt.userId;
                receipt.avatarURL = item[@"avatar"] ? [item[@"avatar"] description] : nil;
                receipt.readAt = [item[@"readAt"] longLongValue];
                [result addObject:receipt];
            }
            [result sortUsingComparator:^NSComparisonResult(GRRReceipt *a, GRRReceipt *b) {
                if (a.readAt < b.readAt) return NSOrderedAscending;
                if (a.readAt > b.readAt) return NSOrderedDescending;
                return [a.userId compare:b.userId];
            }];
        }
        NSUInteger online = error ? 0 : [data[@"onlineCount"] unsignedIntegerValue];
        if (completion) completion(result, online);
    }];
}

- (void)reportBody:(NSDictionary *)body completion:(void (^)(BOOL))completion {
    NSString *chatId = body[@"chatId"];
    NSString *msgId = body[@"msgId"];
    [self perform:@"POST" path:@"/api/report" body:body chatId:chatId msgId:msgId attempt:0
       completion:^(NSDictionary *data, NSError *error) { if (completion) completion(!error); }];
}

- (void)flushQueue {
    if (![GRRSettings shared].isReportingAllowed) return;
    NSArray *batch = [[GRRStorage shared] drainQueue];
    for (NSDictionary *item in batch) {
        NSDictionary *body = item[@"body"];
        if (![body isKindOfClass:[NSDictionary class]]) continue;
        [self reportBody:body completion:^(BOOL success) {
            if (success) {
                [[GRRStorage shared] markReported:body[@"chatId"] msgId:body[@"msgId"] userId:body[@"userId"]];
            } else {
                NSInteger attempts = [item[@"attempts"] integerValue] + 1;
                if (attempts <= 1) {
                    NSMutableDictionary *copy = [item mutableCopy];
                    copy[@"attempts"] = @(attempts);
                    [[GRRStorage shared] restoreQueue:copy];
                }
            }
        }];
    }
}

@end
