# Sub2API 自定义镜像部署指南

本文档说明如何基于源码构建自己的 Sub2API 镜像，推送到 Docker Hub，并在服务器上一键部署。

---

## 概览

```
┌──────────────────────┐     ┌──────────────────────┐     ┌─────────────────────────┐
│     本地开发机       │     │     Docker Hub       │     │       生产服务器        │
│                      │     │                      │     │                         │
│ 1. 修改代码          │     │                      │     │ 5. 拉取脚本 + 部署      │
│ 2. build_and_push.sh │────▶│ abevol/sub2api:latest│────▶│   docker-deploy-custom  │
│                      │     │                      │     │ 6. docker compose up -d │
│ 3. 构建镜像          │     │                      │     │                         │
│ 4. 推送到 DockerHub  │     │                      │     │                         │
└──────────────────────┘     └──────────────────────┘     └─────────────────────────┘
```

---

## 前提条件

| 环节 | 依赖 |
|------|------|
| 本地构建 | Docker、Docker Hub 账号 |
| 服务器部署 | Docker、Docker Compose（≥ v2）、80GB+ 磁盘 |

---

## 第一步：本地构建并推送镜像

```bash
cd /path/to/sub2api/deploy

# 用法: ./build_and_push.sh <DockerHub用户名> [标签]
./build_and_push.sh abevol
```

脚本会自动完成：
1. `docker build` — 多阶段构建（前端 pnpm 编译 + Go 后端编译 + 最终精简镜像）
2. `docker login` — 如未登录则提示输入 Docker Hub 凭据
3. `docker push` — 推送 `<用户名>/sub2api:latest` 到 Docker Hub

构建参数：
- `GOPROXY`：默认 `https://goproxy.cn,direct`（国内加速），海外服务器可改为 `https://proxy.golang.org,direct`
- `GOSUMDB`：默认 `sum.golang.google.cn`

**指定版本标签：**

```bash
./build_and_push.sh abevol v1.0.0    # 推送 abevol/sub2api:v1.0.0
```

---

## 第二步：服务器上一键部署

### 2.1 获取部署脚本

**方式 A**：直接从 GitHub 下载（如果你已 fork 仓库）

```bash
wget https://raw.githubusercontent.com/<你的GitHub用户名>/sub2api/main/deploy/docker-deploy-custom.sh
chmod +x docker-deploy-custom.sh
```

**方式 B**：从本地上传

```bash
scp deploy/docker-deploy-custom.sh user@server:~/sub2api/
ssh user@server
cd ~/sub2api
chmod +x docker-deploy-custom.sh
```

### 2.2 运行部署脚本

```bash
# 用法: ./docker-deploy-custom.sh <DockerHub用户名> [标签]
./docker-deploy-custom.sh abevol
```

脚本自动完成：
1. `docker pull` — 拉取 `<用户名>/sub2api:latest`
2. 自动生成 `.env` — 包含安全的随机密钥（JWT_SECRET、TOTP_ENCRYPTION_KEY、POSTGRES_PASSWORD）
3. 自动生成 `docker-compose.yml` — 包含 sub2api + PostgreSQL + Redis 三服务
4. 创建数据目录 `data/`、`postgres_data/`、`redis_data/`

生成的文件：

```
sub2api/
├── .env                       # 环境配置（密钥请妥善保管）
├── docker-compose.yml         # Docker Compose 编排
├── data/                      # 应用数据
├── postgres_data/             # PostgreSQL 数据
└── redis_data/                # Redis 数据
```

### 2.3 配置管理员账号（可选）

编辑 `.env`，取消注释并设置：

```bash
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=your_secure_password
```

如果不设置，首次启动时系统会**自动生成管理员密码**并输出到日志。

### 2.4 启动服务

```bash
docker compose up -d
```

### 2.5 获取管理员密码（如未手动设置）

```bash
docker compose logs sub2api | grep -i "admin password"
```

### 2.6 验证部署

```bash
# 健康检查
curl http://localhost:8080/health

# 访问管理后台
# 浏览器打开: http://<服务器IP>:8080
```

---

## 第三步：升级到新版本

当你在本地修改代码后，重新构建推送：

```bash
# 本地
cd deploy
./build_and_push.sh abevol v1.1.0    # 推送新标签

# 服务器
cd ~/sub2api
sed -i 's/abevol\/sub2api:latest/abevol\/sub2api:v1.1.0/' docker-compose.yml
docker compose pull
docker compose up -d
```

或者直接覆盖 latest 标签：

```bash
# 本地
./build_and_push.sh abevol           # latest 被覆盖

# 服务器
docker compose pull && docker compose up -d
```

---

## 自定义配置参考

### `.env` 关键变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `SERVER_PORT` | 服务端口 | `8080` |
| `RUN_MODE` | 运行模式（standard/simple） | `standard` |
| `AUTO_SETUP` | 首次启动自动初始化 | `true` |
| `CODEX_CLI_VERSION` | Codex CLI 版本号 | `0.130.0` |
| `UPDATE_PROXY_URL` | GitHub 代理地址（国内可配） | 空（直连） |

### 配置上游 Codex/Antigravity 账号

1. 登录管理后台 `http://<IP>:8080`
2. 进入 **账号管理** → 添加 OpenAI / Antigravity 账号
3. 进入 **分组管理** → 创建分组并关联上述账号
4. 进入 **API Key 管理** → 创建 API Key 关联该分组
5. 在 Codex CLI 配置中设置：
   ```toml
   [model_providers.OpenAI]
   base_url = "http://<服务器IP>:8080"
   requires_openai_auth = false
   ```
   并通过 `OPENAI_API_KEY` 环境变量传递上述 API Key

---

## 数据备份

数据存储在宿主机目录，直接打包即可：

```bash
# 备份
tar czf sub2api-backup-$(date +%Y%m%d).tar.gz data/ postgres_data/ redis_data/ .env

# 恢复（在新机器上）
tar xzf sub2api-backup-*.tar.gz
docker compose up -d
```

---

## 常见问题

**Q: 构建时 pnpm 报错 "Ignored build scripts"**  
A: 已修复 — `Dockerfile` 锁定 `pnpm@9`，`frontend/pnpm-workspace.yaml` 已声明 `onlyBuiltDependencies`。

**Q: 国内构建速度慢**  
A: 已默认使用 `goproxy.cn`。如仍慢，可在 `build_and_push.sh` 中设置 `GOPROXY` 环境变量。

**Q: 服务器内存不足**  
A: 建议至少 2GB 空闲内存。可在 `.env` 中调低 PostgreSQL 缓存参数：
```bash
POSTGRES_SHARED_BUFFERS=256MB
POSTGRES_EFFECTIVE_CACHE_SIZE=512MB
```
