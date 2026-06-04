package service

import "context"

// Anthropic403CounterCache 追踪 Anthropic 账号连续 403 失败次数。
// 与 OpenAI403CounterCache 同构,但使用独立的 Redis key 前缀,
// 使 anthropic / openai 两平台的 403 计数互不干扰、阈值互相隔离。
type Anthropic403CounterCache interface {
	// IncrementAnthropic403Count 原子递增 403 计数并返回当前值。
	IncrementAnthropic403Count(ctx context.Context, accountID int64, windowMinutes int) (int64, error)
	// ResetAnthropic403Count 成功后清零计数器。
	ResetAnthropic403Count(ctx context.Context, accountID int64) error
}
