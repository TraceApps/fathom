import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../theme/app_theme.dart';
import 'app_snack.dart';
import 'app_spinner.dart';
import 'arr_tags.dart';
import 'arr_widgets.dart';
import 'context_menu.dart';
import 'detail_header.dart';
import 'hover_pill_button.dart';

/// Runs a change against Sonarr or Radarr and says how it went: [done] on
/// success, the app's own reason on failure. True when it worked.
Future<bool> arrRun(
  BuildContext context,
  Future<void> Function() action, {
  required String done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    showSnackOn(messenger, done, kind: SnackKind.success);
    return true;
  } catch (e) {
    showSnackOn(messenger, e.toString(), kind: SnackKind.error);
    return false;
  }
}

/// One action on a detail page, drawn as a round header button on wide
/// windows and as a labelled pill under the header on narrow ones.
class ArrAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;
  const ArrAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });
}

/// The actions of a title: the main ones as buttons, the rest behind More.
class ArrActionBar extends StatelessWidget {
  final List<ArrAction> main;
  final List<ArrAction> more;
  final bool header; // round buttons over the backdrop
  final String title;

  const ArrActionBar({
    super.key,
    required this.main,
    required this.more,
    required this.header,
    required this.title,
  });

  void _openMore(BuildContext context, BuildContext anchor) {
    final box = anchor.findRenderObject() as RenderBox?;
    final at = box == null
        ? Offset.zero
        : box.localToGlobal(box.size.bottomCenter(Offset.zero));
    showContextMenu(
      context,
      at: at,
      title: title,
      actions: [
        for (final a in more)
          ContextMenuAction(
            icon: a.icon,
            label: a.label,
            onTap: a.onTap,
            color: a.destructive ? Theme.of(context).colorScheme.error : null,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final buttons = <Widget>[
      for (final a in main)
        header
            ? HeaderActionButton(
                icon: a.icon,
                tooltip: a.label,
                primary: a.primary,
                onTap: a.onTap,
              )
            : HoverPillButton(
                icon: a.icon,
                label: a.label,
                primary: a.primary,
                onTap: a.onTap,
              ),
      if (more.isNotEmpty)
        Builder(
          builder: (anchor) => header
              ? HeaderActionButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: l.arrMore,
                  onTap: () => _openMore(context, anchor),
                )
              : HoverPillButton(
                  icon: Icons.more_horiz_rounded,
                  label: l.arrMore,
                  onTap: () => _openMore(context, anchor),
                ),
        ),
    ];
    if (header) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            buttons[i],
          ],
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: buttons,
    );
  }
}

/// The frame every Arr dialog shares: the title's backdrop with what the
/// dialog does over it, a scrolling body, and the buttons.
class ArrDialogFrame extends StatelessWidget {
  final ArrClient? client;
  final List<ArrImage> images;
  final String heading;
  final String title;
  final Widget body;
  final List<Widget> actions;

