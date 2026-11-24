package database

import (
	"database/sql"
	"fmt"
	"log"
	"strings"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// PostgreSQLDatabase PostgreSQL数据库实现 (用于Supabase)
type PostgreSQLDatabase struct {
	config *DatabaseConfig
	db     *gorm.DB
}

// NewPostgreSQLDatabase 创建PostgreSQL数据库连接
// 使用GORM和PostgreSQL驱动连接数据库，适配Supabase
func NewPostgreSQLDatabase(config *DatabaseConfig) (*PostgreSQLDatabase, error) {
	if config == nil {
		return nil, fmt.Errorf("数据库配置不能为空")
	}

	// 验证配置
	if config.Host == "" {
		return nil, fmt.Errorf("数据库主机不能为空")
	}
	if config.Database == "" {
		return nil, fmt.Errorf("数据库名不能为空")
	}

	// 设置默认端口
	if config.Port == 0 {
		config.Port = 5432 // PostgreSQL默认端口
	}

	db := &PostgreSQLDatabase{
		config: config,
	}

	// 自动建立数据库连接
	if _, err := db.Connect(); err != nil {
		return nil, err
	}

	return db, nil
}

// Connect 连接PostgreSQL数据库
func (d *PostgreSQLDatabase) Connect() (*gorm.DB, error) {
	// 构建 DSN 连接字符串，sslmode 支持从配置传入。
	dsn := buildPostgresDSN(d.config)

	// 使用GORM连接PostgreSQL
	db, err := gorm.Open(postgres.Open(dsn), GormConfig())
	if err != nil {
		return nil, fmt.Errorf("连接PostgreSQL失败: %w", err)
	}

	// 获取底层的*sql.DB以配置连接池
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("获取SQL DB失败: %w", err)
	}

	// 配置连接池
	sqlDB.SetMaxIdleConns(10)           // 最大空闲连接数
	sqlDB.SetMaxOpenConns(100)          // 最大打开连接数
	sqlDB.SetConnMaxLifetime(time.Hour) // 连接最大生命周期

	d.db = db

	log.Printf("PostgreSQL数据库连接成功: %s@%s:%d/%s (Supabase)", d.config.Username, d.config.Host, d.config.Port, d.config.Database)

	return db, nil
}

// buildPostgresDSN 构建 pgx 连接串。
//
// 关于 PgBouncer/Supabase pooler 与 prepared statement 的冲突：
// pooler 的 transaction 模式会复用服务端连接，而 pgx 默认按 SQL 文本缓存
// prepared statement 名称（stmtcache_xxx）。当两条连接复用到同一个后端会话时，
// 第二次 Prepare 会报 `SQLSTATE 42P05 prepared statement ... already exists`，
// Outbox 每 500ms 轮询一次就会把日志刷成 85MB。
//
// 修复要点：
//   - default_query_exec_mode=simple_protocol：走简单查询协议，不发送 Parse/Prepare；
//   - statement_cache_capacity=0：彻底关闭客户端语句缓存；
//   - prefer_simple_protocol 是 pgx v4 的参数名，v5 不认，已移除；
//   - TimeZone 用 URL 编码的 key（pgx 会把它当运行时参数）。
func buildPostgresDSN(cfg *DatabaseConfig) string {
	sslMode := strings.TrimSpace(cfg.SSLMode)
	if sslMode == "" {
		sslMode = "disable"
	}

	params := []string{
		fmt.Sprintf("sslmode=%s", sslMode),
		"TimeZone=Asia/Shanghai",
		"default_query_exec_mode=simple_protocol",
		"statement_cache_capacity=0",
	}
	return fmt.Sprintf(
		"host=%s user=%s password=%s dbname=%s port=%d %s",
		cfg.Host,
		cfg.Username,
		cfg.Password,
		cfg.Database,
		cfg.Port,
		strings.Join(params, " "),
	)
}

// Close 关闭数据库连接
func (d *PostgreSQLDatabase) Close() error {
	if d.db == nil {
		return nil
	}

	sqlDB, err := d.db.DB()
	if err != nil {
		return fmt.Errorf("获取SQL DB失败: %w", err)
	}

	return sqlDB.Close()
}

// GetDB 获取GORM数据库实例
func (d *PostgreSQLDatabase) GetDB() *gorm.DB {
	return d.db
}

// Migrate 执行数据库迁移
// 使用 DisableForeignKeyConstraintWhenMigrating 避免约束冲突
func (d *PostgreSQLDatabase) Migrate(models ...any) error {
	// 逐个迁移模型，忽略已存在表的错误
	for _, model := range models {
		if err := d.db.AutoMigrate(model); err != nil {
			// 记录错误但继续迁移其他表
			log.Printf("警告: 迁移表失败 (可能已存在): %v", err)
		}
	}

	log.Println("PostgreSQL数据库迁移完成")
	return nil
}

// GetDBType 获取数据库类型
func (d *PostgreSQLDatabase) GetDBType() DatabaseType {
	return PostgreSQL
}

// Ping 测试数据库连接
func (d *PostgreSQLDatabase) Ping() error {
	sqlDB, err := d.db.DB()
	if err != nil {
		return fmt.Errorf("获取SQL DB失败: %w", err)
	}

	return sqlDB.Ping()
}

// GetStats 获取数据库连接统计信息
func (d *PostgreSQLDatabase) GetStats() sql.DBStats {
	sqlDB, _ := d.db.DB()
	return sqlDB.Stats()
}
