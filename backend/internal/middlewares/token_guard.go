package middlewares

import (
	"backend/pkg/utils/logger"
	"crypto/subtle"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// RequireToken 用共享令牌保护运维端点（/metrics、/swagger）。
//
// 审计实测这两个端点在生产配置下均返回 200：/metrics 泄露了包含
// /api/admin/users 在内的全部路由指标，/swagger/index.html 泄露完整接口清单。
//
// 行为：
//   - token 为空且 allowWhenEmpty=true（非 release 模式）：放行，便于本地调试；
//   - token 为空且 allowWhenEmpty=false：返回 404，隐藏端点存在性；
//   - token 非空：校验 Authorization: Bearer 或 ?token=，失败返回 401。
func RequireToken(token string, allowWhenEmpty bool) gin.HandlerFunc {
	token = strings.TrimSpace(token)

	return func(c *gin.Context) {
		if token == "" {
			if allowWhenEmpty {
				c.Next()
				return
			}
			logger.Warnf("[TokenGuard] 未配置访问令牌，拒绝暴露运维端点 %s", c.FullPath())
			c.AbortWithStatus(http.StatusNotFound)
			return
		}

		provided := ""
		if auth := c.GetHeader("Authorization"); strings.HasPrefix(auth, "Bearer ") {
			provided = strings.TrimSpace(strings.TrimPrefix(auth, "Bearer "))
		}
		if provided == "" {
			provided = c.Query("token")
		}

		if subtle.ConstantTimeCompare([]byte(provided), []byte(token)) != 1 {
			logger.Warnf("[TokenGuard] 运维端点访问令牌无效 ip=%s path=%s", c.ClientIP(), c.FullPath())
			c.Header("WWW-Authenticate", `Bearer realm="ops"`)
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		c.Next()
	}
}
