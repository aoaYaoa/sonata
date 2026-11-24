package container

import (
	"backend/internal/database"
	"backend/internal/repositories"
	"backend/pkg/utils/logger"
)

// managerAvailable 判断数据库管理器是否可用。
//
// 启动阶段数据库不可用时会以 dbManager=nil 继续运行（便于离线开发），
// 但 provider 直接调用 manager.IsMySQL() 会解引用 nil 指针并 panic，
// 实测堆栈：container.ProvideTaskRepository(0x0) → main.main()。
func managerAvailable(manager *database.Manager) bool {
	return manager != nil && manager.Available()
}

// ProvideTaskRepository 根据数据库类型提供 TaskRepository
func ProvideTaskRepository(manager *database.Manager) repositories.TaskRepository {
	if !managerAvailable(manager) {
		logger.Warnf("[Container] 数据库不可用，TaskRepository 降级为内存实现")
		return repositories.NewTaskRepository()
	}
	if manager.IsMySQL() {
		return repositories.NewDBTaskRepository(manager.GetDB())
	}
	return repositories.NewTaskRepository()
}

// ProvideUserRepository 根据数据库类型提供 UserRepository
func ProvideUserRepository(manager *database.Manager) repositories.UserRepository {
	// 使用数据库仓储（支持 PostgreSQL, MySQL 等）
	if !managerAvailable(manager) {
		logger.Warnf("[Container] 数据库不可用，UserRepository 降级为内存实现")
		return repositories.NewUnavailableUserRepository()
	}
	return repositories.NewDBUserRepository(manager.GetDB())
}

// ProvideMenuRepository 提供 MenuRepository
func ProvideMenuRepository(manager *database.Manager) repositories.MenuRepository {
	if !managerAvailable(manager) {
		logger.Warnf("[Container] 数据库不可用，MenuRepository 降级为内存实现")
		return repositories.NewUnavailableMenuRepository()
	}
	return repositories.NewMenuRepository(manager.GetDB())
}
