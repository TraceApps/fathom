/// Per-user playback state attached to an item.
class UserItemData {
  final double playedPercentage;
  final int playbackPositionTicks;
  final bool played;
  final bool isFavorite;
  final int unplayedItemCount; // unwatched children (series/season)

  /// When this was last played, as the server recorded it. Continue Watching
  /// comes back in an order that buries the thing you're actually watching, and
  /// its endpoint takes no sort parameters, so the row is sorted on this.
  final DateTime? lastPlayedDate;

  const UserItemData({
    this.playedPercentage = 0,
    this.playbackPositionTicks = 0,
    this.played = false,
    this.isFavorite = false,
    this.unplayedItemCount = 0,
    this.lastPlayedDate,
  });

  factory UserItemData.fromJson(Map<String, dynamic> json) => UserItemData(
        playedPercentage: (json['PlayedPercentage'] as num?)?.toDouble() ?? 0,
        playbackPositionTicks:
            (json['PlaybackPositionTicks'] as num?)?.toInt() ?? 0,
        played: json['Played'] as bool? ?? false,
        isFavorite: json['IsFavorite'] as bool? ?? false,
        unplayedItemCount: (json['UnplayedItemCount'] as num?)?.toInt() ?? 0,
        lastPlayedDate: DateTime.tryParse(
            (json['LastPlayedDate'] as String?) ?? ''),
      );
}

/// A chapter marker within a video.
class Chapter {
  final int startTicks;
  final String? name;
  final String? imageTag;

  const Chapter({required this.startTicks, this.name, this.imageTag});

  Duration get start => Duration(microseconds: startTicks ~/ 10);

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        startTicks: (json['StartPositionTicks'] as num?)?.toInt() ?? 0,
        name: json['Name'] as String?,
        imageTag: json['ImageTag'] as String?,
      );
}

/// Trickplay (scrub-preview) tile geometry for one resolution of one item.
/// The server bakes evenly spaced thumbnails into sprite sheets; each sheet
/// holds [tileWidth] x [tileHeight] thumbs of [width] x [height] pixels.
class TrickplayInfo {
  final int width;
  final int height;
  final int tileWidth;
  final int tileHeight;
  final int thumbnailCount;
  final int interval; // ms between thumbnails

  const TrickplayInfo({
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.thumbnailCount,
    required this.interval,
  });

  int get perTile => tileWidth * tileHeight;

  factory TrickplayInfo.fromJson(Map<String, dynamic> json) => TrickplayInfo(
        width: (json['Width'] as num?)?.toInt() ?? 0,
        height: (json['Height'] as num?)?.toInt() ?? 0,
        tileWidth: (json['TileWidth'] as num?)?.toInt() ?? 1,
        tileHeight: (json['TileHeight'] as num?)?.toInt() ?? 1,
        thumbnailCount: (json['ThumbnailCount'] as num?)?.toInt() ?? 0,
        interval: (json['Interval'] as num?)?.toInt() ?? 10000,
      );
}

/// A cast or crew member.
class Person {
  final String id;
  final String name;
  final String? role;
  final String? type; // Actor, Director, Writer, ...
  final String? primaryImageTag;

  const Person({
    required this.id,
    required this.name,
    this.role,
    this.type,
    this.primaryImageTag,
  });

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['Id'] as String? ?? '',
        name: json['Name'] as String? ?? '',
        role: json['Role'] as String?,
        type: json['Type'] as String?,
        primaryImageTag: json['PrimaryImageTag'] as String?,
      );
}

/// A lean projection of Jellyfin's BaseItemDto covering the fields the client
/// currently uses. Grows as new screens need more.
class BaseItemDto {
  final String id;
  final String name;
  final String? type; // Movie, Series, Episode, BoxSet, MusicAlbum, ...
  final String? collectionType; // movies, tvshows, music, livetv, ... (views)
  final String? primaryImageTag;
  final List<String> backdropImageTags;
  final String? seriesName;
  final String? seriesId;
  final int? productionYear;
  final int? indexNumber; // episode number
  final int? parentIndexNumber; // season number
  final int? runTimeTicks;
  final String? overview;
  final List<String> genres;
  final String? mediaType; // Video, Audio
  /// Jellyfin's ExtraType on a bonus item: Trailer, BehindTheScenes,
  /// DeletedScene, Interview, Scene, Sample, Clip, Featurette, Short,
  /// ThemeSong, ThemeVideo. Null on ordinary library items.
  final String? extraType;

