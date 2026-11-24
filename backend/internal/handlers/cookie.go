package handlers

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"backend/internal/config"
	"github.com/gin-gonic/gin"
)

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// cookiePath 返回 cookie 文件落盘路径。
// 历史实现硬编码 /app/*.txt，本地运行与非容器部署直接失效（P1-6）。

func cookiePath(filename string) string {
	dir := config.AppConfig.CookieDir
	if strings.TrimSpace(dir) == "" {
		dir = "./data"
	}
	return filepath.Join(dir, filename)
}

func ytCookieFilePath() string { return cookiePath("yt_cookies.txt") }

func bilibiliCookieFilePath() string { return cookiePath("bilibili_cookies.txt") }

func (h *SolaraHandler) UploadCookie(c *gin.Context) {
	if !h.isAuthed(c) {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false})
		return
	}
	cookieType := c.Query("type")
	if cookieType != "youtube" && cookieType != "bilibili" {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "type must be youtube or bilibili"})
		return
	}

	// 限制请求体大小，避免无上限 io.ReadAll 打满内存（P1-6）。
	// multipart 有边界与头开销，给 1 MiB 数据留出余量。
	const multipartOverhead = 64 << 10
	if c.Request.ContentLength > maxCookieFileSize+multipartOverhead {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{
			"success": false,
			"error":   fmt.Sprintf("cookie 文件超过 %d 字节上限", maxCookieFileSize),
		})
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxCookieFileSize+multipartOverhead)

	file, _, err := c.Request.FormFile("file")
	if err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			c.JSON(http.StatusRequestEntityTooLarge, gin.H{
				"success": false,
				"error":   fmt.Sprintf("cookie 文件超过 %d 字节上限", maxCookieFileSize),
			})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "missing file"})
		return
	}
	defer file.Close()

	data, err := io.ReadAll(io.LimitReader(file, maxCookieFileSize+1))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "读取上传文件失败"})
		return
	}
	if len(data) > maxCookieFileSize {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{
			"success": false,
			"error":   fmt.Sprintf("cookie 文件超过 %d 字节上限", maxCookieFileSize),
		})
		return
	}
	// Netscape cookie 文件是纯文本；出现 NUL 字节说明不是 cookie 文件
	if bytes.IndexByte(data, 0) >= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"success": false, "error": "文件不是合法的 Netscape cookie 文本"})
		return
	}

	destPath := ytCookieFilePath()
	if cookieType == "bilibili" {
		destPath = bilibiliCookieFilePath()
	}

	if err := os.MkdirAll(filepath.Dir(destPath), 0o700); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "无法创建 cookie 目录"})
		return
	}
	// cookie 等同凭据，权限必须收紧到 0600（历史为 0644）
	if err := os.WriteFile(destPath, data, 0o600); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": "写入 cookie 文件失败"})
		return
	}

	// 解析过期时间
	expiry := parseCookieExpiry(data)
	c.JSON(http.StatusOK, gin.H{"success": true, "expiry": expiry})
}

// CookieStatus 查询 cookie 状态
// GET /api/cookies/status

func (h *SolaraHandler) CookieStatus(c *gin.Context) {
	if !h.isAuthed(c) {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"youtube":  cookieFileStatus(ytCookieFilePath()),
		"bilibili": cookieFileStatus(bilibiliCookieFilePath()),
	})
}

// cookieFileStatus 返回 cookie 文件状态

func cookieFileStatus(path string) map[string]interface{} {
	data, err := os.ReadFile(path)
	if err != nil {
		return map[string]interface{}{"exists": false}
	}
	expiry := parseCookieExpiry(data)
	info := map[string]interface{}{"exists": true, "expiry": expiry}
	return info
}

// parseCookieExpiry 从 Netscape cookie 文件中提取最早过期时间（Unix 时间戳）
// 格式：domain	flag	path	secure	expiry	name	value

func parseCookieExpiry(data []byte) int64 {
	lines := strings.Split(string(data), "\n")
	var earliest int64 = 0
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Split(line, "\t")
		if len(parts) < 7 {
			continue
		}
		var ts int64
		fmt.Sscanf(parts[4], "%d", &ts)
		if ts <= 0 {
			continue
		}
		if earliest == 0 || ts < earliest {
			earliest = ts
		}
	}
	return earliest
}
