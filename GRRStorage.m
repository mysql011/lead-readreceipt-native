#import "GRRStorage.h"

@interface GRRStorage ()
@property (nonatomic, strong) NSString *cacheDirectory;
@property (nonatomic, strong) NSMutableSet<NSString *> *enabledMessages;
@property (nonatomic, strong) NSMutableSet<NSString *> *offGroups;
@property (nonatomic, strong) NSMutableSet<NSString *> *reported;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *queue;
@property (nonatomic, strong) NSMutableArray<NSString *> *logs;
@property (nonatomic, strong) NSRecursiveLock *lock;
@end

@implementation GRRStorage

+ (instancetype)shared {
    static GRRStorage *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSRecursiveLock alloc] init];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *base = paths.firstObject ?: NSTemporaryDirectory();
        _cacheDirectory = [base stringByAppendingPathComponent:@"com.group.readreceipt"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_cacheDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        _enabledMessages = [NSMutableSet setWithArray:[self loadArray:@"enabled.json"]];
        _offGroups = [NSMutableSet setWithArray:[self loadArray:@"groupoff.json"]];
        _reported = [NSMutableSet setWithArray:[self loadArray:@"reported.json"]];
        NSArray *savedQueue = [self loadArray:@"queue.json"];
        _queue = savedQueue ? [savedQueue mutableCopy] : [NSMutableArray array];
        _logs = [NSMutableArray array];
        NSString *logPath = [self.cacheDirectory stringByAppendingPathComponent:@"logs.jsonl"];
        NSString *content = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
        if (content.length) {
            [_logs addObjectsFromArray:[content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]];
        }
    }
    return self;
}

