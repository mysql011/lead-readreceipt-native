#import "GRRTypes.h"

@implementation GRRMessageInfo

- (BOOL)isEligibleChat {
    // 私聊 / 频道 / 广播群写死禁用；只有群聊参与
    return self.isGroup && !self.isPrivate && !self.isChannel;
}

- (NSString *)dedupeKey {
    return [NSString stringWithFormat:@"%@|%@|%@", self.chatId ?: @"", self.msgId ?: @"", self.senderId ?: @""];
}

@end

@implementation GRRReceipt

@end
