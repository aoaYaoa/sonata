package handlers

import (
	"context"
	"net"
	"testing"
)

func TestHostInAllowlist(t *testing.T) {
	tests := []struct {
		name      string
		host      string
		allowlist []string
		want      bool
	}{
		{"exact match", "kuwo.cn", []string{"kuwo.cn"}, true},
		{"subdomain via dot prefix", "www.kuwo.cn", []string{".kuwo.cn"}, true},
		{"deep subdomain", "a.b.bilivideo.com", []string{".bilivideo.com"}, true},
		{"dot prefix must not match apex", "kuwo.cn", []string{".kuwo.cn"}, false},

		// 这是修复前的实际绕过路径：strings.HasSuffix 会把 evilkuwo.cn 判为命中
		{"suffix attack rejected", "evilkuwo.cn", []string{".kuwo.cn", "kuwo.cn"}, false},
		{"prefix attack rejected", "notbilibili.com", []string{".bilibili.com"}, false},
		{"trailing dot attack rejected", "evilkuwo.cn.", []string{"kuwo.cn"}, false},
		{"empty host", "", []string{"kuwo.cn"}, false},
		{"empty allowlist", "kuwo.cn", nil, false},
		{"case insensitive", "WWW.KUWO.CN", []string{".kuwo.cn"}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := hostInAllowlist(tt.host, tt.allowlist); got != tt.want {
				t.Fatalf("hostInAllowlist(%q, %v) = %v, want %v", tt.host, tt.allowlist, got, tt.want)
			}
		})
	}
}

func TestIsDisallowedIP(t *testing.T) {
	tests := []struct {
		ip   string
		want bool
	}{
		{"127.0.0.1", true},
		{"10.0.0.1", true},
		{"172.16.0.1", true},
		{"192.168.1.1", true},
		{"169.254.169.254", true}, // 云元数据
		{"0.0.0.0", true},
		{"::1", true},
		{"fd00::1", true},
		{"fe80::1", true},
		{"224.0.0.1", true},
		{"8.8.8.8", false},
		{"1.1.1.1", false},
	}

	for _, tt := range tests {
		ip := net.ParseIP(tt.ip)
		if ip == nil {
			t.Fatalf("解析失败: %s", tt.ip)
		}
		if got := isDisallowedIP(ip); got != tt.want {
			t.Fatalf("isDisallowedIP(%s) = %v, want %v", tt.ip, got, tt.want)
		}
	}
}

func TestValidateProxyTarget(t *testing.T) {
	allowlist := []string{"kuwo.cn", ".126.net"}

	t.Run("loopback rejected", func(t *testing.T) {
		// 内网 SSRF 是修复前 /imgproxy 的实测攻击面
		if _, err := validateProxyTarget(context.Background(), "http://127.0.0.1:8080/health", allowlist); err == nil {
			t.Fatal("期望拒绝回环地址，实际放行")
		}
	})

	t.Run("metadata endpoint rejected", func(t *testing.T) {
		if _, err := validateProxyTarget(context.Background(), "http://169.254.169.254/latest/meta-data/", allowlist); err == nil {
			t.Fatal("期望拒绝云元数据地址，实际放行")
		}
	})

	t.Run("non-allowlisted host rejected", func(t *testing.T) {
		if _, err := validateProxyTarget(context.Background(), "https://example.com/a.jpg", allowlist); err == nil {
			t.Fatal("期望拒绝白名单外域名，实际放行")
		}
	})

	t.Run("unsupported scheme rejected", func(t *testing.T) {
		for _, raw := range []string{"file:///etc/passwd", "gopher://127.0.0.1:6379/_x", "dict://127.0.0.1:11211/"} {
			if _, err := validateProxyTarget(context.Background(), raw, allowlist); err == nil {
				t.Fatalf("期望拒绝协议 %s，实际放行", raw)
			}
		}
	})

	t.Run("allowlisted literal", func(t *testing.T) {
		// 用 IP 字面量的公网地址验证正向路径（不依赖 DNS）
		parsed, err := validateProxyTarget(context.Background(), "https://1.1.1.1/x.jpg", []string{"1.1.1.1"})
		if err != nil {
			t.Fatalf("期望放行，实际拒绝: %v", err)
		}
		if parsed.Hostname() != "1.1.1.1" {
			t.Fatalf("解析结果异常: %s", parsed.Hostname())
		}
	})
}

func TestYoutubeVideoIDPattern(t *testing.T) {
	valid := []string{"dQw4w9WgXcQ", "9bZkp7q19f0", "a_B-c1D2e3F"}
	for _, id := range valid {
		if !youtubeVideoIDPattern.MatchString(id) {
			t.Fatalf("合法 video id 被拒: %s", id)
		}
	}

	// 修复前这些输入会被拼进 `sh -c` 命令串
	invalid := []string{
		"x'; id > /tmp/pwned; '",
		"../../etc/passwd",
		"a$(id)",
		"abc",
		"dQw4w9WgXcQ; rm -rf /",
		"dQw4w9WgXcQ`id`",
		"",
	}
	for _, id := range invalid {
		if youtubeVideoIDPattern.MatchString(id) {
			t.Fatalf("非法 video id 被放行: %q", id)
		}
	}
}

func TestValidStorageKey(t *testing.T) {
	// 白名单内的真实键
	valid := []string{
		"solara_state", "favoriteSongs", "playlistSongs", "settings",
		"queueUpdatedAt", "lastPlaybackPosition", "listenHistory",
	}
	for _, k := range valid {
		if !validStorageKey(k) {
			t.Fatalf("合法 key 被拒: %s", k)
		}
	}

	// 字符集合法但不在白名单内 —— 修复前的"任意 key 写入"攻击面
	for _, k := range []string{"user:1", "a.b-c$d", "arbitrary_key"} {
		if validStorageKey(k) {
			t.Fatalf("白名单外 key 被放行: %s", k)
		}
	}

	invalid := []string{
		"arbitrary_attacker_key_12345!!!", // 长度超限
		"key with spaces",
		"key'; DROP TABLE playback_stores; --",
		"",
		"键",
	}
	for _, k := range invalid {
		if validStorageKey(k) {
			t.Fatalf("非法 key 被放行: %q", k)
		}
	}
}
