import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/work.dart';
import '../models/history_record.dart';
import '../models/audio_track.dart';
import '../services/history_database.dart';
import '../services/audio_player_service.dart';

final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<HistoryRecord>>((ref) {
  return HistoryNotifier();
});

class HistoryNotifier extends StateNotifier<List<HistoryRecord>> {
  HistoryNotifier() : super([]) {
    load();
    _initPlaybackListener();
  }

  StreamSubscription? _positionSubscription;
  StreamSubscription? _trackSubscription;
  DateTime _lastUpdateTime = DateTime.now();

  Future<void> load() async {
    final history = await HistoryDatabase.instance.getAllHistory();
    state = history;
  }

  Future<void> addOrUpdate(Work work,
      {AudioTrack? track, int? positionMs}) async {
    final now = DateTime.now();
    final audioService = AudioPlayerService.instance;

    // Get playlist info if available and matching current work
    int playlistIndex = 0;
    int playlistTotal = 0;

    if (audioService.currentTrack?.workId == work.id) {
      playlistIndex = audioService.currentIndex;
      playlistTotal = audioService.queue.length;
    }

    // Find existing record
    final existingIndex = state.indexWhere((r) => r.work.id == work.id);
    HistoryRecord record;

    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      record = existing.copyWith(
        work: work,
        lastPlayedTime: now,
        lastTrack: track ?? existing.lastTrack,
        lastPositionMs: positionMs ?? existing.lastPositionMs,
        playlistIndex:
            playlistIndex > 0 ? playlistIndex : existing.playlistIndex,
        playlistTotal:
            playlistTotal > 0 ? playlistTotal : existing.playlistTotal,
      );
    } else {
      record = HistoryRecord(
        work: work,
        lastPlayedTime: now,
        lastTrack: track,
        lastPositionMs: positionMs ?? 0,
        playlistIndex: playlistIndex,
        playlistTotal: playlistTotal,
      );
    }

    await HistoryDatabase.instance.addOrUpdate(record);

    // Reload to ensure sort order
    await load();
  }

  Future<void> remove(int workId) async {
    await HistoryDatabase.instance.delete(workId);
    await load();
  }

  Future<void> clear() async {
    await HistoryDatabase.instance.clear();
    state = [];
  }

  void _initPlaybackListener() {
    // Listen to track changes
    _trackSubscription =
        AudioPlayerService.instance.currentTrackStream.listen((track) {
      if (track != null && track.workId != null) {
        _updateHistoryFromPlayback(track);
      }
    });

    // Listen to position changes
    _positionSubscription =
        AudioPlayerService.instance.positionStream.listen((position) {
      final now = DateTime.now();
      // Throttle updates to every 5 seconds
      if (now.difference(_lastUpdateTime).inSeconds >= 5) {
        _lastUpdateTime = now;
        final track = AudioPlayerService.instance.currentTrack;
        if (track != null && track.workId != null) {
          _updateHistoryFromPlayback(track, position: position);
        }
      }
    });
  }

  Future<void> _updateHistoryFromPlayback(AudioTrack track,
      {Duration? position}) async {
    if (track.workId == null) return;

    // We need the Work object.
    // We check if the work is already in history.
    final existingIndex = state.indexWhere((r) => r.work.id == track.workId);

    if (existingIndex >= 0) {
      // Update existing record
      final existing = state[existingIndex];
      await addOrUpdate(existing.work,
          track: track, positionMs: position?.inMilliseconds);
    } else {
      // If not in history, we can't add it because we don't have the Work object.
      // The UI is responsible for adding the Work to history when playback starts.
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _trackSubscription?.cancel();
    super.dispose();
  }
}
