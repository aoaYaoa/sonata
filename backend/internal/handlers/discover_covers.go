package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// DiscoverLeaderboardCovers 按需返回某个榜单的拼图封面。
//
// GET /api/discover/leaderboard/:id/covers?source=netease
//
// 首页面世时只给前几张贴了拼图（首屏要快），剩下的卡片滚到可见范围时再逐张要。
// 这样「音乐馆里是不是每张卡都有图」不再取决于首页一次批量预热，
// 而是每张卡各自按需补齐。
func (h *SolaraHandler) DiscoverLeaderboardCovers(c *gin.Context) {
	if !h.isAuthed(c) {
		c.JSON(http.StatusUnauthorized, gin.H{"success": false})
		return
	}
	source := c.DefaultQuery("source", "netease")
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing id"})
		return
	}

	coverCacheMu.Lock()
	if e, ok := coverCache[source]; ok {
		if urls, hit := e.covers[id]; hit {
			coverCacheMu.Unlock()
			c.JSON(http.StatusOK, gin.H{"coverUrls": urls})
			return
		}
	}
	coverCacheMu.Unlock()

	urls := leaderboardTopCovers(source, id)
	if len(urls) > 0 {
		coverCacheMu.Lock()
		entry := coverCache[source]
		if entry.covers == nil {
			entry.covers = map[string][]string{}
		}
		entry.covers[id] = urls
		if entry.expiry.IsZero() {
			entry.expiry = nowPlusTTL()
		}
		coverCache[source] = entry
		coverCacheMu.Unlock()
	}
	c.JSON(http.StatusOK, gin.H{"coverUrls": urls})
}
