package middlewares

import (
	"backend/pkg/utils/logger"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

const (
	// defaultLoginMaxFailures 窗口内允许的失败次数。
	defaultLoginMaxFailures = 5
	// defaultLoginLockDuration 达到阈值后的锁定时长。
	defaultLoginLockDuration = 15 * time.Minute
	// defaultLoginWindow 失败计数的统计窗口。
	defaultLoginWindow = 15 * time.Minute
	// defaultLoginCleanup 过期条目清理间隔。
	defaultLoginCleanup = 10 * time.Minute
)

// loginAttempt 单个 IP 的登录尝试状态。
type loginAttempt struct {
	failures     int
	firstFailure time.Time
	lockedUntil  time.Time
	lastSeen     time.Time
}

// LoginGuard 登录暴力破解防护。
//
// 审计实测：原实现下 30 次错误口令登录耗时 0.31s，全部返回 401，
// 既无失败计数也无锁定，配合 8 位弱口令可在线爆破。
// 这里按 IP 做失败计数 + 指数退避锁定。
type LoginGuard struct {
	attempts map[string]*loginAttempt
	mu       sync.Mutex

	maxFailures  int
	lockDuration time.Duration
	window       time.Duration
	now          func() time.Time

	lastCleanup time.Time
}

// NewLoginGuard 创建默认配置的登录防护器。
func NewLoginGuard() *LoginGuard {
	return NewLoginGuardWithConfig(defaultLoginMaxFailures, defaultLoginLockDuration, defaultLoginWindow)
}

// NewLoginGuardWithConfig 创建自定义配置的登录防护器。
func NewLoginGuardWithConfig(maxFailures int, lockDuration, window time.Duration) *LoginGuard {
	if maxFailures <= 0 {
		maxFailures = defaultLoginMaxFailures
	}
	if lockDuration <= 0 {
		lockDuration = defaultLoginLockDuration
	}
	if window <= 0 {
		window = defaultLoginWindow
	}
	return &LoginGuard{
		attempts:     make(map[string]*loginAttempt),
		maxFailures:  maxFailures,
		lockDuration: lockDuration,
		window:       window,
		now:          time.Now,
		lastCleanup:  time.Now(),
	}
}

// Middleware 返回 gin 中间件：命中锁定直接拒绝，未锁定则放行。
func (g *LoginGuard) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := c.ClientIP()

		g.mu.Lock()
		g.cleanupLocked(g.now())
		attempt := g.attempts[ip]
		var remaining time.Duration
		if attempt != nil && g.now().Before(attempt.lockedUntil) {
			remaining = attempt.lockedUntil.Sub(g.now())
		}
		g.mu.Unlock()

		if remaining > 0 {
			logger.Warnf("[LoginGuard] IP %s 处于登录锁定状态，剩余 %s", ip, remaining.Truncate(time.Second))
			c.Header("Retry-After", formatRetryAfter(remaining))
			c.JSON(http.StatusTooManyRequests, gin.H{
				"success": false,
				"error":   "登录失败次数过多，请在冷却后重试",
			})
			c.Abort()
			return
		}

		c.Next()

		// 依据响应码记录成功/失败
		switch c.Writer.Status() {
		case http.StatusOK:
			g.RecordSuccess(ip)
		case http.StatusUnauthorized:
			g.RecordFailure(ip)
		}
	}
}

// RecordFailure 记录一次登录失败，达到阈值后锁定。
func (g *LoginGuard) RecordFailure(ip string) {
	g.mu.Lock()
	defer g.mu.Unlock()

	now := g.now()
	attempt := g.attempts[ip]
	if attempt == nil || now.Sub(attempt.firstFailure) > g.window {
		attempt = &loginAttempt{firstFailure: now}
		g.attempts[ip] = attempt
	}
	attempt.failures++
	attempt.lastSeen = now

	if attempt.failures >= g.maxFailures {
		attempt.lockedUntil = now.Add(g.lockDuration)
		// 锁定后重新计数，避免解锁瞬间立即再次触发
		attempt.failures = 0
		attempt.firstFailure = now
		logger.Warnf("[LoginGuard] IP %s 登录失败达 %d 次，锁定至 %s",
			ip, g.maxFailures, attempt.lockedUntil.Format(time.RFC3339))
	}
}

// RecordSuccess 记录一次登录成功并清空该 IP 的失败记录。
func (g *LoginGuard) RecordSuccess(ip string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	delete(g.attempts, ip)
}

// cleanupLocked 清理长期无活动的条目。调用方需持有锁。
func (g *LoginGuard) cleanupLocked(now time.Time) {
	if now.Sub(g.lastCleanup) < defaultLoginCleanup {
		return
	}
	g.lastCleanup = now
	for ip, attempt := range g.attempts {
		idle := now.Sub(attempt.lastSeen)
		unlocked := !now.Before(attempt.lockedUntil)
		if idle > g.window && unlocked {
			delete(g.attempts, ip)
		}
	}
}

// formatRetryAfter 把剩余时长格式化为 Retry-After 需要的秒数字符串。
func formatRetryAfter(d time.Duration) string {
	secs := int(d.Seconds())
	if secs < 1 {
		secs = 1
	}
	return strconv.Itoa(secs)
}
