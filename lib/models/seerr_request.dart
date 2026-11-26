/// A media request from Seerr.
class SeerrRequest {
  final int id;
  final int requestStatus; // 1 pending, 2 approved, 3 declined
  final String mediaType; // 'movie' | 'tv'
  final int tmdbId;
  final int? mediaStatus; // 1 unknown..5 available
  final int? mediaId; // Jellyseerr media record id (for remove-from-arr)
  final int? tvdbId; // a show's TVDB id, which is how Sonarr knows it
  final String? requestedBy;
  final int? requestedById; // the requester's user id, for "Request As"
  final String? requestedByAvatar; // raw avatar value, resolved at display
  final String? modifiedBy;
  final String? modifiedByAvatar;
  final String? createdAt; // ISO
  final String? updatedAt; // ISO
  final List<int> seasons; // requested season numbers (TV)

  // Advanced options, for editing a pending request.
  final bool is4k;
  final int? serverId;
  final int? profileId;
  final String? rootFolder;
  final int? languageProfileId;
  final List<int> tags;

  const SeerrRequest({
    required this.id,
    required this.requestStatus,
    required this.mediaType,
    required this.tmdbId,
    this.mediaStatus,
    this.mediaId,
    this.tvdbId,
    this.requestedBy,
    this.requestedById,
    this.requestedByAvatar,
    this.modifiedBy,
    this.modifiedByAvatar,
    this.createdAt,
    this.updatedAt,
    this.seasons = const [],
    this.is4k = false,
    this.serverId,
    this.profileId,
    this.rootFolder,
    this.languageProfileId,
    this.tags = const [],
  });

  bool get isPending => requestStatus == 1;
  bool get isDeclined => requestStatus == 3;
  bool get isFailed => requestStatus == 4;

  factory SeerrRequest.fromJson(Map<String, dynamic> j) {
    final media = (j['media'] as Map?)?.cast<String, dynamic>() ?? const {};
    final by = (j['requestedBy'] as Map?)?.cast<String, dynamic>();
    final mod = (j['modifiedBy'] as Map?)?.cast<String, dynamic>();
    return SeerrRequest(
      id: (j['id'] as num?)?.toInt() ?? 0,
      requestStatus: (j['status'] as num?)?.toInt() ?? 1,
      mediaType: media['mediaType'] as String? ?? 'movie',
      tmdbId: (media['tmdbId'] as num?)?.toInt() ?? 0,
      mediaStatus: (media['status'] as num?)?.toInt(),
      mediaId: (media['id'] as num?)?.toInt(),
      tvdbId: (media['tvdbId'] as num?)?.toInt(),
      requestedBy: by?['displayName'] as String? ?? by?['username'] as String?,
      requestedById: (by?['id'] as num?)?.toInt(),
      requestedByAvatar: by?['avatar'] as String?,
      modifiedBy: mod?['displayName'] as String? ?? mod?['username'] as String?,
      modifiedByAvatar: mod?['avatar'] as String?,
      createdAt: j['createdAt'] as String?,
      updatedAt: j['updatedAt'] as String?,
      seasons: [
        for (final s in (j['seasons'] as List?) ?? const [])
          if (s is Map && s['seasonNumber'] != null)
            (s['seasonNumber'] as num).toInt(),
      ],
      is4k: j['is4k'] == true,
      serverId: (j['serverId'] as num?)?.toInt(),
      profileId: (j['profileId'] as num?)?.toInt(),
      rootFolder: j['rootFolder'] as String?,
      languageProfileId: (j['languageProfileId'] as num?)?.toInt(),
      tags: [
        for (final t in (j['tags'] as List?) ?? const [])
          if (t is num) t.toInt(),
      ],
    );
  }
}
