import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';

class TrackState {
  final List<Track> tracks;
  final bool isLoading;
  final String? error;
  final String? albumId;
  final String? albumName;
  final String? playlistName;
  final String? artistId;
  final String? artistName;
  final String? coverUrl;
  final List<ArtistAlbum>? artistAlbums; // For artist page
  final List<SearchArtist>? searchArtists; // For search results
  final bool hasSearchText; // For back button handling

  const TrackState({
    this.tracks = const [],
    this.isLoading = false,
    this.error,
    this.albumId,
    this.albumName,
    this.playlistName,
    this.artistId,
    this.artistName,
    this.coverUrl,
    this.artistAlbums,
    this.searchArtists,
    this.hasSearchText = false,
  });

  bool get hasContent => tracks.isNotEmpty || artistAlbums != null || (searchArtists != null && searchArtists!.isNotEmpty);

  TrackState copyWith({
    List<Track>? tracks,
    bool? isLoading,
    String? error,
    String? albumId,
    String? albumName,
    String? playlistName,
    String? artistId,
    String? artistName,
    String? coverUrl,
    List<ArtistAlbum>? artistAlbums,
    List<SearchArtist>? searchArtists,
    bool? hasSearchText,
  }) {
    return TrackState(
      tracks: tracks ?? this.tracks,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      albumId: albumId ?? this.albumId,
      albumName: albumName ?? this.albumName,
      playlistName: playlistName ?? this.playlistName,
      artistId: artistId ?? this.artistId,
      artistName: artistName ?? this.artistName,
      coverUrl: coverUrl ?? this.coverUrl,
      artistAlbums: artistAlbums ?? this.artistAlbums,
      searchArtists: searchArtists ?? this.searchArtists,
      hasSearchText: hasSearchText ?? this.hasSearchText,
    );
  }
}

/// Represents an album in artist discography
class ArtistAlbum {
  final String id;
  final String name;
  final String releaseDate;
  final int totalTracks;
  final String? coverUrl;
  final String albumType; // album, single, compilation
  final String artists;

  const ArtistAlbum({
    required this.id,
    required this.name,
    required this.releaseDate,
    required this.totalTracks,
    this.coverUrl,
    required this.albumType,
    required this.artists,
  });
}

/// Represents an artist in search results
class SearchArtist {
  final String id;
  final String name;
  final String? imageUrl;
  final int followers;
  final int popularity;

  const SearchArtist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.followers,
    required this.popularity,
  });
}

class TrackNotifier extends Notifier<TrackState> {
  /// Request ID to track and cancel outdated requests
  int _currentRequestId = 0;

  @override
  TrackState build() {
    return const TrackState();
  }

  /// Check if request is still valid (not cancelled by newer request)
  bool _isRequestValid(int requestId) => requestId == _currentRequestId;

