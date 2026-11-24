package config

import (
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

// MinAppPasswordLength 应用口令最小长度。
// 原值为 8 位小写+数字，实测 30 次登录尝试仅耗时 0.31s 且无限流。
const MinAppPasswordLength = 16

// Config 应用配置结构
type Config struct {
	// 服务器配置
	ServerPort  string
	ServerMode  string
	CORSOrigins []string

	// 数据库配置
	DatabaseType    string
	DatabaseHost    string
	DatabasePort    int
	DatabaseName    string
	DatabaseUser    string
	DatabasePass    string
	DatabaseSSLMode string

	// Redis 配置（用于验证码等缓存）
	RedisAddr      string
	RedisUsername  string
	RedisPassword  string
	RedisDB        int
	RedisTLS       bool
	RedisKeyPrefix string

	// Kafka 配置
	KafkaBrokers          string
	KafkaTopic            string
	KafkaSecurityProtocol string
	KafkaSSLCAFile        string
	KafkaSSLCertFile      string
	KafkaSSLKeyFile       string

	// JWT配置
	JWTSecret string

	// 签名配置
	SignatureSecret  string
	EnableSignature  bool
	EncryptionAESKey string

	// IP访问控制配置
	EnableIPWhitelist bool
	IPWhitelist       string // 逗号分隔的IP列表
	EnableIPBlacklist bool
	IPBlacklist       string // 逗号分隔的IP列表

	// 应用口令（Solara 单口令登录）
	AppPassword string

	// 运行时数据目录（cookie 文件、本地状态）
	CookieDir string

	// 图片代理允许的域名（逗号分隔，支持 ".example.com" 表示子域）
	ImgProxyAllowedHosts []string

	// 媒体流代理允许的域名（逗号分隔）
	MediaProxyAllowedHosts []string

	// 监控端点保护
	MetricsToken string

	// 生产环境开关
	EnableSwagger bool

	// 可信代理（逗号分隔，留空表示不信任任何代理）
	TrustedProxies []string

	// AllowStorageDump 是否允许不带 keys 参数导出全部 storage（默认关闭）
	AllowStorageDump bool

	// StorageExtraKeys 追加允许写入的 storage 键（逗号分隔）
	StorageExtraKeys []string
}

var AppConfig *Config

// LoadConfig 加载配置
// 从.env文件和环境变量读取配置，如果未设置则使用默认值
func LoadConfig() *Config {
	// 加载.env文件
	if err := godotenv.Load(); err != nil {
		log.Printf("警告: 未找到.env文件，使用默认配置: %v", err)
	}

	corsOrigin := getEnv("CORS_ORIGIN", "http://localhost:5173")
	corsOrigins := strings.Split(corsOrigin, ",")
	for i := range corsOrigins {
		corsOrigins[i] = strings.TrimSpace(corsOrigins[i])
	}

	return &Config{
		ServerPort:  getEnv("SERVER_PORT", getEnv("PORT", "8080")),
		ServerMode:  getEnv("SERVER_MODE", "debug"),
		CORSOrigins: corsOrigins,

		// 数据库配置
		DatabaseType:    getEnv("DATABASE_TYPE", "mysql"),
		DatabaseHost:    getEnv("DATABASE_HOST", "localhost"),
		DatabasePort:    getEnvAsInt("DATABASE_PORT", 3306),
		DatabaseName:    getEnv("DATABASE_NAME", "appdb"),
		DatabaseUser:    getEnv("DATABASE_USER", "root"),
		DatabasePass:    getEnv("DATABASE_PASS", ""),
		DatabaseSSLMode: strings.ToLower(getEnv("DATABASE_SSL_MODE", "disable")),

		// Redis 配置
		RedisAddr:      getEnv("REDIS_ADDR", ""),
		RedisUsername:  getEnv("REDIS_USERNAME", ""),
		RedisPassword:  getEnv("REDIS_PASSWORD", ""),
		RedisDB:        getEnvAsInt("REDIS_DB", 0),
		RedisTLS:       getEnvAsBool("REDIS_TLS", false),
		RedisKeyPrefix: getEnv("REDIS_KEY_PREFIX", "captcha:"),

		// Kafka 配置
		KafkaBrokers:          getEnv("KAFKA_BROKERS", ""),
		KafkaTopic:            getEnv("KAFKA_TOPIC", ""),
		KafkaSecurityProtocol: strings.ToUpper(getEnv("KAFKA_SECURITY_PROTOCOL", "SSL")),
		KafkaSSLCAFile:        getEnv("KAFKA_SSL_CA_FILE", ""),
		KafkaSSLCertFile:      getEnv("KAFKA_SSL_CERT_FILE", ""),
		KafkaSSLKeyFile:       getEnv("KAFKA_SSL_KEY_FILE", ""),

		// JWT配置
		JWTSecret: getEnv("JWT_SECRET", "your-secret-key-change-in-production"),

		// 签名配置
		SignatureSecret:  getEnv("SIGNATURE_SECRET", "your-api-signing-secret-change-me"),
		EnableSignature:  getEnvAsBool("ENABLE_SIGNATURE", false),
		EncryptionAESKey: getEnv("ENCRYPTION_AES_KEY", ""),

		// IP访问控制配置
		EnableIPWhitelist: getEnvAsBool("ENABLE_IP_WHITELIST", false),
		IPWhitelist:       getEnv("IP_WHITELIST", ""),
		EnableIPBlacklist: getEnvAsBool("ENABLE_IP_BLACKLIST", false),
		IPBlacklist:       getEnv("IP_BLACKLIST", ""),

		// 应用口令：不再给默认值，空值会在 Validate() 中被拒绝
		AppPassword: getEnv("APP_PASSWORD", ""),

		// 运行时数据目录（替代硬编码 /app）
		CookieDir: getEnv("COOKIE_DIR", "./data"),

		// 图片代理白名单：默认只放行网易云图床
		ImgProxyAllowedHosts: splitAndTrim(getEnv(
			"IMG_PROXY_ALLOWED_HOSTS",
			".music.126.net,.126.net,.127.net,.netease.com",
		)),

		// 媒体流代理白名单
		MediaProxyAllowedHosts: splitAndTrim(getEnv(
			"MEDIA_PROXY_ALLOWED_HOSTS",
			"kuwo.cn,.bilivideo.com,.bilivideo.cn,.bilibili.com,.akamaized.net,.googlevideo.com",
		)),

		MetricsToken:     getEnv("METRICS_TOKEN", ""),
		EnableSwagger:    getEnvAsBool("ENABLE_SWAGGER", false),
		TrustedProxies:   splitAndTrim(getEnv("TRUSTED_PROXIES", "")),
		AllowStorageDump: getEnvAsBool("ALLOW_STORAGE_DUMP", false),
		StorageExtraKeys: splitAndTrim(getEnv("STORAGE_EXTRA_KEYS", "")),
	}
}

// Validate 校验生产必需配置，返回所有问题而不是第一个。
func (c *Config) Validate() error {
	var problems []string

	if strings.TrimSpace(c.AppPassword) == "" {
		problems = append(problems,
			"APP_PASSWORD 未配置。空口令会导致认证完全失效，拒绝启动")
	} else if len(c.AppPassword) < MinAppPasswordLength {
		problems = append(problems, fmt.Sprintf(
			"APP_PASSWORD 长度 %d < %d，易被爆破。请用 `openssl rand -base64 24` 重新生成",
			len(c.AppPassword), MinAppPasswordLength))
	}

	for _, origin := range c.CORSOrigins {
		if origin == "*" {
			problems = append(problems,
				"CORS_ORIGIN 为通配符 *，请改为显式域名（如 https://solara.example.com）")
			break
		}
	}

	if len(problems) > 0 {
		return fmt.Errorf("配置校验失败:\n  - %s", strings.Join(problems, "\n  - "))
	}
	return nil
}

// IsProduction 判断是否处于 release 模式。
func (c *Config) IsProduction() bool {
	return strings.EqualFold(c.ServerMode, "release")
}

// splitAndTrim 按逗号切分并去除空白与空项。
func splitAndTrim(v string) []string {
	if strings.TrimSpace(v) == "" {
		return nil
	}
	items := strings.Split(v, ",")
	out := make([]string, 0, len(items))
	for _, item := range items {
		item = strings.TrimSpace(item)
		if item != "" {
			out = append(out, item)
		}
	}
	return out
}

// Init 初始化配置
func Init() {
	AppConfig = LoadConfig()
	log.Printf("配置加载成功:")
	log.Printf("  - Port: %s", AppConfig.ServerPort)
	log.Printf("  - Mode: %s", AppConfig.ServerMode)
	log.Printf("  - Database: %s@%s:%d/%s", AppConfig.DatabaseType, AppConfig.DatabaseHost, AppConfig.DatabasePort, AppConfig.DatabaseName)
	log.Printf("  - Database SSLMode: %s", AppConfig.DatabaseSSLMode)
	if AppConfig.RedisAddr == "" {
		log.Printf("  - Redis: disabled")
	} else {
		log.Printf("  - Redis: %s (db=%d, tls=%v)", AppConfig.RedisAddr, AppConfig.RedisDB, AppConfig.RedisTLS)
	}
	if AppConfig.KafkaBrokers == "" || AppConfig.KafkaTopic == "" {
		log.Printf("  - Kafka: disabled")
	} else {
		log.Printf("  - Kafka: %s topic=%s protocol=%s",
			AppConfig.KafkaBrokers, AppConfig.KafkaTopic, AppConfig.KafkaSecurityProtocol)
	}
	log.Printf("  - 签名验证: %v", AppConfig.EnableSignature)
	if AppConfig.EnableSignature {
		log.Printf("  - AES 密钥已配置: %v", strings.TrimSpace(AppConfig.EncryptionAESKey) != "")
	}
	log.Printf("  - IP白名单: %v (启用: %v)", AppConfig.IPWhitelist, AppConfig.EnableIPWhitelist)
	log.Printf("  - IP黑名单: %v (启用: %v)", AppConfig.IPBlacklist, AppConfig.EnableIPBlacklist)
	log.Printf("  - 应用口令: %s", maskSecret(AppConfig.AppPassword))
	log.Printf("  - Cookie 目录: %s", AppConfig.CookieDir)
	log.Printf("  - 图片代理白名单: %v", AppConfig.ImgProxyAllowedHosts)
	log.Printf("  - 媒体代理白名单: %v", AppConfig.MediaProxyAllowedHosts)
	log.Printf("  - Swagger: %v / Metrics 保护: %v",
		AppConfig.EnableSwagger, strings.TrimSpace(AppConfig.MetricsToken) != "")

	if err := AppConfig.Validate(); err != nil {
		log.Printf("❌ %v", err)
		panic(err)
	}
}

// maskSecret 返回不泄露内容的密钥描述，用于启动日志核验。
func maskSecret(v string) string {
	if strings.TrimSpace(v) == "" {
		return "<未配置>"
	}
	return fmt.Sprintf("已配置(长度=%d)", len(v))
}

// GetIPWhitelist 获取IP白名单
func GetIPWhitelist() []string {
	if !AppConfig.EnableIPWhitelist || AppConfig.IPWhitelist == "" {
		return []string{}
	}
	whitelist := strings.Split(AppConfig.IPWhitelist, ",")
	for i := range whitelist {
		whitelist[i] = strings.TrimSpace(whitelist[i])
	}
	return whitelist
}

// GetIPBlacklist 获取IP黑名单
func GetIPBlacklist() []string {
	if !AppConfig.EnableIPBlacklist || AppConfig.IPBlacklist == "" {
		return []string{}
	}
	blacklist := strings.Split(AppConfig.IPBlacklist, ",")
	for i := range blacklist {
		blacklist[i] = strings.TrimSpace(blacklist[i])
	}
	return blacklist
}

// getEnv 从环境变量获取值，如果不存在则返回默认值
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvAsInt 从环境变量获取整数值
func getEnvAsInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}

// getEnvAsBool 从环境变量获取布尔值
func getEnvAsBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		if boolVal, err := strconv.ParseBool(value); err == nil {
			return boolVal
		}
	}
	return defaultValue
}
