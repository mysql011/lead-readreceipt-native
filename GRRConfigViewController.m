#import "GRRConfigViewController.h"
#import "GRRSettings.h"
#import "GRRStorage.h"
#import "GRRHookRegistry.h"
#import "Headers/GRRTypes.h"

@interface GRRConfigViewController ()
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISwitch *privacySwitch;
@property (nonatomic, strong) UISwitch *hostLogSwitch;
@property (nonatomic, strong) UITextField *intervalField;
@property (nonatomic, strong) UITextField *backendField;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UILabel *hookStatus;
@end

@implementation GRRConfigViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) self.title = @"群组已读回执";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    GRRSettings *settings = [GRRSettings shared];

    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.on = settings.enabled;
    self.privacySwitch = [[UISwitch alloc] init];
    self.privacySwitch.on = settings.allowReport;
    self.hostLogSwitch = [[UISwitch alloc] init];
    self.hostLogSwitch.on = settings.captureHostLog;

    self.intervalField = [self fieldWithText:[NSString stringWithFormat:@"%.0f", settings.refreshInterval * 1000]
                                 placeholder:@"3000"];
    self.intervalField.keyboardType = UIKeyboardTypeNumberPad;
    self.backendField = [self fieldWithText:settings.backendURL placeholder:@"http://127.0.0.1:8787"];
    self.backendField.keyboardType = UIKeyboardTypeURL;
    self.tokenField = [self fieldWithText:settings.apiToken placeholder:@"可选，与服务端 API_TOKEN 一致"];

    self.hookStatus = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 60)];
    self.hookStatus.numberOfLines = 0;
    self.hookStatus.font = [UIFont systemFontOfSize:12];
    self.hookStatus.textColor = [UIColor grayColor];
    NSArray *installed = [[GRRHookRegistry shared] installedHooks];
    NSArray *failed = [[GRRHookRegistry shared] failedHooks];
    self.hookStatus.text = [NSString stringWithFormat:@"原生钩子：成功 %lu / 失败 %lu\n%@",
                            (unsigned long)installed.count, (unsigned long)failed.count,
                            failed.count ? [failed componentsJoinedByString:@"\n"] : @"已按 GRRHooks.plist 装配"];

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
}

- (UITextField *)fieldWithText:(NSString *)text placeholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 220, 30)];
    field.text = text;
    field.placeholder = placeholder;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    return field;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : (section == 1 ? 3 : (section == 2 ? 2 : 1));
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"开关", @"服务与刷新", @"诊断", @"原生钩子"][section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.accessoryView = nil;
    cell.textLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"启用本插件";
            cell.accessoryView = self.enabledSwitch;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"允许上报我的已读记录";
            cell.accessoryView = self.privacySwitch;
        } else {
            cell.textLabel.text = @"采集宿主错误日志（诊断）";
            cell.accessoryView = self.hostLogSwitch;
        }
    } else if (indexPath.section == 1) {
        NSArray *labels = @[@"后端服务地址", @"刷新间隔（毫秒）", @"访问令牌"];
        cell.textLabel.text = labels[indexPath.row];
        cell.accessoryView = @[self.backendField, self.intervalField, self.tokenField][indexPath.row];
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"保存设置";
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            cell.textLabel.text = @"导出本地日志";
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    } else {
        [cell.contentView addSubview:self.hookStatus];
        self.hookStatus.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.hookStatus.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [self.hookStatus.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [self.hookStatus.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
            [self.hookStatus.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8]
        ]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 2) return;
    if (indexPath.row == 0) {
        GRRSettings *settings = [GRRSettings shared];
        [settings setEnabled:self.enabledSwitch.on];
        [settings setAllowReport:self.privacySwitch.on];
        [settings setCaptureHostLog:self.hostLogSwitch.on];
        [settings setBackendURL:self.backendField.text];
        [settings setRefreshInterval:MAX(1000, self.intervalField.text.doubleValue) / 1000.0];
        [settings setAPIToken:self.tokenField.text];
        [[GRRStorage shared] logAction:@"config" code:200 chatId:@"" msgId:@"" detail:@"saved"];
    } else {
        NSURL *url = [[GRRStorage shared] exportLogFile];
        UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            activity.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
        }
        [self presentViewController:activity animated:YES completion:nil];
    }
}

@end
