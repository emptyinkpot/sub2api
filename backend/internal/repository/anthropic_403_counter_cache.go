package repository

import (
	"context"
	"fmt"

	"github.com/Wei-Shaw/sub2api/internal/service"
	"github.com/redis/go-redis/v9"
)

const anthropic403CounterPrefix = "anthropic_403_count:account:"

var anthropic403CounterIncrScript = redis.NewScript(`
	local key = KEYS[1]
	local ttl = tonumber(ARGV[1])

	local count = redis.call('INCR', key)
	if count == 1 then
		redis.call('EXPIRE', key, ttl)
	end

	return count
`)

type anthropic403CounterCache struct {
	rdb *redis.Client
}

func NewAnthropic403CounterCache(rdb *redis.Client) service.Anthropic403CounterCache {
	return &anthropic403CounterCache{rdb: rdb}
}

func (c *anthropic403CounterCache) IncrementAnthropic403Count(ctx context.Context, accountID int64, windowMinutes int) (int64, error) {
	key := fmt.Sprintf("%s%d", anthropic403CounterPrefix, accountID)

	ttlSeconds := windowMinutes * 60
	if ttlSeconds < 60 {
		ttlSeconds = 60
	}

	result, err := anthropic403CounterIncrScript.Run(ctx, c.rdb, []string{key}, ttlSeconds).Int64()
	if err != nil {
		return 0, fmt.Errorf("increment anthropic 403 count: %w", err)
	}
	return result, nil
}

func (c *anthropic403CounterCache) ResetAnthropic403Count(ctx context.Context, accountID int64) error {
	key := fmt.Sprintf("%s%d", anthropic403CounterPrefix, accountID)
	return c.rdb.Del(ctx, key).Err()
}
