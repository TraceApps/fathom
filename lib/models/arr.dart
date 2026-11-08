/// Sonarr and Radarr data, read from their v3 API (Sonarr 4 and Radarr 5 both
/// still serve /api/v3). Field names follow their OpenAPI specs.
library;

enum ArrKind { sonarr, radarr }

extension ArrKindName on ArrKind {
  /// The app's own name, never translated.
  String get appName => this == ArrKind.sonarr ? 'Sonarr' : 'Radarr';
}

DateTime? _date(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

/// Movie release dates are days, sent as midnight UTC. Kept as that day;
/// turning them into local time would move them a day earlier west of UTC.
DateTime? _day(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final d = DateTime.tryParse(v)?.toUtc();
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
int? _intOrNull(Object? v) => (v as num?)?.toInt();
List<Map<String, dynamic>> _maps(Object? v) => [
  for (final e in (v as List?) ?? const [])
    if (e is Map) Map<String, dynamic>.from(e),
];
List<String> _strings(Object? v) => [
  for (final e in (v as List?) ?? const [])
    if (e is String) e,
];

/// One picture of a title (poster, fanart, banner...). [url] is the copy the
/// server keeps (needs the API key), [remoteUrl] the original online.
class ArrImage {
  final String coverType;
  final String? url;
  final String? remoteUrl;
  const ArrImage({required this.coverType, this.url, this.remoteUrl});

  factory ArrImage.fromJson(Map<String, dynamic> j) => ArrImage(
    coverType: j['coverType'] as String? ?? '',
    url: j['url'] as String?,
    remoteUrl: j['remoteUrl'] as String?,
  );
}

List<ArrImage> _images(Object? v) => [
  for (final m in _maps(v)) ArrImage.fromJson(m),
];

/// A quality as the apps name it ("Bluray-1080p", "WEBDL-2160p").
String? _qualityName(Object? qualityModel) {
  final q = (qualityModel as Map?)?['quality'];
  return (q as Map?)?['name'] as String?;
}

/// The technical details of a file, as the apps read them from the file.
class ArrMediaInfo {
  final String? videoCodec;
  final String? resolution;
  final String? videoDynamicRangeType; // HDR10, DV, HLG...
  final int? videoBitDepth;
  final String? audioCodec;
  final double? audioChannels;
  final String? audioLanguages;
  final String? subtitles;
  final String? runTime;

  const ArrMediaInfo({
    this.videoCodec,
    this.resolution,
    this.videoDynamicRangeType,
    this.videoBitDepth,
    this.audioCodec,
    this.audioChannels,
    this.audioLanguages,
    this.subtitles,
    this.runTime,
  });

  factory ArrMediaInfo.fromJson(Map<String, dynamic> j) => ArrMediaInfo(
    videoCodec: j['videoCodec'] as String?,
    resolution: j['resolution'] as String?,
    videoDynamicRangeType: j['videoDynamicRangeType'] as String?,
    videoBitDepth: _intOrNull(j['videoBitDepth']),
    audioCodec: j['audioCodec'] as String?,
    audioChannels: (j['audioChannels'] as num?)?.toDouble(),
    audioLanguages: j['audioLanguages'] as String?,
    subtitles: j['subtitles'] as String?,
    runTime: j['runTime'] as String?,
  );

  /// "5.1", "7.1", "2.0": how the apps show channel counts.
  String? get channels {
    final c = audioChannels;
    if (c == null || c <= 0) return null;
    return c.toStringAsFixed(1);
  }
}

/// A movie or episode file on disk.
class ArrFile {
  final int id;
  final String? relativePath;
  final String? path;
  final int size;
  final DateTime? dateAdded;
  final String? quality;
  final String? releaseGroup;
  final List<String> languages;
  final ArrMediaInfo? mediaInfo;
  final bool qualityCutoffNotMet;
  final int? seasonNumber;

  const ArrFile({
    required this.id,
    this.relativePath,
    this.path,
    this.size = 0,
    this.dateAdded,
    this.quality,
    this.releaseGroup,
    this.languages = const [],
    this.mediaInfo,
    this.qualityCutoffNotMet = false,
    this.seasonNumber,
  });

  factory ArrFile.fromJson(Map<String, dynamic> j) => ArrFile(
    id: _int(j['id']),
    relativePath: j['relativePath'] as String?,
    path: j['path'] as String?,
    size: _int(j['size']),
    dateAdded: _date(j['dateAdded']),
    quality: _qualityName(j['quality']),
    releaseGroup: j['releaseGroup'] as String?,
    languages: [
      for (final m in _maps(j['languages']))
        if (m['name'] is String) m['name'] as String,
    ],
    mediaInfo: j['mediaInfo'] is Map
        ? ArrMediaInfo.fromJson(Map<String, dynamic>.from(j['mediaInfo']))
        : null,
    qualityCutoffNotMet: j['qualityCutoffNotMet'] == true,
    seasonNumber: _intOrNull(j['seasonNumber']),
  );
}

/// A movie in Radarr.
class ArrMovie {
  final int id;
  final String title;
  final String? sortTitle;
  final int? year;
  final String? overview;
  final int? tmdbId;
  final String? imdbId;
  final String? titleSlug;
  final bool monitored;
  final bool hasFile;
  final bool isAvailable;
  final String? status; // tba, announced, inCinemas, released, deleted
  final int sizeOnDisk;
  final int? runtime;
  final String? studio;
  final String? certification;
  final List<String> genres;
  final int? qualityProfileId;
  final String? minimumAvailability; // announced, inCinemas, released
  final String? path;
  final List<ArrImage> images;
  final DateTime? added;
  final DateTime? inCinemas;
  final DateTime? digitalRelease;
  final DateTime? physicalRelease;
  final ArrFile? movieFile;
  final double? imdbRating;
  final double? tmdbRating;
  final int? rottenTomatoes;

  const ArrMovie({
    required this.id,
    required this.title,
    this.sortTitle,
    this.year,
    this.overview,
    this.tmdbId,
    this.imdbId,
    this.titleSlug,
    this.monitored = false,
    this.hasFile = false,
    this.isAvailable = false,
    this.status,
    this.sizeOnDisk = 0,
    this.runtime,
    this.studio,
    this.certification,
    this.genres = const [],
    this.qualityProfileId,
    this.minimumAvailability,
    this.path,
    this.images = const [],
    this.added,
    this.inCinemas,
    this.digitalRelease,
    this.physicalRelease,
    this.movieFile,
    this.imdbRating,
    this.tmdbRating,
    this.rottenTomatoes,
  });

  factory ArrMovie.fromJson(Map<String, dynamic> j) {
    final ratings = (j['ratings'] as Map?) ?? const {};
    double? rating(String k) =>
        ((ratings[k] as Map?)?['value'] as num?)?.toDouble();
    final file = j['movieFile'];
    return ArrMovie(
      id: _int(j['id']),
      title: j['title'] as String? ?? '',
      sortTitle: j['sortTitle'] as String?,
      year: _intOrNull(j['year']),
      overview: j['overview'] as String?,
      tmdbId: _intOrNull(j['tmdbId']),
      imdbId: j['imdbId'] as String?,
      titleSlug: j['titleSlug'] as String?,
      monitored: j['monitored'] == true,
      hasFile: j['hasFile'] == true,
      isAvailable: j['isAvailable'] == true,
      status: j['status'] as String?,
      sizeOnDisk: _int(
        j['sizeOnDisk'] ?? (j['statistics'] as Map?)?['sizeOnDisk'],
      ),
      runtime: _intOrNull(j['runtime']),
      studio: j['studio'] as String?,
      certification: j['certification'] as String?,
      genres: _strings(j['genres']),
      qualityProfileId: _intOrNull(j['qualityProfileId']),
      minimumAvailability: j['minimumAvailability'] as String?,
      path: j['path'] as String?,
      images: _images(j['images']),
      added: _date(j['added']),
      inCinemas: _day(j['inCinemas']),
      digitalRelease: _day(j['digitalRelease']),
      physicalRelease: _day(j['physicalRelease']),
      movieFile: file is Map
          ? ArrFile.fromJson(Map<String, dynamic>.from(file))
          : null,
      imdbRating: rating('imdb'),
      tmdbRating: rating('tmdb'),
      rottenTomatoes: rating('rottenTomatoes')?.round(),
    );
  }

  /// Where the movie stands, the way Radarr's own poster colors read.
  ArrState get state {
    if (hasFile) return ArrState.downloaded;
    if (!monitored) return ArrState.unmonitored;
    if (!isAvailable) return ArrState.unreleased;
    return ArrState.missing;
  }
}

/// A title's state, for the colored bar on posters and the status chip.
enum ArrState {
  downloaded,
  missing,
  unreleased,
  unmonitored,
  continuing,
  ended,
}

class ArrSeason {
  final int seasonNumber;
  final bool monitored;
  final int episodeFileCount;
  final int episodeCount; // aired, monitored episodes
  final int totalEpisodeCount;
  final int sizeOnDisk;
  final DateTime? nextAiring;

  const ArrSeason({
    required this.seasonNumber,
    this.monitored = false,
    this.episodeFileCount = 0,
    this.episodeCount = 0,
    this.totalEpisodeCount = 0,
    this.sizeOnDisk = 0,
    this.nextAiring,
  });

  factory ArrSeason.fromJson(Map<String, dynamic> j) {
    final s = (j['statistics'] as Map?) ?? const {};
    return ArrSeason(
      seasonNumber: _int(j['seasonNumber']),
      monitored: j['monitored'] == true,
      episodeFileCount: _int(s['episodeFileCount']),
      episodeCount: _int(s['episodeCount']),
      totalEpisodeCount: _int(s['totalEpisodeCount']),
      sizeOnDisk: _int(s['sizeOnDisk']),
      nextAiring: _date(s['nextAiring']),
    );
  }
}

/// A show in Sonarr.
class ArrSeries {
  final int id;
  final String title;
  final String? sortTitle;
  final int? year;
  final String? overview;
  final int? tvdbId;
  final int? tmdbId;
  final String? imdbId;
  final String? titleSlug;
  final String? status; // continuing, ended, upcoming, deleted
  final bool ended;
  final String? network;
  final bool monitored;
  final int? qualityProfileId;
  final String? path;
  final String? seriesType; // standard, daily, anime
  final bool seasonFolder;
  final List<ArrImage> images;
  final List<ArrSeason> seasons;
  final int episodeFileCount;
  final int episodeCount;
  final int totalEpisodeCount;
  final int sizeOnDisk;
  final DateTime? nextAiring;
  final DateTime? previousAiring;
  final DateTime? added;
  final List<String> genres;
  final String? certification;
  final int? runtime;
  final double? rating;

  const ArrSeries({
    required this.id,
    required this.title,
    this.sortTitle,
    this.year,
    this.overview,
    this.tvdbId,
    this.tmdbId,
    this.imdbId,
    this.titleSlug,
    this.status,
    this.ended = false,
    this.network,
    this.monitored = false,
    this.qualityProfileId,
    this.path,
    this.seriesType,
    this.seasonFolder = true,
    this.images = const [],
    this.seasons = const [],
    this.episodeFileCount = 0,
    this.episodeCount = 0,
    this.totalEpisodeCount = 0,
    this.sizeOnDisk = 0,
    this.nextAiring,
    this.previousAiring,
    this.added,
    this.genres = const [],
    this.certification,
    this.runtime,
    this.rating,
  });

  factory ArrSeries.fromJson(Map<String, dynamic> j) {
    final s = (j['statistics'] as Map?) ?? const {};
    return ArrSeries(
      id: _int(j['id']),
      title: j['title'] as String? ?? '',
      sortTitle: j['sortTitle'] as String?,
      year: _intOrNull(j['year']),
      overview: j['overview'] as String?,
      tvdbId: _intOrNull(j['tvdbId']),
      tmdbId: _intOrNull(j['tmdbId']),
      imdbId: j['imdbId'] as String?,
      titleSlug: j['titleSlug'] as String?,
      status: j['status'] as String?,
      ended: j['ended'] == true || j['status'] == 'ended',
      network: j['network'] as String?,
      monitored: j['monitored'] == true,
      qualityProfileId: _intOrNull(j['qualityProfileId']),
      path: j['path'] as String?,
      seriesType: j['seriesType'] as String?,
      seasonFolder: j['seasonFolder'] as bool? ?? true,
      images: _images(j['images']),
      seasons: [for (final m in _maps(j['seasons'])) ArrSeason.fromJson(m)]
        ..sort((a, b) => b.seasonNumber.compareTo(a.seasonNumber)),
      episodeFileCount: _int(s['episodeFileCount']),
      episodeCount: _int(s['episodeCount']),
      totalEpisodeCount: _int(s['totalEpisodeCount']),
      sizeOnDisk: _int(s['sizeOnDisk']),
      nextAiring: _date(j['nextAiring']),
      previousAiring: _date(j['previousAiring']),
      added: _date(j['added']),
      genres: _strings(j['genres']),
      certification: j['certification'] as String?,
      runtime: _intOrNull(j['runtime']),
      rating: ((j['ratings'] as Map?)?['value'] as num?)?.toDouble(),
    );
  }

  /// Share of aired, monitored episodes that have a file (0 to 1), as on
  /// Sonarr's poster bar.
  double get progress => episodeCount == 0
      ? (episodeFileCount > 0 ? 1 : 0)
      : episodeFileCount / episodeCount;

  int get missingEpisodes =>
      (episodeCount - episodeFileCount).clamp(0, episodeCount);

  ArrState get state {
    if (!monitored) return ArrState.unmonitored;
    if (missingEpisodes > 0) return ArrState.missing;
    return ended ? ArrState.ended : ArrState.continuing;
  }
}

/// An episode of a show in Sonarr.
class ArrEpisode {
  final int id;
  final int seriesId;
  final int seasonNumber;
  final int episodeNumber;
  final String? title;
  final DateTime? airDate;
  final String? overview;
  final bool hasFile;
  final bool monitored;
  final int? episodeFileId;
  final String? finaleType;
  final ArrSeries? series;

  const ArrEpisode({
    required this.id,
    required this.seriesId,
    required this.seasonNumber,
    required this.episodeNumber,
    this.title,
    this.airDate,
    this.overview,
    this.hasFile = false,
    this.monitored = false,
    this.episodeFileId,
    this.finaleType,
    this.series,
  });

  factory ArrEpisode.fromJson(Map<String, dynamic> j) => ArrEpisode(
    id: _int(j['id']),
    seriesId: _int(j['seriesId']),
    seasonNumber: _int(j['seasonNumber']),
    episodeNumber: _int(j['episodeNumber']),
    title: j['title'] as String?,
    airDate: _date(j['airDateUtc']) ?? _date(j['airDate']),
    overview: j['overview'] as String?,
    hasFile: j['hasFile'] == true,
    monitored: j['monitored'] == true,
    episodeFileId: _intOrNull(j['episodeFileId']),
    finaleType: j['finaleType'] as String?,
    series: j['series'] is Map
        ? ArrSeries.fromJson(Map<String, dynamic>.from(j['series']))
        : null,
  );

  /// "S01E02", the way the apps write it.
  String get code =>
      'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';

  bool aired(DateTime now) => airDate != null && !airDate!.isAfter(now);
}

/// Something downloading (or stuck) in an app's queue.
class ArrQueueItem {
  final ArrKind kind;
  final int id;
  final String title; // the release name
  final String? mediaTitle; // the movie or show
  final String? episodeCode; // S01E02, shows only
  final String? episodeTitle;
  final int? movieId;
  final int? seriesId;
  final double size;
  final double sizeleft;
  final DateTime? estimatedCompletion;
  final String?
  status; // queued, paused, downloading, completed, failed, warning...
  final String? trackedDownloadStatus; // ok, warning, error
  final String?
  trackedDownloadState; // downloading, importPending, importBlocked...
  final List<String> messages;
  final String? errorMessage;
  final String? downloadClient;
  final String? indexer;
  final String? protocol; // torrent, usenet
  final String? quality;
  final List<ArrImage> images;

  const ArrQueueItem({
    required this.kind,
    required this.id,
    required this.title,
    this.mediaTitle,
    this.episodeCode,
    this.episodeTitle,
    this.movieId,
    this.seriesId,
    this.size = 0,
    this.sizeleft = 0,
    this.estimatedCompletion,
    this.status,
    this.trackedDownloadStatus,
    this.trackedDownloadState,
    this.messages = const [],
    this.errorMessage,
    this.downloadClient,
    this.indexer,
    this.protocol,
    this.quality,
    this.images = const [],
  });

  factory ArrQueueItem.fromJson(ArrKind kind, Map<String, dynamic> j) {
    final movie = j['movie'] as Map?;
    final series = j['series'] as Map?;
    final episode = j['episode'] as Map?;
    ArrEpisode? ep;
    if (episode != null) {
      ep = ArrEpisode.fromJson(Map<String, dynamic>.from(episode));
    }
    return ArrQueueItem(
      kind: kind,
      id: _int(j['id']),
      title: j['title'] as String? ?? '',
      mediaTitle: (movie?['title'] ?? series?['title']) as String?,
      episodeCode: ep?.code,
      episodeTitle: ep?.title,
      movieId: _intOrNull(j['movieId']),
      seriesId: _intOrNull(j['seriesId']),
      size: (j['size'] as num?)?.toDouble() ?? 0,
      sizeleft: (j['sizeleft'] as num?)?.toDouble() ?? 0,
      estimatedCompletion: _date(j['estimatedCompletionTime']),
      status: j['status'] as String?,
      trackedDownloadStatus: j['trackedDownloadStatus'] as String?,
      trackedDownloadState: j['trackedDownloadState'] as String?,
      messages: [
        for (final m in _maps(j['statusMessages'])) ...[
          ..._strings(m['messages']),
          if (_strings(m['messages']).isEmpty && m['title'] is String)
            m['title'] as String,
        ],
      ],
      errorMessage: j['errorMessage'] as String?,
      downloadClient: j['downloadClient'] as String?,
      indexer: j['indexer'] as String?,
      protocol: j['protocol'] as String?,
      quality: _qualityName(j['quality']),
      images: _images(movie?['images'] ?? series?['images']),
    );
  }

  /// How much is downloaded, 0 to 1.
  double get progress => size <= 0 ? 0 : ((size - sizeleft) / size).clamp(0, 1);

  /// Needs a look: the app reports a warning or error, or the download failed.
  bool get hasProblem =>
      trackedDownloadStatus == 'warning' ||
      trackedDownloadStatus == 'error' ||
      status == 'failed' ||
      status == 'warning' ||
      trackedDownloadState == 'importBlocked' ||
      trackedDownloadState == 'failedPending' ||
      (errorMessage?.isNotEmpty ?? false);
}

/// One thing on the calendar: an episode airing, or a movie release.
class ArrCalendarEntry {
  final ArrKind kind;
  final DateTime date;
  final String title; // the show or movie
  final String? episodeCode;
  final String? episodeTitle;
  final ArrRelease? release; // movies: which release this is
  final bool hasFile;
  final bool monitored;
  final bool finale;
  final int? seriesId;
  final int? movieId;
  final List<ArrImage> images;

  const ArrCalendarEntry({
    required this.kind,
    required this.date,
    required this.title,
    this.episodeCode,
    this.episodeTitle,
    this.release,
    this.hasFile = false,
    this.monitored = true,
    this.finale = false,
    this.seriesId,
    this.movieId,
    this.images = const [],
  });

  /// Sonarr's calendar: one entry per episode (asked with includeSeries).
  static ArrCalendarEntry? fromEpisode(Map<String, dynamic> j) {
    final ep = ArrEpisode.fromJson(j);
    if (ep.airDate == null) return null;
    return ArrCalendarEntry(
      kind: ArrKind.sonarr,
      date: ep.airDate!,
      title: ep.series?.title ?? '',
      episodeCode: ep.code,
      episodeTitle: ep.title,
      hasFile: ep.hasFile,
      monitored: ep.monitored,
      finale: ep.finaleType != null,
      seriesId: ep.seriesId,
      images: ep.series?.images ?? const [],
    );
  }

  /// Radarr's calendar lists a movie when any of its releases falls in the
  /// range, so one movie can give an entry for each release inside it.
  static List<ArrCalendarEntry> fromMovie(
    Map<String, dynamic> j,
    DateTime start,
    DateTime end,
  ) {
    final m = ArrMovie.fromJson(j);
    final out = <ArrCalendarEntry>[];
    void add(DateTime? d, ArrRelease r) {
      if (d == null || d.isBefore(start) || !d.isBefore(end)) return;
      out.add(
        ArrCalendarEntry(
          kind: ArrKind.radarr,
          date: d,
          title: m.title,
          release: r,
          hasFile: m.hasFile,
          monitored: m.monitored,
          movieId: m.id,
          images: m.images,
        ),
      );
    }

    add(m.inCinemas, ArrRelease.cinemas);
    add(m.digitalRelease, ArrRelease.digital);
    add(m.physicalRelease, ArrRelease.physical);
    return out;
  }
}

enum ArrRelease { cinemas, digital, physical }

/// One event in a title's history: grabbed, imported, failed, deleted...
/// From the History tab it also carries the title it belongs to.
class ArrHistoryItem {
  final ArrKind? kind;
  final int id;
  final DateTime? date;
  final String eventType;
  final String? sourceTitle;
  final String? quality;
  final int? episodeId;
  final int? seriesId;
  final int? movieId;
  final String? title; // the show or movie, when the app sent it along
  final String? episodeCode;
  final String? episodeTitle;
  final List<ArrImage> images;
  final Map<String, dynamic> data;

  const ArrHistoryItem({
    required this.id,
    required this.eventType,
    this.kind,
    this.date,
    this.sourceTitle,
    this.quality,
    this.episodeId,
    this.seriesId,
    this.movieId,
    this.title,
    this.episodeCode,
    this.episodeTitle,
    this.images = const [],
    this.data = const {},
  });

  factory ArrHistoryItem.fromJson(Map<String, dynamic> j, [ArrKind? kind]) {
    final series = j['series'] is Map
        ? ArrSeries.fromJson(Map<String, dynamic>.from(j['series']))
        : null;
    final movie = j['movie'] is Map
        ? ArrMovie.fromJson(Map<String, dynamic>.from(j['movie']))
        : null;
    final episode = j['episode'] is Map
        ? ArrEpisode.fromJson(Map<String, dynamic>.from(j['episode']))
        : null;
    return ArrHistoryItem(
      kind: kind,
      id: _int(j['id']),
      date: _date(j['date']),
      eventType: j['eventType'] as String? ?? 'unknown',
      sourceTitle: j['sourceTitle'] as String?,
      quality: _qualityName(j['quality']),
      episodeId: _intOrNull(j['episodeId']),
      seriesId: _intOrNull(j['seriesId']),
      movieId: _intOrNull(j['movieId']),
      title: series?.title ?? movie?.title,
      episodeCode: episode?.code,
      episodeTitle: episode?.title,
      images: series?.images ?? movie?.images ?? const [],
      data: j['data'] is Map ? Map<String, dynamic>.from(j['data']) : const {},
    );
  }

  /// The download client, indexer or reason the app recorded, if any.
  String? get detail =>
      (data['reason'] ??
              data['message'] ??
              data['indexer'] ??
              data['downloadClient'])
          as String?;

  /// A grab can be marked failed: the app blocklists the release and looks
  /// for another.
  bool get canMarkFailed => eventType == 'grabbed';
}

/// A monitored episode or movie from Wanted: missing, or below the quality
/// profile's cutoff.
class ArrWantedItem {
  final ArrKind kind;
  final String title; // the show or movie
  final String? episodeCode;
  final String? episodeTitle;
  final DateTime? date; // air date, or the movie's release
  final int? year;
  final int? seriesId;
  final int? movieId;
  final int? episodeId;
  final String? quality; // what's there now (cutoff unmet)
  final bool available; // out, so a search can find it
  final List<ArrImage> images;

  const ArrWantedItem({
    required this.kind,
    required this.title,
    this.episodeCode,
    this.episodeTitle,
    this.date,
    this.year,
    this.seriesId,
    this.movieId,
    this.episodeId,
    this.quality,
    this.available = true,
    this.images = const [],
  });

  /// Sonarr's Wanted lists episodes (asked with includeSeries, and with
  /// includeEpisodeFile for cutoff unmet).
  factory ArrWantedItem.fromEpisode(Map<String, dynamic> j) {
    final e = ArrEpisode.fromJson(j);
    final file = j['episodeFile'];
    return ArrWantedItem(
      kind: ArrKind.sonarr,
      title: e.series?.title ?? '',
      episodeCode: e.code,
      episodeTitle: e.title,
      date: e.airDate,
      seriesId: e.seriesId,
      episodeId: e.id,
      quality: file is Map ? _qualityName(file['quality']) : null,
      images: e.series?.images ?? const [],
    );
  }

  /// Radarr's Wanted lists movies.
  factory ArrWantedItem.fromMovie(Map<String, dynamic> j) {
    final m = ArrMovie.fromJson(j);
    return ArrWantedItem(
      kind: ArrKind.radarr,
      title: m.title,
      date: m.digitalRelease ?? m.physicalRelease ?? m.inCinemas,
      year: m.year,
      movieId: m.id,
      quality: m.movieFile?.quality,
      // Radarr lists monitored movies that aren't out yet too.
      available: m.isAvailable,
      images: m.images,
    );
  }
}

/// One page of a list the app pages through, and how many there are in all.
class ArrPage<T> {
  final List<T> items;
  final int total;
  const ArrPage(this.items, this.total);
}

/// Something the app's own health check found: an indexer down, a disk
/// filling up, an update waiting...
class ArrHealth {
  final ArrKind kind;
  final String source;
  final String type; // ok, notice, warning, error
  final String message;
  final String? wikiUrl;

  const ArrHealth({
    required this.kind,
    required this.source,
    required this.type,
    required this.message,
    this.wikiUrl,
  });

  factory ArrHealth.fromJson(ArrKind kind, Map<String, dynamic> j) {
    final wiki = j['wikiUrl'];
    return ArrHealth(
      kind: kind,
      source: j['source'] as String? ?? '',
      type: j['type'] as String? ?? 'notice',
      message: j['message'] as String? ?? '',
      // Older versions send a Uri object rather than a string.
      wikiUrl: wiki is String
          ? wiki
          : wiki is Map
          ? wiki['fullUri'] as String?
          : null,
    );
  }

  bool get isProblem => type == 'warning' || type == 'error';
}

class ArrQualityProfile {
  final int id;
  final String name;
  const ArrQualityProfile({required this.id, required this.name});

  factory ArrQualityProfile.fromJson(Map<String, dynamic> j) =>
      ArrQualityProfile(id: _int(j['id']), name: j['name'] as String? ?? '');
}

/// What /system/status says the server is.
class ArrStatus {
  final String appName;
  final String version;
  const ArrStatus({required this.appName, required this.version});

  factory ArrStatus.fromJson(Map<String, dynamic> j) => ArrStatus(
    appName: j['appName'] as String? ?? j['instanceName'] as String? ?? '',
    version: j['version'] as String? ?? '',
  );
}

/// A folder where the app puts new titles.
class ArrRootFolder {
  final int id;
  final String path;
  final int? freeSpace;
  final bool accessible;

  /// Folders inside this one that the app doesn't manage yet: titles already
  /// on disk, such as ones Jellyfin plays that were never added.
  final List<ArrFolder> unmappedFolders;
  const ArrRootFolder({
    required this.id,
    required this.path,
    this.freeSpace,
    this.accessible = true,
    this.unmappedFolders = const [],
  });

  factory ArrRootFolder.fromJson(Map<String, dynamic> j) => ArrRootFolder(
    id: _int(j['id']),
    path: j['path'] as String? ?? '',
    freeSpace: _intOrNull(j['freeSpace']),
    accessible: j['accessible'] as bool? ?? true,
    unmappedFolders: [
      for (final m in _maps(j['unmappedFolders']))
        if ((m['path'] as String?)?.isNotEmpty ?? false)
          ArrFolder(
            name: m['name'] as String? ?? '',
            path: m['path'] as String,
          ),
    ],
  );
}

/// A folder on the app's disk.
class ArrFolder {
  final String name;
  final String path;
  const ArrFolder({required this.name, required this.path});
}

/// Lowercase letters and digits only, so "The Matrix 1999 [1080p]" and
/// "the.matrix.(1999)" compare alike.
String _folderKey(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// A folder on disk that seems to hold a title, and how sure that is.
class ArrFolderMatch {
  final ArrFolder folder;

  /// The folder's name has the title and its year, or is the exact folder
  /// Jellyfin plays the title from. When false the name is the title alone
  /// while the title has a year, which can be a remake (a "Dune" folder that
  /// holds the 1984 film when adding the 2021 one), so Add asks first.
  final bool sure;
  const ArrFolderMatch(this.folder, {required this.sure});
}

/// The unmanaged folder that already holds [title], if one does.
///
/// A folder counts when its name is the title, or the title then its year,
/// whatever the punctuation: "The Matrix (1999)", "The.Matrix.1999.1080p",
/// "Breaking Bad". Anything else after the title is another title, so "Dune"
/// never takes "Dune Part Two". [hint] is the folder's own name when Jellyfin
/// knows it; it only chooses among folders that already match the title, so a
/// collection folder ("Kids") or a stale hint never points at a wrong one.
/// Several candidates left, or none, means no match: Add never guesses.
ArrFolderMatch? arrExistingFolder(
  List<ArrRootFolder> roots, {
  required String title,
  int? year,
  String? hint,
}) {
  final t = _folderKey(title);
  if (t.isEmpty) return null;
  final y = (year ?? 0) > 0 ? '$year' : '';
  final found = [
    for (final r in roots)
      for (final f in r.unmappedFolders)
        if (_folderKey(f.name).startsWith(t))
          if (_folderKey(f.name).substring(t.length) case final rest
              when rest.isEmpty || (y.isNotEmpty && rest.startsWith(y)))
            (folder: f, withYear: rest.isNotEmpty),
  ];
  if (hint != null && hint.isNotEmpty) {
    final h = hint.toLowerCase();
    final exact = found.where((c) => c.folder.name.toLowerCase() == h);
    if (exact.length == 1) {
      return ArrFolderMatch(exact.first.folder, sure: true);
    }
  }
  if (found.length != 1) return null;
  final c = found.single;
  return ArrFolderMatch(c.folder, sure: c.withYear || y.isEmpty);
}

/// The folder a Jellyfin item lives in, by name, to find it on the Sonarr or
/// Radarr side where the same disk may be mounted somewhere else. A movie's
/// path is its file, so its folder is the parent; a show's path is its folder.
String? arrFolderNameOf(String? path, {required bool isFile}) {
  if (path == null || path.isEmpty) return null;
  final parts = path
      .split(RegExp(r'[\\/]'))
      .where((p) => p.isNotEmpty)
      .toList();
  // A disc rip (BDMV, VIDEO_TS) is a folder itself, with no extension.
  final video = RegExp(
    r'\.(mkv|mp4|m4v|avi|mov|wmv|ts|m2ts|mts|iso|img|webm|mpg|mpeg|vob|divx|flv|ogv|3gp|strm)$',
    caseSensitive: false,
  );
  if (isFile && video.hasMatch(parts.lastOrNull ?? '')) {
    if (parts.length < 2) return null;
    parts.removeLast();
  }
  return parts.isEmpty ? null : parts.last;
}

/// What Add starts with for a new title. Every field is optional: one that's
/// missing, or no longer exists on the server, falls back to what most of the
/// library uses.
class ArrAddDefaults {
  final String? rootFolder;
  final int? qualityProfileId;
  final String? monitor;
  final String? minimumAvailability; // Radarr
  final String? seriesType; // Sonarr
  final bool? seasonFolder; // Sonarr
  final bool? search;

  const ArrAddDefaults({
    this.rootFolder,
    this.qualityProfileId,
    this.monitor,
    this.minimumAvailability,
    this.seriesType,
    this.seasonFolder,
    this.search,
  });

  bool get isEmpty =>
      rootFolder == null &&
      qualityProfileId == null &&
      monitor == null &&
      minimumAvailability == null &&
      seriesType == null &&
      seasonFolder == null &&
      search == null;

  factory ArrAddDefaults.fromJson(Map<String, dynamic> j) => ArrAddDefaults(
    rootFolder: j['rootFolder'] as String?,
    qualityProfileId: _intOrNull(j['qualityProfileId']),
    monitor: j['monitor'] as String?,
    minimumAvailability: j['minimumAvailability'] as String?,
    seriesType: j['seriesType'] as String?,
    seasonFolder: j['seasonFolder'] as bool?,
    search: j['search'] as bool?,
  );

  @override
  bool operator ==(Object other) =>
      other is ArrAddDefaults &&
      other.rootFolder == rootFolder &&
      other.qualityProfileId == qualityProfileId &&
      other.monitor == monitor &&
      other.minimumAvailability == minimumAvailability &&
      other.seriesType == seriesType &&
      other.seasonFolder == seasonFolder &&
      other.search == search;

  @override
  int get hashCode => Object.hash(
    rootFolder,
    qualityProfileId,
    monitor,
    minimumAvailability,
    seriesType,
    seasonFolder,
    search,
  );

  Map<String, dynamic> toJson() => {
    if (rootFolder != null) 'rootFolder': rootFolder,
    if (qualityProfileId != null) 'qualityProfileId': qualityProfileId,
    if (monitor != null) 'monitor': monitor,
    if (minimumAvailability != null) 'minimumAvailability': minimumAvailability,
    if (seriesType != null) 'seriesType': seriesType,
    if (seasonFolder != null) 'seasonFolder': seasonFolder,
    if (search != null) 'search': search,
  };
}

/// One title the app already manages, reduced to the choices it was added
/// with, for working out what the library usually uses.
typedef ArrAddedWith = ({
  String? path,
  int? qualityProfileId,
  String? minimumAvailability,
  String? seriesType,
  bool? seasonFolder,
});

/// Where a starting choice came from.
enum ArrChoiceSource { saved, library, first }

/// The choices Add opens with.
class ArrAddChoice {
  final String? rootFolder;
  final int? qualityProfileId;
  final String monitor;
  final String minimumAvailability;
  final String seriesType;
  final bool seasonFolder;
  final bool search;

  /// Where the quality profile came from, which is the choice people most
  /// want explained.
  final ArrChoiceSource profileSource;

  const ArrAddChoice({
    required this.rootFolder,
    required this.qualityProfileId,
    required this.monitor,
    required this.minimumAvailability,
    required this.seriesType,
    required this.seasonFolder,
    required this.search,
    required this.profileSource,
  });
}

/// The most common non-null value, or null. Ties go to the one seen first.
T? _mostCommon<T>(Iterable<T?> values) {
  final counts = <T, int>{};
  for (final v in values) {
    if (v != null) counts[v] = (counts[v] ?? 0) + 1;
  }
  T? best;
  var top = 0;
  counts.forEach((v, n) {
    if (n > top) {
      best = v;
      top = n;
    }
  });
  return best;
}

/// The root folder a title's path sits in: the longest root that's a prefix,
/// so `/media/movies-4k` doesn't count as inside `/media/movies`.
String? arrRootOf(String? path, Iterable<String> roots) {
  if (path == null) return null;
  String norm(String p) => p.endsWith('/') || p.endsWith('\\') ? p : '$p/';
  final p = norm(path);
  String? best;
  for (final r in roots) {
    if (p.startsWith(norm(r)) && (best == null || r.length > best.length)) {
      best = r;
    }
  }
  return best;
}

/// What Add starts with: [saved] where it still fits the server, then what
/// most of [library] uses, then the app's first root folder and profile.
ArrAddChoice arrStartingChoice({
  required ArrKind kind,
  required ArrAddDefaults saved,
  required List<String> roots,
  required List<int> profiles,
  required List<ArrAddedWith> library,
}) {
  final shows = kind == ArrKind.sonarr;
  final root =
      (saved.rootFolder != null && roots.contains(saved.rootFolder)
          ? saved.rootFolder
          : null) ??
      _mostCommon(library.map((t) => arrRootOf(t.path, roots))) ??
      (roots.isEmpty ? null : roots.first);
  final savedProfile =
      saved.qualityProfileId != null &&
          profiles.contains(saved.qualityProfileId)
      ? saved.qualityProfileId
      : null;
  final libraryProfile = _mostCommon(
    library.map(
      (t) => profiles.contains(t.qualityProfileId) ? t.qualityProfileId : null,
    ),
  );
  final profile =
      savedProfile ??
      libraryProfile ??
      (profiles.isEmpty ? null : profiles.first);
  return ArrAddChoice(
    rootFolder: root,
    qualityProfileId: profile,
    monitor: saved.monitor ?? (shows ? 'all' : 'movieOnly'),
    minimumAvailability:
        saved.minimumAvailability ??
        _mostCommon(library.map((t) => t.minimumAvailability)) ??
        'released',
    seriesType:
        saved.seriesType ??
        _mostCommon(library.map((t) => t.seriesType)) ??
        'standard',
    seasonFolder:
        saved.seasonFolder ??
        _mostCommon(library.map((t) => t.seasonFolder)) ??
        true,
    search: saved.search ?? true,
    profileSource: savedProfile != null
        ? ArrChoiceSource.saved
        : libraryProfile != null
        ? ArrChoiceSource.library
        : ArrChoiceSource.first,
  );
}

/// A title from a lookup, with the raw entry the app wants back to add it.
/// [item]'s id is 0 unless the app already has it.
class ArrLookup<T> {
  final T item;
  final Map<String, dynamic> raw;
  const ArrLookup(this.item, this.raw);

  int get existingId => _int(raw['id']);
  bool get inLibrary => existingId > 0;
}

/// A release an indexer offers, from an interactive search, with the app's
/// verdict on it.
class ArrSearchResult {
  final String guid;
  final int indexerId;
  final String title;
  final String? indexer;
  final String? quality;
  final int qualityWeight;
  final int size;
  final double? ageHours;
  final String protocol; // torrent, usenet
  final int? seeders;
  final int? leechers;
  final int customFormatScore;
  final List<String> customFormats;
  final List<String> languages;
  final bool rejected;
  final List<String> rejections;
  final bool downloadAllowed;
  final String? releaseGroup;
  final String? infoUrl;
  final bool fullSeason;

  const ArrSearchResult({
    required this.guid,
    required this.indexerId,
    required this.title,
    this.indexer,
    this.quality,
    this.qualityWeight = 0,
    this.size = 0,
    this.ageHours,
    this.protocol = 'unknown',
    this.seeders,
    this.leechers,
    this.customFormatScore = 0,
    this.customFormats = const [],
    this.languages = const [],
    this.rejected = false,
    this.rejections = const [],
    this.downloadAllowed = true,
    this.releaseGroup,
    this.infoUrl,
    this.fullSeason = false,
  });

  factory ArrSearchResult.fromJson(Map<String, dynamic> j) => ArrSearchResult(
    guid: j['guid'] as String? ?? '',
    indexerId: _int(j['indexerId']),
    title: j['title'] as String? ?? '',
    indexer: j['indexer'] as String?,
    quality: _qualityName(j['quality']),
    qualityWeight: _int(j['qualityWeight']),
    size: _int(j['size']),
    ageHours:
        (j['ageHours'] as num?)?.toDouble() ??
        (j['age'] == null ? null : (j['age'] as num).toDouble() * 24),
    protocol: j['protocol'] as String? ?? 'unknown',
    seeders: _intOrNull(j['seeders']),
    leechers: _intOrNull(j['leechers']),
    customFormatScore: _int(j['customFormatScore']),
    customFormats: [
      for (final m in _maps(j['customFormats']))
        if (m['name'] is String) m['name'] as String,
    ],
    languages: [
      for (final m in _maps(j['languages']))
        if (m['name'] is String) m['name'] as String,
    ],
    rejected: j['rejected'] as bool? ?? false,
    rejections: [
      for (final r in (j['rejections'] as List?) ?? const [])
        if (r is String)
          r
        else if (r is Map && r['reason'] is String)
          r['reason'] as String,
    ],
    downloadAllowed: j['downloadAllowed'] as bool? ?? true,
    releaseGroup: j['releaseGroup'] as String?,
    infoUrl: j['infoUrl'] as String?,
    fullSeason: j['fullSeason'] as bool? ?? false,
  );

  bool get isTorrent => protocol == 'torrent';
}

/// A file a rename would change.
class ArrRename {
  final int fileId;
  final String existingPath;
  final String newPath;
  const ArrRename({
    required this.fileId,
    required this.existingPath,
    required this.newPath,
  });

  factory ArrRename.fromJson(Map<String, dynamic> j) => ArrRename(
    fileId: _int(j['episodeFileId'] ?? j['movieFileId']),
    existingPath: j['existingPath'] as String? ?? '',
    newPath: j['newPath'] as String? ?? '',
  );
}