  Future<void> fetchFromUrl(String url, {bool useDeezerFallback = true}) async {
    // Increment request ID to cancel any pending requests
    final requestId = ++_currentRequestId;

    // Preserve hasSearchText during fetch
    state = TrackState(isLoading: true, hasSearchText: state.hasSearchText);

    try {
      final parsed = await PlatformBridge.parseSpotifyUrl(url);
      if (!_isRequestValid(requestId)) return; // Request cancelled
      
      final type = parsed['type'] as String;

      // Use the new fallback-enabled method
      Map<String, dynamic> metadata;
      
      try {
        // ignore: avoid_print
        print('[FetchURL] Fetching $type with Deezer fallback enabled...');
        metadata = await PlatformBridge.getSpotifyMetadataWithFallback(url);
        // ignore: avoid_print
        print('[FetchURL] Metadata fetch success');
      } catch (e) {
        // If fallback also fails, show error
        // ignore: avoid_print
        print('[FetchURL] Metadata fetch failed: $e');
        rethrow;
      }
      
      if (!_isRequestValid(requestId)) return; // Request cancelled

      if (type == 'track') {
        final trackData = metadata['track'] as Map<String, dynamic>;
        final track = _parseTrack(trackData);
        state = TrackState(
          tracks: [track],
          isLoading: false,
          coverUrl: track.coverUrl,
        );
      } else if (type == 'album') {
        final albumInfo = metadata['album_info'] as Map<String, dynamic>;
        final trackList = metadata['track_list'] as List<dynamic>;
        final tracks = trackList.map((t) => _parseTrack(t as Map<String, dynamic>)).toList();
        state = TrackState(
          tracks: tracks,
          isLoading: false,
          albumId: parsed['id'] as String?,
          albumName: albumInfo['name'] as String?,
          coverUrl: albumInfo['images'] as String?,
        );
        // Pre-warm cache for album tracks in background
        _preWarmCacheForTracks(tracks);
      } else if (type == 'playlist') {
        final playlistInfo = metadata['playlist_info'] as Map<String, dynamic>;
        final trackList = metadata['track_list'] as List<dynamic>;
        final tracks = trackList.map((t) => _parseTrack(t as Map<String, dynamic>)).toList();
        final owner = playlistInfo['owner'] as Map<String, dynamic>?;
        state = TrackState(
          tracks: tracks,
          isLoading: false,
          playlistName: owner?['name'] as String?,
          coverUrl: owner?['images'] as String?,
        );
        // Pre-warm cache for playlist tracks in background
        _preWarmCacheForTracks(tracks);
      } else if (type == 'artist') {
        final artistInfo = metadata['artist_info'] as Map<String, dynamic>;
        final albumsList = metadata['albums'] as List<dynamic>;
        final albums = albumsList.map((a) => _parseArtistAlbum(a as Map<String, dynamic>)).toList();
        state = TrackState(
          tracks: [], // No tracks for artist view
          isLoading: false,
          artistId: artistInfo['id'] as String?,
          artistName: artistInfo['name'] as String?,
          coverUrl: artistInfo['images'] as String?,
          artistAlbums: albums,
        );
      }
    } catch (e) {
      if (!_isRequestValid(requestId)) return; // Request cancelled
      // Preserve hasSearchText on error so user stays on search screen
      state = TrackState(isLoading: false, error: e.toString(), hasSearchText: state.hasSearchText);
    }
  }

  Future<void> search(String query, {String? metadataSource}) async {
    // Increment request ID to cancel any pending requests
    final requestId = ++_currentRequestId;

    // Preserve hasSearchText during search
    state = TrackState(isLoading: true, hasSearchText: state.hasSearchText);

    try {
      // Use Deezer or Spotify based on settings
      final source = metadataSource ?? 'deezer';
      
      // Debug log to show which source is being used
      // ignore: avoid_print
      print('[Search] Using metadata source: $source for query: "$query"');
      
      Map<String, dynamic> results;
      if (source == 'deezer') {
        results = await PlatformBridge.searchDeezerAll(query, trackLimit: 20, artistLimit: 5);
        // ignore: avoid_print
        print('[Search] Deezer returned ${(results['tracks'] as List?)?.length ?? 0} tracks');
      } else {
        results = await PlatformBridge.searchSpotifyAll(query, trackLimit: 20, artistLimit: 5);
        // ignore: avoid_print
        print('[Search] Spotify returned ${(results['tracks'] as List?)?.length ?? 0} tracks');
      }
      
      if (!_isRequestValid(requestId)) return; // Request cancelled
      
      final trackList = results['tracks'] as List<dynamic>? ?? [];
      final artistList = results['artists'] as List<dynamic>? ?? [];
      
      // Parse tracks with error handling per item
      final tracks = <Track>[];
      for (final t in trackList) {
        try {
          if (t is Map<String, dynamic>) {
            tracks.add(_parseSearchTrack(t));
          }
        } catch (e) {
          // ignore: avoid_print
          print('[Search] Failed to parse track: $e');
        }
      }
      
      // Parse artists with error handling per item
      final artists = <SearchArtist>[];
      for (final a in artistList) {
        try {
          if (a is Map<String, dynamic>) {
            artists.add(_parseSearchArtist(a));
          }
        } catch (e) {
          // ignore: avoid_print
          print('[Search] Failed to parse artist: $e');
        }
      }
      
      // ignore: avoid_print
      print('[Search] Parsed ${tracks.length} tracks, ${artists.length} artists');
      
      state = TrackState(
        tracks: tracks,
        searchArtists: artists,
        isLoading: false,
        hasSearchText: state.hasSearchText,
      );
    } catch (e) {
      if (!_isRequestValid(requestId)) return; // Request cancelled
      // Preserve hasSearchText on error so user stays on search screen
      state = TrackState(isLoading: false, error: e.toString(), hasSearchText: state.hasSearchText);
    }
  }

