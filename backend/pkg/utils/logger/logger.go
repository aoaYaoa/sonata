package logger

import (
	"flag"
	"io"
	"log"
	"os"
	"path/filepath"
	"regexp"
)

var (
	InfoLogger  *log.Logger
	ErrorLogger *log.Logger
	DebugLogger *log.Logger
	WarnLogger  *log.Logger
)

// init 先绑定标准库默认 logger，保证任何在 logger.Init() 之前发生的
// 日志调用（单元测试、包级 init、中间件早期路径）不会解引用 nil 崩溃。
// 历史实现里这四个变量在 Init() 前都是 nil，一次 Warnf 就是 SIGSEGV。
func init() {
	InfoLogger = log.Default()
	ErrorLogger = log.Default()
	DebugLogger = log.Default()
	WarnLogger = log.Default()
}

// ANSI Color Codes
const (
	Reset   = "\033[0m"
	Red     = "\033[31m"
	Green   = "\033[32m"
	Yellow  = "\033[33m"
	Blue    = "\033[34m"
	Magenta = "\033[35m"
	Cyan    = "\033[36m"
)

// StripANSIWriter 用于去除 ANSI 颜色代码的 Writer
type StripANSIWriter struct {
	w  io.Writer
	re *regexp.Regexp
}

func NewStripANSIWriter(w io.Writer) *StripANSIWriter {
	return &StripANSIWriter{
		w:  w,
		re: regexp.MustCompile(`\x1b\[[0-9;]*m`),
	}
}

func (w *StripANSIWriter) Write(p []byte) (n int, err error) {
	// 去除 ANSI 代码
	clean := w.re.ReplaceAll(p, []byte(""))
	return w.w.Write(clean)
}

// logDir 返回日志目录。
//
// 历史上这里硬编码相对路径 "logs"，而 logger 是按“当前工作目录”解析相对路径的，
// 于是 `go test ./internal/services` 会在 backend/internal/services/logs/ 下建目录，
// `go test ./pkg/utils/jwt` 同理 —— 日志散落在各包目录里。
// 现在统一读 LOG_DIR（默认 logs），测试进程默认不落盘。
func logDir() string {
	if dir := os.Getenv("LOG_DIR"); dir != "" {
		return dir
	}
	return "logs"
}

// runningUnderTest 判断当前进程是否是 go test 生成的测试二进制。
func runningUnderTest() bool {
	return flag.Lookup("test.v") != nil
}

func Init() {
	// 创建按天轮转的日志写入器
	// 日志保存到 LOG_DIR（默认 ./logs），文件名为 app-YYYY-MM-DD.log
	var fileWriter io.Writer
	if runningUnderTest() && os.Getenv("LOG_DIR") == "" {
		// 测试进程不写文件，避免在各包目录下生成 logs/
		fileWriter = io.Discard
	} else {
		fileWriter = NewStripANSIWriter(NewDailyWriter(logDir(), "app"))
	}

	// 组合写入器：同时输出到控制台和文件
	// Info/Debug/Warn -> 标准输出 + 文件
	// 控制台保留颜色，文件去除颜色
	outWriter := io.MultiWriter(os.Stdout, fileWriter)

	// Error -> 标准错误 + 文件
	errWriter := io.MultiWriter(os.Stderr, fileWriter)

	// 使用带颜色的前缀初始化 Logger
	// Info: 绿色
	InfoLogger = log.New(outWriter, Green+"[INFO] "+Reset, log.Ldate|log.Ltime|log.Lshortfile)
	// Error: 红色
	ErrorLogger = log.New(errWriter, Red+"[ERROR] "+Reset, log.Ldate|log.Ltime|log.Lshortfile)
	// Debug: 青色
	DebugLogger = log.New(outWriter, Cyan+"[DEBUG] "+Reset, log.Ldate|log.Ltime|log.Lshortfile)
	// Warn: 黄色
	WarnLogger = log.New(outWriter, Yellow+"[WARN] "+Reset, log.Ldate|log.Ltime|log.Lshortfile)
}

// InitWithDir 显式指定日志目录（供 main 从配置读取后调用）。
func InitWithDir(dir string) {
	if dir != "" {
		_ = os.Setenv("LOG_DIR", filepath.Clean(dir))
	}
	Init()
}

func Info(v ...any) {
	InfoLogger.Println(v...)
}

func Error(v ...any) {
	ErrorLogger.Println(v...)
}

func Debug(v ...any) {
	DebugLogger.Println(v...)
}

func Warn(v ...any) {
	WarnLogger.Println(v...)
}

func Infof(format string, v ...any) {
	InfoLogger.Printf(format, v...)
}

func Errorf(format string, v ...any) {
	ErrorLogger.Printf(format, v...)
}

func Debugf(format string, v ...any) {
	DebugLogger.Printf(format, v...)
}

func Warnf(format string, v ...any) {
	WarnLogger.Printf(format, v...)
}
