package handlers

import (
	"bytes"
	"io"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// 音乐馆「查看全部」只列真能播的榜单。
//
// 上游榜单列表里混着一批详情页永远是空的榜（QQ 的 MV 榜是视频榜、B 站有几个
// 分类关键词搜不到歌、Jamendo 部分 tag 没有曲目）。直接把列表铺满一屏，用户
// 每点一张卡都是一次「这个榜单暂时没有歌曲」，那等于把空态做成了常态。
//
// 判定方式：拿每个榜单的详情接口取 1 首，取得到就算有数据。这套判定和详情页
// 走的是同一条代码路径，不会出现「列表说有、点进去没有」。
//
// 代价：上游不提供「有没有歌」的字段，只能逐个探测。所以
//   - 只给「查看全部」页用（首页仍然用原始列表，首屏不能被几十次探测拖慢）；
//   - 判定结果按榜单 id 缓存 2 小时；
//   - 并发上限 20（探测只需要读到 tracks 就断开，单次约 4KB）。

// availableVerdictTTL 单个榜单「有没有数据」判定的有效期。
//
// 榜单平时不会变空，但停更/下架会。2 小时是「一天里反复进出全部榜单只探一次」
// 和「真下架了当天就会消失」之间的折中——首次探测要 6 秒左右（65 个榜挨个确认），
// TTL 太短就等于每次进来都要等这一轮。
const availableVerdictTTL = 2 * time.Hour

type availableVerdict struct {
	has    bool
	expiry time.Time
}

var (
	// source -> 榜单 id -> 判定
	availableCache   = map[string]map[string]availableVerdict{}
	availableCacheMu sync.Mutex
)

// filterAvailableLeaderboards 去掉详情页取不到歌的榜单，保持原顺序。
//
// 首次进「全部榜单」要等一轮探测（网易云 65 个榜并发探测约 6s），
// 页面上是「正在逐个确认榜单内容」。之后的请求命中缓存，1~2s 返回。
func filterAvailableLeaderboards(source string, items []map[string]interface{}) []map[string]interface{} {
	if len(items) == 0 {
		return items
	}
	ids := availableLeaderboardIDs(source, items)
	out := make([]map[string]interface{}, 0, len(items))
	for _, it := range items {
		if ids[jsonIDToString(it["id"])] {
			out = append(out, it)
		}
	}
	return out
}

// availableLeaderboardIDs 返回「有数据」的榜单 id 集合。
func availableLeaderboardIDs(source string, items []map[string]interface{}) map[string]bool {
	type probe struct {
		id string
	}
	todo := make([]probe, 0, len(items))
	out := make(map[string]bool, len(items))

	now := time.Now()
	availableCacheMu.Lock()
	byID := availableCache[source]
	if byID == nil {
		byID = map[string]availableVerdict{}
		availableCache[source] = byID
	}
	for _, it := range items {
		id := jsonIDToString(it["id"])
		if id == "" {
			continue
		}
		if v, ok := byID[id]; ok && now.Before(v.expiry) {
			if v.has {
				out[id] = true
			}
			continue
		}
		todo = append(todo, probe{id: id})
	}
	availableCacheMu.Unlock()

	if len(todo) == 0 {
		return out
	}

	// 并发探测；命中结果写回缓存，失败按「没有数据」处理并照样缓存，
	// 避免上游抽风时每来一次请求就重探一遍。
	//
	// 并发 20：网易云 65 个榜首次进「全部榜单」实测 6.5s→2.5s 左右。
	// 探测走的是不敏感的 v2 接口（v3 在 30+ 次突发后会 405），20 路仍稳定。
	sem := make(chan struct{}, 20)
	var mu sync.Mutex
	var wg sync.WaitGroup
	verdicts := make(map[string]bool, len(todo))

	for _, p := range todo {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			has := leaderboardHasSongs(source, id)
			mu.Lock()
			verdicts[id] = has
			mu.Unlock()
		}(p.id)
	}
	wg.Wait()

	expiry := time.Now().Add(availableVerdictTTL)
	availableCacheMu.Lock()
	byID = availableCache[source]
	if byID == nil {
		byID = map[string]availableVerdict{}
		availableCache[source] = byID
	}
	for id, has := range verdicts {
		byID[id] = availableVerdict{has: has, expiry: expiry}
		if has {
			out[id] = true
		}
	}
	availableCacheMu.Unlock()

	return out
}

