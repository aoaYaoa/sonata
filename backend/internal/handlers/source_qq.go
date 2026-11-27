package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

// QQ 音乐音源。
//
// 两条链路都是官方 Web 端在用的接口，不需要登录态：
//   - 搜索：c.y.qq.com/soso/fcgi-bin/client_search_cp（旧版 CGI，字段稳定）
//   - 取流：u.y.qq.com/cgi-bin/musicu.fcg 的 vkey.GetVkeyServer/CgiGetVkey
//
// 匿名态的能力上限是 128k（m4a），拿到 purl 即代表可播：
// 完全没有 purl 的曲目一律映射成 errNeedVip，让前端显式提示，
// 而不是返回一个空 URL 让播放器静默失败。

// qqHeaders 是 QQ 音乐 Web 接口要求的请求头。
// 歌词接口缺 Referer 会直接返回 code=-1310，所以统一带上。
func qqHeaders() map[string]string {
	return map[string]string{
		"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
		"Referer":    "https://y.qq.com/",
	}
}

// errNeedVip 表示上游确认该曲目需要会员/无版权/地区受限。
var errNeedVip = fmt.Errorf("该曲目需要会员或当前地区不可播放")

func qqClient() *http.Client {
	return &http.Client{Timeout: 15 * time.Second}
}

func fetchQQJSON(apiURL string) (map[string]interface{}, error) {
	req, err := http.NewRequest(http.MethodGet, apiURL, nil)
	if err != nil {
		return nil, err
	}
	for k, v := range qqHeaders() {
		req.Header.Set(k, v)
	}
	resp, err := qqClient().Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("qq api status %d", resp.StatusCode)
	}
	var result map[string]interface{}
	dec := json.NewDecoder(resp.Body)
	dec.UseNumber()
	if err := dec.Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}

// fetchQQMusicu 向 musicu.fcg 发 POST JSON。
// 该端点不接受 application/x-www-form-urlencoded 形式的 data=，必须 raw JSON。
func fetchQQMusicu(payload map[string]interface{}) (map[string]interface{}, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest(http.MethodPost, "https://u.y.qq.com/cgi-bin/musicu.fcg", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	for k, v := range qqHeaders() {
		req.Header.Set(k, v)
	}
	resp, err := qqClient().Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("qq musicu status %d", resp.StatusCode)
	}
	var result map[string]interface{}
	dec := json.NewDecoder(resp.Body)
	dec.UseNumber()
	if err := dec.Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}

// qqSingerName 把 singer 数组拼成「A/B」形式
func qqSingerName(v interface{}) string {
	arr, ok := v.([]interface{})
	if !ok {
		return ""
	}
	names := make([]string, 0, len(arr))
	for _, item := range arr {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		if name, ok := m["name"].(string); ok && name != "" {
			names = append(names, name)
		}
	}
	return strings.Join(names, "/")
}

// qqCoverURL 用 albummid 拼封面地址。y.gtimg.cn 是官方图床，无防盗链。
func qqCoverURL(albumMid string, size int) string {
	if albumMid == "" {
		return ""
	}
	return fmt.Sprintf("https://y.gtimg.cn/music/photo_new/T002R%dx%dM000%s.jpg", size, size, albumMid)
}

