/// What a notification is about, for its icon/colour and grouping.
enum AppNotifKind {
  seerrNewRequest,
  seerrApproved,
  seerrDeclined,
  seerrAvailable,
  downloadComplete,
  // Manage: Sonarr, Radarr or Lidarr downloaded, failed, grabbed, or found a
  // health problem.
  arrImported,
  arrFailed,
  arrGrabbed,
  arrHealth,
  updateAvailable,
  info,
}

/// One entry in the in-app notification centre. Persisted, so the bell survives
/// a restart and collects events even when the desktop toast was missed.
class AppNotif {
  final String id;
  final AppNotifKind kind;
  final String title;
  final String body;
  final DateTime time;
  final bool read;

  /// Optional in-app destination to open when tapped (e.g. '/downloads').
  final String? route;

  /// The go_router `extra` for [route] (e.g. which tab to land on). Only
  /// JSON-primitive values (int/String/bool) survive a restart — that covers
  /// every real use so far; a route needing more should carry an id in the
  /// route path instead of a complex extra.
  final Object? routeExtra;

  const AppNotif({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.time,
    this.read = false,
    this.route,
    this.routeExtra,
  });

  AppNotif copyWith({bool? read}) => AppNotif(
        id: id,
        kind: kind,
        title: title,
        body: body,
        time: time,
        read: read ?? this.read,
        route: route,
        routeExtra: routeExtra,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'body': body,
        'time': time.toIso8601String(),
        'read': read,
        if (route != null) 'route': route,
        if (routeExtra != null) 'routeExtra': routeExtra,
      };

  factory AppNotif.fromJson(Map<String, dynamic> j) => AppNotif(
        id: j['id'] as String? ?? '',
        kind: AppNotifKind.values.firstWhere(
            (k) => k.name == j['kind'], orElse: () => AppNotifKind.info),
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        time: DateTime.tryParse(j['time'] as String? ?? '') ?? DateTime(2020),
        read: j['read'] == true,
        route: j['route'] as String?,
        routeExtra: j['routeExtra'],
      );
}
