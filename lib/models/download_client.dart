// What the download clients behind Sonarr, Radarr and Lidarr say:
// qBittorrent's torrents and SABnzbd's queue and history, in one shape.

/// A download client Fathom talks to directly.
enum DownloadClientKind {
  qbittorrent('qBittorrent'),
  sabnzbd('SABnzbd');

  final String appName;
  const DownloadClientKind(this.appName);
}

/// How a download is doing, across both clients.
enum DownloadState {
  downloading,

  /// Finding the torrent's details from its peers (a magnet link), or
  /// SABnzbd fetching an NZB.
  fetching,

  /// Downloading, but nothing's coming in: no peers to take it from.
  stalled,
  queued,
  paused,
  checking,
  moving,

  /// Done, and shared with others (a torrent).
  seeding,

  /// Done: a stopped torrent, finished.
  done,
  failed,
}

/// One download in a client's list.
class DownloadItem {
  final DownloadClientKind client;

  /// The torrent's hash, or SABnzbd's job id.
  final String id;
  final String name;
  final DownloadState state;

  /// 0 to 1.
  final double progress;

  /// Bytes in all; 0 while a torrent's details aren't known yet.
  final int size;

  /// Bytes still to come.
  final int left;

  /// Bytes a second; SABnzbd says this for the queue as a whole only.
  final int? downSpeed;
  final int? upSpeed;

  /// Time to go, when the client knows it.
  final Duration? eta;
  final String? category;

  /// A torrent's share ratio, and who it's connected to.
  final double? ratio;
  final int? seeds;
  final int? peers;
  final DateTime? added;

  /// What's wrong, when it failed.
  final String? problem;

  /// SABnzbd's priority: Force, High, Normal, Low.
  final String? priority;

  const DownloadItem({
    required this.client,
    required this.id,
    required this.name,
    required this.state,
    this.progress = 0,
    this.size = 0,
    this.left = 0,
    this.downSpeed,
    this.upSpeed,
    this.eta,
    this.category,
    this.ratio,
    this.seeds,
    this.peers,
    this.added,
    this.problem,
    this.priority,
  });

  /// Stopped by hand: a resume starts it again.
  bool get paused =>
      state == DownloadState.paused || state == DownloadState.done;

  /// qBittorrent's answer for one torrent (torrents/info).
  factory DownloadItem.fromQbit(Map<String, dynamic> j) {
    final state = j['state'] as String? ?? '';
    final eta = _int(j['eta']);
    final size = _int(j['size']);
    return DownloadItem(
      client: DownloadClientKind.qbittorrent,
      id: j['hash'] as String? ?? '',
      name: j['name'] as String? ?? '',
      state: qbitState(state),
      progress: _double(j['progress']).clamp(0, 1).toDouble(),
      // A magnet link's size is -1 until its details come in.
      size: size < 0 ? 0 : size,
      left: _int(j['amount_left']),
      downSpeed: _int(j['dlspeed']),
      upSpeed: _int(j['upspeed']),
      // 8640000 (100 days) is qBittorrent's "never".
      eta: eta > 0 && eta < 8640000 ? Duration(seconds: eta) : null,
      category: _text(j['category']),
      ratio: j['ratio'] is num ? (j['ratio'] as num).toDouble() : null,
      seeds: j['num_seeds'] is num ? _int(j['num_seeds']) : null,
      peers: j['num_leechs'] is num ? _int(j['num_leechs']) : null,
      added: _epoch(j['added_on']),
      problem: switch (state) {
        'missingFiles' => 'missingFiles',
        'error' => 'error',
        _ => null,
      },
    );
  }

  /// SABnzbd's answer for one job in its queue.
  factory DownloadItem.fromSab(
    Map<String, dynamic> j, {
    bool queuePaused = false,
  }) {
    final mb = _double(j['mb']);
    final left = _double(j['mbleft']);
    final status = j['status'] as String? ?? '';
    final s = sabState(status);
    return DownloadItem(
      client: DownloadClientKind.sabnzbd,
      id: j['nzo_id'] as String? ?? '',
      name: j['filename'] as String? ?? '',
      // The whole queue paused holds every job, whatever its own status.
      state: queuePaused && s == DownloadState.downloading
          ? DownloadState.queued
          : s,
      progress: (_double(j['percentage']) / 100).clamp(0, 1).toDouble(),
      size: (mb * _mib).round(),
      left: (left * _mib).round(),
      eta: s == DownloadState.downloading && !queuePaused
          ? sabDuration(j['timeleft'])
          : null,
      category: _text(j['cat']) == '*' ? null : _text(j['cat']),
      added: _epoch(j['time_added']),
      priority: _text(j['priority']),
    );
  }

  static const _mib = 1024 * 1024;
}

