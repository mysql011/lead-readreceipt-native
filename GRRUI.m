#import "GRRUI.h"
#import "GRRMessageContext.h"
#import "GRRSettings.h"
#import "GRRStorage.h"
#import "GRRNetwork.h"
#import <objc/runtime.h>

static NSString * const GRRFooterTagPrefix = @"grr-footer-";

@interface GRRFooterView : UILabel
@property (nonatomic, copy) NSString *chatId;
@property (nonatomic, copy) NSString *msgId;
@end

@implementation GRRFooterView
@end

@interface GRRReceiptCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@end

@implementation GRRReceiptCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(12, 8, 40, 40)];
        _avatarView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarView.clipsToBounds = YES;
        _avatarView.layer.cornerRadius = 20;
        [self.contentView addSubview:_avatarView];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.textLabel.frame = CGRectMake(64, 10, CGRectGetWidth(self.contentView.bounds) - 150, 22);
    self.detailTextLabel.frame = CGRectMake(64, 34, CGRectGetWidth(self.contentView.bounds) - 150, 16);
}
@end

@interface GRRReceiptPopupController : UITableViewController
@property (nonatomic, copy) NSString *chatId;
@property (nonatomic, copy) NSString *msgId;
@property (nonatomic, strong) NSArray<GRRReceipt *> *receipts;
@property (nonatomic, assign) NSUInteger onlineCount;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *avatarCache;
@end

@implementation GRRReceiptPopupController

- (instancetype)initWithChatId:(NSString *)chatId msgId:(NSString *)msgId {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _chatId = [chatId copy];
        _msgId = [msgId copy];
        _receipts = @[];
        _avatarCache = [NSMutableDictionary dictionary];
        self.title = @"已读回执";
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                              target:self
                                                                                              action:@selector(close)];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[GRRReceiptCell class] forCellReuseIdentifier:@"receipt"];
    self.tableView.rowHeight = 56;
    NSTimeInterval interval = MAX(1.0, [GRRSettings shared].refreshInterval);
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                        target:self
                                                      selector:@selector(load)
                                                      userInfo:nil
                                                       repeats:YES];
    [self load];
}

- (void)dealloc {
    [self.refreshTimer invalidate];
}

- (void)close {
    [self.refreshTimer invalidate];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)load {
    __weak typeof(self) weakSelf = self;
    [[GRRNetwork shared] queryChatId:self.chatId msgId:self.msgId
                          completion:^(NSArray<GRRReceipt *> *receipts, NSUInteger onlineCount) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.receipts = receipts;
            weakSelf.onlineCount = onlineCount;
            [weakSelf.tableView reloadData];
        });
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.receipts.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 34)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, tableView.bounds.size.width - 32, 20)];
    label.font = [UIFont systemFontOfSize:12];
    label.textColor = [UIColor grayColor];
    label.text = [NSString stringWithFormat:@"已读 %lu 人 · 群内插件在线 %lu 人",
                  (unsigned long)self.receipts.count, (unsigned long)self.onlineCount];
    [header addSubview:label];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 34; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GRRReceiptCell *cell = [tableView dequeueReusableCellWithIdentifier:@"receipt" forIndexPath:indexPath];
    GRRReceipt *receipt = self.receipts[indexPath.row];
    cell.avatarView.image = self.avatarCache[receipt.userId] ?: [self placeholderFor:receipt];
    cell.textLabel.text = receipt.nickname.length ? receipt.nickname : receipt.userId;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"user_id: %@", receipt.userId];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:receipt.readAt / 1000.0];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    UILabel *timeLabel = [cell.contentView viewWithTag:99];
    if (!timeLabel) {
        timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetWidth(cell.contentView.bounds) - 132, 18, 120, 18)];
        timeLabel.tag = 99;
        timeLabel.font = [UIFont systemFontOfSize:11];
        timeLabel.textColor = [UIColor grayColor];
        timeLabel.textAlignment = NSTextAlignmentRight;
        timeLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [cell.contentView addSubview:timeLabel];
    }
    timeLabel.text = [formatter stringFromDate:date];
    return cell;
}

