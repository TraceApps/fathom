part of 'jellyfin_client.dart';

/// Playback: stream URLs, opening and closing live streams, device profiles, playback reporting, and image URLs.
extension JellyfinStreamingApi on JellyfinClient {
/// Direct stream URL for a video. libmpv plays the original file; the server
  /// serves range requests so seeking works. Auth travels as the api_key param.
  String videoStreamUrl({
    required String baseUrl,
    required String itemId,
    required String token,
  }) {
    final params = {
      'static': 'true',
      'mediaSourceId': itemId,
      'api_key': token,
      'deviceId': deviceId,
    };
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$baseUrl/Videos/$itemId/stream?$q';
  }

/// Resolves a playable URL for a regular video via PlaybackInfo. With
  /// [forceTranscode] the server is told not to direct-play, so it returns an
  /// HLS transcode URL — the fallback for files libmpv can't play directly.
  Future<String> openVideoStream({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
    bool forceTranscode = false,
    int? maxBitrate,
  }) async {
    try {
      final profile = _deviceVideoProfile;
      final force = forceTranscode;
      final res = await _dio.post(
        '$baseUrl/Items/$itemId/PlaybackInfo',
        queryParameters: {
          'UserId': userId,
          'MaxStreamingBitrate': '${maxBitrate ?? 120000000}',
          'EnableDirectPlay': force ? 'false' : 'true',
          'EnableDirectStream': force ? 'false' : 'true',
          'EnableTranscoding': 'true',
          'AllowVideoStreamCopy': 'true',
          'AllowAudioStreamCopy': 'true',
        },
        data: {'DeviceProfile': profile},
        options: _authed(token),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final playSessionId = data['PlaySessionId'] as String?;
      final sources = (data['MediaSources'] as List?) ?? const [];
      if (sources.isEmpty) {
        throw JellyfinException(tr.errNoSourceVideo);
      }
      final ms = Map<String, dynamic>.from(sources.first as Map);
      final transcodingUrl = ms['TranscodingUrl'] as String?;
      if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
        return transcodingUrl.startsWith('http')
            ? transcodingUrl
            : '$baseUrl$transcodingUrl';
      }
      final params = {
        'static': 'true',
        'mediaSourceId': ?(ms['Id'] as String?),
        'playSessionId': ?playSessionId,
        'api_key': token,
        'deviceId': deviceId,
      };
      final q = params.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      return '$baseUrl/Videos/$itemId/stream?$q';
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Resolves a Chromecast-playable stream for [itemId]. The server direct-plays
  /// when the source codecs fit a Cast device (returning the raw file URL and
  /// its container's MIME, so an h264/aac MKV casts as-is on a Chromecast with
  /// Google TV / Android TV), or hands back an HLS transcode URL when they don't.
  /// Returns the URL and the content type to give the Cast receiver.
  Future<({String url, String contentType})> castStream({
    required String baseUrl,
    required String userId,
    required String token,
    required String itemId,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Items/$itemId/PlaybackInfo',
        queryParameters: {
          'UserId': userId,
          'MaxStreamingBitrate': '120000000',
          'EnableDirectPlay': 'true',
          'EnableDirectStream': 'true',
          'EnableTranscoding': 'true',
          'AllowVideoStreamCopy': 'true',
          'AllowAudioStreamCopy': 'true',
        },
        data: {'DeviceProfile': _castDeviceProfile},
        options: _authed(token),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final playSessionId = data['PlaySessionId'] as String?;
      final sources = (data['MediaSources'] as List?) ?? const [];
      if (sources.isEmpty) {
        throw JellyfinException(tr.errNoSourceVideo);
      }
      final ms = Map<String, dynamic>.from(sources.first as Map);
      final transcodingUrl = ms['TranscodingUrl'] as String?;
      if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
        final url = transcodingUrl.startsWith('http')
            ? transcodingUrl
            : '$baseUrl$transcodingUrl';
        return (url: url, contentType: 'application/x-mpegurl');
      }
      final container = (ms['Container'] as String?)
          ?.split(',')
          .first
          .trim()
          .toLowerCase();
      final params = {
        'static': 'true',
        'mediaSourceId': ?(ms['Id'] as String?),
        'playSessionId': ?playSessionId,
        'api_key': token,
        'deviceId': deviceId,
      };
      final q = params.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      return (
        url: '$baseUrl/Videos/$itemId/stream?$q',
        contentType: _mimeForContainer(container),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

static String _mimeForContainer(String? c) {
    switch (c) {
      case 'mp4':
      case 'm4v':
      case 'mov':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'ts':
      case 'mpegts':
      case 'm2ts':
        return 'video/mp2t';
      default:
        return 'video/mp4';
    }
  }

/// Opens a live stream for a channel via PlaybackInfo (the handshake HDHomeRun
  /// and most tuners require). Returns the playable URL plus the ids needed to
  /// close it later (freeing the tuner). Falls back to letting the server choose
  /// the source if our device profile trips it up.
  Future<LiveStreamHandle> openLiveStream({
    required String baseUrl,
    required String userId,
    required String token,
    required String channelId,
  }) async {
    // Mobile and Android TV both force the server's HLS h264 transcode. On the TV
    // this keeps the video in a clean 8-bit h264 the box decodes without wedging
    // its GPU (raw broadcast MPEG-TS / interlaced wedged the compositor), and the
    // ExoPlayer path still shows live captions: it injects a CLOSED-CAPTIONS
    // declaration into the HLS playlist so the embedded CEA-608 becomes selectable
    // (see ExoVideoPlayer). Desktop (libmpv) direct-plays the TS.
    final profile = (Platform.isAndroid || Platform.isIOS)
        ? {..._liveDeviceProfile, 'DirectPlayProfiles': const <Map>[]}
        : _liveDeviceProfile;
    try {
      return await _requestLiveStream(
        baseUrl: baseUrl,
        userId: userId,
        token: token,
        channelId: channelId,
        deviceProfile: profile,
      );
    } on JellyfinException {
      // Some channels 500 with a custom profile but work when the server picks.
      // NOT on Android TV: it renders through ExoPlayer, which wedges the Amlogic
      // GPU compositor on a raw MPEG-2 stream (needs a reboot to clear), and
      // letting the server pick can hand back exactly that. Surfacing the error is
      // far better than wedging the box. Phones use media_kit, which plays it fine.
      if (isTvDevice) rethrow;
      return _requestLiveStream(
        baseUrl: baseUrl,
        userId: userId,
        token: token,
        channelId: channelId,
        deviceProfile: null,
      );
    }
  }

/// Closes a previously opened live stream so the tuner is released. Without
  /// this, opening a few channels exhausts the tuners and further opens 500.
  Future<void> closeLiveStream({
    required String baseUrl,
    required String token,
    required String liveStreamId,
    String? playSessionId,
  }) async {
    try {
      await _dio.post(
        '$baseUrl/LiveStreams/Close',
        queryParameters: {'liveStreamId': liveStreamId},
        options: _authed(token),
      );
    } on DioException {
      // Best-effort.
    }
    // /Videos/ActiveEncodings used to live here. It is not part of the
    // Jellyfin API any more (checked against the published OpenAPI spec: no
    // such path), so it 404'd every time and released nothing. The transcode
    // is torn down by reporting Stopped WITH the LiveStreamId and
    // PlaySessionId, which reportPlaybackStopped now does.
  }

Future<LiveStreamHandle> _requestLiveStream({
    required String baseUrl,
    required String userId,
    required String token,
    required String channelId,
    required Map<String, dynamic>? deviceProfile,
  }) async {
    try {
      final res = await _dio.post(
        '$baseUrl/Items/$channelId/PlaybackInfo',
        queryParameters: {
          'UserId': userId,
          'StartTimeTicks': '0',
          'IsPlayback': 'true',
          'AutoOpenLiveStream': 'true',
          'MaxStreamingBitrate': '120000000',
        },
        data: deviceProfile != null
            ? {'DeviceProfile': deviceProfile}
            : <String, dynamic>{},
        options: _authed(token),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final playSessionId = data['PlaySessionId'] as String?;
      final sources = (data['MediaSources'] as List?) ?? const [];
      if (sources.isEmpty) {
        throw JellyfinException(tr.errNoSourceChannel);
      }
      final ms = Map<String, dynamic>.from(sources.first as Map);
      final liveStreamId = ms['LiveStreamId'] as String?;

      final transcodingUrl = ms['TranscodingUrl'] as String?;
      final String url;
      if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
        url = transcodingUrl.startsWith('http')
            ? transcodingUrl
            : '$baseUrl$transcodingUrl';
      } else {
        final params = {
          'static': 'true',
          'mediaSourceId': ?(ms['Id'] as String?),
          'liveStreamId': ?liveStreamId,
          'playSessionId': ?playSessionId,
          'api_key': token,
          'deviceId': deviceId,
        };
        final q = params.entries
            .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
            .join('&');
        url = '$baseUrl/Videos/$channelId/stream?$q';
      }
      return LiveStreamHandle(
        url: url,
        liveStreamId: liveStreamId ?? (ms['Id'] as String?),
        playSessionId: playSessionId,
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

// General video profile. libmpv plays essentially every container, codec and
  // subtitle format, so advertise a wide direct-play set and declare embedded
  // subtitle support. Without this (the old code reused the narrow live-TV
  // profile below, which had no subtitle profiles), Jellyfin would fall back to
  // a full HLS transcode for many files the client can actually play directly,
  // which is what made startup and seeking slow.
  // What a modern Cast device (Chromecast with Google TV / Android TV) plays
  // directly. Broad enough that an h264/aac MKV direct-plays (cast as-is), while
  // codecs a Chromecast can't handle fall back to an h264/aac HLS transcode.
  // The video profile actually sent for playback. On Android it restricts video
  // direct-play to codecs the device can HARDWARE decode (see
  // [hardwareVideoCodecs]); everything else transcodes to h264, which the device
  // decodes in hardware. This is what keeps AV1 (software-only on cheaper TV
  // sticks) from stuttering. Elsewhere (and until the codec probe runs) it's the
  // full profile unchanged.
  static Map<String, dynamic> get _deviceVideoProfile {
    bool android;
    try {
      android = Platform.isAndroid;
    } catch (_) {
      android = false;
    }
    if (!android || hardwareVideoCodecs.isEmpty) return _videoDeviceProfile;
    // Always keep h264: it's the transcode target and is hardware-decodable on
    // essentially every Android device, so it's the safe direct-play floor.
    final allowed = {...hardwareVideoCodecs, 'h264'};
    final profile =
        jsonDecode(jsonEncode(_videoDeviceProfile)) as Map<String, dynamic>;
    for (final p in (profile['DirectPlayProfiles'] as List)) {
      final m = p as Map;
      if (m['Type'] != 'Video') continue;
      final kept = (m['VideoCodec'] as String)
          .split(',')
          .where(allowed.contains)
          .toList();
      m['VideoCodec'] = (kept.isEmpty ? ['h264'] : kept).join(',');
    }
    // Transcode to h264 for the TV: universal hardware support, so a transcoded
    // stream is guaranteed to decode in hardware even if hevc isn't available.
    for (final p in (profile['TranscodingProfiles'] as List)) {
      final m = p as Map;
      if (m['Type'] == 'Video') m['VideoCodec'] = 'h264';
    }
    return profile;
  }

static const _castDeviceProfile = {
    'MaxStreamingBitrate': 120000000,
    'MaxStaticBitrate': 120000000,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container': 'mp4,mkv,webm,m4v,mov',
        'VideoCodec': 'h264,hevc,vp8,vp9',
        'AudioCodec': 'aac,mp3,ac3,eac3,opus,vorbis,flac',
      },
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac,mp3',
        'Context': 'Streaming',
      },
    ],
    'SubtitleProfiles': [
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'webvtt', 'Method': 'External'},
    ],
  }

;

static const _videoDeviceProfile = {
    'MaxStreamingBitrate': 120000000,
    'MaxStaticBitrate': 120000000,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container':
            'mp4,m4v,mkv,webm,mov,avi,flv,ts,m2ts,mts,mpegts,wmv,asf,3gp,3g2,'
            'ogv,ogm,mpg,mpeg,vob,divx,dvr-ms,f4v,rm,rmvb',
        'VideoCodec':
            'h264,hevc,h265,mpeg2video,mpeg4,msmpeg4v3,vc1,vp8,vp9,av1,theora,'
            'wmv1,wmv2,wmv3,prores,dv,mjpeg',
        'AudioCodec':
            'aac,ac3,eac3,mp3,mp2,opus,flac,vorbis,dts,dca,truehd,mlp,alac,pcm,'
            'pcm_s16le,pcm_s24le,pcm_dvd,wmav2,wmapro,wmavoice,nellymoser,'
            'speex,amr_nb,amr_wb,ape,tta,wavpack',
      },
      {
        'Type': 'Audio',
        'Container':
            'mp3,aac,m4a,m4b,flac,alac,ogg,oga,opus,wav,wma,ape,wv,mka,tak,'
            'dsf,dff,mpc',
      },
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'VideoCodec': 'h264,hevc',
        'AudioCodec': 'aac,ac3,eac3,mp3',
        'Context': 'Streaming',
      },
      {
        'Type': 'Audio',
        'Container': 'mp3',
        'AudioCodec': 'mp3',
        'Protocol': 'http',
        'Context': 'Streaming',
      },
    ],
    // Declaring these as Embed/External stops the server from burning subtitles
    // into the video (which forces a transcode); libmpv renders them itself.
    'SubtitleProfiles': [
      {'Format': 'srt', 'Method': 'Embed'},
      {'Format': 'subrip', 'Method': 'Embed'},
      {'Format': 'ass', 'Method': 'Embed'},
      {'Format': 'ssa', 'Method': 'Embed'},
      {'Format': 'vtt', 'Method': 'Embed'},
      {'Format': 'webvtt', 'Method': 'Embed'},
      {'Format': 'pgssub', 'Method': 'Embed'},
      {'Format': 'dvdsub', 'Method': 'Embed'},
      {'Format': 'dvbsub', 'Method': 'Embed'},
      {'Format': 'sub', 'Method': 'Embed'},
      {'Format': 'idx', 'Method': 'Embed'},
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'subrip', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'ssa', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'webvtt', 'Method': 'External'},
    ],
  }