/// qBittorrent's torrent states (both the 5.x "stopped" names and the
/// older "paused" ones).
DownloadState qbitState(String s) => switch (s) {
  'downloading' || 'forcedDL' || 'allocating' => DownloadState.downloading,
  'metaDL' || 'forcedMetaDL' => DownloadState.fetching,
  'stalledDL' => DownloadState.stalled,
  'queuedDL' || 'queuedUP' => DownloadState.queued,
  'stoppedDL' || 'pausedDL' => DownloadState.paused,
  'stoppedUP' || 'pausedUP' => DownloadState.done,
  'uploading' || 'forcedUP' || 'stalledUP' => DownloadState.seeding,
  'checkingDL' ||
  'checkingUP' ||
  'checkingResumeData' => DownloadState.checking,
  'moving' => DownloadState.moving,
  'error' || 'missingFiles' => DownloadState.failed,
  _ => DownloadState.queued,
};

/// SABnzbd's job states in its queue.
DownloadState sabState(String s) => switch (s) {
  'Downloading' => DownloadState.downloading,
  'Paused' => DownloadState.paused,
  'Grabbing' || 'Fetching' => DownloadState.fetching,
  'Checking' ||
  'QuickCheck' ||
  'Verifying' ||
  'Repairing' => DownloadState.checking,
  'Extracting' || 'Moving' || 'Running' => DownloadState.moving,
  'Completed' => DownloadState.done,
  'Failed' => DownloadState.failed,
  _ => DownloadState.queued,
};

/// SABnzbd's "1:02:03" or "2:01:02:03" (with days), as a duration; null
/// for nothing left to time.
Duration? sabDuration(Object? v) {
  if (v is! String) return null;
  final parts = [for (final p in v.split(':')) int.tryParse(p)];
  if (parts.isEmpty || parts.length > 4 || parts.contains(null)) return null;
  var seconds = 0;
  const units = [86400, 3600, 60, 1];
  final n = parts.length;
  for (var i = 0; i < n; i++) {
    seconds += parts[i]! * units[4 - n + i];
  }
  return seconds > 0 ? Duration(seconds: seconds) : null;
}

/// A finished job in SABnzbd's history: done, or failed and why.
class DownloadHistoryItem {
  final DownloadClientKind client;
  final String id;
  final String name;
  final DownloadState state;
  final String status;
  final String? problem;
  final int size;
  final DateTime? completed;
  final String? category;

  /// SABnzbd can try it again.
  final bool canRetry;

  const DownloadHistoryItem({
    required this.client,
    required this.id,
    required this.name,
    required this.state,
    required this.status,
    this.problem,
    this.size = 0,
    this.completed,
    this.category,
    this.canRetry = false,
  });

  bool get failed => state == DownloadState.failed;

  factory DownloadHistoryItem.fromSab(Map<String, dynamic> j) {
    final status = j['status'] as String? ?? '';
    return DownloadHistoryItem(
      client: DownloadClientKind.sabnzbd,
      id: j['nzo_id'] as String? ?? '',
      name: _text(j['name']) ?? _text(j['nzb_name']) ?? '',
      state: sabState(status),
      status: status,
      problem: _text(j['fail_message']),
      size: _int(j['bytes']),
      completed: _epoch(j['completed']),
      category: _text(j['category']) == '*' ? null : _text(j['category']),
      canRetry: j['retry'] == true || j['retry'] == 1,
    );
  }
}

/// How a client is doing as a whole: its speeds, whether it's all paused,
/// and its speed limit.
class DownloadClientSummary {
  final DownloadClientKind client;
  final int downSpeed;
  final int upSpeed;

  /// The whole client paused (SABnzbd's queue).
  final bool paused;

  /// qBittorrent's alternative speed limits are on.
  final bool slowMode;

  /// qBittorrent's alternative download limit, bytes a second (0: none).
  final int slowDownLimit;

  /// SABnzbd's speed limit, bytes a second (0: none).
  final int speedLimit;

  /// SABnzbd's free space where it downloads, in bytes.
  final int? freeSpace;

  /// qBittorrent's connection: connected, firewalled or disconnected.
  final String? connection;

  const DownloadClientSummary({
    required this.client,
    this.downSpeed = 0,
    this.upSpeed = 0,
    this.paused = false,
    this.slowMode = false,
    this.slowDownLimit = 0,
    this.speedLimit = 0,
    this.freeSpace,
    this.connection,
  });
}

/// One client's list and its summary, as the page shows them.
typedef DownloadClientState = ({
  DownloadClientSummary summary,
  List<DownloadItem> items,
});

int _int(Object? v) => switch (v) {
  num n => n.toInt(),
  String s => int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? 0,
  _ => 0,
};

double _double(Object? v) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};

String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

DateTime? _epoch(Object? v) {
  final s = _int(v);
  return s > 0 ? DateTime.fromMillisecondsSinceEpoch(s * 1000) : null;
}

/// Parsers kept for the client: SABnzbd says numbers as text.
int downloadInt(Object? v) => _int(v);
double downloadDouble(Object? v) => _double(v);
