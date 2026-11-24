package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
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
		songLists = append(songLists, map[string]interface{}{
			"id":          fmt.Sprintf("%v", m["id"]),
			"name":        m["dispname"],
			"author":      "Jamendo Radio",
			"coverUrl":    m["image"],
			"playCount":   "",
			"description": fmt.Sprintf("%s - Free Music Radio", m["dispname"]),
			"source":      "jamendo",
		})
	}
	return songLists, nil
}

// jamendoSongListDetail 获取 Jamendo 歌单详情（通过电台名称获取对应标签的歌曲）

func jamendoSongListDetail(radioID string, limit int) ([]map[string]interface{}, error) {
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

	var apiURL string
	if tag == "" {
		// 获取热门歌曲
		apiURL = fmt.Sprintf(
			"https://api.jamendo.com/v3.0/tracks?client_id=%s&order=popularity_total&format=json&limit=%d&include=musicinfo",
			cid, limit,
		)
	} else {
		// 按标签获取歌曲
		apiURL = fmt.Sprintf(
			"https://api.jamendo.com/v3.0/tracks?client_id=%s&tags=%s&order=popularity_total&format=json&limit=%d&include=musicinfo",
			cid, url.QueryEscape(tag), limit,
		)
	}

	return jamendoParseTracks(apiURL)
}

// jamendoFirstPic 获取分类第一首歌的封面

func jamendoFirstPic(tag string) string {
	cid := jamendoClientID()
	if cid == "" {
		return ""
	}
	apiURL := fmt.Sprintf(
		"https://api.jamendo.com/v3.0/tracks?client_id=%s&tags=%s&order=popularity_total&format=json&limit=1",
		cid, url.QueryEscape(tag),
	)
	data, err := fetchJamendo(apiURL)
	if err != nil {
		return ""
	}
	results, _ := data["results"].([]interface{})
	if len(results) == 0 {
		return ""
	}
	m, _ := results[0].(map[string]interface{})
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
