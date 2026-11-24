package middlewares

import (
	"backend/pkg/utils/logger"
	"mime"
	"net/http"

	"github.com/gin-gonic/gin"
)

// Security 安全中间件，设置安全相关的 HTTP 响应头
func Security() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 防止点击劫持
		c.Header("X-Frame-Options", "DENY")

		// 防止 MIME 类型嗅探
		c.Header("X-Content-Type-Options", "nosniff")

		// XSS 保护
		c.Header("X-XSS-Protection", "1; mode=block")

		// 内容安全策略（根据实际情况调整）
		c.Header(
			"Content-Security-Policy",
			"default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';",
		)

		// 严格传输安全（仅限 HTTPS）
		// c.Header("Strict-Transport-Security", "max-age=63072000; includeSubDomains")

		// 引用策略
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")

		// 权限策略
		c.Header("Permissions-Policy", "geolocation=(), microphone=(), camera=()")

		logger.Debugf("[Security] 设置安全响应头")
		c.Next()
	}
}

// NoCache 禁用缓存中间件
func NoCache() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Cache-Control", "no-cache, no-store, max-age=0, must-revalidate")
		c.Header("Pragma", "no-cache")
		c.Header("Expires", "0")

		c.Next()
	}
}

// allowedMediaTypes 允许的请求体媒体类型。
//
// 历史实现做的是 `contentType != "application/json"` 的精确比较，
// 因此浏览器 fetch 默认带出的 `application/json; charset=utf-8`
// 被判为不支持而返回 415；multipart/form-data 也被挡在门外，
// 导致 /api/cookies/upload 完全不可用。
var allowedMediaTypes = map[string]struct{}{
	"application/json":                  {},
	"application/x-www-form-urlencoded": {},
	"multipart/form-data":               {},
	"text/plain":                        {},
	"application/octet-stream":          {},
}

// ContentType 内容类型检查中间件：解析媒体类型而非比较原始字符串。
func ContentType() gin.HandlerFunc {
	return func(c *gin.Context) {
		switch c.Request.Method {
		case http.MethodPost, http.MethodPut, http.MethodPatch:
		default:
			c.Next()
			return
		}

		raw := c.GetHeader("Content-Type")
		if raw == "" {
			// 无请求体的操作（如 POST 触发类接口）不应被拦
			c.Next()
			return
		}

		mediaType, _, err := mime.ParseMediaType(raw)
		if err != nil {
			logger.Warnf("[ContentType] 无法解析 Content-Type: %s", raw)
			c.JSON(http.StatusUnsupportedMediaType, gin.H{
				"success": false,
				"error":   "无法解析的 Content-Type",
			})
			c.Abort()
			return
		}

		if _, ok := allowedMediaTypes[mediaType]; !ok {
			logger.Warnf("[ContentType] 不支持的媒体类型: %s", mediaType)
			c.JSON(http.StatusUnsupportedMediaType, gin.H{
				"success": false,
				"error":   "不支持的媒体类型",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}
