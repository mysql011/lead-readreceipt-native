#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Headers/GRRTypes.h"

@interface GRRUI : NSObject

+ (instancetype)shared;

- (void)refreshFooterForView:(UIView *)view info:(GRRMessageInfo *)info;
- (void)refreshVisibleFooters;
- (void)removeFooterForMessage:(NSString *)chatId msgId:(NSString *)msgId;
- (void)removeFootersForChat:(NSString *)chatId;
- (void)setCurrentMenuView:(UIView *)view;
- (void)injectMenu;
- (void)enableCurrentMenuMessage;
- (void)showReceiptsForChat:(NSString *)chatId msgId:(NSString *)msgId from:(UIViewController *)controller;

@end
