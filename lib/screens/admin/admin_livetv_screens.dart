import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/error_text.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/admin_providers.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../widgets/page_width.dart';
import '../../widgets/format.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/tv_keyboard.dart';
import '../../widgets/ui_common.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/app_spinner.dart';
import '../../api/jellyfin_client.dart';


/// Live TV administration: tuner devices and TV guide (listing) providers.
class AdminLiveTvScreen extends ConsumerWidget {
  const AdminLiveTvScreen({super.key});

  /// Add or edit a tuner. Editing POSTs the whole existing object back with the
  /// edited fields merged in: the server upserts on Id, and anything not sent
  /// (TunerCount, UserAgent, the Allow* flags) would otherwise fall back to
  /// defaults and quietly undo the admin's setup.
  Future<void> _tunerDialog(BuildContext context, WidgetRef ref,
      {Map<String, dynamic>? existing}) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final editing = existing != null;
    final urlCtrl = TextEditingController(text: '${existing?['Url'] ?? ''}');
    final nameCtrl =
        TextEditingController(text: '${existing?['FriendlyName'] ?? ''}');
    var type = '${existing?['Type'] ?? 'm3u'}';
    if (type != 'm3u' && type != 'hdhomerun') type = 'm3u';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(editing ? l.adminEditTuner : l.adminAddTuner),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(labelText: l.adminType),
                items: [
                  DropdownMenuItem(value: 'm3u', child: Text(l.adminM3uTuner)),
                  const DropdownMenuItem(
                      value: 'hdhomerun', child: Text('HDHomeRun')),
                ],
                onChanged: (v) => setLocal(() => type = v ?? 'm3u'),
              ),
              const SizedBox(height: 12),
              TvTextField(
                controller: urlCtrl,
                label: type == 'm3u' ? l.adminM3uUrl : l.adminDeviceUrl,
                hint: type == 'hdhomerun' ? 'http://192.168.1.x' : null,
              ),
              const SizedBox(height: 12),
              TvTextField(
                controller: nameCtrl,
                label: l.adminFriendlyName,
                hint: l.adminHintOptional,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.commonCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(editing ? l.commonSave : l.commonAdd)),
          ],
        ),
      ),
    );
    if (ok != true || urlCtrl.text.trim().isEmpty) return;
    try {
      await ref.read(jellyfinClientProvider).addTunerHost(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        tuner: {
          ...?existing,
          'Type': type,
          'Url': urlCtrl.text.trim(),
          if (nameCtrl.text.trim().isNotEmpty)
            'FriendlyName': nameCtrl.text.trim(),
        },
      );
      ref.invalidate(adminLiveTvInfoProvider);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  /// Guide providers come in two flavours, same as the official dashboard:
  /// a plain XMLTV file/URL, or a Schedules Direct account.
  Future<void> _addGuide(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.adminAddGuideProvider),
        children: [
          ListTile(
            leading: const Icon(Icons.menu_book_rounded),
            title: const Text('XMLTV'),
            subtitle: Text(l.adminXmltvSubtitle),
            onTap: () => Navigator.pop(ctx, 'xmltv'),
          ),
          ListTile(
            leading: const Icon(Icons.satellite_alt_rounded),
            title: const Text('Schedules Direct'),
            subtitle: Text(l.adminScdSubtitle),
            onTap: () => Navigator.pop(ctx, 'scd'),
          ),
        ],
      ),
    );
    if (kind == null || !context.mounted) return;
    if (kind == 'scd') {
      final added = await showDialog<bool>(
        context: context,
        builder: (_) => const _SchedulesDirectDialog(),
      );
      if (added == true) ref.invalidate(adminLiveTvInfoProvider);
      return;
    }
    if (context.mounted) await _xmltvDialog(context, ref);
  }

  /// Add or edit an XMLTV provider. As with tuners, the existing object is sent
  /// back whole so the category and channel-mapping settings survive an edit.
  Future<void> _xmltvDialog(BuildContext context, WidgetRef ref,
      {Map<String, dynamic>? existing}) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final editing = existing != null;
    final ctrl = TextEditingController(text: '${existing?['Path'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(editing ? l.adminEditXmltvGuide : l.adminAddXmltvGuide),
        content: TvTextField(
          controller: ctrl,
          autofocus: true,
          label: l.adminXmltvPathLabel,
          hint: 'https://.../guide.xml',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(editing ? l.commonSave : l.commonAdd)),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await ref.read(jellyfinClientProvider).saveListingProvider(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        info: {...?existing, 'Type': 'xmltv', 'Path': ctrl.text.trim()},
      );
      ref.invalidate(adminLiveTvInfoProvider);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref,
      {required String what, required Future<void> Function() onDelete}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirm(context,
        title: l.adminRemoveConfirm(what),
        message: l.adminRemoveFromServerBody,
        confirmLabel: l.commonRemove,
        destructive: true);
    if (!ok) return;
    try {
      await onDelete();
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  Future<void> _delTuner(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref.read(jellyfinClientProvider).deleteTunerHost(
        baseUrl: s.baseUrl, token: s.accessToken, id: id);
    ref.invalidate(adminLiveTvInfoProvider);
  }

  Future<void> _delGuide(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref.read(jellyfinClientProvider).deleteListingProvider(
        baseUrl: s.baseUrl, token: s.accessToken, id: id);
    ref.invalidate(adminLiveTvInfoProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final info = ref.watch(adminLiveTvInfoProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.adminLiveTvTitle),
          bottom: TabBar(tabs: [
            Tab(text: l.adminTabTuners),
            Tab(text: l.adminTabTvGuide),
            Tab(text: l.adminTabRecording),
          ]),
        ),
        body: info.when(
          loading: () => const Center(child: AppSpinner()),
          error: (e, _) => ErrorView(
              message: errorText(e),
              onRetry: () => ref.invalidate(adminLiveTvInfoProvider)),
          data: (m) {
            final tuners = (m['TunerHosts'] as List?)
                    ?.whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                const <Map<String, dynamic>>[];
            final guides = (m['ListingProviders'] as List?)
                    ?.whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                const <Map<String, dynamic>>[];
            return TabBarView(
              children: [
                _liveTvList(
                  context,
                  empty: l.adminNoTuners,
                  addLabel: l.adminAddTuner,
                  onAdd: () => _tunerDialog(context, ref),
                  items: [
                    for (final t in tuners)
                      ListTile(
                        leading: const Icon(Icons.settings_input_antenna_rounded),
                        title: Text('${t['FriendlyName'] ?? t['Url'] ?? '-'}'),
                        subtitle: Text(
                            '${_tunerType(l, t['Type'])}  ·  ${t['Url'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        onTap: () =>
                            _tunerDialog(context, ref, existing: t),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          tooltip: l.commonRemove,
                          onPressed: () => _confirmDelete(context, ref,
                              what: l.adminWhatTuner,
                              onDelete: () =>
                                  _delTuner(ref, '${t['Id'] ?? ''}')),
                        ),
                      ),
                  ],
                ),
                _liveTvList(
                  context,
                  empty: l.adminNoGuideProviders,
                  addLabel: l.adminAddGuideProvider,
                  onAdd: () => _addGuide(context, ref),
                  items: [
                    for (final g in guides)
                      _guideTile(context, ref, g),
                  ],
                ),
                _RecordingOptions(options: m),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _tunerType(AppLocalizations l, Object? type) =>
      switch ('$type'.toLowerCase()) {
        'm3u' => l.adminM3uTuner,
        'hdhomerun' => 'HDHomeRun',
        _ => '$type',
      };

  Widget _guideTile(
      BuildContext context, WidgetRef ref, Map<String, dynamic> g) {
    final l = AppLocalizations.of(context);
    final isScd = '${g['Type']}'.toLowerCase() == 'schedulesdirect';
    final subtitle = isScd
        ? [
            if ('${g['Username'] ?? ''}'.isNotEmpty) '${g['Username']}',
            if ('${g['ListingsId'] ?? ''}'.isNotEmpty) '${g['ListingsId']}',
          ].join('  ·  ')
        : '${g['Path'] ?? ''}';
    return ListTile(
      leading: Icon(
          isScd ? Icons.satellite_alt_rounded : Icons.menu_book_rounded),
      title: Text(isScd ? 'Schedules Direct' : 'XMLTV'),
      subtitle:
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      // Schedules Direct is credential-and-lineup driven, so changing it means
      // running the wizard again rather than editing fields in place.
      onTap: () async {
        if (isScd) {
          final saved = await showDialog<bool>(
            context: context,
            builder: (_) => const _SchedulesDirectDialog(),
          );
          if (saved == true) ref.invalidate(adminLiveTvInfoProvider);
        } else {
          await _xmltvDialog(context, ref, existing: g);
        }
      },
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        tooltip: l.commonRemove,
        onPressed: () => _confirmDelete(context, ref,
            what: l.adminWhatGuideProvider,
            onDelete: () => _delGuide(ref, '${g['Id'] ?? ''}')),
      ),
    );
  }

  Widget _liveTvList(BuildContext context,
      {required String empty,
      required String addLabel,
      required VoidCallback onAdd,
      required List<Widget> items}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(addLabel),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? EmptyState(icon: Icons.live_tv_rounded, title: empty)
              : PageWidth(builder: (c, inset) => ListView.separated(
                  padding: pageInsetsSafe(c, inset),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => items[i],
                )),
        ),
      ],
    );
  }
}

/// The rest of LiveTvOptions: guide depth, recording paths and padding. These
/// come from the same config section the tuners do, so they're editable here
/// rather than being read-only text.
class _RecordingOptions extends ConsumerStatefulWidget {
  final Map<String, dynamic> options;
  const _RecordingOptions({required this.options});

  @override
  ConsumerState<_RecordingOptions> createState() => _RecordingOptionsState();
}

class _RecordingOptionsState extends ConsumerState<_RecordingOptions> {
  late final Map<String, dynamic> _draft =
      Map<String, dynamic>.from(widget.options);
  bool _saving = false;

  Future<void> _save() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = AppLocalizations.of(context).adminSaved;
    setState(() => _saving = true);
    try {
      // The whole section goes back, so tuners and guide providers held in the
      // same object aren't dropped by saving a padding value.
      await ref.read(jellyfinClientProvider).updateNamedConfiguration(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          key: 'livetv',
          config: _draft);
      ref.invalidate(adminLiveTvInfoProvider);
      showSnackOn(messenger, saved, kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Outlined, matching every other admin editor. These were the one form still
  // using the default underline input, which read as a less-finished screen.
  Widget _num(String label, String key, {String? helper}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: TvField(label: label, child: TextFormField(
          initialValue: '${_draft[key] ?? ''}',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              labelText: label,
              helperText: helper,
              border: const OutlineInputBorder()),
          onChanged: (v) => _draft[key] = int.tryParse(v) ?? _draft[key],
        )),
      );

  Widget _text(String label, String key, {String? hint}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: TvField(label: label, child: TextFormField(
          initialValue: '${_draft[key] ?? ''}',
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder()),
          onChanged: (v) => _draft[key] = v.trim().isEmpty ? null : v.trim(),
        )),
      );

  Widget _toggle(String label, String key) => SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(label),
        value: _draft[key] == true,
        onChanged: (v) => setState(() => _draft[key] = v),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PageWidth(builder: (_, inset) => ListView(
      padding: pageInsets(inset, const EdgeInsets.fromLTRB(0, 8, 0, 24)),
      children: [
        SettingsSectionHeader(l.adminSectionGuide, first: true),
        _num(l.adminGuideDays, 'GuideDays',
            helper: l.adminGuideDaysHelper),
        SettingsSectionHeader(l.adminSectionRecordingPaths),
        _text(l.adminRecordingPath, 'RecordingPath'),
        _text(l.adminMovieRecordingPath, 'MovieRecordingPath'),
        _text(l.adminSeriesRecordingPath, 'SeriesRecordingPath'),
        SettingsSectionHeader(l.adminSectionPadding),
        _num(l.adminPrePadding, 'PrePaddingSeconds'),
        _num(l.adminPostPadding, 'PostPaddingSeconds'),
        SettingsSectionHeader(l.adminSectionOptions),
        _toggle(l.adminRecordingSubfolders, 'EnableRecordingSubfolders'),
        _toggle(l.adminSaveRecordingNfo, 'SaveRecordingNFO'),
        _toggle(l.adminSaveRecordingImages, 'SaveRecordingImages'),
        const SizedBox(height: 24),
        // The full-width Save the other config editors use, not a bare button.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            icon: _saving
                ? AppSpinner.inline()
                : const Icon(Icons.save_rounded),
            label: Text(l.commonSave),
          ),
        ),
      ],
    ));
  }
}

