package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"backend/internal/config"
	"backend/pkg/utils/logger"
	"github.com/gin-gonic/gin"
)

func (h *SolaraHandler) Proxy(c *gin.Context) {
	targetParam := c.Query("url")
	if targetParam != "" {
		// 媒体流代理：allowlist 已限制域名，无需 auth
		h.proxyKuwoAudio(c, targetParam)
		return
	}

	if !h.isAuthed(c) {
		c.Status(http.StatusUnauthorized)
		return
	}

	source := c.Query("source")
	types := c.Query("types")

	switch source {
	case "bilibili":
		switch types {
		case "search":
			page := 1
			count := 20
			fmt.Sscanf(c.DefaultQuery("pages", "1"), "%d", &page)
			fmt.Sscanf(c.DefaultQuery("count", "20"), "%d", &count)
			results, err := h.BilibiliSearch(c.Query("name"), page, count)
			if err != nil {
				// B站风控降级：返回空列表而非502
				c.JSON(http.StatusOK, []interface{}{})
				return
			}
			c.JSON(http.StatusOK, results)
		case "url":
			bvid := c.Query("id")
			audioURL, err := h.BilibiliPlayUrl(bvid)
			if err != nil {
				c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
				return
			}
			// 返回JSON让前端直接播放（B站音频URL含鉴权参数，前端用时效性URL即可）
			writeJSON(c, http.StatusOK, gin.H{"url": audioURL})
		case "mv":
			bvid := c.Query("id")
			// MV 需要视频流，不是音频流
			videoURL, err := h.BilibiliVideoUrl(bvid)
			if err != nil {
				c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
				return
			}
			writeJSON(c, http.StatusOK, gin.H{"url": videoURL})
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported types for bilibili"})
		}
	case "youtube":
		switch types {
		case "search":
			count := 20
			fmt.Sscanf(c.DefaultQuery("count", "20"), "%d", &count)
			results, err := youtubeSearch(c.Query("name"), count)
			if err != nil {
				c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusOK, results)
		case "url":
			videoId := c.Query("id")
			audioURL, err := youtubeGetAudioUrl(videoId)
			if err != nil {
				c.JSON(statusForSourceError(err), gin.H{"error": err.Error()})
				return
			}
			writeJSON(c, http.StatusOK, gin.H{"url": audioURL})
		case "mv":
			videoId := c.Query("id")
			videoURL, err := youtubeGetVideoUrl(videoId)
			if err != nil {
				c.JSON(statusForSourceError(err), gin.H{"error": err.Error()})
				return
			}
			writeJSON(c, http.StatusOK, gin.H{"url": videoURL})
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported types for youtube"})
		}
	case "jamendo":
		switch types {
		case "search":
			count := 20
			fmt.Sscanf(c.DefaultQuery("count", "20"), "%d", &count)
			results, err := jamendoSearch(c.Query("name"), count)
			if err != nil {
				c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
				return
			}
			c.JSON(http.StatusOK, results)
		case "url":
			// Jamendo url_id 直接是音频URL，前端直接播放，此处仅透传
			audioURL := c.Query("id")
			if strings.HasPrefix(audioURL, "http") {
				c.JSON(http.StatusOK, gin.H{"url": audioURL})
			} else {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid jamendo url_id"})
			}
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported types for jamendo"})
		}
	default:
		// 国内四源：透传到 music-api，需将内部 source 名映射到上游 API 名
		sourceRemap := map[string]string{
			"tencent": "qq",
		}
		params := c.Request.URL.Query()
		params.Del("url")
		if remapped, ok := sourceRemap[params.Get("source")]; ok {
			params.Set("source", remapped)
		}
		targetURL := musicAPIBase + "?" + params.Encode()
		h.proxyRequest(c, targetURL, nil)
	}
}

// ImgProxy 代理网易云图片，加上 Referer 头绕过防盗链。
//
// 安全约束（历史实现三项全无，构成无鉴权 SSRF）：
//  1. 只允许白名单域名（默认网易云图床），拒绝任意主机；
//  2. 解析结果不得为内网/回环/链路本地地址，挡住 127.0.0.1、169.254.169.254；
//  3. 响应体限制 10 MiB，且只回显 image/* 内容类型。

