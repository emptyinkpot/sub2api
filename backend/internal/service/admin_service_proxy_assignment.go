package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

	infraerrors "github.com/Wei-Shaw/sub2api/internal/pkg/errors"
	"github.com/Wei-Shaw/sub2api/internal/pkg/logger"
)

type ProxyAssignmentInput struct {
	AccountIDs              []int64                   `json:"account_ids"`
	Filters                 *BulkUpdateAccountFilters `json:"filters"`
	PlanID                  string                    `json:"plan_id,omitempty"`
	OnlyUnbound             bool                      `json:"only_unbound"`
	PreserveExistingBinding *bool                     `json:"preserve_existing_binding,omitempty"`
	RequireExitIP           *bool                     `json:"require_exit_ip,omitempty"`
	MinQualityScore         *int                      `json:"min_quality_score,omitempty"`
	MaxAccountsPerExitIP    *int                      `json:"max_accounts_per_exit_ip,omitempty"`
}

type ProxyAssignmentPlan struct {
	PlanID       string                 `json:"plan_id"`
	GeneratedAt  int64                  `json:"generated_at"`
	AccountCount int                    `json:"account_count"`
	ChangeCount  int                    `json:"change_count"`
	Items        []ProxyAssignmentItem  `json:"items"`
	Summary      ProxyAssignmentSummary `json:"summary"`
}

type ProxyAssignmentSummary struct {
	Keep      int `json:"keep"`
	Assign    int `json:"assign"`
	Rebalance int `json:"rebalance"`
	Skip      int `json:"skip"`
	NoProxy   int `json:"no_available_proxy"`
	OverLimit int `json:"exit_ip_over_limit"`
}

type ProxyAssignmentItem struct {
	AccountID            int64    `json:"account_id"`
	AccountName          string   `json:"account_name"`
	Platform             string   `json:"platform"`
	Type                 string   `json:"type"`
	OldProxyID           *int64   `json:"old_proxy_id,omitempty"`
	OldProxyName         string   `json:"old_proxy_name,omitempty"`
	OldExitIP            string   `json:"old_exit_ip,omitempty"`
	NewProxyID           *int64   `json:"new_proxy_id,omitempty"`
	NewProxyName         string   `json:"new_proxy_name,omitempty"`
	NewExitIP            string   `json:"new_exit_ip,omitempty"`
	Action               string   `json:"action"`
	Reason               string   `json:"reason"`
	Warnings             []string `json:"warnings,omitempty"`
	MaxAccountsPerExitIP int      `json:"max_accounts_per_exit_ip"`
}

type ProxyAssignmentApplyResult struct {
	Plan       *ProxyAssignmentPlan       `json:"plan"`
	Success    int                        `json:"success"`
	Failed     int                        `json:"failed"`
	SuccessIDs []int64                    `json:"success_ids"`
	FailedIDs  []int64                    `json:"failed_ids"`
	Results    []ProxyAssignmentApplyItem `json:"results"`
}

type ProxyAssignmentApplyItem struct {
	AccountID int64  `json:"account_id"`
	Success   bool   `json:"success"`
	Action    string `json:"action"`
	Error     string `json:"error,omitempty"`
}

func (s *adminServiceImpl) CloneAccount(ctx context.Context, id int64) (*Account, error) {
	account, err := s.accountRepo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}

	clonedName := strings.TrimSpace(account.Name)
	if clonedName == "" {
		clonedName = fmt.Sprintf("account-%d", account.ID)
	}

	input := &CreateAccountInput{
		Name:                  clonedName + " - 副本",
		Notes:                 account.Notes,
		Platform:              account.Platform,
		Type:                  account.Type,
		Credentials:           cloneAccountJSONMap(account.Credentials),
		Extra:                 cloneAccountJSONMap(account.Extra),
		ProxyID:               cloneInt64Ptr(account.ProxyID),
		Concurrency:           account.Concurrency,
		Priority:              account.Priority,
		RateMultiplier:        cloneFloat64Ptr(account.RateMultiplier),
		LoadFactor:            cloneIntPtr(account.LoadFactor),
		GroupIDs:              append([]int64(nil), account.GroupIDs...),
		ExpiresAt:             timeToUnixSecondsPtr(account.ExpiresAt),
		AutoPauseOnExpired:    cloneBoolPtr(account.AutoPauseOnExpired),
		SkipMixedChannelCheck: true,
	}

	cloned, err := s.CreateAccount(ctx, input)
	if err != nil {
		return nil, err
	}
	return s.accountRepo.GetByID(ctx, cloned.ID)
}

