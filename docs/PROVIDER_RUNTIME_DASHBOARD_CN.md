# Provider Runtime Dashboard

本文定义 Sub2API P0 阶段的运行透明度目标。这里的 runtime 指 API 中转网关的运行态，不代表 Agent Runtime 或 Workflow Runtime。

## 目标

Sub2API 当前已经具备账号池、渠道监控、用量统计、账号测试、Ops Monitoring 和管理后台。P0 不新造一套系统，而是以现有 `/admin/ops` 为主入口，把这些已有能力收敛成一个面向运营的 Provider Runtime Dashboard，让管理员能快速回答：

- 哪些 provider / account 正常，哪些正在降级或失败
- 哪些模型的延迟、失败率、重试量异常
- 当前 token 吞吐、成本和额度消耗是否健康
- 失败来自上游、账号、代理、限流、配置还是用户请求
- fallback / retry 是否真的改善了成功率

## 非目标

P0 不做：

- Agent Runtime
- Workflow Runtime
- tool execution layer
- semantic memory
- 完整 distributed trace graph

这些可以作为长期演进方向，但不能写成当前能力。

## 现有能力映射

| 能力 | 现有入口 | P0 用法 |
| --- | --- | --- |
| Provider health | `channel_monitors` / `channel_monitor_history` | 汇总 provider、model、endpoint 最近健康状态 |
| Account test | `AccountTestService` | 将手动测试结果归入 account health |
| Usage stats | `/admin/usage/stats`、dashboard trend/model/group APIs | 计算 throughput、cost、token 和请求量 |
| Ops Monitoring UI | `/admin/ops` / `OpsDashboard.vue` | 作为 P0 运行态总览主入口 |
| Admin monitor UI | `ChannelMonitorView.vue` | 作为 provider/model 探测配置与详情入口 |
| Request logs | usage logs | 展示失败请求、延迟和成本明细 |

## P0 数据模型

第一版不要求新增持久化表，优先做只读聚合 API：

```text
GET /api/v1/admin/runtime/providers/summary
```

建议响应结构：

```json
{
  "generated_at": "2026-05-08T00:00:00Z",
  "window": {
    "minutes": 60
  },
  "providers": [
    {
      "provider": "openai",
      "status": "operational",
      "monitors": 3,
      "accounts": 12,
      "healthy_accounts": 10,
      "degraded_accounts": 1,
      "failed_accounts": 1,
      "requests": 1200,
      "failures": 24,
      "failure_rate": 0.02,
      "avg_latency_ms": 860,
      "p95_latency_ms": 2200,
      "input_tokens": 123456,
      "output_tokens": 65432,
      "actual_cost": 12.34,
      "recent_errors": [
        {
          "code": "rate_limited",
          "count": 10
        }
      ]
    }
  ]
}
```

## Account Health Score

第一版用可解释的规则，不做黑盒算法。

建议字段：

```text
score = 100
- recent_failure_penalty
- latency_penalty
- rate_limit_penalty
- disabled_or_expired_penalty
+ recent_success_bonus
```

分级：

| Score | 状态 |
| --- | --- |
| 80-100 | healthy |
| 50-79 | degraded |
| 1-49 | failing |
| 0 | disabled / unavailable |

第一版可以先只在 API 响应中计算，不写回数据库。等 routing 真正使用 score 时，再考虑落表或缓存。

## UI 第一版

不新增平行页面。第一版以现有后台入口为准：

```text
Admin -> Ops Monitoring
```

`OpsDashboard.vue` 已经承载 throughput、latency、error trend、error distribution、request details、alert events、runtime settings 等能力。P0 只补齐 provider/account 视角，避免重复建设。

第一屏应稳定呈现这些区域：

- Provider cards：provider 状态、请求量、失败率、延迟、成本
- Account health table：账号、provider、score、最近测试、最近失败原因
- Model QoS table：模型、请求量、失败率、平均延迟、p95 延迟
- Recent failures：最近失败请求，带错误分类、账号、provider、model

Channel Monitor 和 Usage 页面继续保留为详情页。Ops 页面只做总览和跳转，不复制全部配置表单。

## 错误分类

P0 必须先统一错误分类，否则 observability 只能展示散乱 message。

建议初始 taxonomy：

- `rate_limited`
- `auth_failed`
- `account_expired`
- `provider_timeout`
- `provider_5xx`
- `proxy_failed`
- `model_not_available`
- `quota_exceeded`
- `invalid_request`
- `unknown`

## 实施顺序

1. 对齐现有 `/admin/ops` 数据结构，定义 provider/account summary 扩展字段
2. 后端聚合 channel monitor + usage stats + account status
3. 增加错误分类 helper
4. 在 `OpsDashboard.vue` 增加 provider/account/model 运行态卡片
5. 把 Ops、Channel Monitor 和 Usage 页面互相链接
6. 加最小测试：JSON contract、错误分类、空数据行为

## 验收标准

- 管理员无需翻多个页面即可看到 provider/account/model 的健康概览
- 空数据、无 monitor、无 usage 时页面可解释，不报错
- API 返回结构稳定，前端不解析自由文本 message
- 不引入明文 token、refresh token、id token 或完整 API key
- README 和 `project.json` 的 P0 描述与此文档一致