  /// The subtitle tracks the server knows about, including any that live in
  /// their own file beside the video. Empty unless the item was fetched with
  /// its media streams (the player does that before it starts).
  final List<SubtitleStream> subtitleStreams;

  /// The audio tracks the server knows about, in file order.
  final List<AudioStream> audioStreams;

  /// The item's media source, needed to fetch a subtitle that lives in its own
  /// file. Usually the same as the item's own id, but not always.
  final String? mediaSourceId;

  /// The original file's extension (`mkv`, `mp4`, `flac`), so a download can be
  /// saved under a name other apps recognise. Null when the server gives no
  /// clue. See [mediaFileExtension].
  final String? fileExtension;
  /// When the item arrived in the library. For a weekly show this is the day
  /// after each episode airs, which is how Continue Watching spots a new one.
  final DateTime? dateCreated;
  final bool isFolder;
  final String? officialRating;
  final double? communityRating; // IMDb-style, 0-10
  final double? criticRating; // Rotten Tomatoes critic score, 0-100
  final List<String> remoteTrailers; // trailer URLs (usually YouTube)
  final String? album;
  final String? albumId;
  final String? albumPrimaryImageTag;
  final String? albumArtist;
  final List<String> artists;
  final List<Person> artistItems; // artists with ids, for navigation
  final String? channelNumber;
  final String? channelId;
  final BaseItemDto? currentProgram;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? timerId; // set on a program that has a scheduled recording
  final String? seriesTimerId; // set when that recording is part of a series
  final List<Person> people;
  final List<Chapter> chapters;
  final UserItemData userData;
  final int? childCount; // e.g. number of items in a playlist / folder
  final String? playlistItemId; // per-entry id when listing playlist contents
  final String? logoImageTag; // the item's own Logo image (movies, series)
  final String? parentLogoImageTag; // series logo, present on episodes
  final String? episodeTitle; // Live TV program's episode/subtitle
  final String? seriesPrimaryImageTag; // series poster, present on episodes
  final TrickplayInfo? trickplayInfo; // best-resolution scrub-preview geometry
  final int? trickplayWidth; // resolution key for the trickplay tile URL
  final String? tmdbId; // TMDB id from ProviderIds, for external ratings
  final String? tvdbId; // TVDB id from ProviderIds, for finding a show in Sonarr
  final String? path; // where the server keeps it: a file, or a show's folder

  const BaseItemDto({
    required this.id,
    required this.name,
    this.type,
    this.collectionType,
    this.primaryImageTag,
    this.backdropImageTags = const [],
    this.seriesName,
    this.seriesId,
    this.productionYear,
    this.indexNumber,
    this.parentIndexNumber,
    this.runTimeTicks,
    this.overview,
    this.genres = const [],
    this.mediaType,
    this.extraType,
    this.subtitleStreams = const [],
    this.audioStreams = const [],
    this.mediaSourceId,
    this.fileExtension,
    this.dateCreated,
    this.isFolder = false,
    this.officialRating,
    this.communityRating,
    this.criticRating,
    this.remoteTrailers = const [],
    this.album,
    this.albumId,
    this.albumPrimaryImageTag,
    this.albumArtist,
    this.artists = const [],
    this.artistItems = const [],
    this.channelNumber,
    this.channelId,
    this.currentProgram,
    this.startDate,
    this.endDate,
    this.timerId,
    this.seriesTimerId,
    this.people = const [],
    this.chapters = const [],
    this.userData = const UserItemData(),
    this.childCount,
    this.playlistItemId,
    this.logoImageTag,
    this.parentLogoImageTag,
    this.episodeTitle,
    this.seriesPrimaryImageTag,
    this.trickplayInfo,
    this.trickplayWidth,
    this.tmdbId,
    this.tvdbId,
    this.path,
  });

  /// Seerr media type for external ratings lookups: 'movie' or 'tv'.
  String? get seerrMediaType {
    if (isSeries || isEpisode) return 'tv';
    if (type == 'Movie') return 'movie';
    return null;
  }

  /// The first trailer URL (usually a YouTube link), if any.
  String? get trailerUrl => remoteTrailers.isNotEmpty ? remoteTrailers.first : null;

  bool get isEpisode => type == 'Episode';
  bool get isSeries => type == 'Series';
  bool get isAlbum => type == 'MusicAlbum';
  bool get isLiveChannel => type == 'TvChannel';
  bool get isAudio => mediaType == 'Audio' || type == 'Audio';