;

// Broad direct-play profile: libmpv plays these, so the server hands back a
  // direct stream (remuxing to HLS only when it must).
  static const _liveDeviceProfile = {
    'MaxStreamingBitrate': 120000000,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts,mkv,mp4,m4v,avi,mov,webm,flv',
        'VideoCodec': 'h264,hevc,mpeg2video,mpeg4,vc1,vp9,av1',
        'AudioCodec': 'aac,ac3,eac3,mp3,mp2,opus,flac,vorbis,dts',
      },
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac,mp3',
        'Context': 'Streaming',
      },
    ],
    // Without any SubtitleProfiles the server has no plan to deliver captions on
    // a live channel, so nothing renders when you enable CC. Declaring the same
    // Embed/External support the VOD profile uses tells the server to keep the
    // subtitle stream in the container (DVB/teletext/608 caption streams
    // included) for libmpv to render, instead of dropping it.
    'SubtitleProfiles': [
      {'Format': 'srt', 'Method': 'Embed'},
      {'Format': 'subrip', 'Method': 'Embed'},
      {'Format': 'ass', 'Method': 'Embed'},
      {'Format': 'ssa', 'Method': 'Embed'},
      {'Format': 'vtt', 'Method': 'Embed'},
      {'Format': 'webvtt', 'Method': 'Embed'},
      {'Format': 'pgssub', 'Method': 'Embed'},
      {'Format': 'dvdsub', 'Method': 'Embed'},
      {'Format': 'dvbsub', 'Method': 'Embed'},
      {'Format': 'dvb_teletext', 'Method': 'Embed'},
      {'Format': 'eia_608', 'Method': 'Embed'},
      {'Format': 'eia_708', 'Method': 'Embed'},
      {'Format': 'cc_dec', 'Method': 'Embed'},
      {'Format': 'sub', 'Method': 'Embed'},
      {'Format': 'idx', 'Method': 'Embed'},
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'subrip', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'ssa', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'webvtt', 'Method': 'External'},
    ],
  }

