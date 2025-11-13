import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/audio_track.dart';
import '../services/audio_player_service.dart';

// Audio Player Service Provider
final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService.instance;
  return service;
});

// Current Track Provider
final currentTrackProvider = StreamProvider<AudioTrack?>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.currentTrackStream;
});

// Player State Provider
final playerStateProvider = StreamProvider<PlayerState>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.playerStateStream;
});

// Position Provider
final positionProvider = StreamProvider<Duration>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.positionStream;
});

// Duration Provider
final durationProvider = StreamProvider<Duration?>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.durationStream;
});

// Queue Provider
final queueProvider = StreamProvider<List<AudioTrack>>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.queueStream;
});

// Playing State Provider (convenience)
final isPlayingProvider = Provider<bool>((ref) {
  final playerState = ref.watch(playerStateProvider);
  return playerState.when(
    data: (state) => state.playing,
    loading: () => false,
    error: (_, __) => false,
  );
});

// Progress Provider (convenience)
final progressProvider = Provider<double>((ref) {
  final position = ref.watch(positionProvider);
  final duration = ref.watch(durationProvider);

  return position.when(
    data: (pos) => duration.when(
      data: (dur) => dur != null && dur.inMilliseconds > 0
          ? pos.inMilliseconds / dur.inMilliseconds
          : 0.0,
      loading: () => 0.0,
      error: (_, __) => 0.0,
    ),
    loading: () => 0.0,
    error: (_, __) => 0.0,
  );
});

// Audio Player Controller
class AudioPlayerController extends StateNotifier<AudioPlayerState> {
  final AudioPlayerService _service;

  AudioPlayerController(this._service) : super(const AudioPlayerState());

  Future<void> initialize() async {
    print('[AudioPlayerController] initialize() called');
    // Request notification permission for Android 13+
    await Permission.notification.request();

    print('[AudioPlayerController] Calling service.initialize()');
    await _service.initialize();
    print('[AudioPlayerController] service.initialize() completed');

    // Listen to player state changes
    _service.playerStateStream.listen((playerState) {
      // Force a state update to trigger UI rebuild
      state = state.copyWith();
    });
    print('[AudioPlayerController] initialize() completed');
  }

  Future<void> playTrack(AudioTrack track) async {
    await _service.updateQueue([track]);
    await _service.play();
  }

  Future<void> playTracks(List<AudioTrack> tracks, {int startIndex = 0}) async {
    await _service.updateQueue(tracks, startIndex: startIndex);
    await _service.play();
  }

  Future<void> play() async {
    await _service.play();
  }

  Future<void> pause() async {
    await _service.pause();
  }

  Future<void> stop() async {
    await _service.stop();
  }

  Future<void> seek(Duration position) async {
    await _service.seek(position);
  }

  Future<void> seekForward(Duration duration) async {
    await _service.seekForward(duration);
  }

  Future<void> seekBackward(Duration duration) async {
    await _service.seekBackward(duration);
  }

  Future<void> skipToNext() async {
    await _service.skipToNext();
  }

  Future<void> skipToPrevious() async {
    await _service.skipToPrevious();
  }

  Future<void> skipToIndex(int index) async {
    await _service.skipToIndex(index);
  }

  Future<void> setRepeatMode(LoopMode mode) async {
    await _service.setRepeatMode(mode);
    state = state.copyWith(repeatMode: mode);
  }

  Future<void> setShuffleMode(bool enabled) async {
    await _service.setShuffleMode(enabled);
    state = state.copyWith(shuffleMode: enabled);
  }

  Future<void> setVolume(double volume) async {
    await _service.setVolume(volume);
    state = state.copyWith(volume: volume);
  }

  Future<void> setSpeed(double speed) async {
    await _service.setSpeed(speed);
    state = state.copyWith(speed: speed);
  }

  // Getters to expose service state
  bool get isPlaying => _service.playing;
  PlayerState get playerState => _service.playerState;
  AudioTrack? get currentTrack => _service.currentTrack;
  List<AudioTrack> get queue => _service.queue;
  Stream<PlayerState> get playerStateStream => _service.playerStateStream;
  Stream<AudioTrack?> get currentTrackStream => _service.currentTrackStream;
}

// Audio Player State
class AudioPlayerState {
  final LoopMode repeatMode;
  final bool shuffleMode;
  final double volume;
  final double speed;

  const AudioPlayerState({
    this.repeatMode = LoopMode.off,
    this.shuffleMode = false,
    this.volume = 1.0,
    this.speed = 1.0,
  });

  AudioPlayerState copyWith({
    LoopMode? repeatMode,
    bool? shuffleMode,
    double? volume,
    double? speed,
  }) {
    return AudioPlayerState(
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
    );
  }
}

// Audio Player Controller Provider
final audioPlayerControllerProvider =
    StateNotifierProvider<AudioPlayerController, AudioPlayerState>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return AudioPlayerController(service);
});

// MiniPlayer Visibility Controller
class MiniPlayerVisibilityController extends StateNotifier<bool> {
  MiniPlayerVisibilityController() : super(true);

  void show() => state = true;
  void hide() => state = false;
}

// MiniPlayer Visibility Provider
final miniPlayerVisibilityProvider =
    StateNotifierProvider<MiniPlayerVisibilityController, bool>((ref) {
  return MiniPlayerVisibilityController();
});