func (s *adminServiceImpl) buildProxyAssignmentPlan(ctx context.Context, input *ProxyAssignmentInput) (*ProxyAssignmentPlan, error) {
	if input == nil {
		input = &ProxyAssignmentInput{}
	}
	accountIDs := dedupeInt64s(input.AccountIDs)
	if len(accountIDs) == 0 && input.Filters != nil {
		ids, err := s.resolveBulkUpdateTargetIDs(ctx, input.Filters)
		if err != nil {
			return nil, err
		}
		accountIDs = dedupeInt64s(ids)
	}
	plan := &ProxyAssignmentPlan{
		GeneratedAt: time.Now().Unix(),
		Items:       make([]ProxyAssignmentItem, 0, len(accountIDs)),
	}
	if len(accountIDs) == 0 {
		plan.PlanID = proxyAssignmentPlanID(plan.Items)
		return plan, nil
	}

	accounts, err := s.accountRepo.GetByIDs(ctx, accountIDs)
	if err != nil {
		return nil, err
	}
	proxies, err := s.GetAllProxiesWithAccountCount(ctx)
	if err != nil {
		return nil, err
	}

	preserveExisting := true
	if input.PreserveExistingBinding != nil {
		preserveExisting = *input.PreserveExistingBinding
	}
	requireExitIP := true
	if input.RequireExitIP != nil {
		requireExitIP = *input.RequireExitIP
	}
	minQualityScore := 70
	if input.MinQualityScore != nil {
		minQualityScore = *input.MinQualityScore
	}

	proxyByID := make(map[int64]ProxyWithAccountCount, len(proxies))
	exitUsage := make(map[string]int64, len(proxies))
	eligible := make([]ProxyWithAccountCount, 0, len(proxies))
	for i := range proxies {
		p := proxies[i]
		proxyByID[p.ID] = p
		exitIP := proxyExitIP(p)
		if exitIP != "" {
			exitUsage[exitIP] += p.AccountCount
		}
		if !proxyEligibleForAssignment(p, requireExitIP, minQualityScore) {
			continue
		}
		eligible = append(eligible, p)
	}

	if !preserveExisting {
		for _, account := range accounts {
			if account == nil || account.ProxyID == nil {
				continue
			}
			if p, ok := proxyByID[*account.ProxyID]; ok {
				if exitIP := proxyExitIP(p); exitIP != "" && exitUsage[exitIP] > 0 {
					exitUsage[exitIP]--
				}
			}
		}
	}

	sortProxyAssignmentCandidates(eligible, exitUsage)
	for _, account := range accounts {
		if account == nil {
			continue
		}
		item := ProxyAssignmentItem{
			AccountID:            account.ID,
			AccountName:          account.Name,
			Platform:             account.Platform,
			Type:                 account.Type,
			Action:               "skip",
			Reason:               "no_available_proxy",
			Warnings:             make([]string, 0),
			MaxAccountsPerExitIP: proxyAssignmentMaxAccountsPerExitIP(account, input.MaxAccountsPerExitIP),
		}
		if account.ProxyID != nil {
			item.OldProxyID = cloneInt64Ptr(account.ProxyID)
			if oldProxy, ok := proxyByID[*account.ProxyID]; ok {
				item.OldProxyName = oldProxy.Name
				item.OldExitIP = proxyExitIP(oldProxy)
			} else if account.Proxy != nil {
				item.OldProxyName = account.Proxy.Name
				item.OldExitIP = account.Proxy.IPAddress
			}
		}
		if account.ProxyID != nil && (preserveExisting || input.OnlyUnbound) {
			item.Action = "keep"
			item.Reason = "existing_binding"
			plan.Summary.Keep++
			plan.Items = append(plan.Items, item)
			continue
		}

		selected, ok := chooseProxyAssignmentCandidate(eligible, exitUsage, item.MaxAccountsPerExitIP, account.ProxyID)
		if !ok {
			if len(eligible) == 0 {
				item.Warnings = append(item.Warnings, "no_eligible_proxy")
			} else {
				item.Warnings = append(item.Warnings, "exit_ip_capacity_exhausted")
				plan.Summary.OverLimit++
			}
			plan.Summary.Skip++
			plan.Summary.NoProxy++
			plan.Items = append(plan.Items, item)
			continue
		}

		newProxyID := selected.ID
		newExitIP := proxyExitIP(selected)
		item.NewProxyID = &newProxyID
		item.NewProxyName = selected.Name
		item.NewExitIP = newExitIP
		item.Reason = "unassigned"
		if account.ProxyID != nil {
			item.Action = "rebalance"
			item.Reason = "exit_ip_rebalance"
			plan.Summary.Rebalance++
		} else {
			item.Action = "assign"
			plan.Summary.Assign++
		}
		exitUsage[newExitIP]++
		plan.ChangeCount++
		plan.Items = append(plan.Items, item)
	}
	plan.AccountCount = len(plan.Items)
	plan.PlanID = proxyAssignmentPlanID(plan.Items)
	return plan, nil
}