// writeLeaderboardList 输出榜单列表。
//
// available=1 时先过滤掉详情页取不到歌的榜单——「查看全部」页用这个模式，
// 首页照旧用原始列表（不等几十次探测）。
//
// 过滤结果按榜单 id 缓存 2 小时（见 leaderboard_available.go），
// 所以第二次进「查看全部」不会再打一轮上游。
func writeLeaderboardList(c *gin.Context, source string, result []map[string]interface{}) {
	if c.Query("available") == "1" {
		filtered := filterAvailableLeaderboards(source, result)
		// 兜底：探测全失败（上游临时抽风、全被判成空）时不要输出空列表，
		// 宁可退化成不过滤——「可能点到空榜」远好过「整页没有榜单」。
		if len(filtered) > 0 {
			result = filtered
		}
	}
	c.JSON(http.StatusOK, attachLeaderboardCovers(source, result))
}

func leaderboardHasSongs(source, id string) bool {
	switch source {
	case "tencent":
		songs, err := qqLeaderboardDetail(id, 1, 0)
		return err == nil && len(songs) > 0
	case "kugou":
		songs, err := kugouLeaderboardDetail(id, 1, 0)
		return err == nil && len(songs) > 0
	case "bilibili":
		songs, err := bilibiliLeaderboardDetailByID(id, 1, 0)
		return err == nil && len(songs) > 0
	case "jamendo":
		songs, err := jamendoLeaderboardDetailByID(id, 1)
		return err == nil && len(songs) > 0
	case "youtube":
		songs, err := youtubeLeaderboardDetailByID(id, 1)
		return err == nil && len(songs) > 0
	}
	return neteasePlaylistHasTracks(id)
}

// neteasePlaylistHasTracks 判断网易云歌单（榜单）里有没有歌。
//
// 用 v2 的 playlist/detail：它把整张歌单的曲目内联在 result.tracks 里，
// 而 v3 版本在并发请求下会返回 405（实测 65 个榜并发探一轮，一半是 405），
// 拿它判空会把限流误判成「空榜」。
//
// 响应体带 100~200 首歌的完整元数据（实测 300KB 上下），只为一个布尔值不值得
// 全读：读到 `"tracks":` 后的第一个非空白字符就能收工，实测每个榜约 4KB。
func neteasePlaylistHasTracks(id string) bool {
	req, err := http.NewRequest(
		"GET",
		"https://music.163.com/api/playlist/detail?id="+url.QueryEscape(id),
		nil,
	)
	if err != nil {
		return false
	}
	for k, v := range neteaseHeaders() {
		req.Header.Set(k, v)
	}
	resp, err := neteaseHTTPClient.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	const key = `"tracks":`
	buf := make([]byte, 4096)
	acc := make([]byte, 0, 16384)
	for {
		n, err := resp.Body.Read(buf)
		if n > 0 {
			acc = append(acc, buf[:n]...)
			if idx := bytes.Index(acc, []byte(key)); idx >= 0 {
				rest := acc[idx+len(key):]
				// 跳过空白，找 '['，再看数组第一个元素是 '{'（有歌）还是 ']'（空）
				for i := 0; i < len(rest); i++ {
					switch rest[i] {
					case ' ', '\n', '\r', '\t':
						continue
					case '[':
						for _, c := range rest[i+1:] {
							switch c {
							case ' ', '\n', '\r', '\t':
								continue
							}
							return c == '{'
						}
					default:
						// 标记后面不是数组，说明命中的不是 result.tracks
						return false
					}
					break
				}
			}
			// 兜底：1MB 还没找到标记，说明响应结构变了，别一直读到超时
			if len(acc) > 1<<20 {
				return false
			}
		}
		if err != nil {
			if err == io.EOF {
				return false
			}
			return false
		}
	}
}
