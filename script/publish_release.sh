#!/usr/bin/env bash
#
# 把 dist/ 里的安装包发布到 GitHub Release（可重复执行，已存在则覆盖附件）。
#
# 用法：
#   ./script/publish_release.sh v1.0.2            # 创建/更新 v1.0.2 的 Release
#   ./script/publish_release.sh v1.0.2 --draft    # 创建为草稿 Release
#
# 依赖：gh（已登录；CI 中通过 GH_TOKEN 环境变量认证）
# 前置：先跑 ./script/package_release.sh 生成 dist/ 下的产物
#
# 注意：脚本要在 macOS 自带的 bash 3.2 下也能跑，所有变量展开都写成 ${VAR}，
# 避免 ${VAR} 后面紧跟中文标点时被 bash 3.2 当作变量名的一部分。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
REPO="${REPO:-MIN202299/MouserNative}"

TAG="${1:-}"
DRAFT=0
for arg in "$@"; do
  if [[ "${arg}" == "--draft" ]]; then
    DRAFT=1
  fi
done

step() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -z "${TAG}" || "${TAG}" == --* ]]; then
  die "用法：$0 <tag> [--draft]，例如 $0 v1.0.2"
fi
command -v gh >/dev/null || die "找不到 gh CLI（brew install gh）"

NOTES_FILE="${DIST_DIR}/release-notes.md"
[[ -f "${NOTES_FILE}" ]] || die "找不到 ${NOTES_FILE}，请先运行 ./script/package_release.sh"

shopt -s nullglob
ASSETS=("${DIST_DIR}"/*.dmg "${DIST_DIR}"/*.zip)
shopt -u nullglob
[[ ${#ASSETS[@]} -gt 0 ]] || die "${DIST_DIR} 里没有 .dmg/.zip 安装包"

TITLE="Mouser ${TAG#v}"
step "发布 ${TAG}：共 ${#ASSETS[@]} 个附件 → ${REPO}"

if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  step "Release ${TAG} 已存在，覆盖附件并更新说明"
  gh release upload "${TAG}" "${ASSETS[@]}" --repo "${REPO}" --clobber
  gh release edit "${TAG}" --repo "${REPO}" --title "${TITLE}" --notes-file "${NOTES_FILE}"
else
  step "创建 Release ${TAG}"
  # 注意：${DRAFT_ARG} 故意不加引号，空值时该参数自动消失（兼容 bash 3.2）
  DRAFT_ARG=""
  if [[ "${DRAFT}" == "1" ]]; then
    DRAFT_ARG="--draft"
  fi

  if git -C "${ROOT_DIR}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    gh release create "${TAG}" "${ASSETS[@]}" \
      --repo "${REPO}" --title "${TITLE}" --notes-file "${NOTES_FILE}" ${DRAFT_ARG}
  else
    gh release create "${TAG}" "${ASSETS[@]}" \
      --repo "${REPO}" --title "${TITLE}" --notes-file "${NOTES_FILE}" \
      --target "$(git -C "${ROOT_DIR}" rev-parse HEAD)" ${DRAFT_ARG}
  fi
fi

step "完成：https://github.com/${REPO}/releases/tag/${TAG}"