func proxyAssignmentMaxAccountsPerExitIP(account *Account, override *int) int {
	if override != nil && *override > 0 {
		return *override
	}
	if account == nil {
		return 1
	}
	switch strings.ToLower(strings.TrimSpace(account.Type)) {
	case AccountTypeAPIKey, AccountTypeBedrock:
		return 3
	default:
		return 1
	}
}

func proxyEligibleForAssignment(proxy ProxyWithAccountCount, requireExitIP bool, minQualityScore int) bool {
	if proxy.Status != StatusActive {
		return false
	}
	if requireExitIP && proxyExitIP(proxy) == "" {
		return false
	}
	if strings.EqualFold(proxy.QualityStatus, "failed") {
		return false
	}
	if proxy.QualityScore != nil && *proxy.QualityScore < minQualityScore {
		return false
	}
	return true
}

func chooseProxyAssignmentCandidate(candidates []ProxyWithAccountCount, exitUsage map[string]int64, maxPerExitIP int, oldProxyID *int64) (ProxyWithAccountCount, bool) {
	if maxPerExitIP <= 0 {
		maxPerExitIP = 1
	}
	for _, candidate := range candidates {
		if oldProxyID != nil && candidate.ID == *oldProxyID {
			continue
		}
		exitIP := proxyExitIP(candidate)
		if exitIP == "" {
			continue
		}
		if exitUsage[exitIP] >= int64(maxPerExitIP) {
			continue
		}
		return candidate, true
	}
	return ProxyWithAccountCount{}, false
}

func sortProxyAssignmentCandidates(candidates []ProxyWithAccountCount, exitUsage map[string]int64) {
	sort.SliceStable(candidates, func(i, j int) bool {
		left, right := candidates[i], candidates[j]
		leftIP, rightIP := proxyExitIP(left), proxyExitIP(right)
		if exitUsage[leftIP] != exitUsage[rightIP] {
			return exitUsage[leftIP] < exitUsage[rightIP]
		}
		leftScore, rightScore := proxyQualityScoreValue(left), proxyQualityScoreValue(right)
		if leftScore != rightScore {
			return leftScore > rightScore
		}
		leftLatency, rightLatency := proxyLatencyValue(left), proxyLatencyValue(right)
		if leftLatency != rightLatency {
			return leftLatency < rightLatency
		}
		return left.ID < right.ID
	})
}

func proxyExitIP(proxy ProxyWithAccountCount) string {
	if strings.TrimSpace(proxy.IPAddress) != "" {
		return strings.TrimSpace(proxy.IPAddress)
	}
	return strings.TrimSpace(proxy.Proxy.IPAddress)
}

func proxyQualityScoreValue(proxy ProxyWithAccountCount) int {
	if proxy.QualityScore == nil {
		return 0
	}
	return *proxy.QualityScore
}

func proxyLatencyValue(proxy ProxyWithAccountCount) int64 {
	if proxy.LatencyMs == nil {
		return 1<<62 - 1
	}
	return *proxy.LatencyMs
}

func proxyQualityRank(status string) int {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "failed":
		return 4
	case "challenge":
		return 3
	case "warn":
		return 2
	case "healthy":
		return 1
	default:
		return 0
	}
}

