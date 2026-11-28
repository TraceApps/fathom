import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/radio_station.dart';
import '../routing/app_shell.dart';
import '../services/tv_mode.dart';
import '../state/audio_player.dart';
import '../state/radio.dart';
import '../widgets/cached_image.dart';
import '../widgets/context_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/motion.dart';
import '../widgets/reorder.dart';
import '../widgets/search_field.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/ui_common.dart';

/// Internet radio: your saved stations (favorites first, then by group), a
/// radio-browser.info directory search to discover and add stations, and
/// add-by-URL. Tapping a station plays it through the shared audio stack.
class RadioScreen extends ConsumerStatefulWidget {
  const RadioScreen({super.key});

  @override
  ConsumerState<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends ConsumerState<RadioScreen> {
  final _searchCtrl = TextEditingController();
  List<RadioStation> _results = const [];
  bool _searching = false;
  Timer? _searchDebounce;
  // false = My Stations (saved), true = Browse (radio-browser directory search).
  bool _browse = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Search as you type (like every other search box), debounced since it hits
  // the external radio-browser directory.
  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    final r = await ref.read(radioControllerProvider.notifier).search(q);
    if (mounted) {
      setState(() {
        _results = r;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(radioControllerProvider);
    final stations = async.asData?.value ?? const <RadioStation>[];
    final playingId =
        ref.watch(audioControllerProvider.select((a) => a.radioStation?.id));

    return Scaffold(
      appBar: AppBar(
        leading: mobileLeading(context),
        title: Text(l.radioTitle),
        actions: [
          IconButton(
            tooltip: l.radioAddByUrl,
            icon: const Icon(Icons.add_link_rounded),
            onPressed: () => _addByUrl(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _SlidingTabs(
              value: _browse,
              leftIcon: Icons.library_music_rounded,
              leftLabel: l.radioTabMyStations,
              rightIcon: Icons.travel_explore_rounded,
              rightLabel: l.radioTabBrowse,
              onChanged: (v) => setState(() => _browse = v),
            ),
          ),
          if (_browse)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SearchField(
                controller: _searchCtrl,
                hint: l.radioSearchHint,
                autofocus: true,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _runSearch(),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              // Top-align (the default centres children, which left a big gap
              // above a short, content-sized My Stations list).
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: [
                  ...previousChildren,
                  ?currentChild,
                ],
              ),
              transitionBuilder: (child, animation) {
                // Slide the tabs past each other: Browse (right tab) enters from
                // the right, My Stations (left tab) from the left; the outgoing
                // one slides off the opposite edge. Fades along the way.
                final incoming = child.key == ValueKey(_browse);
                final sign = _browse ? 1.0 : -1.0;
                final begin = Offset(incoming ? sign : -sign, 0);
                return ClipRect(
                  child: SlideTransition(
                    position: Tween(begin: begin, end: Offset.zero)
                        .animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_browse),
                child: _browse
                    ? _directoryResults(l)
                    : _savedStations(l, stations, playingId),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _directoryResults(AppLocalizations l) {
    if (_searching) {
      return const Center(child: AppSpinner());
    }
    if (_searchCtrl.text.trim().isEmpty) {
      return EmptyState(
          icon: Icons.travel_explore_rounded, title: l.radioSearchPrompt);
    }
    if (_results.isEmpty) {
      return EmptyState(icon: Icons.radio_rounded, title: l.radioNoResults);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final s = _results[i];
        return _StationTile(
          station: s,
          playing: false,
          // On TV the trailing "+" is unreachable (the row is one focus target),
          // so hide it there and surface Add in the select sheet instead.
          trailing: isTvDevice
              ? null
              : IconButton(
                  tooltip: l.radioAdd,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: () async {
                    await ref.read(radioControllerProvider.notifier).add(s);
                    if (context.mounted) {
                      showSnack(context, l.radioAdded(s.name),
                          kind: SnackKind.success);
                    }
                  },
                ),
          // TV: selecting opens Play/Add sheet. Elsewhere, tapping a browse
          // result previews it (plays now) without saving; use + to add it.
          onTap: isTvDevice
              ? () => _showStationSheet(s, saved: false)
              : () => ref.read(audioControllerProvider.notifier).playStation(s),
        );
      },
    );
  }

  Widget _savedStations(
      AppLocalizations l, List<RadioStation> stations, String? playingId) {
    if (stations.isEmpty) {
      return EmptyState(
        icon: Icons.radio_rounded,
        title: l.radioNoStations,
        message: l.radioNoStationsSub,
      );
    }
    final favorites = stations.where((s) => s.favorite).toList();
    final groups = <String, List<RadioStation>>{};
    final ungrouped = <RadioStation>[];
    for (final s in stations) {
      // A favorite is listed once, under Favorites: listed again under its
      // group (or Other) it read as the station saved twice.
      if (s.favorite) continue;
      if (s.group != null && s.group!.isNotEmpty) {
        groups.putIfAbsent(s.group!, () => []).add(s);
      } else {
        ungrouped.add(s);
      }
    }
    final groupNames = groups.keys.toList()..sort();

    // Each section is its own reorderable list, so dragging rearranges stations
    // WITHIN a section (Favorites / a group / Other) and never across them. Uses
    // the same ReorderableListView the Home/Navigation editors use (drops
    // correctly), shrink-wrapped and non-scrolling inside the page scroll view.
    final sections = <Widget>[];
    void section(String? label, List<RadioStation> items,
        {Widget? headerTrailing}) {
      if (items.isEmpty) return;
      if (label != null) {
        sections.add(_sectionHeader(label, trailing: headerTrailing));
      }
      sections.add(ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: items.length,
        // ignore: deprecated_member_use
        onReorder: (o, n) => _onReorder(items, o, n),
        itemBuilder: (context, i) => _tile(items[i], playingId, dragIndex: i),
      ));
    }

    if (favorites.isNotEmpty) section(l.radioFavorites, favorites);
    for (final g in groupNames) {
      section(g, groups[g]!, headerTrailing: _groupMenu(g));
    }
    if (ungrouped.isNotEmpty) {
      section(
          groupNames.isNotEmpty || favorites.isNotEmpty
              ? l.radioUngrouped
              : null,
          ungrouped);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sections,
      ),
    );
  }

  void _onReorder(List<RadioStation> bucket, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final ids = bucket.map((s) => s.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    ref.read(radioControllerProvider.notifier).reorderBucket(ids);
  }

  Widget _sectionHeader(String label, {Widget? trailing}) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, trailing == null ? 16 : 4, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary)),
            ),
            ?trailing,
          ],
        ),
      );

  /// Overflow menu on a group header: rename the group or delete it (moving its
  /// stations to Other, keeping the stations).
  Widget _groupMenu(String group) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // A pencil (not the station rows' vertical ⋮) so a group-level action
    // reads as distinct: "manage this group", not "options for a station".
    return Builder(builder: (btnContext) {
      return IconButton(
        tooltip: l.radioGroupOptions,
        icon:
            Icon(Icons.edit_rounded, size: 18, color: scheme.onSurfaceVariant),
        splashRadius: 20,
        onPressed: () {
          final box = btnContext.findRenderObject() as RenderBox?;
          final at = box == null
              ? Offset.zero
              : box.localToGlobal(box.size.center(Offset.zero));
          showContextMenu(context, at: at, actions: [
            ContextMenuAction(
              icon: Icons.drive_file_rename_outline_rounded,
              label: l.radioRenameGroup,
              onTap: () => _renameGroup(group),
            ),
            ContextMenuAction(
              icon: Icons.delete_outline_rounded,
              label: l.radioDeleteGroup,
              onTap: () => _deleteGroup(group),
            ),
          ]);
        },
      );
    });
  }

  Future<void> _renameGroup(String group) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameGroupDialog(initial: group),
    );
    if (name != null && name.isNotEmpty && name != group) {
      await ref.read(radioControllerProvider.notifier).renameGroup(group, name);
    }
  }

  Future<void> _deleteGroup(String group) async {
    final l = AppLocalizations.of(context);
    final ok = await confirm(context,
        title: l.radioDeleteGroup,
        message: l.radioDeleteGroupBody(group),
        confirmLabel: l.commonRemove,
        destructive: true);
    if (ok) {
      await ref.read(radioControllerProvider.notifier).deleteGroup(group);
    }
  }

  Widget _tile(RadioStation s, String? playingId, {int? dragIndex}) {
    final di = dragIndex;
    final tile = _StationTile(
      station: s,
      playing: s.id == playingId,
      // The dots are just a "this moves" hint; the whole row is draggable
      // (wrapped below), so you can grab a station from anywhere on it.
      dragHandle: di == null
          ? null
          : Icon(Icons.drag_indicator, color: dragGripColor(context)),
      trailing: isTvDevice
          ? null
          : Builder(builder: (btnContext) {
              return IconButton(
                tooltip: AppLocalizations.of(context).commonMore,
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () {
                  final box = btnContext.findRenderObject() as RenderBox?;
                  _openStationMenu(
                      s,
                      box == null
                          ? Offset.zero
                          : box.localToGlobal(box.size.center(Offset.zero)));
                },
              );
            }),
      // TV: selecting opens the Play/Favorite/Group/Edit/Remove sheet, since the
      // row's ⋮ can't be reached with a remote.
      onTap: isTvDevice
          ? () => _showStationSheet(s, saved: true)
          : () => ref.read(audioControllerProvider.notifier).playStation(s),
      onOpenMenu: isTvDevice ? null : (at) => _openStationMenu(s, at),
      // Rows in this section are already draggable from anywhere on touch (a
      // long-press starts the drag); a competing long-press-for-menu recognizer
      // would fight it for the gesture. Right-click never conflicts (it's a
      // separate mouse button from the drag-start press), so that stays on.
      allowLongPressMenu: di == null,
    );
    if (di == null) return KeyedSubtree(key: ValueKey(s.id), child: tile);
    // Drag from anywhere on the row (press-drag on desktop, long-press on touch).
    return dragAnywhere(key: ValueKey(s.id), index: di, child: tile);
  }

  Future<void> _openStationMenu(RadioStation s, Offset at) async {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    await showContextMenu(context, at: at, title: s.name, actions: [
      ContextMenuAction(
        icon: s.favorite
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
        label: s.favorite ? l.radioUnfavorite : l.radioFavorite,
        onTap: () => _onAction('favorite', s),
      ),
      ContextMenuAction(
        icon: Icons.folder_rounded,
        label: l.radioSetGroup,
        onTap: () => _onAction('group', s),
      ),
      ContextMenuAction(
        icon: Icons.edit_rounded,
        label: l.commonEdit,
        onTap: () => _onAction('edit', s),
      ),
      ContextMenuAction(
        icon: Icons.delete_outline_rounded,
        label: l.commonRemove,
        color: cs.error,
        onTap: () => _onAction('remove', s),
      ),
    ]);
  }

  Future<void> _onAction(String action, RadioStation s) async {
    final ctrl = ref.read(radioControllerProvider.notifier);
    switch (action) {
      case 'favorite':
        await ctrl.toggleFavorite(s.id);
      case 'group':
        await _setGroup(context, s);
      case 'edit':
        await _edit(context, s);
      case 'remove':
        await ctrl.remove(s.id);
    }
  }

  /// TV action sheet for a station. A remote can't reach the row's trailing "+"
  /// or ⋮ (the whole row is one focus target), so selecting a station opens
  /// this: Play first, then Add (browse results) or the manage actions (saved).
  Future<void> _showStationSheet(RadioStation s, {required bool saved}) async {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(s.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              autofocus: true,
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text(l.commonPlay),
              onTap: () => Navigator.of(ctx).pop('play'),
            ),
            if (!saved)
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: Text(l.radioAdd),
                onTap: () => Navigator.of(ctx).pop('add'),
              ),
            if (saved) ...[
              ListTile(
                leading: Icon(s.favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded),
                title:
                    Text(s.favorite ? l.radioUnfavorite : l.radioFavorite),
                onTap: () => Navigator.of(ctx).pop('favorite'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(l.radioSetGroup),
                onTap: () => Navigator.of(ctx).pop('group'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text(l.commonEdit),
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
              const Divider(),
              ListTile(
                leading:
                    Icon(Icons.delete_outline_rounded, color: scheme.error),
                title: Text(l.commonRemove,
                    style: TextStyle(color: scheme.error)),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
            ],
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen == 'play') {
      ref.read(audioControllerProvider.notifier).playStation(s);
    } else if (chosen == 'add') {
      await ref.read(radioControllerProvider.notifier).add(s);
      if (mounted) {
        showSnack(context, l.radioAdded(s.name), kind: SnackKind.success);
      }
    } else {
      await _onAction(chosen, s);
    }
  }

  Future<void> _addByUrl(BuildContext context) async {
    final station = await showDialog<RadioStation>(
      context: context,
      builder: (_) => const _AddByUrlDialog(),
    );
    if (station != null) {
      await ref.read(radioControllerProvider.notifier).add(station);
    }
  }

  Future<void> _edit(BuildContext context, RadioStation s) async {
    final updated = await showDialog<RadioStation>(
      context: context,
      builder: (_) => _EditStationDialog(station: s),
    );
    if (updated != null) {
      await ref.read(radioControllerProvider.notifier).updateStation(updated);
    }
  }

  Future<void> _setGroup(BuildContext context, RadioStation s) async {
    final existing = ref.read(radioControllerProvider.notifier).groups;
    // Returns '' to clear the group, a name to set it, or null on cancel.
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _SetGroupDialog(initial: s.group ?? '', existing: existing),
    );
    if (result != null) {
      await ref.read(radioControllerProvider.notifier).updateStation(
          s.copyWith(group: result.isEmpty ? null : result));
    }
  }
}

