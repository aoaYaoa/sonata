package database

import (
	"backend/internal/config"
	"backend/internal/models"
	"backend/pkg/utils/logger"
	"context"
	"fmt"

	"gorm.io/gorm"
)

// Manager 数据库管理器
// 负责数据库的初始化、连接管理和迁移
type Manager struct {
	db Database
}

// NewManager 创建数据库管理器实例
// 根据配置自动选择并初始化数据库
func NewManager(cfg *config.Config) (*Manager, error) {
	// 创建数据库配置
	dbConfig := &DatabaseConfig{
		Type:     DatabaseType(cfg.DatabaseType),
		Host:     cfg.DatabaseHost,
		Port:     cfg.DatabasePort,
		Database: cfg.DatabaseName,
		Username: cfg.DatabaseUser,
		Password: cfg.DatabasePass,
		SSLMode:  cfg.DatabaseSSLMode,
	}

	// 根据类型创建数据库连接
	db, err := NewDatabase(dbConfig)
	if err != nil {
		return nil, fmt.Errorf("创建数据库连接失败: %w", err)
	}

	// 测试数据库连接
	if err := Ping(db.GetDB()); err != nil {
		return nil, fmt.Errorf("数据库连接测试失败: %w", err)
	}

	manager := &Manager{
		db: db,
	}

	logger.Infof("数据库管理器初始化成功: 类型=%s", db.GetDBType())
	return manager, nil
}

// available 判断管理器是否持有可用连接。
//
// 启动阶段数据库不可用时会以 dbManager=nil 继续运行，
// 因此所有导出方法都必须先做 nil 检查，否则会在运行时 panic。
func (m *Manager) available() bool {
	return m != nil && m.db != nil
}

// Available 对外暴露可用性判断，供容器与健康检查使用。
func (m *Manager) Available() bool {
	return m.available()
}

// GetDB 获取GORM数据库实例
// 用于在Repository层进行数据库操作。
// 数据库不可用时返回 nil，调用方需自行判断（仓储层已做降级）。
func (m *Manager) GetDB() *gorm.DB {
	if !m.available() {
		return nil
	}
	return m.db.GetDB()
}

// Migrate 执行数据库迁移
// 自动创建或更新所有模型对应的表结构
func (m *Manager) Migrate() error {
	if !m.available() {
		return fmt.Errorf("数据库不可用，跳过迁移")
	}
	logger.Info("开始执行数据库迁移...")

	// 列出所有需要迁移的模型
	modelsToMigrate := []any{
		&models.User{},
		&models.Role{},
		&models.Menu{},
		&models.UserRole{},
		&models.RoleMenu{},
		&models.PlaybackStore{},
		&models.FavoritesStore{},
	}

	// 执行迁移
	if err := m.db.Migrate(modelsToMigrate...); err != nil {
		return fmt.Errorf("数据库迁移失败: %w", err)
	}

	logger.Info("数据库迁移完成")
	return nil
}

// Close 关闭数据库连接
// 应该在应用退出时调用
func (m *Manager) Close() error {
	if !m.available() {
		return nil
	}
	logger.Info("正在关闭数据库连接...")
	if err := m.db.Close(); err != nil {
		return fmt.Errorf("关闭数据库连接失败: %w", err)
	}
	logger.Info("数据库连接已关闭")
	return nil
}

// GetDatabaseType 获取当前数据库类型
func (m *Manager) GetDatabaseType() DatabaseType {
	if !m.available() {
		return ""
	}
	return m.db.GetDBType()
}

// IsMySQL 判断是否为MySQL数据库
func (m *Manager) IsMySQL() bool {
	return m.GetDatabaseType() == MySQL
}

// Ping 测试数据库连接状态（用于健康检查）。
func (m *Manager) Ping(ctx context.Context) error {
	if ctx == nil {
		ctx = context.Background()
	}
	if !m.available() {
		return fmt.Errorf("数据库未连接")
	}

	db := m.db.GetDB()
	if db == nil {
		return fmt.Errorf("database instance is nil")
	}

	sqlDB, err := db.WithContext(ctx).DB()
	if err != nil {
		return fmt.Errorf("get sql db failed: %w", err)
	}

	if err := sqlDB.PingContext(ctx); err != nil {
		return fmt.Errorf("ping db failed: %w", err)
	}

	return nil
}
