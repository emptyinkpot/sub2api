//go:build unit

package service

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
)

type accountRepoStubForCreateAccount struct {
	accountRepoStub
	createCalled bool
}

func (s *accountRepoStubForCreateAccount) Create(_ context.Context, account *Account) error {
	s.createCalled = true
	account.ID = 99
	return nil
}

func (s *accountRepoStubForCreateAccount) BindGroups(_ context.Context, _ int64, _ []int64) error {
	return nil
}

func TestAdminServiceCreateAccountRejectsAPIKeyOAuthOnlyGroupBeforeCreate(t *testing.T) {
	accountRepo := &accountRepoStubForCreateAccount{}
	groupRepo := &groupRepoStubForAdmin{
		getByID: &Group{
			ID:               12,
			Name:             "oauth-only-openai",
			Platform:         PlatformOpenAI,
			RequireOAuthOnly: true,
		},
	}
	svc := &adminServiceImpl{
		accountRepo: accountRepo,
		groupRepo:   groupRepo,
	}

	created, err := svc.CreateAccount(context.Background(), &CreateAccountInput{
		Name:        "bad-apikey",
		Platform:    PlatformOpenAI,
		Type:        AccountTypeAPIKey,
		Credentials: map[string]any{"api_key": "sk-test"},
		GroupIDs:    []int64{12},
	})

	require.Nil(t, created)
	require.Error(t, err)
	require.Contains(t, err.Error(), "仅允许 OAuth 账号")
	require.False(t, accountRepo.createCalled, "oauth-only group rejection must happen before account persistence")
}
