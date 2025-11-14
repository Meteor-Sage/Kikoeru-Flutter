import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/audio_track.dart';

/// 播放器封面组件
class PlayerCoverWidget extends StatelessWidget {
  final AudioTrack track;
  final String? workCoverUrl;
  final bool isLandscape;
  final VoidCallback? onTap;

  const PlayerCoverWidget({
    super.key,
    required this.track,
    this.workCoverUrl,
    this.isLandscape = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Hero(
          tag: 'audio_player_artwork_${track.id}',
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isLandscape
                  ? MediaQuery.of(context).size.width * 0.35
                  : MediaQuery.of(context).size.width - 48,
              maxHeight: isLandscape
                  ? MediaQuery.of(context).size.height * 0.6
                  : MediaQuery.of(context).size.height * 0.4,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: (workCoverUrl ?? track.artworkUrl) != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: (workCoverUrl ?? track.artworkUrl)!,
                        fit: BoxFit.contain,
                        errorWidget: (context, url, error) {
                          return Padding(
                            padding: const EdgeInsets.all(40),
                            child: Icon(
                              Icons.album,
                              size: isLandscape ? 80 : 120,
                            ),
                          );
                        },
                        placeholder: (context, url) {
                          return Padding(
                            padding: const EdgeInsets.all(40),
                            child: Icon(
                              Icons.album,
                              size: isLandscape ? 80 : 120,
                            ),
                          );
                        },
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(40),
                      child: Icon(
                        Icons.album,
                        size: isLandscape ? 80 : 120,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
