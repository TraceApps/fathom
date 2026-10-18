import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/seerr_detail.dart';
import '../models/seerr_options.dart';
import '../models/seerr_result.dart';
import '../state/preferences.dart';
import '../state/seerr_providers.dart';
import '../theme/app_theme.dart';
import 'cached_image.dart';
import 'seerr_avatar.dart';
import 'app_snack.dart';
import 'app_spinner.dart';

/// Jellyseerr's request flow: a backdrop header, a per-season table for a
/// series, and the advanced options (4K, server, quality/language profile,
/// root folder, tags, and who to request as).
///
/// Returns true if a request was made.
Future<bool> showSeerrRequestDialog(
  BuildContext context,
  SeerrResult result, {
  List<int>? seasons,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _SeerrRequestDialog(result: result, seasons: seasons),
  );
  return ok ?? false;
}

class _SeerrRequestDialog extends ConsumerStatefulWidget {
  final SeerrResult result;
  final List<int>? seasons;
  const _SeerrRequestDialog({required this.result, this.seasons});

  @override
  ConsumerState<_SeerrRequestDialog> createState() =>
      _SeerrRequestDialogState();
}

class _SeerrRequestDialogState extends ConsumerState<_SeerrRequestDialog> {
  List<SeerrUser> _users = const [];
  List<SeerrServer> _servers = const [];
  SeerrServerOptions _opts = SeerrServerOptions.empty;

  int? _serverId;
  int? _profileId;
  int? _rootFolderId; // resolved to a path on submit
  int? _languageProfileId;
  int? _userId;
  bool _is4k = false;
  final Set<int> _selectedTags = {};

  bool _loading = true;
  bool _switching = false; // reloading options for a different server
  bool _busy = false;

  List<SeerrSeason> _seasons = const [];
  final Set<int> _selectedSeasons = {};
  String? _backdropUrl;

  // A per-user (Jellyfin/local) sign-in: the "request as" admin override
  // doesn't apply and must never be sent (see the note in _load).
  bool get _isCookieMode =>
      ref.read(preferencesProvider).asData?.value.seerrAuthMode == 'cookie';

  bool get _isTv => widget.result.mediaType == 'tv';
  List<SeerrSeason> get _requestable =>
      _seasons.where((s) => !s.isAvailable && !s.isRequested).toList();
  bool get _hasSeasonChoice => _requestable.isNotEmpty;
  bool get _needsSeason => _isTv && _hasSeasonChoice;
  bool get _has4k => _servers.any((s) => s.is4k);
  List<SeerrServer> get _serversForMode =>
      _servers.where((s) => s.is4k == _is4k).toList();

  @override
  void initState() {
    super.initState();
    _backdropUrl = widget.result.backdropUrl;
    _load();
  }

