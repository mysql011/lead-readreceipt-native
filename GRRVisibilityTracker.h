#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Headers/GRRTypes.h"

@interface GRRVisibilityTracker : NSObject

+ (instancetype)shared;

- (void)trackView:(UIView *)view info:(GRRMessageInfo *)info;
- (void)untrackView:(UIView *)view;
- (void)untrackMessage:(NSString *)chatId msgId:(NSString *)msgId;
- (void)untrackChat:(NSString *)chatId;

@end
