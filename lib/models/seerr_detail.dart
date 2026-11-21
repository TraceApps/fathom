import '../l10n/generated/app_localizations.dart';
import 'seerr_request.dart';
import 'seerr_result.dart';

/// A movie collection (franchise) with its member titles.
class SeerrCollection {
  final int id;
  final String name;
  final String? overview;
  final String? backdropPath;
  final List<SeerrResult> parts;
  const SeerrCollection({
    required this.id,
    required this.name,
    this.overview,
    this.backdropPath,
    this.parts = const [],
  });

  String? get backdropUrl => backdropPath != null
      ? 'https://image.tmdb.org/t/p/w1280$backdropPath'
      : null;

  factory SeerrCollection.fromJson(Map<String, dynamic> j) => SeerrCollection(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        overview: j['overview'] as String?,
        backdropPath: j['backdropPath'] as String?,
        parts: [
          for (final p in (j['parts'] as List?) ?? const [])
            if (p is Map)
              SeerrResult.fromJson({
                ...Map<String, dynamic>.from(p),
                'mediaType': p['mediaType'] ?? 'movie',
              }),
        ],
      );
}

/// A cast member on a Seerr title.
class SeerrCast {
  final int id;
  final String name;
  final String? character;
  final String? profilePath;

  const SeerrCast(
      {required this.id, required this.name, this.character, this.profilePath});

  String? get profileUrl => profilePath != null
      ? 'https://image.tmdb.org/t/p/w185$profilePath'
      : null;

  factory SeerrCast.fromJson(Map<String, dynamic> j) => SeerrCast(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        character: j['character'] as String?,
        profilePath: j['profilePath'] as String?,
      );
}

/// A crew member (director, writer, etc.) on a title.
class SeerrCrew {
  final int id;
  final String name;
  final String? job;
  final String? profilePath;
  const SeerrCrew({required this.id, required this.name, this.job, this.profilePath});

  String? get profileUrl => profilePath != null
      ? 'https://image.tmdb.org/t/p/w185$profilePath'
      : null;

  factory SeerrCrew.fromJson(Map<String, dynamic> j) => SeerrCrew(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        job: j['job'] as String?,
        profilePath: j['profilePath'] as String?,
      );
}

/// One episode of a season.
class SeerrEpisode {
  final int episodeNumber;
  final String name;
  final String? overview;
  final String? stillPath;
  final String? airDate;
  final double? voteAverage;
  const SeerrEpisode({
    required this.episodeNumber,
    required this.name,
    this.overview,
    this.stillPath,
    this.airDate,
    this.voteAverage,
  });

  String? get stillUrl => stillPath != null
      ? 'https://image.tmdb.org/t/p/w300$stillPath'
      : null;

  factory SeerrEpisode.fromJson(Map<String, dynamic> j) => SeerrEpisode(
        episodeNumber: (j['episodeNumber'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        overview: j['overview'] as String?,
        stillPath: j['stillPath'] as String?,
        airDate: j['airDate'] as String?,
        voteAverage: (j['voteAverage'] as num?)?.toDouble(),
      );
}

/// A season of a TV title, merged with its per-season availability status.
class SeerrSeason {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final int? status; // 1 unknown,2 pending,3 processing,4 partial,5 available

  const SeerrSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.status,
  });

  bool get isRequested => status != null && status! >= 2;
  bool get isAvailable => status == 5;
}

/// A streaming service a title is available on, from TMDB watch providers.
class SeerrWatchProvider {
  final int id;
  final String name;
  final String? logoPath;
  const SeerrWatchProvider(
      {required this.id, required this.name, this.logoPath});

  String? get logoUrl => logoPath != null
      ? 'https://image.tmdb.org/t/p/w92$logoPath'
      : null;
}

/// An in-progress download reported by Radarr/Sonarr (mediaInfo.downloadStatus),
/// for the "Processing" progress bar on the detail page.
class SeerrDownload {
  final String title;
  final double size;
  final double sizeLeft;
  final String status; // e.g. 'downloading', 'queued'
  final String? estimatedCompletionTime; // ISO

  const SeerrDownload({
    required this.title,
    required this.size,
    required this.sizeLeft,
    required this.status,
    this.estimatedCompletionTime,
  });