;

/// Direct audio stream URL. libmpv plays the original file.
  String audioStreamUrl({
    required String baseUrl,
    required String itemId,
    required String token,
  }) {
    final params = {'static': 'true', 'api_key': token, 'deviceId': deviceId};
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$baseUrl/Audio/$itemId/stream?$q';
  }

/// An audio-only HLS stream of [itemId]'s primary audio track, for casting a
  /// video's audio to an audio-only speaker (Nest/Home Mini) which can't render
  /// a video stream. Uses the universal audio endpoint, which extracts and
  /// transcodes the audio to AAC-in-HLS.
  String castAudioUrl({
    required String baseUrl,
    required String userId,
    required String itemId,
    required String token,
  }) {
    // A plain progressive MP3 stream, which Google speakers play the most
    // reliably (HLS-in-TS tended to load but never start on a Nest/Home Mini).
    final params = {
      'UserId': userId,
      'DeviceId': deviceId,
      'api_key': token,
      'AudioCodec': 'mp3',
      'Container': 'mp3',
      'MaxStreamingBitrate': '320000',
    };
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$baseUrl/Audio/$itemId/universal?$q';
  }

Future<void> reportPlaybackStart({
    required String baseUrl,
    required String token,
    required String itemId,
    required int positionTicks,
  }) =>
      _postPlayState('$baseUrl/Sessions/Playing', token, itemId, positionTicks);

