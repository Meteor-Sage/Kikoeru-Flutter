import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'work.dart';
import 'audio_track.dart';

class HistoryRecord extends Equatable {
  final Work work;
  final DateTime lastPlayedTime;
  final AudioTrack? lastTrack;
  final int lastPositionMs;
  final int playlistIndex;
  final int playlistTotal;

  const HistoryRecord({
    required this.work,
    required this.lastPlayedTime,
    this.lastTrack,
    this.lastPositionMs = 0,
    this.playlistIndex = 0,
    this.playlistTotal = 0,
  });

  HistoryRecord copyWith({
    Work? work,
    DateTime? lastPlayedTime,
    AudioTrack? lastTrack,
    int? lastPositionMs,
    int? playlistIndex,
    int? playlistTotal,
  }) {
    return HistoryRecord(
      work: work ?? this.work,
      lastPlayedTime: lastPlayedTime ?? this.lastPlayedTime,
      lastTrack: lastTrack ?? this.lastTrack,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      playlistIndex: playlistIndex ?? this.playlistIndex,
      playlistTotal: playlistTotal ?? this.playlistTotal,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'work_id': work.id,
      'work_json': jsonEncode(work.toJson()),
      'last_played_time': lastPlayedTime.millisecondsSinceEpoch,
      'last_track_json':
          lastTrack != null ? jsonEncode(lastTrack!.toJson()) : null,
      'last_position_ms': lastPositionMs,
      'playlist_index': playlistIndex,
      'playlist_total': playlistTotal,
    };
  }

  factory HistoryRecord.fromMap(Map<String, dynamic> map) {
    return HistoryRecord(
      work: Work.fromJson(jsonDecode(map['work_json'])),
      lastPlayedTime:
          DateTime.fromMillisecondsSinceEpoch(map['last_played_time']),
      lastTrack: map['last_track_json'] != null
          ? AudioTrack.fromJson(jsonDecode(map['last_track_json']))
          : null,
      lastPositionMs: map['last_position_ms'] ?? 0,
      playlistIndex: map['playlist_index'] ?? 0,
      playlistTotal: map['playlist_total'] ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        work,
        lastPlayedTime,
        lastTrack,
        lastPositionMs,
        playlistIndex,
        playlistTotal,
      ];
}
