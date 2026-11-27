package handlers

import (
	"crypto/md5"
	"encoding/hex"
	"strconv"
	"strings"
)

// 音质档位。
//
// 各音源能给的档位并不一致：网易云与酷狗有 320k/无损，QQ 匿名态最高只有 128k。
// 前端统一传一档，后端按各源能力挑最接近的一档，并把「实际给了什么」回给前端，
// 让 UI 显示真实码率而不是用户选的那个数字。
type audioQuality int

const (
	qualityAuto audioQuality = iota // auto：能拿多高拿多高
	quality128
	quality320
	qualityFlac
)

// String 用于回给前端与日志，取值与前端 settings 里的标识一致。
func (q audioQuality) String() string {
	switch q {
	case qualityFlac:
		return "flac"
	case quality320:
		return "320"
	case quality128:
		return "128"
	default:
		return "auto"
	}
}

// normalizeQuality 把前端传来的各种写法收敛成四档。
//
// 历史实现里前端会把 192 也传下来（老 UI 的「较高 192K」），但国内各家音源
// 都没有 192k 档，192 一律按 320 处理 —— 让上游自己降级，比在中间假装有这一档好。
func normalizeQuality(raw string) audioQuality {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "", "auto", "0":
		return qualityAuto
	case "flac", "lossless", "sq", "999", "999000":
		return qualityFlac
	case "320", "320000", "hq", "high", "192", "192000":
		return quality320
	case "128", "128000", "lq", "standard":
		return quality128
	default:
		// 纯数字按千比特每秒理解，再向上归到最接近的一档
		if n, err := strconv.Atoi(raw); err == nil {
			switch {
			case n >= 700:
				return qualityFlac
			case n >= 200:
				return quality320
			default:
				return quality128
			}
		}
		return qualityAuto
	}
}

// streamInfo 是取流接口的统一回执。
//
// 前端需要 quality/bitrate 来显示「实际音质」，preview 用来提示这是 60 秒试听，
// ext 决定下载时的文件后缀 —— 三者都不能靠前端猜。
type streamInfo struct {
	URL      string
	Quality  audioQuality
	Bitrate  int    // 实际码率，单位 bps；未知为 0
	Ext      string // mp3 / m4a / flac
	Size     int64  // 文件字节数；未知为 0
	Preview  bool   // true 表示这是试听片段而非完整曲目
	Upstream string // 实际命中的上游档位标识，仅用于日志与排查
}

// toJSON 转成前端消费的字段名。url 单独由调用方写，这里只出附加信息。
func (s streamInfo) toJSON() map[string]interface{} {
	out := map[string]interface{}{
		"quality": s.Quality.String(),
		"bitrate": s.Bitrate,
	}
	if s.Ext != "" {
		out["ext"] = s.Ext
	}
	if s.Size > 0 {
		out["size"] = s.Size
	}
	if s.Preview {
		out["preview"] = true
	}
	return out
}

// withURL 把 streamInfo 转成带 url 的完整回执。
// 取流接口的响应里必须同时有 url 和实际音质信息，前端才知道「确实拿到的是哪一档」。
func withURL(s streamInfo) map[string]interface{} {
	out := s.toJSON()
	out["url"] = s.URL
	return out
}

// kgHashKey 是酷狗 trackercdn 的签名 key：md5(hash + 固定盐)。
// 两个盐对应两套接口：kgcloud 给 v1（cmd=4，能出 320/flac），
// kgcloudv2 给 v2（新版，实测对普通曲目一律 errcode=20028，仅作兜底）。
func kgHashKey(hash, salt string) string {
	sum := md5.Sum([]byte(hash + salt))
	return hex.EncodeToString(sum[:])
}
