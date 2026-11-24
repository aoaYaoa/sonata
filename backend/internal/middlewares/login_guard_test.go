package middlewares

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func TestLoginGuardLocksAfterMaxFailures(t *testing.T) {
	gin.SetMode(gin.TestMode)

	guard := NewLoginGuardWithConfig(3, time.Minute, time.Minute)
	r := gin.New()
	r.POST("/login", guard.Middleware(), func(c *gin.Context) {
		// 前两次返回失败，第三次成功，用于验证状态机
		if c.GetHeader("X-Ok") == "1" {
			c.Status(http.StatusOK)
			return
		}
		c.Status(http.StatusUnauthorized)
	})

	do := func(headers map[string]string) int {
		req := httptest.NewRequest(http.MethodPost, "/login", nil)
		req.RemoteAddr = "203.0.113.7:12345"
		for k, v := range headers {
			req.Header.Set(k, v)
		}
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		return w.Code
	}

	// 修复前：任意次数错误口令都只返回 401，无锁定
	for i := 0; i < 3; i++ {
		if code := do(nil); code != http.StatusUnauthorized {
			t.Fatalf("第 %d 次失败响应码 = %d, want 401", i+1, code)
		}
	}

	// 达到阈值后即使口令正确也应被拦（Limit 在 handler 之前执行）
	if code := do(map[string]string{"X-Ok": "1"}); code != http.StatusTooManyRequests {
		t.Fatalf("锁定后响应码 = %d, want 429", code)
	}
}

func TestLoginGuardSuccessResetsFailures(t *testing.T) {
	guard := NewLoginGuardWithConfig(2, time.Minute, time.Minute)

	now := time.Now()
	guard.now = func() time.Time { return now }

	guard.RecordFailure("198.51.100.1")
	guard.RecordSuccess("198.51.100.1")
	guard.RecordFailure("198.51.100.1")

	guard.mu.Lock()
	attempt := guard.attempts["198.51.100.1"]
	locked := attempt != nil && !attempt.lockedUntil.IsZero()
	guard.mu.Unlock()

	if locked {
		t.Fatal("成功登录后应清空失败计数，不应触发锁定")
	}
}

func TestLoginGuardLockExpires(t *testing.T) {
	guard := NewLoginGuardWithConfig(1, time.Minute, time.Minute)

	now := time.Now()
	guard.now = func() time.Time { return now }

	guard.RecordFailure("192.0.2.5")

	guard.mu.Lock()
	lockedImmediately := guard.now().Before(guard.attempts["192.0.2.5"].lockedUntil)
	guard.mu.Unlock()
	if !lockedImmediately {
		t.Fatal("达到阈值后应立即锁定")
	}

	now = now.Add(2 * time.Minute)

	guard.mu.Lock()
	stillLocked := guard.now().Before(guard.attempts["192.0.2.5"].lockedUntil)
	guard.mu.Unlock()
	if stillLocked {
		t.Fatal("锁定应在到期后自动解除")
	}
}

func TestFormatRetryAfter(t *testing.T) {
	if got := formatRetryAfter(90 * time.Second); got != "90" {
		t.Fatalf("formatRetryAfter(90s) = %q, want \"90\"", got)
	}
	if got := formatRetryAfter(time.Millisecond); got != "1" {
		t.Fatalf("formatRetryAfter(1ms) = %q, want \"1\"", got)
	}
}

func TestContentTypeAcceptsJSONWithCharset(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(ContentType())
	r.POST("/x", func(c *gin.Context) { c.Status(http.StatusOK) })

	cases := []struct {
		contentType string
		want        int
	}{
		{"application/json", http.StatusOK},
		// 修复前：浏览器 fetch 默认值会被判为 415
		{"application/json; charset=utf-8", http.StatusOK},
		{"application/json;charset=UTF-8", http.StatusOK},
		// /api/cookies/upload 依赖 multipart
		{"multipart/form-data; boundary=----x", http.StatusOK},
		{"application/x-www-form-urlencoded", http.StatusOK},
		{"application/xml", http.StatusUnsupportedMediaType},
		{"text/html", http.StatusUnsupportedMediaType},
		{"不合法值;;;", http.StatusUnsupportedMediaType},
	}

	for _, tc := range cases {
		req := httptest.NewRequest(http.MethodPost, "/x", nil)
		req.Header.Set("Content-Type", tc.contentType)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if w.Code != tc.want {
			t.Fatalf("Content-Type %q => %d, want %d", tc.contentType, w.Code, tc.want)
		}
	}
}

func TestRequireToken(t *testing.T) {
	gin.SetMode(gin.TestMode)

	build := func(token string, allowWhenEmpty bool) *gin.Engine {
		r := gin.New()
		r.GET("/metrics", RequireToken(token, allowWhenEmpty), func(c *gin.Context) {
			c.String(http.StatusOK, "ok")
		})
		return r
	}

	do := func(r *gin.Engine, query, header string) int {
		req := httptest.NewRequest(http.MethodGet, "/metrics"+query, nil)
		if header != "" {
			req.Header.Set("Authorization", header)
		}
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		return w.Code
	}

	// 未配置令牌 + 生产模式 => 404（隐藏端点）
	if code := do(build("", false), "", ""); code != http.StatusNotFound {
		t.Fatalf("未配置令牌且生产模式 => %d, want 404", code)
	}
	// 未配置令牌 + 调试模式 => 放行
	if code := do(build("", true), "", ""); code != http.StatusOK {
		t.Fatalf("未配置令牌且调试模式 => %d, want 200", code)
	}
	// 已配置令牌
	secured := build("s3cr3t", false)
	if code := do(secured, "", ""); code != http.StatusUnauthorized {
		t.Fatalf("无令牌 => %d, want 401", code)
	}
	if code := do(secured, "", "Bearer wrong"); code != http.StatusUnauthorized {
		t.Fatalf("错误令牌 => %d, want 401", code)
	}
	if code := do(secured, "", "Bearer s3cr3t"); code != http.StatusOK {
		t.Fatalf("正确令牌 => %d, want 200", code)
	}
	if code := do(secured, "?token=s3cr3t", ""); code != http.StatusOK {
		t.Fatalf("query 令牌 => %d, want 200", code)
	}
}
