package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

// bilibiliBVIDPattern B 站 BV 号：BV + 10 位 base58。

func bilibiliHeaders() map[string]string {
	return map[string]string{
		"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
		"Referer":    "https://www.bilibili.com/",
	}
}

// loadBilibiliCookie 从 Netscape cookie 文件读取 Cookie 字符串

func loadBilibiliCookie() string {
	data, err := os.ReadFile(bilibiliCookieFilePath())
	if err != nil {
		return ""
	}
	var parts []string
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 7 {
			continue
		}
		parts = append(parts, fields[5]+"="+fields[6])
	}
	return strings.Join(parts, "; ")
}

func fetchBilibili(apiURL string) (map[string]interface{}, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return nil, err
	}
	for k, v := range bilibiliHeaders() {
		req.Header.Set(k, v)
	}
	if cookie := loadBilibiliCookie(); cookie != "" {
		req.Header.Set("Cookie", cookie)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("bilibili api status %d", resp.StatusCode)
	}
	var result map[string]interface{}
	dec := json.NewDecoder(resp.Body)
	dec.UseNumber()
	if err := dec.Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}

// BilibiliSearch 搜索B站音乐视频

func (h *SolaraHandler) BilibiliSearch(keyword string, page, count int) ([]map[string]interface{}, error) {
	apiURL := fmt.Sprintf(
		"https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=%s&tids=3&page=%d&page_size=%d",
		url.QueryEscape(keyword), page, count,
	)
	data, err := fetchBilibili(apiURL)
	if err != nil {
		return nil, err
	}
	dataMap, _ := data["data"].(map[string]interface{})
	if dataMap == nil {
		return []map[string]interface{}{}, nil
	}
	result2, _ := dataMap["result"].([]interface{})
	result := make([]map[string]interface{}, 0, len(result2))
	for _, item := range result2 {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		bvid, _ := m["bvid"].(string)
		if bvid == "" {
			continue
		}
		title, _ := m["title"].(string)
		// 去除 HTML 标签
		title = strings.ReplaceAll(title, "<em class=\"keyword\">", "")
		title = strings.ReplaceAll(title, "</em>", "")
		author, _ := m["author"].(string)
		pic, _ := m["pic"].(string)
		if !strings.HasPrefix(pic, "http") {
			pic = "https:" + pic
		}
		result = append(result, map[string]interface{}{
			"id":       bvid,
			"name":     title,
			"artist":   author,
			"album":    "Bilibili",
			"pic_id":   "",
			"pic_url":  pic,
			"url_id":   bvid,
			"mv_id":    bvid,
			"lyric_id": "",
			"source":   "bilibili",
		})
	}
	return result, nil
}

// BilibiliPlayUrl 获取B站视频音频流URL

