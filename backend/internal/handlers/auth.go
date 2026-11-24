package handlers

import (
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"backend/internal/config"
	"backend/pkg/utils/jwt"
	"backend/pkg/utils/logger"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

const (
	maxAgeSec    = 48 * 60 * 60
	musicAPIBase = "https://music-api.gdstudio.xyz/api.php"

	// maxCookieFileSize 单个 cookie 文件上限，防止 io.ReadAll 打满内存/磁盘
	maxCookieFileSize = 1 << 20 // 1 MiB

	// maxImgProxyResponse 图片代理响应上限
	maxImgProxyResponse = 10 << 20 // 10 MiB

	// maxStorageValueLen 单个 storage 值上限
	maxStorageValueLen = 1 << 20 // 1 MiB

	// maxStorageKeys 单次 storage 请求的键数量上限
	maxStorageKeys = 64

	// loginMaxFailures 单 IP 登录失败阈值（配合 loginGuard 使用）
	loginMaxFailures  = 5
	loginLockDuration = 15 * time.Minute
)

// youtubeVideoIDPattern YouTube 视频 ID 定长 11，只含 URL-safe base64 字符。
// 用它做输入白名单，从根上掐掉命令注入。
var youtubeVideoIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{11}$`)

// bilibiliBVIDPattern B 站 BV 号：BV + 10 位 base58。
var bilibiliBVIDPattern = regexp.MustCompile(`^BV[0-9A-Za-z]{10}$`)

// errInvalidVideoID 表示调用方传入的 videoId 不合法（应回 400 而不是 502）。
var errInvalidVideoID = errors.New("invalid video id")

var favoriteKeys = map[string]bool{
	"favoriteSongs":        true,
	"currentFavoriteIndex": true,
	"favoritePlayMode":     true,
	"favoritePlaybackTime": true,
}

type SolaraHandler struct {
	db *gorm.DB
}

func NewSolaraHandler(db *gorm.DB) *SolaraHandler {
	return &SolaraHandler{db: db}
}

func (h *SolaraHandler) Login(c *gin.Context) {
	var body struct {
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		body.Password = ""
	}

	password := config.AppConfig.AppPassword
	if password == "" {
		// 正常路径下 config.Validate() 已在启动阶段拒绝空口令；
		// 这里再次 fail-closed，避免配置热加载或测试环境绕过。
		logger.Errorf("[Login] APP_PASSWORD 未配置，拒绝所有登录")
		c.JSON(http.StatusServiceUnavailable, gin.H{"success": false, "error": "服务未正确配置"})
		return
	}

	// 定长比较，避免通过响应时间侧信道逐字节猜测口令
	if subtle.ConstantTimeCompare([]byte(body.Password), []byte(password)) != 1 {
		logger.Warnf("[Login] 口令校验失败 ip=%s", c.ClientIP())
		c.JSON(http.StatusUnauthorized, gin.H{"success": false})
		return
	}

	cookieVal := base64.StdEncoding.EncodeToString([]byte(password))
	secure := c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https"
	sameSite := "SameSite=Lax"
	parts := []string{
		fmt.Sprintf("auth=%s", cookieVal),
		fmt.Sprintf("Max-Age=%d", maxAgeSec),
		"Path=/",
		sameSite,
		"HttpOnly",
	}
	if secure {
		parts = append(parts, "Secure")
	}
	c.Header("Set-Cookie", strings.Join(parts, "; "))

	// 同时返回 JWT token 供移动端/Flutter使用
	token, err := jwt.GenerateToken("app_user", "app_user", "app", "", 48*time.Hour)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"success": true})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "data": gin.H{"token": token}})
}

func (h *SolaraHandler) isAuthed(c *gin.Context) bool {
	authorization := c.GetHeader("Authorization")
	if strings.HasPrefix(authorization, "Bearer ") {
		token := strings.TrimPrefix(authorization, "Bearer ")
		if _, err := jwt.ValidateToken(token, ""); err == nil {
			return true
		}
	}
	// JWT 通道不通过时回落到 Cookie 通道。
	// 注意：口令未配置时一律判定未认证（fail-closed），
	// 历史实现在这里 return true，导致漏配 APP_PASSWORD 时接口完全开放。
	password := config.AppConfig.AppPassword
	if password == "" {
		return false
	}
	cookie, err := c.Cookie("auth")
	if err != nil {
		return false
	}
	expected := base64.StdEncoding.EncodeToString([]byte(password))
	return subtle.ConstantTimeCompare([]byte(cookie), []byte(expected)) == 1
}