func (h *SolaraHandler) ImgProxy(c *gin.Context) {
	targetURL := c.Query("url")
	if targetURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing url"})
		return
	}

	parsed, err := validateProxyTarget(c.Request.Context(), targetURL, config.AppConfig.ImgProxyAllowedHosts)
	if err != nil {
		logger.Warnf("[ImgProxy] 拒绝代理请求 url=%s: %v", truncateForLog(targetURL), err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "目标地址不受支持"})
		return
	}

	client := newGuardedHTTPClient(10 * time.Second)
	req, err := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, parsed.String(), nil)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid url"})
		return
	}
	req.Header.Set("Referer", "https://music.163.com/")
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "upstream request failed"})
		return
	}
	defer resp.Body.Close()

	contentType := resp.Header.Get("Content-Type")
	if !strings.HasPrefix(strings.ToLower(contentType), "image/") {
		c.JSON(http.StatusBadGateway, gin.H{"error": "upstream did not return an image"})
		return
	}
	if resp.ContentLength > maxImgProxyResponse {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "image too large"})
		return
	}

	c.Header("Content-Type", contentType)
	c.Header("Cache-Control", "public, max-age=86400")
	c.Header("Access-Control-Allow-Origin", "*")
	c.Status(resp.StatusCode)
	io.Copy(c.Writer, io.LimitReader(resp.Body, maxImgProxyResponse)) //nolint:errcheck
}

// storageKeyPattern 限制 storage 键的字符集。

// statusForSourceError 把「调用方输入非法」和「上游失败」区分开：
// 前者 400，后者 502。历史实现一律 502，会把客户端错误误导成上游故障。
func statusForSourceError(err error) int {
	if errors.Is(err, errInvalidVideoID) {
		return http.StatusBadRequest
	}
	return http.StatusBadGateway
}

func writeJSON(c *gin.Context, status int, v interface{}) {
	c.Status(status)
	c.Header("Content-Type", "application/json; charset=utf-8")
	enc := json.NewEncoder(c.Writer)
	enc.SetEscapeHTML(false)
	enc.Encode(v) //nolint:errcheck
}

// neteaseGetSongUrl 获取网易云歌曲播放URL

func (h *SolaraHandler) proxyKuwoAudio(c *gin.Context, targetURL string) {
	allowlist := config.AppConfig.MediaProxyAllowedHosts
	parsed, err := validateProxyTarget(c.Request.Context(), targetURL, allowlist)
	if err != nil {
		logger.Warnf("[Proxy] 拒绝媒体代理 url=%s: %v", truncateForLog(targetURL), err)
		c.JSON(http.StatusForbidden, gin.H{"error": "target host not allowed"})
		return
	}

	host := strings.ToLower(parsed.Hostname())
	var referer string
	switch {
	case hostInAllowlist(host, []string{"kuwo.cn", ".kuwo.cn"}):
		parsed.Scheme = "http"
		referer = "https://www.kuwo.cn/"
	case hostInAllowlist(host, []string{".bilivideo.com", ".bilivideo.cn", ".bilibili.com", ".akamaized.net"}):
		referer = "https://www.bilibili.com/"
	case hostInAllowlist(host, []string{".googlevideo.com"}):
		referer = "https://www.youtube.com/"
	default:
		c.JSON(http.StatusForbidden, gin.H{"error": "target host not allowed"})
		return
	}
	extraHeaders := map[string]string{
		"Referer":    referer,
		"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
	}
	h.proxyRequest(c, parsed.String(), extraHeaders)
}

func (h *SolaraHandler) proxyRequest(c *gin.Context, targetURL string, extraHeaders map[string]string) {
	req, err := http.NewRequestWithContext(c.Request.Context(), c.Request.Method, targetURL, nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create request"})
		return
	}
	req.Header.Set("User-Agent", c.GetHeader("User-Agent"))
	if rangeH := c.GetHeader("Range"); rangeH != "" {
		req.Header.Set("Range", rangeH)
	}
	for k, v := range extraHeaders {
		req.Header.Set(k, v)
	}

	// 流媒体代理只设置连接超时，不设整体超时（否则大文件传输会被截断）；
	// 但保留拨号前的内网地址校验（timeout=0 表示禁用整体超时）。
	client := newGuardedHTTPClient(0)
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "upstream request failed"})
		return
	}
	defer resp.Body.Close()

	safeHeaders := []string{"Content-Type", "Cache-Control", "Accept-Ranges", "Content-Length", "Content-Range", "ETag", "Last-Modified", "Expires"}
	for _, h := range safeHeaders {
		if v := resp.Header.Get(h); v != "" {
			c.Header(h, v)
		}
	}
	c.Header("Access-Control-Allow-Origin", "*")
	c.Status(resp.StatusCode)
	io.Copy(c.Writer, resp.Body)
}

// jsonIDToString 将 JSON 解析出的数字 ID 转为整数字符串，避免 float64 精度损失
