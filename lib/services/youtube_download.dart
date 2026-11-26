import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

import '../l10n/l10n.dart';
import 'youtube_streams.dart';

/// What a download produces.
enum YtDownloadKind {
  /// Video with sound. Above 360p that means fetching two streams and muxing.
  video,

  /// Just the audio track. Needs no muxing at all.
  audio,
}

/// The container/codec for an audio-only download.
enum YtAudioFormat {
  /// YouTube's native AAC, saved as .m4a with no re-encode (passthrough).
  m4a,

  /// Re-encoded to MP3 (needs ffmpeg). Plays on essentially anything.
  mp3,
}

/// The container for a video download.
enum YtVideoContainer { mp4, mkv }

/// Everything that decides what a single download produces, bundled so the queue
/// can carry one value per job.
class YtDownloadOptions {
  final YtDownloadKind kind;
  final int? preferredHeight;
  final YtAudioFormat audioFormat;
  final int audioBitrate; // kbps, MP3 only
  final YtVideoContainer container;

  const YtDownloadOptions({
    this.kind = YtDownloadKind.video,
    this.preferredHeight,
    this.audioFormat = YtAudioFormat.m4a,
    this.audioBitrate = 320,
    this.container = YtVideoContainer.mp4,
  });

  /// Turns the saved `youtubeDownloadQuality` + `youtubeVideoContainer` prefs
  /// into options. Null when the quality is 'ask' (show the picker instead).
  static YtDownloadOptions? fromPrefs(String quality, String container) {
    if (quality == 'ask') return null;
    final box =
        container == 'mkv' ? YtVideoContainer.mkv : YtVideoContainer.mp4;
    if (quality == 'audio') {
      return const YtDownloadOptions(kind: YtDownloadKind.audio);
    }
    if (quality.startsWith('mp3-')) {
      return YtDownloadOptions(
        kind: YtDownloadKind.audio,
        audioFormat: YtAudioFormat.mp3,
        audioBitrate: int.tryParse(quality.substring(4)) ?? 320,
      );
    }
    return YtDownloadOptions(
      kind: YtDownloadKind.video,
      preferredHeight: int.tryParse(quality),
      container: box,
    );
  }
}

/// How far along a download is. Bytes, not percentages: totals aren't always
/// known up front, and a bare percentage can't say how much is left.
class YtDownloadProgress {
  final int received;
  final int total; // -1 when the server doesn't say
  final String stage; // 'video', 'audio', 'merging'

  const YtDownloadProgress({
    required this.received,
    required this.total,
    required this.stage,
  });

  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

/// Downloading a YouTube video to a file.
///
/// The awkward part is that YouTube only serves video and audio together up to
/// 360p. Anything better is two separate streams, so a real download means
/// fetching both and muxing them. That is a container operation, not a re-encode
/// — ffmpeg copies the streams, which takes a second or two rather than minutes,
/// and loses nothing.
///
/// Desktop shells out to ffmpeg: the copy bundled beside Fathom when there is
/// one (the Windows build ships it, since Windows has none of its own), else
/// the system's. Android has no binary to run, so it runs the same commands
/// through a bundled ffmpeg instead (ffmpeg_kit_flutter_new) rather than being
/// permanently capped at 360p/M4A the way it was before.
class YoutubeDownloader {
  YoutubeDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static bool? _ffmpegCached;

  /// The desktop ffmpeg that answered [hasFfmpeg]: the bundled copy's full
  /// path, or plain 'ffmpeg' for the one on PATH.
  static String _ffmpegExe = 'ffmpeg';

  /// Where a bundled ffmpeg sits: beside the Fathom executable.
  static String get _bundledFfmpeg {
    final dir = File(Platform.resolvedExecutable).parent.path;
    return '$dir${Platform.pathSeparator}'
        '${Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg'}';
  }

  /// Whether ffmpeg is available: bundled on Android, so always true there;
  /// the copy beside Fathom or the one on PATH elsewhere. Cached, since it
  /// can't change while we run and this is asked on every download and every
  /// menu build.
  static Future<bool> hasFfmpeg() async {
    if (_ffmpegCached != null) return _ffmpegCached!;
    if (Platform.isAndroid) return _ffmpegCached = true;
    final bundled = _bundledFfmpeg;
    for (final exe in [if (File(bundled).existsSync()) bundled, 'ffmpeg']) {
      try {
        final r = await Process.run(exe, ['-version']);
        if (r.exitCode == 0) {
          _ffmpegExe = exe;
          return _ffmpegCached = true;
        }
      } catch (_) {}
    }
    return _ffmpegCached = false;
  }

