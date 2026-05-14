#!/usr/bin/env bash
# =============================================================================
# 构建自定义 Sub2API 镜像并推送到 Docker Hub
# =============================================================================
# 用法: ./build_and_push.sh <dockerhub用户名> [镜像标签]
# 示例: ./build_and_push.sh abevol
#       ./build_and_push.sh abevol v0.1.0
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --------------- 参数 ---------------
DOCKER_USER="${1:-}"
IMAGE_TAG="${2:-latest}"

if [[ -z "$DOCKER_USER" ]]; then
    echo -e "${RED}错误: 请指定 Docker Hub 用户名${NC}"
    echo "用法: $(basename "$0") <dockerhub用户名> [标签]"
    exit 1
fi

IMAGE_NAME="${DOCKER_USER}/sub2api:${IMAGE_TAG}"

# --------------- 构建 ---------------
echo -e "${BLUE}[1/3] 构建镜像: ${IMAGE_NAME}${NC}"

docker build \
    --build-arg GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" \
    --build-arg GOSUMDB="${GOSUMDB:-sum.golang.google.cn}" \
    -t "$IMAGE_NAME" \
    -f "${REPO_ROOT}/Dockerfile" \
    "${REPO_ROOT}"

echo -e "${GREEN}构建完成${NC}"

# --------------- 登录 ---------------
echo ""
echo -e "${BLUE}[2/3] 登录 Docker Hub...${NC}"

if ! docker info 2>/dev/null | grep -q "Username"; then
    docker login
fi

# --------------- 推送 ---------------
echo ""
echo -e "${BLUE}[3/3] 推送镜像...${NC}"

docker push "$IMAGE_NAME"

echo ""
echo -e "${GREEN}完成! 镜像已推送: ${IMAGE_NAME}${NC}"
echo ""
echo "在服务器上拉取:"
echo "  docker pull ${IMAGE_NAME}"
