package handlers

import (
	"testing"
)

// TestQQCoverURL 验证封面地址拼接。
// albummid 为空时必须返回空串，避免前端拿到 ".../M000.jpg" 这种坏链接。
func TestQQCoverURL(t *testing.T) {
	if got := qqCoverURL("", 300); got != "" {
		t.Fatalf("空 albummid 应返回空串，实际 %q", got)
	}
	got := qqCoverURL("000MkMni19ClKG", 300)
	want := "https://y.gtimg.cn/music/photo_new/T002R300x300M000000MkMni19ClKG.jpg"
	if got != want {
		t.Fatalf("封面地址不符: got %q want %q", got, want)
	}
}

// TestQQSingerName 验证歌手名拼接。
// QQ 返回的 singer 是数组，多歌手应拼成 A/B。
func TestQQSingerName(t *testing.T) {
	raw := []interface{}{
		map[string]interface{}{"name": "周杰伦"},
		map[string]interface{}{"name": "费玉清"},
	}
	if got := qqSingerName(raw); got != "周杰伦/费玉清" {
		t.Fatalf("歌手名拼接错误: %q", got)
	}
	if got := qqSingerName(nil); got != "" {
		t.Fatalf("nil 应返回空串，实际 %q", got)
	}
}

// TestQQSongFromSearchItem 验证搜索结果到内部结构的映射。
// media_mid 为空时要回落到 songmid，否则取流会拼错 filename。
func TestQQSongFromSearchItem(t *testing.T) {
	item := map[string]interface{}{
		"songmid":   "000dkZDx1pwNRW",
		"songname":  "千与千寻 (钢琴版)",
		"albumname": "千与千寻",
		"albummid":  "001abc",
		"media_mid": "0041N3Zg2DKHOh",
		"singer":    []interface{}{map[string]interface{}{"name": "久石让"}},
		"pay":       map[string]interface{}{"payplay": float64(0)},
	}
	song := qqSongFromSearchItem(item)
	if song == nil {
		t.Fatal("应返回有效结构")
	}
	if song["id"] != "000dkZDx1pwNRW" {
		t.Fatalf("id 不符: %v", song["id"])
	}
	if song["media_id"] != "0041N3Zg2DKHOh" {
		t.Fatalf("media_id 应取 media_mid，实际 %v", song["media_id"])
	}
	if song["need_vip"] != false {
		t.Fatalf("payplay=0 不应标记 need_vip")
	}

	// 缺 songmid 时应返回 nil，避免下游拿空 id 请求上游
	if qqSongFromSearchItem(map[string]interface{}{"songname": "x"}) != nil {
		t.Fatal("缺 songmid 应返回 nil")
	}
}

// TestNormalizeQuality 验证前端各种音质写法都能收敛到四档。
// 192 是历史 UI 留下的档位，国内音源都没有这一档，按 320 处理让上游自己降级。
func TestNormalizeQuality(t *testing.T) {
	cases := []struct {
		raw  string
		want audioQuality
	}{
		{"", qualityAuto},
		{"auto", qualityAuto},
		{"128", quality128},
		{"128000", quality128},
		{"lq", quality128},
		{"320", quality320},
		{"320000", quality320},
		{"hq", quality320},
		{"192", quality320},
		{"192000", quality320},
		{"flac", qualityFlac},
		{"FLAC", qualityFlac},
		{"lossless", qualityFlac},
		{"999", qualityFlac},
		{"999000", qualityFlac},
		// 纯数字按 kbps 向上归档
		{"96", quality128},
		{"256", quality320},
		{"900", qualityFlac},
		// 无法识别时按 auto，让后端挑最高可用档
		{"weird", qualityAuto},
	}
	for _, c := range cases {
		if got := normalizeQuality(c.raw); got != c.want {
			t.Fatalf("normalizeQuality(%q) = %v, want %v", c.raw, got, c.want)
		}
	}
}

// TestQualityOfBitrate 验证码率归档边界。
// 酷狗无损实测 694000，必须落在 flac 档；320000 落在 320 档。
func TestQualityOfBitrate(t *testing.T) {
	cases := []struct {
		bitrate int
		want    audioQuality
	}{
		{128000, quality128},
		{192000, quality128},
		{320000, quality320},
		{694000, qualityFlac},
		{1476000, qualityFlac},
		{0, quality128},
	}
	for _, c := range cases {
		if got := qualityOfBitrate(c.bitrate); got != c.want {
			t.Fatalf("qualityOfBitrate(%d) = %v, want %v", c.bitrate, got, c.want)
		}
	}
}

