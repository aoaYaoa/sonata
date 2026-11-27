package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

func jamendoClientID() string {
	return os.Getenv("JAMENDO_CLIENT_ID")
}

func fetchJamendo(apiURL string) (map[string]interface{}, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(apiURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}

func jamendoSearch(keyword string, limit int) ([]map[string]interface{}, error) {
	cid := jamendoClientID()
	if cid == "" {
		return nil, fmt.Errorf("JAMENDO_CLIENT_ID not configured")
	}
	apiURL := fmt.Sprintf(
		"https://api.jamendo.com/v3.0/tracks?client_id=%s&namesearch=%s&format=json&limit=%d&include=musicinfo",
		cid, url.QueryEscape(keyword), limit,
	)
	return jamendoParseTracks(apiURL)
}

// jamendoSongList 获取 Jamendo 歌单列表（使用电台分类）

func jamendoSongList() ([]map[string]interface{}, error) {
	cid := jamendoClientID()
	if cid == "" {
		return nil, fmt.Errorf("JAMENDO_CLIENT_ID not configured")
	}
	apiURL := fmt.Sprintf("https://api.jamendo.com/v3.0/radios/?client_id=%s&format=json&limit=20", cid)
	data, err := fetchJamendo(apiURL)
	if err != nil {
		return nil, err
	}
	results, _ := data["results"].([]interface{})
	songLists := make([]map[string]interface{}, 0, len(results))
	for _, item := range results {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		cover, _ := m["image"].(string)
		name, _ := m["dispname"].(string)
		// 部分电台的官方配图在 CDN 上已经 404（piano/happy），
		// 用同名 tag 的曲目封面兜底，避免卡片只剩渐变底。
		if !jamendoImageAlive(cover) {
			cover = jamendoFirstPic(strings.ToLower(strings.TrimSuffix(name, " Radio")))
		}
		songLists = append(songLists, map[string]interface{}{
			"id":          fmt.Sprintf("%v", m["id"]),
			"name":        name,
			"author":      "Jamendo Radio",
			"coverUrl":    cover,
			"playCount":   "",
			"description": fmt.Sprintf("%s - Free Music Radio", name),
			"source":      "jamendo",
		})
	}
	return songLists, nil
}

// jamendoImageAlive 探测封面地址是否还能取到图。
//
// 只发 HEAD 并限制 3 秒：电台列表本身是内存里拼的，探测失败就降级，
// 不能让一个 404 的图拖住整个歌单接口。
func jamendoImageAlive(url string) bool {
	if url == "" {
		return false
	}
	client := &http.Client{Timeout: 3 * time.Second}
	req, err := http.NewRequest(http.MethodHead, url, nil)
	if err != nil {
		return false
	}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

// jamendoSongListDetail 获取 Jamendo 歌单详情（通过电台名称获取对应标签的歌曲）

func jamendoSongListDetail(
	radioID string,
	limit int,
	offset int,
) ([]map[string]interface{}, error) {
	// 电台 ID 到标签的映射
	radioTagMap := map[string]string{
		"1":  "",           // bestof - 不指定标签，获取热门
		"2":  "electronic", // electro
		"3":  "rock",
		"4":  "lounge",
		"5":  "hiphop",
		"6":  "world",
		"7":  "jazz",
		"8":  "classical",
		"9":  "pop",
		"10": "songwriting",
		"11": "metal",
		"12": "soundtrack",
		"13": "relaxation",
		"14": "piano",
		"15": "happy",
	}

	tag, ok := radioTagMap[radioID]
	if !ok {
		tag = "" // 默认获取热门
	}

	cid := jamendoClientID()
	if cid == "" {
		return nil, fmt.Errorf("JAMENDO_CLIENT_ID not configured")
	}

	// Jamendo 自己支持 offset，直接透传（原来只传 limit，
	// 「加载更多」拿回的还是同一批）。
	if offset < 0 {
		offset = 0
	}
	var apiURL string
	if tag == "" {
		// 获取热门歌曲
		apiURL = fmt.Sprintf(
			"https://api.jamendo.com/v3.0/tracks?client_id=%s&order=popularity_total&format=json&limit=%d&offset=%d&include=musicinfo",
			cid, limit, offset,
		)
	} else {
		// 按标签获取歌曲
		apiURL = fmt.Sprintf(
			"https://api.jamendo.com/v3.0/tracks?client_id=%s&tags=%s&order=popularity_total&format=json&limit=%d&offset=%d&include=musicinfo",
			cid, url.QueryEscape(tag), limit, offset,
		)
	}

	return jamendoParseTracks(apiURL)
}

// jamendoFirstPic 获取分类封面。
//
// Jamendo 的 tag 检索本身不稳定：同一个查询连续 5 次会在 0/1 条之间跳，
// 并发 8 个分类时经常一半返回空。所以按「严格 tag → 模糊 tag → 热门兜底」
// 三级降级，前两级各重试一次；兜底时按 tag 哈希从热门列表里挑不同的一张，
// 避免几个缺图分类挂上同一张封面。
func jamendoFirstPic(tag string) string {
	cid := jamendoClientID()
	if cid == "" {
		return ""
	}
	for _, q := range []string{
		"tags=" + url.QueryEscape(tag),
		"fuzzytags=" + url.QueryEscape(tag),
	} {
		for attempt := 0; attempt < 2; attempt++ {
			if img := jamendoCoverFromQuery(cid, q, 0); img != "" {
				return img
			}
		}
	}
	// 兜底：热门曲目列表里按 tag 哈希取一张，宁可挂主题略有偏差的真图，
	// 也不要音乐馆里出现空白卡片。
	seed := 0
	for _, ch := range tag {
		seed = seed*31 + int(ch)
	}
	return jamendoCoverFromQuery(cid, "order=popularity_total", seed%8)
}

// jamendoCoverFromQuery 取一批结果里的第 pick 张封面（越界则取最后一张）。
func jamendoCoverFromQuery(cid, query string, pick int) string {
	apiURL := fmt.Sprintf(
		"https://api.jamendo.com/v3.0/tracks?client_id=%s&%s&format=json&limit=8",
		cid, query,
	)
	data, err := fetchJamendo(apiURL)
	if err != nil {
		return ""
	}
	results, _ := data["results"].([]interface{})
	if len(results) == 0 {
		return ""
	}
	if pick >= len(results) {
		pick = len(results) - 1
	}
	m, _ := results[pick].(map[string]interface{})
	if m == nil {
		return ""
	}
	image, _ := m["image"].(string)
	return image
}

func jamendoLeaderboardList() ([]map[string]interface{}, error) {
	type coverResult struct {
		index int
		url   string
	}
	covers := make([]string, len(jamendoCategories))
	ch := make(chan coverResult, len(jamendoCategories))
	for i, cat := range jamendoCategories {
		go func(idx int, tag string) {
			ch <- coverResult{idx, jamendoFirstPic(tag)}
		}(i, cat.tag)
	}
	for range jamendoCategories {
		r := <-ch
		covers[r.index] = r.url
	}
	result := make([]map[string]interface{}, 0, len(jamendoCategories))
	for i, cat := range jamendoCategories {
		result = append(result, map[string]interface{}{
			"id":              cat.id,
			"name":            cat.name,
			"coverUrl":        covers[i],
			"updateFrequency": "",
			"source":          "jamendo",
		})
	}
	return result, nil
}

func jamendoParseTracks(apiURL string) ([]map[string]interface{}, error) {
	data, err := fetchJamendo(apiURL)
	if err != nil {
		return nil, err
	}
	results, _ := data["results"].([]interface{})
	out := make([]map[string]interface{}, 0, len(results))
	for _, item := range results {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		id, _ := m["id"].(string)
		name, _ := m["name"].(string)
		artist, _ := m["artist_name"].(string)
		album, _ := m["album_name"].(string)
		audio, _ := m["audio"].(string)
		image, _ := m["image"].(string)
		out = append(out, map[string]interface{}{
			"id":       id,
			"name":     name,
			"artist":   artist,
			"album":    album,
			"pic_id":   "",
			"pic_url":  image,
			"url_id":   audio, // 直接是播放URL
			"lyric_id": "",
			"source":   "jamendo",
		})
	}
	return out, nil
}

var jamendoCategories = []struct{ id, name, tag string }{
	{"jam_pop", "流行", "pop"},
	{"jam_electronic", "电子", "electronic"},
	{"jam_rock", "摇滚", "rock"},
	{"jam_jazz", "爵士", "jazz"},
	{"jam_classical", "古典", "classical"},
	{"jam_ambient", "氛围", "ambient"},
	{"jam_folk", "民谣", "folk"},
	{"jam_hiphop", "嘻哈", "hiphop"},
}

func jamendoLeaderboardDetail(limit int) ([]map[string]interface{}, error) {
	return jamendoLeaderboardDetailByID("jam_pop", limit)
}

func jamendoLeaderboardDetailByID(id string, limit int) ([]map[string]interface{}, error) {
	cid := jamendoClientID()
	if cid == "" {
		return nil, fmt.Errorf("JAMENDO_CLIENT_ID not configured")
	}
	tag := "pop"
	for _, cat := range jamendoCategories {
		if cat.id == id {
			tag = cat.tag
			break
		}
	}
	apiURL := fmt.Sprintf(
		"https://api.jamendo.com/v3.0/tracks?client_id=%s&tags=%s&order=popularity_total&format=json&limit=%d",
		cid, url.QueryEscape(tag), limit,
	)
	return jamendoParseTracks(apiURL)
}

// ─────────────────────────────────────────────────────────────────────────────
// YouTube Music 音源（InnerTube API）
// ─────────────────────────────────────────────────────────────────────────────
