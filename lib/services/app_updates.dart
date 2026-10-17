import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:dio/dio.dart';

import 'secure_http.dart';

/// A downloadable file attached to a release.
class ReleaseAsset {
  final String name;
  final String url; // browser_download_url
  final int size; // bytes

  /// The file's SHA-256 as GitHub records it (lowercase hex), or null for
  /// releases published before GitHub started listing digests.
  final String? sha256;

  const ReleaseAsset(
      {required this.name, required this.url, required this.size, this.sha256});

  factory ReleaseAsset.fromJson(Map<String, dynamic> j) {
    final digest = j['digest'] as String? ?? '';
    return ReleaseAsset(
      name: j['name'] as String? ?? '',
      url: j['browser_download_url'] as String? ?? '',
      size: (j['size'] as num?)?.toInt() ?? 0,
      sha256: digest.startsWith('sha256:')
          ? digest.substring(7).toLowerCase()
          : null,
    );
  }
}

/// A published Fathom release, from the GitHub Releases API.
class GithubRelease {
  final String tagName; // e.g. "v0.9.0-beta.1"
  final String version; // normalized semver, e.g. "0.9.0-beta.1"
  final String name; // release title
  final String body; // markdown notes
  final String htmlUrl; // release page
  final bool prerelease;
  final List<ReleaseAsset> assets;

  const GithubRelease({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.prerelease,
    this.assets = const [],
  });

  factory GithubRelease.fromJson(Map<String, dynamic> j) {
    final tag = (j['tag_name'] as String? ?? '').trim();
    final title = (j['name'] as String? ?? '').trim();
    return GithubRelease(
      tagName: tag,
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      name: title.isNotEmpty ? title : tag,
      body: (j['body'] as String? ?? '').trim(),
      htmlUrl: j['html_url'] as String? ?? '',
      prerelease: j['prerelease'] as bool? ?? false,
      assets: [
        for (final a in (j['assets'] as List?) ?? const [])
          if (a is Map) ReleaseAsset.fromJson(a.cast<String, dynamic>()),
      ],
    );
  }

  /// The installable asset for the running platform: the AppImage on Linux, the
  /// Windows zip on Windows. Null when the release has no matching file.
  ReleaseAsset? get platformAsset {
    ReleaseAsset? pick(bool Function(String) test) {
      for (final a in assets) {
        if (test(a.name.toLowerCase())) return a;
      }
      return null;
    }

    if (Platform.isLinux) {
      // Releases now ship both x86_64 and aarch64 AppImages, so match this
      // host's arch (falling back to any AppImage for older single-arch tags).
      final arch = Abi.current() == Abi.linuxArm64 ? 'aarch64' : 'x86_64';
      return pick((n) => n.endsWith('.appimage') && n.contains(arch)) ??
          pick((n) => n.endsWith('.appimage'));
    }
    if (Platform.isWindows) {
      return pick((n) => n.endsWith('.zip') && n.contains('windows'));
    }
    if (Platform.isAndroid) {
      // Match this device's ABI when a release ships split APKs (so an
      // armeabi-v7a TV box doesn't grab the arm64 phone build), then a
      // universal APK, then any .apk. (Requires an .apk on the release.)
      final abi = Abi.current();
      final tags = abi == Abi.androidArm64
          ? const ['arm64', 'aarch64']
          : abi == Abi.androidArm
              ? const ['armeabi', 'armv7', 'arm-v7', 'arm32']
              : abi == Abi.androidX64
                  ? const ['x86_64', 'x64']
                  : const <String>[];
      for (final t in tags) {
        final m = pick((n) => n.endsWith('.apk') && n.contains(t));
        if (m != null) return m;
      }
      return pick((n) =>
              n.endsWith('.apk') &&
              !n.contains('arm') &&
              !n.contains('aarch64') &&
              !n.contains('x86')) ??
          pick((n) => n.endsWith('.apk'));
    }
    return null;
  }
}