  Future<void> checkAvailability(int index) async {
    if (index < 0 || index >= state.tracks.length) return;

    final track = state.tracks[index];
    if (track.isrc == null || track.isrc!.isEmpty) return;

    try {
      final availability = await PlatformBridge.checkAvailability(track.id, track.isrc!);
      final updatedTrack = Track(
        id: track.id,
        name: track.name,
        artistName: track.artistName,
        albumName: track.albumName,
        albumArtist: track.albumArtist,
        coverUrl: track.coverUrl,
        isrc: track.isrc,
        duration: track.duration,
        trackNumber: track.trackNumber,
        discNumber: track.discNumber,
        releaseDate: track.releaseDate,
        availability: ServiceAvailability(
          tidal: availability['tidal'] as bool? ?? false,
          qobuz: availability['qobuz'] as bool? ?? false,
          amazon: availability['amazon'] as bool? ?? false,
          tidalUrl: availability['tidal_url'] as String?,
          qobuzUrl: availability['qobuz_url'] as String?,
          amazonUrl: availability['amazon_url'] as String?,
        ),
      );

      final tracks = List<Track>.from(state.tracks);
      tracks[index] = updatedTrack;
      state = state.copyWith(tracks: tracks);
    } catch (e) {
      // Silently fail availability check
    }
  }

  void clear() {
    state = const TrackState();
  }

  /// Set search text state for back button handling
  void setSearchText(bool hasText) {
    state = state.copyWith(hasSearchText: hasText);
  }

  Track _parseTrack(Map<String, dynamic> data) {
    return Track(
      id: data['spotify_id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      artistName: data['artists'] as String? ?? '',
      albumName: data['album_name'] as String? ?? '',
      albumArtist: data['album_artist'] as String?,
      coverUrl: data['images'] as String?,
      isrc: data['isrc'] as String?,
      duration: ((data['duration_ms'] as int? ?? 0) / 1000).round(),
      trackNumber: data['track_number'] as int?,
      discNumber: data['disc_number'] as int?,
      releaseDate: data['release_date'] as String?,
    );
  }

  Track _parseSearchTrack(Map<String, dynamic> data) {
    // Handle duration_ms which might be int or double
    int durationMs = 0;
    final durationValue = data['duration_ms'];
    if (durationValue is int) {
      durationMs = durationValue;
    } else if (durationValue is double) {
      durationMs = durationValue.toInt();
    }
    
    return Track(
      id: (data['spotify_id'] ?? data['id'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      artistName: (data['artists'] ?? data['artist'] ?? '').toString(),
      albumName: (data['album_name'] ?? data['album'] ?? '').toString(),
      albumArtist: data['album_artist']?.toString(),
      coverUrl: data['images']?.toString(),
      isrc: data['isrc']?.toString(),
      duration: (durationMs / 1000).round(),
      trackNumber: data['track_number'] as int?,
      discNumber: data['disc_number'] as int?,
      releaseDate: data['release_date']?.toString(),
    );
  }

  ArtistAlbum _parseArtistAlbum(Map<String, dynamic> data) {
    return ArtistAlbum(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      releaseDate: data['release_date'] as String? ?? '',
      totalTracks: data['total_tracks'] as int? ?? 0,
      coverUrl: data['images'] as String?,
      albumType: data['album_type'] as String? ?? 'album',
      artists: data['artists'] as String? ?? '',
    );
  }

  SearchArtist _parseSearchArtist(Map<String, dynamic> data) {
    return SearchArtist(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      imageUrl: data['images'] as String?,
      followers: data['followers'] as int? ?? 0,
      popularity: data['popularity'] as int? ?? 0,
    );
  }

  /// Pre-warm track ID cache for faster downloads
  /// Runs in background, doesn't block UI
  void _preWarmCacheForTracks(List<Track> tracks) {
    // Only pre-warm if we have tracks with ISRC
    final tracksWithIsrc = tracks.where((t) => t.isrc != null && t.isrc!.isNotEmpty).toList();
    if (tracksWithIsrc.isEmpty) return;

    // Build request list for Go backend
    final cacheRequests = tracksWithIsrc.map((t) => {
      'isrc': t.isrc!,
      'track_name': t.name,
      'artist_name': t.artistName,
      'spotify_id': t.id, // Include Spotify ID for Amazon lookup
      'service': 'tidal', // Default to tidal for pre-warming
    }).toList();

    // Fire and forget - runs in background
    PlatformBridge.preWarmTrackCache(cacheRequests).catchError((_) {
      // Silently ignore errors - this is just an optimization
    });
  }
}

final trackProvider = NotifierProvider<TrackNotifier, TrackState>(
  TrackNotifier.new,
);