  /// A display artist line ("Artist A, Artist B" or the album artist).
  String? get artistLine {
    if (artists.isNotEmpty) return artists.join(', ');
    return albumArtist;
  }

  int get resumePositionTicks => userData.playbackPositionTicks;
  bool get canResume => resumePositionTicks > 0;

  /// How far through the item playback is, 0..1, or null when there's no saved
  /// position or the runtime is unknown. Drives the resume sliver on cards.
  double? get progressFraction {
    // No bar on finished items, matching Jellyfin web (a played item can still
    // carry a stale resume position).
    if (userData.played) return null;
    final rt = runTimeTicks;
    if (rt == null || rt <= 0 || resumePositionTicks <= 0) return null;
    return (resumePositionTicks / rt).clamp(0.0, 1.0);
  }

  // Title-logo art (a transparent PNG of the title's logo). For episodes the
  // logo lives on the parent series.
  String? get logoTag => logoImageTag ?? parentLogoImageTag;
  String? get logoItemId {
    if (logoImageTag != null) return id;
    if (parentLogoImageTag != null && seriesId != null) return seriesId;
    return null;
  }

  bool get hasLogo => logoTag != null && logoItemId != null;

  /// Runtime in whole minutes, or null when unknown.
  int? get runtimeMinutes =>
      runTimeTicks == null ? null : (runTimeTicks! / 600000000).round();

  /// Fraction (0..1) watched, for progress indicators.
  double get progress {
    if (userData.playedPercentage > 0) {
      return (userData.playedPercentage / 100).clamp(0, 1);
    }
    if (runTimeTicks != null && runTimeTicks! > 0) {
      return (userData.playbackPositionTicks / runTimeTicks!).clamp(0, 1);
    }
    return 0;
  }

