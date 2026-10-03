#!/usr/bin/env bash
#
# 构建 Mouser.app 并打包成可分发的安装包（DMG + ZIP），同时在 dist/ 生成
# release-notes.md（发布说明），供 GitHub Release 使用。
#
# 用法：
#   ./script/package_release.sh                 # 构建 + 打包到 dist/
#   SKIP_BUILD=1 ./script/package_release.sh    # 复用已有产物，只打包
#
# 可覆盖的环境变量：
#   CONFIGURATION  构建配置，默认 Release
#   BUILD_ARCHS    构建架构，默认 "arm64 x86_64"（通用二进制）
#   DERIVED_DATA   DerivedData 路径，默认 .build/DerivedData
#   DIST_DIR       产物目录，默认 dist/
#   VERSION        覆盖版本号，默认取 Info.plist 的 CFBundleShortVersionString
#
# 说明：本项目没有付费开发者账号，安装包只做 ad-hoc 临时签名，未做 Apple 公证。
# 用户首次打开需要手动放行（见 dist/release-notes.md）。
#
# 注意：脚本要在 macOS 自带的 bash 3.2 下也能跑，所有变量展开都写成 ${VAR}，
# 避免 ${VAR} 后面紧跟中文标点时被 bash 3.2 当作变量名的一部分。
set -euo pipefail

APP_NAME="Mouser"
SCHEME="Mouser"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${ROOT_DIR}/Mouser.xcodeproj"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_ARCHS="${BUILD_ARCHS:-arm64 x86_64}"
DERIVED_DATA="${DERIVED_DATA:-${ROOT_DIR}/.build/DerivedData}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
APP_BUNDLE="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
APP_BINARY="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"

step() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warn\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror\033[0m %s\n' "$*" >&2; exit 1; }

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "${INFO_PLIST}" 2>/dev/null || true
}

# --- 1. 构建 ---------------------------------------------------------------

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  step "构建 ${APP_NAME}：${CONFIGURATION} / ${BUILD_ARCHS} / 关闭 Xcode 签名"
  rm -rf "${APP_BUNDLE}"
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -destination 'generic/platform=macOS' \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="${BUILD_ARCHS}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build
else
  step "跳过构建：SKIP_BUILD=1，直接使用 ${APP_BUNDLE}"
fi

[[ -d "${APP_BUNDLE}" ]] || die "找不到构建产物：${APP_BUNDLE}"
[[ -x "${APP_BINARY}" ]] || die "找不到可执行文件：${APP_BINARY}"

# --- 2. 版本信息 -----------------------------------------------------------

VERSION="${VERSION:-$(plist_value CFBundleShortVersionString)}"
BUILD_NUMBER="$(plist_value CFBundleVersion)"
MIN_MACOS="$(plist_value LSMinimumSystemVersion)"
[[ -n "${VERSION}" ]] || die "无法从 Info.plist 读取版本号"
BUILD_NUMBER="${BUILD_NUMBER:-0}"
MIN_MACOS="${MIN_MACOS:-14.0}"

ARCHS_IN_BINARY="$(lipo -archs "${APP_BINARY}" 2>/dev/null || true)"
case "${ARCHS_IN_BINARY}" in
  *arm64*x86_64*|*x86_64*arm64*) ARCH_DESC="Apple Silicon（M 系列）与 Intel" ;;
  *arm64*)                       ARCH_DESC="Apple Silicon（M 系列）" ;;
  *x86_64*)                      ARCH_DESC="Intel" ;;
  *)                             ARCH_DESC="${ARCHS_IN_BINARY:-未知}" ;;
esac

step "版本 ${VERSION} / build ${BUILD_NUMBER} / 最低系统 macOS ${MIN_MACOS} / 架构 ${ARCH_DESC}"

# --- 3. 清理 + ad-hoc 签名 -------------------------------------------------

step "清理扩展属性，做 ad-hoc 临时签名"
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true
find "${APP_BUNDLE}" -name '.DS_Store' -delete 2>/dev/null || true
codesign --force --sign - --timestamp=none "${APP_BUNDLE}"
codesign --verify --strict --verbose=2 "${APP_BUNDLE}" 2>&1 | sed 's/^/    /'

# --- 4. DMG / ZIP ----------------------------------------------------------

mkdir -p "${DIST_DIR}"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"

step "生成 DMG：${DMG_PATH}"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGING_DIR}"' EXIT
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}" >/dev/null

step "生成 ZIP：${ZIP_PATH}"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

SHA_DMG="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
SHA_ZIP="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"

# --- 5. 发布说明 -----------------------------------------------------------

step "生成发布说明：${DIST_DIR}/release-notes.md"
sed \
  -e "s|__VERSION__|${VERSION}|g" \
  -e "s|__APP_NAME__|${APP_NAME}|g" \
  -e "s|__BUILD_NUMBER__|${BUILD_NUMBER}|g" \
  -e "s|__MIN_MACOS__|${MIN_MACOS}|g" \
  -e "s|__ARCH_DESC__|${ARCH_DESC}|g" \
  -e "s|__SHA_DMG__|${SHA_DMG}|g" \
  -e "s|__SHA_ZIP__|${SHA_ZIP}|g" > "${DIST_DIR}/release-notes.md" <<'NOTES_EOF'
轻量、完全本地的 Logitech 鼠标按键重映射 macOS 应用：无遥测、无云端、不需要罗技账号。

## 下载与安装

| 文件 | 说明 |
| --- | --- |
| `__APP_NAME__-__VERSION__.dmg` | 推荐。打开后把 **__APP_NAME__** 拖进「应用程序」 |
| `__APP_NAME__-__VERSION__.zip` | 备用。解压后把 `__APP_NAME__.app` 拖进「应用程序」 |

1. 下载并打开 DMG，把 **__APP_NAME__** 拖到「应用程序」文件夹。
2. 从「应用程序」里打开 __APP_NAME__。

### 首次打开被系统拦下怎么办

安装包使用 **ad-hoc 临时签名**，未经过 Apple 公证（需要付费开发者账号），
因此第一次打开时 macOS 会提示「无法验证开发者」或「已损坏」。任选一种方式放行：

- **右键打开**：在「应用程序」里右键（或按住 Control 点击）__APP_NAME__，选择「打开」，弹窗里再点一次「打开」；
- **或在「终端」执行一次**（复制整行回车）：

      xattr -dr com.apple.quarantine /Applications/__APP_NAME__.app

3. 首次运行按引导授权两项权限（系统设置 → 隐私与安全性）：
   - **辅助功能**：拦截鼠标按键事件；
   - **输入监控**：通过蓝牙与鼠标通信（HID++）。
4. 鼠标需已通过蓝牙（BLE）配对连接。

## 校验

    shasum -a 256 __APP_NAME__-__VERSION__.dmg

- `__APP_NAME__-__VERSION__.dmg`：`__SHA_DMG__`
- `__APP_NAME__-__VERSION__.zip`：`__SHA_ZIP__`

## 系统要求

- macOS __MIN_MACOS__ 或更高
- 架构：__ARCH_DESC__
- 构建号：__BUILD_NUMBER__
NOTES_EOF

# --- 6. 汇总 ---------------------------------------------------------------

ls -lh "${DMG_PATH}" "${ZIP_PATH}" | sed 's/^/    /'
step "打包完成，产物在 ${DIST_DIR}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=${VERSION}"
    echo "build_number=${BUILD_NUMBER}"
    echo "dmg=${DMG_PATH}"
    echo "zip=${ZIP_PATH}"
    echo "archs=${ARCHS_IN_BINARY}"
  } >> "${GITHUB_OUTPUT}"
fi