Future<void> reportPlaybackProgress({
    required String baseUrl,
    required String token,
    required String itemId,
    required int positionTicks,
  }) => _postPlayState(
    '$baseUrl/Sessions/Playing/Progress',
    token,
    itemId,
    positionTicks,
  );

/// Tells the server playback ended.
  ///
  /// [liveStreamId] and [playSessionId] are not optional extras for Live TV:
  /// they are how the server knows WHICH live session ended, and without them
  /// it leaves the tuner and any transcode running. On an HDHomeRun that means
  /// the 2-stream limit is reached after a couple of channel changes and every
  /// further tune-in 500s.
  Future<void> reportPlaybackStopped({
    required String baseUrl,
    required String token,
    required String itemId,
    required int positionTicks,
    String? liveStreamId,
    String? playSessionId,
  }) => _postPlayState(
    '$baseUrl/Sessions/Playing/Stopped',
    token,
    itemId,
    positionTicks,
    liveStreamId: liveStreamId,
    playSessionId: playSessionId,
  );

Future<void> _postPlayState(
    String url,
    String token,
    String itemId,
    int positionTicks, {
    String? liveStreamId,
    String? playSessionId,
  }) async {
    try {
      await _dio.post(
        url,
        data: {
          'ItemId': itemId,
          'MediaSourceId': itemId,
          'PositionTicks': positionTicks,
          'CanSeek': true,
          'PlayMethod': 'DirectStream',
          'LiveStreamId': ?liveStreamId,
          'PlaySessionId': ?playSessionId,
        },
        options: _authed(token),
      );
    } on DioException {
      // Progress reporting is best-effort; never let it break playback.
    }
  }

