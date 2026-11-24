package handlers

import (
	"fmt"
	"net/http"
	"net/url"

	"github.com/gin-gonic/gin"
)

func (h *SolaraHandler) DiscoverLeaderboardList(c *gin.Context) {
	if !h.isAuthed(c) {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false})
		return
	}
	source := c.DefaultQuery("source", "netease")
	switch source {
	case "bilibili":
		result, err := bilibiliLeaderboardList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
	case "youtube":
		result, err := youtubeLeaderboardList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
	case "jamendo":
		result, err := jamendoLeaderboardList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
	default: // netease and others
		data, err := fetchNetease("https://music.163.com/api/toplist")
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		list, _ := data["list"].([]interface{})
		result := make([]map[string]interface{}, 0, len(list))
		for _, item := range list {
			m, ok := item.(map[string]interface{})
			if !ok {
				continue
			}
			result = append(result, map[string]interface{}{
				"id":              jsonIDToString(m["id"]),
				"name":            m["name"],
				"coverUrl":        m["coverImgUrl"],
				"updateFrequency": m["updateFrequency"],
				"source":          "netease",
			})
		}
		c.JSON(http.StatusOK, result)
	}
}

// DiscoverLeaderboardDetail 获取排行榜详情
// GET /api/discover/leaderboard/:id?source=...

func (h *SolaraHandler) DiscoverLeaderboardDetail(c *gin.Context) {
	if !h.isAuthed(c) {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false})
		return
	}
	source := c.DefaultQuery("source", "netease")
	limitStr := c.DefaultQuery("limit", "30")
	limit := 30
	fmt.Sscanf(limitStr, "%d", &limit)

	id := c.Param("id")
	switch source {
	case "bilibili":
		result, err := bilibiliLeaderboardDetailByID(id, limit)
		if err != nil {
			// B站可能触发风控返回 HTML，降级为空列表
			c.JSON(http.StatusOK, []interface{}{})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	case "youtube":
		result, err := youtubeLeaderboardDetailByID(id, limit)
		if err != nil {
			c.JSON(http.StatusOK, []interface{}{})
			return
		}
		c.JSON(http.StatusOK, result)
		// 后台预热前5首歌的音频URL缓存
		go func() {
			for i, song := range result {
				if i >= 5 {
					break
				}
				if vid, ok := song["url_id"].(string); ok && vid != "" {
					youtubeGetAudioUrl(vid) //nolint:errcheck
				}
			}
		}()
		return
	case "jamendo":
		result, err := jamendoLeaderboardDetailByID(id, limit)
		if err != nil {
			c.JSON(http.StatusOK, []interface{}{})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	}

	apiURL := fmt.Sprintf("https://music.163.com/api/v3/playlist/detail?id=%s&n=%d", url.QueryEscape(id), limit)
	data, err := fetchNetease(apiURL)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	playlist, _ := data["playlist"].(map[string]interface{})
	if playlist == nil {
		c.JSON(http.StatusOK, []interface{}{})
		return
	}
	tracks, _ := playlist["tracks"].([]interface{})
	result := make([]map[string]interface{}, 0, len(tracks))
	for _, item := range tracks {
		t, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		artists := ""
		if ar, ok := t["ar"].([]interface{}); ok && len(ar) > 0 {
			if a, ok := ar[0].(map[string]interface{}); ok {
				artists, _ = a["name"].(string)
			}
		}
		al, _ := t["al"].(map[string]interface{})
		picId := ""
		picUrl := ""
		if al != nil {
			picUrl, _ = al["picUrl"].(string)
			picId = jsonIDToString(al["pic"])
			if picId == "0" || picId == "" {
				picId = jsonIDToString(al["id"])
			}
		}
		songID := jsonIDToString(t["id"])
		albumName := ""
		if al != nil {
			albumName, _ = al["name"].(string)
		}
		result = append(result, map[string]interface{}{
			"id":       songID,
			"name":     t["name"],
			"artist":   artists,
			"album":    albumName,
			"pic_id":   picId,
			"pic_url":  picUrl,
			"url_id":   songID,
			"lyric_id": songID,
			"source":   "netease",
		})
	}
	c.JSON(http.StatusOK, result)
}

// DiscoverSongList 获取推荐歌单列表
// GET /api/discover/songlist?source=netease|bilibili|youtube|jamendo

func (h *SolaraHandler) DiscoverSongList(c *gin.Context) {
	if !h.isAuthed(c) {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false})
		return
	}
	source := c.DefaultQuery("source", "netease")
	switch source {
	case "bilibili":
		result, err := bilibiliSongList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
	case "jamendo":
		// Jamendo：使用电台分类作为歌单
		result, err := jamendoSongList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
	case "youtube":
		// YouTube：使用音乐分类关键词作为歌单
		result := youtubeSongList()
		c.JSON(http.StatusOK, result)
	default: // netease
		limitStr := c.DefaultQuery("limit", "30")
		limit := 30
		fmt.Sscanf(limitStr, "%d", &limit)
		pageStr := c.DefaultQuery("page", "1")
		page := 1
		fmt.Sscanf(pageStr, "%d", &page)
		offset := (page - 1) * limit
		tag := c.DefaultQuery("tag", "")
		cat := "%E5%85%A8%E9%83%A8"
		if tag != "" {
			cat = url.QueryEscape(tag)
		}
		apiURL := fmt.Sprintf("https://music.163.com/api/playlist/list?cat=%s&order=hot&offset=%d&total=true&limit=%d", cat, offset, limit)
		data, err := fetchNetease(apiURL)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		playlists, _ := data["playlists"].([]interface{})
		result := make([]map[string]interface{}, 0, len(playlists))
		for _, item := range playlists {
			m, ok := item.(map[string]interface{})
			if !ok {
				continue
			}
			creator := ""
			if cr, ok := m["creator"].(map[string]interface{}); ok {
				creator, _ = cr["nickname"].(string)
			}
			result = append(result, map[string]interface{}{
				"id":          jsonIDToString(m["id"]),
				"name":        m["name"],
				"author":      creator,
				"coverUrl":    m["coverImgUrl"],
				"playCount":   fmt.Sprintf("%v", m["playCount"]),
				"description": m["description"],
				"source":      "netease",
			})
		}
		c.JSON(http.StatusOK, result)
	}
}