func proxyAssignmentPlanID(items []ProxyAssignmentItem) string {
	payload, _ := json.Marshal(items)
	sum := sha256.Sum256(payload)
	return hex.EncodeToString(sum[:])[:16]
}

func cloneIntPtr(v *int) *int {
	if v == nil {
		return nil
	}
	out := *v
	return &out
}

func cloneFloat64Ptr(v *float64) *float64 {
	if v == nil {
		return nil
	}
	out := *v
	return &out
}

func cloneBoolPtr(v bool) *bool {
	out := v
	return &out
}

func timeToUnixSecondsPtr(v *time.Time) *int64 {
	if v == nil {
		return nil
	}
	out := v.Unix()
	return &out
}

func cloneAccountJSONMap(src map[string]any) map[string]any {
	if src == nil {
		return nil
	}
	raw, err := json.Marshal(src)
	if err != nil {
		out := make(map[string]any, len(src))
		for key, value := range src {
			out[key] = value
		}
		return out
	}
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		fallback := make(map[string]any, len(src))
		for key, value := range src {
			fallback[key] = value
		}
		return fallback
	}
	return out
}

func dedupeInt64s(in []int64) []int64 {
	if len(in) == 0 {
		return nil
	}
	out := make([]int64, 0, len(in))
	seen := make(map[int64]struct{}, len(in))
	for _, id := range in {
		if id <= 0 {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

func (s *adminServiceImpl) PreviewProxyAssignment(ctx context.Context, input *ProxyAssignmentInput) (*ProxyAssignmentPlan, error) {
	return s.buildProxyAssignmentPlan(ctx, input)
}

func (s *adminServiceImpl) ApplyProxyAssignment(ctx context.Context, input *ProxyAssignmentInput) (*ProxyAssignmentApplyResult, error) {
	plan, err := s.buildProxyAssignmentPlan(ctx, input)
	if err != nil {
		return nil, err
	}
	if input != nil && strings.TrimSpace(input.PlanID) != "" && strings.TrimSpace(input.PlanID) != plan.PlanID {
		return nil, infraerrors.Conflict("PROXY_ASSIGNMENT_PLAN_STALE", "proxy assignment plan is stale; preview again before applying")
	}
	result := &ProxyAssignmentApplyResult{
		Plan:       plan,
		SuccessIDs: make([]int64, 0),
		FailedIDs:  make([]int64, 0),
		Results:    make([]ProxyAssignmentApplyItem, 0, len(plan.Items)),
	}
	for _, item := range plan.Items {
		entry := ProxyAssignmentApplyItem{AccountID: item.AccountID, Action: item.Action}
		if item.Action != "assign" && item.Action != "rebalance" {
			entry.Success = true
			result.Results = append(result.Results, entry)
			continue
		}
		if item.NewProxyID == nil {
			entry.Error = "missing new proxy id"
			result.Failed++
			result.FailedIDs = append(result.FailedIDs, item.AccountID)
			result.Results = append(result.Results, entry)
			continue
		}
		proxyID := *item.NewProxyID
		if _, err := s.accountRepo.BulkUpdate(ctx, []int64{item.AccountID}, AccountBulkUpdate{ProxyID: &proxyID}); err != nil {
			entry.Error = err.Error()
			result.Failed++
			result.FailedIDs = append(result.FailedIDs, item.AccountID)
			result.Results = append(result.Results, entry)
			continue
		}
		entry.Success = true
		result.Success++
		result.SuccessIDs = append(result.SuccessIDs, item.AccountID)
		result.Results = append(result.Results, entry)
	}
	return result, nil
}

func (s *adminServiceImpl) persistProxyExitIP(ctx context.Context, proxyID int64, ipAddress string) {
	ipAddress = strings.TrimSpace(ipAddress)
	if ipAddress == "" || s.proxyRepo == nil {
		return
	}
	proxy, err := s.proxyRepo.GetByID(ctx, proxyID)
	if err != nil || proxy == nil {
		return
	}
	if strings.TrimSpace(proxy.IPAddress) == ipAddress {
		return
	}
	proxy.IPAddress = ipAddress
	if err := s.proxyRepo.Update(ctx, proxy); err != nil {
		logger.LegacyPrintf("service.admin", "Warning: persist proxy exit ip failed: proxy_id=%d err=%v", proxyID, err)
	}
}