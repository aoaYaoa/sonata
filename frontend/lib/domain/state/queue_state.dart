import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../../services/persistent_state_service.dart';
import '../../services/providers.dart';

enum PlayMode { list, single, random }

class QueueState {
  final List<Song> songs;
  final int currentIndex;
  final PlayMode playMode;

  const QueueState({
    required this.songs,
    required this.currentIndex,
    required this.playMode,
  });

  QueueState copyWith({
    List<Song>? songs,
    int? currentIndex,
    PlayMode? playMode,
  }) {
    return QueueState(
      songs: songs ?? this.songs,
      currentIndex: currentIndex ?? this.currentIndex,
      playMode: playMode ?? this.playMode,
    );
  }

  static QueueState initial() {
    return const QueueState(
      songs: [],
      currentIndex: 0,
      playMode: PlayMode.list,
    );
  }
}

class QueueStateNotifier extends StateNotifier<QueueState> {
  final PersistentStateService persistence;
  late final Future<void> loaded;

  QueueStateNotifier({required this.persistence})
    : super(QueueState.initial()) {
    loaded = persistence.loadQueue(this);
  }

  void addSong(Song song) {
    // 已存在则跳过，避免重复
    if (state.songs.any((s) => s.id == song.id)) return;
    final updated = [...state.songs, song];
    state = state.copyWith(songs: updated);
    persistence.saveQueue(state);
  }

  /// 插到当前播放的下一首。
  ///
  /// 队列原来只有 `addSong`（扔到队尾），想「这首歌听完就听那首」只能
  /// 手动把整条队列清掉重排。插在当前曲后面、并把 currentIndex 之前的判定
  /// 保持不变，播完当前这首自然就轮到它。
  void insertNext(Song song) {
    final existing = state.songs.indexWhere((s) => s.id == song.id);
    if (existing == state.currentIndex) return; // 就是当前这首，别动
    final updated = [...state.songs];
    if (existing >= 0) updated.removeAt(existing);

    // 当前曲的索引可能因为上面的删除而前移一位。
    final current = state.songs[state.currentIndex];
    var currentIndex = updated.indexWhere(
      (s) => s.id == current.id && s.source == current.source,
    );
    if (currentIndex < 0) currentIndex = 0;

    final insertAt = (currentIndex + 1).clamp(0, updated.length);
    updated.insert(insertAt, song);

    state = state.copyWith(songs: updated, currentIndex: currentIndex);
    persistence.saveQueue(state);
  }

  void selectSong(Song song) {
    final index = state.songs.indexWhere((item) => item.id == song.id);
    if (index == -1) {
      addSong(song);
      setCurrentIndex(state.songs.length - 1);
      return;
    }
    setCurrentIndex(index);
  }

  /// 仅用于启动时从持久化恢复，不触发 saveQueue
  void loadState({required int currentIndex, required PlayMode playMode}) {
    final clampedIndex = currentIndex.clamp(
      0,
      state.songs.isEmpty ? 0 : state.songs.length - 1,
    );
    state = state.copyWith(currentIndex: clampedIndex, playMode: playMode);
  }

  /// 用新列表替换队列，并定位到 selected 歌曲
  void replaceQueue(List<Song> songs, Song selected) {
    if (songs.isEmpty) return;
    final index = songs.indexWhere((s) => s.id == selected.id);
    state = state.copyWith(
      songs: List.unmodifiable(songs),
      currentIndex: index < 0 ? 0 : index,
    );
    persistence.saveQueue(state);
  }

  void addSongs(List<Song> songs) {
    if (songs.isEmpty) return;
    final existingIds = state.songs.map((s) => s.id).toSet();
    final newSongs = songs.where((s) => !existingIds.contains(s.id)).toList();
    if (newSongs.isEmpty) return;
    final updated = [...state.songs, ...newSongs];
    state = state.copyWith(songs: updated);
    persistence.saveQueue(state);
  }

  /// 拖动排序：把第 [oldIndex] 首移到 [newIndex]。
  ///
  /// 当前播的那首要跟着索引走，否则用户在队列里挪一下顺序，
  /// 「正在播放第 N 首」和实际的歌就对不上，下一首会跳错。
  void moveSong(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= state.songs.length) return;
    final updated = [...state.songs];
    final song = updated.removeAt(oldIndex);
    final target = newIndex.clamp(0, updated.length);
    updated.insert(target, song);

    final current = state.songs[state.currentIndex];
    var nextIndex = updated.indexWhere(
      (s) => s.id == current.id && s.source == current.source,
    );
    if (nextIndex < 0) {
      nextIndex = state.currentIndex.clamp(0, updated.length - 1);
    }

    state = state.copyWith(songs: updated, currentIndex: nextIndex);
    persistence.saveQueue(state);
  }

  void removeAt(int index) {
    if (index < 0 || index >= state.songs.length) return;
    final updated = [...state.songs]..removeAt(index);
    final nextIndex = state.currentIndex.clamp(
      0,
      updated.isEmpty ? 0 : updated.length - 1,
    );
    state = state.copyWith(songs: updated, currentIndex: nextIndex);
    persistence.saveQueue(state);
  }

  void clear() {
    state = state.copyWith(songs: [], currentIndex: 0);
    persistence.saveQueue(state);
  }

  void setCurrentIndex(int index) {
    if (index < 0 || index >= state.songs.length) return;
    state = state.copyWith(currentIndex: index);
    persistence.saveQueue(state);
  }

  void setPlayMode(PlayMode mode) {
    state = state.copyWith(playMode: mode);
    persistence.saveQueue(state);
  }

  void cyclePlayMode() {
    final modes = PlayMode.values;
    final next = modes[(modes.indexOf(state.playMode) + 1) % modes.length];
    state = state.copyWith(playMode: next);
    persistence.saveQueue(state);
  }
}

final queueStateProvider = StateNotifierProvider<
  QueueStateNotifier,
  QueueState
>((ref) => QueueStateNotifier(persistence: ref.watch(persistentStateProvider)));
