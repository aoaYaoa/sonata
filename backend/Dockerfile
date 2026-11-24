# ── 构建阶段 ───────────────────────────────────────────────────────
FROM golang:1.26-alpine AS builder

ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    GOPROXY="https://goproxy.cn,direct"

WORKDIR /app

# 先只拷依赖清单，最大化利用构建缓存
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# -trimpath 去掉本机绝对路径；-ldflags 注入版本号便于线上核对
ARG VERSION=dev
RUN go build -trimpath \
      -ldflags "-s -w -X backend/internal/routes.buildVersion=${VERSION}" \
      -o main ./cmd/server

# ── 运行阶段 ───────────────────────────────────────────────────────
# 固定小版本，避免 alpine:latest 漂移带来的不可复现构建
FROM alpine:3.20

# yt-dlp 用于 YouTube 源；node 是 yt-dlp 解签名所需 JS 运行时。
# 历史镜像只装了 ca-certificates/tzdata，容器内 YouTube 搜索与取流必失败。
RUN apk --no-cache add \
      ca-certificates \
      tzdata \
      python3 \
      py3-pip \
      nodejs \
      ffmpeg && \
    pip install --no-cache-dir --break-system-packages yt-dlp && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

# 以非 root 运行；cookie 与数据目录归该用户所有
RUN addgroup -S solara && adduser -S -G solara -h /app solara

WORKDIR /app
COPY --from=builder /app/main .

RUN mkdir -p /app/data /app/logs && chown -R solara:solara /app
USER solara

ENV COOKIE_DIR=/app/data

EXPOSE 8080

# 健康检查：/health 在依赖降级时返回 503，用 200 判定进程可用性
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health >/dev/null 2>&1 || exit 1

CMD ["./main"]
