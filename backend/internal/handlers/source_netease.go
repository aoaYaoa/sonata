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

// neteaseHTTPClient 网易云请求共用同一个 Transport。
//
// 原来每次请求都 new 一个 http.Client：65 个榜单并发探测要各自走一遍
// TCP + TLS 握手（实测单次 3.1s，其中握手占大头），探一轮 6.4s。
// 连接复用之后同一批探测稳定在 2.5s 上下——「全部榜单」页的等待时间
// 基本就花在这上面。
var neteaseHTTPClient = &http.Client{
	Timeout: 12 * time.Second,
	Transport: &http.Transport{
		Proxy:               http.ProxyFromEnvironment,
		MaxIdleConns:        64,
		MaxIdleConnsPerHost: 32,
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: 8 * time.Second,
		ForceAttemptHTTP2:   true,
	},
}

// fetchNetease 发起网易云 API 请求并返回解析后的 JSON

func fetchNetease(apiURL string) (map[string]interface{}, error) {
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return nil, err
	}
	for k, v := range neteaseHeaders() {
		req.Header.Set(k, v)
	}
	resp, err := neteaseHTTPClient.Do(req)
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