  /// 0..1 downloaded so far.
  double get progress =>
      size > 0 ? ((size - sizeLeft) / size).clamp(0.0, 1.0) : 0.0;

  factory SeerrDownload.fromJson(Map<String, dynamic> j) => SeerrDownload(
        title: j['title'] as String? ?? '',
        size: (j['size'] as num?)?.toDouble() ?? 0,
        sizeLeft: (j['sizeLeft'] as num?)?.toDouble() ?? 0,
        status: j['status'] as String? ?? '',
        estimatedCompletionTime: j['estimatedCompletionTime'] as String?,
      );
}

/// Full detail for a movie or TV title from Seerr (TMDB-backed).
class SeerrDetail {
  final int tmdbId;
  final String mediaType; // 'movie' | 'tv'
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double? voteAverage;
  final int? status; // mediaInfo.status
  final int? mediaId; // mediaInfo.id (the record id for /media endpoints)
  final List<SeerrRequest> requests; // mediaInfo.requests, for the Manage panel
  final List<SeerrDownload> downloadStatus; // active downloads, for progress
  final String? releaseDate;
  final int? runtime; // minutes (movie)
  final String? certification; // content rating, e.g. R / TV-MA
  final List<String> genres;
  final List<SeerrCast> cast;
  final List<SeerrCrew> crew;
  final List<SeerrSeason> seasons; // TV only
  final List<String> studios;
  final String? jellyfinMediaId; // set when the title is on the Jellyfin server
  final int? tvdbId; // a show's TVDB id, which is how Sonarr knows it
  final String? trailerUrl; // YouTube trailer, if any
  final int? rtCriticScore; // Rotten Tomatoes critics, 0-100
  final int? rtAudienceScore; // Rotten Tomatoes audience, 0-100
  final double? imdbScore; // IMDb rating, 0-10

  // Extra TMDB info, for the detail page's facts + "Where to watch".
  final String? statusText; // e.g. 'Released', 'Returning Series'
  final String? originalLanguage; // ISO code, e.g. 'en'
  final String? homepage;
  final List<SeerrWatchProvider> watchProviders;
  final int? collectionId; // movie franchise, if any
  final String? collectionName;

  const SeerrDetail({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage,
    this.status,
    this.mediaId,
    this.requests = const [],
    this.downloadStatus = const [],
    this.releaseDate,
    this.runtime,
    this.certification,
    this.genres = const [],
    this.cast = const [],
    this.crew = const [],
    this.seasons = const [],
    this.studios = const [],
    this.jellyfinMediaId,
    this.tvdbId,
    this.trailerUrl,
    this.rtCriticScore,
    this.rtAudienceScore,
    this.imdbScore,
    this.statusText,
    this.originalLanguage,
    this.homepage,
    this.watchProviders = const [],
    this.collectionId,
    this.collectionName,
  });

  /// Overlays external ratings (fetched from a separate Seerr endpoint) onto an
  /// already-parsed detail.
  SeerrDetail copyWithRatings({
    int? rtCriticScore,
    int? rtAudienceScore,
    double? imdbScore,
  }) =>
      SeerrDetail(
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
        overview: overview,
        posterPath: posterPath,
        backdropPath: backdropPath,
        voteAverage: voteAverage,
        status: status,
        mediaId: mediaId,
        requests: requests,
        downloadStatus: downloadStatus,
        releaseDate: releaseDate,
        runtime: runtime,
        certification: certification,
        genres: genres,
        cast: cast,
        crew: crew,
        seasons: seasons,
        studios: studios,
        jellyfinMediaId: jellyfinMediaId,
        tvdbId: tvdbId,
        trailerUrl: trailerUrl,
        rtCriticScore: rtCriticScore ?? this.rtCriticScore,
        rtAudienceScore: rtAudienceScore ?? this.rtAudienceScore,
        imdbScore: imdbScore ?? this.imdbScore,
        statusText: statusText,
        originalLanguage: originalLanguage,
        homepage: homepage,
        watchProviders: watchProviders,
        collectionId: collectionId,
        collectionName: collectionName,
      );

  String? get posterUrl =>
      posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : null;
  String? get backdropUrl => backdropPath != null
      ? 'https://image.tmdb.org/t/p/w1280$backdropPath'
      : null;

  bool get isRequested => status != null && status! >= 2;
  bool get isAvailable => status == 5;

