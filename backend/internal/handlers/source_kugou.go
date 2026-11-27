package handlers

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// 酷狗音乐音源。
//
// 链路（均为移动端 Web 接口，不校验 Referer）：
//   - 搜索：mobiles.kugou.com/api/v3/search/song
//   - 档位反查：mobiles.kugou.com/api/v3/song/info（按 128hash 拿 320/sq hash）
//   - 取流：trackercdn.kugou.com/i/?cmd=4（按 hash 出对应码率），兜底 m.kugou.com/app/i/getSongInfo.php
//   - 歌词：krcs.kugou.com/search 取 candidate，再 lyrics.kugou.com/download 取 base64
//   - 榜单：mobiles.kugou.com/api/v3/rank/list 与 /rank/song
//
// 两条硬结论（都是实测推翻文档/直觉的）：
//  1. 可播判定看 privilege 而不是 pay_type：0/8 都能拿到流，只有 10 才是真的没有。
//  2. 音质切换必须换 hash，br 参数对 trackercdn v1 完全无效 ——
//     同一条 hash 上 br=128/320/flac/sqx 返回的都是同一个 128000 文件。
//     每首歌在 128hash 之外还有独立的 320hash / sqhash（权限位也各自独立）。

// kugouHeaders 是酷狗移动端接口要求的请求头组合。
// 缺 UA 时 mobiles 接口会返回空 data，所以必须带。
func kugouHeaders() map[string]string {
	return map[string]string{
		"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
		"Referer":    "https://m.kugou.com/",
	}
}

func fetchKugou(apiURL string) (map[string]interface{}, error) {
	req, err := http.NewRequest(http.MethodGet, apiURL, nil)
	if err != nil {
		return nil, err
	}
	for k, v := range kugouHeaders() {
		req.Header.Set(k, v)
	}
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("kugou api status %d", resp.StatusCode)
	}
	var result map[string]interface{}
	dec := json.NewDecoder(resp.Body)
	dec.UseNumber()
	if err := dec.Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}

// kugouCoverFromTemplate 把 {size} 占位替换成实际尺寸。
// imge.kugou.com 的模板形如 http://imge.kugou.com/stdmusic/{size}/2026.../xxx.jpg
func kugouCoverFromTemplate(tpl string, size int) string {
	if tpl == "" {
		return ""
	}
	out := strings.ReplaceAll(tpl, "{size}", fmt.Sprintf("%d", size))
	return strings.Replace(out, "http://", "https://", 1)
}

// kugouSingerName 从 authors 数组或 singername 字段取歌手名
func kugouSingerName(m map[string]interface{}) string {
	if name, ok := m["singername"].(string); ok && name != "" {
		return name
	}
	authors, ok := m["authors"].([]interface{})
	if !ok {
		return ""
	}
	names := make([]string, 0, len(authors))
	for _, a := range authors {
		am, ok := a.(map[string]interface{})
		if !ok {
			continue
		}
		if name, ok := am["author_name"].(string); ok && name != "" {
			names = append(names, name)
		}
	}
	return strings.Join(names, "/")
}

// kugouCoverOf 依次从 trans_param.union_cover、album_sizable_cover 取封面模板
func kugouCoverOf(m map[string]interface{}, size int) string {
	if tp, ok := m["trans_param"].(map[string]interface{}); ok {
		if cover, ok := tp["union_cover"].(string); ok && cover != "" {
			return kugouCoverFromTemplate(cover, size)
		}
	}
	if cover, ok := m["album_sizable_cover"].(string); ok && cover != "" {
		return kugouCoverFromTemplate(cover, size)
	}
	return ""
}