func (h *SolaraHandler) BilibiliPlayUrl(bvid string) (string, error) {
	// 检查缓存（B站音频URL有效期约2分钟，缓存90秒）
	biliCacheMu.Lock()
	if entry, ok := biliCache[bvid]; ok && time.Now().Before(entry.expiry) {
		biliCacheMu.Unlock()
		return entry.url, nil
	}
	biliCacheMu.Unlock()

	// 1. 获取 cid
	pageURL := fmt.Sprintf("https://api.bilibili.com/x/player/pagelist?bvid=%s", url.QueryEscape(bvid))
	pageData, err := fetchBilibili(pageURL)
	if err != nil {
		return "", err
	}
	pages, _ := pageData["data"].([]interface{})
	if len(pages) == 0 {
		return "", fmt.Errorf("no pages found for bvid %s", bvid)
	}
	firstPage, _ := pages[0].(map[string]interface{})
	cid := jsonIDToString(firstPage["cid"])

	// 2. 获取播放 URL（fnval=16 = dash格式）
	playURL := fmt.Sprintf(
		"https://api.bilibili.com/x/player/playurl?bvid=%s&cid=%s&fnval=16&qn=64",
		url.QueryEscape(bvid), url.QueryEscape(cid),
	)
	playData, err := fetchBilibili(playURL)
	if err != nil {
		return "", err
	}
	dataMap, _ := playData["data"].(map[string]interface{})
	if dataMap == nil {
		return "", fmt.Errorf("no data in playurl response")
	}

	// 优先取 dash audio
	if dash, ok := dataMap["dash"].(map[string]interface{}); ok {
		if audioList, ok := dash["audio"].([]interface{}); ok && len(audioList) > 0 {
			// 取第一个（最高码率）
			if audioItem, ok := audioList[0].(map[string]interface{}); ok {
				if baseUrl, ok := audioItem["baseUrl"].(string); ok && baseUrl != "" {
					biliCacheMu.Lock()
					biliCache[bvid] = biliCacheEntry{url: baseUrl, expiry: time.Now().Add(90 * time.Second)}
					biliCacheMu.Unlock()
					return baseUrl, nil
				}
				if baseUrl, ok := audioItem["base_url"].(string); ok && baseUrl != "" {
					biliCacheMu.Lock()
					biliCache[bvid] = biliCacheEntry{url: baseUrl, expiry: time.Now().Add(90 * time.Second)}
					biliCacheMu.Unlock()
					return baseUrl, nil
				}
			}
		}
	}

	// fallback: durl
	if durls, ok := dataMap["durl"].([]interface{}); ok && len(durls) > 0 {
		if d, ok := durls[0].(map[string]interface{}); ok {
			if u, ok := d["url"].(string); ok && u != "" {
				biliCacheMu.Lock()
				biliCache[bvid] = biliCacheEntry{url: u, expiry: time.Now().Add(90 * time.Second)}
				biliCacheMu.Unlock()
				return u, nil
			}
		}
	}
	return "", fmt.Errorf("no audio url found")
}

// BilibiliVideoUrl 获取B站视频流URL（用于MV播放）

func (h *SolaraHandler) BilibiliVideoUrl(bvid string) (string, error) {
	// 检查缓存
	cacheKey := "video_" + bvid
	biliCacheMu.Lock()
	if entry, ok := biliCache[cacheKey]; ok && time.Now().Before(entry.expiry) {
		biliCacheMu.Unlock()
		return entry.url, nil
	}
	biliCacheMu.Unlock()

	// 1. 获取 cid
	pageURL := fmt.Sprintf("https://api.bilibili.com/x/player/pagelist?bvid=%s", url.QueryEscape(bvid))
	pageData, err := fetchBilibili(pageURL)
	if err != nil {
		return "", err
	}
	pages, _ := pageData["data"].([]interface{})
	if len(pages) == 0 {
		return "", fmt.Errorf("no pages found for bvid %s", bvid)
	}
	firstPage, _ := pages[0].(map[string]interface{})
	cid := jsonIDToString(firstPage["cid"])

	// 2. 获取播放 URL（fnval=16 = dash格式，qn=80 = 高清1080P）
	playURL := fmt.Sprintf(
		"https://api.bilibili.com/x/player/playurl?bvid=%s&cid=%s&fnval=16&qn=80",
		url.QueryEscape(bvid), url.QueryEscape(cid),
	)
	playData, err := fetchBilibili(playURL)
	if err != nil {
		return "", err
	}
	dataMap, _ := playData["data"].(map[string]interface{})
	if dataMap == nil {
		return "", fmt.Errorf("no data in playurl response")
	}

	// 优先取 dash video
	if dash, ok := dataMap["dash"].(map[string]interface{}); ok {
		if videoList, ok := dash["video"].([]interface{}); ok && len(videoList) > 0 {
			// 取第一个视频流（通常是最高质量）
			if videoItem, ok := videoList[0].(map[string]interface{}); ok {
				if baseUrl, ok := videoItem["baseUrl"].(string); ok && baseUrl != "" {
					biliCacheMu.Lock()
					biliCache[cacheKey] = biliCacheEntry{url: baseUrl, expiry: time.Now().Add(90 * time.Second)}
					biliCacheMu.Unlock()
					return baseUrl, nil
				}
				if baseUrl, ok := videoItem["base_url"].(string); ok && baseUrl != "" {
					biliCacheMu.Lock()
					biliCache[cacheKey] = biliCacheEntry{url: baseUrl, expiry: time.Now().Add(90 * time.Second)}
					biliCacheMu.Unlock()
					return baseUrl, nil
				}
			}
		}
	}

	// fallback: durl（旧版格式，包含音视频混合流）
	if durls, ok := dataMap["durl"].([]interface{}); ok && len(durls) > 0 {
		if d, ok := durls[0].(map[string]interface{}); ok {
			if u, ok := d["url"].(string); ok && u != "" {
				biliCacheMu.Lock()
				biliCache[cacheKey] = biliCacheEntry{url: u, expiry: time.Now().Add(90 * time.Second)}
				biliCacheMu.Unlock()
				return u, nil
			}
		}
	}
	return "", fmt.Errorf("no video url found")
}