- (UIImage *)placeholderFor:(GRRReceipt *)receipt {
    NSString *initial = (receipt.nickname ?: receipt.userId).length ? [(receipt.nickname ?: receipt.userId) substringToIndex:1] : @"?";
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 40)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithRed:0.18 green:0.43 blue:0.93 alpha:1] setFill];
        CGContextFillEllipseInRect(context.CGContext, CGRectMake(0, 0, 40, 40));
        [[UIColor whiteColor] setFill];
        [initial drawAtPoint:CGPointMake(14, 8) withAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:18]}];
    }];
}

@end

@interface GRRUI ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, GRRFooterView *> *footers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *lastRefresh;
@property (nonatomic, weak) UIView *currentMenuView;
@property (nonatomic, strong) UIView *floatingMenu;
@end

@implementation GRRUI

+ (instancetype)shared {
    static GRRUI *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _footers = [NSMutableDictionary dictionary];
        _lastRefresh = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)keyChat:(NSString *)chatId msg:(NSString *)msgId {
    return [NSString stringWithFormat:@"%@|%@", chatId ?: @"", msgId ?: @""];
}

- (UIView *)bubbleForView:(UIView *)view {
    if (!view) return nil;
    if ([view isKindOfClass:[UILabel class]]) return view.superview ?: view;
    return view;
}

- (void)refreshFooterForView:(UIView *)view info:(GRRMessageInfo *)info {
    if (!view || !info || ![info isEligibleChat]) return;
    GRRSettings *settings = [GRRSettings shared];
    if (!settings.enabled || ![[GRRStorage shared] isMessageEnabled:info.chatId msgId:info.msgId] ||
        [[GRRStorage shared] isGroupOff:info.chatId]) return;

    NSString *key = [self keyChat:info.chatId msg:info.msgId];
    UIView *bubble = [self bubbleForView:view];
    GRRFooterView *footer = self.footers[key];
    if (!footer || footer.superview != bubble) {
        footer = [[GRRFooterView alloc] initWithFrame:CGRectZero];
        footer.font = [UIFont systemFontOfSize:11];
        footer.textColor = [UIColor grayColor];
        footer.userInteractionEnabled = YES;
        footer.chatId = info.chatId;
        footer.msgId = info.msgId;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(footerTapped:)];
        [footer addGestureRecognizer:tap];
        [bubble addSubview:footer];
        self.footers[key] = footer;
    }
    footer.frame = CGRectMake(8, CGRectGetHeight(bubble.bounds) - 16, CGRectGetWidth(bubble.bounds) - 16, 14);
    [self loadFooter:footer force:NO];
}

- (void)loadFooter:(GRRFooterView *)footer force:(BOOL)force {
    NSString *key = [self keyChat:footer.chatId msg:footer.msgId];
    NSDate *last = self.lastRefresh[key];
    NSTimeInterval interval = MAX(1.0, [GRRSettings shared].refreshInterval);
    if (!force && last && [[NSDate date] timeIntervalSinceDate:last] < interval) return;
    self.lastRefresh[key] = [NSDate date];
    __weak typeof(footer) weakFooter = footer;
    [[GRRNetwork shared] queryChatId:footer.chatId msgId:footer.msgId
                          completion:^(NSArray<GRRReceipt *> *receipts, NSUInteger onlineCount) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakFooter.text = [NSString stringWithFormat:@"已读 %lu / 群内插件在线 %lu 人",
                               (unsigned long)receipts.count, (unsigned long)onlineCount];
        });
    }];
}

- (void)refreshVisibleFooters {
    for (GRRFooterView *footer in [self.footers allValues]) {
        if (footer.window) [self loadFooter:footer force:YES];
    }
}

- (void)removeFooterForMessage:(NSString *)chatId msgId:(NSString *)msgId {
    NSString *key = [self keyChat:chatId msg:msgId];
    GRRFooterView *footer = self.footers[key];
    [footer removeFromSuperview];
    [self.footers removeObjectForKey:key];
    [self.lastRefresh removeObjectForKey:key];
}

