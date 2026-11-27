package handlers

import (
	"net/url"
	"strings"
)

// 网易云歌单（榜单）曲目读取。
//
// 三个接口都试过，差别很大：
//
//   - v2 `/api/playlist/detail?id=..`：整张歌单内联在 `result.tracks`，
//     **但普通用户歌单只内联 10 首**（官方榜才是 100/200 首）。实测
//     id=8458285200 的 `trackCount` 直接报 10，真实却有 202 首。
//     这就是「发现里的歌单全都只有 10 首」的根因——不是前端没翻页，
//     而是拿到的响应里就这么多。
//   - v3 `/api/v3/playlist/detail?id=..&n=N`：`n` 只控制内联多少首，
//     但 `playlist.trackIds` 永远是**完整**的曲目 id 列表（上面那张 202 首）。
//     突发并发下会 405（65 个榜单并发探测时一半 405），所以只用来取 id。
//   - `api/song/detail?ids=[..]`：按 id 批量取详情，一次 200 个稳定，
//     返回的字段是 v2 那套（`artists` / `album`），顺序与请求一致。
//
// 现在的组合：v3 拿完整 id 列表（n=0，响应约 44KB 且不含曲目元数据）
// → 按 offset/limit 切片 → song/detail 批量补齐。这样既能拿全，也能翻页。
// v3 失败时才退回 v2 的内联曲目。

// neteasePlaylistSongs 取歌单前 limit 首（保留给不需要分页的调用方）。
func neteasePlaylistSongs(id string, limit int) []map[string]interface{} {
	return neteasePlaylistSongsPage(id, 0, limit)
}

// neteasePlaylistSongsPage 取歌单 [offset, offset+limit) 的曲目。
func neteasePlaylistSongsPage(id string, offset, limit int) []map[string]interface{} {
	if limit <= 0 {
		limit = 30
	}
	if offset < 0 {
		offset = 0
	}

	ids := neteasePlaylistTrackIDs(id)
	if len(ids) == 0 {
		// 取不到 id 列表（v3 限流 / 老接口变更）：退回 v2 的内联曲目。
		// 普通歌单只有 10 首，但聊胜于无。
		return neteasePlaylistSongsV2(id, limit)
	}
	if offset >= len(ids) {
		return []map[string]interface{}{}
	}
	end := offset + limit
	if end > len(ids) {
		end = len(ids)
	}
	return neteaseSongsByIDs(ids[offset:end])
}

// neteasePlaylistTrackIDs 取歌单完整曲目 id 列表（顺序与歌单一致）。
func neteasePlaylistTrackIDs(id string) []string {
	data, err := fetchNetease(
		"https://music.163.com/api/v3/playlist/detail?id=" +
			url.QueryEscape(id) + "&n=0",
	)
	if err != nil {
		return nil
	}
	playlist, _ := data["playlist"].(map[string]interface{})
	if playlist == nil {
		return nil
	}
	raw, _ := playlist["trackIds"].([]interface{})
	if len(raw) == 0 {
		return nil
	}
	ids := make([]string, 0, len(raw))
	for _, item := range raw {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		if sid := jsonIDToString(m["id"]); sid != "" && sid != "0" {
			ids = append(ids, sid)
		}
	}
	return ids
}

// neteaseSongDetailBatch 单次 song/detail 最多带多少个 id。
// 实测 200 个稳定返回 200 首，再多会被截断，所以按 200 切块。
const neteaseSongDetailBatch = 200

// neteaseSongsByIDs 批量取曲目详情，保持传入顺序。
func neteaseSongsByIDs(ids []string) []map[string]interface{} {
	out := make([]map[string]interface{}, 0, len(ids))
	for start := 0; start < len(ids); start += neteaseSongDetailBatch {
		end := start + neteaseSongDetailBatch
		if end > len(ids) {
			end = len(ids)
		}
		chunk := ids[start:end]
		data, err := fetchNetease(
			"https://music.163.com/api/song/detail?ids=" +
				url.QueryEscape("["+strings.Join(chunk, ",")+"]"),
		)
		if err != nil {
			continue
		}
		songs, _ := data["songs"].([]interface{})
		out = append(out, neteaseTracksToSongs(songs, neteaseTrackToSongV2, 0)...)
	}
	return out
}

func neteasePlaylistSongsV2(id string, limit int) []map[string]interface{} {
	data, err := fetchNetease(
		"https://music.163.com/api/playlist/detail?id=" + url.QueryEscape(id),
	)
	if err != nil {
		return nil
	}
	result, _ := data["result"].(map[string]interface{})
	if result == nil {
		return nil
	}
	tracks, _ := result["tracks"].([]interface{})
	return neteaseTracksToSongs(tracks, neteaseTrackToSongV2, limit)
}

func neteaseTracksToSongs(
	tracks []interface{},
	convert func(map[string]interface{}) map[string]interface{},
	limit int,
) []map[string]interface{} {
	if len(tracks) == 0 {
		return nil
	}
	if limit > 0 && len(tracks) > limit {
		tracks = tracks[:limit]
	}
	out := make([]map[string]interface{}, 0, len(tracks))
	for _, item := range tracks {
		t, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		if song := convert(t); song != nil {
			out = append(out, song)
		}
	}
	return out
}

// neteaseTrackToSongV2 转换 v2 / song/detail 的曲目结构：
// `artists:[{name}]` + `album:{name,pic,picUrl}`。
func neteaseTrackToSongV2(t map[string]interface{}) map[string]interface{} {
	artists := ""
	if ar, ok := t["artists"].([]interface{}); ok && len(ar) > 0 {
		if a, ok := ar[0].(map[string]interface{}); ok {
			artists, _ = a["name"].(string)
		}
	}
	// song/detail 只给 `album`；v3 给 `al`。两个都接受，
	// 免得将来某一边换了字段名就整批没封面。
	al, _ := t["album"].(map[string]interface{})
	if al == nil {
		al, _ = t["al"].(map[string]interface{})
	}
	picID, picURL, albumName := "", "", ""
	if al != nil {
		picURL, _ = al["picUrl"].(string)
		picID = jsonIDToString(al["pic"])
		if picID == "0" || picID == "" {
			picID = jsonIDToString(al["id"])
		}
		albumName, _ = al["name"].(string)
	}
	return neteaseSongMap(t, artists, albumName, picID, picURL)
}

func neteaseSongMap(
	t map[string]interface{},
	artist, album, picID, picURL string,
) map[string]interface{} {
	songID := jsonIDToString(t["id"])
	if songID == "" || songID == "0" {
		return nil
	}
	return map[string]interface{}{
		"id":       songID,
		"name":     t["name"],
		"artist":   artist,
		"album":    album,
		"pic_id":   picID,
		"pic_url":  picURL,
		"url_id":   songID,
		"lyric_id": songID,
		"source":   "netease",
	}
}