/// A row for a station: logo (or a radio glyph), name, and a subtitle of group
/// / tags / country, with a playing indicator or a supplied trailing control.
class _StationTile extends StatelessWidget {
  final RadioStation station;
  final bool playing;
  final Widget? trailing;
  final Widget? dragHandle;
  final VoidCallback onTap;
  // Right-click / long-press opens the same menu as the trailing "⋮" button,
  // matching every other item row in the app. Null where the row has no menu
  // to offer (a browse-search result only has a single "+" action).
  final void Function(Offset at)? onOpenMenu;
  final bool allowLongPressMenu;
  const _StationTile({
    required this.station,
    required this.playing,
    required this.onTap,
    this.trailing,
    this.dragHandle,
    this.onOpenMenu,
    this.allowLongPressMenu = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = [
      if (station.group != null && station.group!.isNotEmpty) station.group!,
      if (station.country != null && station.country!.isNotEmpty)
        station.country!,
      if (station.tags != null && station.tags!.isNotEmpty)
        station.tags!.split(',').take(2).join(', '),
    ].join(' · ');
    final logo = SizedBox(
      width: 44,
      height: 44,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: station.favicon != null
            ? CachedImage(
                url: station.favicon!,
                // Disk-cached, so a station's logo loads instantly on the second
                // visit to the radio screen instead of re-downloading every time.
                placeholder: _fallback(scheme),
                errorBuilder: (_) => _fallback(scheme),
              )
            : _fallback(scheme),
      ),
    );
    final tile = TvFocusRing(
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        // Drag grip (when reorderable) sits at the very left, before the logo,
        // consistent with the Navigation screen.
        leading: dragHandle == null
            ? logo
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [dragHandle!, const SizedBox(width: 6), logo],
              ),
        title: Text(station.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: sub.isEmpty
            ? null
            : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: playing
            ? Icon(Icons.graphic_eq_rounded, color: scheme.primary)
            : trailing,
        onTap: onTap,
      ),
    );
    if (onOpenMenu == null || isTvDevice) return tile;
    final openMenu = onOpenMenu!;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onLongPressStart:
          allowLongPressMenu ? (d) => openMenu(d.globalPosition) : null,
      onSecondaryTapUp: (d) => openMenu(d.globalPosition),
      child: tile,
    );
  }

  Widget _fallback(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.radio_rounded, color: scheme.onSurfaceVariant),
      );
}