/// Whether Fathom can replace itself in place on this install: only when running
/// as an AppImage on Linux, or as the portable build on Windows. A package- or
/// store-managed install must update through its manager, so this returns false
/// and callers fall back to opening the release page.
bool get canSelfInstall {
  if (Platform.isLinux) return Platform.environment.containsKey('APPIMAGE');
  if (Platform.isWindows) return true;
  // Android hands the downloaded APK to the system package installer (the user
  // still confirms). A Play-store install would update through the store, but
  // Fathom's Android build is sideloaded, so this is the right path.
  if (Platform.isAndroid) return true;
  return false;
}

const _repo = 'TraceApps/fathom';

/// Fetches releases from GitHub and returns the newest one for the channel:
/// stable-only, or including pre-releases. Returns null if none or on failure
/// (offline, rate-limited, etc.) so the caller can degrade quietly.
Future<GithubRelease?> fetchLatestRelease({
  required bool includePrereleases,
  Dio? dio,
}) async {
  final client = dio ??
      await secureDio(
          options: BaseOptions(connectTimeout: const Duration(seconds: 12)));
  try {
    final res = await client.get(
      'https://api.github.com/repos/$_repo/releases',
      queryParameters: {'per_page': 30},
      // GitHub's API requires a User-Agent and returns 403 without one. dart:io
      // sets a default on some platforms but not others (Windows sends none), so
      // set it explicitly rather than relying on the implicit default.
      options: Options(headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Fathom',
      }),
    );
    final list = (res.data as List?) ?? const [];
    final releases = list
        .whereType<Map>()
        .map((e) => GithubRelease.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.version.isNotEmpty)
        .where((r) => includePrereleases || !r.prerelease)
        .toList();
    if (releases.isEmpty) return null; // no release for this channel yet
    releases.sort((a, b) => compareSemver(b.version, a.version)); // newest first
    return releases.first;
  } on DioException {
    // A real reach/rate-limit failure. Rethrow so the caller can tell "offline"
    // apart from "no newer version", which returns null above.
    rethrow;
  }
}

/// Compares two semver strings. Returns >0 if [a] is newer than [b], <0 if
/// older, 0 if equal. Follows semver precedence: a release with no pre-release
/// tag outranks the same core version with one (1.0.0 > 1.0.0-rc.1), and
/// pre-release identifiers compare field by field (numeric by value, else
/// lexically). Build metadata (after '+') is ignored.
int compareSemver(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  for (var i = 0; i < 3; i++) {
    final c = pa.nums[i].compareTo(pb.nums[i]);
    if (c != 0) return c;
  }
  if (pa.pre.isEmpty && pb.pre.isEmpty) return 0;
  if (pa.pre.isEmpty) return 1; // a is a full release, b is a pre-release
  if (pb.pre.isEmpty) return -1;
  final n = pa.pre.length < pb.pre.length ? pa.pre.length : pb.pre.length;
  for (var i = 0; i < n; i++) {
    final ai = pa.pre[i];
    final bi = pb.pre[i];
    final an = int.tryParse(ai);
    final bn = int.tryParse(bi);
    int c;
    if (an != null && bn != null) {
      c = an.compareTo(bn);
    } else if (an != null) {
      c = -1; // numeric identifiers rank below non-numeric ones
    } else if (bn != null) {
      c = 1;
    } else {
      c = ai.compareTo(bi);
    }
    if (c != 0) return c;
  }
  return pa.pre.length.compareTo(pb.pre.length);
}

({List<int> nums, List<String> pre}) _parse(String v) {
  var s = v.trim();
  if (s.startsWith('v')) s = s.substring(1);
  final plus = s.indexOf('+'); // strip build metadata
  if (plus >= 0) s = s.substring(0, plus);
  final dash = s.indexOf('-');
  final core = dash >= 0 ? s.substring(0, dash) : s;
  final pre = dash >= 0 ? s.substring(dash + 1) : '';
  final parts = core.split('.');
  int at(int i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0;
  return (
    nums: [at(0), at(1), at(2)],
    pre: pre.isEmpty ? <String>[] : pre.split('.'),
  );
}
