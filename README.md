# Sub2API

---
title: sub2api
status: canonical
---

<div align="center">

[![Go](https://img.shields.io/badge/Go-1.26.2-00ADD8.svg)](https://golang.org/)
[![Vue](https://img.shields.io/badge/Vue-3.4+-4FC08D.svg)](https://vuejs.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-336791.svg)](https://www.postgresql.org/)
[![Redis](https://img.shields.io/badge/Redis-7+-DC382D.svg)](https://redis.io/)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg)](https://www.docker.com/)

<a href="https://trendshift.io/repositories/21823" target="_blank"><img src="https://trendshift.io/api/badge/repositories/21823" alt="Wei-Shaw%2Fsub2api | Trendshift" width="250" height="55"/></a>

**AI API 网关平台 - 订阅配额分发管理**

</div>

> **Sub2API 官方仅使用  `sub2api.org` 与 `pincc.ai` 两个域名。其他使用 Sub2API 名义的网站可能为第三方部署或服务，与本项目无关，请自行甄别。**
---

## 项目说明入口

```yaml
projectName: sub2api
canonicalDoc: README.md
machineReadableEntry: project.json
localSourceRoot: E:\My Project\sub2api
owningWorkspaceRoot: E:\My Project
projectType: ai api gateway platform
projectStatus: active
currentDeliveryMode: server-https-live
currentPhase: public-domain-live-on-170
publicBaseUrl: https://sub2api.tengokukk.com/
publicHealthUrl: https://sub2api.tengokukk.com/health
chosenPublicHost: sub2api.tengokukk.com
serverHost: 170.106.179.226
serverRuntimeRoot: /srv/sub2api
runtimeMode: docker-compose
runtimeStack: Docker container `sub2api` + Postgres + Redis behind Nginx
nginxSite: /etc/nginx/sites-enabled/sub2api.tengokukk.com
codexBaseUrl: https://sub2api.tengokukk.com
codexWireApi: responses
githubUpstream: https://github.com/Wei-Shaw/sub2api.git
githubFork: https://github.com/emptyinkpot/sub2api.git
defaultPushRemote: origin
```

- 人类优先读取 `README.md`；机器优先读取 `project.json`。
- 当前这份 README 同时承担项目介绍、当前公网部署说明、以及账号导入规范入口。
- 当前已验证的自托管公网入口为 `https://sub2api.tengokukk.com/`，健康检查入口为 `GET https://sub2api.tengokukk.com/health`。
- 维护边界：以后只维护公网生产运行态 `https://sub2api.tengokukk.com/`；本机 Docker 运行态不再作为本文档或 `project.json` 的维护对象。
- 如果要查账号、渠道、GLM/Coze 配置或真实运行状态，以 170 服务器生产库和公网后台为准，不以本机 `127.0.0.1:8080` 为准。

## 当前运行信息卡

| 项目 | 值 |
| --- | --- |
| 当前目录 | `E:\My Project\sub2api` |
| 所属工作区根 | `E:\My Project` |
| 当前机器可读入口 | `project.json` |
| 当前公网主入口 | `https://sub2api.tengokukk.com/` |
| 当前公网健康检查 | `https://sub2api.tengokukk.com/health` |
| 当前选定域名 | `sub2api.tengokukk.com` |
| 当前服务器 | `170.106.179.226` |
| 当前服务器运行根 | `/srv/sub2api` |
| 当前部署方式 | `docker-compose` |
| 当前 nginx site | `/etc/nginx/sites-enabled/sub2api.tengokukk.com` |
| 当前证书目录 | `/etc/letsencrypt/live/sub2api.tengokukk.com/` |
| Codex base URL | `https://sub2api.tengokukk.com` |
| Codex wire API | `responses` |
| 当前 GitHub 上游 | `https://github.com/Wei-Shaw/sub2api.git` |
| 当前 GitHub fork | `https://github.com/emptyinkpot/sub2api.git` |

## 线上运维速查

这些是当前线上环境的已验证事实，用来避免排障时绕到错误路径：

- 公网入口是 `https://sub2api.tengokukk.com/`，服务器是 `170.106.179.226`，SSH alias 是 `server-170`，运行目录是 `/srv/sub2api`。
- Codex 当前接入方式是 `base_url=https://sub2api.tengokukk.com` + `wire_api=responses`，主请求会打到 `/responses`；`/v1/responses` 也由 Nginx 代理到后端。
- `/openai/v1/responses` 不是当前公网 Codex 主入口；不要把排障重点放到这个路径。
- 运行态健康检查顺序：先查 `GET /health`，再查 `GET /health/deps`。`/health/deps` 返回 `openai_gateway_responses.ok=true` 才说明 Responses handler 依赖齐全。
- Nginx 站点文件是 `/etc/nginx/sites-enabled/sub2api.tengokukk.com`；当前必须代理 `/v1/`、`/api/`、`/responses`、`/health`、`/health/` 到 `http://127.0.0.1:8080`。
- 静态前端根目录是 `/srv/sub2api/deploy/data/public`，普通页面由 Nginx `try_files` 兜底到 `index.html`。
- 当前生产修复版本是 `2026-05-05 failover-fix`，生产容器使用镜像标签 `sub2api:local`。
- 当前生产镜像同时保留标签 `sub2api:failover-fix-20260505`、`weishaw/sub2api:latest`，镜像 ID 是 `6081e9f74eb2`。
- 2026-05-02 热修镜像 `sha256:980925094c0ef0821641d9af5176e611a468034ad446575add2b9e04d6f5c872` 和备份标签 `sub2api:backup-before-healthdeps-20260502175334` 只是历史回滚点，不是当前生产基线。
- 已运行容器的 inspect image 可能仍显示旧 image ID；这是因为二进制可能先在容器内热替换，验证后再 `docker commit` 到 `sub2api:local`。判断是否生效应以 `/health/deps`、真实 `/responses` 请求和请求日志为准。

### 后端热修优先路径

后端 Go 代码变更需要生效时，不要默认整镜像构建。优先按以下最小路径：

1. 在服务器上用一次性 `golang:1.26.2-alpine` 容器编译后端二进制，挂载 `/srv/sub2api`、Go mod cache 和 Go build cache。
2. `docker cp` 新二进制到 `sub2api:/tmp/sub2api.hotfix`。
3. 在容器内备份 `/app/sub2api`，再替换为新二进制。
4. 只重启 `sub2api` 容器，不动 `sub2api-postgres` 和 `sub2api-redis`。
5. 验证 `GET /health/deps`、无 key 的 `/responses` 401、真实 key 的 `/responses` 200。
6. 验证通过后 `docker commit sub2api sub2api:local`，并给旧镜像保留备份标签。

整镜像 `docker build` 只在基础镜像、系统依赖、前端嵌入产物、Dockerfile 或用户明确要求完整镜像发布时使用。

### 生产复刻 Runbook

如果要让另一台服务器复刻当前 `sub2api.tengokukk.com` 的部署形态，按下面的顺序做；这不是通用开发安装，而是当前生产布局的最小可复现路径。

前置条件：

- 一台 Ubuntu/Debian 服务器，开放公网 `80`、`443`，后端容器监听宿主机 `8080`。
- 已安装 Docker、Docker Compose v2、Nginx、Certbot。
- DNS A 记录已指向服务器公网 IP，例如 `sub2api.example.com -> <server-ip>`。
- 运行目录固定为 `/srv/sub2api`，静态前端目录为 `/srv/sub2api/deploy/data/public`。

部署骨架：

```bash
sudo mkdir -p /srv/sub2api
sudo chown -R "$USER:$USER" /srv/sub2api
git clone https://github.com/Wei-Shaw/sub2api.git /srv/sub2api
cd /srv/sub2api/deploy
cp .env.example .env
openssl rand -hex 32
openssl rand -hex 32
```

编辑 `/srv/sub2api/deploy/.env`，至少固定这些值：

```bash
POSTGRES_PASSWORD=<strong-postgres-password>
JWT_SECRET=<fixed-hex-secret>
TOTP_ENCRYPTION_KEY=<fixed-hex-secret>
ADMIN_EMAIL=<admin-email>
ADMIN_PASSWORD=<admin-password>
SERVER_PORT=8080
BIND_HOST=0.0.0.0
TZ=Asia/Shanghai
```

启动容器：

```bash
cd /srv/sub2api/deploy
mkdir -p data postgres_data redis_data
docker compose -f docker-compose.local.yml up -d
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

目标容器形态：

| 容器 | 作用 | 要点 |
| --- | --- | --- |
| `sub2api` | 后端应用 | 端口 `0.0.0.0:8080->8080`，挂载 `/srv/sub2api/deploy/data:/app/data` |
| `sub2api-postgres` | PostgreSQL | 不对公网暴露端口，数据在 `/srv/sub2api/deploy/postgres_data` |
| `sub2api-redis` | Redis | 不对公网暴露端口，数据在 `/srv/sub2api/deploy/redis_data` |
| `sub2api-network` | Docker bridge | 应用、Postgres、Redis 只通过内部网络互通 |

Nginx 必须满足：

- `http` 块里启用 `underscores_in_headers on;`。
- `/v1/`、`/api/`、`/responses`、`/health`、`/health/` 代理到 `http://127.0.0.1:8080`。
- 静态根目录指向 `/srv/sub2api/deploy/data/public`。
- `/assets/` 使用长期缓存，`/` 和 `/index.html` 使用 no-cache，避免 SPA 入口缓存旧版本。

最小站点配置轮廓：

```nginx
server {
    listen 80;
    server_name sub2api.example.com;

    root /srv/sub2api/deploy/data/public;

    location ^~ /v1/ { proxy_pass http://127.0.0.1:8080; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme; }
    location ^~ /api/ { proxy_pass http://127.0.0.1:8080; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme; }
    location = /responses { proxy_pass http://127.0.0.1:8080; proxy_http_version 1.1; proxy_buffering off; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme; }
    location = /health { proxy_pass http://127.0.0.1:8080; }
    location ^~ /health/ { proxy_pass http://127.0.0.1:8080; }

    location ^~ /assets/ { add_header Cache-Control "public, max-age=31536000, immutable" always; try_files $uri =404; }
    location = /index.html { add_header Cache-Control "no-cache, no-store, must-revalidate" always; try_files /index.html =404; }
    location / { add_header Cache-Control "no-cache, no-store, must-revalidate" always; try_files $uri $uri/ /index.html; }
}
```

启用 HTTPS：

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d sub2api.example.com
```

上线验证矩阵：

| 验证项 | 命令/入口 | 期望 |
| --- | --- | --- |
| 健康检查 | `curl -i https://sub2api.example.com/health` | `200` |
| 依赖检查 | `curl -i https://sub2api.example.com/health/deps` | `200`，包含 Responses gateway 依赖状态 |
| 无 key Responses | `curl -i https://sub2api.example.com/responses` | `401`，提示 API key required |
| 有效 key 模型列表 | `GET /v1/models` | `200` |
| 有效 key non-stream Responses | `POST /responses` | `200` |
| 有效 key stream Responses | `POST /responses` with `stream:true` | 返回事件流并出现 `response.completed` |
| 日志 | `docker logs --since 10m sub2api` | 有 `account_id` 调度记录，无连续 `openai.forward_failed` |

### Codex Responses 池子 Failover 排障

典型症状：

- Codex CLI 显示 `Reconnecting...`，随后报 `Unexpected status 502 Bad Gateway: Upstream request failed`。
- Nginx 或应用日志中请求路径是 `/responses`。
- 应用日志出现 `openai.forward_failed`，错误类似 `upstream request failed: Post "https://chatgpt.com/backend-api/codex/responses": EOF`。

这类故障不等于用户 API key 错，也不等于整个池子没有可用账号。2026-05-05 前的问题是：上游连接在拿到 HTTP 状态码前就发生 `EOF` 这类传输错误，旧逻辑把它当成普通错误返回，handler 没有进入账号 failover，于是一次请求可能被一个坏账号直接拖成 502，即使池子里还有其他账号。

2026-05-05 修复后的行为：

- OpenAI 上游传输错误会被包装成 `UpstreamFailoverError`。
- handler 会把这类错误纳入账号切换路径，继续尝试池子里的其他可调度账号。
- 同一账号重复出现上游传输错误后，会进入临时不可调度冷却，避免短时间内持续拖垮请求。
- DB、Redis 不需要重建；修复只要求后端代码/镜像生效。

排障命令：

```bash
docker logs --since 20m sub2api | grep -E 'openai.forward_failed|upstream request failed|account_id|responses'
sudo tail -n 200 /var/log/nginx/sub2api_access.log
docker exec -it sub2api-postgres psql -U sub2api -d sub2api
```

常用 SQL：

```sql
select id, name, platform, type, status, schedulable, temp_unschedulable_until, last_error
from accounts
where platform = 'openai'
order by id;

select id, name, enabled
from account_groups
order by id;
```

临时止血可以先把持续 EOF 的账号放入冷却：

```sql
update accounts
set schedulable = false,
    temp_unschedulable_until = now() + interval '6 hours',
    last_error = 'temporary quarantine: upstream EOF transport failure'
where id = <bad_account_id>;
```

如果已经部署 2026-05-05 修复版，也可以恢复人工关闭的账号，让代码按冷却字段自动调度：

```sql
update accounts
set schedulable = true
where id = <account_id>;
```

修复是否真的生效，以三项为准：`GET /v1/models` 返回 200，`POST /responses` 非流式返回 200，`POST /responses` 流式返回 `response.completed`；同时日志里不再因为单个账号的 `EOF` 直接把整次请求结束为 502。

## 在线体验

体验地址：**[https://demo.sub2api.org/](https://demo.sub2api.org/)**

演示账号（共享演示环境；自建部署不会自动创建该账号）：

| 邮箱 | 密码 |
|------|------|
| admin@sub2api.org | admin123 |

## 项目概述

Sub2API 是一个 AI API 网关平台，用于分发和管理 AI 产品订阅的 API 配额。用户通过平台生成的 API Key 调用上游 AI 服务，平台负责鉴权、计费、负载均衡和请求转发。

### 当前自托管公网状态

- 当前 170 服务器公网入口：`https://sub2api.tengokukk.com/`
- 当前公网健康检查：`GET https://sub2api.tengokukk.com/health -> 200`
- 当前 DNS：`sub2api.tengokukk.com -> 170.106.179.226`
- 当前 TLS：Let's Encrypt 证书已签发到 `/etc/letsencrypt/live/sub2api.tengokukk.com/`

## 核心功能

- **多账号管理** - 支持多种上游账号类型（OAuth、API Key）
- **API Key 分发** - 为用户生成和管理 API Key
- **精确计费** - Token 级别的用量追踪和成本计算
- **智能调度** - 智能账号选择，支持粘性会话
- **并发控制** - 用户级和账号级并发限制
- **速率限制** - 可配置的请求和 Token 速率限制
- **内置支付系统** - 支持 EasyPay 易支付、支付宝官方、微信官方、Stripe，用户自助充值，无需独立部署支付服务（[配置指南](docs/PAYMENT_CN.md)）
- **管理后台** - Web 界面进行监控和管理
- **外部系统集成** - 支持通过 iframe 嵌入外部系统（如工单等），扩展管理后台功能

## ❤️ 赞助商

> [想出现在这里？](mailto:support@pincc.ai)

<table>
<tr>
<td width="180" align="center" valign="middle"><a href="https://shop.pincc.ai/"><img src="assets/partners/logos/pincc-logo.png" alt="pincc" width="150"></a></td>
<td valign="middle"><b><a href="https://shop.pincc.ai/">PinCC</a></b> 是基于 Sub2API 搭建的官方中转服务，提供 Claude Code、Codex、Gemini 等主流模型的稳定中转，开箱即用，免去自建部署与运维烦恼。</td>
</tr>

<tr>
<td width="180"><a href="https://www.packyapi.com/register?aff=sub2api"><img src="assets/partners/logos/packycode.png" alt="PackyCode" width="150"></a></td>
<td>感谢 PackyCode 赞助了本项目！PackyCode 是一家稳定、高效的API中转服务商，提供 Claude Code、Codex、Gemini 等多种中转服务。PackyCode 为本软件的用户提供了特别优惠，使用<a href="https://www.packyapi.com/register?aff=sub2api">此链接</a>注册并在充值时填写"sub2api"优惠码，首次充值可以享受9折优惠！</td>
</tr>

<tr>
<td width="180"><a href="https://poixe.com/i/sub2api"><img src="assets/partners/logos/poixe.png" alt="PoixeAI" width="150"></a></td>
<td>感谢 Poixe AI 赞助了本项目！Poixe AI 提供可靠的 AI 模型接口服务，您可以使用平台提供的 LLM API 接口轻松构建 AI 产品，同时也可以成为供应商，为平台提供大模型资源以赚取收益。通过 <a href="https://poixe.com/i/sub2api">此链接</a> 专属链接注册，充值额外赠送 $5 美金</td>
</tr>

<tr>
<td width="180"><a href="https://ctok.ai"><img src="assets/partners/logos/ctok.png" alt="CTok" width="150"></a></td>
<td>感谢 CTok.ai 赞助了本项目！CTok.ai 致力于打造一站式 AI 编程工具服务平台。我们提供 Claude Code 专业套餐及技术社群服务，同时支持 Google Gemini 和 OpenAI Codex。通过精心设计的套餐方案和专业的技术社群，为开发者提供稳定的服务保障和持续的技术支持，让 AI 辅助编程真正成为开发者的生产力工具。点击<a href="https://ctok.ai">这里</a>注册！</td>
</tr>

<tr>
<td width="180"><a href="https://code.silkapi.com/"><img src="assets/partners/logos/silkapi.png" alt="silkapi" width="150"></a></td>
<td>感谢 丝绸API 赞助了本项目！ <a href="https://code.silkapi.com/">丝绸API</a> 是基于 Sub2API 搭建的中转服务，专注于提供 Codex 高速稳定API中转。</td>
</tr>

<tr>
<td width="180"><a href="https://ylscode.com/"><img src="assets/partners/logos/ylscode.png" alt="ylscode" width="150"></a></td>
<td>感谢 伊莉思Code 赞助了本项目！ <a href="https://ylscode.com/">伊莉思Code</a> 致力于构建安全的企业级Coding Agent生产力服务，提供稳定快速的 Codex / Claude / Gemini 订阅服务与即用即付API多种方案灵活选择，限时注册赠送 3 天 Codex 试用福利！</td>
</tr>

<tr>
<td width="180"><a href="https://www.aicodemirror.com/register?invitecode=KMVZQM"><img src="assets/partners/logos/AICodeMirror.jpg" alt="AICodeMirror" width="150"></a></td>
<td>感谢 AICodeMirror 赞助了本项目！AICodeMirror 提供 Claude Code / Codex / Gemini CLI 官方高稳定性中转服务，企业级并发、快速开票、7×24 小时专属技术支持。Claude Code / Codex / Gemini 官方通道低至原价 38% / 2% / 9%，充值更享额外折扣！AICodeMirror 为 sub2api 用户提供专属福利：通过<a href="https://www.aicodemirror.com/register?invitecode=KMVZQM">此链接</a>注册，首次充值立享 8 折优惠，企业客户最高可享 75 折！</td>
</tr>

<tr>
<td width="180"><a href="https://aigocode.com/invite/SUB2API"><img src="assets/partners/logos/aigocode.png" alt="AIGoCode" width="150"></a></td>
<td>感谢 AIGoCode 赞助了本项目！AIGoCode 是一站式集成 Claude Code、Codex 以及最新 Gemini 模型的综合平台，为您提供稳定、高效、高性价比的 AI 编程服务。平台提供灵活的订阅方案，零封号风险，免 VPN 直连，响应极速。AIGoCode 为 sub2api 用户准备了专属福利：通过<a href="https://aigocode.com/invite/SUB2API">此链接</a>注册，首次充值可额外获得 10% 赠送额度！</td>
</tr>

<tr>
<td width="180"><a href="https://shop.bmoplus.com/?utm_source=github"><img src="assets/partners/logos/bmoplus.jpg" alt="bmoplus" width="150"></a></td>
<td>感谢 BmoPlus 赞助了本项目！BmoPlus 是一家专为AI订阅重度用户打造的可靠 AI 账号代充服务商，提供稳定的 ChatGPT Plus / ChatGPT Pro(全程质保) / Claude Pro / Super Grok / Gemini Pro 的官方代充&成品账号。 通过<a href="https://shop.bmoplus.com/?utm_source=github">BmoPlus AI成品号专卖/代充</a>注册下单的用户，可享GPT 官网订阅一折 的震撼价格！</td>
</tr>

<tr>
<td width="180"><a href="https://bestproxy.com/?keyword=a2e8iuol"><img src="assets/partners/logos/bestproxy.png" alt="bestproxy" width="150"></a></td>
<td>感谢 Bestproxy 赞助了本项目！<a href="https://bestproxy.com/?keyword=a2e8iuol">Bestproxy</a> 是一家提供高纯度住宅IP，支持一号一IP独享，结合真实家庭网络与指纹隔离，可实现链路环境隔离，降低关联风控概率。</td>
</tr>

<tr>
<td width="180"><a href="https://pateway.ai/?ch=1tsfr51"><img src="assets/partners/logos/pateway.png" alt="pateway" width="150"></a></td>
<td>感谢 PatewayAI 赞助了本项目！PatewayAI 是一家面向重度 AI 开发者、专注官方直连的高品质模型 API 中转服务商。提供 Claude 全系列与 Codex 系列模型，100% 官方源直供，不掺假不注水，欢迎检验。计费透明，Token 级账单可逐笔核验。
同时支持企业级高并发，并为企业客户提供了专业的管理平台，企业客户可签订正式合同并开具发票，更多详情进入官网获取联系方式。
现在通过 <a href="https://pateway.ai/?ch=1tsfr51">此链接</a> 注册即送 $3 试用额度，用户充值低至 6 折，邀请好友双向赠送，邀请奖励可达 $150。</td>
</tr>

</table>

## 生态项目

围绕 Sub2API 的社区扩展与集成项目：

| 项目 | 说明 | 功能 |
|------|------|------|
| ~~[Sub2ApiPay](https://github.com/touwaeriol/sub2apipay)~~ | ~~自助支付系统~~ | **已内置** — 支付功能已集成到 Sub2API 中，无需独立部署。详见 [支付配置指南](docs/PAYMENT_CN.md) |
| [sub2api-mobile](https://github.com/ckken/sub2api-mobile) | 移动端管理控制台 | 跨平台应用（iOS/Android/Web），支持用户管理、账号管理、监控看板、多后端切换；基于 Expo + React Native 构建 |

## 技术栈

| 组件 | 技术 |
|------|------|
| 后端 | Go 1.26.2, Gin, Ent, Wire |
| 前端 | Vue 3.4+, Vite 5+, TypeScript, TailwindCSS, pnpm |
| 数据库 | PostgreSQL 15+ |
| 缓存/队列 | Redis 7+ |

---

## 文档索引

README 是人类总入口；更细的专项文档按职责分流：

| 文档 | 用途 |
| --- | --- |
| `project.json` | 机器可读项目真相：公网入口、部署模式、运行根、导入契约、验证要求。 |
| `DEV_GUIDE.md` | 本地开发环境、CI 要求、常见坑点、测试命令和项目结构速览。 |
| `deploy/README.md` | Docker、二进制安装、自动 setup、数据库迁移、TLS 指纹、Gemini OAuth 等部署细节。 |
| `deploy/DATAMANAGEMENTD_CN.md` | 管理后台“数据管理”宿主机进程的部署和联动说明。 |
| `docs/PAYMENT_CN.md` | 中文支付配置指南，覆盖 EasyPay、支付宝、微信、Stripe、Webhook、迁移。 |
| `docs/PAYMENT.md` | 英文支付配置指南。 |
| `docs/ADMIN_PAYMENT_INTEGRATION_API.md` | 外部管理支付集成 API：创建并兑换、用户查询、余额调整、URL query 透传。 |
| `CLA.md` | 个人贡献者许可协议。 |

---

## 后端工程说明

后端位于 `backend/`，核心职责是提供管理 API、用户 API、网关转发、账号调度、计费、支付、运维监控和静态前端托管。

### 后端目录结构

```text
backend/
├── cmd/
│   ├── server/             # 主服务入口、Wire 注入、setup 启动逻辑
│   └── jwtgen/             # JWT 工具
├── ent/                    # Ent schema、生成代码和迁移元数据
├── internal/
│   ├── config/             # 配置结构、加载、运行时设置
│   ├── domain/             # 平台、账号、模型等领域常量
│   ├── handler/            # HTTP handler、DTO、网关 handler
│   ├── integration/        # 外部服务集成
│   ├── middleware/         # 鉴权、限流、日志、CORS 等中间件
│   ├── model/              # 内部模型
│   ├── payment/            # 支付提供商、加密 key、Wire provider
│   ├── repository/         # Ent/Redis/外部客户端仓储封装
│   ├── server/             # Gin router、路由注册、server middleware
│   ├── service/            # 业务服务、调度、计费、token 刷新、运维任务
│   ├── setup/              # 首次安装向导和自动 setup
│   ├── testutil/           # 测试桩和测试辅助
│   ├── util/               # 通用工具
│   └── web/                # 前端静态资源嵌入和 SPA fallback
├── migrations/             # 手写 SQL 迁移
├── resources/              # 后端资源文件
└── Makefile                # 后端构建、生成、测试入口
```

### 请求链路

1. `cmd/server/main.go` 检查 setup 状态，必要时进入 setup wizard 或自动 setup。
2. 正常模式下通过 Wire 组装配置、数据库、Redis、仓储、服务、handler 和后台任务。
3. `internal/server` 注册 Gin 路由和中间件。
4. `internal/handler` 处理 HTTP 请求，转换 DTO，并调用 `internal/service`。
5. `internal/service` 承载业务规则、账号调度、计费、支付、token 刷新、监控聚合等核心逻辑。
6. `internal/repository` 负责 Ent、Redis、上游 OAuth/API 客户端等数据访问。
7. `internal/web` 托管前端构建产物，并处理 SPA fallback、缓存与特殊 API 前缀排除。

### 后端能力矩阵

| 能力 | 主要模块 | 说明 |
| --- | --- | --- |
| 用户与认证 | `handler/auth*`、`service/auth*`、`api/auth.ts` | 登录、注册、刷新 token、OAuth/OIDC/微信、TOTP、邮箱验证。 |
| API Key 与用量 | `handler/api_key*`、`service/usage*`、`repository/usage*` | Key 管理、Token 级用量、趋势、统计、清理任务。 |
| 网关转发 | `handler/gateway*`、`handler/openai_gateway*`、`service/*gateway*` | OpenAI/Claude/Gemini/Antigravity 等兼容转发、模型映射、流式响应。 |
| 账号池与调度 | `service/*scheduler*`、`service/ratelimit*`、`repository/account*` | 多账号调度、粘性会话、限速、并发、冷却、可用性恢复。 |
| 代理池 | `repository/proxy*`、`service/proxy*`、`handler/admin/proxy*` | 代理 CRUD、质量检测、账号关联、导入导出。 |
| 支付与订阅 | `internal/payment`、`service/payment*`、`service/subscription*` | EasyPay、支付宝、微信、Stripe、订单、退款、订阅计划。 |
| 公告与自定义页 | `service/announcement*`、`service/setting*` | 公告、站点设置、自定义菜单、iframe 外部系统。 |
| 运维看板 | `service/ops*`、`repository/ops*`、`handler/admin/ops*` | 实时流量、错误、延迟、日志、告警、OpenAI token 统计。 |
| 备份与数据管理 | `service/backup*`、`handler/admin/data_management*`、`deploy/DATAMANAGEMENTD_CN.md` | S3 备份、恢复、宿主机数据管理进程联动。 |
| TLS 指纹与上游兼容 | `tlsFingerprintProfile`、`http_upstream` 相关模块 | TLS 指纹配置、上游请求形态控制。 |
| Setup 与部署 | `internal/setup`、`deploy/` | 首次安装、Docker 自动初始化、systemd/compose 部署。 |

### 代理出口 IP 风险隔离目标形态

这个能力的目标是降低账号池被同一批代理、同一出口 IP、同一低质量网络环境关联风控后大批量封禁的概率。它不是请求级动态换 IP，也不是为了提高调度随机性；正确形态是让账号稳定绑定一个健康、可追踪、尽量独占的代理出口，并在代理质量变化时提供可审计的重平衡。

当前项目已有的基础能力：

- 账号已经支持 `proxy_id`，运行时网关转发、OAuth 登录、token 刷新、Gemini/Antigravity/OpenAI 相关链路会优先使用账号绑定的代理。
- 代理池已有 CRUD、批量导入、批量删除、账号数量统计、连通性测试和质量检查。
- 代理质量检查可以探测出口 IP、国家/地区、延迟、目标站点可达性、Cloudflare challenge 等信息。
- 管理后台账号页可以手动选择代理，代理页可以查看代理使用数量和质量信息。

当前缺口：

- 现有批量编辑只能把一批账号统一设置为同一个 `proxy_id`，不能按出口 IP 自动分散绑定。
- 调度器选择账号时不按代理出口 IP 做隔离，只按账号状态、模型能力、并发、优先级、错误率、TTFT 和 sticky session 排序。
- `proxies.ip_address` 已有字段，但出口 IP 目前主要来自探测缓存；自动分配前需要把最近一次可信出口 IP 稳定写入数据库，不能只依赖 Redis 缓存。
- 现有代理去重只按 `host + port + username + password` 判断，不能识别多个不同代理入口实际落到同一个出口 IP 的情况。

完成后的行为要求：

- 每个高风险账号默认稳定绑定一个代理，不做每次请求轮换。OAuth、ChatGPT、Gemini、Antigravity 等需要会话连续性的账号尤其必须保持稳定出口。
- 自动分配以真实出口 IP 为核心，而不是以代理入口地址为核心。多个代理节点如果探测到同一个 `exit_ip`，应视为同一个风险组。
- 默认策略应支持 `1 个出口 IP = 1 个高风险账号`；可按平台、账号类型、分组或业务场景配置 `max_accounts_per_exit_ip`。
- 代理质量状态为 failed、challenge 严重、近期检测过期、未检测到出口 IP 的代理，默认不参与自动分配，除非用户显式允许。
- 新导入账号、批量导入账号、CRS 同步账号、OAuth 新增账号时，可以选择自动挑选一个健康且未超额的代理。
- 已有账号可以执行“预览重平衡”，先展示哪些账号会换代理、为什么换、从哪个出口 IP 换到哪个出口 IP，再由管理员确认应用。
- 代理出口 IP 变化、代理质量下降、同出口 IP 账号数超过阈值时，应能在管理后台看见风险提示，并提供重新分配入口。

建议的数据模型和持久化字段：

- `proxies.ip_address`：最近一次可信出口 IP，质量检测或连通性测试成功后写入。
- `proxies.ip_country_code`、`proxies.ip_country`、`proxies.ip_region`、`proxies.ip_city`：出口地理信息，可后续补充，MVP 可继续从质量缓存展示。
- `proxies.quality_status`、`proxies.quality_score`、`proxies.quality_checked_at`：如果需要让自动分配脱离 Redis，应把关键质量状态落库。
- `accounts.proxy_assignment_locked`：可选字段，用于锁定人工指定代理，自动重平衡不得覆盖。
- `accounts.proxy_assignment_reason`：可选字段，记录自动分配原因，便于审计和回滚。
- MVP 可以先不新增账号字段，只做“保留已有绑定/仅处理未绑定账号/预览后应用”；后续再补锁定和审计字段。

建议的后端服务形态：

- 新增 `ProxyAssignmentService`，放在管理侧服务层，不进入网关请求热路径。
- 服务输入支持账号筛选：账号 ID 列表、平台、类型、状态、分组、是否仅未绑定账号、是否覆盖已有绑定。
- 服务输入支持代理筛选：只用 active 代理、最小质量分、允许的国家/地区、排除 failed/challenge、是否允许未知出口 IP。
- 服务规则支持 `max_accounts_per_proxy`、`max_accounts_per_exit_ip`、`prefer_unused_exit_ip`、`preserve_existing_binding`、`respect_assignment_locked`。
- 分配算法先按 `exit_ip` 聚合代理，再按当前绑定账号数、质量分、延迟、最近检测时间排序，优先选择健康、低占用、出口 IP 未超额的代理。
- 应用分配时复用现有账号 `proxy_id` 更新逻辑，并触发账号缓存/调度快照同步，确保运行态立刻拿到新的代理绑定。

建议的管理 API：

```text
POST /api/v1/admin/accounts/proxy-assignment/preview
POST /api/v1/admin/accounts/proxy-assignment/apply
GET  /api/v1/admin/proxies/risk-summary
```

`preview` 返回的计划至少包含：

- `account_id`、`account_name`、`platform`、`type`
- `old_proxy_id`、`old_proxy_name`、`old_exit_ip`
- `new_proxy_id`、`new_proxy_name`、`new_exit_ip`
- `action`: `keep`、`assign`、`rebalance`、`clear`、`skip`
- `reason`: `unassigned`、`exit_ip_over_limit`、`proxy_failed`、`proxy_quality_stale`、`manual_locked`、`no_available_proxy`
- `warnings`: 例如出口 IP 未知、代理检测过期、同国家集中、可用代理不足

`apply` 必须要求携带 preview 生成的 plan id 或幂等 key，避免用户在代理质量或账号状态变化后误应用旧计划。

建议的前端入口：

- 账号页批量操作栏增加“自动分配代理”入口，用于选中账号或当前筛选结果。
- 代理页增加“出口 IP 风险概览”和“重平衡账号”入口。
- 代理列表增加按 `exit_ip` 聚合的风险提示：同出口 IP 代理数、绑定账号数、超额账号数、最近检测时间。
- 预览弹窗必须显示变更表，不允许直接一键静默修改大量账号。
- 对人工绑定的账号提供“锁定代理”标记，避免重平衡覆盖管理员明确指定的代理。

建议的默认策略：

```yaml
proxy_assignment:
  enabled: false
  default_mode: preview_first
  preserve_existing_binding: true
  assign_only_unbound_on_import: true
  max_accounts_per_exit_ip:
    openai_oauth: 1
    gemini_oauth: 1
    antigravity_oauth: 1
    api_key: 3
  require_proxy_active: true
  require_exit_ip: true
  min_quality_score: 70
  reject_quality_status:
    - failed
  warn_quality_status:
    - challenge
    - warn
  quality_max_age_minutes: 1440
```

推荐实施顺序：

1. 先修正代理探测持久化：质量检测和连通性测试成功时，把出口 IP 写入 `proxies.ip_address`，并确保列表、导出、导入不会丢失。
2. 增加代理出口 IP 风险聚合查询：按 `ip_address` 统计代理数、绑定账号数、活跃账号数、质量状态。
3. 实现 `preview`：只生成计划，不改账号，用真实账号和代理数据验证分配规则。
4. 实现 `apply`：按 preview 计划逐个更新账号 `proxy_id`，记录成功/失败，并刷新调度缓存。
5. 在账号页接入批量自动分配，在代理页接入风险概览和重平衡。
6. 再考虑导入账号、CRS 同步、OAuth 新建账号时的自动分配开关。

明确非目标：

- 不做每次请求随机换代理。
- 不在账号调度器热路径里实时计算代理分配。
- 不因为某个代理瞬时失败就自动大规模迁移账号；应先进入告警/预览，再由管理员确认。
- 不承诺彻底避免封禁；该能力只降低同出口 IP 和低质量代理导致的关联风险。

验收标准：

- 代理质量检测后，代理列表能稳定展示最近出口 IP，重启服务或 Redis 清空后仍可从数据库读取核心出口 IP。
- 当 10 个账号、10 个不同出口 IP 的健康代理存在时，自动分配预览应默认生成 10 个不同出口 IP 的绑定计划。
- 当多个代理实际出口 IP 相同时，系统应按同一风险组计数，不能把它们当成完全独立出口。
- 当可用健康出口 IP 数不足时，预览必须明确显示哪些账号无法分配或会超额绑定。
- 对已锁定或人工保留绑定的账号，自动重平衡默认不得覆盖。
- 应用计划后，账号详情、账号列表、代理账号数量统计和运行时转发使用的代理应一致。

### 后端命令

在仓库根目录：

```bash
make build-backend
make test-backend
```

在 `backend/` 目录：

```bash
make build
make generate
make test
make test-unit
make test-integration
make test-e2e-local
```

Ent schema 修改后必须运行 `make generate`，并同步提交生成代码和必要的迁移文件。

---

## 前端工程说明

本章节基于当前 `frontend/` 目录真实实现整理，用于接手前端开发、排查页面问题和维护页面/API 对应关系。

### 前端目录结构

```text
frontend/
├── public/                 # 静态资源
├── src/
│   ├── api/                # API 封装
│   ├── assets/             # 资源文件
│   ├── components/         # 通用组件
│   ├── composables/        # 组合式逻辑
│   ├── constants/          # 常量
│   ├── i18n/               # 国际化
│   ├── router/             # 路由和守卫
│   ├── stores/             # Pinia 状态
│   ├── styles/             # 样式拆分
│   ├── types/              # TypeScript 类型
│   ├── utils/              # 工具函数
│   ├── views/              # 页面
│   └── __tests__/          # 测试
├── package.json
├── vite.config.ts
├── tailwind.config.js
├── tsconfig.json
└── vitest.config.ts
```

### 依赖与工程能力

运行时依赖：

- 核心框架：`vue`、`vue-router`、`pinia`、`vue-i18n`
- 网络与安全：`axios`、`dompurify`、`marked`
- 交互体验：`@vueuse/core`、`@tanstack/vue-virtual`、`driver.js`、`vue-draggable-plus`
- 图表与数据：`chart.js`、`vue-chartjs`、`xlsx`、`file-saver`、`qrcode`
- 支付与图标：`@stripe/stripe-js`、`@lobehub/icons`

开发依赖：

- 构建：`vite`、`@vitejs/plugin-vue`、`vite-plugin-checker`
- 类型：`typescript`、`vue-tsc`
- 样式：`tailwindcss`、`postcss`、`autoprefixer`
- 规范：`eslint`、`@typescript-eslint/*`、`eslint-plugin-vue`
- 测试：`vitest`、`@vue/test-utils`、`jsdom`、`@vitest/coverage-v8`

### 启动与初始化流程

前端入口是 `frontend/src/main.ts`：

1. 先根据 `localStorage.theme` 和系统偏好设置根节点 `dark` 类，避免首屏主题闪烁。
2. 创建 Vue App 并注册 Pinia。
3. 通过 `appStore.initFromInjectedConfig()` 读取 `window.__APP_CONFIG__` 注入配置。
4. 执行 `authStore.bootstrapAutoLogin()` 和 `authStore.checkAuth()` 恢复登录态。
5. 根据站点配置设置 `document.title`。
6. 初始化 i18n。
7. 注册 router/i18n，等待 `router.isReady()` 后挂载到 `#app`。

### 构建与后端集成

`frontend/vite.config.ts` 的关键约定：

- 构建输出目录是 `../backend/internal/web/dist`，前端产物直接进入后端静态资源目录。
- 开发代理默认后端是 `http://localhost:8080`，可用 `VITE_DEV_PROXY_TARGET` 覆盖。
- 开发端口默认是 `3000`，可用 `VITE_DEV_PORT` 覆盖。
- 开发模式会尝试请求 `GET /api/v1/settings/public` 并注入 `window.__APP_CONFIG__`。
- 代理路径包括 `/api`、`/v1`、`/setup`。

分包策略：

- `vendor-vue`：Vue、Router、Pinia、`@vue/*`
- `vendor-ui`：`@vueuse`、`xlsx`
- `vendor-chart`：`chart.js`、`vue-chartjs`
- `vendor-i18n`：`vue-i18n`、`@intlify`
- `vendor-misc`：其他第三方依赖

### 开发命令

在 `frontend/` 目录执行：

```bash
pnpm install
pnpm run dev
pnpm run build
pnpm run preview
pnpm run lint
pnpm run lint:check
pnpm run typecheck
pnpm run test
pnpm run test:run
pnpm run test:coverage
```

推荐提交前验证：

```bash
pnpm run typecheck
pnpm run lint:check
pnpm run test:run
pnpm run build
```

### 路由分区

基于 `frontend/src/router/index.ts`：

- 初始化与公共页：`/setup`、`/home`、`/login`、`/register`、`/forgot-password`、`/reset-password`、`/email-verify`、`/key-usage`
- OAuth/OIDC 回调页：`/auth/callback`、`/auth/linuxdo/callback`、`/auth/wechat/callback`、`/auth/wechat/payment/callback`、`/auth/oidc/callback`
- 用户侧控制台：`/dashboard`、`/keys`、`/usage`、`/redeem`、`/affiliate`、`/available-channels`、`/profile`、`/subscriptions`、`/monitor`、`/custom/:id`
- 用户侧支付：`/purchase`、`/orders`、`/payment/qrcode`、`/payment/result`、`/payment/stripe`、`/payment/stripe-popup`
- 管理侧控制台：`/admin/dashboard`、`/admin/ops`、`/admin/users`、`/admin/groups`、`/admin/channels/pricing`、`/admin/channels/monitor`、`/admin/subscriptions`、`/admin/accounts`、`/admin/announcements`、`/admin/proxies`、`/admin/redeem`、`/admin/promo-codes`、`/admin/settings`、`/admin/usage`
- 管理侧支付：`/admin/orders/dashboard`、`/admin/orders`、`/admin/orders/plans`
- 兜底页：`/:pathMatch(.*)*`

路由守卫策略：

- `requiresAuth` 控制是否需要登录，默认需要登录。
- `requiresAdmin` 控制管理员路由，非管理员访问会回到用户仪表盘。
- `requiresPayment` 受公共配置中的支付开关联动，支付关闭时会回到对应仪表盘。
- Backend Mode 只允许未登录用户访问 `/login`、`/key-usage`、`/setup`、支付结果页和认证回调页。
- Simple Mode 会限制分组、订阅、兑换等复杂页面入口。
- 动态 chunk 加载失败时会写入 `sessionStorage` 并自动刷新一次，用于处理发布后缓存不一致。

### 页面到 API 矩阵

该矩阵基于 `frontend/src/views` 中的实际 import 与调用整理，新增页面或接口时需要同步维护。

#### 公共与认证页面

| 页面 | 路由 | 主要 API | 说明 |
| --- | --- | --- | --- |
| `SetupWizardView.vue` | `/setup` | `setup.testDatabase`、`setup.testRedis`、`setup.install` | 首次安装、数据库/Redis 连通性测试、初始化安装。 |
| `LoginView.vue` | `/login` | `auth.getPublicSettings`、`auth.isTotp2FARequired`、`auth.isWeChatWebOAuthEnabled`，并通过 auth store 完成登录 | 登录页、公共设置、TOTP/微信登录能力判断。 |
| `RegisterView.vue` | `/register` | `auth.register`、`auth.sendVerifyCode`、`auth.validatePromoCode`、`auth.validateInvitationCode`、OAuth pending 账号创建/绑定方法 | 注册、验证码、邀请码/促销码、第三方登录补全注册。 |
| `EmailVerifyView.vue` | `/email-verify` | `auth.sendVerifyCode`、`auth.sendPendingOAuthVerifyCode`、`apiClient` | 邮箱验证与 OAuth pending 场景验证码。 |
| `ForgotPasswordView.vue` | `/forgot-password` | `auth.getPublicSettings`、`auth.forgotPassword` | 找回密码入口。 |
| `ResetPasswordView.vue` | `/reset-password` | `auth.resetPassword` | 重置密码。 |
| `OAuthCallbackView.vue` | `/auth/callback` | `auth.persistOAuthTokenContext`、`auth.exchangePendingOAuthCompletion`、`auth.completePendingOAuthBindLogin`、`apiClient` | 通用 OAuth 回调处理。 |
| `LinuxDoCallbackView.vue` | `/auth/linuxdo/callback` | `auth.completeLinuxDoOAuthRegistration`、`auth.createPendingLinuxDoOAuthAccount`、`apiClient` | LinuxDo OAuth 回调与账号创建。 |
| `OidcCallbackView.vue` | `/auth/oidc/callback` | `auth.completeOIDCOAuthRegistration`、`auth.createPendingOIDCOAuthAccount`、`apiClient` | OIDC 回调与账号创建。 |
| `WechatCallbackView.vue` | `/auth/wechat/callback` | `auth.completeWeChatOAuthRegistration`、`auth.createPendingWeChatOAuthAccount`、`apiClient` | 微信登录回调与账号创建。 |
| `WechatPaymentCallbackView.vue` | `/auth/wechat/payment/callback` | `apiClient`、支付回调相关逻辑 | 微信支付授权/回调承接。 |
| `KeyUsageView.vue` | `/key-usage` | 页面输入 API Key 后查询用量 | 公共 Key 用量查询页。 |

#### 用户侧页面

| 页面 | 路由 | 主要 API | 说明 |
| --- | --- | --- | --- |
| `DashboardView.vue` | `/dashboard` | `usageAPI.getDashboardStats`、`usageAPI.getDashboardTrend`、`usageAPI.getDashboardModels`、`usageAPI.getByDateRange` | 用户首页统计、趋势图、模型分布、最近用量。 |
| `KeysView.vue` | `/keys` | `keysAPI.list/create/update/delete/toggleStatus`、`usageAPI.getDashboardApiKeysUsage`、`userGroupsAPI.getAvailable/getUserGroupRates`、`authAPI.getPublicSettings` | API Key 列表、创建、编辑、禁用、删除、额度/限速重置、分组与用量展示。 |
| `UsageView.vue` | `/usage` | `usageAPI.list/query/getStats/getStatsByDateRange/getByDateRange/getById` | 用户用量明细、筛选、统计与详情。 |
| `RedeemView.vue` | `/redeem` | `redeemAPI.redeem`、`redeemAPI.getHistory`、`authAPI.getPublicSettings` | 兑换码使用与历史。 |
| `AffiliateView.vue` | `/affiliate` | `userAPI.getAffiliateDetail`、`userAPI.transferAffiliateQuota` | 邀请/返利详情与额度转移。 |
| `AvailableChannelsView.vue` | `/available-channels` | `userChannelsAPI.getAvailable`、`userGroupsAPI.getUserGroupRates` | 用户可用渠道、分组倍率展示。 |
| `ChannelStatusView.vue` | `/monitor` | `channelMonitorUserAPI.list/status` | 用户侧渠道监控状态。 |
| `ProfileView.vue` | `/profile` | `auth.isWeChatWebOAuthEnabled`、用户资料/TOTP/绑定相关 store/API | 个人资料、第三方绑定、安全设置。 |
| `SubscriptionsView.vue` | `/subscriptions` | `subscriptionsAPI.getMySubscriptions`、`getActiveSubscriptions`、`getSubscriptionsProgress`、`getSubscriptionSummary` | 我的订阅、进度和汇总。 |
| `CustomPageView.vue` | `/custom/:id` | `appStore.cachedPublicSettings.custom_menu_items`、`adminSettingsStore.customMenuItems` | 自定义菜单页，标题与内容来自公共/管理员设置。 |
| `PaymentView.vue` | `/purchase` | `paymentAPI.getCheckoutInfo`、下单/支付相关方法 | 购买订阅、选择支付方式、发起订单。 |
| `UserOrdersView.vue` | `/orders` | `paymentAPI.getMyOrders`、`paymentAPI.cancelOrder`、`paymentAPI.requestRefund`、`paymentAPI.getRefundEligibleProviders` | 用户订单、取消订单、退款申请。 |
| `PaymentQRCodeView.vue` | `/payment/qrcode` | `paymentAPI.cancelOrder` | 二维码支付页和取消订单。 |
| `PaymentResultView.vue` | `/payment/result` | `paymentAPI.resolveOrderPublicByResumeToken`、`paymentAPI.verifyOrderPublic` | 支付结果确认，支持 resume token 和商户单号。 |
| `StripePaymentView.vue` | `/payment/stripe` | `paymentAPI.getOrder`、Stripe SDK | Stripe 支付页。 |
| `StripePopupView.vue` | `/payment/stripe-popup` | Stripe SDK/支付状态同步 | Stripe 弹窗支付承接页。 |

#### 管理侧页面

| 页面 | 路由 | 主要 API | 说明 |
| --- | --- | --- | --- |
| `DashboardView.vue` | `/admin/dashboard` | `adminAPI.dashboard.getSnapshotV2`、`getUserUsageTrend`、`getUserSpendingRanking` | 管理首页指标、趋势、用户排行。 |
| `OpsDashboard.vue` | `/admin/ops` | `opsAPI.getDashboardOverview`、`getDashboardSnapshotV2`、`getThroughputTrend`、`getLatencyHistogram`、`getErrorTrend`、`getErrorDistribution`、`getMetricThresholds`、`getAdvancedSettings` | 运维监控总览、吞吐、延迟、错误与阈值。 |
| `UsersView.vue` | `/admin/users` | `adminAPI.users.list/getById/create/update/delete/toggleStatus/updateBalance/updateConcurrency/replaceGroup/bindUserAuthIdentity`、`adminAPI.groups.getAll`、`adminAPI.dashboard.getBatchUsersUsage`、`adminAPI.userAttributes.*` | 用户管理、余额、并发、分组、属性、用量。 |
| `GroupsView.vue` | `/admin/groups` | `adminAPI.groups.*`、`adminAPI.accounts.*`、`adminAPI.channels.*` | 分组管理、模型/倍率、关联账号与渠道。 |
| `ChannelsView.vue` | `/admin/channels/pricing` | `adminAPI.channels.list/create/update/remove`、`adminAPI.groups.getAll`、`adminAPI.accounts.list/getById`、`adminAPI.settings.getWebSearchEmulationConfig` | 渠道定价、账号关联、分组可见性、Web Search 配置联动。 |
| `ChannelMonitorView.vue` | `/admin/channels/monitor` | `adminAPI.channelMonitor.list/update/runNow/del` | 管理侧渠道监控规则、启停、立即检测、删除。 |
| `SubscriptionsView.vue` | `/admin/subscriptions` | `adminAPI.subscriptions.list/assign/extend/revoke/resetQuota`、`adminAPI.groups.getAll`、`adminAPI.usage.searchUsers` | 订阅分配、延期、撤销、额度重置、用户筛选。 |
| `AccountsView.vue` | `/admin/accounts` | `adminAPI.accounts.list/listWithEtag/getBatchTodayStats/delete/batchClearError/batchRefresh/bulkUpdate/exportData/getAvailableModels/refreshCredentials/recoverState/resetAccountQuota/setPrivacy/setSchedulable`、`adminAPI.proxies.getAll`、`adminAPI.groups.getAll` | 上游账号管理、批量操作、状态恢复、导入导出、代理/分组关联。 |
| `AnnouncementsView.vue` | `/admin/announcements` | `adminAPI.announcements.list/create/update/delete`、`adminAPI.groups.getAll` | 公告发布、编辑、删除、分组可见性。 |
| `ProxiesView.vue` | `/admin/proxies` | `adminAPI.proxies.list/getAll/getById/create/update/delete/toggleStatus/testProxy/checkProxyQuality/getStats/getProxyAccounts/batchCreate/batchDelete/exportData/importData` | 代理池管理、测试、质量检查、批量导入导出。 |
| `RedeemView.vue` | `/admin/redeem` | `adminAPI.redeem.list/getById/generate/delete/batchDelete/expire/getStats/exportCodes` | 兑换码生成、查询、过期、导出与统计。 |
| `PromoCodesView.vue` | `/admin/promo-codes` | `adminAPI.promo.list/create/update/delete/getUsages` | 促销码管理和使用记录。 |
| `SettingsView.vue` | `/admin/settings` | `adminAPI.settings.*`、`adminAPI.payment.*`、`adminAPI.proxies.list`、`adminAPI.groups.getAll`、`affiliatesAPI.*` | 系统设置、SMTP、管理员 API Key、过载冷却、流超时、Rectifier、Beta 策略、Web Search、支付提供商、推广返利。 |
| `UsageView.vue` | `/admin/usage` | `adminAPI.usage.list/getStats/searchUsers/searchApiKeys/listCleanupTasks/createCleanupTask/cancelCleanupTask`、`adminAPI.dashboard.getModelStats/getSnapshotV2`、`adminAPI.users.getById` | 管理端用量日志、统计、搜索、清理任务。 |
| `BackupView.vue` | `/admin/backup` | `adminAPI.backup.getS3Config/updateS3Config/testS3Connection/getSchedule/updateSchedule/listBackups/createBackup/getBackup/getDownloadURL/restoreBackup/deleteBackup` | S3 备份配置、计划、手动备份、下载、恢复、删除。 |
| `AdminPaymentDashboardView.vue` | `/admin/orders/dashboard` | `adminAPI.payment.*` | 支付统计与订单看板。 |
| `AdminOrdersView.vue` | `/admin/orders` | `adminAPI.payment.*` | 管理端订单查询、取消、重试、退款。 |
| `AdminPaymentPlansView.vue` | `/admin/orders/plans` | `adminAPI.payment.*`、`PlanEditDialog.vue` | 订阅计划管理。 |
| `PlanEditDialog.vue` | 页面内弹窗 | `adminPaymentAPI.createPlan/updatePlan` | 支付计划创建与编辑弹窗。 |

#### 账号管理页显示契约

`frontend/src/views/admin/AccountsView.vue` 是后台账号列表页，页面类型是 `list`。当前固定采用“紧凑行卡（compact row-card）”模式，而不是宽表格、瀑布卡或六列大卡片：

- 账号列表外层必须是纵向滚动容器，横向溢出必须隐藏；页面级、列表级、卡片级都不允许出现横向拉条。
- 账号列表不显示底部分页信息，不显示“显示 1 至 N 共 N 条结果”，不显示“每页”下拉；统一采用上下滚动的无限流加载。
- 首屏只加载第一页；滚动到底部时自动追加下一页，直到服务端返回最后一页为止。
- 当当前视口内容不足一屏时，前端可以自动继续补页填满列表，但仍不得出现分页条。
- 每个账号必须渲染为独立 `article` 行卡，用浅边框、轻背景、细分隔线和 hover 边框区分条目；不能用大面积留白制造“卡片感”。
- 行卡主结构固定为两层：第一层是主行，第二层是详情条。第一层只承载高频决策信息，第二层承载补充信息。
- 第一层必须压缩为四个稳定区域：`identity`、`state`、`metrics`、`actions`。禁止再拆成 6 个等权模块横向铺满整行，因为这会让卡片显得太宽、字段距离过远且条目不清晰。
- `identity` 合并选择框、账号名/邮箱、平台/类型/套餐/privacy 标签；平台不再占独立大列。
- `state` 合并账号状态和调度开关；状态在上，调度在下或右侧，二者必须在同一区域内形成明确状态块。
- `metrics` 合并今日统计和用量窗口摘要；统计信息必须紧凑呈现，避免把请求、Token、计费、窗口拆散到远距离列中。
- `actions` 固定只展示编辑、删除、更多三个入口；更多操作进菜单，不能把测试、统计、重授权、恢复、刷新 token 等操作平铺出来。
- 第二层详情条使用 `border-t`、小字号、固定槽位：容量、分组、代理、最近使用、过期时间、备注。详情条必须比主行弱，不能抢占主信息空间。
- 账号列表本体不应在超宽内容区内无限拉伸；数据卡列表推荐 `w-full max-w-[1080px]`，让字段保持紧凑距离，右侧留白由页面容器承担。
- 备注、代理、邮箱、错误摘要等长文本必须有 `title` 或 popover 作为完整信息入口；摘要处可以 `truncate`，但不能发生文字上半截/下半截被裁掉、重叠、乱码或横向撑出。
- 空态、加载态和数据态必须保持同一版式宽度：加载 skeleton 是紧凑行卡骨架，空态是居中卡片，不允许加载完成后布局横向跳变。
- 当列表继续向下加载时，底部只显示轻量“加载中…”提示；加载完最后一页后显示“没有更多数据”，不能再露出分页器。

账号卡片的预期代码形态如下，源码可以抽成局部组件，但 DOM 语义、槽位顺序和防溢出规则必须保持一致：

```vue
<div class="flex min-h-0 flex-1 flex-col overflow-y-auto overflow-x-hidden">
  <div class="w-full max-w-[1080px] space-y-2.5">
    <article
      v-for="row in accounts"
      :key="row.id"
      class="account-row-card rounded-lg border border-gray-200 bg-white px-3 py-2.5 shadow-sm dark:border-dark-700 dark:bg-dark-800 sm:px-3.5"
    >
      <div
        class="account-row-card__main grid min-w-0 grid-cols-1 gap-2.5 lg:grid-cols-[minmax(0,1fr)_minmax(0,220px)_minmax(0,240px)_auto] lg:items-start"
      >
        <section class="account-row-card__identity min-w-0">
          <!-- checkbox + name/email + PlatformTypeBadge；长文本 truncate + title -->
        </section>

        <section class="account-row-card__state min-w-0">
          <!-- AccountStatusIndicator + schedulable switch；状态和调度形成一个状态块 -->
        </section>

        <section class="account-row-card__metrics min-w-0">
          <!-- AccountTodayStatsCell + AccountUsageCell；指标摘要靠近展示，但不拆成过窄小列 -->
        </section>

        <section class="account-row-card__actions flex shrink-0 justify-start gap-1 lg:justify-end">
          <!-- edit / delete / more only -->
        </section>
      </div>

      <div
        class="account-row-card__details mt-2 border-t border-gray-100 pt-2 text-[11px] leading-snug dark:border-dark-700"
      >
        <dl class="grid min-w-0 grid-cols-2 gap-x-3 gap-y-1.5 sm:grid-cols-3 xl:grid-cols-6">
          <!-- capacity / groups / proxy / last used / expires / notes -->
        </dl>
      </div>
    </article>
  </div>
</div>
```

固定行卡布局的硬性验收规则：

- `account-row-card__main` 必须使用四区 grid；禁止恢复到六列主模块，也禁止把全部字段放入一个自由 `flex-wrap` 容器。
- 账号列表容器必须设置上限宽度；禁止让账号卡在桌面宽屏无限拉伸到内容区全宽，导致模块之间距离过大、条目不清晰。
- `account-row-card__details` 必须使用 `dl/dt/dd` 或等价语义，label 和 value 成对出现；即使没有数据也显示 `-`，不能因为条件渲染移除整块导致上下账号基线不同。
- 主行必须 `lg:items-start` 或等价样式；禁止用 `items-center` 让不同高度模块垂直居中造成错位。
- 固定槽位不等于固定高度；父级禁止使用 `max-h-* + overflow-hidden` 直接裁剪真实内容。槽位只能用 `min-h-*` 保持基线，用 `min-w-0` 和宽度约束防横向溢出，卡片高度必须允许随内容自然增加。
- 状态、用量、容量、分组这类可变高度组件必须在组件内部定义摘要和折叠规则；超出内容折叠为 `+N`、popover 或 tooltip，不得把同一行其他区域挤压、覆盖或顶乱。
- 所有文本入口必须经过 i18n、格式化函数、`String(...)` 安全转换或显式兜底；禁止直接渲染对象、数组、未转义错误体、token、credentials、回调 URL，避免 `[object Object]`、乱码文字、泄密和异常换行。
- 所有长文本必须同时具备 `min-w-0`、`overflow-hidden`、`truncate` 或 `break-words` 的明确策略；同一区域内 badge、图标、按钮不得和文本重叠。
- 中文、英文、邮箱、代理名、备注、模型名、错误摘要都必须在窄屏和大屏下验证不重叠、不乱码、不出现横向滚动。

紧凑密度契约：

- 账号卡必须以“信息密度优先、条目清晰”为原则；不能为了卡片视觉效果保留大面积空白，也不能为了压缩高度再次引入粗暴截断。
- 卡片外层推荐 `px-3 py-2.5 sm:px-3.5`、`rounded-lg`、`gap-2.5`、`space-y-2.5`；除非有明确交互需要，禁止使用 `p-4+`、`gap-4+`、`mt-4+` 作为默认账号卡密度。
- 标签使用弱化样式：推荐 `text-[10px]` 或 `text-[11px]`、低对比灰色；label 只承担定位作用，不应抢占主要信息空间。
- 主信息正文推荐 `text-[12px] leading-snug`，详情条推荐 `text-[11px] leading-snug`；账号名可略高权重，但不应扩大整卡字号。
- 图标按钮必须使用小尺寸：主操作图标推荐 `h-3.5 w-3.5` 或 `h-4 w-4`，按钮内边距推荐 `p-1` 到 `p-1.5`；禁止用大图标和大按钮撑高操作区。
- badge、容量、分组、状态和用量 chip 推荐 `text-[10px]`、`px-1` 到 `px-1.5`、`py-px` 到 `py-0.5`；同类 chip 间距推荐 `gap-1`，不得用过大 pill 造成无意义留白。
- 空值占位必须轻量：使用 `-` 或短文案，不要用高占位块；空值不能撑高卡片。
- 紧凑化后仍必须保留完整信息入口：长文本使用 `title`、tooltip、popover 或详情菜单补足，不能因为字号变小导致可访问信息减少。

Base URL 自动聚类与账号复制契约：

- 账号列表必须按派生维度自动聚类，聚类 key 为 `platform + effective_base_url`，不是新增数据库分组，也不能改变现有账号分组、调度、计费或权限语义。
- `effective_base_url` 的解析顺序固定为：Anthropic OAuth/SetupToken 且 `extra.custom_base_url_enabled=true` 时优先使用 `extra.custom_base_url`；否则使用 `credentials.base_url`；值必须 `trim()` 并移除尾部 `/`；空值显示为“默认 Base URL”。
- 每个 Base URL 聚类块必须有轻量 header，显示平台、Base URL 和账号数量；header 支持折叠/展开，折叠状态只影响当前前端视图，不写入后端。
- 聚类块内部仍然使用同一套紧凑行卡 DOM：`identity/state/metrics/actions` 四区主行 + `details` 详情条；禁止在聚类后退回宽表格、大卡片或横向滚动容器。
- 聚类 header 和行卡都必须 `min-w-0`、`truncate`、`title` 兜底；超长 Base URL、账号名、邮箱、代理、备注不能撑出横拉条，不能和按钮、badge、统计块重叠，也不能出现乱码。
- “复制账号”是单账号 clone 操作，入口放在账号“更多”菜单中；它不是“从分组复制账号”，也不是复制到剪贴板。
- “复制账号”应同时提供行内快捷入口和“更多”菜单入口；行内按钮只做快捷触发，仍必须保留菜单入口作为次级操作，避免鼠标移动成本过高。
- 复制账号调用 `POST /api/v1/admin/accounts/:id/clone`，后端必须复制账号名称、平台、类型、凭证、extra、代理、并发、优先级、倍率、负载因子、过期策略和当前账号分组绑定；新账号名称追加“ - 副本”，运行态 ID、创建时间、更新时间、错误状态、限流状态、最近使用时间等由系统重新生成或保持初始状态。
- 前端复制成功后应把新账号插入当前列表并保留在对应 Base URL 聚类块；若当前筛选条件不匹配，则提示列表有待同步而不是强行刷新导致上下文丢失。
- 复制账号必须走管理端封装 API `adminAPI.accounts.clone`，页面不得散落底层 `apiClient` 调用；接口应支持写操作幂等，避免重复点击产生难以解释的重复数据。

#### 运维组件级 API

| 组件 | 主要 API | 说明 |
| --- | --- | --- |
| `OpsAlertRulesCard.vue` | `opsAPI.listAlertRules/createAlertRule/updateAlertRule/deleteAlertRule`、`adminAPI.groups.getAll` | 告警规则管理。 |
| `OpsAlertEventsCard.vue` | `opsAPI.listAlertEvents/getAlertEvent/updateAlertEventStatus/createAlertSilence` | 告警事件、详情、手动解决、静默。 |
| `OpsConcurrencyCard.vue` | `opsAPI.getUserConcurrencyStats/getConcurrencyStats/getAccountAvailabilityStats` | 用户并发、账号可用性。 |
| `OpsDashboardHeader.vue` | `opsAPI.getRealtimeTrafficSummary`、`adminAPI.groups.getAll` | 实时流量摘要与筛选。 |
| `OpsEmailNotificationCard.vue` | `opsAPI.getEmailNotificationConfig/updateEmailNotificationConfig` | 邮件通知配置。 |
| `OpsErrorDetailModal.vue` | `opsAPI.listRequestErrorUpstreamErrors/getUpstreamErrorDetail/getRequestErrorDetail` | 请求错误/上游错误详情。 |
| `OpsErrorDetailsModal.vue` | `opsAPI.listUpstreamErrors/listRequestErrors` | 错误列表弹窗。 |
| `OpsOpenAITokenStatsCard.vue` | `opsAPI.getOpenAITokenStats` | OpenAI token 统计。 |
| `OpsRequestDetailsModal.vue` | `opsAPI.listRequestDetails` | 请求详情列表。 |
| `OpsRuntimeSettingsCard.vue` | `opsAPI.getAlertRuntimeSettings/updateAlertRuntimeSettings` | 运行时告警设置。 |
| `OpsSettingsDialog.vue` | `opsAPI.getAlertRuntimeSettings/getEmailNotificationConfig/getAdvancedSettings/getMetricThresholds/updateAlertRuntimeSettings/updateEmailNotificationConfig/updateAdvancedSettings/updateMetricThresholds` | 运维设置弹窗。 |
| `OpsSystemLogTable.vue` | `opsAPI.listSystemLogs/getSystemLogSinkHealth/getRuntimeLogConfig/updateRuntimeLogConfig/resetRuntimeLogConfig/cleanupSystemLogs` | 系统日志、日志配置、清理。 |

### API 模块职责

用户侧 API：

- `api/client.ts`：统一 axios 实例、token 注入、401/刷新 token、错误处理。
- `api/auth.ts`：登录、注册、token、公共设置、OAuth/OIDC/微信回调、验证码、邀请码/促销码校验、找回/重置密码。
- `api/user.ts`：用户资料、邀请/返利、用户级操作。
- `api/keys.ts`：用户 API Key 的列表、创建、编辑、删除、启停、额度/限速重置。
- `api/usage.ts`：用户用量列表、统计、趋势、模型分布、Key 维度用量。
- `api/redeem.ts`：用户兑换码使用与历史。
- `api/payment.ts`：用户订单、支付、退款、Stripe/微信等支付结果查询。
- `api/subscriptions.ts`：用户订阅列表、活跃订阅、进度和汇总。
- `api/channels.ts`：用户可用渠道。
- `api/groups.ts`：用户可用分组与分组倍率。
- `api/channelMonitor.ts`：用户侧渠道监控列表与详情。
- `api/totp.ts`：TOTP/验证码二次验证。
- `api/setup.ts`：安装向导专用 setup 请求。
- `api/announcements.ts`：用户公告列表与已读状态。

管理侧 API：

- `api/admin/index.ts`：管理侧 API 聚合出口。
- `api/admin/dashboard.ts`：管理首页统计、趋势、排行和批量用量。
- `api/admin/users.ts`：用户 CRUD、余额、并发、状态、分组、身份绑定。
- `api/admin/accounts.ts`：上游账号 CRUD、状态、测试、刷新、恢复、OAuth 导入、CRS 同步、批量操作、OpenAI token 刷新、隐私设置。
- `api/admin/channels.ts`：渠道 CRUD、模型定价、账号关联、分组策略。
- `api/admin/groups.ts`：分组 CRUD、倍率、默认权限和关联策略。
- `api/admin/proxies.ts`：代理 CRUD、测试、质量检查、账号关联、批量导入导出。
- `api/admin/usage.ts`：管理端用量查询、统计、用户/Key 搜索、清理任务。
- `api/admin/subscriptions.ts`：订阅分配、批量分配、延期、撤销、额度重置。
- `api/admin/redeem.ts`：兑换码生成、导出、统计和批量管理。
- `api/admin/promo.ts`：促销码 CRUD 和使用记录。
- `api/admin/announcements.ts`：公告 CRUD、已读状态。
- `api/admin/settings.ts`：系统设置、SMTP、管理员 API Key、运行时策略、Web Search、Beta/Rectifier/超时等配置。
- `api/admin/payment.ts`：支付配置、订单、渠道、计划、提供商。
- `api/admin/backup.ts`：S3 备份、计划、下载、恢复、删除。
- `api/admin/channelMonitor.ts`：管理侧渠道监控规则。
- `api/admin/ops.ts`：运维监控、错误、日志、告警、并发、token 统计、运行时设置。
- `api/admin/affiliates.ts`：推广返利用户列表、查找、设置、清除、批量设置倍率。
- `api/admin/userAttributes.ts`：用户自定义属性定义和值。
- `api/admin/system.ts`：版本、更新、回滚、重启服务。
- `api/admin/scheduledTests.ts`：账号计划测试与结果。
- `api/admin/tlsFingerprintProfile.ts`：TLS 指纹配置。
- `api/admin/antigravity.ts`、`api/admin/gemini.ts`、`api/admin/errorPassthrough.ts`、`api/admin/dataManagement.ts`：平台/数据/错误透传等专项能力。

### 前端维护规则

- 新增页面必须同步更新 `frontend/src/router/index.ts` 的 route meta，并在 README 的页面到 API 矩阵中登记。
- 新增接口必须优先封装到 `frontend/src/api`，页面不直接散落底层 `apiClient` 调用，OAuth/回调等特殊场景除外。
- 跨页面共享状态放入 `frontend/src/stores`，页面局部临时状态留在组件内部。
- 新增后台页面必须显式声明 `requiresAdmin: true`。
- 新增支付相关页面必须显式声明 `requiresPayment: true` 或说明为什么不需要支付开关控制。
- 新增用户可见文案优先接入 `frontend/src/i18n`，避免页面内长期硬编码。
- Markdown/富文本渲染必须经过 `dompurify` 或等价清洗流程。
- 大列表优先考虑 `@tanstack/vue-virtual`，避免后台表格或日志页一次性渲染过多 DOM。

### 前端发布注意事项

- 运维变更默认一律走热重载优先：能同步静态产物、reload 配置、热替换运行态的，不走整镜像构建。
- 仅前端静态资源变更时，只同步 `frontend/dist` 到服务端 `data/public/`，不重启后端服务。
- 前端静态发布后，线上 Nginx 必须让 SPA 入口和所有 fallback HTML 返回 `Cache-Control: no-cache, no-store, must-revalidate`；否则浏览器可能继续使用旧 `index.html`，导致用户看不到新 chunk。
- `/assets/` 下带 hash 的构建产物可以返回 `Cache-Control: public, max-age=31536000, immutable`；发布依靠文件 hash 切换版本，不直接覆盖同名 chunk。
- 配置类变更优先调用 `POST /api/reload-config`。
- 后端 Go 代码改动不能通过 `data/public/` 热更新；必须生效时优先使用最小重启/替换运行二进制，不默认执行 `docker build`。
- 只有热重载无效、进程异常或运行态不同步时再调用 `POST /api/restart-service`。
- 只有用户明确要求完整镜像发布、基础镜像/依赖变更、或最小重启路径不可用时，才允许执行 `docker build` / `docker compose up --build`。
- 通过 Nginx 反代时仍需保留本文档后续 `underscores_in_headers on;` 约定，避免会话粘性相关请求头被丢弃。

---

## CI/CD 与质量门禁

当前仓库使用 GitHub Actions、Makefile 和专项脚本共同承担质量检查。

### GitHub Actions

| Workflow | 触发 | 主要检查 |
| --- | --- | --- |
| `.github/workflows/backend-ci.yml` | `push`、`pull_request` | Go 1.26.2 校验、后端单元测试、后端集成测试、前端 `pnpm install --frozen-lockfile`、前端 lint/typecheck/关键 Vitest、`golangci-lint`。 |
| `.github/workflows/security-scan.yml` | `push`、`pull_request`、每周一 | `govulncheck`、`pnpm audit --prod --audit-level=high`、审计例外校验。 |
| `.github/workflows/release.yml` | 发布流程 | 前端 pnpm 构建、后端构建、Release 产物。 |
| `.github/workflows/cla.yml` | PR/贡献流程 | CLA 检查。 |

### 根 Makefile

| 命令 | 说明 |
| --- | --- |
| `make build` | 构建后端和前端。 |
| `make build-backend` | 调用 `backend/Makefile` 构建 Go server。 |
| `make build-frontend` | 使用 `pnpm --dir frontend run build` 构建前端。 |
| `make test` | 执行后端测试和前端测试。 |
| `make test-backend` | 后端完整测试入口。 |
| `make test-frontend` | 前端 lint、typecheck 和关键 Vitest。 |
| `make test-frontend-critical` | 只跑关键前端用例。 |

### 安全与依赖

- 前端包管理以 `pnpm` 为准，`pnpm-lock.yaml` 必须和 `package.json` 同步提交。
- CI 使用 Node 20、pnpm 9、Go 1.26.2。
- 前端安全扫描使用 `pnpm audit`，例外文件是 `.github/audit-exceptions.yml`。
- 后端安全扫描使用 `govulncheck ./...`。
- 不得提交真实 token、OAuth 回调 URL 中的 token、人工密码、生产密钥或包含真实凭证的配置。

### 当前一致性注意

- 根 `Makefile` 仍包含 `build-datamanagementd`、`test-datamanagementd` 目标，但当前仓库根目录没有 `datamanagement/` 目录；使用前应确认该组件是否在独立仓库、子模块或待恢复目录中。
- 根 `Makefile` 的 `secret-scan` 目标引用 `tools/secret_scan.py`，但当前 `tools/` 下只有 `check_pnpm_audit_exceptions.py`；需要补齐脚本或更新目标。
- 前端目录同时存在 `package-lock.json` 和 `pnpm-lock.yaml`，工程约定以 `pnpm-lock.yaml` 为准；避免用 npm 重装依赖造成 lock 文件漂移。

---

## Nginx 反向代理注意事项

通过 Nginx 反向代理 Sub2API（或 CRS 服务）并搭配 Codex CLI 使用时，需要在 Nginx 配置的 `http` 块中添加：

```nginx
underscores_in_headers on;
```

Nginx 默认会丢弃名称中含下划线的请求头（如 `session_id`），这会导致多账号环境下的粘性会话功能失效。

当前公网前端由 Nginx 直接托管 `/srv/sub2api/deploy/data/public`。为了避免前端热更新后浏览器继续使用旧 SPA 入口，静态缓存策略必须固定为：

```nginx
location ^~ /assets/ {
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Permissions-Policy "camera=(), geolocation=(), microphone=()" always;
    add_header Cache-Control "public, max-age=31536000, immutable" always;
    try_files $uri =404;
}

location = /index.html {
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Permissions-Policy "camera=(), geolocation=(), microphone=()" always;
    add_header Cache-Control "no-cache, no-store, must-revalidate" always;
    try_files /index.html =404;
}

location / {
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Permissions-Policy "camera=(), geolocation=(), microphone=()" always;
    add_header Cache-Control "no-cache, no-store, must-revalidate" always;
    try_files $uri $uri/ /index.html;
}
```

其中 `/v1/`、`/api/`、`/responses`、`/health`、`/health/` 仍必须优先代理到后端，不能被前端 fallback location 抢走。

---

## OpenAI OAuth 账号导入说明

如需批量导入账号数据，请使用：

- `POST /api/v1/admin/accounts/data`

导入数据的外层结构为：

```json
{
  "data": {
    "type": "sub2api-data",
    "version": 1,
    "exported_at": "2026-05-01T00:00:00Z",
    "proxies": [],
    "accounts": []
  }
}
```

说明：

- `type` 可省略，也可使用兼容旧格式的 `sub2api-bundle`
- 如果提供 `version`，其值必须为 `1`
- `proxies` 和 `accounts` 都必须存在，并且都必须是数组

每条导入账号最少需要包含：

- `name`
- `platform`
- `type`
- `credentials`

OpenAI OAuth 账号建议使用如下稳定结构：

```json
{
  "name": "openai-oauth-account",
  "platform": "openai",
  "type": "oauth",
  "credentials": {
    "access_token": "<same-login-batch>",
    "refresh_token": "<same-login-batch>",
    "id_token": "<same-login-batch>"
  },
  "extra": {
    "privacy_mode": "training_off"
  }
}
```

解析与规范化规则：

- `access_token`、`refresh_token`、`id_token` 必须来自同一次 OAuth 登录批次
- 不要混用不同登录批次拷出的 token，即使每个 token 单看都像是有效的
- 对 OpenAI OAuth 导入，系统可从 `id_token` 中补全缺失的 `email`、`plan_type`、`chatgpt_account_id`、`chatgpt_user_id`、`organization_id`
- 如果这些字段由外部手工提供，它们应与解码后的 `id_token` claims 保持一致
- 不要把人工密码或单独邮箱地址当作这条导入链路的账号凭证

推荐的导入后校验流程：

1. 使用一组内部一致的 token 批次导入或更新账号
2. 调用 `POST /api/v1/admin/accounts/:id/test`
3. 只有拿到真实的上游成功响应后，才将该账号视为可用
4. 如果界面仍停留在旧的 `Fail` 状态，再调用 `POST /api/v1/admin/accounts/:id/clear-error`

安全说明：

- 不要把真实 `access_token`、`refresh_token`、`id_token`、包含 token 的回调 URL、人工密码提交进仓库

---

## 部署方式

### 方式一：脚本安装（推荐）

一键安装脚本，自动从 GitHub Releases 下载预编译的二进制文件。

#### 前置条件

- Linux 服务器（amd64 或 arm64）
- PostgreSQL 15+（已安装并运行）
- Redis 7+（已安装并运行）
- Root 权限

#### 安装步骤

```bash
curl -sSL https://raw.githubusercontent.com/Wei-Shaw/sub2api/main/deploy/install.sh | sudo bash
```

脚本会自动：
1. 检测系统架构
2. 下载最新版本
3. 安装二进制文件到 `/opt/sub2api`
4. 创建 systemd 服务
5. 配置系统用户和权限

#### 安装后配置

```bash
# 1. 启动服务
sudo systemctl start sub2api

# 2. 设置开机自启
sudo systemctl enable sub2api

# 3. 在浏览器中打开设置向导
# http://你的服务器IP:8080
```

设置向导将引导你完成：
- 数据库配置
- Redis 配置
- 管理员账号创建

#### 升级

可以直接在 **管理后台** 左上角点击 **检测更新** 按钮进行在线升级。

网页升级功能支持：
- 自动检测新版本
- 一键下载并应用更新
- 支持回滚

#### 常用命令

```bash
# 查看状态
sudo systemctl status sub2api

# 查看日志
sudo journalctl -u sub2api -f

# 重启服务
sudo systemctl restart sub2api

# 卸载
curl -sSL https://raw.githubusercontent.com/Wei-Shaw/sub2api/main/deploy/install.sh | sudo bash -s -- uninstall -y
```

---

### 方式二：Docker Compose（推荐）

使用 Docker Compose 部署，包含 PostgreSQL 和 Redis 容器。

#### 前置条件

- Docker 20.10+
- Docker Compose v2+

#### 快速开始（一键部署）

使用自动化部署脚本快速搭建：

```bash
# 创建部署目录
mkdir -p sub2api-deploy && cd sub2api-deploy

# 下载并运行部署准备脚本
curl -sSL https://raw.githubusercontent.com/Wei-Shaw/sub2api/main/deploy/docker-deploy.sh | bash

# 启动服务
docker compose up -d

# 查看日志
docker compose logs -f sub2api
```

**脚本功能：**
- 下载 `docker-compose.local.yml`（本地保存为 `docker-compose.yml`）和 `.env.example`
- 自动生成安全凭证（JWT_SECRET、TOTP_ENCRYPTION_KEY、POSTGRES_PASSWORD）
- 创建 `.env` 文件并填充自动生成的密钥
- 创建数据目录（使用本地目录，便于备份和迁移）
- 显示生成的凭证供你记录

#### 手动部署

如果你希望手动配置：

```bash
# 1. 克隆仓库
git clone https://github.com/Wei-Shaw/sub2api.git
cd sub2api/deploy

# 2. 复制环境配置文件
cp .env.example .env

# 3. 编辑配置（生成安全密码）
nano .env
```

**`.env` 必须配置项：**

```bash
# PostgreSQL 密码（必需）
POSTGRES_PASSWORD=your_secure_password_here

# JWT 密钥（推荐 - 重启后保持用户登录状态）
JWT_SECRET=your_jwt_secret_here

# TOTP 加密密钥（推荐 - 重启后保留双因素认证）
TOTP_ENCRYPTION_KEY=your_totp_key_here

# 可选：管理员账号
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=your_admin_password

# 可选：自定义端口
SERVER_PORT=8080
```

**生成安全密钥：**
```bash
# 生成 JWT_SECRET
openssl rand -hex 32

# 生成 TOTP_ENCRYPTION_KEY
openssl rand -hex 32

# 生成 POSTGRES_PASSWORD
openssl rand -hex 32
```

```bash
# 4. 创建数据目录（本地版）
mkdir -p data postgres_data redis_data

# 5. 启动所有服务
# 选项 A：本地目录版（推荐 - 易于迁移）
docker compose -f docker-compose.local.yml up -d

# 选项 B：命名卷版（简单设置）
docker compose up -d

# 6. 查看状态
docker compose -f docker-compose.local.yml ps

# 7. 查看日志
docker compose -f docker-compose.local.yml logs -f sub2api
```

#### 部署版本对比

| 版本 | 数据存储 | 迁移便利性 | 适用场景 |
|------|---------|-----------|---------|
| **docker-compose.local.yml** | 本地目录 | ✅ 简单（打包整个目录） | 生产环境、频繁备份 |
| **docker-compose.yml** | 命名卷 | ⚠️ 需要 docker 命令 | 简单设置 |

**推荐：** 使用 `docker-compose.local.yml`（脚本部署）以便更轻松地管理数据。

#### 启用“数据管理”功能（datamanagementd）

如需启用管理后台“数据管理”，需要额外部署宿主机数据管理进程 `datamanagementd`。

关键点：

- 主进程固定探测：`/tmp/sub2api-datamanagement.sock`
- 只有该 Socket 可连通时，数据管理功能才会开启
- Docker 场景需将宿主机 Socket 挂载到容器同路径

详细部署步骤见：`deploy/DATAMANAGEMENTD_CN.md`

#### 访问

在浏览器中打开 `http://你的服务器IP:8080`

如果管理员密码是自动生成的，在日志中查找：
```bash
docker compose -f docker-compose.local.yml logs sub2api | grep "admin password"
```

#### 升级

默认不要先整镜像构建。升级顺序固定为：热重载/静态产物同步 → `POST /api/reload-config` → 最小重启服务 → 明确需要时才拉镜像或构建镜像。

```bash
# 仅在明确需要完整镜像升级时执行
docker compose -f docker-compose.local.yml pull
docker compose -f docker-compose.local.yml up -d
```

#### 轻松迁移（本地目录版）

使用 `docker-compose.local.yml` 时，可以轻松迁移到新服务器：

```bash
# 源服务器
docker compose -f docker-compose.local.yml down
cd ..
tar czf sub2api-complete.tar.gz sub2api-deploy/

# 传输到新服务器
scp sub2api-complete.tar.gz user@new-server:/path/

# 新服务器
tar xzf sub2api-complete.tar.gz
cd sub2api-deploy/
docker compose -f docker-compose.local.yml up -d
```

#### 常用命令

```bash
# 停止所有服务
docker compose -f docker-compose.local.yml down

# 重启
docker compose -f docker-compose.local.yml restart

# 查看所有日志
docker compose -f docker-compose.local.yml logs -f

# 删除所有数据（谨慎！）
docker compose -f docker-compose.local.yml down
rm -rf data/ postgres_data/ redis_data/
```

---

### 方式三：源码编译

从源码编译安装，适合开发或定制需求。

#### 前置条件

- Go 1.21+
- Node.js 18+
- PostgreSQL 15+
- Redis 7+

#### 编译步骤

```bash
# 1. 克隆仓库
git clone https://github.com/Wei-Shaw/sub2api.git
cd sub2api

# 2. 安装 pnpm（如果还没有安装）
npm install -g pnpm

# 3. 编译前端
cd frontend
pnpm install
pnpm run build
# 构建产物输出到 ../backend/internal/web/dist/

# 4. 编译后端（嵌入前端）
cd ../backend
go build -tags embed -o sub2api ./cmd/server

# 5. 创建配置文件
cp ../deploy/config.example.yaml ./config.yaml

# 6. 编辑配置
nano config.yaml
```

> **注意：** `-tags embed` 参数会将前端嵌入到二进制文件中。不使用此参数编译的程序将不包含前端界面。

**`config.yaml` 关键配置：**

```yaml
server:
  host: "0.0.0.0"
  port: 8080
  mode: "release"

database:
  host: "localhost"
  port: 5432
  user: "postgres"
  password: "your_password"
  dbname: "sub2api"

redis:
  host: "localhost"
  port: 6379
  password: ""

jwt:
  secret: "change-this-to-a-secure-random-string"
  expire_hour: 24

default:
  user_concurrency: 5
  user_balance: 0
  api_key_prefix: "sk-"
  rate_multiplier: 1.0
```

### Sora 功能状态（暂不可用）

> ⚠️ 当前 Sora 相关功能因上游接入与媒体链路存在技术问题，暂时不可用。
> 现阶段请勿在生产环境依赖 Sora 能力。
> 文档中的 `gateway.sora_*` 配置仅作预留，待技术问题修复后再恢复可用。

### Sora 媒体签名 URL（功能恢复后可选）

当配置 `gateway.sora_media_signing_key` 且 `gateway.sora_media_signed_url_ttl_seconds > 0` 时，网关会将 Sora 输出的媒体地址改写为临时签名 URL（`/sora/media-signed/...`）。这样无需 API Key 即可在浏览器中直接访问，且具备过期控制与防篡改能力（签名包含 path + query）。

```yaml
gateway:
  # /sora/media 是否强制要求 API Key（默认 false）
  sora_media_require_api_key: false
  # 媒体临时签名密钥（为空则禁用签名）
  sora_media_signing_key: "your-signing-key"
  # 临时签名 URL 有效期（秒）
  sora_media_signed_url_ttl_seconds: 900
```

> 若未配置签名密钥，`/sora/media-signed` 将返回 503。  
> 如需更严格的访问控制，可将 `sora_media_require_api_key` 设为 true，仅允许携带 API Key 的 `/sora/media` 访问。

访问策略说明：
- `/sora/media`：内部调用或客户端携带 API Key 才能下载
- `/sora/media-signed`：外部可访问，但有签名 + 过期控制

`config.yaml` 还支持以下安全相关配置：

- `cors.allowed_origins` 配置 CORS 白名单
- `security.url_allowlist` 配置上游/价格数据/CRS 主机白名单
- `security.url_allowlist.enabled` 可关闭 URL 校验（慎用）
- `security.url_allowlist.allow_insecure_http` 关闭校验时允许 HTTP URL
- `security.url_allowlist.allow_private_hosts` 允许私有/本地 IP 地址
- `security.response_headers.enabled` 可启用可配置响应头过滤（关闭时使用默认白名单）
- `security.csp` 配置 Content-Security-Policy
- `billing.circuit_breaker` 计费异常时 fail-closed
- `server.trusted_proxies` 启用可信代理解析 X-Forwarded-For
- `turnstile.required` 在 release 模式强制启用 Turnstile

**网关防御纵深建议（重点）**

- `gateway.upstream_response_read_max_bytes`：限制非流式上游响应读取大小（默认 `8MB`），用于防止异常响应导致内存放大。
- `gateway.proxy_probe_response_read_max_bytes`：限制代理探测响应读取大小（默认 `1MB`）。
- `gateway.gemini_debug_response_headers`：默认 `false`，仅在排障时短时开启，避免高频请求日志开销。
- `/auth/register`、`/auth/login`、`/auth/login/2fa`、`/auth/send-verify-code` 已提供服务端兜底限流（Redis 故障时 fail-close）。
- 推荐将 WAF/CDN 作为第一层防护，服务端限流与响应读取上限作为第二层兜底；两层同时保留，避免旁路流量与误配置风险。

**⚠️ 安全警告：HTTP URL 配置**

当 `security.url_allowlist.enabled=false` 时，系统默认执行最小 URL 校验，**拒绝 HTTP URL**，仅允许 HTTPS。要允许 HTTP URL（例如用于开发或内网测试），必须显式设置：

```yaml
security:
  url_allowlist:
    enabled: false                # 禁用白名单检查
    allow_insecure_http: true     # 允许 HTTP URL（⚠️ 不安全）
```

**或通过环境变量：**

```bash
SECURITY_URL_ALLOWLIST_ENABLED=false
SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP=true
```

**允许 HTTP 的风险：**
- API 密钥和数据以**明文传输**（可被截获）
- 易受**中间人攻击 (MITM)**
- **不适合生产环境**

**适用场景：**
- ✅ 开发/测试环境的本地服务器（http://localhost）
- ✅ 内网可信端点
- ✅ 获取 HTTPS 前测试账号连通性
- ❌ 生产环境（仅使用 HTTPS）

**未设置此项时的错误示例：**
```
Invalid base URL: invalid url scheme: http
```

如关闭 URL 校验或响应头过滤，请加强网络层防护：
- 出站访问白名单限制上游域名/IP
- 阻断私网/回环/链路本地地址
- 强制仅允许 TLS 出站
- 在反向代理层移除敏感响应头

```bash
# 6. 运行应用
./sub2api
```

#### HTTP/2 (h2c) 与 HTTP/1.1 回退

后端明文端口默认支持 h2c，并保留 HTTP/1.1 回退用于 WebSocket 与旧客户端。浏览器通常不支持 h2c，性能收益主要在反向代理或内网链路。

**反向代理示例（Caddy）：**

```caddyfile
transport http {
	versions h2c h1
}
```

**验证：**

```bash
# h2c prior knowledge
curl --http2-prior-knowledge -I http://localhost:8080/health
# HTTP/1.1 回退
curl --http1.1 -I http://localhost:8080/health
# WebSocket 回退验证（需管理员 token）
websocat -H="Sec-WebSocket-Protocol: sub2api-admin, jwt.<ADMIN_TOKEN>" ws://localhost:8080/api/v1/admin/ops/ws/qps
```

#### 开发模式

```bash
# 后端（支持热重载）
cd backend
go run ./cmd/server

# 前端（支持热重载）
cd frontend
pnpm run dev
```

#### 代码生成

修改 `backend/ent/schema` 后，需要重新生成 Ent + Wire：

```bash
cd backend
go generate ./ent
go generate ./cmd/server
```

---

## 简易模式

简易模式适合个人开发者或内部团队快速使用，不依赖完整 SaaS 功能。

- 启用方式：设置环境变量 `RUN_MODE=simple`
- 功能差异：隐藏 SaaS 相关功能，跳过计费流程
- 安全注意事项：生产环境需同时设置 `SIMPLE_MODE_CONFIRM=true` 才允许启动

---

## Antigravity 使用说明

Sub2API 支持 [Antigravity](https://antigravity.so/) 账户，授权后可通过专用端点访问 Claude 和 Gemini 模型。

### 专用端点

| 端点 | 模型 |
|------|------|
| `/antigravity/v1/messages` | Claude 模型 |
| `/antigravity/v1beta/` | Gemini 模型 |

### Claude Code 配置示例

```bash
export ANTHROPIC_BASE_URL="http://localhost:8080/antigravity"
export ANTHROPIC_AUTH_TOKEN="sk-xxx"
```

### 混合调度模式

Antigravity 账户支持可选的**混合调度**功能。开启后，通用端点 `/v1/messages` 和 `/v1beta/` 也会调度该账户。

> **⚠️ 注意**：Anthropic Claude 和 Antigravity Claude **不能在同一上下文中混合使用**，请通过分组功能做好隔离。


### 已知问题
在 Claude Code 中，无法自动退出Plan Mode。（正常使用原生Claude Api时，Plan 完成后，Claude Code会弹出弹出选项让用户同意或拒绝Plan。） 
解决办法：shift + Tab，手动退出Plan mode，然后输入内容 告诉 Claude Code 同意或拒绝 Plan
---

## 项目结构

```
sub2api/
├── backend/                  # Go 后端服务
│   ├── cmd/server/           # 应用入口
│   ├── internal/             # 内部模块
│   │   ├── config/           # 配置管理
│   │   ├── model/            # 数据模型
│   │   ├── service/          # 业务逻辑
│   │   ├── handler/          # HTTP 处理器
│   │   └── gateway/          # API 网关核心
│   └── resources/            # 静态资源
│
├── frontend/                 # Vue 3 前端
│   └── src/
│       ├── api/              # API 调用
│       ├── stores/           # 状态管理
│       ├── views/            # 页面组件
│       └── components/       # 通用组件
│
└── deploy/                   # 部署文件
    ├── docker-compose.yml    # Docker Compose 配置
    ├── .env.example          # Docker Compose 环境变量
    ├── config.example.yaml   # 二进制部署完整配置文件
    └── install.sh            # 一键安装脚本
```

## 免责声明

> **使用本项目前请仔细阅读：**
>
> :rotating_light: **服务条款风险**: 使用本项目可能违反 Anthropic 的服务条款。请在使用前仔细阅读 Anthropic 的用户协议，使用本项目的一切风险由用户自行承担。
>
> :book: **免责声明**: 本项目仅供技术学习和研究使用，作者不对因使用本项目导致的账户封禁、服务中断或其他损失承担任何责任。

---

## Star History

<a href="https://star-history.com/#Wei-Shaw/sub2api&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Wei-Shaw/sub2api&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Wei-Shaw/sub2api&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Wei-Shaw/sub2api&type=Date" />
 </picture>
</a>

---

## 许可证

本项目基于 [GNU 宽通用公共许可证 v3.0](LICENSE)（或更高版本）授权。

Copyright (c) 2026 Wesley Liddick

---

<div align="center">

**如果觉得有用，请给个 Star 支持一下！**

</div>
