part of 'arr_detail_screens.dart';

/// A refresh of an artist's page, by a pull or a key: Lidarr is asked for
/// it again.
void _askArtistAgain(WidgetRef ref, int id) {
  ref.invalidate(lidarrAlbumsProvider(id));
  ref.invalidate(lidarrTrackFilesProvider(id));
  ref.invalidate(lidarrTracksProvider);
  ref.invalidate(lidarrArtistHistoryProvider(id));
  ref.invalidate(lidarrArtistProvider(id));
  ref.invalidate(arrLibraryItemProvider);
}

/// The kinds of release an artist's page lists apart, in Lidarr's order.
/// Anything Lidarr calls something else goes with Other.
const _albumTypes = ['Album', 'EP', 'Single', 'Broadcast', 'Other'];

String _albumTypeOf(ArrAlbum a) =>
    _albumTypes.contains(a.albumType) ? a.albumType : 'Other';

/// An artist's albums by kind (albums, EPs, singles...), in Lidarr's order
/// of kinds, the newest of each first and those without a date last.
@visibleForTesting
List<(String, List<ArrAlbum>)> arrAlbumGroups(List<ArrAlbum> albums) {
  return [
    for (final type in _albumTypes)
      if (albums.any((a) => _albumTypeOf(a) == type))
        (
          type,
          arrNewestFirst(
            [for (final a in albums) if (_albumTypeOf(a) == type) a],
            (a) => a.releaseDate,
          ),
        ),
  ];
}

String _albumTypeHeading(AppLocalizations l, String type) => switch (type) {
  'Album' => l.arrAlbumTypeAlbums,
  'EP' => l.arrAlbumTypeEps,
  'Single' => l.arrAlbumTypeSingles,
  'Broadcast' => l.arrAlbumTypeBroadcasts,
  _ => l.arrAlbumTypeOther,
};

