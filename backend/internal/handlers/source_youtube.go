package handlers

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

var youtubeInnertubeContext = map[string]interface{}{
	"client": map[string]interface{}{
		"clientName":    "WEB_REMIX",
		"clientVersion": "1.20240101.00.00",
		"hl":            "zh-CN",
	},
}

// iOS 客户端 context，用于获取未加密的播放 URL

var youtubeIOSContext = map[string]interface{}{
	"client": map[string]interface{}{
		"clientName":    "IOS",
		"clientVersion": "19.29.1",
		"deviceMake":    "Apple",
		"deviceModel":   "iPhone16,2",
		"osName":        "iPhone",
		"osVersion":     "17.5.1.21F90",
		"hl":            "zh-CN",
	},
}

// loadYouTubeCookie 从 Netscape cookie 文件读取 YouTube Cookie 字符串

func loadYouTubeCookie() string {
	data, err := os.ReadFile(ytCookieFilePath())
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

func fetchYouTube(apiURL string, body map[string]interface{}) (map[string]interface{}, error) {
	body["context"] = youtubeInnertubeContext
	payload, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	// 强制 HTTP/1.1，避免 YouTube Music API 的 HTTP/2 header 大小限制
	transport := &http.Transport{
		TLSNextProto:       make(map[string]func(authority string, c *tls.Conn) http.RoundTripper),
		DisableCompression: true,
	}
	client := &http.Client{Timeout: 15 * time.Second, Transport: transport}
	req, err := http.NewRequest("POST", apiURL, strings.NewReader(string(payload)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Origin", "https://music.youtube.com")
	req.Header.Set("Referer", "https://music.youtube.com/")
	req.Header.Set("X-Goog-Api-Key", "AIzaSyC9XL3ZjWddXya6X74dJoCTL-NKNELL6Mg")
	req.Header.Set("X-YouTube-Client-Name", "67")
	req.Header.Set("X-YouTube-Client-Version", "1.20240101.00.00")
	req.Header.Set("Accept", "*/*")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	req.Header.Set("Accept-Encoding", "identity")
	if cookie := loadYouTubeCookie(); cookie != "" {
		req.Header.Set("Cookie", cookie)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var result map[string]interface{}
	dec := json.NewDecoder(resp.Body)
	dec.UseNumber()
	if err := dec.Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}

// youtubeSongList 获取 YouTube 歌单列表（使用音乐分类）

func youtubeSongList() []map[string]interface{} {
	categories := []struct {
		id, name, keyword, coverUrl string
	}{
		{"1", "流行音乐 Pop", "pop music hits", "https://i.ytimg.com/vi/kTJczUoc26U/hqdefault.jpg"},
		{"2", "摇滚 Rock", "rock music", "https://i.ytimg.com/vi/fJ9rUzIMcZQ/hqdefault.jpg"},
		{"3", "嘻哈说唱 Hip Hop", "hip hop rap music", "https://i.ytimg.com/vi/uelHwf8o7_U/hqdefault.jpg"},
		{"4", "电子音乐 EDM", "edm electronic music", "https://i.ytimg.com/vi/IcrbM1l_BoI/hqdefault.jpg"},
		{"5", "爵士 Jazz", "jazz music", "https://i.ytimg.com/vi/vmDDOFXSgAs/hqdefault.jpg"},
		{"6", "古典 Classical", "classical music", "https://i.ytimg.com/vi/jgpJVI3tDbY/hqdefault.jpg"},
		{"7", "乡村 Country", "country music", "https://i.ytimg.com/vi/VuNIsY6JdUw/hqdefault.jpg"},
		{"8", "R&B/灵魂 Soul", "r&b soul music", "https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg"},
		{"9", "雷鬼 Reggae", "reggae music", "https://i.ytimg.com/vi/hzqFmXZ8tOE/hqdefault.jpg"},
		{"10", "蓝调 Blues", "blues music", "https://i.ytimg.com/vi/qiRiPtg9EFk/hqdefault.jpg"},
		{"11", "金属 Metal", "metal music", "https://i.ytimg.com/vi/v2AC41dglnM/hqdefault.jpg"},
		{"12", "朋克 Punk", "punk rock music", "https://i.ytimg.com/vi/z5rRZdiu1UE/hqdefault.jpg"},
		{"13", "独立音乐 Indie", "indie music", "https://i.ytimg.com/vi/rVN1B-tUpgs/hqdefault.jpg"},
		{"14", "放克 Funk", "funk music", "https://i.ytimg.com/vi/0CFuCYNx-1g/hqdefault.jpg"},
		{"15", "迪斯科 Disco", "disco music", "https://i.ytimg.com/vi/TsuVAQkfCes/hqdefault.jpg"},
		{"16", "K-Pop", "kpop music", "https://i.ytimg.com/vi/pSUydWEqKwE/hqdefault.jpg"},
		{"17", "J-Pop", "jpop japanese music", "https://i.ytimg.com/vi/X9zw0QF12Kc/hqdefault.jpg"},
		{"18", "拉丁 Latin", "latin music", "https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg"},
		{"19", "氛围音乐 Ambient", "ambient music", "https://i.ytimg.com/vi/M5QY2_8704o/hqdefault.jpg"},
		{"20", "Lo-Fi", "lofi hip hop music", "https://i.ytimg.com/vi/n61ULEU7CO0/hqdefault.jpg"},
	}

	result := make([]map[string]interface{}, 0, len(categories))
	for _, cat := range categories {
		result = append(result, map[string]interface{}{
			"id":          cat.id,
			"name":        cat.name,
			"author":      "YouTube Music",
			"coverUrl":    cat.coverUrl,
			"playCount":   "",
			"description": fmt.Sprintf("%s - Curated by YouTube Music", cat.name),
			"source":      "youtube",
		})
	}
	return result
}

// youtubeSongListDetail 获取 YouTube 歌单详情（通过分类 ID 搜索）

func youtubeSongListDetail(
	categoryID string,
	limit int,
	offset int,
) ([]map[string]interface{}, error) {
	categoryMap := map[string]string{
		"1":  "pop music hits",
		"2":  "rock music",
		"3":  "hip hop rap music",
		"4":  "edm electronic music",
		"5":  "jazz music",
		"6":  "classical music",
		"7":  "country music",
		"8":  "r&b soul music",
		"9":  "reggae music",
		"10": "blues music",
		"11": "metal music",
		"12": "punk rock music",
		"13": "indie music",
		"14": "funk music",
		"15": "disco music",
		"16": "kpop music",
		"17": "jpop japanese music",
		"18": "latin music",
		"19": "ambient music",
		"20": "lofi hip hop music",
	}

	keyword, ok := categoryMap[categoryID]
	if !ok {
		keyword = "pop music hits" // 默认
	}

	// yt-dlp 一次只能搜一批，翻页靠多取再切片：offset 越大取越多，
	// 上限 3 倍以免每次翻页都去抓上百条。
	batch := offset + limit
	if batch > limit*3 {
		batch = limit * 3
	}
	items, err := youtubeSearchPage(keyword, batch)
	if err != nil {
		return nil, err
	}
	return slicePage(items, offset, limit), nil
}

func youtubeSearch(keyword string, limit int) ([]map[string]interface{}, error) {
	return youtubeSearchPage(keyword, limit)
}

func youtubeSearchPage(keyword string, limit int) ([]map[string]interface{}, error) {
	// 检查搜索缓存（缓存30分钟）
	cacheKey := fmt.Sprintf("%s:%d", keyword, limit)
	ytSearchCacheMu.Lock()
	if entry, ok := ytSearchCache[cacheKey]; ok && time.Now().Before(entry.expiry) {
		ytSearchCacheMu.Unlock()
		return entry.results, nil
	}
	ytSearchCacheMu.Unlock()

	// 用 yt-dlp 搜索，避免 InnerTube API 的 TLS 指纹检测。
	// 参数以数组形式传入 exec.Command，keyword 不再是 shell 字符串的一部分，
	// 因此不存在命令注入面（历史实现用 sh -c 拼接，见安全审计 P0-2）。
	fetchLimit := limit * 3
	args := []string{
		"--dump-json",
		"--flat-playlist",
		"--no-warnings",
	}
	if cookiesPath := ytCookieFilePath(); fileExists(cookiesPath) {
		args = append(args, "--cookies", cookiesPath)
	}
	args = append(args, fmt.Sprintf("ytsearch%d:%s official music video", fetchLimit, keyword))

	out, err := runYtDlp(context.Background(), args...)
	if err != nil || strings.TrimSpace(out) == "" {
		return []map[string]interface{}{}, nil
	}
	result := make([]map[string]interface{}, 0, limit)
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if len(result) >= limit {
			break
		}
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var m map[string]interface{}
		if err := json.Unmarshal([]byte(line), &m); err != nil {
			continue
		}
		videoId, _ := m["id"].(string)
		if videoId == "" {
			continue
		}
		// 过滤时长超过15分钟的合辑/播放列表视频
		if dur, ok := m["duration"].(float64); ok && dur > 900 {
			continue
		}
		title, _ := m["title"].(string)
		artist, _ := m["channel"].(string)
		picUrl := fmt.Sprintf("https://i.ytimg.com/vi/%s/hqdefault.jpg", videoId)
		result = append(result, map[string]interface{}{
			"id":       videoId,
			"name":     title,
			"artist":   artist,
			"album":    "YouTube Music",
			"pic_id":   "",
			"pic_url":  picUrl,
			"url_id":   videoId,
			"mv_id":    videoId,
			"lyric_id": "",
			"source":   "youtube",
		})
	}
	// 写入搜索缓存
	ytSearchCacheMu.Lock()
	ytSearchCache[cacheKey] = ytSearchCacheEntry{results: result, expiry: time.Now().Add(30 * time.Minute)}
	ytSearchCacheMu.Unlock()
	return result, nil
}

func youtubeExtractSongs(node interface{}, result *[]map[string]interface{}, limit int) {
	if len(*result) >= limit {
		return
	}
	switch v := node.(type) {
	case map[string]interface{}:
		// musicResponsiveListItemRenderer 是搜索结果 item
		if renderer, ok := v["musicResponsiveListItemRenderer"].(map[string]interface{}); ok {
			if song := youtubeParseListItem(renderer); song != nil {
				*result = append(*result, song)
			}
			return
		}
		for _, val := range v {
			youtubeExtractSongs(val, result, limit)
		}
	case []interface{}:
		for _, item := range v {
			youtubeExtractSongs(item, result, limit)
		}
	}
}

func youtubeParseListItem(renderer map[string]interface{}) map[string]interface{} {
	// 提取 videoId
	videoId := ""
	if overlay, ok := renderer["overlay"].(map[string]interface{}); ok {
		if mtivor, ok := overlay["musicItemThumbnailOverlayRenderer"].(map[string]interface{}); ok {
			if content, ok := mtivor["content"].(map[string]interface{}); ok {
				if mptbr, ok := content["musicPlayButtonRenderer"].(map[string]interface{}); ok {
					if playNav, ok := mptbr["playNavigationEndpoint"].(map[string]interface{}); ok {
						if watchEndpoint, ok := playNav["watchEndpoint"].(map[string]interface{}); ok {
							videoId, _ = watchEndpoint["videoId"].(string)
						}
					}
				}
			}
		}
	}
	if videoId == "" {
		return nil
	}
	// 提取标题和副标题
	title := ""
	artist := ""
	if flexColumns, ok := renderer["flexColumns"].([]interface{}); ok {
		for i, col := range flexColumns {
			colMap, ok := col.(map[string]interface{})
			if !ok {
				continue
			}
			if mrlfc, ok := colMap["musicResponsiveListItemFlexColumnRenderer"].(map[string]interface{}); ok {
				if text, ok := mrlfc["text"].(map[string]interface{}); ok {
					if runs, ok := text["runs"].([]interface{}); ok && len(runs) > 0 {
						if run, ok := runs[0].(map[string]interface{}); ok {
							t, _ := run["text"].(string)
							if i == 0 {
								title = t
							} else if i == 1 && artist == "" {
								artist = t
							}
						}
					}
				}
			}
		}
	}
	if title == "" {
		return nil
	}
	picUrl := fmt.Sprintf("https://i.ytimg.com/vi/%s/hqdefault.jpg", videoId)
	return map[string]interface{}{
		"id":       videoId,
		"name":     title,
		"artist":   artist,
		"album":    "YouTube Music",
		"pic_id":   "",
		"pic_url":  picUrl,
		"url_id":   videoId,
		"lyric_id": "",
		"source":   "youtube",
	}
}

type ytCacheEntry struct {
	url    string
	expiry time.Time
}

type ytSearchCacheEntry struct {
	results []map[string]interface{}
	expiry  time.Time
}

var (
	ytCache         = map[string]ytCacheEntry{}
	ytCacheMu       sync.Mutex
	ytSearchCache   = map[string]ytSearchCacheEntry{}
	ytSearchCacheMu sync.Mutex
)

func youtubeGetAudioUrl(videoId string) (string, error) {
	// 检查缓存（YouTube URL 有效期约6小时，缓存5小时）
	ytCacheMu.Lock()
	if entry, ok := ytCache[videoId]; ok && time.Now().Before(entry.expiry) {
		ytCacheMu.Unlock()
		return entry.url, nil
	}
	ytCacheMu.Unlock()

	// 用 yt-dlp + cookies + node.js 获取音频 URL。
	// videoId 先做白名单校验再作为独立 argv 传入，杜绝命令注入。
	if !youtubeVideoIDPattern.MatchString(videoId) {
		return "", errInvalidVideoID
	}
	args := []string{"--js-runtimes", "node"}
	// 没有 cookie 文件时不传 --cookies，否则 yt-dlp 直接报错退出
	if cookiesPath := ytCookieFilePath(); fileExists(cookiesPath) {
		args = append(args, "--cookies", cookiesPath)
	}
	args = append(args,
		"-f", "bestaudio[ext=m4a]/bestaudio[acodec=aac]/bestaudio",
		"--get-url",
		"https://www.youtube.com/watch?v="+videoId,
	)
	out, err := runYtDlp(context.Background(), args...)
	if err != nil {
		return "", fmt.Errorf("yt-dlp failed: %w", err)
	}
	u := strings.TrimSpace(out)
	if u == "" {
		return "", fmt.Errorf("yt-dlp returned empty url")
	}

	// 写入缓存
	ytCacheMu.Lock()
	ytCache[videoId] = ytCacheEntry{url: u, expiry: time.Now().Add(5 * time.Hour)}
	ytCacheMu.Unlock()
	return u, nil
}

func youtubeGetVideoUrl(videoId string) (string, error) {
	if !youtubeVideoIDPattern.MatchString(videoId) {
		return "", errInvalidVideoID
	}
	// 格式18 = 360p 预合并 mp4，几乎所有视频都有，video_player 单 URL 直接播放
	// fallback: best[ext=mp4] -> best
	args := []string{"--js-runtimes", "node"}
	if cookiesPath := ytCookieFilePath(); fileExists(cookiesPath) {
		args = append(args, "--cookies", cookiesPath)
	}
	args = append(args,
		"-f", "18/best[ext=mp4]/best",
		"--get-url",
		"https://www.youtube.com/watch?v="+videoId,
	)
	out, err := runYtDlp(context.Background(), args...)
	if err != nil {
		return "", fmt.Errorf("yt-dlp video failed: %w", err)
	}
	u := strings.TrimSpace(strings.Split(strings.TrimSpace(out), "\n")[0])
	if u == "" {
		return "", fmt.Errorf("yt-dlp returned empty video url")
	}
	return u, nil
}

// runYtDlp 以参数数组方式执行 yt-dlp。
//
// 历史实现 execShell 把整条命令交给 `sh -c`，任何拼接进命令串的用户输入
// （videoId 来自 query 参数）都构成 RCE。改为 exec.Command + 独立 argv 后，
// shell 元字符失去语义；同时保留 60s 超时与 stderr 采集便于排障。

func runYtDlp(ctx context.Context, args ...string) (string, error) {
	bin, err := exec.LookPath("yt-dlp")
	if err != nil {
		return "", fmt.Errorf("未找到 yt-dlp，可执行文件不在 PATH 中: %w", err)
	}

	execCtx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()

	cmd := exec.CommandContext(execCtx, bin, args...)
	// yt-dlp 输出可能包含 Cookie 值，禁止透传到服务日志
	cmd.Env = append(os.Environ(), "PYTHONWARNINGS=ignore")

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if execCtx.Err() == context.DeadlineExceeded {
			return "", fmt.Errorf("yt-dlp 执行超时（60s）")
		}
		tail := stderr.String()
		if len(tail) > 400 {
			tail = tail[len(tail)-400:]
		}
		return "", fmt.Errorf("yt-dlp 执行失败: %w: %s", err, strings.TrimSpace(tail))
	}
	return stdout.String(), nil
}

// fileExists 判断路径是否存在且为普通文件。

func youtubeLeaderboardList() ([]map[string]interface{}, error) {
	results, _ := youtubeSearch("Bruno Mars", 1)
	coverUrl := ""
	if len(results) > 0 {
		coverUrl, _ = results[0]["pic_url"].(string)
	}
	return []map[string]interface{}{
		{
			"id":              "yt_hot",
			"name":            "热门音乐",
			"coverUrl":        coverUrl,
			"updateFrequency": "",
			"source":          "youtube",
		},
	}, nil
}

func youtubeLeaderboardDetail(limit int) ([]map[string]interface{}, error) {
	return youtubeLeaderboardDetailByID("yt_hot", limit)
}

func youtubeLeaderboardDetailByID(id string, limit int) ([]map[string]interface{}, error) {
	return youtubeSearch("Bruno Mars", limit)
}

// ── Cookie 管理 ────────────────────────────────────────────────────

// UploadCookie 上传 cookie 文件
// POST /api/cookies/upload?type=youtube|bilibili
