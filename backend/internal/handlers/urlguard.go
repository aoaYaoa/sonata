package handlers

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"syscall"
	"time"
)

// ErrHostNotAllowed 目标域名不在白名单内。
var ErrHostNotAllowed = errors.New("目标域名不在允许列表内")

// ErrPrivateAddress 目标解析到内网/回环/链路本地地址。
var ErrPrivateAddress = errors.New("目标地址位于内网范围")

// hostInAllowlist 判断 host 是否命中白名单。
//
// 白名单条目语义（务必与 strings.HasSuffix 的裸用法区分开）：
//   - "kuwo.cn"        精确匹配 host == "kuwo.cn"
//   - ".kuwo.cn"       子域匹配 host 以 ".kuwo.cn" 结尾
//   - "www.kuwo.cn"    精确匹配该主机
//
// 历史上这里用的是 strings.HasSuffix(host, "kuwo.cn")，
// 攻击者注册 evilkuwo.cn / notbilibili.com 即可通过校验，
// 配合 skip-auth 分支构成开放代理 + SSRF。
func hostInAllowlist(host string, allowlist []string) bool {
	host = strings.ToLower(strings.TrimSuffix(strings.TrimSpace(host), "."))
	if host == "" {
		return false
	}
	for _, pattern := range allowlist {
		p := strings.ToLower(strings.TrimSpace(pattern))
		if p == "" {
			continue
		}
		if strings.HasPrefix(p, ".") {
			// 子域匹配：要求 host 以 ".pattern" 结尾，且不是 pattern 本身
			if strings.HasSuffix(host, p) {
				return true
			}
			continue
		}
		if host == p {
			return true
		}
	}
	return false
}

// isDisallowedIP 判断 IP 是否属于必须拒绝的地址族。
func isDisallowedIP(ip net.IP) bool {
	if ip == nil {
		return true
	}
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
		ip.IsLinkLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified() {
		return true
	}
	// 云元数据服务常用 169.254.169.254（已被 IsLinkLocalUnicast 覆盖），
	// 这里补充 IPv6 唯一本地地址段与 0.0.0.0/8。
	if ip.To4() == nil && (ip.IsInterfaceLocalMulticast() || ip.IsLinkLocalUnicast()) {
		return true
	}
	if v4 := ip.To4(); v4 != nil && v4[0] == 0 {
		return true
	}
	return false
}

// resolveAndCheckHost 解析域名并确认所有解析结果都是公网地址。
//
// 必须在建立连接前调用，否则可被 DNS rebinding 绕过
// （第一次解析返回公网 IP 通过校验，连接时解析到 127.0.0.1）。
// 生产环境更稳的做法是自定义 http.Transport.DialContext 在拨号时校验实际 IP，
// 这里的实现覆盖了常见场景。
func resolveAndCheckHost(ctx context.Context, host string) error {
	if ip := net.ParseIP(host); ip != nil {
		if isDisallowedIP(ip) {
			return ErrPrivateAddress
		}
		return nil
	}

	lookupCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	addrs, err := net.DefaultResolver.LookupIPAddr(lookupCtx, host)
	if err != nil {
		return fmt.Errorf("域名解析失败: %w", err)
	}
	if len(addrs) == 0 {
		return errors.New("域名无解析结果")
	}
	for _, addr := range addrs {
		if isDisallowedIP(addr.IP) {
			return ErrPrivateAddress
		}
	}
	return nil
}

// validateProxyTarget 校验待代理 URL：仅允许 http/https，
// 域名命中白名单，且解析结果不含内网地址。
func validateProxyTarget(ctx context.Context, rawURL string, allowlist []string) (*url.URL, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, errors.New("无效的目标地址")
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return nil, fmt.Errorf("不支持的协议: %s", parsed.Scheme)
	}
	host := parsed.Hostname()
	if host == "" {
		return nil, errors.New("目标地址缺少主机名")
	}
	if !hostInAllowlist(host, allowlist) {
		return nil, ErrHostNotAllowed
	}
	if err := resolveAndCheckHost(ctx, host); err != nil {
		return nil, err
	}
	return parsed, nil
}

// safeDialControl 供 http.Transport.DialContext 使用的兜底校验，
// 在真正建立 TCP 连接前再检查一次目标 IP，挡住 DNS rebinding。
func safeDialControl(network, address string, _ syscall.RawConn) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return err
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return nil
	}
	if isDisallowedIP(ip) {
		return ErrPrivateAddress
	}
	return nil
}

// newGuardedHTTPClient 构造一个带 IP 兜底校验的 HTTP 客户端。
// timeout <= 0 表示不设整体超时（流媒体代理需要，见 proxyRequest 注释）。
func newGuardedHTTPClient(timeout time.Duration) *http.Client {
	dialer := &net.Dialer{
		Timeout:   15 * time.Second,
		KeepAlive: 30 * time.Second,
		Control:   safeDialControl,
	}
	transport := &http.Transport{
		DialContext:           dialer.DialContext,
		MaxIdleConns:          50,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
	}
	return &http.Client{Transport: transport, Timeout: timeout}
}
