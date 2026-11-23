'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const read = (relative) => fs.readFileSync(path.join(ROOT, relative), 'utf8');

const businessFiles = [
  'GroupReadReceipt.m',
  'GRRSettings.m',
  'GRRStorage.m',
  'GRRNetwork.m',
  'GRRMessageContext.m',
  'GRRHookRegistry.m',
  'GRRVisibilityTracker.m',
  'GRRUI.m',
  'GRRConfigViewController.m',
  'GRRFishhookBridge.m',
  'Headers/GRRMessageInfo.m'
];

test('业务 dylib 不依赖 Lead JS 沙箱与内部钩子 API', () => {
  const banned = [/Lead\s*JS/, /messageHook/, /uiContextMenu/, /LeadPluginReadReceipt/, /window\.Lead/];
  for (const file of businessFiles) {
    const source = read(file);
    for (const pattern of banned) {
      assert.equal(pattern.test(source), false, `${file} 不应包含 ${pattern}`);
    }
  }
  const shell = read('Shell/GRRShell.m');
  assert.ok(shell.includes('LeadPluginDescriptorAvailableNotification'), '注册壳应只做面板注册');
  assert.ok(!shell.includes('MSHookMessageEx'), '注册壳不应包含业务 hook');
});

test('原生 hook 使用 MSHookMessageEx 且构造入口独立', () => {
  const registry = read('GRRHookRegistry.m');
  assert.ok(registry.includes('MSHookMessageEx'), '应使用 MSHookMessageEx');
  for (const kind of ['Identity', 'Render', 'LongPress', 'Menu', 'Delete']) {
    assert.ok(registry.includes(`[kind isEqualToString:@"${kind}"]`), `缺少 ${kind} 钩子分发`);
  }
  assert.ok(read('GroupReadReceipt.m').includes('__attribute__((constructor))'), '缺少 dylib 构造入口');
  assert.ok(read('GRRFishhookBridge.m').includes('rebind_symbols'), '应包含 fishhook 重绑定');
});

test('核心阈值写死：800ms 停留与最多 2 次重试', () => {
  const types = read('Headers/GRRTypes.h');
  assert.ok(/GRRDwellThreshold\s*=\s*0\.8/.test(types));
  assert.ok(/GRRMaxRetry\s*=\s*2/.test(types));
  const tracker = read('GRRVisibilityTracker.m');
  assert.ok(/dwell\s*>=\s*GRRDwellThreshold/.test(tracker));
  const network = read('GRRNetwork.m');
  assert.ok(/attempt\s*<\s*GRRMaxRetry/.test(network));
});

test('六个后端接口全部由原生网络层调用', () => {
  const network = read('GRRNetwork.m');
  for (const endpoint of [
    '/api/report', '/api/query', '/api/groupSwitch',
    '/api/message/enable', '/api/presence', '/api/message/clear'
  ]) {
    assert.ok(network.includes(endpoint), `缺少接口 ${endpoint}`);
  }
});

test('隐私开关与私聊/频道过滤存在', () => {
  assert.ok(read('Headers/GRRTypes.h').includes('GRRKeyAllowReport'));
  assert.ok(read('GRRSettings.m').includes('isReportingAllowed'));
  const model = read('Headers/GRRMessageInfo.m');
  assert.ok(model.includes('isGroup && !self.isPrivate && !self.isChannel'));
  const tracker = read('GRRVisibilityTracker.m');
  assert.ok(tracker.includes('settings.allowReport'));
  assert.ok(tracker.includes('isGroupOff'));
});

test('群管理员指令在渲染链路中闭环', () => {
  const registry = read('GRRHookRegistry.m');
  assert.ok(registry.includes('GRRHandleGroupCommand'));
  assert.ok(registry.includes('/receipt') && registry.includes('(on|off)'));
  assert.ok(registry.includes('groupSwitch:info.chatId'));
  assert.ok(read('GRRUI.m').includes('removeFootersForChat'));
  assert.ok(read('GRRVisibilityTracker.m').includes('untrackChat'));
});

test('hook 声明表包含全部钩子类型与 Turrit 过滤', () => {
  const plist = read('GRRHooks.plist');
  for (const kind of ['Identity', 'Render', 'LongPress', 'Menu', 'Delete']) {
    assert.ok(plist.includes(`<key>${kind}</key>`), `plist 缺少 ${kind}`);
  }
  const filter = read('layout/Library/MobileSubstrate/DynamicLibraries/GroupReadReceipt.plist');
  assert.ok(filter.includes('Turrit'));
  assert.ok(fs.existsSync(path.join(ROOT, 'layout/Library/MobileSubstrate/DynamicLibraries/GRRShell.plist')));
});

test('deb 元数据与后端 7 天清理策略', () => {
  const control = read('deb/DEBIAN/control');
  assert.ok(control.includes('Package: com.group.readreceipt'));
  assert.ok(control.includes('Architecture: iphoneos-arm'));
  const backendConfig = fs.readFileSync(path.join(ROOT, '..', 'server', 'config.js'), 'utf8');
  assert.ok(backendConfig.includes('RETENTION_DAYS'));
  const server = fs.readFileSync(path.join(ROOT, '..', 'server', 'server.js'), 'utf8');
  assert.ok(server.includes('cleanupLoop'));
});
