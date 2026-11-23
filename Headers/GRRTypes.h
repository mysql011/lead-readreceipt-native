#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static NSString * const GRRPluginID      = @"com.group.readreceipt";
static NSString * const GRRPluginVersion = @"1.0.0";

// 可视停留阈值：800ms
static NSTimeInterval const GRRDwellThreshold = 0.8;
// 单次上报最多重试 2 次（首次 + 2 次重试）
static NSInteger const GRRMaxRetry = 2;
// 在线心跳间隔与 TTL
static NSTimeInterval const GRRHeartbeatInterval = 30.0;
static NSTimeInterval const GRRPresenceTTL = 60.0;

// NSUserDefaults 键（注册壳与 dylib 在同一进程内共享）
static NSString * const GRRKeyEnabled         = @"com.group.readreceipt.enabled";
static NSString * const GRRKeyAllowReport     = @"com.group.readreceipt.allowReport";
static NSString * const GRRKeyRefreshInterval = @"com.group.readreceipt.refreshInterval";
static NSString * const GRRKeyBackendURL      = @"com.group.readreceipt.backendUrl";
static NSString * const GRRKeyAPIToken        = @"com.group.readreceipt.apiToken";
static NSString * const GRRKeyCaptureHostLog  = @"com.group.readreceipt.captureHostLog";

// 通知名：配置变更后由注册壳的配置页发出，dylib 监听并热更新
static NSString * const GRRSettingsDidChangeNotification = @"GRRSettingsDidChangeNotification";
static NSString * const GRRDisplayModeDidChangeNotification = @"GRRDisplayModeDidChangeNotification";

@interface GRRMessageInfo : NSObject

@property (nonatomic, copy) NSString *chatId;
@property (nonatomic, copy) NSString *msgId;
@property (nonatomic, copy) NSString *senderId;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, assign) BOOL isChannel;
@property (nonatomic, assign) BOOL isPrivate;
@property (nonatomic, assign) BOOL isOutgoing;
@property (nonatomic, copy, nullable) NSString *nickname;
@property (nonatomic, copy, nullable) NSString *avatarURL;

- (BOOL)isEligibleChat;
- (NSString *)dedupeKey;

@end

@interface GRRReceipt : NSObject

@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *nickname;
@property (nonatomic, copy, nullable) NSString *avatarURL;
@property (nonatomic, assign) long long readAt;

@end

NS_ASSUME_NONNULL_END
