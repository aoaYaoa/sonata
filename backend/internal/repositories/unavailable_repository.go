package repositories

import (
	"backend/internal/models"
	"context"
	"errors"

	"github.com/google/uuid"
)

// ErrRepositoryUnavailable 数据库不可用时由降级仓储返回。
var ErrRepositoryUnavailable = errors.New("数据库不可用，该功能暂不可用")

// unavailableUserRepository 是 UserRepository 的降级实现。
//
// 启动阶段数据库连接失败时，容器曾直接把 nil *gorm.DB 交给 DB 仓储，
// 后续任何调用都会解引用空指针。这里提供一个显式报错的空对象，
// 让 /health 与不依赖数据库的接口仍可提供服务。
type unavailableUserRepository struct{}

// NewUnavailableUserRepository 创建不可用状态的用户仓储。
func NewUnavailableUserRepository() UserRepository {
	return &unavailableUserRepository{}
}

func (r *unavailableUserRepository) Create(context.Context, *models.User) (*models.User, error) {
	return nil, ErrRepositoryUnavailable
}

func (r *unavailableUserRepository) FindByID(context.Context, uuid.UUID) (*models.User, error) {
	return nil, ErrRepositoryUnavailable
}

func (r *unavailableUserRepository) FindByUsername(context.Context, string) (*models.User, error) {
	return nil, ErrRepositoryUnavailable
}

func (r *unavailableUserRepository) FindByEmail(context.Context, string) (*models.User, error) {
	return nil, ErrRepositoryUnavailable
}

func (r *unavailableUserRepository) Update(context.Context, *models.User) (*models.User, error) {
	return nil, ErrRepositoryUnavailable
}

func (r *unavailableUserRepository) Delete(context.Context, uuid.UUID) error {
	return ErrRepositoryUnavailable
}

func (r *unavailableUserRepository) List(context.Context) ([]*models.User, error) {
	return nil, ErrRepositoryUnavailable
}

// unavailableMenuRepository 是 MenuRepository 的降级实现。
type unavailableMenuRepository struct{}

// NewUnavailableMenuRepository 创建不可用状态的菜单仓储。
func NewUnavailableMenuRepository() MenuRepository {
	return &unavailableMenuRepository{}
}

func (r *unavailableMenuRepository) FindByRoleIDs(context.Context, []uuid.UUID) ([]*models.Menu, error) {
	return nil, ErrRepositoryUnavailable
}

func (r *unavailableMenuRepository) FindAll(context.Context) ([]*models.Menu, error) {
	return nil, ErrRepositoryUnavailable
}
