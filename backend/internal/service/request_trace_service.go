package service

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/pkg/logger"
	"github.com/redis/go-redis/v9"
)

const (
	traceRedisKey       = "trace:recent"
	traceRedisMaxLen    = 10000
	traceBatchSize      = 100
	traceFlushInterval  = 1 * time.Second
	traceChannelBuffer  = 4096
	traceRedisTimeout   = 500 * time.Millisecond
)

// RequestTraceService collects request traces asynchronously.
// It writes to Redis (ring buffer for realtime queries) and Postgres (batch archive).
type RequestTraceService struct {
	repo        RequestTraceRepository
	redisClient *redis.Client

	traceCh   chan *RequestTrace
	stopCh    chan struct{}
	startOnce sync.Once
	stopOnce  sync.Once
}

func NewRequestTraceService(repo RequestTraceRepository, redisClient *redis.Client) *RequestTraceService {
	return &RequestTraceService{
		repo:        repo,
		redisClient: redisClient,
		traceCh:     make(chan *RequestTrace, traceChannelBuffer),
		stopCh:      make(chan struct{}),
	}
}

// Start launches the background batch writer goroutine.
func (s *RequestTraceService) Start() {
	s.startOnce.Do(func() {
		go s.batchWriter()
	})
}

// Stop gracefully shuts down the batch writer.
func (s *RequestTraceService) Stop() {
	s.stopOnce.Do(func() {
		close(s.stopCh)
	})
}

// Record enqueues a trace for async persistence. Non-blocking; drops if buffer full.
func (s *RequestTraceService) Record(trace *RequestTrace) {
	if trace == nil {
		return
	}
	if trace.CreatedAt.IsZero() {
		trace.CreatedAt = time.Now()
	}
	select {
	case s.traceCh <- trace:
	default:
		// Channel full — drop trace rather than block the request path.
	}
}

// ListRecentFromRedis returns the most recent traces from Redis ring buffer.
func (s *RequestTraceService) ListRecentFromRedis(ctx context.Context, offset, count int64) ([]*RequestTrace, error) {
	vals, err := s.redisClient.LRange(ctx, traceRedisKey, offset, offset+count-1).Result()
	if err != nil {
		return nil, err
	}
	traces := make([]*RequestTrace, 0, len(vals))
	for _, v := range vals {
		var t RequestTrace
		if err := json.Unmarshal([]byte(v), &t); err != nil {
			continue
		}
		traces = append(traces, &t)
	}
	return traces, nil
}

// ListTraces queries Postgres via the repository.
func (s *RequestTraceService) ListTraces(ctx context.Context, filter *RequestTraceFilter) ([]*RequestTrace, int64, error) {
	return s.repo.ListTraces(ctx, filter)
}

// batchWriter consumes traces from the channel and flushes them in batches.
// It writes to Redis immediately (ring buffer) and Postgres in batches.
func (s *RequestTraceService) batchWriter() {
	ticker := time.NewTicker(traceFlushInterval)
	defer ticker.Stop()

	buf := make([]*RequestTrace, 0, traceBatchSize)

	flush := func() {
		if len(buf) == 0 {
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		if _, err := s.repo.BatchInsertTraces(ctx, buf); err != nil {
			logger.LegacyPrintf("service.request_trace", "batch insert failed: count=%d err=%v", len(buf), err)
		}
		cancel()
		buf = buf[:0]
	}

	for {
		select {
		case <-s.stopCh:
			// Drain remaining traces from channel before exit.
			for {
				select {
				case t := <-s.traceCh:
					s.pushRedis(t)
					buf = append(buf, t)
					if len(buf) >= traceBatchSize {
						flush()
					}
				default:
					flush()
					return
				}
			}
		case t := <-s.traceCh:
			s.pushRedis(t)
			buf = append(buf, t)
			if len(buf) >= traceBatchSize {
				flush()
			}
		case <-ticker.C:
			flush()
		}
	}
}

// pushRedis writes a single trace to the Redis ring buffer (LPUSH + LTRIM).
// Failures here are logged but never block the pipeline.
func (s *RequestTraceService) pushRedis(t *RequestTrace) {
	if s.redisClient == nil || t == nil {
		return
	}
	payload, err := json.Marshal(t)
	if err != nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), traceRedisTimeout)
	defer cancel()

	pipe := s.redisClient.Pipeline()
	pipe.LPush(ctx, traceRedisKey, payload)
	pipe.LTrim(ctx, traceRedisKey, 0, traceRedisMaxLen-1)
	if _, err := pipe.Exec(ctx); err != nil {
		logger.LegacyPrintf("service.request_trace", "redis push failed: request_id=%s err=%v", t.RequestID, err)
	}
}