/// DVR: scheduled recordings, series rules, and completed recordings.
class AdminDvrScreen extends ConsumerWidget {
  const AdminDvrScreen({super.key});

  /// Asks, then does it, and says so when the server refuses: each of these
  /// used to go on one press, and fail in silence.
  Future<void> _asking(
    BuildContext context, {
    required String title,
    required String message,
    required String label,
    String? keepLabel,
    required Future<void> Function() run,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirm(
      context,
      title: title,
      message: message,
      confirmLabel: label,
      cancelLabel: keepLabel,
      destructive: true,
    );
    if (!ok) return;
    try {
      await run();
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  Future<void> _cancelTimer(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .cancelTimer(baseUrl: s.baseUrl, token: s.accessToken, timerId: id);
    ref.invalidate(adminTimersProvider);
  }

  Future<void> _cancelSeries(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .cancelSeriesTimer(baseUrl: s.baseUrl, token: s.accessToken, id: id);
    ref.invalidate(adminSeriesTimersProvider);
  }

  Future<void> _deleteRecording(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .deleteRecording(baseUrl: s.baseUrl, token: s.accessToken, id: id);
    ref.invalidate(adminRecordingsProvider);
  }

  Future<void> _editSeriesPadding(
      BuildContext context, WidgetRef ref, Map<String, dynamic> timer) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final pre = TextEditingController(
        text: '${((timer['PrePaddingSeconds'] as num?)?.toInt() ?? 0) ~/ 60}');
    final post = TextEditingController(
        text: '${((timer['PostPaddingSeconds'] as num?)?.toInt() ?? 0) ~/ 60}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${timer['Name'] ?? l.adminSeriesFallback}'),
        content: Row(
          children: [
            Expanded(
              child: TvField(child: TextField(
                controller: pre,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: l.adminStartBefore, suffixText: 'min'),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TvField(child: TextField(
                controller: post,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: l.adminStopAfter, suffixText: 'min'),
              )),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonSave)),
        ],
      ),
    );
    if (ok != true) return;
    final preMin = int.tryParse(pre.text) ?? 0;
    final postMin = int.tryParse(post.text) ?? 0;
    final updated = <String, dynamic>{
      ...timer,
      'PrePaddingSeconds': preMin * 60,
      'PostPaddingSeconds': postMin * 60,
      'IsPrePaddingRequired': preMin > 0,
      'IsPostPaddingRequired': postMin > 0,
    };
    try {
      await ref.read(jellyfinClientProvider).updateSeriesTimer(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          id: '${timer['Id']}',
          timer: updated);
      ref.invalidate(adminSeriesTimersProvider);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.adminDvrTitle),
          bottom: TabBar(tabs: [
            Tab(text: l.adminTabScheduled),
            Tab(text: l.adminTabSeries),
            Tab(text: l.adminTabRecorded),
          ]),
        ),
        body: TabBarView(
          children: [
            _dvrList(
              context,
              async: ref.watch(adminTimersProvider),
              empty: l.adminNoScheduledRecordings,
              onInvalidate: () => ref.invalidate(adminTimersProvider),
              tile: (t) => ListTile(
                leading: const Icon(Icons.fiber_manual_record_rounded,
                    color: Colors.red),
                title: Text('${t['Name'] ?? '-'}'),
                subtitle: Text(_timerSubtitle(context, t),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: l.commonCancel,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _asking(
                    context,
                    title: l.adminCancelRecordingTitle,
                    message: l.adminCancelRecordingBody('${t['Name'] ?? ''}'),
                    label: l.detailCancelRecording,
                    keepLabel: l.adminKeepRecording,
                    run: () => _cancelTimer(ref, '${t['Id'] ?? ''}'),
                  ),
                ),
              ),
            ),
            _dvrList(
              context,
              async: ref.watch(adminSeriesTimersProvider),
              empty: l.adminNoSeriesRules,
              onInvalidate: () => ref.invalidate(adminSeriesTimersProvider),
              tile: (t) => ListTile(
                leading: const Icon(Icons.repeat_rounded),
                title: Text('${t['Name'] ?? '-'}'),
                subtitle: Text(l.adminSeriesPad(
                    ((t['PrePaddingSeconds'] as num?)?.toInt() ?? 0) ~/ 60,
                    ((t['PostPaddingSeconds'] as num?)?.toInt() ?? 0) ~/ 60)),
                onTap: () => _editSeriesPadding(context, ref, t),
                trailing: IconButton(
                  tooltip: l.commonDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _asking(
                    context,
                    title: l.adminDeleteSeriesRuleTitle,
                    message: l.adminDeleteSeriesRuleBody('${t['Name'] ?? ''}'),
                    label: l.commonDelete,
                    run: () => _cancelSeries(ref, '${t['Id'] ?? ''}'),
                  ),
                ),
              ),
            ),
            _RecordedTab(
              onDelete: (id, name) => _asking(
                context,
                title: l.adminDeleteRecordingTitle,
                message: l.adminDeleteRecordingBody(name),
                label: l.commonDelete,
                run: () => _deleteRecording(ref, id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _timerSubtitle(BuildContext context, Map<String, dynamic> t) {
    final start = DateTime.tryParse('${t['StartDate'] ?? ''}');
    final chan = '${t['ChannelName'] ?? ''}';
    final when = start == null
        ? ''
        : shortDateTime(context, start);
    return [chan, when].where((x) => x.isNotEmpty).join('  ·  ');
  }

  Widget _dvrList(
    BuildContext context, {
    required AsyncValue<List<Map<String, dynamic>>> async,
    required String empty,
    required VoidCallback onInvalidate,
    required Widget Function(Map<String, dynamic>) tile,
  }) {
    return async.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(message: errorText(e), onRetry: onInvalidate),
      data: (list) => list.isEmpty
          ? EmptyState(icon: Icons.live_tv_rounded, title: empty)
          : RefreshIndicator(
              onRefresh: () async => onInvalidate(),
              child: PageWidth(builder: (c, inset) => ListView.separated(
                padding: pageInsetsSafe(c, inset),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => tile(list[i]),
              )),
            ),
    );
  }
}

/// The Recorded tab of the DVR screen: completed recordings, playable and
/// deletable.
class _RecordedTab extends ConsumerWidget {
  final void Function(String id, String name) onDelete;
  const _RecordedTab({required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(adminRecordingsProvider);
    return async.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(adminRecordingsProvider)),
      data: (list) => list.isEmpty
          ? EmptyState(icon: Icons.videocam_rounded, title: l.adminNoRecordings)
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(adminRecordingsProvider),
              child: PageWidth(builder: (c, inset) => ListView.separated(
                padding: pageInsetsSafe(c, inset),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = list[i];
                  return ListTile(
                    leading: const Icon(Icons.video_file_rounded),
                    title: Text(r.name),
                    subtitle: r.overview == null
                        ? null
                        : Text(r.overview!,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => context.push('/item', extra: r),
                    trailing: IconButton(
                      tooltip: l.commonDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => onDelete(r.id, r.name),
                    ),
                  );
                },
              )),
            ),
    );
  }
}

/// Schedules Direct setup, mirroring the official dashboard's flow: sign in to
/// validate the account (which creates the provider and returns its id), then
/// pick a country + postal code to look up lineups, and save the chosen one.
class _SchedulesDirectDialog extends ConsumerStatefulWidget {
  const _SchedulesDirectDialog();

  @override
  ConsumerState<_SchedulesDirectDialog> createState() =>
      _SchedulesDirectDialogState();
}

class _SchedulesDirectDialogState
    extends ConsumerState<_SchedulesDirectDialog> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _zip = TextEditingController();

  int _step = 0; // 0 = credentials, 1 = lineup
  bool _busy = false;
  String? _error;
  String? _providerId;
  Map<String, dynamic>? _countries;
  String? _country;
  List<({String id, String name})> _lineups = const [];
  String? _lineupId;
  bool _enableAllTuners = true;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _zip.dispose();
    super.dispose();
  }

