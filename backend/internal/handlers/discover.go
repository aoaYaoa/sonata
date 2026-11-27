package handlers

import (
	"fmt"
	"net/http"
	"net/url"
	"strconv"

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
		writeLeaderboardList(c, source, result)
	case "youtube":
		result, err := youtubeLeaderboardList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		writeLeaderboardList(c, source, result)
	case "jamendo":
		result, err := jamendoLeaderboardList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		writeLeaderboardList(c, source, result)
	case "tencent":
		result, err := qqLeaderboardList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		writeLeaderboardList(c, source, result)
	case "kugou":
		result, err := kugouLeaderboardList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		writeLeaderboardList(c, source, result)
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
		writeLeaderboardList(c, "netease", result)
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
	limit, offset := pageParams(c, 30)

	id := c.Param("id")
	switch source {
	case "bilibili":
		result, err := bilibiliLeaderboardDetailByID(id, limit, offset)
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
	case "tencent":
		result, err := qqLeaderboardDetail(id, limit, offset)
		if err != nil {
			c.JSON(http.StatusOK, []interface{}{})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	case "kugou":
		result, err := kugouLeaderboardDetail(id, limit, offset)
		if err != nil {
			c.JSON(http.StatusOK, []interface{}{})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	}

	c.JSON(http.StatusOK, neteasePlaylistSongsPage(id, offset, limit))
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
		limit, offset := pageParams(c, 30)
		result, err := bilibiliSongList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, sliceMapPage(result, offset, limit))
	case "jamendo":
		// Jamendo：使用电台分类作为歌单
		limit, offset := pageParams(c, 30)
		result, err := jamendoSongList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, sliceMapPage(result, offset, limit))
	case "youtube":
		// YouTube：使用音乐分类关键词作为歌单
		limit, offset := pageParams(c, 30)
		c.JSON(http.StatusOK, sliceMapPage(youtubeSongList(), offset, limit))
	case "tencent":
		limit, offset := pageParams(c, 30)
		result, err := qqSongList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		// 封面拼图只补当前这一页的卡片，避免为翻页后的榜单白算一遍。
		c.JSON(http.StatusOK, attachLeaderboardCovers("tencent", sliceMapPage(result, offset, limit)))
	case "kugou":
		limit, offset := pageParams(c, 30)
		result, err := kugouSongList()
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, attachLeaderboardCovers("kugou", sliceMapPage(result, offset, limit)))
	default: // netease
		limit, offset := pageParams(c, 30)
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
		// 随列表一起把拼图封面发下去。
		// 不这么做的话，每张卡都要自己再打一次 /covers，慢的那几张会先显示
		// 中性占位（灰块），用户看到的就是「有几张卡没图」。
		c.JSON(http.StatusOK, attachLeaderboardCovers("netease", result))
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
	limit, offset := pageParams(c, 30)

	switch source {
	case "bilibili":
		result, err := bilibiliLeaderboardDetail(limit, offset)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	case "jamendo":
		// Jamendo：通过电台 ID 获取对应标签的歌曲
		id := c.Param("id")
		result, err := jamendoSongListDetail(id, limit, offset)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	case "youtube":
		// YouTube：通过分类 ID 搜索对应关键词的歌曲
		id := c.Param("id")
		result, err := youtubeSongListDetail(id, limit, offset)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	case "tencent":
		// QQ 歌单：id 是 disstid。匿名态部分歌单无权限，失败按空列表降级
		id := c.Param("id")
		result, err := qqPlaylistDetail(id, limit, offset)
		if err != nil {
			c.JSON(http.StatusOK, []interface{}{})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	case "kugou":
		// 酷狗没有匿名可用的歌单详情，列表项实际是榜单，走榜单详情
		id := c.Param("id")
		result, err := kugouLeaderboardDetail(id, limit, offset)
		if err != nil {
			c.JSON(http.StatusOK, []interface{}{})
			return
		}
		c.JSON(http.StatusOK, result)
		return
	}

	id := c.Param("id")

	c.JSON(http.StatusOK, neteasePlaylistSongsPage(id, offset, limit))
}

// ─────────────────────────────────────────────────────────────────────────────
// Bilibili 音源
// ─────────────────────────────────────────────────────────────────────────────

// pageParams 统一解析分页参数。
//
// 前端一直按 page 传（`page=2`），后端此前只读 limit、忽略 page，
// 于是「加载更多」永远返回第一页同一批歌。现在 page 与 offset 都支持，page 优先。
func pageParams(c *gin.Context, defaultLimit int) (limit, offset int) {
	limit = defaultLimit
	if v := c.Query("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			limit = n
		}
	}
	if limit > 500 {
		limit = 500
	}
	if v := c.Query("offset"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			return limit, n
		}
	}
	if v := c.Query("page"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 1 {
			offset = (n - 1) * limit
		}
	}
	return limit, offset
}

// sliceMapPage 取 [offset, offset+limit)。歌单列表这类「上游一次给全、
// 但前端按页要」的接口在 handler 层统一切片，避免每个音源各写一遍。
func sliceMapPage(
	items []map[string]interface{},
	offset, limit int,
) []map[string]interface{} {
	if offset < 0 {
		offset = 0
	}
	if offset >= len(items) {
		return []map[string]interface{}{}
	}
	end := offset + limit
	if end > len(items) {
		end = len(items)
	}
	return items[offset:end]
}
