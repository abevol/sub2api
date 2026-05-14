#!/bin/bash
# =============================================================================
# Sub2API 自定义镜像快速部署脚本
# =============================================================================
# 用于一键部署你自己的 Sub2API 镜像（替代官方 weishaw/sub2api）。
#
# 用法:
#   1. 先构建并推送你的镜像: ./build_and_push.sh <你的DockerHub用户名>
#   2. 在服务器上运行本脚本:
#      ./docker-deploy-custom.sh <你的DockerHub用户名> [标签]
#
# 示例:
#   ./docker-deploy-custom.sh abevol
#   ./docker-deploy-custom.sh abevol v1.0.0
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --------------- 参数 ---------------
DOCKER_USER="${1:-}"
IMAGE_TAG="${2:-latest}"

if [[ -z "$DOCKER_USER" ]]; then
    print_error "请指定 Docker Hub 用户名"
    echo "用法: $(basename "$0") <dockerhub用户名> [标签]"
    exit 1
fi

IMAGE_NAME="${DOCKER_USER}/sub2api:${IMAGE_TAG}"

# --------------- 依赖检查 ---------------
for cmd in openssl docker; do
    if ! command -v "$cmd" &>/dev/null; then
        print_error "$cmd 未安装，请先安装"
        exit 1
    fi
done

# --------------- 拉取镜像 ---------------
print_info "拉取镜像: ${IMAGE_NAME}..."
docker pull "$IMAGE_NAME"
print_ok "镜像拉取完成"

# --------------- 生成密钥 ---------------
gen_secret() { openssl rand -hex 32; }

JWT_SECRET=$(gen_secret)
TOTP_ENCRYPTION_KEY=$(gen_secret)
POSTGRES_PASSWORD=$(gen_secret)

# --------------- 生成 .env ---------------
cat > .env << ENVEOF
# ============================================================
# Sub2API 环境配置（由 docker-deploy-custom.sh 自动生成）
# 镜像: ${IMAGE_NAME}
# ============================================================

# --- 服务 ---
BIND_HOST=0.0.0.0
SERVER_PORT=8080
SERVER_MODE=release
RUN_MODE=standard
TZ=Asia/Shanghai

# --- 密钥（自动生成，请妥善保管）---
JWT_SECRET=${JWT_SECRET}
TOTP_ENCRYPTION_KEY=${TOTP_ENCRYPTION_KEY}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# --- 数据库 ---
POSTGRES_USER=sub2api
POSTGRES_DB=sub2api
DATABASE_HOST=postgres
DATABASE_PORT=5432
DATABASE_SSLMODE=disable

# --- Redis ---
REDIS_HOST=redis
REDIS_PORT=6379

# --- 自动初始化 ---
AUTO_SETUP=true
# ADMIN_EMAIL=admin@example.com
# ADMIN_PASSWORD=   # 留空则自动生成并输出到日志

# --- Codex CLI 版本号 ---
CODEX_CLI_VERSION=0.130.0
ENVEOF

print_ok ".env 已生成"

# --------------- 生成 docker-compose.yml ---------------
cat > docker-compose.yml << COMPOSEEOF
# ============================================================
# Sub2API Docker Compose（自定义镜像: ${IMAGE_NAME}）
# 由 docker-deploy-custom.sh 自动生成
# ============================================================

services:
  sub2api:
    image: ${IMAGE_NAME}
    container_name: sub2api
    restart: unless-stopped
    ports:
      - "\${BIND_HOST:-0.0.0.0}:\${SERVER_PORT:-8080}:8080"
    env_file:
      - .env
    environment:
      - DATABASE_HOST=postgres
      - DATABASE_PORT=5432
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    volumes:
      - ./data:/app/data
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - sub2api-net
    healthcheck:
      test: ["CMD", "wget", "-q", "-T", "5", "-O", "/dev/null", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  postgres:
    image: postgres:18-alpine
    container_name: sub2api-pg
    restart: unless-stopped
    environment:
      - POSTGRES_USER=\${POSTGRES_USER:-sub2api}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB:-sub2api}
    volumes:
      - ./postgres_data:/var/lib/postgresql/data
    networks:
      - sub2api-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER:-sub2api}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:8-alpine
    container_name: sub2api-redis
    restart: unless-stopped
    command: redis-server --save 60 1 --appendonly yes
    volumes:
      - ./redis_data:/data
    networks:
      - sub2api-net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  sub2api-net:
    driver: bridge
COMPOSEEOF

print_ok "docker-compose.yml 已生成"

# --------------- 创建数据目录 ---------------
mkdir -p data postgres_data redis_data
chmod 600 .env

# --------------- 完成 ---------------
echo ""
echo "=========================================="
echo "  部署准备完成！"
echo "=========================================="
echo ""
echo "镜像:    ${IMAGE_NAME}"
echo "密钥已保存在 .env 中（仅文件所有者可读）"
echo ""
echo "启动服务:"
echo "  docker compose up -d"
echo ""
echo "查看日志:"
echo "  docker compose logs -f sub2api"
echo ""
echo "首次启动后，若未设置 ADMIN_PASSWORD，查看日志获取自动生成的管理员密码:"
echo "  docker compose logs sub2api | grep -i 'admin password'"