// qqSongFromSearchItem 把搜索结果里的一条歌曲记录统一成内部 song 结构。
//
// media_mid 必须带出来：取流时 filename 的中段是 media_mid 而不是 songmid，
// 用 songmid 会拿到 result=101404「曲目不存在」。
//
// alt_ids 只登记匿名态真能拿到的档位。QQ 的 320/flac 需要登录态，
// 搜索结果里的 size320/sizeflac 只代表「服务端存在这个文件」，不代表我们有权限，
// 所以只在 payplay=0 时登记 128 档 —— 宁可菜单里少一档，也不要让用户点了拿到 404。
func qqSongFromSearchItem(m map[string]interface{}) map[string]interface{} {
	songMid, _ := m["songmid"].(string)
	if songMid == "" {
		return nil
	}
	name, _ := m["songname"].(string)
	album, _ := m["albumname"].(string)
	albumMid, _ := m["albummid"].(string)
	mediaMid, _ := m["media_mid"].(string)
	if mediaMid == "" {
		mediaMid, _ = m["strMediaMid"].(string)
	}
	if mediaMid == "" {
		mediaMid = songMid
	}

	// pay.payplay == 1 表示需要会员
	payplay := 0
	if pay, ok := m["pay"].(map[string]interface{}); ok {
		payplay = int(jsonNumberToInt64(pay["payplay"]))
	}

	alt := map[string]interface{}{}
	if payplay == 0 {
		alt["128"] = mediaMid
	}

	return map[string]interface{}{
		"id":       songMid,
		"name":     name,
		"artist":   qqSingerName(m["singer"]),
		"album":    album,
		"pic_id":   albumMid,
		"pic_url":  qqCoverURL(albumMid, 300),
		"url_id":   songMid,
		"mv_id":    "",
		"lyric_id": songMid,
		"source":   "tencent",
		"need_vip": payplay == 1,
		// media_mid 与 songmid 不同，取流时用它拼 filename 才能命中正确档位
		"media_id": mediaMid,
		"alt_ids":  alt,
	}
}

func jsonNumberToInt64(v interface{}) int64 {
	switch val := v.(type) {
	case json.Number:
		n, _ := val.Int64()
		return n
	case float64:
		return int64(val)
	case int:
		return int64(val)
	case int64:
		return val
	case string:
		n, _ := strconv.ParseInt(val, 10, 64)
		return n
	default:
		return 0
	}
}

// qqSearch 搜索歌曲。
// 主用 client_search_cp；它偶尔会返回 500（历史上发生过），失败时回落到
// search_for_qq_cp —— 两者字段一致，只有 highlight 标签不同。
func qqSearch(keyword string, page, count int) ([]map[string]interface{}, error) {
	if page < 1 {
		page = 1
	}
	if count <= 0 || count > 50 {
		count = 20
	}
	kw := url.QueryEscape(keyword)

	endpoints := []string{
		fmt.Sprintf("https://c.y.qq.com/soso/fcgi-bin/client_search_cp?format=json&p=%d&n=%d&w=%s", page, count, kw),
		fmt.Sprintf("https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp?format=json&p=%d&n=%d&w=%s", page, count, kw),
	}

	var lastErr error
	for _, apiURL := range endpoints {
		data, err := fetchQQJSON(apiURL)
		if err != nil {
			lastErr = err
			continue
		}
		d, _ := data["data"].(map[string]interface{})
		songSection, _ := d["song"].(map[string]interface{})
		list, _ := songSection["list"].([]interface{})
		if len(list) == 0 {
			// 空列表不一定是错误（关键词无结果），但换一个端点再试一次更稳
			lastErr = fmt.Errorf("qq search empty result")
			continue
		}
		result := make([]map[string]interface{}, 0, len(list))
		for _, item := range list {
			m, ok := item.(map[string]interface{})
			if !ok {
				continue
			}
			if song := qqSongFromSearchItem(m); song != nil {
				result = append(result, song)
			}
		}
		if len(result) > 0 {
			return result, nil
		}
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("qq search failed")
	}
	return nil, lastErr
}

// qqSongCache 缓存已取到的播放地址。
// vkey 有效期为 7200 秒，但 CDN 侧可能提前失效，取一半时间做安全边界。
// key 里带档位，否则切音质会拿到上一次的缓存。
type qqCacheEntry struct {
	info   streamInfo
	expiry time.Time
}

var (
	qqCacheMu sync.Mutex
	qqCache   = map[string]qqCacheEntry{}
)

const qqCacheTTL = 30 * time.Minute