  // The dashboard hashes the password client-side; the server stores it as-is.
  String get _hashedPassword =>
      sha1.convert(utf8.encode(_pass.text)).toString();

  Map<String, dynamic> _info({String? listingsId}) => {
        if (_providerId != null && _providerId!.isNotEmpty) 'Id': _providerId,
        'Type': 'SchedulesDirect',
        'Username': _user.text.trim(),
        'Password': _hashedPassword,
        'EnableAllTuners': _enableAllTuners,
        if (_country != null) 'Country': _country,
        if (_zip.text.trim().isNotEmpty) 'ZipCode': _zip.text.trim(),
        'ListingsId': ?listingsId,
      };

  /// Flattens Schedules Direct's region-grouped country list.
  List<({String code, String name})> get _countryOptions {
    final out = <({String code, String name})>[];
    final c = _countries;
    if (c == null) return out;
    for (final region in c.values) {
      if (region is! List) continue;
      for (final m in region.whereType<Map>()) {
        final code = '${m['shortName'] ?? ''}';
        if (code.isEmpty) continue;
        out.add((code: code, name: '${m['fullName'] ?? code}'));
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Future<void> _signIn() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = ref.read(jellyfinClientProvider);
      final saved = await client.saveListingProvider(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        info: _info(),
        validateLogin: true,
      );
      _providerId = '${saved['Id'] ?? ''}';
      final countries = await client.getSchedulesDirectCountries(
          baseUrl: s.baseUrl, token: s.accessToken);
      if (!mounted) return;
      setState(() {
        _countries = countries;
        _step = 1;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _busy = false;
        });
      }
    }
  }