/// A two-option segmented toggle whose selected "pill" slides between the two
/// choices, matching the tab content's slide. Text/icon colours cross-fade as
/// the pill passes under them.
class _SlidingTabs extends StatelessWidget {
  final bool value; // false = left, true = right
  final IconData leftIcon;
  final String leftLabel;
  final IconData rightIcon;
  final String rightLabel;
  final ValueChanged<bool> onChanged;
  const _SlidingTabs({
    required this.value,
    required this.leftIcon,
    required this.leftLabel,
    required this.rightIcon,
    required this.rightLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dur = reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(23),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          return Stack(
            children: [
              // The sliding selection pill.
              AnimatedAlign(
                duration: dur,
                curve: Curves.easeOutCubic,
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: c.maxWidth / 2,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(19),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _seg(scheme, dur, leftIcon, leftLabel,
                        selected: !value, onTap: () => onChanged(false)),
                  ),
                  Expanded(
                    child: _seg(scheme, dur, rightIcon, rightLabel,
                        selected: value, onTap: () => onChanged(true)),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _seg(ColorScheme scheme, Duration dur, IconData icon, String label,
      {required bool selected, required VoidCallback onTap}) {
    final seg = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          duration: dur,
          curve: Curves.easeOut,
          tween: Tween(begin: 0, end: selected ? 1 : 0),
          builder: (context, t, _) {
            final color =
                Color.lerp(scheme.onSurfaceVariant, scheme.onPrimary, t)!;
            // Center the icon+label as a group: a Flexible in a full-width Row
            // eats the free space, so center it with a min-width Row instead.
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
          },
        ),
      );
    if (!isTvDevice) return seg;
    return TvFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      scale: 1.03,
      child: seg,
    );
  }
}

/// Rename-group dialog. Owns its own controller so it's disposed when the dialog
/// unmounts (after the exit animation) — disposing it synchronously right after
/// showDialog() returns crashed the tree (`_dependents.isEmpty`).
/// Add a station by URL. Owns its controllers (disposed on unmount) so it can't
/// hit the "_dependents.isEmpty" crash from disposing them mid-teardown.
class _AddByUrlDialog extends StatefulWidget {
  const _AddByUrlDialog();

  @override
  State<_AddByUrlDialog> createState() => _AddByUrlDialogState();
}

class _AddByUrlDialogState extends State<_AddByUrlDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _add() {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    final name = _name.text.trim();
    Navigator.pop(
      context,
      RadioStation(id: url, name: name.isEmpty ? url : name, url: url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.radioAddByUrl),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TvTextField(
            controller: _name,
            label: l.radioStationName,
          ),
          const SizedBox(height: 12),
          TvTextField(
            controller: _url,
            label: l.radioStreamUrl,
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _add(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(onPressed: _add, child: Text(l.commonAdd)),
      ],
    );
  }
}

/// Set/clear a station's group, with chips for the groups already in use. Owns
/// its controller so it's disposed safely on unmount.
class _SetGroupDialog extends StatefulWidget {
  final String initial;
  final List<String> existing;
  const _SetGroupDialog({required this.initial, required this.existing});

  @override
  State<_SetGroupDialog> createState() => _SetGroupDialogState();
}

class _SetGroupDialogState extends State<_SetGroupDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.radioSetGroup),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvTextField(
            controller: _ctrl,
            label: l.radioGroup,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => Navigator.pop(context, _ctrl.text.trim()),
          ),
          if (widget.existing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in widget.existing)
                  ActionChip(
                      label: Text(g),
                      onPressed: () => Navigator.pop(context, g)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(l.commonCancel)),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: Text(l.commonSave)),
      ],
    );
  }
}