var bilibiliCategories = []struct {
	id, name      string
	searchKeyword string   // 用于搜索的关键词
	filterWords   []string // 搜索结果按此过滤（空则不过滤）
}{
	{"bili_pop", "流行", "流行歌曲", nil},
	{"bili_electronic", "电子", "电子音乐 EDM", nil},
	{"bili_rock", "摇滚", "摇滚乐队", nil},
	{"bili_folk", "民谣", "民谣吉他弹唱", nil},
	{"bili_ancient", "古风", "古风国风音乐", nil},
	{"bili_cover", "翻唱", "翻唱cover", nil},
	{"bili_jazz", "爵士", "jazz爵士乐", nil},
	{"bili_classical", "古典", "钢琴古典音乐", nil},
	{"bili_ranking", "音乐区周榜", "", nil},
}

func bilibiliLeaderboardList() ([]map[string]interface{}, error) {
	// 从周榜API取第一个视频封面作为周榜分类封面
	rankingCover := ""
	data, err := fetchBilibili("https://api.bilibili.com/x/web-interface/ranking/v2?rid=3&type=all")
	if err == nil {
		if dm, ok := data["data"].(map[string]interface{}); ok {
			if list, ok := dm["list"].([]interface{}); ok && len(list) > 0 {
				if first, ok := list[0].(map[string]interface{}); ok {
					pic, _ := first["pic"].(string)
					if pic != "" && !strings.HasPrefix(pic, "http") {
						pic = "https:" + pic
					}
					rankingCover = pic
				}
			}
		}
	}
	result := make([]map[string]interface{}, 0, len(bilibiliCategories))
	for _, cat := range bilibiliCategories {
		coverUrl := ""
		if cat.id == "bili_ranking" {
			coverUrl = rankingCover
		}
		result = append(result, map[string]interface{}{
			"id":              cat.id,
			"name":            cat.name,
			"coverUrl":        coverUrl,
			"updateFrequency": "",
			"source":          "bilibili",
		})
	}
	return result, nil
}

func bilibiliSongList() ([]map[string]interface{}, error) {
	// 用音乐区排行榜视频列表作为「歌单」
	apiURL := "https://api.bilibili.com/x/web-interface/ranking/v2?rid=3&type=all"
	data, err := fetchBilibili(apiURL)
	if err != nil {
		return nil, err
	}
	dataMap, _ := data["data"].(map[string]interface{})
	if dataMap == nil {
		return []map[string]interface{}{}, nil
	}
	return []map[string]interface{}{
		{
			"id":          "bilibili_music_ranking",
			"name":        "音乐区周榜",
			"author":      "Bilibili",
			"coverUrl":    "",
			"playCount":   "",
			"description": "B站音乐区本周最热视频",
			"source":      "bilibili",
		},
	}, nil
}