  factory BaseItemDto.fromJson(Map<String, dynamic> json) {
    final imageTags =
        (json['ImageTags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final trickplay = _parseTrickplay(json['Trickplay']);
    return BaseItemDto(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? '',
      type: json['Type'] as String?,
      collectionType: json['CollectionType'] as String?,
      primaryImageTag: imageTags['Primary'] as String?,
      backdropImageTags:
          (json['BackdropImageTags'] as List?)?.cast<String>() ?? const [],
      seriesName: json['SeriesName'] as String?,
      seriesId: json['SeriesId'] as String?,
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      overview: json['Overview'] as String?,
      genres: (json['Genres'] as List?)?.cast<String>() ?? const [],
      mediaType: json['MediaType'] as String?,
      extraType: json['ExtraType'] as String?,
      subtitleStreams: parseSubtitleStreams(json),
      audioStreams: parseAudioStreams(json),
      mediaSourceId: firstMediaSourceId(json),
      fileExtension: mediaFileExtension(json),
      dateCreated: DateTime.tryParse((json['DateCreated'] as String?) ?? ''),
      isFolder: json['IsFolder'] as bool? ?? false,
      officialRating: json['OfficialRating'] as String?,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      criticRating: (json['CriticRating'] as num?)?.toDouble(),
      remoteTrailers: (json['RemoteTrailers'] as List?)
              ?.whereType<Map>()
              .map((e) => e['Url'] as String?)
              .whereType<String>()
              .toList() ??
          const [],
      album: json['Album'] as String?,
      albumId: json['AlbumId'] as String?,
      albumPrimaryImageTag: json['AlbumPrimaryImageTag'] as String?,
      albumArtist: json['AlbumArtist'] as String?,
      artists: (json['Artists'] as List?)?.cast<String>() ?? const [],
      artistItems: (json['ArtistItems'] as List?)
              ?.whereType<Map>()
              .map((e) => Person.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      channelNumber: json['ChannelNumber'] as String?,
      channelId: json['ChannelId'] as String?,
      currentProgram: json['CurrentProgram'] is Map
          ? BaseItemDto.fromJson(
              Map<String, dynamic>.from(json['CurrentProgram'] as Map))
          : null,
      // Server sends UTC; keep these as local so every consumer formats the
      // viewer's local time (the guide, program details, recordings).
      startDate: DateTime.tryParse(json['StartDate'] as String? ?? '')?.toLocal(),
      endDate: DateTime.tryParse(json['EndDate'] as String? ?? '')?.toLocal(),
      timerId: json['TimerId'] as String?,
      seriesTimerId: json['SeriesTimerId'] as String?,
      people: (json['People'] as List?)
              ?.whereType<Map>()
              .map((e) => Person.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      chapters: (json['Chapters'] as List?)
              ?.whereType<Map>()
              .map((e) => Chapter.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      userData: UserItemData.fromJson(
          (json['UserData'] as Map?)?.cast<String, dynamic>() ?? const {}),
      childCount: (json['ChildCount'] as num?)?.toInt(),
      playlistItemId: json['PlaylistItemId'] as String?,
      logoImageTag: imageTags['Logo'] as String?,
      parentLogoImageTag: json['ParentLogoImageTag'] as String?,
      episodeTitle: json['EpisodeTitle'] as String?,
      seriesPrimaryImageTag: json['SeriesPrimaryImageTag'] as String?,
      trickplayInfo: trickplay?.$1,
      trickplayWidth: trickplay?.$2,
      tmdbId: (json['ProviderIds'] as Map?)?['Tmdb']?.toString(),
      tvdbId: (json['ProviderIds'] as Map?)?['Tvdb']?.toString(),
      path: json['Path'] as String?,
    );
  }

  /// Picks the highest-resolution trickplay tile set from the server's nested
  /// `Trickplay` map ({mediaSourceId: {widthKey: info}}), returning its geometry
  /// and the width key needed to build tile URLs.
  static (TrickplayInfo, int)? _parseTrickplay(dynamic raw) {
    if (raw is! Map || raw.isEmpty) return null;
    // Merge all media sources; the width keys are what matter for the URL.
    final byWidth = <int, Map<String, dynamic>>{};
    for (final source in raw.values) {
      if (source is! Map) continue;
      source.forEach((k, v) {
        final w = int.tryParse('$k');
        if (w != null && v is Map) {
          byWidth[w] = Map<String, dynamic>.from(v);
        }
      });
    }
    if (byWidth.isEmpty) return null;
    final width = byWidth.keys.reduce((a, b) => a > b ? a : b);
    return (TrickplayInfo.fromJson(byWidth[width]!), width);
  }
}

/// One subtitle track as the server describes it.
///
/// Jellyfin reports both the tracks inside the video file and any that sit
/// beside it in their own file (a .srt next to the video, or one a subtitle
/// plugin downloaded). Only the external ones need Fathom to do anything: the
/// player never sees them, because they aren't in the stream it opens.
class SubtitleStream {
  const SubtitleStream({
    required this.index,
    required this.isExternal,
    required this.isTextSubtitleStream,
    this.codec,
    this.displayTitle,
    this.language,
    this.title,
    this.deliveryUrl,
    this.isForced = false,
    this.isDefault = false,
  });

  final int index;
  final bool isExternal;

  /// False for the picture-based formats (Blu-ray PGS, DVD VobSub, DVB), which
  /// are images rather than text and so can only be drawn by the player.
  final bool isTextSubtitleStream;
  final String? codec;
  final String? displayTitle;
  final String? language;
  final String? title;

  /// Where to fetch an external track, relative to the server.
  final String? deliveryUrl;
  final bool isForced;
  final bool isDefault;

  /// What to call it in the track picker.
  String get label {
    final name = (displayTitle?.trim().isNotEmpty ?? false)
        ? displayTitle!.trim()
        : (title?.trim().isNotEmpty ?? false)
            ? title!.trim()
            : (language ?? codec ?? 'Subtitle');
    return name;
  }

  static SubtitleStream? fromJson(Map json) {
    final index = (json['Index'] as num?)?.toInt();
    if (index == null) return null;
    return SubtitleStream(
      index: index,
      isExternal: json['IsExternal'] as bool? ?? false,
      isTextSubtitleStream: json['IsTextSubtitleStream'] as bool? ?? true,
      codec: json['Codec'] as String?,
      displayTitle: json['DisplayTitle'] as String?,
      language: json['Language'] as String?,
      title: json['Title'] as String?,
      deliveryUrl: json['DeliveryUrl'] as String?,
      isForced: json['IsForced'] as bool? ?? false,
      isDefault: json['IsDefault'] as bool? ?? false,
    );
  }
}

/// The subtitle streams in an item's JSON, from either shape the server uses:
/// MediaStreams at the top level, or inside the first media source.
List<SubtitleStream> parseSubtitleStreams(Map<String, dynamic> json) {
  final out = <SubtitleStream>[];
  final seen = <int>{};
  void take(dynamic list) {
    if (list is! List) return;
    for (final st in list.whereType<Map>()) {
      if ('${st['Type']}' != 'Subtitle') continue;
      final s = SubtitleStream.fromJson(st);
      if (s != null && seen.add(s.index)) out.add(s);
    }
  }

  take(json['MediaStreams']);
  for (final src in (json['MediaSources'] as List? ?? const [])) {
    if (src is Map) take(src['MediaStreams']);
  }
  return out;
}

/// One audio track as the server describes it. The player knows little more
/// than a language code, so the format and channel layout come from here.
class AudioStream {
  const AudioStream({
    required this.index,
    this.codec,
    this.profile,
    this.displayTitle,
    this.language,
    this.title,
    this.channelLayout,
    this.channels,
    this.isDefault = false,
  });

  final int index;
  final String? codec;

  /// The finer name for the format where there is one: "DTS-HD MA" rather
  /// than plain "dts".
  final String? profile;
  final String? displayTitle;
  final String? language;
  final String? title;
  final String? channelLayout;
  final int? channels;
  final bool isDefault;

  static AudioStream? fromJson(Map json) {
    final index = (json['Index'] as num?)?.toInt();
    if (index == null) return null;
    return AudioStream(
      index: index,
      codec: json['Codec'] as String?,
      profile: json['Profile'] as String?,
      displayTitle: json['DisplayTitle'] as String?,
      language: json['Language'] as String?,
      title: json['Title'] as String?,
      channelLayout: json['ChannelLayout'] as String?,
      channels: (json['Channels'] as num?)?.toInt(),
      isDefault: json['IsDefault'] as bool? ?? false,
    );
  }
}

/// The audio streams in an item's JSON, from either shape the server uses.
List<AudioStream> parseAudioStreams(Map<String, dynamic> json) {
  final out = <AudioStream>[];
  final seen = <int>{};
  void take(dynamic list) {
    if (list is! List) return;
    for (final st in list.whereType<Map>()) {
      if ('${st['Type']}' != 'Audio') continue;
      final s = AudioStream.fromJson(st);
      if (s != null && seen.add(s.index)) out.add(s);
    }
  }

  take(json['MediaStreams']);
  for (final src in (json['MediaSources'] as List? ?? const [])) {
    if (src is Map) take(src['MediaStreams']);
  }
  return out;
}

/// The extension of an item's original file, from the best clue the server
/// gives: the file's own name (item lists only carry it when asked for), else
/// its media source's format, else the item's format list, which uses ffmpeg's
/// names (`mov,mp4,m4a,3gp,3g2,mj2`, `matroska,webm`) and is always present.
String? mediaFileExtension(Map<String, dynamic> json) {
  final audio = json['MediaType'] == 'Audio' || json['Type'] == 'Audio';
  String? fromPath(Object? path) {
    if (path is! String) return null;
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext) ? ext : null;
  }

  String? fromFormat(Object? format) {
    if (format is! String || format.trim().isEmpty) return null;
    final names = format.toLowerCase().split(',').map((s) => s.trim()).toList();
    if (names.contains('matroska') || names.first == 'mkv') return 'mkv';
    if (names.contains('mp4')) return audio ? 'm4a' : 'mp4';
    const known = {
      'mpegts': 'ts',
      'mpeg': 'mpg',
      'asf': 'wmv',
      'webm': 'webm',
      'avi': 'avi',
      'flv': 'flv',
      'ogg': 'ogg',
      'flac': 'flac',
      'mp3': 'mp3',
      'wav': 'wav',
      'aac': 'aac',
      'opus': 'opus',
      'm4a': 'm4a',
      'm4v': 'm4v',
      'm2ts': 'm2ts',
      'wtv': 'wtv',
    };
    final first = names.first;
    if (known.containsKey(first)) {
      return first == 'asf' && audio ? 'wma' : known[first];
    }
    return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(first) ? first : null;
  }

  final sources = (json['MediaSources'] as List? ?? const [])
      .whereType<Map>()
      .toList();
  final source = sources.isEmpty ? null : sources.first;
  return fromPath(json['Path']) ??
      fromPath(source?['Path']) ??
      fromFormat(source?['Container']) ??
      fromFormat(json['Container']);
}

/// The id of an item's first media source, or null when it has none.
String? firstMediaSourceId(Map<String, dynamic> json) {
  for (final src in (json['MediaSources'] as List? ?? const [])) {
    if (src is Map) {
      final id = src['Id'];
      if (id is String && id.isNotEmpty) return id;
    }
  }
  return null;
}