// qqFilenameTiers 是 QQ 的档位文件名映射。
//
// 前缀是固定的：M500=128k mp3、C400=128k m4a、M800=320k mp3、F000=flac、
// RS02=60 秒试听。中段必须是 media_mid（搜索结果里的 file.strMediaMid，
// 不等于 songmid），用错 mid 会拿到 result=101404「曲目不存在」。
type qqTier struct {
	prefix  string
	ext     string
	quality audioQuality
	bitrate int
}

var qqTiers = map[audioQuality][]qqTier{
	// auto：从最高档开始试，逐级降级 —— 自己就是完整降级链
	qualityAuto: {
		{prefix: "F000", ext: "flac", quality: qualityFlac, bitrate: 900000},
		{prefix: "M800", ext: "mp3", quality: quality320, bitrate: 320000},
		{prefix: "C400", ext: "m4a", quality: quality128, bitrate: 128000},
		{prefix: "M500", ext: "mp3", quality: quality128, bitrate: 128000},
	},
	qualityFlac: {
		{prefix: "F000", ext: "flac", quality: qualityFlac, bitrate: 900000},
		{prefix: "M800", ext: "mp3", quality: quality320, bitrate: 320000},
		{prefix: "C400", ext: "m4a", quality: quality128, bitrate: 128000},
		{prefix: "M500", ext: "mp3", quality: quality128, bitrate: 128000},
	},
	quality320: {
		{prefix: "M800", ext: "mp3", quality: quality320, bitrate: 320000},
		{prefix: "C400", ext: "m4a", quality: quality128, bitrate: 128000},
		{prefix: "M500", ext: "mp3", quality: quality128, bitrate: 128000},
	},
	quality128: {
		{prefix: "C400", ext: "m4a", quality: quality128, bitrate: 128000},
		{prefix: "M500", ext: "mp3", quality: quality128, bitrate: 128000},
	},
}

// qqResolveMediaID 按 songmid 反查 media_mid。
//
// 队列/收藏里存的是老版本写入的 song（只有 songmid），这时候必须反查，
// 否则拼出的 filename 中段是错的，申请 320/flac 一律 101404。
// fcg_play_single_song 的 file.media_mid 就是我们要的值。
func qqResolveMediaID(songMid string) string {
	apiURL := fmt.Sprintf(
		"https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg?songmid=%s&format=json&platform=yqq&needNewCode=0",
		url.QueryEscape(songMid),
	)
	data, err := fetchQQJSON(apiURL)
	if err != nil {
		return ""
	}
	list, _ := data["data"].([]interface{})
	if len(list) == 0 {
		return ""
	}
	first, _ := list[0].(map[string]interface{})
	file, _ := first["file"].(map[string]interface{})
	mediaMid, _ := file["media_mid"].(string)
	if mediaMid == "" {
		mediaMid, _ = file["strMediaMid"].(string)
	}
	return mediaMid
}

