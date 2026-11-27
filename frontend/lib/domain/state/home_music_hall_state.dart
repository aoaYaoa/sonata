import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/discover.dart';
import '../../data/providers.dart';

/// 首页音乐馆（各平台实时榜单）的状态。
///
/// 有个容易出错的地方：换音源时旧列表必须立刻清掉。原来用
/// `copyWith(loading: true)`——旧榜单留在 state 里，而 `loadedSource` 已经
/// 指向新音源，于是「新音源的徽标 + 旧音源的卡片」会先渲染一帧，等请求回来
/// 再整屏换掉。用户看到的就是「先闪一下旧的文字，再刷成最新的」。
class HomeMusicHallState {
  final List<LeaderboardItem> leaderboards;
  final bool loading;
  final String? error;
  final String? loadedSource;

  const HomeMusicHallState({
    this.leaderboards = const [],
    this.loading = false,
    this.error,
    this.loadedSource,
  });

  HomeMusicHallState copyWith({
    List<LeaderboardItem>? leaderboards,
    bool? loading,
    String? error,
    bool clearError = false,
    String? loadedSource,
  }) {
    return HomeMusicHallState(
      leaderboards: leaderboards ?? this.leaderboards,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      loadedSource: loadedSource ?? this.loadedSource,
    );
  }
}

class HomeMusicHallNotifier extends StateNotifier<HomeMusicHallState> {
  final Ref _ref;
  final Map<String, List<LeaderboardItem>> _leaderboardCache = {};

  /// 请求序号：晚回来的旧请求直接丢弃。
  ///
  /// 用户连点两个音源时，前一个的响应可能后到，把界面刷回已经切走的音源。
  int _requestId = 0;

  HomeMusicHallNotifier(this._ref) : super(const HomeMusicHallState());

  /// 当前数据不是这个音源时才加载。
  ///
  /// 原来还短路了 `state.loading`：换音源时若上一次请求还没回来，新音源
  /// 就直接不加载了，界面会一直停在上一个音源的数据上。
  Future<void> ensureLoaded({required String source}) async {
    if (state.loadedSource == source && !state.loading) return;
    await load(source: source);
  }

  Future<void> load({required String source, bool forceRefresh = false}) async {
    final sameTarget = state.loadedSource == source;
    final cached = _leaderboardCache[source];

    if (!forceRefresh && !sameTarget && cached != null) {
      state = HomeMusicHallState(leaderboards: cached, loadedSource: source);
      return;
    }

    final requestId = ++_requestId;
    // 换音源时清空旧列表：这一屏直接进 loading 态，没有可对照的旧内容，
    // 就不会出现「旧卡片顶一下再换成新的」。
    state = HomeMusicHallState(
      leaderboards: sameTarget ? state.leaderboards : const [],
      loading: true,
      loadedSource: source,
    );

    try {
      final repo = _ref.read(solaraRepositoryProvider);
      final leaderboards = await repo.fetchLeaderboardList(source: source);
      // 已经被下一次请求顶掉，这份结果不该再写进界面。
      if (requestId != _requestId) return;
      _leaderboardCache[source] = leaderboards;
      state = HomeMusicHallState(
        leaderboards: leaderboards,
        loadedSource: source,
      );
    } catch (e) {
      if (requestId != _requestId) return;
      state = HomeMusicHallState(
        // 失败时保留同音源的已有数据：下拉刷新失败不该把列表清空。
        leaderboards: sameTarget ? state.leaderboards : const [],
        loadedSource: source,
        error: '加载失败: $e',
      );
    }
  }
}

final homeMusicHallStateProvider =
    StateNotifierProvider<HomeMusicHallNotifier, HomeMusicHallState>(
      (ref) => HomeMusicHallNotifier(ref),
    );