  /// Only for tests, which must not depend on the host having ffmpeg.
  static void debugSetFfmpeg(bool? value) => _ffmpegCached = value;

  /// Runs an ffmpeg command: the bundled plugin on Android (which has no
  /// system binary), the bundled or system ffmpeg elsewhere. Same call sites,
  /// same failure behavior, either way.
  static Future<void> _ffmpeg(List<String> args, String context) async {
    if (Platform.isAndroid) {
      final session = await FFmpegKit.executeWithArguments(args);
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        final log = await session.getAllLogsAsString();
        throw Exception('$context: ${(log ?? '').trim()}');
      }
      return;
    }
    await hasFfmpeg(); // settles which ffmpeg to run
    final r = await Process.run(_ffmpegExe, args);
    if (r.exitCode != 0) {
      throw Exception('$context: ${r.stderr.toString().trim()}');
    }
  }

  /// Filenames that survive a real filesystem.
  ///
  /// Video titles contain slashes, colons, quotes and emoji. A slash alone
  /// silently writes to a directory that doesn't exist.
  static String safeFileName(String title, {required String extension}) {
    var name = title
        .replaceAll(RegExp(r'[/\\?%*:|"<>]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.isEmpty) name = 'video';
    // Most filesystems cap a component at 255 bytes; leave room for the
    // extension and for the uniquifying suffix below.
    const maxBase = 180;
    if (name.length > maxBase) name = name.substring(0, maxBase).trim();
    return '$name.$extension';
  }

  /// A path that doesn't exist yet, by adding " (2)", " (3)" and so on.
  /// Downloading the same video twice shouldn't silently destroy the first.
  static File uniqueFile(Directory dir, String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot == -1 ? fileName : fileName.substring(0, dot);
    final ext = dot == -1 ? '' : fileName.substring(dot);
    var candidate = File('${dir.path}/$fileName');
    var n = 2;
    while (candidate.existsSync()) {
      candidate = File('${dir.path}/$base ($n)$ext');
      n++;
    }
    return candidate;
  }

  /// A folder path in one form for comparing: forward slashes, no trailing
  /// slash, and case-folded on Windows, where the folder picker hands back
  /// backslashes and downloads are written with forward ones.
  static String comparableFolder(String path, {bool? windows}) {
    var s = path.replaceAll(r'\', '/');
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return (windows ?? Platform.isWindows) ? s.toLowerCase() : s;
  }

  /// Moves a finished download into [into] and returns its new path: a
  /// rename, or a copy and delete when the folder is on another drive.
  /// Never overwrites: a name already taken there gets " (2)" and so on.
  static Future<String> moveInto(File file, Directory into) async {
    await into.create(recursive: true);
    final name = file.path.split(RegExp(r'[/\\]')).last;
    final target = uniqueFile(into, name);
    try {
      return (await file.rename(target.path)).path;
    } on FileSystemException {
      await file.copy(target.path);
      await file.delete();
      return target.path;
    }
  }

  /// How much to ask for at a time.
  ///
  /// The size matters: YouTube throttles a single continuous GET of a stream to
  /// around 96 KB/s, while the same URL served in ranged chunks runs at several
  /// MB/s — measured at 56x on this machine. yt-dlp chunks for exactly this
  /// reason, and 10MB is roughly what it uses.
  static const _chunkSize = 10 * 1024 * 1024;

  /// Downloads [url] to [target] in ranged chunks, reporting progress.
  ///
  /// Not dio's download(), which issues one continuous GET and gets throttled
  /// into taking half an hour over a 200MB video.
  Future<void> _fetch(
    String url,
    String target,
    String stage,
    void Function(YtDownloadProgress) onProgress,
    CancelToken cancel, {
    int retries = 3,
  }) async {
    final sink = File(target).openWrite();
    var received = 0;
    var total = -1;

    try {
      while (true) {
        final end = received + _chunkSize - 1;

        // Retry the chunk, not the file. Ranged requests make that possible:
        // a failure mid-download resumes from the bytes already written rather
        // than starting a 200MB video again.
        Response<ResponseBody>? res;
        for (var attempt = 1; ; attempt++) {
          try {
            res = await _dio.get<ResponseBody>(
              url,
              cancelToken: cancel,
              options: Options(
                responseType: ResponseType.stream,
                headers: {'Range': 'bytes=$received-$end'},
                // 206 is the ranged answer we want; 200 means the server
                // ignored the header and is sending everything, which works.
                validateStatus: (s) => s == 200 || s == 206,
              ),
            );
            break;
          } on DioException catch (e) {
            // A cancel is a decision, not a failure: never retry it.
            if (e.type == DioExceptionType.cancel) rethrow;
            if (attempt >= retries) rethrow;
            await Future<void>.delayed(Duration(seconds: attempt));
          }
        }

        // "bytes 0-10485759/30760668" — the only place the full size appears.
        if (total < 0) {
          final cr = res.headers.value('content-range');
          final slash = cr?.lastIndexOf('/') ?? -1;
          if (cr != null && slash != -1) {
            total = int.tryParse(cr.substring(slash + 1)) ?? -1;
          } else {
            total = int.tryParse(
                    res.headers.value('content-length') ?? '') ??
                -1;
          }
        }

        var chunkBytes = 0;
        // Throttled: an unthrottled callback fires on every raw stream chunk
        // (dozens of times a second on a fast connection), and each one
        // rebuilds every widget watching the downloads list — fine for one
        // download, but with several running at once it was enough to make
        // the whole app janky, not just the downloads UI. Still reports the
        // final byte count below so the bar doesn't stall between ticks.
        var lastReport = DateTime.now();
        await for (final bytes in res.data!.stream) {
          sink.add(bytes);
          chunkBytes += bytes.length;
          received += bytes.length;
          final now = DateTime.now();
          if (now.difference(lastReport) >= const Duration(milliseconds: 150)) {
            lastReport = now;
            onProgress(YtDownloadProgress(
                received: received, total: total, stage: stage));
          }
        }
        onProgress(
            YtDownloadProgress(received: received, total: total, stage: stage));

        // The server ignored the Range header and sent the lot: done already.
        if (res.statusCode == 200) break;
        // A short chunk means the end of the file, whatever the total said.
        if (chunkBytes == 0) break;
        if (total > 0 && received >= total) break;
        if (chunkBytes < _chunkSize) break;
      }
    } finally {
      await sink.close();
    }
  }

  /// Muxes [video] and [audio] into [output] without re-encoding. mp4 needs the
  /// faststart flag; mkv takes any codec pairing as-is, so it's dropped there.
  Future<void> _mux(File video, File audio, File output,
      {bool mkv = false}) async {
    await _ffmpeg([
      '-hide_banner', '-loglevel', 'error',
      '-i', video.path,
      '-i', audio.path,
      '-map', '0:v:0',
      '-map', '1:a:0',
      '-c', 'copy',
      if (!mkv) ...['-movflags', '+faststart'],
      '-y', output.path,
    ], 'Merging failed');
  }

  /// Rewraps a self-contained stream into a new container without re-encoding.
  Future<void> _remux(File input, File output) async {
    await _ffmpeg([
      '-hide_banner', '-loglevel', 'error',
      '-i', input.path,
      '-c', 'copy',
      '-y', output.path,
    ], 'Remux failed');
  }

  /// Re-encodes the audio in [input] to an MP3 at [bitrateKbps].
  Future<void> _transcodeMp3(File input, File output, int bitrateKbps) async {
    await _ffmpeg([
      '-hide_banner', '-loglevel', 'error',
      '-i', input.path,
      '-vn',
      '-c:a', 'libmp3lame',
      '-b:a', '${bitrateKbps}k',
      '-y', output.path,
    ], 'MP3 conversion failed');
  }

  /// Downloads a video, muxing when it has to.
  ///
  /// Returns the file written. [preferredHeight] picks the closest quality at
  /// or below it; null takes the best available.
  Future<File> download({
    required String videoUrl,
    required String title,
    required Directory into,
    YtDownloadKind kind = YtDownloadKind.video,
    int? preferredHeight,
    YtAudioFormat audioFormat = YtAudioFormat.m4a,
    int audioBitrate = 320,
    YtVideoContainer container = YtVideoContainer.mp4,
    int retries = 3,
    required void Function(YtDownloadProgress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final cancel = cancelToken ?? CancelToken();
    final streams = await resolveYoutubeStreams(videoUrl);
    await into.create(recursive: true);

    // Audio. M4A is a passthrough (no ffmpeg); MP3 is a quick re-encode.
    if (kind == YtDownloadKind.audio) {
      final audio = streams.audioUrl;
      if (audio == null) {
        throw Exception(tr.errYtNoAudio);
      }
      if (audioFormat == YtAudioFormat.mp3) {
        if (!await hasFfmpeg()) {
          throw Exception(tr.errYtNeedsFfmpegMp3);
        }
        final aTmp = File(
            '${into.path}/.fathom-${DateTime.now().microsecondsSinceEpoch}.audio');
        try {
          await _fetch(audio, aTmp.path, 'audio', onProgress, cancel,
              retries: retries);
          onProgress(const YtDownloadProgress(
              received: 0, total: -1, stage: 'merging'));
          final out = uniqueFile(into, safeFileName(title, extension: 'mp3'));
          await _transcodeMp3(aTmp, out, audioBitrate);
          return out;
        } finally {
          try {
            if (aTmp.existsSync()) aTmp.deleteSync();
          } catch (_) {}
        }
      }
      final out = uniqueFile(into, safeFileName(title, extension: 'm4a'));
      await _fetch(audio, out.path, 'audio', onProgress, cancel,
          retries: retries);
      return out;
    }

    final canMux = await hasFfmpeg();
    final mkv = container == YtVideoContainer.mkv;

    // Without ffmpeg the only self-contained option is the muxed stream, which
    // YouTube caps at 360p. Better than refusing, as long as it's said plainly.
    if (!streams.isAdaptive || !canMux) {
      final muxed = streams.muxedUrl;
      if (muxed == null) {
        // YouTube is dropping the single-file 360p stream, so for a growing
        // number of videos nothing is downloadable without a merge.
        throw Exception(canMux
            ? 'No downloadable stream for this video.'
            : 'This video only comes as separate video and audio, which need '
                'ffmpeg to merge. Install it, or download the audio instead.');
      }
      // MKV is a remux, so it needs ffmpeg; with it, wrap the muxed stream.
      if (mkv && canMux) {
        final vTmp = File(
            '${into.path}/.fathom-${DateTime.now().microsecondsSinceEpoch}.video');
        try {
          await _fetch(muxed, vTmp.path, 'video', onProgress, cancel,
              retries: retries);
          onProgress(const YtDownloadProgress(
              received: 0, total: -1, stage: 'merging'));
          final out = uniqueFile(into, safeFileName(title, extension: 'mkv'));
          await _remux(vTmp, out);
          return out;
        } finally {
          try {
            if (vTmp.existsSync()) vTmp.deleteSync();
          } catch (_) {}
        }
      }
      final out = uniqueFile(into, safeFileName(title, extension: 'mp4'));
      await _fetch(muxed, out.path, 'video', onProgress, cancel,
          retries: retries);
      return out;
    }

    final quality = _pick(streams.qualities, preferredHeight);
    if (quality == null || streams.audioUrl == null) {
      throw Exception(tr.errYtNoStream);
    }

    // Scratch files next to the target, then merged and cleaned up. A temp dir
    // could be on another filesystem, which turns the merge into a slow copy.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final vTmp = File('${into.path}/.fathom-$stamp.video');
    final aTmp = File('${into.path}/.fathom-$stamp.audio');
    try {
      await _fetch(quality.url, vTmp.path, 'video', onProgress, cancel,
          retries: retries);
      await _fetch(streams.audioUrl!, aTmp.path, 'audio', onProgress, cancel,
          retries: retries);
      onProgress(
          const YtDownloadProgress(received: 0, total: -1, stage: 'merging'));
      final out =
          uniqueFile(into, safeFileName(title, extension: mkv ? 'mkv' : 'mp4'));
      await _mux(vTmp, aTmp, out, mkv: mkv);
      return out;
    } finally {
      // Never leave scratch files behind, including after a cancel or a throw.
      for (final f in [vTmp, aTmp]) {
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// The best quality at or below [height]; the best available when null.
  /// Qualities arrive highest-first.
  static YtQuality? _pick(List<YtQuality> qualities, int? height) {
    if (qualities.isEmpty) return null;
    if (height == null) return qualities.first;
    for (final q in qualities) {
      if (q.height <= height) return q;
    }
    return qualities.last;
  }
}
