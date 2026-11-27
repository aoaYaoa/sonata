# 2026-11-27 · 自动切歌的媒体服务交接

- 状态：完成
- 涉及模块：`frontend/lib/services/audio_handler.dart`、`frontend/lib/services/player_controller.dart`

## 原因与预期行为

`just_audio` 在旧曲自然结束后装载新 URL 时会短暂上报 `idle`。macOS 原生探针复现了该事件，`audio_service` 收到从其他状态进入 `idle` 的通知后会调用 `stopService`。自动续播时应将这段交接状态上报为 `loading`，让媒体服务持续运行。

## 范围与业务规则

显式停止仍会上报 `idle`。交接结束后立即同步实际状态。预取缓存下一首的流地址，切歌仍需加载和缓冲音频。

## 实际结果与决策

自动续播且引擎保持播放意图时，媒体处理器将交接阶段的 `idle` 和 `completed` 映射为 `loading`。换源成功或加载失败后结束交接，并同步当时的引擎状态。

## 验证与遗留

- `flutter test --no-pub --reporter expanded` 通过 29 项测试，新增覆盖换源期间的 `idle`、结束交接时的状态同步以及显式停止。
- `dart analyze lib test` 无问题。
- macOS 原生播放器用两段本地音频验证自然切歌。引擎产生了 `idle`，媒体服务收到的是 `loading`，随后第二段音频播完。
- iPhone 14 Pro Max 实测使用两段经本机 HTTP 提供的音频，第二段命中预取，媒体服务在交接中未收到 `idle`，随后第二段完整播完。第一段结束到第二段进入 `ready` 为 54 毫秒。
- Sonata `1.0.0+2` 已通过 `devicectl` 覆盖安装并启动。锁屏和线上音源仍待验证。
