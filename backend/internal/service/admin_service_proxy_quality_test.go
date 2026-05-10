package service

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/pkg/pagination"
	"github.com/stretchr/testify/require"
)

func TestFinalizeProxyQualityResult_ScoreAndGrade(t *testing.T) {
	result := &ProxyQualityCheckResult{
		PassedCount:    2,
		WarnCount:      1,
		FailedCount:    1,
		ChallengeCount: 1,
	}

	finalizeProxyQualityResult(result)

	require.Equal(t, 38, result.Score)
	require.Equal(t, "F", result.Grade)
	require.Contains(t, result.Summary, "通过 2 项")
	require.Contains(t, result.Summary, "告警 1 项")
	require.Contains(t, result.Summary, "失败 1 项")
	require.Contains(t, result.Summary, "挑战 1 项")
}

func TestRunProxyQualityTarget_CloudflareChallenge(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.Header().Set("cf-ray", "test-ray-123")
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte("<!DOCTYPE html><title>Just a moment...</title><script>window._cf_chl_opt={};</script>"))
	}))
	defer server.Close()

	target := proxyQualityTarget{
		Target: "openai",
		URL:    server.URL,
		Method: http.MethodGet,
		AllowedStatuses: map[int]struct{}{
			http.StatusUnauthorized: {},
		},
	}

	item := runProxyQualityTarget(context.Background(), server.Client(), target)
	require.Equal(t, "challenge", item.Status)
	require.Equal(t, http.StatusForbidden, item.HTTPStatus)
	require.Equal(t, "test-ray-123", item.CFRay)
}

func TestRunProxyQualityTarget_AllowedStatusPass(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"models":[]}`))
	}))
	defer server.Close()

	target := proxyQualityTarget{
		Target: "gemini",
		URL:    server.URL,
		Method: http.MethodGet,
		AllowedStatuses: map[int]struct{}{
			http.StatusOK: {},
		},
	}

	item := runProxyQualityTarget(context.Background(), server.Client(), target)
	require.Equal(t, "pass", item.Status)
	require.Equal(t, http.StatusOK, item.HTTPStatus)
}

func TestRunProxyQualityTarget_AllowedStatusWarnForUnauthorized(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"unauthorized"}`))
	}))
	defer server.Close()

	target := proxyQualityTarget{
		Target: "openai",
		URL:    server.URL,
		Method: http.MethodGet,
		AllowedStatuses: map[int]struct{}{
			http.StatusUnauthorized: {},
		},
	}

	item := runProxyQualityTarget(context.Background(), server.Client(), target)
	require.Equal(t, "warn", item.Status)
	require.Equal(t, http.StatusUnauthorized, item.HTTPStatus)
	require.Contains(t, item.Message, "目标可达")
}

func TestAdminServiceGetProxyRiskSummary(t *testing.T) {
	now := time.Now().Unix()
	healthyScore := 95
	warnScore := 72
	staleChecked := now - 25*60*60
	freshChecked := now - 60

	svc := &adminServiceImpl{
		proxyRepo: &proxyRiskSummaryRepoStub{
			proxies: []ProxyWithAccountCount{
				{
					Proxy:          Proxy{ID: 1, Name: "healthy", Status: StatusActive},
					AccountCount:   2,
					QualityStatus:  "healthy",
					QualityScore:   &healthyScore,
					QualityChecked: &freshChecked,
				},
				{
					Proxy:          Proxy{ID: 2, Name: "warn", Status: StatusActive},
					AccountCount:   1,
					QualityStatus:  "warn",
					QualityScore:   &warnScore,
					QualityChecked: &staleChecked,
				},
				{
					Proxy:        Proxy{ID: 3, Name: "unknown", Status: StatusActive},
					AccountCount: 0,
				},
			},
		},
	}

	summary, err := svc.GetProxyRiskSummary(context.Background())
	require.NoError(t, err)
	require.Equal(t, 3, summary.Total)
	require.Equal(t, 1, summary.Healthy)
	require.Equal(t, 1, summary.Warn)
	require.Equal(t, 0, summary.Failed)
	require.Equal(t, 0, summary.Challenge)
	require.Equal(t, 1, summary.Unknown)
	require.Equal(t, 2, summary.StaleCount)
	require.NotNil(t, summary.AverageScore)
	require.InDelta(t, 83.5, *summary.AverageScore, 0.001)
	require.NotNil(t, summary.OldestCheckedAt)
	require.Equal(t, staleChecked, *summary.OldestCheckedAt)
	require.Len(t, summary.RiskyProxies, 2)
	require.Equal(t, int64(2), summary.RiskyProxies[0].ID)
	require.Equal(t, "warn", summary.RiskyProxies[0].QualityStatus)
	require.Equal(t, int64(3), summary.RiskyProxies[1].ID)
	require.Equal(t, "unknown", summary.RiskyProxies[1].QualityStatus)
}

type proxyRiskSummaryRepoStub struct {
	proxies []ProxyWithAccountCount
}

func (s *proxyRiskSummaryRepoStub) Create(context.Context, *Proxy) error { panic("unexpected Create") }
func (s *proxyRiskSummaryRepoStub) GetByID(context.Context, int64) (*Proxy, error) {
	panic("unexpected GetByID")
}
func (s *proxyRiskSummaryRepoStub) ListByIDs(context.Context, []int64) ([]Proxy, error) {
	panic("unexpected ListByIDs")
}
func (s *proxyRiskSummaryRepoStub) Update(context.Context, *Proxy) error { panic("unexpected Update") }
func (s *proxyRiskSummaryRepoStub) Delete(context.Context, int64) error  { panic("unexpected Delete") }
func (s *proxyRiskSummaryRepoStub) List(context.Context, pagination.PaginationParams) ([]Proxy, *pagination.PaginationResult, error) {
	panic("unexpected List")
}
func (s *proxyRiskSummaryRepoStub) ListWithFilters(context.Context, pagination.PaginationParams, string, string, string) ([]Proxy, *pagination.PaginationResult, error) {
	panic("unexpected ListWithFilters")
}
func (s *proxyRiskSummaryRepoStub) ListWithFiltersAndAccountCount(context.Context, pagination.PaginationParams, string, string, string) ([]ProxyWithAccountCount, *pagination.PaginationResult, error) {
	panic("unexpected ListWithFiltersAndAccountCount")
}
func (s *proxyRiskSummaryRepoStub) ListActive(context.Context) ([]Proxy, error) {
	panic("unexpected ListActive")
}
func (s *proxyRiskSummaryRepoStub) ListActiveWithAccountCount(context.Context) ([]ProxyWithAccountCount, error) {
	return s.proxies, nil
}
func (s *proxyRiskSummaryRepoStub) ExistsByHostPortAuth(context.Context, string, int, string, string) (bool, error) {
	panic("unexpected ExistsByHostPortAuth")
}
func (s *proxyRiskSummaryRepoStub) CountAccountsByProxyID(context.Context, int64) (int64, error) {
	panic("unexpected CountAccountsByProxyID")
}
func (s *proxyRiskSummaryRepoStub) ListAccountSummariesByProxyID(context.Context, int64) ([]ProxyAccountSummary, error) {
	panic("unexpected ListAccountSummariesByProxyID")
}