// TestQualityOfStream 验证取流回执的音质判定。
// 关键：酷狗 320 档实测 bitRate=0、flac 档 bitRate=411000，
// 只看码率会把 320 说成 128、把无损说成 320，用户看到的标签就是错的。
func TestQualityOfStream(t *testing.T) {
	cases := []struct {
		ext     string
		bitrate int
		hint    audioQuality
		want    audioQuality
	}{
		// flac 扩展名最可信，码率怎么报都算无损
		{"flac", 411000, qualityFlac, qualityFlac},
		{"flac", 0, qualityFlac, qualityFlac},
		{"FLAC", 694000, qualityAuto, qualityFlac},
		// 320 档 bitRate 缺失时按请求档位判
		{"mp3", 0, quality320, quality320},
		// 但请求 flac 却拿到 mp3 且无码率：不能标成无损
		{"mp3", 0, qualityFlac, quality128},
		// 码率明确时以码率为准
		{"mp3", 320000, quality320, quality320},
		{"mp3", 128000, qualityFlac, quality128},
		{"ape", 0, quality128, qualityFlac},
	}
	for _, c := range cases {
		if got := qualityOfStream(c.ext, c.bitrate, c.hint); got != c.want {
			t.Fatalf(
				"qualityOfStream(%q, %d, %v) = %v, want %v",
				c.ext, c.bitrate, c.hint, got, c.want,
			)
		}
	}
}

// TestKGHashKey 验证酷狗 trackercdn 的签名 key。
// 算法是 md5(hash + 盐)，写错一位上游直接回 "Bad key"。
func TestKGHashKey(t *testing.T) {
	// 期望值由实测反推：这条 hash 配 kgcloud 盐能取到 320 档
	got := kgHashKey("3727b6f1a38bb009c8d0623732a74fda", "kgcloud")
	if len(got) != 32 {
		t.Fatalf("md5 十六进制应为 32 位，实际 %d: %q", len(got), got)
	}
	// 同输入必须稳定
	if again := kgHashKey("3727b6f1a38bb009c8d0623732a74fda", "kgcloud"); again != got {
		t.Fatalf("签名不稳定: %q vs %q", got, again)
	}
	// 换盐必须变
	if other := kgHashKey("3727b6f1a38bb009c8d0623732a74fda", "kgcloudv2"); other == got {
		t.Fatal("不同盐应产生不同签名")
	}
}

// TestQQSignGTK 验证 hash33。匿名态用不到，但算法写错会在接 cookie 时静默失效。
func TestQQSignGTK(t *testing.T) {
	// hash33("", 5381) 保持初始值
	if got := qqSignGTK(""); got != "5381" {
		t.Fatalf("空串应返回 5381，实际 %q", got)
	}
	// 与 QQ 官方 JS 实现一致：逐字符 hash = hash*33 + code
	if got := qqSignGTK("a"); got != "177670" {
		t.Fatalf("hash33(\"a\") 应为 177670，实际 %q", got)
	}
}

// TestQQJoinSip 验证 CDN 地址拼接。
// sip 常是 http 且可能带尾斜杠，purl 可能带前导斜杠，?vkey= 必须原样保留。
func TestQQJoinSip(t *testing.T) {
	got := qqJoinSip("http://aqqmusic.tc.qq.com/", "/M500abc.mp3?vkey=XX&guid=10000")
	want := "https://aqqmusic.tc.qq.com/M500abc.mp3?vkey=XX&guid=10000"
	if got != want {
		t.Fatalf("拼接错误:\n got  %q\n want %q", got, want)
	}
	// 无尾斜杠、purl 无前导斜杠也要正常
	got = qqJoinSip("https://ws.stream.qqmusic.qq.com", "C400abc.m4a?vkey=Y")
	want = "https://ws.stream.qqmusic.qq.com/C400abc.m4a?vkey=Y"
	if got != want {
		t.Fatalf("拼接错误:\n got  %q\n want %q", got, want)
	}
}

// TestQQTiersOrder 验证各档位的候选顺序。
// 关键约束：申请高音质时必须先试高音质、再逐级降级，
// 且 flac 档位里 M800 必须排在 F000 之后 —— 顺序错会让无损永远拿不到。
func TestQQTiersOrder(t *testing.T) {
	flac := qqTiers[qualityFlac]
	if len(flac) == 0 || flac[0].prefix != "F000" {
		t.Fatalf("flac 档应优先 F000，实际 %+v", flac)
	}
	if flac[1].prefix != "M800" {
		t.Fatalf("flac 档第二顺位应是 M800，实际 %s", flac[1].prefix)
	}

	hq := qqTiers[quality320]
	if len(hq) == 0 || hq[0].prefix != "M800" {
		t.Fatalf("320 档应优先 M800，实际 %+v", hq)
	}

	lq := qqTiers[quality128]
	if len(lq) == 0 || lq[0].prefix != "C400" {
		t.Fatalf("128 档应优先 C400（m4a 体积更小），实际 %+v", lq)
	}
	// 每一档都必须带 ext 与码率，前端靠它们显示实际音质
	for _, tiers := range qqTiers {
		for _, tier := range tiers {
			if tier.ext == "" || tier.bitrate <= 0 {
				t.Fatalf("档位缺少 ext/bitrate: %+v", tier)
			}
		}
	}
}

