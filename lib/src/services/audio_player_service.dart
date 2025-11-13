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
  bool _completionHandled = false; // Track if completion has been handled for current track
  Timer? _completionCheckTimer; // Timer to periodically check for completion

  // Windows SMTC support
  SMTCWindows? _smtc;

  // Stream controllers
  final StreamController<List<AudioTrack>> _queueController =
      StreamController.broadcast();
  final StreamController<AudioTrack?> _currentTrackController =
      StreamController.broadcast();

  // Initialize the service
  Future<void> initialize() async {
    print('[Audio] initialize() called');
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
      print('[Audio] PlayerState Stream Event - processingState: ${state.processingState}, playing: ${state.playing}');
      
      if (state.processingState == ProcessingState.completed) {
        print('[Audio] Track completed via ProcessingState.completed');
        _handleTrackCompletion();
      }

      // Update audio service playback state
      _updatePlaybackState();
    });

        // Listen to position changes and detect completion as fallback
    Duration lastPosition = Duration.zero;
    int positionEventCount = 0;
    _player.positionStream.listen((position) {
      positionEventCount++;
      final duration = _player.duration;
      final processingState = _player.processingState;
      
      // Log every 10 events to confirm stream is working
      if (positionEventCount % 10 == 0) {
        print('[Audio] PositionStream event #$positionEventCount - position: ${position.inSeconds}s, state: $processingState');
      }
      
      // Reset completion flag when track changes or seeks
      if (position < lastPosition - const Duration(seconds: 1)) {
        _completionHandled = false;
        print('[Audio] Position reset detected, clearing completion flag');
      }
      
      // Check for immediate completion (when processingState is completed but stream didn't fire)
      if (processingState == ProcessingState.completed && 
          !_completionHandled &&
          _player.playing) {
        print('[Audio] Detected completed state in position stream - position: ${position.inSeconds}s');
        _completionHandled = true;
        _handleTrackCompletion();
        return;
      }
      
      // Fallback: detect completion when position reaches duration
      if (duration != null && 
          position >= duration - const Duration(milliseconds: 100) &&
          _player.playing &&
          !_completionHandled) {
        print('[Audio] Position near end - position: ${position.inSeconds}s, duration: ${duration.inSeconds}s, playing: ${_player.playing}');
        
        // Check if position is stuck at the end (completion not triggered)
        if (lastPosition != Duration.zero && 
            (position - lastPosition).inMilliseconds.abs() < 50 &&
            position >= duration - const Duration(milliseconds: 100)) {
          print('[Audio] Detected completion via position fallback - position stuck at ${position.inSeconds}s');
          _completionHandled = true;
          _handleTrackCompletion();
        }
      }
      
      lastPosition = position;
      _updatePlaybackState();
    });
    
    // Start periodic completion check timer (macOS workaround for StreamAudioSource completion bug)
    if (Platform.isMacOS) {
      print('[Audio] About to start completion check timer (macOS workaround)');
      _startCompletionCheckTimer();
    }
    print('[Audio] initialize() completed');
  }

  // Handle track completion logic
  void _handleTrackCompletion() {
    print('[Audio] _handleTrackCompletion called - currentIndex: $_currentIndex, queueLength: ${_queue.length}, loopMode: $_appLoopMode');
    
    if (_appLoopMode == LoopMode.one) {
      // Single track repeat - replay current track
      print('[Audio] Loop mode: one - replaying current track');
      seek(Duration.zero);
      play();
    } else if (_currentIndex < _queue.length - 1) {
      // Has next track - play it
      print('[Audio] Playing next track - index: ${_currentIndex + 1}');
      skipToNext();
    } else if (_appLoopMode == LoopMode.all && _queue.isNotEmpty) {
      // List repeat - go back to first track
      print('[Audio] Loop mode: all - going back to first track');
      skipToIndex(0);
    } else {
      // Reached the end of the queue with no repeat, pause
      print('[Audio] End of queue reached - pausing');
      pause();
    }
  }

  // Start periodic timer to check for track completion (macOS workaround)
  // This is needed because StreamAudioSource on macOS doesn't properly fire completion events
  void _startCompletionCheckTimer() {
    print('[Audio] _startCompletionCheckTimer called (macOS workaround)');
    _completionCheckTimer?.cancel();
    print('[Audio] Creating new periodic timer');
    int tickCount = 0;
    _completionCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      tickCount++;
      final position = _player.position;
      final duration = _player.duration;
      final processingState = _player.processingState;
      final playing = _player.playing;
      
      // Log every tick for debugging
      print('[Audio] Timer tick #$tickCount - playing: $playing, state: $processingState, position: ${position.inSeconds}s/${duration?.inSeconds ?? '?'}s, completionHandled: $_completionHandled');
      
      if (playing && !_completionHandled) {
        // Check if track is completed
        if (processingState == ProcessingState.completed) {
          print('[Audio] Timer detected completion - processingState: completed');
          _completionHandled = true;
          _handleTrackCompletion();
        } else if (duration != null && 
                   duration > Duration.zero && // Must have valid duration
                   position >= duration - const Duration(milliseconds: 50)) {
          print('[Audio] Timer detected completion - position: ${position.inSeconds}/${duration.inSeconds}s');
          _completionHandled = true;
          _handleTrackCompletion();
        }
      }
    });
    print('[Audio] Timer created, isActive: ${_completionCheckTimer?.isActive ?? false}');
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
    print('[Audio] updateQueue called - tracks: ${tracks.length}, startIndex: $startIndex');
    _queue.clear();
    _queue.addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);

    _queueController.add(List.from(_queue));

    // Load the current track
    if (tracks.isNotEmpty && _currentIndex < tracks.length) {
      await _loadTrack(tracks[_currentIndex]);
      print('[Audio] Track loaded, ready to play');
    }
  }

  Future<void> _loadTrack(AudioTrack track) async {
    print('[Audio] Loading track: ${track.title}, hash: ${track.hash}');
    
    // Reset completion flag for new track
    _completionHandled = false;
    print('[Audio] Completion flag reset, timer active: ${_completionCheckTimer?.isActive ?? false}');
    
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

      print('[Audio] Track loaded successfully, duration: ${_player.duration}');
      _currentTrackController.add(track);

      // Update media item for system controls
      _updateMediaItem(track);
    } catch (e) {
      print('[Audio] Error loading audio source: $e');
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

  // Playback controls
  Future<void> play() async {
    print('[Audio] play() called - current state: ${_player.processingState}, playing: ${_player.playing}');
    
    // Ensure completion check timer is running (macOS workaround for StreamAudioSource completion bug)
    if (Platform.isMacOS && (_completionCheckTimer == null || !_completionCheckTimer!.isActive)) {
      print('[Audio] Timer not active, starting it now (macOS workaround)');
      _startCompletionCheckTimer();
    }
    
    await _player.play();
    print('[Audio] play() completed - new state: ${_player.processingState}, playing: ${_player.playing}');
    
    // Check if track completed immediately (workaround for immediate completion bug)
    if (_player.processingState == ProcessingState.completed) {
      print('[Audio] Track completed immediately after play() - triggering completion handler');
      Future.delayed(const Duration(milliseconds: 100), () {
        _handleTrackCompletion();
      });
    }
    
    _updatePlaybackState();
  }

  Future<void> pause() async {
    print('[Audio] pause() called');
    await _player.pause();
    _updatePlaybackState();
  }

  Future<void> stop() async {
    await _player.stop();
    _updatePlaybackState();
  }

  Future<void> seek(Duration position) async {
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
    print('[Audio] skipToNext() called - currentIndex: $_currentIndex, queueLength: ${_queue.length}');
    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      _currentIndex++;
      await _loadTrack(_queue[_currentIndex]);
      await play();
    } else {
      // No next track available
      print('[Audio] skipToNext() failed - no next track');
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
