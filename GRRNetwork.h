#import <Foundation/Foundation.h>
#import "Headers/GRRTypes.h"

@interface GRRNetwork : NSObject

+ (instancetype)shared;
+ (NSString *)currentUserIdSafe;

// 当前登录用户 ID，由 hook 层解析后注入；为空时所有上报跳过
@property (nonatomic, copy, nullable) NSString *currentUserId;

- (void)start;
- (void)stop;

- (void)enableMessage:(NSString *)chatId
                msgId:(NSString *)msgId
          ownerUserId:(NSString *)ownerUserId
           completion:(nullable void (^)(BOOL success))completion;

- (void)clearMessage:(NSString *)chatId
               msgId:(NSString *)msgId
          completion:(nullable void (^)(BOOL success))completion;

- (void)groupSwitch:(NSString *)chatId
            enabled:(BOOL)enabled
      operatorUserId:(NSString *)operatorUserId
         completion:(nullable void (^)(BOOL success))completion;

- (void)presence:(NSString *)chatId userId:(NSString *)userId;

- (void)queryChatId:(NSString *)chatId
              msgId:(NSString *)msgId
         completion:(void (^)(NSArray<GRRReceipt *> *receipts, NSUInteger onlineCount))completion;

- (void)reportBody:(NSDictionary *)body
          completion:(nullable void (^)(BOOL success))completion;

- (void)flushQueue;

@end