- (NSArray *)loadArray:(NSString *)fileName {
    NSData *data = [NSData dataWithContentsOfFile:[self.cacheDirectory stringByAppendingPathComponent:fileName]];
    if (!data) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

- (void)saveArray:(NSArray *)array file:(NSString *)fileName {
    NSData *data = [NSJSONSerialization dataWithJSONObject:array options:0 error:nil];
    [data writeToFile:[self.cacheDirectory stringByAppendingPathComponent:fileName] atomically:YES];
}

- (NSString *)keyChat:(NSString *)chatId msg:(NSString *)msgId {
    return [NSString stringWithFormat:@"%@|%@", chatId ?: @"", msgId ?: @""];
}

- (BOOL)isMessageEnabled:(NSString *)chatId msgId:(NSString *)msgId {
    [self.lock lock]; BOOL result = [self.enabledMessages containsObject:[self keyChat:chatId msg:msgId]]; [self.lock unlock];
    return result;
}

- (void)markMessageEnabled:(NSString *)chatId msgId:(NSString *)msgId {
    [self.lock lock];
    [self.enabledMessages addObject:[self keyChat:chatId msg:msgId]];
    [self saveArray:[self.enabledMessages allObjects] file:@"enabled.json"];
    [self.lock unlock];
}

- (BOOL)isGroupOff:(NSString *)chatId {
    [self.lock lock]; BOOL result = chatId.length && [self.offGroups containsObject:chatId]; [self.lock unlock];
    return result;
}

- (void)setGroup:(NSString *)chatId off:(BOOL)off {
    if (!chatId.length) return;
    [self.lock lock];
    if (off) [self.offGroups addObject:chatId]; else [self.offGroups removeObject:chatId];
    [self saveArray:[self.offGroups allObjects] file:@"groupoff.json"];
    [self.lock unlock];
}

- (BOOL)isReported:(NSString *)chatId msgId:(NSString *)msgId userId:(NSString *)userId {
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", chatId ?: @"", msgId ?: @"", userId ?: @""];
    [self.lock lock]; BOOL result = [self.reported containsObject:key]; [self.lock unlock];
    return result;
}

- (void)markReported:(NSString *)chatId msgId:(NSString *)msgId userId:(NSString *)userId {
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", chatId ?: @"", msgId ?: @"", userId ?: @""];
    [self.lock lock];
    [self.reported addObject:key];
    [self saveArray:[self.reported allObjects] file:@"reported.json"];
    [self.lock unlock];
}

- (void)clearMessage:(NSString *)chatId msgId:(NSString *)msgId {
    [self.lock lock];
    NSString *key = [self keyChat:chatId msg:msgId];
    [self.enabledMessages removeObject:key];
    NSString *prefix = [key stringByAppendingString:@"|"];
    NSMutableArray *remove = [NSMutableArray array];
    for (NSString *item in self.reported) {
        if ([item hasPrefix:prefix]) [remove addObject:item];
    }
    [self.reported minusSet:[NSSet setWithArray:remove]];
    NSMutableArray *remainingQueue = [NSMutableArray array];
    for (NSDictionary *item in self.queue) {
        if (![[item[@"chatId"] ?: @"" description] isEqualToString:chatId] ||
            ![[item[@"msgId"] ?: @"" description] isEqualToString:msgId]) {
            [remainingQueue addObject:item];
        }
    }
    self.queue = remainingQueue;
    [self saveArray:[self.enabledMessages allObjects] file:@"enabled.json"];
    [self saveArray:[self.reported allObjects] file:@"reported.json"];
    [self saveArray:self.queue file:@"queue.json"];
    [self.lock unlock];
}

- (void)enqueueReport:(NSDictionary *)body {
    if (!body) return;
    [self.lock lock];
    [self.queue addObject:@{ @"body": body, @"attempts": @0 }];
    [self saveArray:self.queue file:@"queue.json"];
    [self.lock unlock];
}

- (NSArray<NSDictionary *> *)drainQueue {
    [self.lock lock];
    NSArray *batch = [self.queue copy];
    self.queue = [NSMutableArray array];
    [self saveArray:self.queue file:@"queue.json"];
    [self.lock unlock];
    return batch;
}

- (void)restoreQueue:(NSDictionary *)item {
    if (!item) return;
    [self.lock lock];
    [self.queue addObject:item];
    [self saveArray:self.queue file:@"queue.json"];
    [self.lock unlock];
}

- (NSUInteger)queueCount {
    [self.lock lock]; NSUInteger count = self.queue.count; [self.lock unlock];
    return count;
}

- (void)logAction:(NSString *)action
             code:(NSInteger)code
           chatId:(NSString *)chatId
            msgId:(NSString *)msgId
           detail:(NSString *)detail {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSDictionary *entry = @{
        @"time": [formatter stringFromDate:[NSDate date]] ?: @"",
        @"chatId": chatId ?: @"",
        @"msgId": msgId ?: @"",
        @"action": action ?: @"",
        @"code": @(code),
        @"detail": detail ?: @""
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
    NSString *line = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    [self.lock lock];
    [self.logs addObject:line];
    if (self.logs.count > 1000) [self.logs removeObjectsInRange:NSMakeRange(0, self.logs.count - 1000)];
    [[self.logs componentsJoinedByString:@"\n"] writeToFile:[self.cacheDirectory stringByAppendingPathComponent:@"logs.jsonl"]
                                                 atomically:YES
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    [self.lock unlock];
}

- (NSArray<NSString *> *)exportLogLines {
    [self.lock lock]; NSArray *lines = [self.logs copy]; [self.lock unlock];
    return lines;
}

- (NSURL *)exportLogFile {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject ?: NSTemporaryDirectory();
    NSString *fileName = [NSString stringWithFormat:@"lead-readreceipt-%.0f.log", [[NSDate date] timeIntervalSince1970]];
    NSURL *url = [NSURL fileURLWithPath:[documents stringByAppendingPathComponent:fileName]];
    NSString *header = @"time\tchatId\tmsgId\taction\tcode\tdetail\n";
    NSMutableString *text = [header mutableCopy];
    for (NSString *line in [self exportLogLines]) {
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *entry = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        [text appendFormat:@"%@\t%@\t%@\t%@\t%@\t%@\n",
            entry[@"time"] ?: @"", entry[@"chatId"] ?: @"", entry[@"msgId"] ?: @"",
            entry[@"action"] ?: @"", entry[@"code"] ?: @"", entry[@"detail"] ?: @""];
    }
    [[text copy] writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return url;
}

@end
