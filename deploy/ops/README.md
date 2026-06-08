# Sub2API ops（声明式上游与下游契约）

Git 真源：**厂商目录 + 消费者 lane 声明**；密钥与线上 Postgres 数据不在此目录。

## 文件

| 路径 | 作用 |
|------|------|
| `consumers/*.yaml` | 下游 lane（分组名、platform、key 名、默认模型） |
| `bootstrap-contentmrs.mjs` | 幂等创建 ContentMRS 小说专用分组/账号/Key |
| `deploy-image-170.sh` | 170 从 Git 母集构建 `sub2api:integration` 镜像并重启容器 |
| `nginx/sub2api-gateway-locations.conf` | 170 公网 gateway 路由 snippet（无密钥，部署时 include 到站点配置） |
| `../docs/runtime/provider-catalog.md` | 人类可读厂商表（与 `backend/internal/domain/provider_catalog.go` 对齐） |

## 部署规则

`E:\My Project\sub2api` / Git 分支 `integration/upstream-rebase` 是部署母集。
server-170 的 `/srv/sub2api` 只作为构建工作区；运行态必须是编译后的 Docker image，
不得把宿主源码目录 bind mount 成应用代码。

```bash
cd /srv/sub2api
deploy/ops/deploy-image-170.sh
```

脚本优先调用 `docker-compose` / `docker compose`；若服务器没有 compose，
会导出现有 `sub2api` 容器 env 并用 `docker run` 重建同名容器。
运行容器应显示 `image=sub2api:integration`，代码只从镜像内 `/app/sub2api`
执行；持久化数据只挂载 `/app/data`。

脚本同时同步 server-170 的 nginx gateway snippet，确保公网 `/v1/`、
`/v1beta/`、`/antigravity/v1/`、`/antigravity/v1beta/` 都反代到
`127.0.0.1:8080`。站点配置里的 bootstrap secret 不进入 Git。

## 在 170 上执行（部署/轮换密钥后）

```bash
cd /srv/sub2api
export DASHSCOPE_API_KEY='…'   # 或已在 deploy/.env / 环境
export SUB2API_ADMIN_PASSWORD='…'
node deploy/ops/bootstrap-contentmrs.mjs
```

Windows 本机（写 `~/.codex-secrets/contentmrs/sub2api-novel.env`）：

```powershell
node "E:\My Project\ContentMRS\sub2api\deploy\ops\bootstrap-contentmrs.mjs"
```

然后 ContentMRS：

```powershell
pwsh -File "E:\My Project\ContentMRS\scripts\sync-production-secrets-124.ps1" -Restart
```

## 管理台

创建账号时使用 **上游厂商预设**（通义千问 / Kimi / 智谱等），或调用：

`GET /api/v1/admin/provider-catalog`