/// An artist in Lidarr: where it stands, its albums with their tracks, and
/// its history.
class ArrArtistScreen extends ConsumerWidget {
  final int id;
  const ArrArtistScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(lidarrClientProvider);
    final async = ref.watch(lidarrArtistProvider(id));
    final page = Scaffold(
      body: async.when(
        loading: () => const _LoadingPage(),
        error: (e, _) => _ErrorPage(
          message: e.toString(),
          onRetry: () => ref.invalidate(lidarrArtistProvider(id)),
        ),
        data: (a) {
          final theme = Theme.of(context);
          final profiles =
              ref
                  .watch(arrQualityProfilesProvider(ArrKind.lidarr))
                  .asData
                  ?.value ??
              const {};
          final metadata = {
            for (final p
                in ref.watch(lidarrMetadataProfilesProvider).asData?.value ??
                    const <ArrMetadataProfile>[])
              p.id: p.name,
          };
          final albums = ref.watch(lidarrAlbumsProvider(id));
          final files =
              ref.watch(lidarrTrackFilesProvider(id)).asData?.value ??
              const {};
          final history = ref.watch(lidarrArtistHistoryProvider(id));
          final meta = [
            ?a.artistType,
            if (a.genres.isNotEmpty) a.genres.take(2).join(', '),
          ].join(' · ');
          final wide = MediaQuery.sizeOf(context).width >= 620;
          final actions = _artistActions(
            context,
            ref,
            client,
            a,
            albums.asData?.value,
          );
          final groups = arrAlbumGroups(albums.asData?.value ?? const []);
          final count = albums.asData?.value.length ?? 0;
          final newAlbums = arrNewAlbumChoices(l)[a.monitorNewItems];
          return RefreshIndicator(
            onRefresh: () async {
              _askArtistAgain(ref, id);
              await ref.read(lidarrArtistProvider(id).future);
            },
            child: TvPageEnds(
              child: CustomScrollView(
                slivers: [
                  _Header(
                    client: client,
                    images: a.images,
                    title: a.name,
                    meta: meta,
                    status: Wrap(
                      spacing: 6,
                      children: [
                        if (!a.monitored)
                          ArrChip(
                            label: l.arrUnmonitored,
                            color: theme.colorScheme.outline,
                            onArt: true,
                          ),
                        if (a.monitored && a.missingTracks > 0)
                          ArrChip(
                            label: l.arrMissingTracks(a.missingTracks),
                            color: arrMissingColor,
                            onArt: true,
                          ),
                      ],
                    ),
                    placeholderIcon: Icons.library_music_rounded,
                    actions: wide ? actions(true) : null,
                  ),
                  SliverToBoxAdapter(
                    child: _Body(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!wide) actions(false),
                          SizedBox(height: a.overview != null ? 16 : 20),
                          // One stop for a TV's remote, before the albums.
                          ..._tvRead([
                            if (a.overview != null) ...[
                              Text(
                                a.overview!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                            ArrFact(
                              label: l.arrQualityProfile,
                              value: profiles[a.qualityProfileId] ?? '-',
                            ),
                            ArrFact(
                              label: l.arrMetadataProfile,
                              value: metadata[a.metadataProfileId] ?? '-',
                            ),
                            ArrFact(
                              label: l.arrMonitored,
                              value: a.monitored ? l.arrYes : l.arrNo,
                            ),
                            if (newAlbums != null)
                              ArrFact(
                                label: l.arrMonitorNewAlbums,
                                value: newAlbums,
                              ),
                            ArrFact(
                              label: l.arrFiles,
                              value: l.arrTracksOf(
                                a.trackFileCount,
                                a.trackCount,
                              ),
                            ),
                            if (a.path != null)
                              ArrFact(label: l.arrPath, value: a.path!),
                            ArrFact(
                              label: l.arrSizeOnDisk,
                              value: arrSize(a.sizeOnDisk),
                            ),
                            if (a.added != null && a.added!.year > 1)
                              ArrFact(
                                label: l.arrAdded,
                                value: arrDate(context, a.added!),
                              ),
                          ]),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  if (albums.hasError)
                    SliverToBoxAdapter(
                      child: _Body(
                        child: ErrorView(
                          message: albums.error.toString(),
                          onRetry: () =>
                              ref.invalidate(lidarrAlbumsProvider(id)),
                        ),
                      ),
                    )
                  else if (!albums.hasValue)
                    const SliverToBoxAdapter(
                      child: _Body(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: _BlocksSkeleton(height: 64),
                      ),
                    )
                  else if (count == 0)
                    SliverToBoxAdapter(
                      child: _Body(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Text(
                          l.arrNoAlbums,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final (type, list) in groups) ...[
                      // Named only when there's more than one kind: a page of
                      // nothing but albums needn't say so.
                      if (groups.length > 1)
                        SliverToBoxAdapter(
                          child: _Body(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                            child: Text(
                              _albumTypeHeading(l, type),
                              style: arrSectionStyle(theme),
                            ),
                          ),
                        ),
                      SliverList.builder(
                        // A kind that comes or goes doesn't shift the others.
                        key: ValueKey('albums$type'),
                        itemCount: list.length,
                        // By album: a refresh that brings a new one keeps
                        // the open album open.
                        findChildIndexCallback: (key) {
                          final at = list.indexWhere(
                            (a) => key == ValueKey('album${a.id}'),
                          );
                          return at < 0 ? null : at;
                        },
                        itemBuilder: (context, i) => _Body(
                          key: ValueKey('album${list[i].id}'),
                          child: _AlbumTile(
                            client: client,
                            artist: a,
                            album: list[i],
                            files: files,
                            // One album: open, as there's nothing to choose.
                            initiallyExpanded: count == 1,
                          ),
                        ),
                      ),
                    ],
                  SliverToBoxAdapter(
                    child: _Body(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                      child: _HistorySection(history: history),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return ArrRefreshKeys(
      // Beside a list, the section's own keys ask again.
      onRefresh: ArrPaneHost.of(context) != null
          ? null
          : () => _askArtistAgain(ref, id),
      child: page,
    );
  }
}

/// An artist's actions; call with true for the header's round buttons.
Widget Function(bool header) _artistActions(
  BuildContext context,
  WidgetRef ref,
  LidarrClient? client,
  ArrArtist a,
  List<ArrAlbum>? albums,
) {
  final l = AppLocalizations.of(context);
  if (client == null) return (_) => const SizedBox.shrink();
  void changed() => arrArtistChanged(ref, a.id);
  final play = _watchAction(context, ref, arrLibraryKeyOfArtist(a));
  final main = [
    ?play,
    ArrAction(
      icon: Icons.search_rounded,
      label: l.arrSearchMonitored,
      primary: play == null,
      onTap: () => arrRun(
        context,
        () => client.searchArtist(a.id),
        done: l.arrSearchStarted(client.kind.appName),
      ),
    ),
    // Lidarr's artist switch and its album options in one place, as a
    // show's Monitoring is.
    ArrAction(
      icon: a.monitored
          ? Icons.bookmark_rounded
          : Icons.bookmark_border_rounded,
      label: l.arrMonitoring,
      pinned: true,
      onTap: () async {
        if (await showArrArtistMonitoringDialog(
          context,
          client: client,
          artist: a,
          albums: albums,
        )) {
          changed();
        }
      },
    ),
    ArrAction(
      icon: Icons.edit_rounded,
      label: l.arrEdit,
      onTap: () async {
        if (await showArrEditDialog(
          context,
          client: client,
          id: a.id,
          title: a.name,
          images: a.images,
        )) {
          changed();
        }
      },
    ),
  ];
  final more = [
    ArrAction(
      icon: Icons.sync_rounded,
      label: l.arrRefreshScan,
      onTap: () async {
        if (await arrRun(
          context,
          () => client.refreshArtist(a.id),
          done: l.arrRefreshStarted(client.kind.appName),
        )) {
          Future.delayed(const Duration(seconds: 4), changed);
        }
      },
    ),
    // Files dropped in the artist's folder that Lidarr hasn't taken in.
    if (!isTvDevice && a.path != null && a.path!.isNotEmpty)
      ArrAction(
        icon: Icons.drive_folder_upload_rounded,
        label: l.arrManualImport,
        onTap: () async {
          final imported = await context.push<bool>(
            ArrImportTarget.folder(ArrKind.lidarr, a.path!).location,
          );
          if (imported == true) changed();
        },
      ),
    // Renaming files is for a phone or a desktop, not a remote.
    if (!isTvDevice && a.trackFileCount > 0)
      ArrAction(
        icon: Icons.drive_file_rename_outline_rounded,
        label: l.arrRenameFiles,
        onTap: () async {
          if (await showArrRenameDialog(
            context,
            client: client,
            id: a.id,
            title: a.name,
            images: a.images,
          )) {
            Future.delayed(const Duration(seconds: 3), changed);
          }
        },
      ),
    if (!isTvDevice && a.foreignArtistId != null)
      ArrAction(
        icon: Icons.open_in_new_rounded,
        label: l.arrOpenIn(client.kind.appName),
        onTap: () => _openIn(client, a.foreignArtistId),
      ),
    ArrAction(
      icon: Icons.delete_rounded,
      label: l.commonDelete,
      destructive: true,
      onTap: () async {
        if (await showArrDeleteDialog(
              context,
              client: client,
              id: a.id,
              title: a.name,
              images: a.images,
              sizeOnDisk: a.sizeOnDisk,
            ) &&
            context.mounted) {
          ref.invalidate(lidarrArtistsProvider);
          _leave(context);
        }
      },
    ),
  ];
  return (header) =>
      ArrActionBar(main: main, more: more, header: header, title: a.name);
}

/// An album of an artist, opening into its tracks. The tracks are asked for
/// when it opens: a long discography is one call, its tracks one per album.
class _AlbumTile extends ConsumerWidget {
  final LidarrClient? client;
  final ArrArtist artist;
  final ArrAlbum album;
  final Map<int, ArrFile> files;
  final bool initiallyExpanded;

  const _AlbumTile({
    required this.client,
    required this.artist,
    required this.album,
    required this.files,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = client;
    final out = album.released(DateTime.now());
    final date = album.releaseDate;
    final color = !album.monitored
        ? scheme.outline
        : album.complete
        ? arrDownloadedColor
        : !out
        ? arrUnreleasedColor
        : arrMissingColor;
    final about = [
      if (date != null) out ? '${date.year}' : l.arrOut(arrDate(context, date)),
      l.arrTracksOf(album.trackFileCount, album.totalTrackCount),
      if (album.sizeOnDisk > 0) arrSize(album.sizeOnDisk),
      ...album.secondaryTypes,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          shape: const Border(),
          tilePadding: const EdgeInsetsDirectional.only(start: 12, end: 8),
          // On a TV the remote goes album to album, and RIGHT steps onto an
          // album's own buttons.
          leading: TvRowActions(
            child: IconButton(
              tooltip: album.monitored ? l.arrUnmonitor : l.arrMonitor,
              icon: Icon(
                album.monitored
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: album.monitored ? scheme.primary : scheme.outline,
              ),
              onPressed: c == null
                  ? null
                  : () async {
                      if (await arrRun(
                        context,
                        () => c.setAlbumsMonitored([
                          album.id,
                        ], !album.monitored),
                        done: album.monitored
                            ? l.arrNowUnmonitored
                            : l.arrNowMonitored,
                      )) {
                        arrArtistChanged(ref, artist.id);
                      }
                    },
            ),
          ),
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox.square(
                  dimension: 44,
                  child: ArrArt(
                    client: c,
                    images: album.images,
                    type: 'cover',
                    width: 120,
                    decodeWidth: 120,
                    placeholderIcon: Icons.album_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      about,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: album.progress,
                    minHeight: 5,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              if (c != null) ...[
                TvRowActions(
                  child: IconButton(
                    tooltip: l.arrSearchAlbum,
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () => arrRun(
                      context,
                      () => c.searchAlbums([album.id]),
                      done: l.arrSearchStarted(c.kind.appName),
                    ),
                  ),
                ),
                TvRowActions(
                  child: Builder(
                    builder: (anchor) => IconButton(
                      tooltip: l.arrAlbumActions,
                      icon: const Icon(Icons.more_vert_rounded),
                      onPressed: () => _openMenu(context, ref, anchor, c),
                    ),
                  ),
                ),
              ],
            ],
          ),
          children: [
            _AlbumTracks(
              client: c,
              artist: artist,
              album: album,
              files: files,
            ),
          ],
        ),
      ),
    );
  }

  /// The album's other actions: Interactive Search, and deleting its files.
  void _openMenu(
    BuildContext context,
    WidgetRef ref,
    BuildContext anchor,
    LidarrClient c,
  ) {
    final l = AppLocalizations.of(context);
    final box = anchor.findRenderObject() as RenderBox?;
    final at = box == null
        ? Offset.zero
        : box.localToGlobal(box.size.bottomCenter(Offset.zero));
    final albumFiles = [
      for (final f in files.values)
        if (f.albumId == album.id) f,
    ];
    showContextMenu(
      context,
      at: at,
      title: album.title,
      actions: [
        ContextMenuAction(
          icon: Icons.manage_search_rounded,
          label: l.arrInteractiveSearch,
          onTap: () =>
              context.push(ArrReleaseTarget.album(album.id).location),
        ),
        if (!isTvDevice && albumFiles.isNotEmpty)
          ContextMenuAction(
            icon: Icons.delete_sweep_rounded,
            label: l.arrDeleteAlbumFiles,
            color: Theme.of(context).colorScheme.error,
            onTap: () async {
              final go = await confirm(
                context,
                title: l.arrDeleteAlbumFiles,
                message: l.arrDeleteAlbumFilesMessage(
                  albumFiles.length,
                  album.title,
                  c.kind.appName,
                ),
                confirmLabel: l.commonDelete,
                destructive: true,
              );
              if (!go || !context.mounted) return;
              if (await arrRun(
                context,
                () => c.deleteTrackFiles([for (final f in albumFiles) f.id]),
                done: l.arrFilesDeleted(albumFiles.length),
              )) {
                arrArtistChanged(ref, artist.id);
              }
            },
          ),
      ],
    );
  }
}

/// An open album's tracks, side by side with the files Lidarr has of them.
/// A release on more than one disc lists each disc under its number.
class _AlbumTracks extends ConsumerWidget {
  final LidarrClient? client;
  final ArrArtist artist;
  final ArrAlbum album;
  final Map<int, ArrFile> files;

  const _AlbumTracks({
    required this.client,
    required this.artist,
    required this.album,
    required this.files,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tracks = ref.watch(lidarrTracksProvider(album.id));
    if (tracks.hasError && !tracks.hasValue) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ErrorView(
          message: tracks.error.toString(),
          onRetry: () => ref.invalidate(lidarrTracksProvider(album.id)),
        ),
      );
    }
    final list = tracks.asData?.value;
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: _BlocksSkeleton(height: 36),
      );
    }
    final sorted = [...list]
      ..sort((a, b) {
        final disc = a.mediumNumber.compareTo(b.mediumNumber);
        return disc != 0
            ? disc
            : a.absoluteTrackNumber.compareTo(b.absoluteTrackNumber);
      });
    final discs = {for (final t in sorted) t.mediumNumber};
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, t) in sorted.indexed) ...[
          if (discs.length > 1 &&
              (i == 0 || sorted[i - 1].mediumNumber != t.mediumNumber))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
              child: Text(
                l.arrDisc(t.mediumNumber),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          _TrackRow(
            client: client,
            artist: artist,
            album: album,
            track: t,
            file: t.trackFileId == null ? null : files[t.trackFileId],
            out: album.released(now),
          ),
        ],
        const SizedBox(height: 6),
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  final LidarrClient? client;
  final ArrArtist artist;
  final ArrAlbum album;
  final ArrTrack track;
  final ArrFile? file;
  final bool out;

  const _TrackRow({
    required this.client,
    required this.artist,
    required this.album,
    required this.track,
    required this.file,
    required this.out,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A track has no switch of its own in Lidarr: its album's stands.
    final (String label, Color color) = track.hasFile
        ? (file?.quality ?? l.arrDownloaded, arrDownloadedColor)
        : !album.monitored
        ? (l.arrUnmonitored, scheme.outline)
        : out
        ? (l.arrMissing, arrMissingColor)
        : (l.arrNotReleased, arrUnreleasedColor);
    final length = track.duration;
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 34,
        child: Text(
          track.trackNumber.isNotEmpty
              ? track.trackNumber
              : '${track.absoluteTrackNumber}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: length == null ? null : Text(arrTrackLength(length)),
      trailing: ArrChip(label: label, color: color),
      onTap: () => _showTrack(context, client, artist, album, track, file),
    );
  }
}

/// "4:42", "1:02:05": a track's length as a player shows it.
@visibleForTesting
String arrTrackLength(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

void _showTrack(
  BuildContext context,
  LidarrClient? client,
  ArrArtist artist,
  ArrAlbum album,
  ArrTrack t,
  ArrFile? file,
) {
  final l = AppLocalizations.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // A remote has nothing to drag: on a TV the sheet opens tall.
    showDragHandle: !isTvDevice,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final theme = Theme.of(context);
        final c = client;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: isTvDevice ? 0.92 : 0.6,
          maxChildSize: 0.92,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(20, isTvDevice ? 24 : 0, 20, 28),
            children: [
              Text(
                [
                  album.title,
                  if (t.trackNumber.isNotEmpty) l.arrTrackNumber(t.trackNumber),
                ].join(' · '),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                t.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (t.duration != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    arrTrackLength(t.duration!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Text(l.arrFile, style: arrSectionStyle(theme)),
              const SizedBox(height: 8),
              if (file != null) ...[
                TvReadStop(child: ArrFileCard(file: file)),
                // Deleting a file is for a phone or a desktop.
                if (c != null && !isTvDevice)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _DeleteFileButton(
                      fileName: (file.path ?? '').split('/').last,
                      app: c.kind.appName,
                      delete: () => c.deleteTrackFiles([file.id]),
                      after: () {
                        arrArtistChanged(ref, artist.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
              ] else
                Text(
                  l.arrNoFile,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
