#!/usr/bin/env bash
# update-codex-version.sh — 从 GitHub Releases 获取最新 Codex CLI 版本号
# 用法: update-codex-version.sh [--apply] [--env-file PATH]
#   --apply       将新版本写入 .env 文件的 CODEX_CLI_VERSION 行
#   --env-file    指定 .env 文件路径（默认自动查找）

set -euo pipefail

APPLY=false
ENV_FILE=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--apply) APPLY=true; shift ;;
		--env-file) ENV_FILE="$2"; shift 2 ;;
		-h|--help)
			echo "用法: $(basename "$0") [--apply] [--env-file PATH]"
			echo ""
			echo "从 GitHub Releases API 获取最新 Codex CLI 版本号。"
			echo ""
			echo "选项:"
			echo "  --apply       将新版本写入 .env 文件的 CODEX_CLI_VERSION 行"
			echo "  --env-file    指定 .env 文件路径（默认自动查找）"
			exit 0
			;;
		*)
			echo "未知参数: $1" >&2
			exit 1
			;;
	esac
done

# 依赖检查
for cmd in curl jq; do
	if ! command -v "$cmd" &>/dev/null; then
		echo "错误: 需要 $cmd，请先安装" >&2
		exit 1
	fi
done

# 自动查找 .env 文件
if [[ -z "$ENV_FILE" ]]; then
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
	if [[ -n "$REPO_ROOT" ]]; then
		if [[ -f "$REPO_ROOT/deploy/.env" ]]; then
			ENV_FILE="$REPO_ROOT/deploy/.env"
		elif [[ -f "$REPO_ROOT/deploy/.env.example" ]]; then
			ENV_FILE="$REPO_ROOT/deploy/.env.example"
		fi
	fi
fi

# 获取最新版本号
RELEASES_URL="https://api.github.com/repos/openai/codex/releases/latest"
echo "正在获取最新 Codex CLI 版本..." >&2

# 用 RESP 变量直接捕获返回体，避免临时文件和 trap 的交互问题
RESP=$(curl -sS -w '\n%{http_code}' "$RELEASES_URL") || {
	echo "错误: curl 请求失败（网络不可达或超时）" >&2
	exit 2
}
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
	echo "错误: GitHub API 返回 HTTP $HTTP_CODE" >&2
	echo "$BODY" >&2
	exit 2
fi

TAG_NAME=$(echo "$BODY" | jq -r '.tag_name // empty')
if [[ -z "$TAG_NAME" ]]; then
	echo "错误: 无法从 API 响应中解析 tag_name" >&2
	exit 3
fi

# 从 tag_name 中提取 X.Y.Z 版本号（tag 格式如 "rust-v0.130.0" 或 "v0.125.0"）
VERSION=$(echo "$TAG_NAME" | grep -oP '\d+\.\d+\.\d+' | head -1)
if [[ -z "$VERSION" ]]; then
	echo "错误: 无法从 tag_name 中提取版本号: $TAG_NAME" >&2
	exit 4
fi

echo "$VERSION"

# 写入 .env 文件
if [[ "$APPLY" == true ]]; then
	if [[ -z "$ENV_FILE" ]]; then
		echo "错误: 未找到 .env 文件，请用 --env-file 指定" >&2
		exit 5
	fi
	if ! [[ -f "$ENV_FILE" ]]; then
		echo "错误: 文件不存在: $ENV_FILE" >&2
		exit 6
	fi
	if grep -q "^CODEX_CLI_VERSION=" "$ENV_FILE"; then
		sed -i "s/^CODEX_CLI_VERSION=.*/CODEX_CLI_VERSION=$VERSION/" "$ENV_FILE"
	else
		echo "CODEX_CLI_VERSION=$VERSION" >> "$ENV_FILE"
	fi
	echo "已更新 $ENV_FILE -> CODEX_CLI_VERSION=$VERSION" >&2
fi