// qqVkey 请求指定档位的播放地址。
//
// 一次请求把目标档位的所有候选 filename 全带上（同一首歌、多个 filename），
// 从返回的 midurlinfo 里挑出第一个 purl 非空的 —— 比逐档串行请求省往返，
// 也避免多档都申请时被上游限频。
//
// 匿名态的硬限制：免费曲能拿到 M500/C400（128k），会员曲连 128k 都是 104003，
// 320/flac 只有登录态才给。所以这里必须允许降级，并且把「实际给了哪一档」
// 如实回报给前端。
func qqVkey(songMid, mediaMid string, q audioQuality) (streamInfo, error) {
	if songMid == "" {
		return streamInfo{}, errInvalidVideoID
	}

	cacheKey := songMid + ":" + mediaMid + ":" + q.String()
	qqCacheMu.Lock()
	if entry, ok := qqCache[cacheKey]; ok && time.Now().Before(entry.expiry) {
		qqCacheMu.Unlock()
		return entry.info, nil
	}
	qqCacheMu.Unlock()

	if mediaMid == "" {
		mediaMid = qqResolveMediaID(songMid)
	}
	if mediaMid == "" {
		mediaMid = songMid
	}

	tiers := qqTiers[q]
	if len(tiers) == 0 {
		tiers = qqTiers[quality128]
	}

	filenames := make([]string, 0, len(tiers)+1)
	for _, t := range tiers {
		filenames = append(filenames, fmt.Sprintf("%s%s.%s", t.prefix, mediaMid, t.ext))
	}
	// RS02 放最后：60 秒试听，只在整首歌一档都拿不到时才用
	filenames = append(filenames, fmt.Sprintf("RS02%s.mp3", mediaMid))

	infos, sip, err := qqRequestVkeys(songMid, filenames)
	if err != nil {
		return streamInfo{}, err
	}

	for _, t := range tiers {
		want := fmt.Sprintf("%s%s.%s", t.prefix, mediaMid, t.ext)
		if purl := infos[want]; purl != "" {
			info := streamInfo{
				URL:      qqJoinSip(sip, purl),
				Quality:  t.quality,
				Bitrate:  t.bitrate,
				Ext:      t.ext,
				Upstream: t.prefix,
			}
			qqCacheMu.Lock()
			qqCache[cacheKey] = qqCacheEntry{info: info, expiry: time.Now().Add(qqCacheTTL)}
			qqCacheMu.Unlock()
			return info, nil
		}
	}

	// 整首歌都没权限时退回 60 秒试听。有试听总比直接报错好，
	// 前端按 preview=true 显示「试听」标记。
	if purl := infos[fmt.Sprintf("RS02%s.mp3", mediaMid)]; purl != "" {
		info := streamInfo{
			URL:      qqJoinSip(sip, purl),
			Quality:  quality128,
			Bitrate:  128000,
			Ext:      "mp3",
			Preview:  true,
			Upstream: "RS02",
		}
		qqCacheMu.Lock()
		qqCache[cacheKey] = qqCacheEntry{info: info, expiry: time.Now().Add(qqCacheTTL)}
		qqCacheMu.Unlock()
		return info, nil
	}

	// 1000/104003 都是「该档位没权限」的笼统码：VIP、版权、地区三者之一
	return streamInfo{}, errNeedVip
}

// qqRequestVkeys 批量申请 vkey，返回 filename → purl 的映射与 CDN 前缀。
//
// guid 必须传字符串："10000"。传数组会直接拿到 req_0.code=10006，
// 且没有任何 midurlinfo —— 这是本接口最容易踩的坑（filename 批量没问题，
// 一次带 8 个 filename 都正常，唯独 guid 不能是数组）。
func qqRequestVkeys(songMid string, filenames []string) (map[string]string, string, error) {
	types := make([]int, len(filenames))
	for i := range types {
		types[i] = 0
	}

	payload := map[string]interface{}{
		"comm": map[string]interface{}{
			"uin": 0, "format": "json", "ct": 24, "cv": 0,
		},
		"req_0": map[string]interface{}{
			"module": "vkey.GetVkeyServer",
			"method": "CgiGetVkey",
			"param": map[string]interface{}{
				"guid":      "10000",
				"songmid":   repeatString(songMid, len(filenames)),
				"songtype":  types,
				"filename":  filenames,
				"uin":       "0",
				"loginflag": 1,
				"platform":  "20",
			},
		},
	}

	data, err := fetchQQMusicu(payload)
	if err != nil {
		return nil, "", err
	}

	req0, _ := data["req_0"].(map[string]interface{})
	if req0 == nil {
		return nil, "", fmt.Errorf("qq vkey: 响应缺少 req_0")
	}
	// req_0.code == 1000 表示登录态失效；匿名态不会出现，出现说明上游改了口径
	if code := jsonNumberToInt64(req0["code"]); code != 0 {
		return nil, "", fmt.Errorf("qq vkey: 上游返回 code=%d", code)
	}

	inner, _ := req0["data"].(map[string]interface{})
	if inner == nil {
		return nil, "", fmt.Errorf("qq vkey: 响应缺少 data")
	}
	sipList, _ := inner["sip"].([]interface{})
	sip := ""
	if len(sipList) > 0 {
		sip, _ = sipList[0].(string)
	}
	if sip == "" {
		sip = "https://ws.stream.qqmusic.qq.com/"
	}

	infoList, _ := inner["midurlinfo"].([]interface{})
	if len(infoList) == 0 {
		return nil, "", fmt.Errorf("qq vkey: 响应缺少 midurlinfo")
	}

	out := make(map[string]string, len(infoList))
	for _, item := range infoList {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		fn, _ := m["filename"].(string)
		purl, _ := m["purl"].(string)
		if fn != "" && purl != "" {
			out[fn] = purl
		}
	}
	return out, sip, nil
}