/// Edit a saved station: name, stream URL, logo, genre, and homepage. Owns its
/// controllers (disposed on unmount), and returns the updated [RadioStation].
class _EditStationDialog extends StatefulWidget {
  final RadioStation station;
  const _EditStationDialog({required this.station});

  @override
  State<_EditStationDialog> createState() => _EditStationDialogState();
}

class _EditStationDialogState extends State<_EditStationDialog> {
  late final _name = TextEditingController(text: widget.station.name);
  late final _url = TextEditingController(text: widget.station.url);
  late final _logo = TextEditingController(text: widget.station.favicon ?? '');
  late final _genre = TextEditingController(text: widget.station.tags ?? '');
  late final _home = TextEditingController(text: widget.station.homepage ?? '');

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _logo.dispose();
    _genre.dispose();
    _home.dispose();
    super.dispose();
  }

  void _save() {
    final s = widget.station;
    final url = _url.text.trim();
    if (url.isEmpty) return;
    final name = _name.text.trim();
    final logo = _logo.text.trim();
    final genre = _genre.text.trim();
    final home = _home.text.trim();
    // Build directly (not copyWith) so cleared optional fields become null.
    Navigator.pop(
      context,
      RadioStation(
        id: s.id,
        name: name.isEmpty ? s.name : name,
        url: url,
        homepage: home.isEmpty ? null : home,
        favicon: logo.isEmpty ? null : logo,
        group: s.group,
        favorite: s.favorite,
        tags: genre.isEmpty ? null : genre,
        country: s.country,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget field(TextEditingController c, String label, {bool url = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TvTextField(
            controller: c,
            label: label,
            keyboardType: url ? TextInputType.url : null,
          ),
        );
    return AlertDialog(
      title: Text(l.commonEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(_name, l.radioStationName),
            field(_url, l.radioStreamUrl, url: true),
            field(_logo, l.radioLogoUrl, url: true),
            field(_genre, l.radioGenre),
            field(_home, l.radioHomepage, url: true),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(onPressed: _save, child: Text(l.commonSave)),
      ],
    );
  }
}

class _RenameGroupDialog extends StatefulWidget {
  final String initial;
  const _RenameGroupDialog({required this.initial});

  @override
  State<_RenameGroupDialog> createState() => _RenameGroupDialogState();
}

class _RenameGroupDialogState extends State<_RenameGroupDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.radioRenameGroup),
      content: TvTextField(
        controller: _ctrl,
        label: l.radioGroup,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => Navigator.pop(context, _ctrl.text.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel)),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: Text(l.commonSave)),
      ],
    );
  }
}