// TestWithURL 验证取流回执字段。
// 前端要读 url/quality/bitrate/ext/preview，字段名不能漂。
func TestWithURL(t *testing.T) {
	info := streamInfo{
		URL:     "https://example.com/a.flac",
		Quality: qualityFlac,
		Bitrate: 694000,
		Ext:     "flac",
		Size:    16666650,
		Preview: true,
	}
	out := withURL(info)
	if out["url"] != info.URL {
		t.Fatalf("url 不符: %v", out["url"])
	}
	if out["quality"] != "flac" {
		t.Fatalf("quality 应为 flac，实际 %v", out["quality"])
	}
	if out["bitrate"] != 694000 {
		t.Fatalf("bitrate 不符: %v", out["bitrate"])
	}
	if out["ext"] != "flac" {
		t.Fatalf("ext 不符: %v", out["ext"])
	}
	if out["size"] != int64(16666650) {
		t.Fatalf("size 不符: %v", out["size"])
	}
	if out["preview"] != true {
		t.Fatalf("preview 不符: %v", out["preview"])
	}
}

// TestKugouCoverFromTemplate 验证 {size} 占位替换与协议升级。
func TestKugouCoverFromTemplate(t *testing.T) {
	tpl := "http://imge.kugou.com/stdmusic/{size}/20261126/abc.jpg"
	want := "https://imge.kugou.com/stdmusic/240/20261126/abc.jpg"
	if got := kugouCoverFromTemplate(tpl, 240); got != want {
		t.Fatalf("封面模板替换错误: got %q want %q", got, want)
	}
	if got := kugouCoverFromTemplate("", 240); got != "" {
		t.Fatalf("空模板应返回空串，实际 %q", got)
	}
}

// TestKugouSongFromItem 验证可播判定与档位登记。
// 关键：privilege=8 的 pay_type=3 曲目实际可播，不能判成 VIP；
// privilege=10 才是真的拿不到流，此时不应登记任何档位。
func TestKugouSongFromItem(t *testing.T) {
	base := map[string]interface{}{
		"hash":         "48C685F679FFC7CF08B8A8341CA9DB44",
		"songname":     "晴天",
		"album_name":   "网瘾少女叽",
		"album_id":     "79360569",
		"320hash":      "28F83BBD8CAB043895039E98366AD2B4",
		"sqhash":       "857879479E698D729640A5716DC3E56F",
		"privilege":    float64(0),
		"320privilege": float64(0),
		"sqprivilege":  float64(10),
	}

	song := kugouSongFromItem(base)
	if song == nil {
		t.Fatal("应返回有效结构")
	}
	if song["need_vip"] != false {
		t.Fatalf("privilege=0 不应标记 need_vip")
	}
	alt, _ := song["alt_ids"].(map[string]interface{})
	if alt["128"] == nil || alt["320"] == nil {
		t.Fatalf("128/320 档应登记，实际 %v", alt)
	}
	if alt["flac"] != nil {
		t.Fatalf("sqprivilege=10 时不应登记 flac 档，实际 %v", alt)
	}

	// privilege=8：付费标记但实际可播
	base["privilege"] = float64(8)
	if kugouSongFromItem(base)["need_vip"] != false {
		t.Fatal("privilege=8 实际可播，不应标记 need_vip")
	}

	// privilege=10：真的拿不到流，且不给任何档位
	base["privilege"] = float64(10)
	base["320privilege"] = float64(10)
	base["sqprivilege"] = float64(10)
	vip := kugouSongFromItem(base)
	if vip["need_vip"] != true {
		t.Fatal("privilege=10 应标记 need_vip")
	}
	if alt, _ := vip["alt_ids"].(map[string]interface{}); len(alt) != 0 {
		t.Fatalf("整曲无权限时不应登记档位，实际 %v", alt)
	}

	// 缺 hash 应返回 nil
	if kugouSongFromItem(map[string]interface{}{"songname": "x"}) != nil {
		t.Fatal("缺 hash 应返回 nil")
	}
}

// TestKugouMediaProxyReferer 验证媒体代理的域名归属判定。
// 子域必须命中，且不能误判 egkugou.com 这类仿冒域名。
func TestKugouMediaProxyReferer(t *testing.T) {
	cases := []struct {
		host string
		want bool
	}{
		{"sharefs.kugou.com", true},
		{"fsvippc.kugou.com", true},
		{"kugou.com", true},
		{"evil-kugou.com", false},
		{"notkugou.com", false},
	}
	for _, c := range cases {
		if _, ok := kugouMediaProxyReferer(c.host); ok != c.want {
			t.Fatalf("host=%s 期望 %v 实际 %v", c.host, c.want, ok)
		}
	}
}

// TestQQMediaProxyReferer 同上，QQ CDN 域名归属。
func TestQQMediaProxyReferer(t *testing.T) {
	cases := []struct {
		host string
		want bool
	}{
		{"aqqmusic.tc.qq.com", true},
		{"ws.stream.qqmusic.qq.com", true},
		{"isure.stream.qqmusic.qq.com", true},
		{"eviilqq.com", false},
	}
	for _, c := range cases {
		if _, ok := qqMediaProxyReferer(c.host); ok != c.want {
			t.Fatalf("host=%s 期望 %v 实际 %v", c.host, c.want, ok)
		}
	}
}
