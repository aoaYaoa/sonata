import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solara_flutter/app/app.dart';
import 'package:solara_flutter/data/api/api_client.dart';
import 'package:solara_flutter/data/providers.dart';
import 'package:solara_flutter/data/solara_repository.dart';
import 'package:solara_flutter/data/api/solara_api.dart';
import 'package:solara_flutter/domain/models/discover.dart';
import 'package:solara_flutter/domain/models/song.dart';
import 'package:solara_flutter/services/auth_service.dart';
import 'package:solara_flutter/services/cookie_service.dart';
import 'package:solara_flutter/services/providers.dart';
import 'package:solara_flutter/services/remote_state_models.dart';
import 'package:solara_flutter/services/remote_storage_service.dart';
import 'package:solara_flutter/services/storage_service.dart';
import 'package:solara_flutter/services/sync_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不发网络请求的仓库替身。
///
/// 登录后的首页会挂载发现页 / 搜索面板，它们在 didChangeDependencies 里
/// 就会发起真实请求；widget test 使用 fake_async 时钟，任何在途的 Dio
/// 请求都会留下 pending timer 让测试失败。这里把仓库整体替换掉。
class EmptyRepo extends SolaraRepository {
  EmptyRepo()
      : super(
          api: SolaraApi(
            client: ApiClient(baseUrl: 'https://example.com', dio: Dio()),
          ),
          dio: Dio(),
        );

  @override
  Future<List<SongListItem>> fetchSongList({
    required String source,
    String sort = 'hot',
    String? tag,
    int page = 1,
    int limit = 30,
  }) async => const [];

  @override
  Future<List<LeaderboardItem>> fetchLeaderboardList({
    required String source,
    int limit = 30,
  }) async => const [];

  @override
  Future<List<Song>> search({
    required String keyword,
    required String source,
    int count = 20,
    int page = 1,
  }) async => const [];
}

/// 不发网络请求的 Cookie 状态服务替身（设置页 initState 会直接调用）。
class EmptyCookieService extends CookieService {
  EmptyCookieService() : super(Dio());

  @override
  Future<Map<String, CookieStatus>> fetchStatus() async => {
    'youtube': const CookieStatus(exists: false),
    'bilibili': const CookieStatus(exists: false),
  };
}

class TestAuthNotifier extends AuthStateNotifier {
  TestAuthNotifier()
      : super(client: ApiClient(baseUrl: 'https://example.com', dio: Dio()));

  void setAuthed(bool value) {
    state = AuthState(isAuthed: value);
  }
}

class NoopStorageService extends StorageService {
  @override
  Future<void> setJson(String key, Object value) async {}

  @override
  Future<T?> getJson<T>(String key) async => null;

  @override
  Future<void> remove(String key) async {}
}

class NoopRemoteStorageService extends RemoteStorageService {
  NoopRemoteStorageService()
      : super(client: ApiClient(baseUrl: 'https://example.com', dio: Dio()));

  @override
  Future<RemoteStateSnapshot?> fetchState() async => null;

  @override
  Future<bool> saveState(RemoteStateSnapshot snapshot) async => true;
}

class FakeSyncController extends SyncController {
  bool initializeCalled = false;

  FakeSyncController()
      : super(storage: NoopStorageService(), remote: NoopRemoteStorageService());

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Unauthed user sees login', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SolaraApp()));
    // initState 里通过 microtask 恢复会话，先让出一次事件循环，
    // 否则还停留在 _sessionRestored=false 的加载圈。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // 登录页按钮文案是中文「登录」
    expect(find.text('登录'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Authed user triggers sync initialization', (tester) async {
    final authNotifier = TestAuthNotifier();
    final syncController = FakeSyncController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => authNotifier),
          syncControllerProvider.overrideWithValue(syncController),
          // 阻断真实网络，避免 pending timer
          solaraRepositoryProvider.overrideWith((ref) => EmptyRepo()),
          cookieServiceProvider.overrideWith((ref) => EmptyCookieService()),
        ],
        child: const SolaraApp(),
      ),
    );

    expect(syncController.initializeCalled, isFalse);

    authNotifier.setAuthed(true);
    await tester.pump();
    await tester.pump();

    expect(syncController.initializeCalled, isTrue);

    // 首页会挂载发现页并触发真实网络请求，PlayerController 还持有
    // 500ms 周期 Timer。先用 runAsync 让 Dio 的在途请求真正走完，
    // 再卸载整棵树释放 ProviderScope，否则测试结束时报
    // "A Timer is still pending"。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