func bilibiliLeaderboardDetail(limit int) ([]map[string]interface{}, error) {
	return bilibiliLeaderboardDetailByID("bili_ranking", limit)
}

// bilibiliSearchCache 分类搜索缓存（30分钟）

type biliSearchCacheEntry struct {
	results []map[string]interface{}
	expiry  time.Time
}

var (
	biliSearchCache   = map[string]biliSearchCacheEntry{}
	biliSearchCacheMu sync.Mutex
)

func bilibiliLeaderboardDetailByID(id string, limit int) ([]map[string]interface{}, error) {
	// 周榜：直接用排行榜 API
	if id == "bili_ranking" || id == "" {
		return bilibiliRankingDetail(limit)
	}

	// 其他分类：全量搜索「音乐」，按分类关键词过滤标题
	// 先查缓存
	biliSearchCacheMu.Lock()
	if entry, ok := biliSearchCache[id]; ok && time.Now().Before(entry.expiry) {
		biliSearchCacheMu.Unlock()
		if len(entry.results) > limit {
			return entry.results[:limit], nil
		}
		return entry.results, nil
	}
	biliSearchCacheMu.Unlock()

	// 找分类的搜索关键词
	searchKeyword := "音乐"
	for _, cat := range bilibiliCategories {
		if cat.id == id && cat.searchKeyword != "" {
			searchKeyword = cat.searchKeyword
			break
		}
	}

	// 用分类专属关键词搜索
	h := &SolaraHandler{}
	result, err := h.BilibiliSearch(searchKeyword, 1, limit)
	if err != nil {
		return []map[string]interface{}{}, nil
	}

	// 写缓存
	biliSearchCacheMu.Lock()
	biliSearchCache[id] = biliSearchCacheEntry{results: result, expiry: time.Now().Add(30 * time.Minute)}
	biliSearchCacheMu.Unlock()
	return result, nil
}

func bilibiliRankingDetail(limit int) ([]map[string]interface{}, error) {
	apiURL := "https://api.bilibili.com/x/web-interface/ranking/v2?rid=3&type=all"
	data, err := fetchBilibili(apiURL)
	if err != nil {
		return nil, err
	}
	dataMap, _ := data["data"].(map[string]interface{})
	if dataMap == nil {
		return []map[string]interface{}{}, nil
	}
	list, _ := dataMap["list"].([]interface{})
	result := make([]map[string]interface{}, 0)
	for i, item := range list {
		if i >= limit {
			break
		}
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		bvid, _ := m["bvid"].(string)
		title, _ := m["title"].(string)
		owner, _ := m["owner"].(map[string]interface{})
		author := ""
		if owner != nil {
			author, _ = owner["name"].(string)
		}
		pic, _ := m["pic"].(string)
		if !strings.HasPrefix(pic, "http") {
			pic = "https:" + pic
		}
		result = append(result, map[string]interface{}{
			"id":       bvid,
			"name":     title,
			"artist":   author,
			"album":    "Bilibili音乐区",
			"pic_id":   "",
			"pic_url":  pic,
			"url_id":   bvid,
			"mv_id":    bvid,
			"lyric_id": "",
			"source":   "bilibili",
		})
	}
	return result, nil
}

func h_bilibiliSearchStatic(keyword string, limit int) ([]map[string]interface{}, error) {
	h := &SolaraHandler{}
	return h.BilibiliSearch(keyword, 1, limit)
}

// ─────────────────────────────────────────────────────────────────────────────
// Jamendo 音源
// ─────────────────────────────────────────────────────────────────────────────

type biliCacheEntry struct {
	url    string
	expiry time.Time
}

var (
	biliCache   = map[string]biliCacheEntry{}
	biliCacheMu sync.Mutex
)