// qqJoinSip 拼完整直链。sip 是 CDN 前缀（aqqmusic.tc.qq.com 等）。
//
// ?vkey= 必须保留：去掉后 CDN 直接 403。协议统一换 https，避免 iOS ATS 拦截
// （QQ 的 CDN 实际支持 https，只是接口给出的 sip 常写成 http）。
func qqJoinSip(sip, purl string) string {
	full := strings.TrimSuffix(sip, "/") + "/" + strings.TrimPrefix(purl, "/")
	return strings.Replace(full, "http://", "https://", 1)
}

// repeatString 生成 n 个相同字符串的切片。
func repeatString(s string, n int) []string {
	out := make([]string, n)
	for i := range out {
		out[i] = s
	}
	return out
}

// qqLyric 取歌词。QQ 歌词接口有 base64 与明文两种输出，nobase64=1 拿明文。
func qqLyric(songMid string) (string, error) {
	apiURL := fmt.Sprintf(
		"https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=%s&g_tk=5381&format=json&nobase64=1",
		url.QueryEscape(songMid),
	)
	// 歌词接口对 Referer 敏感，必须是 player.html 这个具体页面
	req, err := http.NewRequest(http.MethodGet, apiURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", qqHeaders()["User-Agent"])
	req.Header.Set("Referer", "https://y.qq.com/portal/player.html")
	resp, err := qqClient().Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("qq lyric status %d", resp.StatusCode)
	}
	var data map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return "", err
	}
	if code := jsonNumberToInt64(data["code"]); code != 0 {
		return "", fmt.Errorf("qq lyric code=%d", code)
	}
	lyric, _ := data["lyric"].(string)
	return lyric, nil
}

// qqLeaderboardList 榜单列表。
// musicu.fcg 的 ToplistInfoServer/GetAll 一次返回全部分组，比逐个 topid 拉取省事。
func qqLeaderboardList() ([]map[string]interface{}, error) {
	payload := map[string]interface{}{
		"comm": map[string]interface{}{"ct": 24, "cv": 0},
		"req_2": map[string]interface{}{
			"module": "musicToplist.ToplistInfoServer",
			"method": "GetAll",
			"param":  map[string]interface{}{},
		},
	}
	data, err := fetchQQMusicu(payload)
	if err != nil {
		return nil, err
	}
	req2, _ := data["req_2"].(map[string]interface{})
	inner, _ := req2["data"].(map[string]interface{})
	groups, _ := inner["group"].([]interface{})

	result := make([]map[string]interface{}, 0, 32)
	for _, g := range groups {
		gm, ok := g.(map[string]interface{})
		if !ok {
			continue
		}
		groupName, _ := gm["groupName"].(string)
		toplists, _ := gm["toplist"].([]interface{})
		for _, t := range toplists {
			tm, ok := t.(map[string]interface{})
			if !ok {
				continue
			}
			topID := jsonIDToString(tm["topId"])
			title, _ := tm["title"].(string)
			cover, _ := tm["headPicUrl"].(string)
			if cover == "" {
				cover, _ = tm["frontPicUrl"].(string)
			}
			result = append(result, map[string]interface{}{
				"id":              topID,
				"name":            title,
				"coverUrl":        cover,
				"updateFrequency": groupName,
				"source":          "tencent",
			})
		}
	}
	return result, nil
}

