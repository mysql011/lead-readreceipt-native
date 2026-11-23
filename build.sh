#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -z "${THEOS:-}" || ! -d "${THEOS}" ]]; then
  echo "[错误] 未找到 Theos。请先安装并设置：export THEOS=\$HOME/theos" >&2
  exit 1
fi
if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "[错误] 缺少 dpkg-deb。macOS 上执行：brew install dpkg" >&2
  exit 1
fi

echo "[1/4] 编译 dylib（注册壳源码已并入主 dylib）"
make clean >/dev/null 2>&1 || true
make

MAIN=$(find .theos -type f -name 'GroupReadReceipt.dylib' 2>/dev/null | head -n 1)
if [[ -z "${MAIN}" ]]; then
  echo "[错误] 编译完成但未找到 dylib。" >&2
  exit 1
fi

echo "[2/4] ad-hoc 规范签名（codesign -s -）"
if command -v codesign >/dev/null 2>&1; then
  codesign --remove-signature "${MAIN}" 2>/dev/null || true
  codesign --force --sign - --timestamp=none "${MAIN}"
  echo "签名完成：$(codesign -dv "${MAIN}" 2>&1 | head -n 2)"
else
  echo "[提示] 未找到 codesign，使用 ldid 伪签名"
  ldid -S "${MAIN}"
fi

echo "[3/4] 组装 deb（仅一个 dylib）"
STAGE="${PWD}/.build/stage"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/DEBIAN"
mkdir -p "${STAGE}/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "${STAGE}/Library/Application Support/GroupReadReceipt"

cp "${MAIN}" "${STAGE}/Library/MobileSubstrate/DynamicLibraries/GroupReadReceipt.dylib"
cp layout/Library/MobileSubstrate/DynamicLibraries/GroupReadReceipt.plist \
   "${STAGE}/Library/MobileSubstrate/DynamicLibraries/GroupReadReceipt.plist"
cp GRRHooks.plist "${STAGE}/Library/Application Support/GroupReadReceipt/GRRHooks.plist"
cp deb/DEBIAN/control "${STAGE}/DEBIAN/control"
cp deb/DEBIAN/postinst "${STAGE}/DEBIAN/postinst"
chmod 755 "${STAGE}/DEBIAN/postinst"
chmod 755 "${STAGE}/Library/MobileSubstrate/DynamicLibraries/GroupReadReceipt.dylib"
# postinst 中不再需要对 GRRShell.dylib 授权，保持兼容即可

echo "[4/4] 打包 deb"
mkdir -p packages
deb="packages/com.group.readreceipt_1.0.0_iphoneos-arm.deb"
rm -f "${deb}"
dpkg-deb -b "${STAGE}" "${deb}"

echo "产物：${deb}"
dpkg-deb -c "${deb}" | sed -n '1,20p'