/// The URL for a subtitle track the server stores beside the video (a .srt
  /// next to it, or one a subtitle plugin fetched).
  ///
  /// [deliveryUrl] is what the item's media streams report, but only some
  /// responses carry it: fetching an item plainly (measured on 12.0) leaves it
  /// out, so the address is built from the item, its media source and the
  /// track's index instead. That route serves the file either way.
  String subtitleUrl({
    required String baseUrl,
    required String token,
    required String itemId,
    required int index,
    String? deliveryUrl,
    String? mediaSourceId,
    String? codec,
  }) {
    final raw = (deliveryUrl != null && deliveryUrl.isNotEmpty)
        ? (deliveryUrl.startsWith('http')
            ? deliveryUrl
            : '$baseUrl$deliveryUrl')
        : '$baseUrl/Videos/$itemId/${mediaSourceId ?? itemId}'
            '/Subtitles/$index/0/Stream.${subtitleExtension(codec)}';
    if (raw.contains('api_key=')) return raw;
    return '$raw${raw.contains('?') ? '&' : '?'}api_key=$token';
  }

  /// The file extension the subtitle route wants. The server converts on the
  /// way out, so asking for the track's own format keeps it untouched.
  String subtitleExtension(String? codec) {
    switch ((codec ?? '').toLowerCase()) {
      case 'subrip':
      case 'srt':
        return 'srt';
      case 'ass':
        return 'ass';
      case 'ssa':
        return 'ssa';
      case 'webvtt':
      case 'vtt':
        return 'vtt';
      case '':
        return 'srt';
      default:
        return 'vtt';
    }
  }

  /// Builds an image URL for an item. Load it with [imageHeaders] for auth.
  String imageUrl({
    required String baseUrl,
    required String itemId,
    String type = 'Primary',
    String? tag,
    int? maxHeight,
    int? maxWidth,
  }) {
    final params = <String, String>{'quality': '90'};
    if (tag != null) params['tag'] = tag;
    if (maxHeight != null) params['fillHeight'] = '$maxHeight';
    if (maxWidth != null) params['fillWidth'] = '$maxWidth';
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$baseUrl/Items/$itemId/Images/$type?$q';
  }

