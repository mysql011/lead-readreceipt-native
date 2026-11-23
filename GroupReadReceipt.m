#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Headers/GRRTypes.h"
#import "GRRSettings.h"
#import "GRRStorage.h"
#import "GRRNetwork.h"
#import "GRRHookRegistry.h"
#import "GRRVisibilityTracker.h"
#import "GRRFishhookBridge.h"

static id GRRLaunchObserver = nil;

__attribute__((constructor)) static void GRRPluginEntry(void) {
    @autoreleasepool {
        [[GRRStorage shared] logAction:@"init" code:200 chatId:@"" msgId:@""
                                detail:[NSString stringWithFormat:@"plugin=%@ version=%@", GRRPluginID, GRRPluginVersion]];
        [GRRFishhookBridge install];
        [[GRRHookRegistry shared] install];
        [GRRVisibilityTracker shared];

        GRRLaunchObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            [[GRRNetwork shared] start];
            [[GRRStorage shared] logAction:@"start" code:200 chatId:@"" msgId:@""
                                    detail:[NSString stringWithFormat:@"hooks=%lu",
                                            (unsigned long)[[GRRHookRegistry shared] installedHooks].count]];
            if (![[GRRNetwork shared].currentUserId length]) {
                [[GRRStorage shared] logAction:@"identity" code:0 chatId:@"" msgId:@"" detail:@"unresolved-check-GRRHooks-plist"];
            }
        }];
    }
}
