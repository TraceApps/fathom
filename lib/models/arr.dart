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
class ArrHistoryItem {
  final int id;
  final DateTime? date;
  final String eventType;
  final String? sourceTitle;
  final String? quality;
  final int? episodeId;
  final Map<String, dynamic> data;

  const ArrHistoryItem({
    required this.id,
    required this.eventType,
    this.date,
    this.sourceTitle,
    this.quality,
    this.episodeId,
    this.data = const {},
  });

  factory ArrHistoryItem.fromJson(Map<String, dynamic> j) => ArrHistoryItem(
    id: _int(j['id']),
    date: _date(j['date']),
    eventType: j['eventType'] as String? ?? 'unknown',
    sourceTitle: j['sourceTitle'] as String?,
    quality: _qualityName(j['quality']),
    episodeId: _intOrNull(j['episodeId']),
    data: j['data'] is Map ? Map<String, dynamic>.from(j['data']) : const {},
  );

  /// The download client, indexer or reason the app recorded, if any.
  String? get detail =>
      (data['reason'] ??
              data['message'] ??
              data['indexer'] ??
              data['downloadClient'])
          as String?;
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
