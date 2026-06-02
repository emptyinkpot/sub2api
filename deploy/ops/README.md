# Sub2API ops（声明式上游与下游契约）

Git 真源：**厂商目录 + 消费者 lane 声明**；密钥与线上 Postgres 数据不在此目录。

## 文件

| 路径 | 作用 |
|------|------|
| `consumers/*.yaml` | 下游 lane（分组名、platform、key 名、默认模型） |
| `bootstrap-contentmrs.mjs` | 幂等创建 ContentMRS 小说专用分组/账号/Key |
| `bootstrap-contentmrs-consumer.ps1` | Windows：SSH 170 执行 bootstrap 并拉回消费者密钥 |
| `build-hotfix-binary-170.sh` | 170 上热替换二进制（无需全量镜像构建） |
| `../docs/runtime/provider-catalog.md` | 人类可读厂商表（与 `backend/internal/domain/provider_catalog.go` 对齐） |

## 在 170 上执行（部署/轮换密钥后）

```bash
cd /srv/sub2api
export DASHSCOPE_API_KEY='…'   # 或已在 deploy/.env / 环境
export SUB2API_ADMIN_PASSWORD='…'
node deploy/ops/bootstrap-contentmrs.mjs
```

Windows 本机（在 170 上 bootstrap 并拉回消费者密钥）：

```powershell
pwsh -File "E:\My Project\sub2api\deploy\ops\bootstrap-contentmrs-consumer.ps1" -Skip124
```

密钥写入 `~/.codex-secrets/sub2api/consumers/contentmrs-novel.env`（ContentMRS 消费者，非 MRS 运行时成员）。

然后 ContentMRS：

```powershell
pwsh -File "E:\My Project\ContentMRS\scripts\sync-production-secrets-124.ps1" -Restart
```

## 管理台

创建账号时使用 **上游厂商预设**（通义千问 / Kimi / 智谱等），或调用：

`GET /api/v1/admin/provider-catalog`