  /// The pending requests attached to this title (newest-shaped as returned).
  List<SeerrRequest> get pendingRequests =>
      requests.where((r) => r.isPending).toList();

  /// The single request the header's quick approve/decline acts on: the first
  /// pending one, preferring the non-4k request. Null when nothing is pending.
  SeerrRequest? get pendingRequest {
    final pending = pendingRequests;
    if (pending.isEmpty) return null;
    return pending.firstWhere((r) => !r.is4k, orElse: () => pending.first);
  }

  String? get year =>
      (releaseDate != null && releaseDate!.length >= 4)
          ? releaseDate!.substring(0, 4)
          : null;

  /// Localized display of the TMDB production status (`statusText`, an English
  /// wire value). Unrecognized values fall through to the raw string.
  String? statusLabel(AppLocalizations l) {
    switch (statusText) {
      case 'Returning Series':
        return l.miscSeerrStatusReturningSeries;
      case 'Ended':
        return l.miscSeerrStatusEnded;
      case 'Released':
        return l.miscSeerrStatusReleased;
      case 'In Production':
        return l.miscSeerrStatusInProduction;
      case 'Post Production':
        return l.miscSeerrStatusPostProduction;
      case 'Planned':
        return l.miscSeerrStatusPlanned;
      case 'Rumored':
        return l.miscSeerrStatusRumored;
      case 'Canceled':
        return l.miscSeerrStatusCanceled;
      case 'Pilot':
        return l.miscSeerrStatusPilot;
      default:
        return statusText;
    }
  }

