import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/api/api_client.dart';
import '../data/providers.dart';
import 'debug_log_bus.dart';

const _kTokenKey = 'jwt_token';

/// 内置口令：通过 `--dart-define=SOLARA_PASS=xxx` 在构建期注入。
///
/// 前端不展示登录页，启动时用它静默换取 token；只有自动登录失败
/// （服务不可达 / 口令被改）时才回落到兜底页。
///
/// 这里**不写默认值**：仓库是公开的，把生产口令写进源码等于公开它，
/// 而且会永久留在 git 历史里。不传 `--dart-define` 时该常量为空串，
/// `restoreSession()` 会跳过静默登录、直接落到兜底页。
const _defaultPassword = String.fromEnvironment('SOLARA_PASS');

/// 会话内的口令缓存。
///
/// 历史实现把明文口令写进 shared_preferences 的 `user_password` 键，
/// 该文件在 Android 上是应用私有目录里的明文 XML、在桌面端是
/// 用户主目录下的明文 JSON，root/越狱或备份导出即可直接读取。
/// 现在口令只留在内存：应用存活期间 token 过期可静默续签，
/// 进程重启后回落到 [_defaultPassword] 重新换 token（见 restoreSession）。
String? _sessionPassword;

class AuthState {
  final bool isAuthed;
  const AuthState({required this.isAuthed});
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  final ApiClient client;

  AuthStateNotifier({required this.client})
    : super(const AuthState(isAuthed: false)) {
    client.onTokenExpired = autoRelogin;
  }

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kTokenKey);
    if (token != null && token.isNotEmpty) {
      client.setToken(token);
      // 本地有 token 直接信任，避免网络慢时长时间白屏
      // token 真正过期时会在 API 调用时触发 autoRelogin
      state = const AuthState(isAuthed: true);
      return;
    }

    // 本地没有 token：用内置口令静默登录，用户看不到登录页。
    // 失败则停在未登录态，由 UI 决定是否展示登录入口。
    if (_defaultPassword.isNotEmpty) {
      final ok = await login('', _defaultPassword);
      if (ok) return;
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      final response = await client.dio.post(
        '/api/login',
        data: {'password': password},
      );
      final data = response.data;
      DebugLogBus.add('[AuthService] login status=${response.statusCode}');
      if (data is! Map || data['success'] != true) {
        state = const AuthState(isAuthed: false);
        return false;
      }
      final token = data['data']?['token'] as String?;
      if (token == null || token.isEmpty) {
        state = const AuthState(isAuthed: false);
        return false;
      }
      client.setToken(token);
      _sessionPassword = password;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTokenKey, token);
      state = const AuthState(isAuthed: true);
      return true;
    } catch (e) {
      DebugLogBus.add('[AuthService] login error: $e');
      state = const AuthState(isAuthed: false);
      return false;
    }
  }

  Future<bool> autoRelogin() async {
    final password = _sessionPassword;
    if (password == null || password.isEmpty) {
      // 进程重启后没有内存中的口令，无法静默续签。
      // 只有「本地仍有 token」时才需要把用户拽回登录页；
      // 游客态（本地无 token）保持当前页面，不能因为一次读操作失败就弹登录。
      final prefs = await SharedPreferences.getInstance();
      final hadToken = (prefs.getString(_kTokenKey) ?? '').isNotEmpty;
      if (hadToken) {
        await prefs.remove(_kTokenKey);
        client.clearToken();
        state = const AuthState(isAuthed: false);
      }
      return false;
    }
    return login('', password);
  }

  Future<void> logout() async {
    client.clearToken();
    _sessionPassword = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
    // 兼容旧版本残留：升级后清掉历史明文口令
    await prefs.remove('user_password');
    state = const AuthState(isAuthed: false);
  }
}

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>(
  (ref) => AuthStateNotifier(client: ref.watch(apiClientProvider)),
);
