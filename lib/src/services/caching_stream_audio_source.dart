import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

import 'cache_service.dart';

class CachingStreamAudioSource extends StreamAudioSource {
  CachingStreamAudioSource({
    required this.uri,
    required this.hash,
  });

  final Uri uri;
  final String hash;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final resolvedStart = start ?? 0;
    final client = HttpClient();
    final request = await client.getUrl(uri);

    if (resolvedStart != 0 || end != null) {
      final endInclusive = end != null ? end - 1 : null;
      final rangeHeader = endInclusive != null
          ? 'bytes=$resolvedStart-$endInclusive'
          : 'bytes=$resolvedStart-';
      request.headers.set(HttpHeaders.rangeHeader, rangeHeader);
    }

    final response = await request.close();

    if (response.statusCode >= 400) {
      client.close(force: true);
      throw HttpException(
        'Failed to load audio (status: ${response.statusCode})',
        uri: uri,
      );
    }

    final totalLength = _parseSourceLength(response.headers, resolvedStart);
    final responseLength = response.contentLength >= 0
        ? response.contentLength
        : (totalLength != null ? totalLength - resolvedStart : null);
    final contentType = response.headers.contentType?.toString();

    final controller = StreamController<List<int>>();
    final tempFile = await CacheService.prepareAudioCacheTempFile(hash);
    final existingLength = await tempFile.length();

    // 非顺序请求时，仅做透传，不写入缓存
    if (resolvedStart != existingLength) {
      () async {
        try {
          await for (final chunk in response) {
            controller.add(chunk);
          }
          await controller.close();
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await controller.close();
        } finally {
          client.close();
        }
      }();

      return StreamAudioResponse(
        sourceLength: totalLength,
        contentLength: responseLength,
        offset: resolvedStart,
        stream: controller.stream,
        contentType: contentType ?? 'application/octet-stream',
      );
    }

    final raf = await tempFile.open(mode: FileMode.writeOnlyAppend);
    int bytesWritten = 0;

    () async {
      try {
        await for (final chunk in response) {
          bytesWritten += chunk.length;
          controller.add(chunk);
          await raf.writeFrom(chunk);
        }
        await raf.flush();
        await raf.close();
        await controller.close();

        if (totalLength != null) {
          await CacheService.finalizeAudioCacheFile(
            hash,
            expectedSize: totalLength,
          );
        } else if (resolvedStart == 0) {
          await CacheService.finalizeAudioCacheFile(
            hash,
            expectedSize: existingLength + bytesWritten,
          );
        }
      } catch (error, stackTrace) {
        await raf.close();
        controller.addError(error, stackTrace);
        await controller.close();
      } finally {
        client.close();
      }
    }();

    return StreamAudioResponse(
      sourceLength: totalLength,
      contentLength: responseLength,
      offset: resolvedStart,
      stream: controller.stream,
      contentType: contentType ?? 'application/octet-stream',
    );
  }

  int? _parseSourceLength(HttpHeaders headers, int start) {
    final contentRange = headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      final match = RegExp(r'bytes \d+-\d+/(\d+)').firstMatch(contentRange);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }

    final length = headers.contentLength;
    if (length != -1 && start == 0) {
      return length;
    }
    return null;
  }
}
