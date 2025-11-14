import 'dart:async';
import 'dart:io' show Platform;
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../models/audio_track.dart';
import 'cache_service.dart';
import 'caching_stream_audio_source.dart';

class AudioPlayerService {
  static AudioPlayerService? _instance;
  static AudioPlayerService get instance =>
      _instance ??= AudioPlayerService._();

  AudioPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  final List<AudioTrack> _queue = [];
  int _currentIndex = 0;
  AudioHandler? _audioHandler;
  LoopMode _appLoopMode = LoopMode.off; // Track loop mode at app level

  // macOS specific: Track completion state to prevent duplicate triggers
  bool _completionHandled = false;
  Timer?
      _completionCheckTimer; // macOS workaround for StreamAudioSource completion bug

  // Windows SMTC support
  SMTCWindows? _smtc;

  // Stream controllers
  final StreamController<List<AudioTrack>> _queueController =
      StreamController.broadcast();
  final StreamController<AudioTrack?> _currentTrackController =
      StreamController.broadcast();

  // Initialize the service
  Future<void> initialize() async {
    // Initialize audio service handler for system integration
    _audioHandler = await AudioService.init(
      builder: () => _AudioPlayerHandler(this),
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.example.kikoeru_flutter.channel.audio',
        androidNotificationChannelName: 'Kikoeru Audio',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidShowNotificationBadge: true,
      ),
    );

    // Initialize Windows SMTC (System Media Transport Controls)
    if (Platform.isWindows) {
      _smtc = SMTCWindows(
        config: const SMTCConfig(
          fastForwardEnabled: false,
          nextEnabled: true,
          pauseEnabled: true,
          playEnabled: true,
          rewindEnabled: false,
          prevEnabled: true,
          stopEnabled: true,
        ),
      );

      // Register SMTC button callbacks
      _smtc!.buttonPressStream.listen((button) {
        switch (button) {
          case PressedButton.play:
            play();
            break;
          case PressedButton.pause:
            pause();
            break;
          case PressedButton.next:
            skipToNext();
            break;
          case PressedButton.previous:
            skipToPrevious();
            break;
          case PressedButton.stop:
            stop();
            break;
          default:
            break;
        }
      });

      // Enable SMTC
      _smtc!.enableSmtc();
    }