  const ArrDialogFrame({
    super.key,
    required this.client,
    required this.images,
    required this.heading,
    required this.title,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 116,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (images.isEmpty)
                    ColoredBox(color: scheme.surfaceContainerHighest)
                  else
                    ArrArt(
                      client: client,
                      images: images,
                      type: 'fanart',
                      width: 780,
                      placeholderIcon: Icons.image_rounded,
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            heading,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: body,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              // A long translation shrinks the buttons together rather than
              // overflowing, as in the Seerr request dialog.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled dropdown, the way every Arr form shows one.
class ArrDropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?>? onChanged;

  /// A line under the field, such as where its starting value came from.
  final String? helper;

  const ArrDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          DropdownButtonFormField<T>(
            initialValue: options.containsKey(value) ? value : null,
            isExpanded: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: helper,
              helperMaxLines: 2,
            ),
            items: [
              for (final e in options.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A checkbox with a line explaining it.
class ArrCheck extends StatelessWidget {
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const ArrCheck({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    dense: true,
    title: Text(label),
    subtitle: hint == null ? null : Text(hint!),
    value: value,
    onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
  );
}

// ------------------------------------------------------------------ Delete

/// Asks how to delete a movie or show, then deletes it. True when deleted.
Future<bool> showArrDeleteDialog(
  BuildContext context, {
  required ArrClient client,
  required int id,
  required String title,
  required List<ArrImage> images,
  required int sizeOnDisk,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _DeleteDialog(
      client: client,
      id: id,
      title: title,
      images: images,
      sizeOnDisk: sizeOnDisk,
    ),
  );
  return ok ?? false;
}

class _DeleteDialog extends StatefulWidget {
  final ArrClient client;
  final int id;
  final String title;
  final List<ArrImage> images;
  final int sizeOnDisk;
  const _DeleteDialog({
    required this.client,
    required this.id,
    required this.title,
    required this.images,
    required this.sizeOnDisk,
  });

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _files = false;
  bool _exclude = false;
  bool _busy = false;

  Future<void> _delete() async {
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    final c = widget.client;
    final ok = await arrRun(
      context,
      () => c is SonarrClient
          ? c.deleteSeries(
              widget.id,
              deleteFiles: _files,
              addExclusion: _exclude,
            )
          : (c as RadarrClient).deleteMovie(
              widget.id,
              deleteFiles: _files,
              addExclusion: _exclude,
            ),
      done: l.arrDeleted(widget.title),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final app = widget.client.kind.appName;
    return ArrDialogFrame(
      client: widget.client,
      images: widget.images,
      heading: l.commonDelete,
      title: widget.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.arrDeleteMessage(app)),
          const SizedBox(height: 8),
          ArrCheck(
            label: l.arrDeleteFiles,
            hint: widget.sizeOnDisk > 0
                ? l.arrDeleteFilesHint(arrSize(widget.sizeOnDisk))
                : null,
            value: _files,
            onChanged: _busy ? null : (v) => setState(() => _files = v),
          ),
          ArrCheck(
            label: l.arrPreventReadding,
            hint: l.arrPreventReaddingHint,
            value: _exclude,
            onChanged: _busy ? null : (v) => setState(() => _exclude = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle.merge(
            FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
          ),
          onPressed: _busy ? null : _delete,
          child: _busy ? const AppSpinner.inline() : Text(l.commonDelete),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- Edit

/// Edits a movie's or show's settings in place. True when saved.
Future<bool> showArrEditDialog(
  BuildContext context, {
  required ArrClient client,
  required int id,
  required String title,
  required List<ArrImage> images,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _EditDialog(client: client, id: id, title: title, images: images),
  );
  return ok ?? false;
}

class _EditDialog extends ConsumerStatefulWidget {
  final ArrClient client;
  final int id;
  final String title;
  final List<ArrImage> images;
  const _EditDialog({
    required this.client,
    required this.id,
    required this.title,
    required this.images,
  });

  @override
  ConsumerState<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends ConsumerState<_EditDialog> {
  Map<String, dynamic>? _raw;
  String? _error;
  bool _busy = false;
  final _path = TextEditingController();
  String _pathBefore = '';

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  bool get _sonarr => widget.client is SonarrClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = widget.client;
      final raw = c is SonarrClient
          ? await c.seriesRaw(widget.id)
          : await (c as RadarrClient).movieRaw(widget.id);
      if (!mounted) return;
      setState(() {
        _raw = raw;
        _pathBefore = (raw['path'] as String?) ?? '';
        _path.text = _pathBefore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _set(String key, Object? value) => setState(() => _raw![key] = value);

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final c = widget.client;
    // A cleared field keeps the old path; a trailing slash isn't a move.
    String bare(String p) => p.replaceAll(RegExp(r'[/\\]+$'), '');
    final typed = _path.text.trim();
    final path = typed.isEmpty || bare(typed) == bare(_pathBefore)
        ? _pathBefore
        : typed;
    var move = false;
    // Always from the field, so a failed save can't leave a path behind.
    _raw!['path'] = path;
    if (path != _pathBefore) {
      // As in Sonarr and Radarr: a new path asks whether to move the files.
      final answer = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.arrMoveFilesTitle),
          content: Text(l.arrMoveFilesMessage(_pathBefore, path)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.arrMoveFilesNo),
            ),
            FilledButton(
              style: kInlineButtonStyle,
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.arrMoveFilesYes),
            ),
          ],
        ),
      );
      if (answer == null || !mounted) return;
      move = answer;
    }
    setState(() => _busy = true);
    final ok = await arrRun(
      context,
      () => c is SonarrClient
          ? c.updateSeries(_raw!, moveFiles: move)
          : (c as RadarrClient).updateMovie(_raw!, moveFiles: move),
      done: l.arrSaved,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final raw = _raw;
    final profiles =
        ref
            .watch(arrQualityProfileListProvider(widget.client.kind))
            .asData
            ?.value ??
        const <ArrQualityProfile>[];
    Widget body;
    if (_error != null) {
      body = Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    } else if (raw == null) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: AppSpinner()),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A show's monitoring lives in its Monitoring dialog (with which
          // episodes, specials and new seasons); a movie has just the switch.
          if (!_sonarr) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.arrMonitored),
              subtitle: Text(l.arrMonitoredMovieHint),
              value: raw['monitored'] == true,
              onChanged: _busy ? null : (v) => _set('monitored', v),
            ),
            const SizedBox(height: 8),
          ],
          ArrDropdownField<int>(
            label: l.arrQualityProfile,
            value: (raw['qualityProfileId'] as num?)?.toInt(),
            options: {for (final p in profiles) p.id: p.name},
            onChanged: _busy
                ? null
                : (v) => v == null ? null : _set('qualityProfileId', v),
          ),
          if (_sonarr) ...[
            ArrDropdownField<String>(
              label: l.arrSeriesType,
              value: raw['seriesType'] as String?,
              options: arrSeriesTypes(l),
              onChanged: _busy
                  ? null
                  : (v) => v == null ? null : _set('seriesType', v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.arrSeasonFolders),
              value: raw['seasonFolder'] != false,
              onChanged: _busy ? null : (v) => _set('seasonFolder', v),
            ),
          ] else
            ArrDropdownField<String>(
              label: l.arrMinimumAvailability,
              value: raw['minimumAvailability'] as String?,
              options: arrAvailabilities(l),
              onChanged: _busy
                  ? null
                  : (v) => v == null ? null : _set('minimumAvailability', v),
            ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              l.arrPath,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextField(
            controller: _path,
            enabled: !_busy,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: l.arrPathHint,
            ),
          ),
          const SizedBox(height: 14),
          ArrTagPicker(
            client: widget.client,
            selected: [
              for (final t in (raw['tags'] as List?) ?? const [])
                if (t is num) t.toInt(),
            ],
            onChanged: _busy ? null : (ids) => _set('tags', ids),
          ),
        ],
      );
    }
    return ArrDialogFrame(
      client: widget.client,
      images: widget.images,
      heading: l.arrEdit,
      title: widget.title,
      body: body,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: _busy || raw == null ? null : _save,
          child: _busy ? const AppSpinner.inline() : Text(l.commonSave),
        ),
      ],
    );
  }
}

