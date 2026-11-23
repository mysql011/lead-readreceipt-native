# Hook 点适配说明

## 1. 为什么需要适配

Turrit 的类名与方法签名不在交付物中，因此 `GRRHooks.plist` 提供的是 Telegram-iOS 系客户端的常见候选值。插件在启动时逐个探测 `objc_getClass` 与 `class_getInstanceMethod`，命中的才用 `MSHookMessageEx` 安装，未命中的写入 `hook` 日志的 `failed` 列表。

配置页「原生钩子」区直接显示：成功数、失败数、失败项。

## 2. 五类钩子

| kind | 用途 | 命中后的行为 |
| --- | --- | --- |
| `Identity` | 解析当前登录用户 ID | 从返回对象按 `id / userId / uid` 取值，写入 `GRRNetwork.currentUserId` |
| `Render` | 消息渲染 / 绑定视图 | 解析消息、绑定上下文、注册到可视追踪、刷新气泡小字 |
| `LongPress` | 长按消息 | 记录当前消息与视图，供菜单注入定位 |
| `Menu` | 菜单构建 | 注入【开启已读回执统计】，失败时显示浮动入口 |
| `Delete` | 消息撤回 / 删除 | 清理本地标记、UI、追踪项并通知后端 |

## 3. 如何找到真实类与方法

在越狱设备或IDA/Frida 环境中：

```bash
class-dump -H Turrit.app/Turrit -o dump
grep -R "Message.*Cell\|ConversationController\|MenuView\|currentUser" dump | head -50
```

Frida 运行时枚举：

```javascript
ObjC.enumerateLoadedClassesSync().filter(n => /Message|Conversation|Menu|User/.test(n))
  .slice(0, 80).forEach(n => console.log(n));
```

找到后编辑 `GRRHooks.plist`，把 `class` / `selector` 换成真实值。

## 4. signature 约定

`MSHookMessageEx` 的 replacement 必须与原方法调用约定一致，否则会破坏宿主。插件提供 6 种模板：

| signature | 含义 | 典型用途 |
| --- | --- | --- |
| `void0` | 无参数，无返回 | `deleteMessage` |
| `void1` | 1 个参数，无返回 | `setMessage:`、`messageLongPressed:` |
| `void2` | 2 个参数，无返回 | `configureMessageCell:atIndexPath:` |
| `obj0` | 无参数，返回对象 | `+currentUser` |
| `obj1` | 1 个参数，返回对象 | 返回菜单数组的构建方法 |
| `obj2` | 2 个参数，返回对象 | 较少见 |

带 `*` 的 selector 参数数量必须与 `voidN`/`objN` 中的 N 一致。

## 5. 消息字段解析（KVC 候选键）

`GRRMessageContext` 不依赖具体类名，按顺序尝试：

- 消息 ID：`msgId / messageId / _identifier / identifier / mid / id`
- 会话与群 ID：`chat / conversation / peer / chatInfo` 下的 `id / chatId / identifier / peerId`
- 发送者：`sender / from / author / fromUser / user` 下的 `id / senderId / fromId / userId / uid`
- 文本：`text / messageText / content / message`
- 会话类型：`chat.type / chatType / peerType`，或 `isChannel / isPrivate / isGroup`;最后用类名与群 ID 负号前缀兜底。

如真机使用完全不同的属性名，在 `GRRMessageContext.m` 的候选数组中补一条即可。

## 6. 群管理员指令接入

`/receipt on|off` 已在 `Render` 钩子链路中直接解析消息文本（正则 `^\s*/receipt\s+(on|off)\b`），不依赖宿主的指令处理方法。判定为管理员后执行：

```objc
[[GRRStorage shared] setGroup:chatId off:!enabled];
[[GRRUI shared] removeFootersForChat:chatId];          // off 时
[[GRRVisibilityTracker shared] untrackChat:chatId];   // off 时
[[GRRNetwork shared] groupSwitch:chatId enabled:enabled operatorUserId:senderId completion:nil];
```

管理员判定通过 KVC 候选键 `sender.isAdmin / from.isAdmin / isGroupAdmin / isChannelAdmin` 读取；若 Turrit 使用其他属性名，在 `GRRHandleGroupCommand` 的候选数组中补一条。若完全无法解析管理员身份，指令会被安全忽略并记录 403。服务端也可配置 `GROUP_ADMINS` 做二次强校验。

## 7. 菜单注入的两级策略

1. 首选 `UIMenuController.menuItems` 插入 `UIMenuItem`，action 为 `grr_enableReceipt`（已通过 UIResponder 分类实现）。
2. 若宿主使用自绘菜单且无法插入，长按钩子会在消息气泡旁显示一个等价的浮动按钮，4 秒后自动消失。

## 8. 安全降级

- Identity 未命中：不上报，只记录日志。
- Render 未命中：无可视追踪，不显示小字。
- fishhook 头文件缺失：跳过宿主日志采集，主功能不受影响。
- 后端不可达：本地队列持久化，网络恢复或定时刷新时重试，单批次最多 2 次重试。
