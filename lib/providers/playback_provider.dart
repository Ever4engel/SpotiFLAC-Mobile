import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_queue_provider.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('PlaybackProvider');

class PlaybackState {
  const PlaybackState();
}

class PlaybackController extends Notifier<PlaybackState> {
  @override
  PlaybackState build() => const PlaybackState();

  Future<void> playLocalPath({
    required String path,
    required String title,
    required String artist,
    String album = '',
    String coverUrl = '',
    Track? track,
  }) async {
    if (isCueVirtualPath(path)) {
      throw Exception(cueVirtualTrackRequiresSplitMessage);
    }
    _log.d('Opening external player for "$title" by $artist: $path');
    await openFile(path);
  }

  Future<void> playTrackList(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;

    final orderedTracks = _orderedTracksFromStartIndex(tracks, startIndex);
    var skippedCueVirtualTrack = false;
    for (final track in orderedTracks) {
      final resolvedPath = await _resolveTrackPath(track);
      if (resolvedPath == null) {
        continue;
      }
      if (isCueVirtualPath(resolvedPath)) {
        skippedCueVirtualTrack = true;
        continue;
      }

      _log.d(
        'Opening first available external track for list playback: '
        '"${track.name}" by ${track.artistName} -> $resolvedPath',
      );
      await openFile(resolvedPath);
      return;
    }

    if (skippedCueVirtualTrack) {
      throw Exception(cueVirtualTrackRequiresSplitMessage);
    }

    throw Exception(
      'No local audio file is available to open. Download the track first.',
    );
  }

  List<Track> _orderedTracksFromStartIndex(List<Track> tracks, int startIndex) {
    final safeStart = startIndex.clamp(0, tracks.length - 1);
    if (safeStart == 0) {
      return List<Track>.from(tracks, growable: false);
    }

    return <Track>[
      ...tracks.sublist(safeStart),
      ...tracks.sublist(0, safeStart),
    ];
  }

  Future<String?> _resolveTrackPath(Track track) async {
    final historyState = ref.read(downloadHistoryProvider);
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);

    final localItem = await _findLocalLibraryItemForTrack(track);
    if (localItem != null && await fileExists(localItem.filePath)) {
      return localItem.filePath;
    }

    final historyItem = await _findDownloadHistoryItemForTrack(
      track,
      historyState,
    );
    if (historyItem != null) {
      if (await fileExists(historyItem.filePath)) {
        return historyItem.filePath;
      }
      historyNotifier.removeFromHistory(historyItem.id);
    }

    return null;
  }

  Future<LocalLibraryItem?> _findLocalLibraryItemForTrack(Track track) async {
    final isLocalSource = (track.source ?? '').toLowerCase() == 'local';
    if (isLocalSource) {
      final byId = await ref
          .read(localLibraryProvider.notifier)
          .getById(track.id);
      if (byId != null) return byId;
    }

    final isrc = track.isrc?.trim();
    return ref
        .read(localLibraryProvider.notifier)
        .findExistingAsync(
          isrc: isrc,
          trackName: track.name,
          artistName: track.artistName,
        );
  }

  Future<DownloadHistoryItem?> _findDownloadHistoryItemForTrack(
    Track track,
    DownloadHistoryState historyState,
  ) async {
    final historyNotifier = ref.read(downloadHistoryProvider.notifier);
    for (final candidateId in _spotifyIdLookupCandidates(track.id)) {
      final bySpotifyId = historyState.getBySpotifyId(candidateId);
      if (bySpotifyId != null) {
        return bySpotifyId;
      }
      final bySpotifyIdAsync = await historyNotifier.getBySpotifyIdAsync(
        candidateId,
      );
      if (bySpotifyIdAsync != null) {
        return bySpotifyIdAsync;
      }
    }

    final isrc = track.isrc?.trim();
    if (isrc != null && isrc.isNotEmpty) {
      final byIsrc = historyState.getByIsrc(isrc);
      if (byIsrc != null) {
        return byIsrc;
      }
      final byIsrcAsync = await historyNotifier.getByIsrcAsync(isrc);
      if (byIsrcAsync != null) {
        return byIsrcAsync;
      }
    }

    return historyNotifier.findByTrackAndArtistAsync(
      track.name,
      track.artistName,
    );
  }

  List<String> _spotifyIdLookupCandidates(String rawId) {
    final trimmed = rawId.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final candidates = <String>{trimmed};
    final lowered = trimmed.toLowerCase();
    if (lowered.startsWith('spotify:track:')) {
      final compact = trimmed.split(':').last.trim();
      if (compact.isNotEmpty) {
        candidates.add(compact);
      }
    } else if (!trimmed.contains(':')) {
      candidates.add('spotify:track:$trimmed');
    }

    final uri = Uri.tryParse(trimmed);
    final segments = uri?.pathSegments ?? const <String>[];
    final trackIndex = segments.indexOf('track');
    if (trackIndex >= 0 && trackIndex + 1 < segments.length) {
      final pathId = segments[trackIndex + 1].trim();
      if (pathId.isNotEmpty) {
        candidates.add(pathId);
        candidates.add('spotify:track:$pathId');
      }
    }

    return candidates.toList(growable: false);
  }
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackState>(
  PlaybackController.new,
);