    // Listen to player state changes
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (Platform.isMacOS) {
          // macOS: Use dedicated handler to prevent duplicate triggers
          if (!_completionHandled) {
            _completionHandled = true;
            _handleTrackCompletion();
          }
        } else {
          // Other platforms: Use simple direct handling
          _handleTrackCompletion();
        }
      }

      // Update audio service playback state
      _updatePlaybackState();
    });

    // macOS specific: Additional position-based completion detection
    if (Platform.isMacOS) {
      Duration lastPosition = Duration.zero;
      _player.positionStream.listen((position) {
        final duration = _player.duration;

        // Reset completion flag when track changes or seeks backward
        if (position < lastPosition - const Duration(seconds: 1)) {
          _completionHandled = false;
        }

        // Fallback: detect completion when position reaches duration
        if (duration != null &&
            position >= duration - const Duration(milliseconds: 100) &&
            _player.playing &&
            !_completionHandled) {
          // Check if position is stuck at the end
          if (lastPosition != Duration.zero &&
              (position - lastPosition).inMilliseconds.abs() < 50 &&
              position >= duration - const Duration(milliseconds: 100)) {
            _completionHandled = true;
            _handleTrackCompletion();
          }
        }

        lastPosition = position;
        _updatePlaybackState();
      });

      // Start periodic completion check timer as final fallback
      _startCompletionCheckTimer();
    } else {
      // Other platforms: Simple position stream for playback state updates
      _player.positionStream.listen((position) {
        _updatePlaybackState();
      });
    }
  }

  // Update audio service playback state for system controls
  void _updatePlaybackState() {
    if (_audioHandler == null) return;

    final playing = _player.playing;
    final processingState = _player.processingState;

    (_audioHandler as _AudioPlayerHandler).playbackState.add(PlaybackState(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: {
                ProcessingState.idle: AudioProcessingState.idle,
                ProcessingState.loading: AudioProcessingState.loading,
                ProcessingState.buffering: AudioProcessingState.buffering,
                ProcessingState.ready: AudioProcessingState.ready,
                ProcessingState.completed: AudioProcessingState.completed,
              }[processingState] ??
              AudioProcessingState.idle,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
        ));

    // Update Windows SMTC playback status
    if (Platform.isWindows && _smtc != null) {
      _smtc!.setPlaybackStatus(
        playing ? PlaybackStatus.Playing : PlaybackStatus.Paused,
      );
    }
  }

  // Queue management
  Future<void> updateQueue(List<AudioTrack> tracks,
      {int startIndex = 0}) async {
    _queue.clear();
    _queue.addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);

    _queueController.add(List.from(_queue));

    // Load the current track
    if (tracks.isNotEmpty && _currentIndex < tracks.length) {
      await _loadTrack(tracks[_currentIndex]);
    }
  }

  Future<void> _loadTrack(AudioTrack track) async {
    // Reset completion flag for new track (macOS specific)
    if (Platform.isMacOS) {
      _completionHandled = false;
    }

    try {
      String? audioFilePath;
      bool loaded = false;

      // 如果有 hash，尝试使用缓存
      if (track.hash != null && track.hash!.isNotEmpty) {
        audioFilePath = await CacheService.getCachedAudioFile(track.hash!);

        if (audioFilePath != null) {
          await _player.setFilePath(audioFilePath);
          print('[Audio] 使用缓存文件播放: ${track.title}');
          loaded = true;
        } else {
          try {
            await CacheService.resetAudioCachePartial(track.hash!);
            final source = CachingStreamAudioSource(
              uri: Uri.parse(track.url),
              hash: track.hash!,
            );
            await _player.setAudioSource(source);
            print('[Audio] 流式播放并写入缓存: ${track.title}');
            loaded = true;
          } catch (error) {
            print('[Audio] 构建缓存流失败，回退到直接流式: $error');
          }
        }
      }

      if (!loaded) {
        await _player.setUrl(track.url);
        print('[Audio] 流式播放: ${track.title}');
      }

      _currentTrackController.add(track);

      // Update media item for system controls
      _updateMediaItem(track);
    } catch (e) {
      print('Error loading audio source: $e');
    }
  }

  // Update media item for system notification
  void _updateMediaItem(AudioTrack track) {
    if (_audioHandler == null) return;

    (_audioHandler as _AudioPlayerHandler).mediaItem.add(MediaItem(
          id: track.id,
          album: track.album ?? '',
          title: track.title,
          artist: track.artist ?? '',
          duration: track.duration,
          artUri:
              track.artworkUrl != null ? Uri.parse(track.artworkUrl!) : null,
        ));

    // Update Windows SMTC media info
    if (Platform.isWindows && _smtc != null) {
      _smtc!.updateMetadata(
        MusicMetadata(
          title: track.title,
          artist: track.artist ?? '',
          album: track.album ?? '',
          thumbnail: track.artworkUrl,
        ),
      );
    }

    // Update playback state immediately after media item change
    _updatePlaybackState();
  }

  // Handle track completion logic
  void _handleTrackCompletion() {
    if (_appLoopMode == LoopMode.one) {
      // Single track repeat - replay current track
      // macOS: Reset completion flag before replaying to allow next completion detection
      if (Platform.isMacOS) {
        _completionHandled = false;
      }
      seek(Duration.zero);
      play();
    } else if (_currentIndex < _queue.length - 1) {
      // Has next track - play it
      skipToNext();
    } else if (_appLoopMode == LoopMode.all && _queue.isNotEmpty) {
      // List repeat - go back to first track
      skipToIndex(0);
    } else {
      // Reached the end of the queue with no repeat, pause
      pause();
    }
  }

  // macOS specific: Start periodic timer to check for track completion
  // This is needed because StreamAudioSource on macOS doesn't properly fire completion events
  void _startCompletionCheckTimer() {
    if (!Platform.isMacOS) return;

    _completionCheckTimer?.cancel();
    _completionCheckTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final position = _player.position;
      final duration = _player.duration;
      final processingState = _player.processingState;
      final playing = _player.playing;

      if (playing && !_completionHandled) {
        // Check if track is completed
        if (processingState == ProcessingState.completed) {
          _completionHandled = true;
          _handleTrackCompletion();
        } else if (duration != null &&
            duration > Duration.zero &&
            position >= duration - const Duration(milliseconds: 50)) {
          _completionHandled = true;
          _handleTrackCompletion();
        }
      }
    });
  }

  // Playback controls
  Future<void> play() async {
    // macOS specific: Ensure completion check timer is running
    if (Platform.isMacOS &&
        (_completionCheckTimer == null || !_completionCheckTimer!.isActive)) {
      _startCompletionCheckTimer();
    }

    await _player.play();
    _updatePlaybackState();

    // macOS specific: Check if track completed immediately (workaround for immediate completion bug)
    if (Platform.isMacOS &&
        _player.processingState == ProcessingState.completed) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_completionHandled) {
          _completionHandled = true;
          _handleTrackCompletion();
        }
      });
    }
  }

  Future<void> pause() async {
    await _player.pause();
    _updatePlaybackState();
  }

  Future<void> stop() async {
    await _player.stop();
    _updatePlaybackState();
  }

  Future<void> seek(Duration position) async {
    // macOS specific: Reset completion flag when seeking to allow new completion detection
    if (Platform.isMacOS) {
      _completionHandled = false;
    }
    await _player.seek(position);
    _updatePlaybackState();
  }

  Future<void> seekForward(Duration duration) async {
    final currentPosition = _player.position;
    final totalDuration = _player.duration;
    if (totalDuration != null) {
      final newPosition = currentPosition + duration;
      await _player
          .seek(newPosition > totalDuration ? totalDuration : newPosition);
      _updatePlaybackState();
    }
  }

  Future<void> seekBackward(Duration duration) async {
    final currentPosition = _player.position;
    final newPosition = currentPosition - duration;
    await _player
        .seek(newPosition < Duration.zero ? Duration.zero : newPosition);
    _updatePlaybackState();
  }

  Future<void> skipToNext() async {
    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      _currentIndex++;
      await _loadTrack(_queue[_currentIndex]);
      await play();
    } else {
      // No next track available
      throw Exception('没有下一首可播放');
    }
  }

  Future<void> skipToPrevious() async {
    if (_queue.isNotEmpty && _currentIndex > 0) {
      _currentIndex--;
      await _loadTrack(_queue[_currentIndex]);
      await play();
    } else {
      // No previous track available
      throw Exception('没有上一首可播放');
    }
  }

  Future<void> skipToIndex(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      await _loadTrack(_queue[_currentIndex]);
      await play();
    }
  }

  // Getters and Streams
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<List<AudioTrack>> get queueStream => _queueController.stream;
  Stream<AudioTrack?> get currentTrackStream => _currentTrackController.stream;

  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get playing => _player.playing;
  PlayerState get playerState => _player.playerState;

  AudioTrack? get currentTrack =>
      _queue.isNotEmpty && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;

  List<AudioTrack> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;

  bool get hasNext => _currentIndex < _queue.length - 1;
  bool get hasPrevious => _currentIndex > 0;

  // Audio settings
  Future<void> setRepeatMode(LoopMode mode) async {
    // Store the mode at app level
    _appLoopMode = mode;
    // Always keep the player's loop mode off to prevent single-track looping
    // We handle all repeat logic in the app layer via playerStateStream listener
    await _player.setLoopMode(LoopMode.off);
  }

  Future<void> setShuffleMode(bool enabled) async {
    await _player.setShuffleModeEnabled(enabled);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed.clamp(0.5, 2.0));
  }

  // Cleanup
  Future<void> dispose() async {
    _completionCheckTimer?.cancel();
    await _queueController.close();
    await _currentTrackController.close();
    await _player.dispose();
  }
}

// Custom AudioHandler for system integration
class _AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayerService _service;

  _AudioPlayerHandler(this._service);

  @override
  Future<void> play() => _service.play();

  @override
  Future<void> pause() => _service.pause();

  @override
  Future<void> stop() => _service.stop();

  @override
  Future<void> seek(Duration position) => _service.seek(position);

  @override
  Future<void> skipToNext() => _service.skipToNext();

  @override
  Future<void> skipToPrevious() => _service.skipToPrevious();
}
