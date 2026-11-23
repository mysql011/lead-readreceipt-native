#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Headers/GRRTypes.h"

@interface GRRMessageContext : NSObject

+ (void)attach:(GRRMessageInfo *)info toView:(UIView *)view;
+ (GRRMessageInfo *)infoForView:(UIView *)view;
+ (void)forgetView:(UIView *)view;

// 当前长按/选中的消息，由 hook 层写入，菜单注入读取
+ (GRRMessageInfo *)currentMenuMessage;
+ (void)setCurrentMenuMessage:(GRRMessageInfo *)info;

// 从宿主对象解析消息信息：按候选 KVC 键路径探测，避免依赖具体类名
+ (GRRMessageInfo *)resolveFromObject:(id)object;
+ (id)valueForKeyPaths:(NSArray<NSString *> *)paths onObject:(id)object;
+ (NSString *)stringFromObject:(id)object;

@end