- (void)removeFootersForChat:(NSString *)chatId {
    NSMutableArray *remove = [NSMutableArray array];
    for (NSString *key in self.footers) {
        GRRFooterView *footer = self.footers[key];
        if ([footer.chatId isEqualToString:chatId]) [remove addObject:key];
    }
    for (NSString *key in remove) {
        [self.footers[key] removeFromSuperview];
        [self.footers removeObjectForKey:key];
        [self.lastRefresh removeObjectForKey:key];
    }
}

- (void)footerTapped:(UITapGestureRecognizer *)gesture {
    GRRFooterView *footer = (GRRFooterView *)gesture.view;
    UIViewController *controller = [GRRUI topViewController];
    if (controller) [self showReceiptsForChat:footer.chatId msgId:footer.msgId from:controller];
}

+ (UIViewController *)topViewController {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    return controller;
}

- (void)showReceiptsForChat:(NSString *)chatId msgId:(NSString *)msgId from:(UIViewController *)controller {
    if (!controller) return;
    GRRReceiptPopupController *popup = [[GRRReceiptPopupController alloc] initWithChatId:chatId msgId:msgId];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:popup];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [controller presentViewController:navigation animated:YES completion:nil];
}

- (void)setCurrentMenuView:(UIView *)view {
    _currentMenuView = view;
    [self dismissFloatingMenu];
}

- (void)dismissFloatingMenu {
    [self.floatingMenu removeFromSuperview];
    self.floatingMenu = nil;
}

- (void)injectMenu {
    GRRMessageInfo *info = [GRRMessageContext currentMenuMessage];
    if (!info || ![GRRSettings shared].enabled || ![[GRRNetwork shared].currentUserId length]) return;
    if (![info isEligibleChat] || [[GRRStorage shared] isGroupOff:info.chatId]) return;
    if (![info.senderId isEqualToString:[GRRNetwork shared].currentUserId]) return;

    UIMenuItem *item = [[UIMenuItem alloc] initWithTitle:@"开启已读回执统计"
                                                 action:NSSelectorFromString(@"grr_enableReceipt")];
    [UIMenuController sharedMenuController].menuItems = @[item];
    [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];

    // 宿主自定义菜单若无法插入 UIMenuItem，则在消息旁显示等价的浮动入口。
    [self showFloatingMenuForView:self.currentMenuView];
}

- (void)showFloatingMenuForView:(UIView *)view {
    if (!view || !view.window) return;
    [self dismissFloatingMenu];
    CGRect rect = [view convertRect:view.bounds toView:view.window];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(CGRectGetMinX(rect), MAX(60, CGRectGetMinY(rect) - 36), 150, 30);
    button.titleLabel.font = [UIFont systemFontOfSize:12];
    [button setTitle:@"开启已读回执统计" forState:UIControlStateNormal];
    [button setBackgroundColor:[UIColor colorWithWhite:0.1 alpha:0.85]];
    [button.layer setCornerRadius:6];
    [button addTarget:self action:@selector(enableCurrentMenuMessage) forControlEvents:UIControlEventTouchUpInside];
    [view.window addSubview:button];
    self.floatingMenu = button;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self dismissFloatingMenu];
    });
}

- (void)enableCurrentMenuMessage {
    GRRMessageInfo *info = [GRRMessageContext currentMenuMessage];
    [self dismissFloatingMenu];
    if (!info || !info.msgId.length || !info.chatId.length) return;
    if (![info.senderId isEqualToString:[GRRNetwork shared].currentUserId]) return;
    [[GRRStorage shared] markMessageEnabled:info.chatId msgId:info.msgId];
    [[GRRNetwork shared] enableMessage:info.chatId msgId:info.msgId ownerUserId:info.senderId completion:^(BOOL success) {
        [[GRRStorage shared] logAction:@"enable" code:success ? 200 : 0 chatId:info.chatId msgId:info.msgId detail:success ? @"ok" : @"fail"];
    }];
    UIView *view = self.currentMenuView;
    if (view) [self refreshFooterForView:view info:info];
}

@end

@implementation UIResponder (GRRMenu)
- (void)grr_enableReceipt {
    [[GRRUI shared] enableCurrentMenuMessage];
}
@end
