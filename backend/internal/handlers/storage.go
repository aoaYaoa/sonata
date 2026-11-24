package handlers

import (
	"encoding/json"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"backend/internal/config"
	"backend/internal/models"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm/clause"
)

func (h *SolaraHandler) Storage(c *gin.Context) {
	if !h.isAuthed(c) {
		c.Redirect(http.StatusFound, "/")
		return
	}
	// 数据库不可用时（启动降级路径）h.db 为 nil，直接操作会 panic
	if h.db == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "存储后端不可用",
		})
		return
	}

	switch c.Request.Method {
	case http.MethodGet:
		h.storageGet(c)
	case http.MethodPost:
		h.storagePost(c)
	case http.MethodDelete:
		h.storageDelete(c)
	default:
		c.Status(http.StatusMethodNotAllowed)
	}
}

func (h *SolaraHandler) storageGet(c *gin.Context) {
	if c.Query("status") == "1" {
		c.JSON(http.StatusOK, gin.H{"d1Available": true})
		return
	}

	keysParam := c.Query("keys")
	if keysParam != "" {
		keys := strings.Split(keysParam, ",")
		result := make(map[string]interface{}, len(keys))
		for _, k := range keys {
			k = strings.TrimSpace(k)
			var val *string
			if favoriteKeys[k] {
				var row models.FavoritesStore
				if err := h.db.First(&row, "key = ?", k).Error; err == nil {
					v := row.Value
					val = &v
				}
			} else {
				var row models.PlaybackStore
				if err := h.db.First(&row, "key = ?", k).Error; err == nil {
					v := row.Value
					val = &v
				}
			}
			if val != nil {
				result[k] = *val
			} else {
				result[k] = nil
			}
		}
		c.JSON(http.StatusOK, gin.H{"d1Available": true, "data": result})
		return
	}

	// 不带 keys 参数时曾有“返回全表”的行为，会把其他用户的播放队列
	// 一并吐给任意调用者。这里改为只返回当前客户端已知的键集合，
	// 需要全量导出的运维场景通过 ALLOW_STORAGE_DUMP=true 显式开启。
	if !config.AppConfig.AllowStorageDump {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "must specify ?keys=...; full export is disabled",
		})
		return
	}

	result := make(map[string]string)
	var playback []models.PlaybackStore
	h.db.Find(&playback)
	for _, r := range playback {
		result[r.Key] = r.Value
	}
	var favorites []models.FavoritesStore
	h.db.Find(&favorites)
	for _, r := range favorites {
		result[r.Key] = r.Value
	}
	c.JSON(http.StatusOK, gin.H{"d1Available": true, "data": result})
}

func (h *SolaraHandler) storagePost(c *gin.Context) {
	var body struct {
		Data map[string]interface{} `json:"data"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.Data == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if len(body.Data) > maxStorageKeys {
		c.JSON(http.StatusBadRequest, gin.H{"error": "too many keys in one request"})
		return
	}

	for k, rawVal := range body.Data {
		if !validStorageKey(k) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid key: " + truncateForLog(k)})
			return
		}
		var v string
		switch val := rawVal.(type) {
		case string:
			v = val
		default:
			b, err := json.Marshal(val)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid value for key " + truncateForLog(k)})
				return
			}
			v = string(b)
		}
		if len(v) > maxStorageValueLen {
			c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "value too large for key " + truncateForLog(k)})
			return
		}
		if favoriteKeys[k] {
			h.db.Clauses(clause.OnConflict{UpdateAll: true}).Create(&models.FavoritesStore{Key: k, Value: v, UpdatedAt: time.Now()})
		} else {
			h.db.Clauses(clause.OnConflict{UpdateAll: true}).Create(&models.PlaybackStore{Key: k, Value: v, UpdatedAt: time.Now()})
		}
	}
	c.JSON(http.StatusOK, gin.H{"d1Available": true, "success": true})
}

func (h *SolaraHandler) storageDelete(c *gin.Context) {
	var body struct {
		Keys []string `json:"keys"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || len(body.Keys) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if len(body.Keys) > maxStorageKeys {
		c.JSON(http.StatusBadRequest, gin.H{"error": "too many keys in one request"})
		return
	}
	for _, k := range body.Keys {
		if !validStorageKey(k) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid key: " + truncateForLog(k)})
			return
		}
		if favoriteKeys[k] {
			h.db.Delete(&models.FavoritesStore{}, "key = ?", k)
		} else {
			h.db.Delete(&models.PlaybackStore{}, "key = ?", k)
		}
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

var storageKeyPattern = regexp.MustCompile(`^[A-Za-z0-9_.:$-]{1,64}$`)

// knownStorageKeys 前端实际使用的键集合。
//
// 历史实现无任何键校验，任何持有口令的人都能把服务端当免费对象存储用
// （实测写入 arbitrary_attacker_key_12345 成功）。这里改为显式白名单：
// 前端新增键时同步补充，或通过 STORAGE_EXTRA_KEYS 环境变量扩展，避免漏改。

var knownStorageKeys = map[string]struct{}{
	"solara_state":         {},
	"favoriteSongs":        {},
	"favoritesUpdatedAt":   {},
	"currentFavoriteIndex": {},
	"favoritePlayMode":     {},
	"favoritePlaybackTime": {},
	"playlistSongs":        {},
	"queueCurrentIndex":    {},
	"queuePlayMode":        {},
	"queueUpdatedAt":       {},
	"settings":             {},
	"settingsUpdatedAt":    {},
	"localSongs":           {},
	"localSongsUpdatedAt":  {},
	"userPlaylists":        {},
	"listenHistory":        {},
	"searchHistory":        {},
	"lastPlaybackPosition": {},
	"lastPlaybackDuration": {},
}

// extraStorageKeysCache 缓存 STORAGE_EXTRA_KEYS 解析结果。
// 用 sync.Once 惰性初始化：包级 var 在 init 阶段读取 config.AppConfig
// 会因 config.Init() 尚未执行而解引用 nil（单元测试下必现）。

var (
	extraStorageKeysOnce  sync.Once
	extraStorageKeysCache map[string]struct{}
)

func extraStorageKeys() map[string]struct{} {
	extraStorageKeysOnce.Do(func() {
		extraStorageKeysCache = make(map[string]struct{})
		if config.AppConfig == nil {
			return
		}
		for _, k := range config.AppConfig.StorageExtraKeys {
			if k = strings.TrimSpace(k); k != "" {
				extraStorageKeysCache[k] = struct{}{}
			}
		}
	})
	return extraStorageKeysCache
}

// validStorageKey 校验键：字符集合法且属于已知键集合。

func validStorageKey(k string) bool {
	if !storageKeyPattern.MatchString(k) {
		return false
	}
	if _, ok := knownStorageKeys[k]; ok {
		return true
	}
	_, ok := extraStorageKeys()[k]
	return ok
}

// truncateForLog 截断日志中的 URL，避免超长输入污染日志。

func truncateForLog(v string) string {
	if len(v) > 200 {
		return v[:200] + "..."
	}
	return v
}

// writeJSON 写入 JSON 响应，禁用 HTML 转义（避免 & 被转义为 \u0026 导致 URL 损坏）
