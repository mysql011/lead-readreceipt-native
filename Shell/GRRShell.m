#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// 极简注册壳：只向 Lead 面板声明插件存在、开关键与配置页类名。
// 不包含任何消息 Hook、UI 渲染、网络或持久化逻辑，全部业务在 GroupReadReceipt.dylib。

static NSDictionary *GRRPluginDescriptor(void) {
    return @{
        @"id": @"com.group.readreceipt",
        @"name": @"群组已读回执",
        @"version": @"1.0.0",
        @"category": @"message",
        @"minLeadVersion": @"2.0",
        @"enabledKey": @"com.group.readreceipt.enabled",
        @"configViewController": @"GRRConfigViewController",
        @"icon": @"icon.png",
        @"standalone": @YES
    };
}

__attribute__((constructor)) static void GRRShellEntry(void) {
    @autoreleasepool {
        NSDictionary *descriptor = GRRPluginDescriptor();

        // 通过运行时约定注册，不对 Lead 产生编译期依赖；Lead 不存在时静默跳过。
        NSArray *candidates = @[@"LeadPluginCenter", @"LeadPluginManager", @"LeadPluginRegistry"];
        for (NSString *name in candidates) {
            Class cls = objc_getClass(name.UTF8String);
            if (!cls) continue;
            SEL selector = NSSelectorFromString(@"registerPluginDescriptor:");
            if ([cls respondsToSelector:selector]) {
                ((void (*)(id, SEL, id))objc_msgSend)((id)cls, selector, descriptor);
                break;
            }
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:@"LeadPluginDescriptorAvailableNotification"
                                                            object:nil
                                                          userInfo:descriptor];
    }
}
