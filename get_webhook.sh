#!/bin/sh
set -eu

# GitHub Releases: https://github.com/adnanh/webhook/releases
# 默认通过 GitHub API 获取最新 release 的资产列表。

RELEASES_API="https://api.github.com/repos/adnanh/webhook/releases/latest"
DOWNLOAD_BASE="https://github.com/adnanh/webhook/releases/download"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)}"

die() {
  printf '错误: %s\n' "$1" >&2
  exit 1
}

detect_os() {
  case "$(uname -s)" in
    Linux) printf 'linux' ;;
    Darwin) printf 'darwin' ;;
    FreeBSD) printf 'freebsd' ;;
    OpenBSD) printf 'openbsd' ;;
    *) die "不支持的操作系统: $(uname -s)" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    i386|i486|i586|i686) printf '386' ;;
    arm|armv5*|armv6*|armv7*|armv8*) printf 'arm' ;;
    *) die "不支持的 CPU 架构: $(uname -m)" ;;
  esac
}

tmpdir=''
output_tmp=''

cleanup() {
  if [ -n "$output_tmp" ]; then
    rm -f "$output_tmp"
  fi
  if [ -n "$tmpdir" ]; then
    rm -rf "$tmpdir"
  fi
}

trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

command -v curl >/dev/null 2>&1 || die '需要 curl，请先安装'
command -v tar >/dev/null 2>&1 || die '需要 tar，请先安装'

os="${WEBHOOK_OS:-$(detect_os)}"
arch="${WEBHOOK_ARCH:-$(detect_arch)}"
asset_name="webhook-${os}-${arch}.tar.gz"

printf '目标平台: %s/%s\n' "$os" "$arch"

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/get-webhook.XXXXXX")

if [ -n "${WEBHOOK_VERSION:-}" ]; then
  tag="$WEBHOOK_VERSION"
  asset_url="${DOWNLOAD_BASE}/${tag}/${asset_name}"
else
  release_json="$tmpdir/release.json"
  curl -fsSL "$RELEASES_API" -o "$release_json" || die '无法获取最新 release 信息'

  tag=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$release_json" | head -n 1)
  [ -n "$tag" ] || die '无法解析最新 release 版本号'

  asset_url=$(sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$release_json" | grep -F "/${asset_name}" | head -n 1)
  [ -n "$asset_url" ] || die "最新 release 中没有找到 ${asset_name}，可通过 WEBHOOK_OS/WEBHOOK_ARCH 覆盖自动检测"
fi

printf '下载 webhook %s: %s\n' "$tag" "$asset_url"
curl -fsSL --retry 3 "$asset_url" -o "$tmpdir/$asset_name" || die '下载失败'

mkdir -p "$OUTPUT_DIR"
printf '解压 %s ...\n' "$asset_name"
tar -xzf "$tmpdir/$asset_name" -C "$tmpdir" || die '解压失败'

binary=$(find "$tmpdir" -type f -name webhook | head -n 1)
[ -n "$binary" ] || die '压缩包中未找到 webhook 二进制文件'

output_tmp="$OUTPUT_DIR/.webhook.$$"
cp "$binary" "$output_tmp"
chmod 0755 "$output_tmp"
mv -f "$output_tmp" "$OUTPUT_DIR/webhook"
output_tmp=''

printf '完成: %s\n' "$OUTPUT_DIR/webhook"
