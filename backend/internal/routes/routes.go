package routes

import (
	"net/http"

	"backend/internal/config"
	"backend/internal/handlers"
	"backend/internal/middlewares"

	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

// buildVersion 由 -ldflags 注入，缺省为 dev。
var buildVersion = "dev"

type Router struct {
	handlers *handlers.Handlers
}

// NewRouter 创建路由实例
func NewRouter(h *handlers.Handlers) *Router {
	return &Router{
		handlers: h,
	}
}

// SetupRoutes 设置路由
func (r *Router) SetupRoutes(engine *gin.Engine) {
	// 初始化IP访问控制
	middlewares.InitIPAccessConfig(&middlewares.IPAccessConfig{
		Whitelist:       config.GetIPWhitelist(),
		Blacklist:       config.GetIPBlacklist(),
		EnableWhitelist: config.AppConfig.EnableIPWhitelist,
		EnableBlacklist: config.AppConfig.EnableIPBlacklist,
	})

	// 构建全局中间件列表
	globalMiddlewares := []gin.HandlerFunc{
		middlewares.RequestID(),                        // 1. 生成请求ID
		middlewares.TraceID(),                          // 2. 生成/透传 TraceID
		middlewares.Metrics(),                          // 2. 指标采集
		middlewares.Logger(),                           // 2. 记录日志
		middlewares.Recovery(),                         // 3. 错误恢复
		middlewares.CORS(config.AppConfig.CORSOrigins), // 4. 跨域支持
		middlewares.Security(),                         // 5. 安全响应头
		middlewares.NoCache(),                          // 6. 禁用缓存（API接口）
		middlewares.ContentType(),                      // 7. 内容类型检查
		middlewares.RateLimit(100, 200),                // 8. 限流：100 req/s, burst 200
	}

	// 根据配置添加IP访问控制中间件
	if config.AppConfig.EnableIPWhitelist || config.AppConfig.EnableIPBlacklist {
		globalMiddlewares = append(globalMiddlewares, middlewares.IPAccessMiddleware()) // 9. IP访问控制
	}

	globalMiddlewares = append(globalMiddlewares, middlewares.Compression()) // 响应压缩

	// 根据配置添加签名验证中间件
	if config.AppConfig.EnableSignature {
		globalMiddlewares = append(globalMiddlewares,
			middlewares.DecryptionMiddleware(), // 请求解密
			middlewares.SignatureMiddleware(),  // API 签名验证
			middlewares.EncryptionMiddleware(), // 响应加密
		)
	}

	// 应用全局中间件
	engine.Use(globalMiddlewares...)

	// 根路径：返回服务标识，不再硬跳 localhost:5173
	// （历史实现把生产请求 302 到开发机的 Vite 端口）
	engine.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"name":    "solara-backend",
			"status":  "ok",
			"version": buildVersion,
		})
	})

	// 健康检查路由
	engine.GET("/health", r.handlers.Health.Check)

	// 运维端点：需要令牌，未配置令牌时在 release 模式下直接 404
	opsGuard := middlewares.RequireToken(
		config.AppConfig.MetricsToken,
		!config.AppConfig.IsProduction(),
	)
	engine.GET("/metrics", opsGuard, middlewares.MetricsHandler())

	// Swagger 文档路由：默认关闭，需 ENABLE_SWAGGER=true 且通过令牌校验
	if config.AppConfig.EnableSwagger {
		engine.GET("/swagger/*any", opsGuard, ginSwagger.WrapHandler(swaggerFiles.Handler))
	}

	// API 路由组
	api := engine.Group("/api")
	{
		// 健康检查
		api.GET("/health", r.handlers.Health.Check)

		// 认证路由（公开访问）
		auth := api.Group("/auth")
		{
			auth.GET("/captcha", r.handlers.Captcha.GetCaptcha)
			auth.POST("/register", r.handlers.User.Register)
			auth.POST("/login", r.handlers.User.Login)
			auth.POST("/app-login", r.handlers.User.AppLogin)
		}

		// 任务管理路由（需要认证）
		// 历史实现注释写"公开访问，无需认证"，实测任意匿名请求即可读取/篡改任务。
		tasks := api.Group("/tasks")
		tasks.Use(middlewares.AuthMiddleware())
		{
			tasks.GET("", r.handlers.Task.GetAllTasks)
			tasks.GET("/:id", r.handlers.Task.GetTask)
			tasks.POST("", r.handlers.Task.CreateTask)
			tasks.PUT("/:id", r.handlers.Task.UpdateTask)
			tasks.DELETE("/:id", r.handlers.Task.DeleteTask)
			tasks.PATCH("/:id/toggle", r.handlers.Task.ToggleTask)
		}

		// 需要认证的路由
		user := api.Group("/user")
		user.Use(middlewares.AuthMiddleware())
		{
			user.GET("/profile", r.handlers.User.GetProfile)
		}

		// 管理员路由
		admin := api.Group("/admin")
		admin.Use(
			middlewares.AuthMiddleware(),
			middlewares.RoleBasedAuth([]string{"admin"}),
		)
		{
			admin.GET("/users", r.handlers.User.ListUsers)
		}
	}

	// 登录：独立严格限流 + 失败锁定（全局 100 req/s 对在线爆破毫无约束）
	login := engine.Group("/api",
		middlewares.RateLimit(0.5, 5),
		middlewares.NewLoginGuard().Middleware(),
	)
	login.POST("/login", r.handlers.Solara.Login)
	engine.GET("/api/storage", r.handlers.Solara.Storage)
	engine.POST("/api/storage", r.handlers.Solara.Storage)
	engine.DELETE("/api/storage", r.handlers.Solara.Storage)
	engine.GET("/proxy", r.handlers.Solara.Proxy)
	engine.GET("/imgproxy", r.handlers.Solara.ImgProxy)

	// Cookie 管理路由
	engine.POST("/api/cookies/upload", r.handlers.Solara.UploadCookie)
	engine.GET("/api/cookies/status", r.handlers.Solara.CookieStatus)

	// Discover 路由
	discover := engine.Group("/api/discover")
	{
		discover.GET("/leaderboard", r.handlers.Solara.DiscoverLeaderboardList)
		discover.GET("/leaderboard/:id", r.handlers.Solara.DiscoverLeaderboardDetail)
		discover.GET("/songlist", r.handlers.Solara.DiscoverSongList)
		discover.GET("/songlist/:id", r.handlers.Solara.DiscoverSongListDetail)
	}

	// 404 处理
	engine.NoRoute(func(c *gin.Context) {
		requestID := middlewares.GetRequestID(c)
		c.JSON(404, gin.H{
			"success":   false,
			"error":     "路由不存在",
			"requestID": requestID,
		})
	})
}