  Future<void> _findLineups() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null || _country == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _lineups = const [];
      _lineupId = null;
    });
    try {
      final lineups =
          await ref.read(jellyfinClientProvider).getListingProviderLineups(
                baseUrl: s.baseUrl,
                token: s.accessToken,
                providerId: _providerId ?? '',
                country: _country!,
                location: _zip.text.trim(),
              );
      if (!mounted) return;
      setState(() {
        _lineups = lineups;
        _lineupId = lineups.isNotEmpty ? lineups.first.id : null;
        _busy = false;
        if (lineups.isEmpty) {
          _error = AppLocalizations.of(context).adminNoLineups;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _busy = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null || _lineupId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(jellyfinClientProvider).saveListingProvider(
            baseUrl: s.baseUrl,
            token: s.accessToken,
            info: _info(listingsId: _lineupId),
            validateListings: true,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Schedules Direct'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step == 0) ...[
                TvTextField(
                  controller: _user,
                  autofocus: true,
                  label: loc.adminUsername,
                ),
                const SizedBox(height: 12),
                TvTextField(
                  controller: _pass,
                  obscure: true,
                  label: loc.adminPassword,
                  onSubmitted: (_) => _busy ? null : _signIn(),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  initialValue: _country,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: loc.adminCountry),
                  items: [
                    for (final c in _countryOptions)
                      DropdownMenuItem(
                          value: c.code,
                          child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _country = v),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TvTextField(
                        controller: _zip,
                        label: loc.adminPostalCode,
                        hint: '10001',
                        onSubmitted: (_) => _busy ? null : _findLineups(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed:
                          (_busy || _country == null) ? null : _findLineups,
                      style: kInlineButtonStyle,
                      child: Text(loc.adminFindLineups),
                    ),
                  ],
                ),
                if (_lineups.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _lineupId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: loc.adminLineup),
                    items: [
                      for (final l in _lineups)
                        DropdownMenuItem(
                            value: l.id,
                            child:
                                Text(l.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _lineupId = v),
                  ),
                ],
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.adminEnableAllTuners),
                  value: _enableAllTuners,
                  onChanged: (v) => setState(() => _enableAllTuners = v),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(loc.commonCancel),
        ),
        if (_step == 0)
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: Text(loc.commonSignIn),
          )
        else
          FilledButton(
            onPressed: (_busy || _lineupId == null) ? null : _save,
            child: Text(loc.commonSave),
          ),
      ],
    );
  }
}
