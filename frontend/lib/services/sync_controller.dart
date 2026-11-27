import 'dart:async';
import 'package:flutter/foundation.dart';
import 'remote_state_models.dart';
import 'remote_storage_service.dart';
import 'storage_service.dart';

/// 云端同步的状态。
///
/// 之前同步是完全静默的：`app.dart` 启动时调一次 `initialize()`，
/// 之后每次写本地就 scheduleSync 一次，成功失败都没有任何界面反馈。
/// 用户无法判断「我在另一台机器上的收藏到底同步过来没有」。
class SyncController extends ChangeNotifier {
  final StorageService storage;
  final RemoteStorageService remote;
  final Duration debounce;
  Timer? _debounceTimer;
  bool _syncInFlight = false;
  bool _initialized = false;

  DateTime? _lastSyncedAt;
  String? _lastError;

  /// 上一次成功同步（上传或拉取合并）的时间；从未成功过则为 null。
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// 上一次失败的原因；成功后清空。
  String? get lastError => _lastError;

  bool get syncing => _syncInFlight;

  bool get initialized => _initialized;

  void _markSuccess() {
    _lastSyncedAt = DateTime.now();
    _lastError = null;
    notifyListeners();
  }

  void _markFailure(Object e) {
    _lastError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    notifyListeners();
  }

  SyncController({
    required this.storage,
    required this.remote,
    this.debounce = const Duration(milliseconds: 800),
  });

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _syncInFlight = true;
    notifyListeners();
    try {
      final local = await _loadLocalSnapshot();
      final remoteSnapshot = await remote.fetchState();
      if (remoteSnapshot == null) {
        if (local != null) {
          await _persistSnapshot(local);
          await remote.saveState(local);
        }
        _markSuccess();
        return;
      }

      final merged =
          local == null ? remoteSnapshot : local.mergeWith(remoteSnapshot);
      await _persistSnapshot(merged);

      if (local != null && merged.updatedAt.isAfter(remoteSnapshot.updatedAt)) {
        await remote.saveState(merged);
      }
      _markSuccess();
    } catch (e) {
      _markFailure(e);
    } finally {
      _syncInFlight = false;
      notifyListeners();
    }
  }

  void scheduleSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _performSync);
  }

  Future<void> _performSync() async {
    if (_syncInFlight) return;
    _syncInFlight = true;
    notifyListeners();
    try {
      final local = await _loadLocalSnapshot();
      if (local != null) {
        await remote.saveState(local);
      }
      _markSuccess();
    } catch (e) {
      _markFailure(e);
    } finally {
      _syncInFlight = false;
      notifyListeners();
    }
  }

  /// 手动触发一次上传，给设置页的「立即同步」用。
  Future<void> syncNow() => _performSync();

  Future<RemoteStateSnapshot?> _loadLocalSnapshot() async {
    final now = DateTime.now().toUtc();

    final queueRaw = await storage.getJson<List<dynamic>>('playlistSongs');
    final queueUpdatedAtRaw = await storage.getJson<String>('queueUpdatedAt');
    final queue = _buildQueue(queueRaw, queueUpdatedAtRaw, now);

    final favoritesRaw = await storage.getJson<List<dynamic>>('favoriteSongs');
    final favoritesUpdatedAtRaw = await storage.getJson<String>(
      'favoritesUpdatedAt',
    );
    final favorites = _buildFavorites(favoritesRaw, favoritesUpdatedAtRaw, now);

    final settingsRaw = await storage.getJson<Map<String, dynamic>>('settings');
    final settingsUpdatedAtRaw = await storage.getJson<String>(
      'settingsUpdatedAt',
    );
    final settings = _buildSettings(settingsRaw, settingsUpdatedAtRaw, now);

    final localSongsRaw = await storage.getJson<List<dynamic>>('localSongs');
    final localSongsUpdatedAtRaw = await storage.getJson<String>(
      'localSongsUpdatedAt',
    );
    final localSongs = _buildLocalSongs(
      localSongsRaw,
      localSongsUpdatedAtRaw,
      now,
    );

    if (queue == null &&
        favorites == null &&
        settings == null &&
        localSongs == null) {
      return null;
    }

    final latest = _latestTimestamp([
      queue?.updatedAt,
      favorites?.updatedAt,
      settings?.updatedAt,
      localSongs?.updatedAt,
    ]);

    return RemoteStateSnapshot(
      version: 1,
      updatedAt: latest,
      queue: queue,
      favorites: favorites,
      settings: settings,
      localSongs: localSongs,
    );
  }

  RemoteQueueState? _buildQueue(
    List<dynamic>? raw,
    String? updatedAtRaw,
    DateTime now,
  ) {
    if (raw == null) return null;
    final updatedAt = _resolveUpdatedAt(updatedAtRaw, now: now, hasData: true);
    final songs =
        raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    return RemoteQueueState(updatedAt: updatedAt, songs: songs);
  }

  RemoteFavoritesState? _buildFavorites(
    List<dynamic>? raw,
    String? updatedAtRaw,
    DateTime now,
  ) {
    if (raw == null) return null;
    final updatedAt = _resolveUpdatedAt(updatedAtRaw, now: now, hasData: true);
    final songs =
        raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    return RemoteFavoritesState(updatedAt: updatedAt, songs: songs);
  }

  RemoteSettingsState? _buildSettings(
    Map<String, dynamic>? raw,
    String? updatedAtRaw,
    DateTime now,
  ) {
    if (raw == null) return null;
    final updatedAt = _resolveUpdatedAt(updatedAtRaw, now: now, hasData: true);
    return RemoteSettingsState(updatedAt: updatedAt, data: raw);
  }

  RemoteLocalSongsState? _buildLocalSongs(
    List<dynamic>? raw,
    String? updatedAtRaw,
    DateTime now,
  ) {
    if (raw == null) return null;
    final updatedAt = _resolveUpdatedAt(updatedAtRaw, now: now, hasData: true);
    final songs =
        raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    return RemoteLocalSongsState(updatedAt: updatedAt, songs: songs);
  }

  DateTime _resolveUpdatedAt(
    String? raw, {
    required DateTime now,
    required bool hasData,
  }) {
    if (raw != null && raw.isNotEmpty) {
      return DateTime.parse(raw);
    }
    if (!hasData) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return now;
  }

  DateTime _latestTimestamp(List<DateTime?> candidates) {
    DateTime latest = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final candidate in candidates) {
      if (candidate != null && candidate.isAfter(latest)) {
        latest = candidate;
      }
    }
    return latest;
  }

  Future<void> _persistSnapshot(RemoteStateSnapshot snapshot) async {
    final queue = snapshot.queue;
    if (queue != null) {
      await storage.setJson('playlistSongs', queue.songs);
      await storage.setJson(
        'queueUpdatedAt',
        queue.updatedAt.toIso8601String(),
      );
    }

    final favorites = snapshot.favorites;
    if (favorites != null) {
      await storage.setJson('favoriteSongs', favorites.songs);
      await storage.setJson(
        'favoritesUpdatedAt',
        favorites.updatedAt.toIso8601String(),
      );
    }

    final settings = snapshot.settings;
    if (settings != null) {
      await storage.setJson('settings', settings.data);
      await storage.setJson(
        'settingsUpdatedAt',
        settings.updatedAt.toIso8601String(),
      );
    }

    final localSongs = snapshot.localSongs;
    if (localSongs != null) {
      await storage.setJson('localSongs', localSongs.songs);
      await storage.setJson(
        'localSongsUpdatedAt',
        localSongs.updatedAt.toIso8601String(),
      );
    }
  }
}