// kugouSongFromItem 把搜索结果或榜单里的一条记录统一成内部 song 结构。
//
// id 存 128k 的 hash（酷狗的曲目主键）。alt_ids 里带各档位的独立 hash：
// 换音质靠换 hash，所以前端必须把选中的 hash 传回来，而不是只传 br。
// 只登记「有 hash 且权限位允许」的档位，前端据此决定菜单里哪些档能点。
func kugouSongFromItem(m map[string]interface{}) map[string]interface{} {
	hash, _ := m["hash"].(string)
	if hash == "" {
		return nil
	}
	name, _ := m["songname"].(string)
	album, _ := m["album_name"].(string)
	albumID := jsonIDToString(m["album_id"])

	hash320, _ := m["320hash"].(string)
	hashSQ, _ := m["sqhash"].(string)

	// privilege>=10 表示取不到流；0/8 都能播
	priv := jsonNumberToInt64(m["privilege"])
	// 320/sq 各有独立权限位；榜单接口不带这些字段时按主 privilege 推断
	priv320 := kugouPrivilegeOf(m, "320privilege", priv)
	privSQ := kugouPrivilegeOf(m, "sqprivilege", priv)

	alt := map[string]interface{}{}
	// 整曲都不可播时不要登记任何档位：前端据此把菜单收成只剩「自动」，
	// 而不是给用户一个点了必然 404 的档位。
	if priv < 10 {
		alt["128"] = hash
	}
	if hash320 != "" && priv320 < 10 {
		alt["320"] = hash320
	}
	if hashSQ != "" && privSQ < 10 {
		alt["flac"] = hashSQ
	}

	return map[string]interface{}{
		"id":       hash,
		"name":     name,
		"artist":   kugouSingerName(m),
		"album":    album,
		"pic_id":   albumID,
		"pic_url":  kugouCoverOf(m, 240),
		"url_id":   hash,
		"mv_id":    "",
		"lyric_id": hash,
		"source":   "kugou",
		"need_vip": priv >= 10,
		// 各档位 hash，键名与前端音质标识一致
		"alt_ids": alt,
	}
}

// kugouPrivilegeOf 读档位权限位，字段缺失时用主 privilege 兜底。
func kugouPrivilegeOf(m map[string]interface{}, key string, fallback int64) int64 {
	if v, ok := m[key]; ok && v != nil {
		return jsonNumberToInt64(v)
	}
	return fallback
}

// kugouSearch 搜索歌曲。
// 注意 status 字段：1 为成功；errcode!=0 时应视为上游失败而不是「无结果」。
func kugouSearch(keyword string, page, count int) ([]map[string]interface{}, error) {
	if page < 1 {
		page = 1
	}
	if count <= 0 || count > 50 {
		count = 20
	}
	apiURL := fmt.Sprintf(
		"https://mobiles.kugou.com/api/v3/search/song?format=json&keyword=%s&page=%d&pagesize=%d&showtype=1",
		url.QueryEscape(keyword), page, count,
	)
	data, err := fetchKugou(apiURL)
	if err != nil {
		return nil, err
	}
	if status := jsonNumberToInt64(data["status"]); status != 1 {
		return nil, fmt.Errorf("kugou search status=%d", status)
	}
	inner, _ := data["data"].(map[string]interface{})
	info, _ := inner["info"].([]interface{})

	result := make([]map[string]interface{}, 0, len(info))
	for _, item := range info {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		if song := kugouSongFromItem(m); song != nil {
			result = append(result, song)
		}
	}
	return result, nil
}

// kugouCacheEntry 缓存取到的播放地址。
// CDN 地址带时间戳路径、通常数小时内有效，取 20 分钟做安全边界。
type kugouCacheEntry struct {
	info   streamInfo
	expiry time.Time
}

var (
	kugouCacheMu sync.Mutex
	kugouCache   = map[string]kugouCacheEntry{}
)

const kugouCacheTTL = 20 * time.Minute

// kugouAltHashes 按 128hash 反查 320/sq hash。
//
// 用途是补齐历史数据：队列/收藏里存的是老版本写入的 song，没有 alt_ids 字段，
// 换音质时只能靠这里反查。song/info 返回的 extra 里三档 hash 与权限位齐全。
func kugouAltHashes(hash string) map[string]string {
	apiURL := fmt.Sprintf("https://mobiles.kugou.com/api/v3/song/info?hash=%s&format=json", url.QueryEscape(hash))
	data, err := fetchKugou(apiURL)
	if err != nil {
		return nil
	}
	if status := jsonNumberToInt64(data["status"]); status != 1 {
		return nil
	}
	inner, _ := data["data"].(map[string]interface{})
	extra, _ := inner["extra"].(map[string]interface{})
	if extra == nil {
		return nil
	}
	out := map[string]string{}
	priv128 := jsonNumberToInt64(extra["128privilege"])
	priv320 := jsonNumberToInt64(extra["320privilege"])
	privSQ := jsonNumberToInt64(extra["sqprivilege"])
	if v := strings.ToLower(jsonIDToString(extra["128hash"])); v != "" && priv128 < 10 {
		out["128"] = v
	}
	if v := strings.ToLower(jsonIDToString(extra["320hash"])); v != "" && priv320 < 10 {
		out["320"] = v
	}
	if v := strings.ToLower(jsonIDToString(extra["sqhash"])); v != "" && privSQ < 10 {
		out["flac"] = v
	}
	return out
}

