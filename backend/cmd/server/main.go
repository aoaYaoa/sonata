package main

import (
	"backend/internal/config"
	"backend/internal/container"
	"backend/internal/database"
	"backend/internal/messaging"
	"backend/internal/middlewares"
	"backend/pkg/utils/captcha"
	"backend/pkg/utils/jwt"
	"backend/pkg/utils/logger"
	"context"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	_ "backend/docs" // 导入 Swagger 文档

	"github.com/gin-gonic/gin"
)

// @title Solara API
// @version 1.0
// @description Solara 多平台音乐播放器后端 API（搜索/播放地址/发现页/云同步）
// @termsOfService http://swagger.io/terms/

// @contact.name Solara Maintainer
// @contact.url https://github.com/uonoe/solara
// @contact.email maintainer@uonoe.com

// @license.name Apache 2.0
// @license.url http://www.apache.org/licenses/LICENSE-2.0.html

// @host localhost:8080
// @BasePath /

// @securityDefinitions.apikey Bearer
// @in header
// @name Authorization

func main() {
	// 初始化配置
	config.Init()

	// 初始化日志（目录可配置，避免日志按当前工作目录散落）
	logger.Init()

	// 初始化 JWT 默认密钥（供登录与鉴权统一使用）
	if err := jwt.SetDefaultSecret(config.AppConfig.JWTSecret); err != nil {
		logger.Errorf("JWT 配置无效: %v", err)
		panic(err)
	}
	// 只打印密钥指纹，便于多环境核验"是否用了同一把密钥"，
	// 又不把密钥本身写进日志/日志采集系统。
	logger.Infof("JWT 密钥指纹: %s", jwt.SecretFingerprint(config.AppConfig.JWTSecret))

	// 启用签名校验时，强制要求配置有效 AES 密钥。
	if config.AppConfig.EnableSignature {
		if err := middlewares.SetEncryptionKey(config.AppConfig.EncryptionAESKey); err != nil {
			logger.Errorf("签名/加密配置无效: %v", err)
			panic(err)
		}
	}

	// 初始化验证码存储（优先 Redis，失败自动回退内存）
	captcha.InitStoreWithConfig(captcha.StoreConfig{
		Addr:      config.AppConfig.RedisAddr,
		Username:  config.AppConfig.RedisUsername,
		Password:  config.AppConfig.RedisPassword,
		DB:        config.AppConfig.RedisDB,
		UseTLS:    config.AppConfig.RedisTLS,
		KeyPrefix: config.AppConfig.RedisKeyPrefix,
	})

	// 设置 Gin 模式
	gin.SetMode(config.AppConfig.ServerMode)

	// 创建 Gin 引擎
	r := gin.New()

	// 初始化数据库（失败时降级运行，不影响不依赖DB的API）
	dbManager, err := database.NewManager(config.AppConfig)
	if err != nil {
		logger.Warnf("数据库初始化失败，部分功能不可用: %v", err)
		dbManager = nil
	} else {
		defer dbManager.Close()
	}

	// 初始化 Kafka 发布器（失败回退 noop，不影响核心业务）
	publisher := messaging.NewNoopPublisher()
	if config.AppConfig.KafkaBrokers != "" && config.AppConfig.KafkaTopic != "" {
		brokers := splitCSV(config.AppConfig.KafkaBrokers)
		kafkaPublisher, kafkaErr := messaging.NewKafkaPublisher(messaging.KafkaConfig{
			Brokers:      brokers,
			Topic:        config.AppConfig.KafkaTopic,
			CAFile:       config.AppConfig.KafkaSSLCAFile,
			CertFile:     config.AppConfig.KafkaSSLCertFile,
			KeyFile:      config.AppConfig.KafkaSSLKeyFile,
			RequireTLS:   strings.EqualFold(config.AppConfig.KafkaSecurityProtocol, "SSL"),
			WriteTimeout: 5 * time.Second,
		})
		if kafkaErr != nil {
			logger.Warnf("Kafka 初始化失败，将禁用事件发布: %v", kafkaErr)
		} else {
			publisher = messaging.NewAsyncPublisher(kafkaPublisher, messaging.AsyncPublisherConfig{
				QueueSize:       512,
				WorkerCount:     2,
				PublishTimeout:  2 * time.Second,
				MaxRetries:      2,
				RetryBackoff:    150 * time.Millisecond,
				ShutdownTimeout: 3 * time.Second,
			})

			outboxStore, outboxErr := messaging.NewGormOutboxStore(dbManager.GetDB())
			if outboxErr != nil {
				logger.Warnf("Outbox 初始化失败，将仅使用异步发布: %v", outboxErr)
			} else {
				publisher = messaging.NewOutboxPublisher(outboxStore, publisher, messaging.OutboxPublisherConfig{
					// 轮询间隔从 500ms 提到 3s：
					// 原值在数据库异常时每秒刷两条错误日志，实测把 backend/logs 刷到 85MB。
					PollInterval:        3 * time.Second,
					BatchSize:           100,
					PublishTimeout:      2 * time.Second,
					MaxDeliveryAttempts: 6,
					RetryBackoff:        200 * time.Millisecond,
					CleanupInterval:     10 * time.Minute,
					SentRetention:       7 * 24 * time.Hour,
					CleanupBatchSize:    1000,
					ShutdownTimeout:     5 * time.Second,
				})
				logger.Infof("Kafka Outbox 已启用: table=event_outbox")
			}

			defer func() {
				if err := publisher.Close(); err != nil {
					logger.Warnf("关闭 Kafka 发布器失败: %v", err)
				}
			}()
			logger.Infof("Kafka 事件发布已启用(异步重试+Outbox): brokers=%s topic=%s",
				config.AppConfig.KafkaBrokers, config.AppConfig.KafkaTopic)
		}
	}

	if dbManager != nil {
		if err := dbManager.Migrate(); err != nil {
			logger.Warnf("数据库迁移警告（可能是表已存在）: %v", err)
		}
	}

	// 初始化依赖容器
	appContainer, err := container.InitializeContainer(dbManager, publisher)
	if err != nil {
		logger.Errorf("依赖注入容器初始化失败: %v", err)
		panic(err)
	}
	appContainer.Router.SetupRoutes(r)

	// 配置可信代理 (消除启动警告)
	// 在生产环境中，应该设置为实际的负载均衡器或反向代理的 IP
	// 这里设置为 nil 表示不信任任何代理，或者设置为 "*" 信任所有（仅限内网安全环境）
	trustedProxies := config.AppConfig.TrustedProxies
	if err := r.SetTrustedProxies(trustedProxies); err != nil {
		logger.Warnf("设置可信代理失败: %v", err)
	}
	if len(trustedProxies) == 0 {
		logger.Infof("未配置 TRUSTED_PROXIES，c.ClientIP() 使用直连地址（限流/审计按真实来源计数）")
	}

	// 启动服务器配置
	addr := ":" + config.AppConfig.ServerPort
	srv := &http.Server{
		Addr:    addr,
		Handler: r,
	}

	// 在 goroutine 中启动服务器
	go func() {
		logger.Infof("服务器启动在 http://localhost%s", addr)
		logger.Infof("数据库类型: %s", dbManager.GetDatabaseType())
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Errorf("服务器启动失败: %v", err)
			panic(err)
		}
	}()

	// 等待中断信号以优雅地关闭服务器（设置 5 秒的超时时间）
	quit := make(chan os.Signal, 1)
	// kill (no param) default send syscall.SIGTERM
	// kill -2 is syscall.SIGINT
	// kill -9 is syscall.SIGKILL but can't be caught, so don't need to add it
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	logger.Info("正在关闭服务器...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Errorf("服务器强制关闭: %v", err)
	}

	logger.Info("服务器已退出")
}

func splitCSV(v string) []string {
	items := strings.Split(v, ",")
	result := make([]string, 0, len(items))
	for _, item := range items {
		item = strings.TrimSpace(item)
		if item != "" {
			result = append(result, item)
		}
	}
	return result
}