/// URL for one trickplay tile sheet (a grid of scrub-preview thumbnails).
  /// [width] is the resolution key from the item's trickplay geometry.
  String trickplayTileUrl({
    required String baseUrl,
    required String itemId,
    required int width,
    required int tileIndex,
  }) {
    return '$baseUrl/Videos/$itemId/Trickplay/$width/$tileIndex.jpg';
  }

/// URL for a user's avatar (profile image). Returns null when the user has
  /// no primary image set.
  String? userImageUrl({
    required String baseUrl,
    required String userId,
    String? tag,
    int? size,
  }) {
    if (tag == null) return null;
    // /UserImage is what Jellyfin 12 documents; the per-user route it replaced
    // is gone from the API. An image URL can't fall back after the fact (it's
    // handed to the image loader), so the newer one is used outright: it has
    // been there since 10.10.
    final params = <String, String>{
      'userId': userId,
      'tag': tag,
      'quality': '90'
    };
    if (size != null) params['fillHeight'] = '$size';
    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$baseUrl/UserImage?$q';
  }

/// Upload a user's avatar. Jellyfin expects the image bytes base64-encoded in
  /// the request body with the image mime type as Content-Type.
  Future<void> uploadUserImage({
    required String baseUrl,
    required String token,
    required String userId,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    try {
      final b64 = base64Encode(bytes);
      try {
        await _dio.post(
          '$baseUrl/UserImage',
          data: b64,
          queryParameters: {'userId': userId},
          options: Options(headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': contentType,
          }),
        );
      } on DioException catch (e) {
        if (e.response?.statusCode != 404 && e.response?.statusCode != 405) {
          rethrow;
        }
        await _dio.post(
          '$baseUrl/Users/$userId/Images/Primary',
          data: b64,
          options: Options(headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': contentType,
          }),
        );
      }
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

Future<void> deleteUserImage({
    required String baseUrl,
    required String token,
    required String userId,
  }) async {
    try {
      await requestWithFallback(
        'DELETE',
        url: '$baseUrl/UserImage',
        legacyUrl: '$baseUrl/Users/$userId/Images/Primary',
        token: token,
        query: {'userId': userId},
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// URL for the server's custom splash screen image.
  String splashscreenUrl({required String baseUrl}) =>
      '$baseUrl/Branding/Splashscreen';

/// Uploads a custom splash screen image (admin only).
  Future<void> uploadSplashscreen({
    required String baseUrl,
    required String token,
    required List<int> bytes,
    String contentType = 'image/png',
  }) async {
    try {
      await _dio.post(
        '$baseUrl/Branding/Splashscreen',
        data: base64Encode(bytes),
        options: Options(
          headers: {
            'Authorization': authHeader(token: token),
            'Content-Type': contentType,
          },
        ),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }

/// Removes the custom splash screen image (admin only).
  Future<void> deleteSplashscreen({
    required String baseUrl,
    required String token,
  }) async {
    try {
      await _dio.delete(
        '$baseUrl/Branding/Splashscreen',
        options: _authed(token),
      );
    } on DioException catch (e) {
      throw JellyfinException(_friendlyDioError(e), cause: e);
    }
  }
}
