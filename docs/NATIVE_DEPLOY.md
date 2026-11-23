# 独立注入插件 · 原生 dylib 部署文档

## 1. 架构

```
Turrit 进程
├── GroupReadReceipt.dylib   全部业务逻辑（独立实现，零 Lead JS API 依赖）
│   ├── MSHookMessageEx      原生 ObjC hook（渲染 / 长按 / 菜单 / 撤回 / 身份）
│   ├── fishhook             可选：重绑定 NSLog 采集宿主诊断日志
│   ├── GRRVisibilityTracker 自研 800ms 可视停留判定 + 去重上报
│   ├── GRRNetwork           NSURLSession + 本地队列 + 最多 2 次重试
│   ├── GRRStorage           本地标记 / 去重 / 队列 / 结构化日志
│   └── GRRUI                气泡小字 / 菜单项 / 已读列表弹窗 / 配置页
└── GRRShell.dylib           极简注册壳（仅面板开关 + 配置页入口，无业务逻辑）
```

与上一版 JS 插件的区别：不加载 `Lead` JS 沙箱，不调用 `messageHook` / `uiContextMenu` 等 Lead 内部 API；只借用 Lead 的注入与面板展示能力。

## 2. 构建（macOS + Theos）

```bash
export THEOS=$HOME/theos
cd native
bash build.sh
```

产物为 `native/packages/com.group.readreceipt_1.0.0_iphoneos-arm.deb`，内含：

- `Library/MobileSubstrate/DynamicLibraries/GroupReadReceipt.dylib`
- `Library/MobileSubstrate/DynamicLibraries/GRRShell.dylib`
- 两个对应的过滤 plist
- `Library/Application Support/GroupReadReceipt/GRRHooks.plist`

依赖：

- `substrate.h` / `MSHookMessageEx`（Theos 自带）。
- `fishhook.h`：可选。放在 Theos include 路径中即自动启用宿主日志采集；缺失时编译自动跳过并写 `fishhook header-missing-skipped` 日志，不影响主功能。

## 3. 全能签注入

1. 准备有使用权的 `Turrit.ipa`。
2. 全能签中打开目标应用，进入 **【第三方库】/【添加第三方库】**。
3. 选择上一步产出的 `com.group.readreceipt_1.0.0_iphoneos-arm.deb` 注入。
4. 保持原 Bundle ID 与签名证书，重新签名并安装。
5. 首次启动后确认两个 dylib 均已加载：配置页「原生钩子」区会显示成功/失败数量。
6. 在 Lead 面板中打开本插件开关，进入配置页填写后端地址与令牌。

**过滤 plist 必须先核对真机 Bundle ID**（见 `layout/.../*.plist` 中的 `com.turrit.Turrit` 候选值）。可用：

```bash
class-dump --info Turrit.app/Turrit | head
# 或从越狱设备：dpkg -l | grep -i turrit
```

若 Bundle ID 不匹配，dylib 不会注入，配置页也不会出现。

## 4. 后端

直接复用 `../server`（Node + SQLite，7 天清理）。启动：

```bat
cd ../server
start.cmd
```

接口：`/api/report`、`/api/query`、`/api/groupSwitch`、`/api/message/enable`、`/api/presence`、`/api/message/clear`，与 JS 版完全一致。配置页中填入后端地址；若服务端设置了 `API_TOKEN`，插件配置页的「访问令牌」必须一致。

## 5. 关键适配点

原生插件不知道 Turrit 的具体类名，因此使用 `GRRHooks.plist` 声明候选类与方法，并在运行时探测。正式交付前必须按真机类结构完成一次适配，详见 `HOOK_POINTS.md`。

若 `Identity` 钩子未命中，`GRRNetwork.currentUserId` 为空，所有上报会被安全跳过（配置页会提示 `unresolved`）。

## 6. 验证清单

- 长按自己发的群消息 → 出现【开启已读回执统计】；长按他人消息 → 不出现。
- 点击开启 → 气泡底部出现「已读 0 / 群内插件在线 Y 人」。
- 另一台设备安装插件并浏览该消息 800ms 以上 → 计数变为 1，弹窗显示完整字段。
- 快速划过不报；反复划入不重复报。
- 关闭隐私开关 → 本机零上报；配置页导出日志中无 `POST /api/report`。
- 管理员发 `/receipt off` → 该群不再上报与展示；`/receipt on` 恢复（管理员身份的 KVC 候选键见 HOOK_POINTS.md）。
- 私聊 / 频道 → 无任何回执 UI 与网络请求。
- 撤回消息 → 本地标记与后端记录清理。

## 7. 隐私边界

- 不抓取 MTProto 数据包，不接触会话密钥。
- 隐私总开关关闭后本机零上报。
- 只处理开启标记的消息；私聊与频道写死禁用。
- 所有数据只发往配置中自托管的后端地址。