// kugouTrackURL 向 trackercdn v1 要一条指定 hash 的直链。
//
// 这是唯一真正按 hash 分档的接口：同一个 br 参数在 v1 上被忽略，
// 换 hash 才会换码率。key = md5(hash + "kgcloud")，hash 大小写不敏感但 key 必须与
// 传入的 hash 原文一致（用大写 hash 配小写 key 会回 "Bad key"）。
//
// hint 是本次请求的目标档位，仅在回执字段不可用时用于判定：
//   - 320 档实测 bitRate 为 0（字段缺失），size 却是 6.2MB 的 320k 文件；
//   - flac 档 bitRate 回 411000（不是采样率也不是码率），但 ext 明确是 flac。
//
// 只用 bitRate 判档会把 320 说成 128、把 flac 说成 320，用户看到的音质标签就是错的。
func kugouTrackURL(hash string, hint audioQuality) (streamInfo, bool) {
	key := kgHashKey(hash, "kgcloud")
	apiURL := fmt.Sprintf(
		"https://trackercdn.kugou.com/i/?cmd=4&pid=1&forceDown=0&vip=1&hash=%s&key=%s",
		url.QueryEscape(hash), key,
	)
	data, err := fetchKugou(apiURL)
	if err != nil {
		return streamInfo{}, false
	}
	if status := jsonNumberToInt64(data["status"]); status != 1 {
		return streamInfo{}, false
	}
	rawURL, _ := data["url"].(string)
	if rawURL == "" {
		return streamInfo{}, false
	}
	bitrate := int(jsonNumberToInt64(data["bitRate"]))
	ext, _ := data["extName"].(string)
	size := jsonNumberToInt64(data["fileSize"])
	return streamInfo{
		URL:      rawURL,
		Quality:  qualityOfStream(ext, bitrate, hint),
		Bitrate:  bitrate,
		Ext:      ext,
		Size:     size,
		Upstream: "trackercdn-v1",
	}, true
}

// qualityOfStream 综合 ext / 码率 / 请求档位判定实际音质。
// 优先级：无损扩展名 > 码率阈值 > 请求档位 > 128 兜底。
func qualityOfStream(ext string, bitrate int, hint audioQuality) audioQuality {
	if strings.EqualFold(ext, "flac") || strings.EqualFold(ext, "ape") ||
		strings.EqualFold(ext, "wav") {
		return qualityFlac
	}
	switch {
	case bitrate >= 500000:
		return qualityFlac
	case bitrate >= 250000:
		return quality320
	case bitrate > 0:
		return quality128
	}
	// 码率字段缺失：信请求档位，但把「未确证的 flac」降一级，
	// 免得 mp3 文件因为请求的是 flac 就被标成无损。
	if hint == quality320 {
		return quality320
	}
	return quality128
}

// kugouSongInfoURL 兜底链路：getSongInfo 固定返回该曲目的 128k 档，
// 但它走的是 sharefs.kugou.com（有 HTTPS），在 trackercdn 抽风时更稳。
func kugouSongInfoURL(hash string) (streamInfo, bool) {
	apiURL := fmt.Sprintf("https://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash=%s", url.QueryEscape(hash))
	data, err := fetchKugou(apiURL)
	if err != nil {
		return streamInfo{}, false
	}
	rawURL, _ := data["url"].(string)
	if rawURL == "" {
		return streamInfo{}, false
	}
	ext, _ := data["extName"].(string)
	bitrate := int(jsonNumberToInt64(data["bitRate"])) * 1000
	size := jsonNumberToInt64(data["fileSize"])
	return streamInfo{
		URL:      strings.Replace(rawURL, "http://", "https://", 1),
		Quality:  qualityOfBitrate(bitrate),
		Bitrate:  bitrate,
		Ext:      ext,
		Size:     size,
		Upstream: "getSongInfo",
	}, true
}

