import 'dart:collection';
import 'dart:io';

/// A lightweight in-memory ring buffer of diagnostic log lines plus a report
/// builder. When the user turns on Diagnostic logging (Settings > Playback >
/// Advanced), the player creates a verbose libmpv logger and feeds its lines
/// here, and records a line each time playback opens. The user can then copy
/// the whole report into a bug report, so playback/streaming issues can be read
/// from a real log instead of guessed from a description.
///
/// Nothing kept here carries credentials, whoever wrote the line: [add] hides
/// them itself (see [redactSecrets]), and the secrets the app knows (the
/// sign-in token, API keys, passwords) are hidden by value too ([protect]).
/// The report is made to be pasted into a public issue, and a stream's
/// address carries the token: libmpv, a cast or an image error can each quote
/// it in a line of their own.
class Diagnostics {
  Diagnostics._();
  static final Diagnostics instance = Diagnostics._();

  static const int _max = 3000;
  final Queue<String> _lines = Queue<String>();

  /// Mirrors the `diagnosticLogging` pref, kept in sync by the app once prefs
  /// load. Capture is app-wide (global error hooks, app logs, verbose mpv), but
  /// [add] is a no-op until this is on, so nothing is recorded unless the user
  /// has opted in. The player also checks it before wiring a verbose logger
  /// (which has a real cost).
  bool enabled = false;

  /// The secrets the app holds, hidden wherever they turn up in a line.
  Set<String> _secrets = const {};

  /// The names of the user's own servers: where they live says who they are.
  Set<String> _hosts = const {};

  /// Tells the log which values must never appear in it: the sign-in token,
  /// API keys, passwords. Short ones are left out (they'd blank ordinary
  /// words). [addresses] are the user's servers: their host names are hidden
  /// too, and the rest of an address (scheme, port, path) stays readable.
  void protect(
    Iterable<String?> secrets, {
    Iterable<String?> addresses = const [],
  }) {
    _secrets = {
      for (final s in secrets)
        if (s != null && s.trim().length >= 6) s.trim(),
    };
    _hosts = {
      for (final a in addresses)
        if (a != null && a.trim().isNotEmpty)
          if (Uri.tryParse(a.contains('://') ? a.trim() : 'http://${a.trim()}')
              case final Uri u when u.host.length >= 4 && u.host != 'localhost')
            u.host,
    };
  }

  /// Append a line. No-ops unless [enabled], so global callers (error hooks,
  /// a teed debugPrint) can call unconditionally without leaking data or cost
  /// when diagnostics are off.
  void add(String source, String message) {
    if (!enabled) return;
    final line =
        '${DateTime.now().toIso8601String()} [$source] ${_safe(message)}';
    _lines.add(line);
    while (_lines.length > _max) {
      _lines.removeFirst();
    }
  }

  /// [text] with every credential in it hidden: by its shape, then by value.
  String _safe(String text) {
    var safe = redactSecrets(text);
    for (final s in _secrets) {
      safe = safe.replaceAll(s, '<redacted>');
      final encoded = Uri.encodeQueryComponent(s);
      if (encoded != s) safe = safe.replaceAll(encoded, '<redacted>');
    }
    for (final h in _hosts) {
      safe = safe.replaceAll(h, '<host>');
    }
    return safe;
  }

  bool get isEmpty => _lines.isEmpty;
  int get length => _lines.length;

  void clear() => _lines.clear();

  /// Build a shareable text report: an environment header, the caller-supplied
  /// [header] entries (app version, active server version, relevant prefs),
  /// then the captured log lines.
  String report(Map<String, Object?> header) {
    final b = StringBuffer();
    b.writeln('=== Fathom diagnostics ===');
    b.writeln('Captured: ${DateTime.now().toIso8601String()}');
    b.writeln(
        'Platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})');
    header.forEach((k, v) => b.writeln('$k: ${_safe('$v')}'));
    b.writeln('');
    b.writeln('--- Log (${_lines.length} lines) ---');
    for (final l in _lines) {
      b.writeln(l);
    }
    return b.toString();
  }
}

/// Strip credentials from a URL's query (api_key / token / password) before it
/// goes into a log the user may share. Leaves everything else intact so the
/// stream path, container, and transcode params stay readable.
String redactUrl(String url) {
  try {
    final u = Uri.parse(url);
    if (u.queryParameters.isEmpty) return url;
    final safe = <String, String>{};
    for (final e in u.queryParameters.entries) {
      final k = e.key.toLowerCase();
      final secret =
          k.contains('key') || k.contains('token') || k.contains('pass');
      safe[e.key] = secret ? '<redacted>' : e.value;
    }
    return u.replace(queryParameters: safe).toString();
  } catch (_) {
    return url;
  }
}

/// [text] with the credentials in it hidden, in whatever it quotes: an
/// address's query (`api_key=`, `apikey=`, `token=`, `password=`...), a
/// request header (`X-Api-Key:`, `X-Emby-Token:`, `Authorization:`,
/// `Cookie:`), or Jellyfin's `Token="..."`. What's around them stays, so the
/// line still says what was asked for.
String redactSecrets(String text) => text
    .replaceAllMapped(_secretHeader, (m) => '${m[1]}<redacted>')
    .replaceAllMapped(_secretQuoted, (m) => '${m[1]}<redacted>${m[2]}')
    .replaceAllMapped(_secretParam, (m) => '${m[1]}<redacted>');

final _secretParam = RegExp(
  r'((?<![A-Za-z])(?:api_?key|apikey|access_?token|token|passkey|password|passwd|pass|pwd|secret|sid|session_?id|auth)=)'
  r'''[^&\s"'<>\]\)]+''',
  caseSensitive: false,
);

final _secretQuoted = RegExp(
  r'((?:token|api_?key|password)\s*[=:]\s*")[^"]*(")',
  caseSensitive: false,
);

final _secretHeader = RegExp(
  r'((?:x-api-key|x-emby-token|x-mediabrowser-token|x-emby-authorization|authorization|proxy-authorization|cookie|set-cookie)\s*[:=]\s*)[^\r\n]+',
  caseSensitive: false,
);