  Future<void> _load() async {
    final client = ref.read(seerrClientProvider);
    if (client == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      // "Request as another user" is an admin-only Jellyseerr feature: the
      // /user list endpoint needs admin permissions, and the request endpoint
      // rejects a userId field from a plain per-user session even when it
      // matches the caller's own id ("needs an api key"). So a signed-in
      // (cookie) user never sees or sends this — the server already attributes
      // the request to them from the session. Only the admin API key mode
      // fetches the user list and offers the picker.
      final results = await Future.wait([
        _isCookieMode ? Future.value(<SeerrUser>[]) : client.requestUsers(),
        client.servers(widget.result.mediaType),
        if (_isTv)
          client
              .detail(mediaType: 'tv', tmdbId: widget.result.tmdbId)
              .then<SeerrDetail?>((d) => d, onError: (_) => null),
      ]);
      final users = results[0] as List<SeerrUser>;
      final servers = results[1] as List<SeerrServer>;
      final detail = _isTv ? results[2] as SeerrDetail? : null;

      // Load the default (non-4K) server's options up front.
      final server = _pickServer(servers, is4k: false);
      final opts = server == null
          ? SeerrServerOptions.empty
          : await client.serverOptions(widget.result.mediaType, server.id);
      if (!mounted) return;
      setState(() {
        _users = users;
        _servers = servers;
        _userId = (!_isCookieMode && users.isNotEmpty) ? users.first.id : null;
        _serverId = server?.id;
        _opts = opts;
        _applyDefaults();
        _seasons = detail?.seasons ?? const [];
        _backdropUrl = detail?.backdropUrl ?? _backdropUrl;
        _selectedSeasons
          ..clear()
          ..addAll(widget.seasons ?? const []);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  SeerrServer? _pickServer(List<SeerrServer> servers, {required bool is4k}) {
    final pool = servers.where((s) => s.is4k == is4k).toList();
    if (pool.isEmpty) return null;
    return pool.firstWhere((s) => s.isDefault, orElse: () => pool.first);
  }

  void _applyDefaults() {
    _profileId = _opts.defaultProfileId;
    _languageProfileId = _opts.defaultLanguageProfileId;
    _selectedTags.clear();
    // Match the server's active directory to a root-folder id.
    _rootFolderId = _opts.rootFolders
        .cast<SeerrRootFolder?>()
        .firstWhere((r) => r?.path == _opts.defaultRootFolder,
            orElse: () => _opts.rootFolders.isNotEmpty
                ? _opts.rootFolders.first
                : null)
        ?.id;
  }

  Future<void> _selectServer(int? id, {bool? is4k}) async {
    final client = ref.read(seerrClientProvider);
    if (client == null) return;
    setState(() {
      _switching = true;
      if (is4k != null) _is4k = is4k;
      _serverId = id;
    });
    final opts = id == null
        ? SeerrServerOptions.empty
        : await client.serverOptions(widget.result.mediaType, id);
    if (!mounted) return;
    setState(() {
      _opts = opts;
      _applyDefaults();
      _switching = false;
    });
  }

  Future<void> _toggle4k(bool v) async {
    final server = _pickServer(_servers, is4k: v);
    await _selectServer(server?.id, is4k: v);
  }

  Future<void> _submit() async {
    final client = ref.read(seerrClientProvider);
    if (client == null || _busy) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final rootFolder = _opts.rootFolders
          .cast<SeerrRootFolder?>()
          .firstWhere((r) => r?.id == _rootFolderId, orElse: () => null)
          ?.path;
      await client.request(
        mediaType: widget.result.mediaType,
        tmdbId: widget.result.tmdbId,
        seasons: _hasSeasonChoice
            ? (_selectedSeasons.toList()..sort())
            : widget.seasons,
        is4k: _is4k,
        serverId: _serverId,
        profileId: _profileId,
        rootFolder: rootFolder,
        languageProfileId: _isTv ? _languageProfileId : null,
        // Never sent for a signed-in (cookie) user: Jellyseerr treats userId as
        // an admin override and rejects it from a per-user session even when
        // it's their own id, so the server attributes the request to them
        // from the session instead.
        userId: _isCookieMode ? null : _userId,
        tags: _selectedTags.toList(),
      );
      if (mounted) Navigator.pop(context, true);
      showSnackOn(messenger, l.detailRequestedTitle(widget.result.title),
          kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        !_busy && !_loading && !(_needsSeason && _selectedSeasons.isEmpty);

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(child: AppSpinner()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(context),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: _body(context),
                    ),
                  ),
                  _actions(context, canSubmit),
                ],
              ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 116,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surfaceContainerHighest),
          if (_backdropUrl != null)
            CachedImage(
                url: _backdropUrl!, errorBuilder: (_) => const SizedBox()),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.78),
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
                    _isTv ? l.detailRequestSeries : l.detailRequestMovie,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(widget.result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final serverOptions = _serversForMode;
    // The admin API key auto-approves; a signed-in user follows their perms.
    final autoApproves = !_isCookieMode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (autoApproves)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(l.detailAutoApprove)),
              ],
            ),
          ),
        if (_has4k) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l.detailRequestIn4k),
            subtitle: Text(l.detailRequest4kSubtitle),
            value: _is4k,
            onChanged: _switching ? null : _toggle4k,
          ),
        ],
        if (_isTv) _seasonTable(context),
        const SizedBox(height: 20),
        Text(l.detailAdvanced,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (_switching)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (serverOptions.length > 1) ...[
          const SizedBox(height: 12),
          _label(l.detailDestinationServer),
          _dropdown<int>(
            value: _serverId,
            items: [
              for (final s in serverOptions)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: _switching ? null : (v) => _selectServer(v),
          ),
        ],
        if (_opts.profiles.isNotEmpty) ...[
          const SizedBox(height: 16),
          _label(l.detailQualityProfile),
          _dropdown<int>(
            value: _profileId,
            items: [
              for (final p in _opts.profiles)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(p.id == _opts.defaultProfileId
                      ? l.detailProfileDefault(p.name)
                      : p.name),
                ),
            ],
            onChanged: (v) => setState(() => _profileId = v),
          ),
        ],
        if (_opts.rootFolders.isNotEmpty) ...[
          const SizedBox(height: 16),
          _label(l.detailRootFolder),
          _dropdown<int>(
            value: _rootFolderId,
            items: [
              for (final r in _opts.rootFolders)
                DropdownMenuItem(value: r.id, child: Text(r.path)),
            ],
            onChanged: (v) => setState(() => _rootFolderId = v),
          ),
        ],
        if (_isTv && _opts.languageProfiles.isNotEmpty) ...[
          const SizedBox(height: 16),
          _label(l.detailLanguageProfile),
          _dropdown<int>(
            value: _languageProfileId,
            items: [
              for (final p in _opts.languageProfiles)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(p.id == _opts.defaultLanguageProfileId
                      ? l.detailProfileDefault(p.name)
                      : p.name),
                ),
            ],
            onChanged: (v) => setState(() => _languageProfileId = v),
          ),
        ],
        if (_opts.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          _label(l.detailTags),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in _opts.tags)
                FilterChip(
                  label: Text(t.label),
                  selected: _selectedTags.contains(t.id),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _selectedTags.add(t.id);
                    } else {
                      _selectedTags.remove(t.id);
                    }
                  }),
                ),
            ],
          ),
        ],
        if (_users.length > 1) ...[
          const SizedBox(height: 16),
          _label(l.detailRequestAs),
          _dropdown<int>(
            value: _userId,
            selectedItemBuilder: (context) => [
              for (final u in _users)
                Row(children: [
                  SeerrAvatar(name: u.name, avatarUrl: u.avatarUrl, radius: 12),
                  const SizedBox(width: 10),
                  Flexible(
                      child: Text(u.name, overflow: TextOverflow.ellipsis)),
                ]),
            ],
            items: [
              for (final u in _users)
                DropdownMenuItem(
                  value: u.id,
                  child: Row(children: [
                    SeerrAvatar(
                        name: u.name, avatarUrl: u.avatarUrl, radius: 12),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        u.email == null ? u.name : '${u.name} (${u.email})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() => _userId = v),
          ),
        ],
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );

  Widget _dropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    List<Widget> Function(BuildContext)? selectedItemBuilder,
  }) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        selectedItemBuilder: selectedItemBuilder,
        items: items,
        onChanged: onChanged,
      );

  Widget _seasonTable(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_seasons.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(l.detailAllSeasonsRequested,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      );
    }
    final requestable = _requestable;
    final allSelected = requestable.isNotEmpty &&
        requestable.every((s) => _selectedSeasons.contains(s.seasonNumber));

    Widget headerCell(String text, {int flex = 1}) => Expanded(
          flex: flex,
          child: Text(text,
              style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(
                children: [
                  _CompactSwitch(
                    value: allSelected,
                    onChanged: requestable.isEmpty
                        ? null
                        : (_) => setState(() {
                              if (allSelected) {
                                _selectedSeasons.clear();
                              } else {
                                _selectedSeasons
                                  ..clear()
                                  ..addAll(
                                      requestable.map((s) => s.seasonNumber));
                              }
                            }),
                  ),
                  headerCell(l.detailColSeason, flex: 4),
                  headerCell(l.detailColEpisodes, flex: 3),
                  headerCell(l.detailColStatus, flex: 3),
                ],
              ),
            ),
            for (final s in _seasons) _seasonRow(context, s),
          ],
        ),
      ),
    );
  }

  Widget _seasonRow(BuildContext context, SeerrSeason s) {
    final theme = Theme.of(context);
    final locked = s.isAvailable || s.isRequested;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          _CompactSwitch(
            value: locked ? true : _selectedSeasons.contains(s.seasonNumber),
            onChanged: locked
                ? null
                : (v) => setState(() {
                      if (v) {
                        _selectedSeasons.add(s.seasonNumber);
                      } else {
                        _selectedSeasons.remove(s.seasonNumber);
                      }
                    }),
          ),
          Expanded(
              flex: 4,
              child:
                  Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: 3,
              child:
                  Text('${s.episodeCount}', style: theme.textTheme.bodyMedium)),
          Expanded(
              flex: 3,
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: _statusPill(context, s))),
        ],
      ),
    );
  }

  Widget _statusPill(BuildContext context, SeerrSeason s) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (label, bg, fg) = s.isAvailable
        ? (l.detailStatusAvailable, const Color(0x3322C55E),
            const Color(0xFF22C55E))
        : s.isRequested
            ? (l.detailRequested, const Color(0x33F59E0B),
                const Color(0xFFF59E0B))
            : (l.detailStatusNotRequested, scheme.secondaryContainer,
                scheme.onSecondaryContainer);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _actions(BuildContext context, bool canSubmit) {
    final l = AppLocalizations.of(context);
    final label = _needsSeason && _selectedSeasons.isEmpty
        ? l.detailSelectSeasons
        : l.detailRequest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      // Scale-safe: "Select Seasons" is already the longest of these
      // labels in English, and a longer translation could outgrow a narrow
      // phone's width even inside this dialog's own cap, so shrink together
      // (both stay fully readable, just smaller) rather than hard-overflowing.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: Text(l.commonCancel)),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: kInlineButtonStyle,
              onPressed: canSubmit ? _submit : null,
              icon: _busy
                  ? AppSpinner.inline()
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

/// A slightly smaller switch, so the season table's toggles don't dominate.
class _CompactSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _CompactSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      child: Transform.scale(
        scale: 0.78,
        alignment: Alignment.centerLeft,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