// qualityOfBitrate 把码率归到统一档位。酷狗无损实测 694000（v0 FLAC）。
func qualityOfBitrate(bitrate int) audioQuality {
	switch {
	case bitrate >= 500000:
		return qualityFlac
	case bitrate >= 250000:
		return quality320
	default:
		return quality128
	}
}

// kugouStream 取指定档位的播放地址。
//
// 参数：主 hash（曲目主键）、前端指定的档位 hash（可为空）、目标档位。
// 顺序：目标 hash → 按需反查 alt 表 → 目标 hash 直取 → 主 hash 兜底。
// 最后一步的意义：320 档没版权时仍能听 128 档，比整体报「需会员」有用。
func kugouStream(mainHash, altHash string, q audioQuality) (streamInfo, error) {
	mainHash = strings.TrimSpace(mainHash)
	if mainHash == "" {
		return streamInfo{}, errInvalidVideoID
	}

	cacheKey := mainHash + ":" + altHash + ":" + q.String()
	kugouCacheMu.Lock()
	if entry, ok := kugouCache[cacheKey]; ok && time.Now().Before(entry.expiry) {
		kugouCacheMu.Unlock()
		return entry.info, nil
	}
	kugouCacheMu.Unlock()

	target := strings.TrimSpace(altHash)
	if target == "" && q != quality128 {
		// 没有指定档位 hash 时按 128hash 反查三档，再按目标档位挑。
		// 酷狗的音质完全由 hash 决定，反查是唯一能让 320/flac 真正生效的路径。
		alt := kugouAltHashes(mainHash)
		if alt != nil {
			for _, tier := range kugouTierOrder(q) {
				if alt[tier] != "" {
					target = alt[tier]
					break
				}
			}
		}
	}
	if target == "" {
		target = mainHash
	}

	info, ok := kugouTrackURL(target, q)
	if !ok && target != mainHash {
		// 目标档位拿不到（多为版权/权限），退回主 hash 的 128 档
		info, ok = kugouTrackURL(mainHash, quality128)
		if ok {
			info.Upstream += "+fallback128"
		}
	}
	if !ok {
		info, ok = kugouSongInfoURL(target)
	}
	if !ok && target != mainHash {
		info, ok = kugouSongInfoURL(mainHash)
		if ok {
			info.Upstream += "+fallback128"
		}
	}
	if !ok {
		// privilege>=10 或无版权：上游返回空 url，http status 仍是 200
		return streamInfo{}, errNeedVip
	}

	kugouCacheMu.Lock()
	kugouCache[cacheKey] = kugouCacheEntry{info: info, expiry: time.Now().Add(kugouCacheTTL)}
	kugouCacheMu.Unlock()

	return info, nil
}

// kugouTierOrder 给出目标档位对应的尝试顺序（含降级）。
// 顺序按「用户愿意接受的损失」排：要无损就先试无损，拿不到退 320，再退 128。
func kugouTierOrder(q audioQuality) []string {
	switch q {
	case qualityFlac:
		return []string{"flac", "320", "128"}
	case quality320:
		return []string{"320", "128"}
	case qualityAuto:
		return []string{"flac", "320", "128"}
	default:
		return []string{"128"}
	}
}

// kugouLyric 两段式取歌词：
// 先用 hash 查 candidate（拿到 id + accesskey），再用它下载 base64 编码的 LRC。
func kugouLyric(hash string) (string, error) {
	searchURL := fmt.Sprintf(
		"https://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration=&hash=%s&album_audio_id=0",
		url.QueryEscape(hash),
	)
	data, err := fetchKugou(searchURL)
	if err != nil {
		return "", err
	}
	candidates, _ := data["candidates"].([]interface{})
	if len(candidates) == 0 {
		return "", nil // 无歌词不算错误
	}
	first, _ := candidates[0].(map[string]interface{})
	id, _ := first["id"].(string)
	accessKey, _ := first["accesskey"].(string)
	if id == "" || accessKey == "" {
		return "", nil
	}

	downloadURL := fmt.Sprintf(
		"https://lyrics.kugou.com/download?charset=utf8&accesskey=%s&id=%s&client=mobi&fmt=lrc&ver=1",
		url.QueryEscape(accessKey), url.QueryEscape(id),
	)
	lyricData, err := fetchKugou(downloadURL)
	if err != nil {
		return "", err
	}
	content, _ := lyricData["content"].(string)
	if content == "" {
		return "", nil
	}
	decoded, err := base64.StdEncoding.DecodeString(content)
	if err != nil {
		return "", nil
	}
	// 部分歌词带 UTF-8 BOM，解析器会把它当成第一行的字符
	return strings.TrimPrefix(string(decoded), "\ufeff"), nil
}

