package handlers

import (
	"net/url"
	"strings"
	"sync"
	"time"
)

// 首页音乐馆的封面拼图。
//
// 各家榜单自带的封面是「榜单品牌图」——纯色底上印着榜名文字（网易云的飙升榜
// 就是紫底白字）。铺到卡片上，用户看到的仍然是一堆文字，不像图片。这里改成
// 取榜单前 4 首歌的专辑封面拼成 2x2，和 QQ 音乐 / Apple Music 的做法一致。
//
// 只为首页要展示的前几张卡补图：网易云有 65 个榜单，每个都要多打一次上游，
// 全量补图会让首页首屏多等好几秒，而用户看不到的那些卡片并不值得这个代价。

const (
	// 首页音乐馆是 2 列，12 张正好是 6 行、覆盖 iPhone 首屏加一次轻滑；
	// 发现页是 3 列，12 张是 4 行。再往后由前端逐张按需补。
	coverCollageCards = 12
	coverCollageTiles = 4 // 每张卡片的拼图块数
)

// coverCacheTTL 拼图缓存的有效期。
const coverCacheTTL = 10 * time.Minute

func nowPlusTTL() time.Time { return time.Now().Add(coverCacheTTL) }

type coverCacheEntry struct {
	covers map[string][]string
	expiry time.Time
}

var (
	coverCache   = map[string]coverCacheEntry{}
	coverCacheMu sync.Mutex
)

// attachLeaderboardCovers 给首页要展示的榜单补 coverUrls 字段。
// 补不到就保持原样，前端回退到榜单品牌图。
func attachLeaderboardCovers(source string, items []map[string]interface{}) []map[string]interface{} {
	if len(items) == 0 {
		return items
	}
	covers := leaderboardCovers(source, items)
	for i, it := range items {
		if i >= coverCollageCards {
			break
		}
		id := jsonIDToString(it["id"])
		if urls := covers[id]; len(urls) > 0 {
			it["coverUrls"] = urls
		}
	}
	return items
}

func leaderboardCovers(source string, items []map[string]interface{}) map[string][]string {
	n := len(items)
	if n > coverCollageCards {
		n = coverCollageCards
	}

	// 先看缓存里已经有哪些，只补缺的。
	// 缓存按 source 存一份、多个列表共用（音乐馆和发现页都会调这里），
	// 早先的实现是「算完整体替换」，两个列表交替刷新时会互相把对方刚算好的
	// 封面冲掉，表现出来的现象就是「卡片一会儿有图一会儿又变回文字图」。
	out := make(map[string][]string, n)
	pending := make([]string, 0, n)
	coverCacheMu.Lock()
	entry := coverCache[source]
	fresh := time.Now().Before(entry.expiry) && entry.covers != nil
	if fresh {
		for k, v := range entry.covers {
			out[k] = v
		}
	} else {
		entry = coverCacheEntry{covers: map[string][]string{}}
	}
	coverCacheMu.Unlock()

	seen := map[string]bool{}
	for i := 0; i < n; i++ {
		id := jsonIDToString(items[i]["id"])
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		if fresh && len(out[id]) > 0 {
			continue
		}
		pending = append(pending, id)
	}
	if len(pending) == 0 {
		return out
	}

	// 并发上限 6：再多容易触发上游风控，收益也不大。
	sem := make(chan struct{}, 6)
	var mu sync.Mutex
	var wg sync.WaitGroup
	for _, id := range pending {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if urls := leaderboardTopCovers(source, id); len(urls) > 0 {
				mu.Lock()
				out[id] = urls
				mu.Unlock()
			}
		}(id)
	}
	wg.Wait()

	coverCacheMu.Lock()
	entry = coverCache[source]
	if entry.covers == nil {
		entry.covers = map[string][]string{}
	}
	for id, urls := range out {
		entry.covers[id] = urls
	}
	entry.expiry = nowPlusTTL()
	coverCache[source] = entry
	coverCacheMu.Unlock()
	return out
}

// leaderboardTopCovers 取某个榜单前几首歌的专辑封面。
func leaderboardTopCovers(source, id string) []string {
	switch source {
	case "netease":
		data, err := fetchNetease("https://music.163.com/api/playlist/detail?id=" + url.QueryEscape(id))
		if err != nil {
			return nil
		}
		inner, _ := data["result"].(map[string]interface{})
		if inner == nil {
			return nil
		}
		tracks, _ := inner["tracks"].([]interface{})
		return collectCovers(tracks, func(m map[string]interface{}) string {
			album, _ := m["album"].(map[string]interface{})
			if album == nil {
				return ""
			}
			s, _ := album["picUrl"].(string)
			return strings.Replace(s, "http://", "https://", 1)
		})
	case "tencent":
		songs, err := qqLeaderboardDetail(id, coverCollageTiles, 0)
		if err != nil {
			return nil
		}
		return songCovers(songs)
	case "kugou":
		songs, err := kugouLeaderboardDetail(id, coverCollageTiles, 0)
		if err != nil {
			return nil
		}
		return songCovers(songs)
	}
	// bilibili / youtube / jamendo 的榜单封面本身就是真图（视频封面、缩略图、
	// 专辑图），不需要拼图。
	return nil
}

func songCovers(songs []map[string]interface{}) []string {
	if len(songs) == 0 {
		return nil
	}
	out := make([]string, 0, coverCollageTiles)
	seen := map[string]bool{}
	for _, m := range songs {
		if len(out) >= coverCollageTiles {
			break
		}
		s, _ := m["pic_url"].(string)
		if s == "" {
			s, _ = m["coverUrl"].(string)
		}
		s = strings.Replace(s, "http://", "https://", 1)
		if s == "" || seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, s)
	}
	return out
}

func collectCovers(items []interface{}, pick func(map[string]interface{}) string) []string {
	if len(items) == 0 {
		return nil
	}
	out := make([]string, 0, coverCollageTiles)
	seen := map[string]bool{}
	for _, it := range items {
		if len(out) >= coverCollageTiles {
			break
		}
		m, ok := it.(map[string]interface{})
		if !ok {
			continue
		}
		u := pick(m)
		if u == "" || seen[u] {
			continue
		}
		seen[u] = true
		out = append(out, u)
	}
	return out
}