Map<String, String> arrSeriesTypes(AppLocalizations l) => {
  'standard': l.arrSeriesStandard,
  'daily': l.arrSeriesDaily,
  'anime': l.arrSeriesAnime,
};

Map<String, String> arrAvailabilities(AppLocalizations l) => {
  'announced': l.arrAnnounced,
  'inCinemas': l.arrInCinemas,
  'released': l.arrReleased,
};

// ------------------------------------------------------------------ Rename

/// Shows what renaming would change, then renames. True when started.
Future<bool> showArrRenameDialog(
  BuildContext context, {
  required ArrClient client,
  required int id,
  required String title,
  required List<ArrImage> images,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _RenameDialog(client: client, id: id, title: title, images: images),
  );
  return ok ?? false;
}

class _RenameDialog extends StatefulWidget {
  final ArrClient client;
  final int id;
  final String title;
  final List<ArrImage> images;
  const _RenameDialog({
    required this.client,
    required this.id,
    required this.title,
    required this.images,
  });

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final Future<List<ArrRename>> _preview = widget.client.renamePreview(
    widget.id,
  );
  // Asked only to explain an empty preview.
  late final Future<bool> _renamingOn = widget.client.renamingOn().catchError(
    (_) => true,
  );
  bool _busy = false;

  Future<void> _rename(List<ArrRename> files) async {
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    final ok = await arrRun(
      context,
      () => widget.client.rename(widget.id, [for (final f in files) f.fileId]),
      done: l.arrRenaming(files.length),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder<List<ArrRename>>(
      future: _preview,
      builder: (context, snap) {
        final files = snap.data;
        Widget body;
        if (snap.hasError) {
          body = Text(
            snap.error.toString(),
            style: TextStyle(color: scheme.error),
          );
        } else if (files == null) {
          body = const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: AppSpinner()),
          );
        } else if (files.isEmpty) {
          body = FutureBuilder<bool>(
            future: _renamingOn,
            builder: (context, on) => Text(
              on.data == false
                  ? l.arrRenamingOff(widget.client.kind.appName)
                  : l.arrRenameNothing,
            ),
          );
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final f in files)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.existingPath,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      Text(
                        f.newPath,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }
        return ArrDialogFrame(
          client: widget.client,
          images: widget.images,
          heading: l.arrRenameFiles,
          title: widget.title,
          body: body,
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: Text(
                files?.isEmpty ?? false ? l.arrClose : l.commonCancel,
              ),
            ),
            if (files?.isNotEmpty ?? false)
              FilledButton(
                style: kInlineButtonStyle,
                onPressed: _busy ? null : () => _rename(files!),
                child: _busy
                    ? const AppSpinner.inline()
                    : Text(l.arrRenameCount(files!.length)),
              ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------- Queue

/// Takes a download out of the queue, asking how. True when removed.
Future<bool> showArrQueueRemoveDialog(
  BuildContext context, {
  required ArrClient client,
  required ArrQueueItem item,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _QueueRemoveDialog(items: [item], clientFor: (_) => client),
  );
  return ok ?? false;
}

/// The same choices for several downloads, which may be from both apps.
Future<bool> showArrQueueRemoveManyDialog(
  BuildContext context, {
  required List<ArrQueueItem> items,
  required ArrClient? Function(ArrKind kind) clientFor,
}) async {
  if (items.isEmpty) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _QueueRemoveDialog(items: items, clientFor: clientFor),
  );
  return ok ?? false;
}

class _QueueRemoveDialog extends StatefulWidget {
  final List<ArrQueueItem> items;
  final ArrClient? Function(ArrKind kind) clientFor;
  const _QueueRemoveDialog({required this.items, required this.clientFor});

  @override
  State<_QueueRemoveDialog> createState() => _QueueRemoveDialogState();
}

class _QueueRemoveDialogState extends State<_QueueRemoveDialog> {
  // Some were removed before another app failed: the queue must refresh.
  bool _removedSome = false;
  // What happens in the download client, as the apps' own Removal Method:
  // remove it, move it to the post-import category, or leave it (ignore).
  String _method = 'remove';
  bool _blocklist = false;
  bool _searchAgain = false;
  bool _busy = false;

  Future<void> _remove() async {
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    final items = widget.items;
    final ok = await arrRun(context, () async {
      if (items.length == 1) {
        final c = widget.clientFor(items.single.kind);
        await c?.removeFromQueue(
          items.single.id,
          removeFromClient: _method == 'remove',
          changeCategory: _method == 'category',
          blocklist: _blocklist,
          searchAgain: _searchAgain,
        );
        return;
      }
      // One call per app; one failing doesn't stop the other.
      Object? failure;
      for (final kind in {for (final i in items) i.kind}) {
        try {
          await widget.clientFor(kind)?.removeManyFromQueue(
            [for (final i in items) if (i.kind == kind) i.id],
            removeFromClient: _method == 'remove',
            changeCategory: _method == 'category',
            blocklist: _blocklist,
            searchAgain: _searchAgain,
          );
          _removedSome = true;
        } catch (e) {
          failure ??= e;
        }
      }
      if (failure != null) throw failure;
    }, done: items.length == 1
        ? l.arrRemovedFromQueue
        : l.arrRemovedCount(items.length));
    if (!mounted) return;
    if (ok || _removedSome) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = widget.items;
    final item = items.first;
    final one = items.length == 1;
    // Named only when every one of them uses the same client.
    final clients = {for (final i in items) i.downloadClient};
    final client = clients.length == 1 ? clients.single : null;
    // The choices every picked download allows, as the apps decide them.
    final pending = items.every((i) => i.isPending);
    final methods = <String, String>{
      'remove': l.arrRemoveFromClient,
      if (items.every((i) => i.clientHasPostImportCategory))
        'category': l.arrChangeCategory,
      if (items.every((i) => i.canIgnore)) 'ignore': l.arrIgnoreDownload,
    };
    final method = methods.containsKey(_method) ? _method : 'remove';
    return ArrDialogFrame(
      client: widget.clientFor(item.kind),
      images: one ? item.images : const [],
      heading: one ? l.arrRemoveFromQueue : l.arrRemoveCount(items.length),
      title: one
          ? [item.mediaTitle ?? item.title, ?item.episodeCode].join(' · ')
          : {for (final i in items) i.mediaTitle ?? i.title}.join(', '),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (one)
            Text(
              item.title,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 8),
          // Held back (not sent yet): there's nothing in a client to touch.
          if (!pending)
            ArrDropdownField<String>(
              label: l.arrInDownloadClient,
              value: method,
              options: methods,
              helper: switch (method) {
                'category' => l.arrChangeCategoryHint,
                'ignore' => l.arrIgnoreDownloadHint,
                _ => client == null
                    ? l.arrRemoveFromClientHint
                    : l.arrRemoveFromNamedClientHint(client),
              },
              onChanged: _busy || methods.length < 2
                  ? null
                  : (v) => setState(() => _method = v ?? 'remove'),
            ),
          ArrCheck(
            label: l.arrBlocklistRelease,
            hint: l.arrBlocklistReleaseHint,
            value: _blocklist,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _blocklist = v;
                    if (!v) _searchAgain = false;
                  }),
          ),
          ArrCheck(
            label: l.arrSearchForAnother,
            hint: l.arrSearchForAnotherHint,
            value: _searchAgain,
            onChanged: _busy || !_blocklist
                ? null
                : (v) => setState(() => _searchAgain = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle.merge(
            FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
          ),
          onPressed: _busy ? null : _remove,
          child: _busy ? const AppSpinner.inline() : Text(l.arrRemove),
        ),
      ],
    );
  }
}
