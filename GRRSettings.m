#import "GRRSettings.h"

@interface GRRSettings ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL allowReport;
@property (nonatomic, assign) NSTimeInterval refreshInterval;
@property (nonatomic, copy) NSString *backendURL;
@property (nonatomic, copy) NSString *apiToken;
@property (nonatomic, assign) BOOL captureHostLog;
@end

@implementation GRRSettings

+ (instancetype)shared {
    static GRRSettings *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reload];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reload)
                                                     name:GRRSettingsDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:key];
    return value ? [defaults boolForKey:key] : defaultValue;
}

- (void)reload {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.enabled = [self boolForKey:GRRKeyEnabled defaultValue:YES];
    self.allowReport = [self boolForKey:GRRKeyAllowReport defaultValue:YES];
    self.refreshInterval = MAX(1.0, [defaults doubleForKey:GRRKeyRefreshInterval] ?: 3.0);
    NSString *url = [defaults stringForKey:GRRKeyBackendURL];
    self.backendURL = url.length ? url : @"http://127.0.0.1:8787";
    self.apiToken = [defaults stringForKey:GRRKeyAPIToken] ?: @"";
    self.captureHostLog = [self boolForKey:GRRKeyCaptureHostLog defaultValue:NO];
}

- (BOOL)isReportingAllowed {
    return self.enabled && self.allowReport;
}

- (void)writeBool:(BOOL)value key:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [self commit];
}

- (void)writeObject:(id)value key:(NSString *)key {
    if (value) {
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }
    [self commit];
}

- (void)commit {
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self reload];
    [[NSNotificationCenter defaultCenter] postNotificationName:GRRSettingsDidChangeNotification object:self];
}

- (void)setEnabled:(BOOL)value { [self writeBool:value key:GRRKeyEnabled]; }
- (void)setAllowReport:(BOOL)value { [self writeBool:value key:GRRKeyAllowReport]; }
- (void)setCaptureHostLog:(BOOL)value { [self writeBool:value key:GRRKeyCaptureHostLog]; }
- (void)setRefreshInterval:(NSTimeInterval)value { [self writeObject:@(MAX(1.0, value)) key:GRRKeyRefreshInterval]; }
- (void)setBackendURL:(NSString *)value { [self writeObject:value key:GRRKeyBackendURL]; }
- (void)setAPIToken:(NSString *)value { [self writeObject:value key:GRRKeyAPIToken]; }

@end
