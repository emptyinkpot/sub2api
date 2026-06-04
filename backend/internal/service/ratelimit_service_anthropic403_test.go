//go:build unit

package service

import (
	"context"
	"net/http"
	"testing"

	"github.com/Wei-Shaw/sub2api/internal/config"
	"github.com/stretchr/testify/require"
)

type anthropic403CounterCacheStub struct {
	counts     []int64
	resetCalls []int64
	err        error
}

func (s *anthropic403CounterCacheStub) IncrementAnthropic403Count(_ context.Context, _ int64, _ int) (int64, error) {
	if s.err != nil {
		return 0, s.err
	}
	if len(s.counts) == 0 {
		return 1, nil
	}
	count := s.counts[0]
	s.counts = s.counts[1:]
	return count, nil
}

func (s *anthropic403CounterCacheStub) ResetAnthropic403Count(_ context.Context, accountID int64) error {
	s.resetCalls = append(s.resetCalls, accountID)
	return nil
}

// 连续未达阈值：只临时冷却，不永久禁号（瞬态 origin 403 不再一次摘号）。
func TestRateLimitService_HandleUpstreamError_Anthropic403FirstHitTempUnschedulable(t *testing.T) {
	repo := &rateLimitAccountRepoStub{}
	counter := &anthropic403CounterCacheStub{counts: []int64{1}}
	service := NewRateLimitService(repo, nil, &config.Config{}, nil, nil)
	service.SetAnthropic403CounterCache(counter)
	account := &Account{ID: 401, Platform: PlatformAnthropic, Type: AccountTypeAPIKey}

	shouldDisable := service.HandleUpstreamError(
		context.Background(), account, http.StatusForbidden, http.Header{},
		[]byte(`{"error":{"type":"bad_response_status_code","message":"bad response status code 403"}}`),
	)

	require.True(t, shouldDisable)
	require.Equal(t, 0, repo.setErrorCalls)
	require.Equal(t, 1, repo.tempCalls)
	require.Contains(t, repo.lastTempReason, "(1/3)")
}

// 达阈值：永久禁号（真号坏了仍会被摘）。
func TestRateLimitService_HandleUpstreamError_Anthropic403ThresholdDisables(t *testing.T) {
	repo := &rateLimitAccountRepoStub{}
	counter := &anthropic403CounterCacheStub{counts: []int64{3}}
	service := NewRateLimitService(repo, nil, &config.Config{}, nil, nil)
	service.SetAnthropic403CounterCache(counter)
	account := &Account{ID: 402, Platform: PlatformAnthropic, Type: AccountTypeAPIKey}

	shouldDisable := service.HandleUpstreamError(
		context.Background(), account, http.StatusForbidden, http.Header{},
		[]byte(`{"error":{"message":"forbidden"}}`),
	)

	require.True(t, shouldDisable)
	require.Equal(t, 1, repo.setErrorCalls)
	require.Equal(t, 0, repo.tempCalls)
	require.Contains(t, repo.lastErrorMsg, "consecutive_403=3/3")
}

// cache 缺失：安全降级回原 SetError 行为，不改既有失败语义。
func TestRateLimitService_HandleUpstreamError_Anthropic403NilCacheFallsBackToSetError(t *testing.T) {
	repo := &rateLimitAccountRepoStub{}
	service := NewRateLimitService(repo, nil, &config.Config{}, nil, nil)
	account := &Account{ID: 403, Platform: PlatformAnthropic, Type: AccountTypeAPIKey}

	shouldDisable := service.HandleUpstreamError(
		context.Background(), account, http.StatusForbidden, http.Header{},
		[]byte(`{"error":{"message":"forbidden"}}`),
	)

	require.True(t, shouldDisable)
	require.Equal(t, 1, repo.setErrorCalls)
	require.Equal(t, 0, repo.tempCalls)
}

// 成功响应清零计数器（连续语义命门）。
func TestRateLimitService_ResetAnthropic403Counter(t *testing.T) {
	counter := &anthropic403CounterCacheStub{}
	service := NewRateLimitService(&rateLimitAccountRepoStub{}, nil, &config.Config{}, nil, nil)
	service.SetAnthropic403CounterCache(counter)

	service.ResetAnthropic403Counter(context.Background(), 456)

	require.Equal(t, []int64{456}, counter.resetCalls)
}