// DiscoverSongListDetail 获取歌单详情
// GET /api/discover/songlist/:id?source=...

func (h *SolaraHandler) DiscoverSongListDetail(c *gin.Context) {
	if !h.isAuthed(c) {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false})
		return
	}
	source := c.DefaultQuery("source", "netease")
	limitStr := c.DefaultQuery("limit", "30")
	limit := 30
	fmt.Sscanf(limitStr, "%d", &limit)

	switch source {
	case "bilibili":
		result, err := bilibiliLeaderboardDetail(limit)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	case "jamendo":
		// Jamendo：通过电台 ID 获取对应标签的歌曲
		id := c.Param("id")
		result, err := jamendoSongListDetail(id, limit)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	case "youtube":
		// YouTube：通过分类 ID 搜索对应关键词的歌曲
		id := c.Param("id")
		result, err := youtubeSongListDetail(id, limit)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	}

	id := c.Param("id")

	apiURL := fmt.Sprintf("https://music.163.com/api/v3/playlist/detail?id=%s&n=%d", url.QueryEscape(id), limit)
	data, err := fetchNetease(apiURL)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	playlist, _ := data["playlist"].(map[string]interface{})
	if playlist == nil {
		c.JSON(http.StatusOK, []interface{}{})
		return
	}
	tracks, _ := playlist["tracks"].([]interface{})
	result := make([]map[string]interface{}, 0, len(tracks))
	for _, item := range tracks {
		t, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		artists := ""
		if ar, ok := t["ar"].([]interface{}); ok && len(ar) > 0 {
			if a, ok := ar[0].(map[string]interface{}); ok {
				artists, _ = a["name"].(string)
			}
		}
		al, _ := t["al"].(map[string]interface{})
		picId := ""
		picUrl := ""
		if al != nil {
			picUrl, _ = al["picUrl"].(string)
			picId = jsonIDToString(al["pic"])
			if picId == "0" || picId == "" {
				picId = jsonIDToString(al["id"])
			}
		}
		songID := jsonIDToString(t["id"])
		albumName := ""
		if al != nil {
			albumName, _ = al["name"].(string)
		}
		result = append(result, map[string]interface{}{
			"id":       songID,
			"name":     t["name"],
			"artist":   artists,
			"album":    albumName,
			"pic_id":   picId,
			"pic_url":  picUrl,
			"url_id":   songID,
			"lyric_id": songID,
			"source":   "netease",
		})
	}
	c.JSON(http.StatusOK, result)
}

// ─────────────────────────────────────────────────────────────────────────────
// Bilibili 音源
// ─────────────────────────────────────────────────────────────────────────────