// qqLeaderboardDetail 榜单详情。topid=26 是热歌榜，作为默认。
//
// 上游用 song_begin/song_num 分页，这里按 offset 透传，否则「加载更多」
// 永远拿回同一批（原来写死 song_begin=0）。
func qqLeaderboardDetail(
	topID string,
	limit int,
	offset int,
) ([]map[string]interface{}, error) {
	if topID == "" {
		topID = "26"
	}
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	if offset < 0 {
		offset = 0
	}
	apiURL := fmt.Sprintf(
		"https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg?topid=%s&format=json&page=detail&type=top&song_begin=%d&song_num=%d",
		url.QueryEscape(topID), offset, limit,
	)
	data, err := fetchQQJSON(apiURL)
	if err != nil {
		return nil, err
	}
	songList, _ := data["songlist"].([]interface{})
	result := make([]map[string]interface{}, 0, len(songList))
	for _, item := range songList {
		wrapper, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		// 榜单把歌曲信息包在 data 里
		m, ok := wrapper["data"].(map[string]interface{})
		if !ok {
			continue
		}
		if song := qqSongFromSearchItem(m); song != nil {
			result = append(result, song)
		}
	}
	return result, nil
}

// qqPlaylistDetail 歌单详情。QQ 歌单的 songlist 结构与榜单一致。
//
// 上游一次返回整张歌单，分页在这里按 offset/limit 切片。
func qqPlaylistDetail(
	disstid string,
	limit int,
	offset int,
) ([]map[string]interface{}, error) {
	if disstid == "" {
		return nil, errInvalidVideoID
	}
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	apiURL := fmt.Sprintf(
		"https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&disstid=%s&format=json&g_tk=5381&loginUin=0&hostUin=0&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0",
		url.QueryEscape(disstid),
	)
	data, err := fetchQQJSON(apiURL)
	if err != nil {
		return nil, err
	}
	cdlist, _ := data["cdlist"].([]interface{})
	if len(cdlist) == 0 {
		return []map[string]interface{}{}, nil
	}
	first, _ := cdlist[0].(map[string]interface{})
	songList, _ := first["songlist"].([]interface{})

	result := make([]map[string]interface{}, 0, len(songList))
	for i, item := range songList {
		if i < offset {
			continue
		}
		if len(result) >= limit {
			break
		}
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		if song := qqSongFromSearchItem(m); song != nil {
			result = append(result, song)
		}
	}
	return result, nil
}

// qqSongList 歌单列表。
// QQ 的公开歌单列表接口全部要求登录态（实测匿名返回空 list），
// 这里用榜单代替，语义上仍是「可浏览的集合」，前端无需区分。
func qqSongList() ([]map[string]interface{}, error) {
	boards, err := qqLeaderboardList()
	if err != nil {
		return nil, err
	}
	for _, b := range boards {
		b["author"] = "QQ 音乐"
		b["playCount"] = ""
		b["description"] = b["updateFrequency"]
	}
	return boards, nil
}

// qqMediaProxyReferer 供媒体代理使用：QQ CDN 不校验 Referer，但统一带上更稳。
func qqMediaProxyReferer(host string) (string, bool) {
	switch {
	case strings.HasSuffix(host, ".qqmusic.qq.com"),
		strings.HasSuffix(host, ".tc.qq.com"):
		return "https://y.qq.com/", true
	}
	return "", false
}

// qqSignGTK 是 QQ 的 hash33 算法，登录态取流时用它算 g_tk。
// 匿名态用不到，但接 cookie 时必须一致，错一位就是全量 401。
func qqSignGTK(key string) string {
	var hash int32 = 5381
	for _, ch := range key {
		hash = (hash << 5) + hash + int32(ch)
	}
	return strconv.FormatInt(int64(hash&0x7fffffff), 10)
}