// kugouLeaderboardList 榜单列表。parentid=0 拿一级榜单。
func kugouLeaderboardList() ([]map[string]interface{}, error) {
	apiURL := "https://mobiles.kugou.com/api/v3/rank/list?parentid=0&page=1&pagesize=20&withsong=1&format=json"
	data, err := fetchKugou(apiURL)
	if err != nil {
		return nil, err
	}
	inner, _ := data["data"].(map[string]interface{})
	info, _ := inner["info"].([]interface{})

	result := make([]map[string]interface{}, 0, len(info))
	for _, item := range info {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		rankID := jsonIDToString(m["rankid"])
		if rankID == "" || rankID == "0" {
			continue
		}
		name, _ := m["rankname"].(string)
		cover := ""
		// 榜单封面同样是 {size} 模板
		if img, ok := m["img_9"].(string); ok {
			cover = kugouCoverFromTemplate(img, 240)
		}
		if cover == "" {
			if img, ok := m["album_img_9"].(string); ok {
				cover = kugouCoverFromTemplate(img, 240)
			}
		}
		result = append(result, map[string]interface{}{
			"id":              rankID,
			"name":            name,
			"coverUrl":        cover,
			"updateFrequency": "酷狗榜单",
			"source":          "kugou",
		})
	}
	return result, nil
}

// kugouLeaderboardDetail 榜单详情。ranktype=2 是「歌曲榜」的固定取值。
//
// 上游支持 page/pagesize，offset 换算成页码传给上游；
// 原来 page 写死 1，「加载更多」只会重复拿第一批。
func kugouLeaderboardDetail(
	rankID string,
	limit int,
	offset int,
) ([]map[string]interface{}, error) {
	if rankID == "" {
		rankID = "8888" // TOP500
	}
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	if offset < 0 {
		offset = 0
	}
	page := offset/limit + 1
	apiURL := fmt.Sprintf(
		"https://mobiles.kugou.com/api/v3/rank/song?rankid=%s&page=%d&pagesize=%d&ranktype=2&format=json",
		url.QueryEscape(rankID), page, limit,
	)
	data, err := fetchKugou(apiURL)
	if err != nil {
		return nil, err
	}
	inner, _ := data["data"].(map[string]interface{})
	info, _ := inner["info"].([]interface{})

	result := make([]map[string]interface{}, 0, len(info))
	for _, item := range info {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		if song := kugouSongFromItem(m); song != nil {
			result = append(result, song)
		}
	}
	return result, nil
}

// kugouSongList 歌单列表：用榜单代替。
// 酷狗的公开歌单列表需要登录态，榜单是同一语义下可匿名访问的集合。
func kugouSongList() ([]map[string]interface{}, error) {
	boards, err := kugouLeaderboardList()
	if err != nil {
		return nil, err
	}
	for _, b := range boards {
		b["author"] = "酷狗音乐"
		b["playCount"] = ""
		b["description"] = b["updateFrequency"]
	}
	return boards, nil
}

// kugouMediaProxyReferer 供媒体代理使用。
// sharefs.kugou.com 有 HTTPS 且不校验来源；trackercdn v1 给出的
// fsvippc.tx.kugou.com 只有 HTTP（443 端口开着但 TLS 握手失败），
// 所以这条域名必须走后端代理，前端不能直接播。
func kugouMediaProxyReferer(host string) (string, bool) {
	switch {
	case strings.HasSuffix(host, ".kugou.com"), host == "kugou.com":
		return "https://www.kugou.com/", true
	}
	return "", false
}
