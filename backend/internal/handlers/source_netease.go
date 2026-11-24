package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *SolaraHandler) neteaseGetSongUrl(c *gin.Context) {
	id := c.Query("id")
	br := c.DefaultQuery("br", "320000")
	// br 参数：前端传 "128"/"320"/"flac"，网易云需要 bit rate 数字
	brMap := map[string]string{
		"128":  "128000",
		"320":  "320000",
		"flac": "999000",
	}
	if mapped, ok := brMap[br]; ok {
		br = mapped
	}
	apiURL := fmt.Sprintf("https://music.163.com/api/song/enhance/player/url?id=%s&br=%s", url.QueryEscape(id), br)
	data, err := fetchNetease(apiURL)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	dataArr, _ := data["data"].([]interface{})
	if len(dataArr) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "no url found"})
		return
	}
	first, _ := dataArr[0].(map[string]interface{})
	songURL, _ := first["url"].(string)
	if songURL == "" {
		c.JSON(http.StatusNotFound, gin.H{"error": "song url is empty (may require VIP or not available)"})
		return
	}
	writeJSON(c, http.StatusOK, gin.H{"url": songURL})
}

// proxyKuwoAudio 转发第三方媒体流（酷我/B站/YouTube）。
//
// 历史实现用 strings.HasSuffix(host, "kuwo.cn") 判定域名，
// 攻击者注册 evilkuwo.cn 即可绕过并借服务端 IP 出网（开放代理 + SSRF）。
// 现改为白名单 + 精确/子域语义匹配 + 私网地址拦截。

func jsonIDToString(v interface{}) string {
	switch val := v.(type) {
	case json.Number:
		return val.String()
	case float64:
		return fmt.Sprintf("%d", int64(val))
	case string:
		return val
	default:
		return fmt.Sprintf("%v", v)
	}
}

// neteaseHeaders 返回请求网易云 API 所需的请求头

func neteaseHeaders() map[string]string {
	return map[string]string{
		"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
		"Referer":    "https://music.163.com/",
	}
}

// fetchNetease 发起网易云 API 请求并返回解析后的 JSON

func fetchNetease(apiURL string) (map[string]interface{}, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return nil, err
	}
	for k, v := range neteaseHeaders() {
		req.Header.Set(k, v)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var result map[string]interface{}
	dec := json.NewDecoder(resp.Body)
	dec.UseNumber() // 避免大整数精度损失
	if err := dec.Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}

// DiscoverLeaderboardList 获取排行榜列表
// GET /api/discover/leaderboard?source=netease|bilibili|youtube|jamendo
