#import <Foundation/Foundation.h>
#import "Headers/GRRTypes.h"

@interface GRRStorage : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSString *cacheDirectory;

- (BOOL)isMessageEnabled:(NSString *)chatId msgId:(NSString *)msgId;
- (void)markMessageEnabled:(NSString *)chatId msgId:(NSString *)msgId;

- (BOOL)isGroupOff:(NSString *)chatId;
- (void)setGroup:(NSString *)chatId off:(BOOL)off;

- (BOOL)isReported:(NSString *)chatId msgId:(NSString *)msgId userId:(NSString *)userId;
- (void)markReported:(NSString *)chatId msgId:(NSString *)msgId userId:(NSString *)userId;

- (void)clearMessage:(NSString *)chatId msgId:(NSString *)msgId;

- (void)enqueueReport:(NSDictionary *)body;
- (NSArray<NSDictionary *> *)drainQueue;
- (void)restoreQueue:(NSDictionary *)item;
- (NSUInteger)queueCount;

- (void)logAction:(NSString *)action
             code:(NSInteger)code
           chatId:(nullable NSString *)chatId
            msgId:(nullable NSString *)msgId
           detail:(nullable NSString *)detail;
- (NSArray<NSString *> *)exportLogLines;
- (NSURL *)exportLogFile;

@end
