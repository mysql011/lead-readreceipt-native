#import <Foundation/Foundation.h>

@interface GRRHookRegistry : NSObject

+ (instancetype)shared;
- (void)install;
- (NSArray<NSString *> *)installedHooks;
- (NSArray<NSString *> *)failedHooks;

@end