  factory SeerrDetail.fromJson(Map<String, dynamic> j) {
    final isTv = j.containsKey('numberOfSeasons') || j['name'] != null;
    final mediaInfo = (j['mediaInfo'] as Map?)?.cast<String, dynamic>();
    final mediaTypeStr = isTv ? 'tv' : 'movie';
    final mediaTmdbId = (j['id'] as num?)?.toInt() ?? 0;
    final mediaRecordId = (mediaInfo?['id'] as num?)?.toInt();

    // mediaInfo.requests carries full request entities but usually omits the
    // back-reference to `media`, so inject the title's own ids/status before
    // parsing (SeerrRequest reads mediaType/tmdbId/status from there). An
    // existing nested media wins if present.
    final requests = <SeerrRequest>[
      for (final r in (mediaInfo?['requests'] as List?) ?? const [])
        if (r is Map)
          SeerrRequest.fromJson({
            ...Map<String, dynamic>.from(r),
            'media': {
              'mediaType': mediaTypeStr,
              'tmdbId': mediaTmdbId,
              'status': mediaInfo?['status'],
              'id': mediaRecordId,
              ...?(r['media'] as Map?)?.cast<String, dynamic>(),
            },
          }),
    ];

    // Per-season status lives in mediaInfo.seasons, keyed by seasonNumber.
    final statusBySeason = <int, int>{};
    for (final s in (mediaInfo?['seasons'] as List?) ?? const []) {
      if (s is Map) {
        final n = (s['seasonNumber'] as num?)?.toInt();
        final st = (s['status'] as num?)?.toInt();
        if (n != null && st != null) statusBySeason[n] = st;
      }
    }

    final seasons = <SeerrSeason>[];
    for (final s in (j['seasons'] as List?) ?? const []) {
      if (s is Map) {
        final n = (s['seasonNumber'] as num?)?.toInt() ?? 0;
        final episodes = (s['episodeCount'] as num?)?.toInt() ?? 0;
        // Season 0 is Specials; Jellyseerr lists it, but only when it has
        // episodes (an empty Specials placeholder isn't worth a row).
        if (n == 0 && episodes == 0) continue;
        seasons.add(SeerrSeason(
          seasonNumber: n,
          name: s['name'] as String? ?? (n == 0 ? 'Specials' : 'Season $n'),
          episodeCount: episodes,
          status: statusBySeason[n],
        ));
      }
    }

    final cast = <SeerrCast>[];
    final credits = (j['credits'] as Map?)?['cast'] as List?;
    for (final c in credits ?? const []) {
      if (c is Map) cast.add(SeerrCast.fromJson(Map<String, dynamic>.from(c)));
    }
    final crew = <SeerrCrew>[];
    final crewRaw = (j['credits'] as Map?)?['crew'] as List?;
    for (final c in crewRaw ?? const []) {
      if (c is Map) crew.add(SeerrCrew.fromJson(Map<String, dynamic>.from(c)));
    }

    // Watch providers arrive as an array of regions; take the first (Jellyseerr
    // filters to the configured region), preferring streaming over buy/rent.
    final providers = <SeerrWatchProvider>[];
    final wp = j['watchProviders'];
    if (wp is List && wp.isNotEmpty && wp.first is Map) {
      final region = wp.first as Map;
      final flat = (region['flatrate'] as List?) ?? const [];
      for (final p in flat.whereType<Map>()) {
        providers.add(SeerrWatchProvider(
          id: (p['id'] as num?)?.toInt() ?? 0,
          name: p['name'] as String? ?? '',
          logoPath: p['logoPath'] as String?,
        ));
      }
    }

    return SeerrDetail(
      tmdbId: (j['id'] as num?)?.toInt() ?? 0,
      mediaType: isTv ? 'tv' : 'movie',
      title: (j['title'] ?? j['name'] ?? '') as String,
      overview: j['overview'] as String?,
      posterPath: j['posterPath'] as String?,
      backdropPath: j['backdropPath'] as String?,
      voteAverage: (j['voteAverage'] as num?)?.toDouble(),
      status: mediaInfo?['status'] as int?,
      mediaId: mediaRecordId,
      requests: requests,
      downloadStatus: [
        for (final d in (mediaInfo?['downloadStatus'] as List?) ?? const [])
          if (d is Map) SeerrDownload.fromJson(d.cast<String, dynamic>()),
      ],
      releaseDate: (j['releaseDate'] ?? j['firstAirDate']) as String?,
      runtime: (j['runtime'] as num?)?.toInt(),
      certification: _certification(j, isTv),
      genres: [
        for (final g in (j['genres'] as List?) ?? const [])
          if (g is Map && g['name'] != null) g['name'] as String,
      ],
      cast: cast,
      crew: crew,
      seasons: seasons,
      studios: [
        for (final s in (j['productionCompanies'] as List?) ?? const [])
          if (s is Map && s['name'] != null) s['name'] as String,
      ],
      jellyfinMediaId: (mediaInfo?['jellyfinMediaId'] ??
          mediaInfo?['jellyfinMediaId4k']) as String?,
      // TMDB's own answer first; Seerr's record of the show has it too.
      tvdbId: ((j['externalIds'] as Map?)?['tvdbId'] as num?)?.toInt() ??
          (mediaInfo?['tvdbId'] as num?)?.toInt(),
      trailerUrl: _firstTrailer(j['relatedVideos']),
      statusText: j['status'] as String?,
      originalLanguage: j['originalLanguage'] as String?,
      collectionId: (j['collection'] as Map?)?['id'] as int?,
      collectionName: (j['collection'] as Map?)?['name'] as String?,
      homepage: (j['homepage'] as String?)?.isNotEmpty == true
          ? j['homepage'] as String
          : null,
      watchProviders: providers,
    );
  }

  /// The US content rating: `releases` (release_dates) for movies, or
  /// `contentRatings` for TV, both TMDB-shaped in Seerr's response.
  static String? _certification(Map<String, dynamic> j, bool isTv) {
    final results = (j[isTv ? 'contentRatings' : 'releases'] as Map?)?['results'];
    if (results is! List) return null;
    Map? region;
    for (final r in results) {
      if (r is Map && r['iso_3166_1'] == 'US') {
        region = r;
        break;
      }
    }
    region ??= results.whereType<Map>().isNotEmpty
        ? results.whereType<Map>().first
        : null;
    if (region == null) return null;
    if (isTv) {
      final rating = region['rating'];
      return (rating is String && rating.isNotEmpty) ? rating : null;
    }
    for (final d in (region['release_dates'] as List?) ?? const []) {
      if (d is Map) {
        final c = d['certification'];
        if (c is String && c.isNotEmpty) return c;
      }
    }
    return null;
  }

  static String? _firstTrailer(dynamic videos) {
    if (videos is! List) return null;
    for (final v in videos) {
      if (v is Map && v['url'] is String) {
        final type = v['type'] as String?;
        if (type == null || type == 'Trailer') return v['url'] as String;
      }
    }
    return null;
  }
}
