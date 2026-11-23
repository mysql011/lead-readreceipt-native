#import "GRRMessageContext.h"
#import "GRRNetwork.h"
#import <objc/runtime.h>

static char GRRInfoKey;
static GRRMessageInfo *GRRCurrentMenuMessage = nil;

@implementation GRRMessageContext

+ (void)attach:(GRRMessageInfo *)info toView:(UIView *)view {
    if (!view || !info) return;
    objc_setAssociatedObject(view, &GRRInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (GRRMessageInfo *)infoForView:(UIView *)view {
    return view ? objc_getAssociatedObject(view, &GRRInfoKey) : nil;
}

+ (void)forgetView:(UIView *)view {
    if (view) objc_setAssociatedObject(view, &GRRInfoKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (GRRMessageInfo *)currentMenuMessage {
    return GRRCurrentMenuMessage;
}

+ (void)setCurrentMenuMessage:(GRRMessageInfo *)info {
    GRRCurrentMenuMessage = info;
}

+ (id)valueForKeyPaths:(NSArray<NSString *> *)paths onObject:(id)object {
    for (NSString *path in paths) {
        @try {
            id value = [object valueForKeyPath:path];
            if (value && value != [NSNull null]) return value;
        } @catch (__unused NSException *exception) {}
    }
    return nil;
}

+ (NSString *)stringFromObject:(id)object {
    if (!object || object == [NSNull null]) return @"";
    if ([object isKindOfClass:[NSString class]]) return object;
    if ([object respondsToSelector:@selector(stringValue)]) return [object stringValue];
    if ([object isKindOfClass:[NSNumber class]]) return [object description];
    return [object description];
}

+ (GRRMessageInfo *)resolveFromObject:(id)object {
    if (!object) return nil;
    if ([object isKindOfClass:[GRRMessageInfo class]]) return object;

    GRRMessageInfo *cached = nil;
    if ([object isKindOfClass:[UIView class]]) {
        cached = [self infoForView:(UIView *)object];
        if (cached) return cached;
    }

    GRRMessageInfo *info = [[GRRMessageInfo alloc] init];
    id message = [self valueForKeyPaths:@[@"message", @"msg", @"_message", @"viewModel.message", @"self"] onObject:object];
    id source = message ?: object;

    id msgIdValue = [self valueForKeyPaths:@[@"msgId", @"messageId", @"_identifier", @"identifier", @"mid", @"id"] onObject:source];
    if (!msgIdValue) msgIdValue = [self valueForKeyPaths:@[@"msgId", @"messageId", @"identifier", @"mid"] onObject:object];
    info.msgId = [self stringFromObject:msgIdValue];

    id chatValue = [self valueForKeyPaths:@[@"chat", @"conversation", @"peer", @"chatInfo", @"dialog"] onObject:source];
    if (!chatValue) chatValue = [self valueForKeyPaths:@[@"chat", @"conversation", @"peer", @"chatId", @"conversationId"] onObject:object];
    id chatIdValue = [self valueForKeyPaths:@[@"id", @"chatId", @"identifier", @"peerId"] onObject:chatValue];
    info.chatId = [self stringFromObject:chatIdValue ?: chatValue];

    id senderValue = [self valueForKeyPaths:@[@"sender", @"from", @"author", @"fromUser", @"user"] onObject:source];
    id senderIdValue = [self valueForKeyPaths:@[@"id", @"senderId", @"fromId", @"userId", @"uid"] onObject:senderValue];
    if (!senderIdValue) senderIdValue = [self valueForKeyPaths:@[@"senderId", @"fromId", @"authorId", @"userId"] onObject:source];
    info.senderId = [self stringFromObject:senderIdValue];

    NSNumber *outgoing = [self valueForKeyPaths:@[@"isOutgoing", @"outgoing", @"isOwn", @"isSelf"] onObject:source];
    info.isOutgoing = outgoing ? outgoing.boolValue : ([info.senderId isEqualToString:[GRRNetwork currentUserIdSafe]]);

    id textValue = [self valueForKeyPaths:@[@"text", @"messageText", @"content", @"message"] onObject:source];
    info.text = [self stringFromObject:textValue];

    id nickname = [self valueForKeyPaths:@[@"firstName", @"nickname", @"username", @"name", @"title"] onObject:senderValue];
    info.nickname = [self stringFromObject:nickname];
    info.avatarURL = [self stringFromObject:[self valueForKeyPaths:@[@"avatar", @"avatarUrl", @"photoUrl"] onObject:senderValue]];

    id typeValue = [self valueForKeyPaths:@[@"type", @"chatType", @"peerType"] onObject:chatValue];
    NSString *type = [[self stringFromObject:typeValue] lowercaseString];
    NSNumber *isChannel = [self valueForKeyPaths:@[@"isChannel", @"isBroadcast"] onObject:chatValue];
    NSNumber *isPrivate = [self valueForKeyPaths:@[@"isPrivate", @"isUser"] onObject:chatValue];
    NSNumber *isGroup = [self valueForKeyPaths:@[@"isGroup", @"isMegagroup", @"isSupergroup"] onObject:chatValue];

    info.isChannel = isChannel.boolValue || [type containsString:@"channel"] || [type containsString:@"broadcast"];
    info.isPrivate = isPrivate.boolValue || [type containsString:@"private"] || [type containsString:@"user"] || [type isEqualToString:@"dm"];
    info.isGroup = isGroup.boolValue || [type containsString:@"group"] || [type containsString:@"chat"];
    if (!info.isGroup && !info.isPrivate && !info.isChannel) {
        NSString *className = NSStringFromClass([source class]) ?: @"";
        if ([className rangeOfString:@"Channel" options:NSCaseInsensitiveSearch].location != NSNotFound) info.isChannel = YES;
        else if ([className rangeOfString:@"Secret" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                 [className rangeOfString:@"Private" options:NSCaseInsensitiveSearch].location != NSNotFound) info.isPrivate = YES;
        else if ([info.chatId hasPrefix:@"-"]) info.isGroup = YES;
    }

    if ([object isKindOfClass:[UIView class]]) [self attach:info toView:(UIView *)object];
    return info;
}

@end
