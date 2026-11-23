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

echo "[1/5] 编译业务 dylib: GroupReadReceipt.dylib"
make clean >/dev/null 2>&1 || true
make

echo "[2/5] 编译注册壳 dylib: GRRShell.dylib"
(
  cd Shell
  make clean >/dev/null 2>&1 || true
  make
)

BUSINESS=$(find .theos -type f -name 'GroupReadReceipt.dylib' 2>/dev/null | head -n 1)
SHELL_DYLIB=$(find Shell/.theos -type f -name 'GRRShell.dylib' 2>/dev/null | head -n 1)
if [[ -z "${BUSINESS}" || -z "${SHELL_DYLIB}" ]]; then
  echo "[错误] 编译完成但未找到 dylib，请检查 .theos/obj 目录。" >&2
  exit 1
fi

echo "[3/5] 组装 deb 目录结构"
STAGE="${PWD}/.build/stage"
rm -rf "${STAGE}"
mkdir -p "${STAGE}/DEBIAN"
mkdir -p "${STAGE}/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "${STAGE}/Library/Application Support/GroupReadReceipt"

cp "${BUSINESS}" "${STAGE}/Library/MobileSubstrate/DynamicLibraries/GroupReadReceipt.dylib"
cp "${SHELL_DYLIB}" "${STAGE}/Library/MobileSubstrate/DynamicLibraries/GRRShell.dylib"
cp layout/Library/MobileSubstrate/DynamicLibraries/GroupReadReceipt.plist \
   "${STAGE}/Library/MobileSubstrate/DynamicLibraries/GroupReadReceipt.plist"
cp layout/Library/MobileSubstrate/DynamicLibraries/GRRShell.plist \
   "${STAGE}/Library/MobileSubstrate/DynamicLibraries/GRRShell.plist"
cp GRRHooks.plist "${STAGE}/Library/Application Support/GroupReadReceipt/GRRHooks.plist"
cp deb/DEBIAN/control "${STAGE}/DEBIAN/control"
cp deb/DEBIAN/postinst "${STAGE}/DEBIAN/postinst"
chmod 755 "${STAGE}/DEBIAN/postinst"
chmod 755 "${STAGE}/Library/MobileSubstrate/DynamicLibraries/"*.dylib

echo "[4/5] 打包 deb"
mkdir -p packages
deb="packages/com.group.readreceipt_1.0.0_iphoneos-arm.deb"
rm -f "${deb}"
dpkg-deb -b "${STAGE}" "${deb}"

echo "[5/5] 完成"
echo "产物：${deb}"
echo "内含："
dpkg-deb -c "${deb}" | sed -n '1,20p'
