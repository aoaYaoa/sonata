.PHONY: run build test lint clean docker-build swag

# 变量定义
APP_NAME=backend
MAIN_FILE=cmd/server/main.go
BUILD_DIR=bin

# 开发运行 (优先尝试 air)
dev:
	@if command -v air > /dev/null; then \
		air; \
	else \
		echo "Air not found, using 'go run'..."; \
		go run $(MAIN_FILE); \
	fi

# 普通运行
run:
	go run $(MAIN_FILE)

# 编译
build:
	mkdir -p $(BUILD_DIR)
	go build -o $(BUILD_DIR)/$(APP_NAME) $(MAIN_FILE)

# 测试
test:
	go test ./...

# 代码检查（未安装 golangci-lint 时回退到 go vet）
lint:
	@if command -v golangci-lint > /dev/null; then \
		golangci-lint run; \
	else \
		echo "golangci-lint not found, falling back to 'go vet' + 'gofmt'"; \
		go vet ./... && test -z "$$(gofmt -l . | grep -v '^.gocache/')"; \
	fi

# 格式化
fmt:
	gofmt -w $$(find . -name '*.go' -not -path './.gocache/*')

# 竞态检测
test-race:
	go test -race ./...

# 覆盖率
cover:
	go test -coverprofile=coverage.out ./... && go tool cover -func=coverage.out

# 清理
clean:
	rm -rf $(BUILD_DIR)

# Docker 相关命令
docker-build:
	docker build -t $(APP_NAME) .

docker-run:
	docker run -p 8080:8080 $(APP_NAME)

# 本仓库没有 docker-compose.yml，改用单容器命令，
# 历史 target 会直接报 "no such file"。
docker-run-prod:
	docker run --rm -p 8080:8080 \
		--env-file .env \
		-v $$(pwd)/data:/app/data \
		-v $$(pwd)/logs:/app/logs \
		$(APP_NAME)

docker-stop:
	docker stop $$(docker ps -aq --filter ancestor=$(APP_NAME)) 2>/dev/null || true

# 生成 Swagger 文档
swag:
	swag init -g $(MAIN_FILE) -o docs --parseDependency --parseInternal

# 帮助
help:
	@echo "make run    - 运行服务"
	@echo "make build  - 编译服务"
	@echo "make test   - 运行测试"
	@echo "make clean  - 清理构建文件"
	@echo "make fmt    - 格式化代码"
	@echo "make lint   - 静态检查"
	@echo "make test-race - 竞态测试"
	@echo "make cover  - 覆盖率报告"
	@echo "make swag   - 生成 Swagger 文档"
