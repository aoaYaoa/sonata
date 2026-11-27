import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../../data/solara_repository.dart';
import '../../data/providers.dart';
import '../../services/providers.dart';

class SearchState {
  final String keyword;
  final String source;
  final int page;
  final bool loading;
  final bool hasMore;
  final String? error;
  final List<Song> results;
  final List<String> history; // 搜索历史词，最新在前

  /// 这次会话里是否真的搜过。
  ///
  /// 用来区分「还没搜」和「搜了但一条没有」：只看 `results.isEmpty` 的话，
  /// 搜不到结果时浮层会整个消失，用户看到的是首页，会以为点击没生效。
  final bool searched;

  const SearchState({
    required this.keyword,
    required this.source,
    required this.page,
    required this.loading,
    required this.hasMore,
    required this.error,
    required this.results,
    this.history = const [],
    this.searched = false,
  });

  SearchState copyWith({
    String? keyword,
    String? source,
    int? page,
    bool? loading,
    bool? hasMore,
    String? error,
    List<Song>? results,
    List<String>? history,
    bool? searched,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      source: source ?? this.source,
      page: page ?? this.page,
      loading: loading ?? this.loading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      results: results ?? this.results,
      history: history ?? this.history,
      searched: searched ?? this.searched,
    );
  }

  static SearchState initial() {
    return const SearchState(
      keyword: '',
      source: 'netease',
      page: 1,
      loading: false,
      hasMore: true,
      error: null,
      results: [],
      history: [],
    );
  }
}

class SearchStateNotifier extends StateNotifier<SearchState> {
  final SolaraRepository repository;
  SearchStateNotifier({required this.repository})
    : super(SearchState.initial());

  void Function(List<String>)? _onHistoryChanged;

  void setOnHistoryChanged(void Function(List<String>) cb) {
    _onHistoryChanged = cb;
  }

  void loadHistory(List<String> history) {
    state = state.copyWith(history: history);
  }

  void _addHistory(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    final updated = [trimmed, ...state.history.where((h) => h != trimmed)];
    state = state.copyWith(history: updated.take(20).toList());
    _onHistoryChanged?.call(state.history);
  }

  void removeHistory(String keyword) {
    state = state.copyWith(
      history: state.history.where((h) => h != keyword).toList(),
    );
    _onHistoryChanged?.call(state.history);
  }

  void clearHistory() {
    state = state.copyWith(history: []);
    _onHistoryChanged?.call(state.history);
  }

  Future<void> search(String keyword) async {
    if (keyword.trim().isEmpty) return;
    _addHistory(keyword.trim());
    state = state.copyWith(
      loading: true,
      error: null,
      keyword: keyword,
      page: 1,
      searched: true,
    );
    try {
      const pageSize = 20;
      final results = await repository.search(
        keyword: keyword,
        source: state.source,
        count: pageSize,
        page: 1,
      );
      state = state.copyWith(
        loading: false,
        results: results,
        // 只有「拿满了」才认为还有下一页：原来写 results.isNotEmpty，
        // 最后一页（返回 3 条）之后还会再多打一次空请求。
        hasMore: results.length >= pageSize,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore || state.keyword.isEmpty) return;
    final nextPage = state.page + 1;
    state = state.copyWith(loading: true, error: null);
    try {
      const pageSize = 20;
      final results = await repository.search(
        keyword: state.keyword,
        source: state.source,
        count: pageSize,
        page: nextPage,
      );
      state = state.copyWith(
        loading: false,
        page: nextPage,
        results: [...state.results, ...results],
        hasMore: results.length >= pageSize,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setSource(String source) {
    state = state.copyWith(source: source);
  }

  void clearResults() {
    state = SearchState.initial().copyWith(
      source: state.source,
      history: state.history,
    );
  }
}

final searchStateProvider =
    StateNotifierProvider<SearchStateNotifier, SearchState>((ref) {
      final notifier = SearchStateNotifier(
        repository: ref.watch(solaraRepositoryProvider),
      );
      // 持久化搜索历史
      final persistence = ref.read(persistentStateProvider);
      persistence.loadSearchHistory(notifier);
      notifier.setOnHistoryChanged(
        (history) => persistence.saveSearchHistory(history),
      );
      return notifier;
    });
