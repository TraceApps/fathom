import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../api/jellyfin_client.dart';
import '../models/session.dart';
import '../state/admin_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/page_width.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/ui_common.dart';

typedef _Toggle = (String key, String label, String subtitle);

// Grouped to mirror the official dashboard's user editor. These take the
// localizations object because they carry user-facing labels but have no
// BuildContext of their own.
List<_Toggle> _managementToggles(AppLocalizations l) => <_Toggle>[
      ('IsAdministrator', l.adminAllowServerManagement,
          l.adminAllowServerManagementSub),
      ('IsDisabled', l.adminDisableUser, l.adminDisableUserSub),
      ('IsHidden', l.adminHideFromLogin, ''),
      ('EnableCollectionManagement', l.adminAllowCollectionMgmt, ''),
      ('EnableSubtitleManagement', l.adminAllowSubtitleMgmt, ''),
    ];

List<_Toggle> _playbackToggles(AppLocalizations l) => <_Toggle>[
      ('EnableMediaPlayback', l.adminAllowMediaPlayback, ''),
      ('EnableAudioPlaybackTranscoding', l.adminAllowAudioTranscoding, ''),
      ('EnableVideoPlaybackTranscoding', l.adminAllowVideoTranscoding, ''),
      ('EnablePlaybackRemuxing', l.adminAllowRemuxing, ''),
      ('ForceRemoteSourceTranscoding', l.adminForceRemoteTranscoding,
          l.adminForceRemoteTranscodingSub),
      ('EnableContentDownloading', l.adminAllowDownloads, ''),
    ];

List<_Toggle> _liveTvToggles(AppLocalizations l) => <_Toggle>[
      ('EnableLiveTvAccess', l.adminAllowLiveTvAccess, ''),
      ('EnableLiveTvManagement', l.adminAllowLiveTvMgmt, ''),
    ];

List<_Toggle> _remoteToggles(AppLocalizations l) => <_Toggle>[
      ('EnableRemoteAccess', l.adminAllowRemoteConnections, ''),
      ('EnableRemoteControlOfOtherUsers', l.adminAllowRemoteControlOthers, ''),
      ('EnableSharedDeviceControl', l.adminAllowBeingControlled, ''),
    ];

/// Admin: view and edit a user's policy across Profile / Access / Parental /
/// Password subsections, mirroring the official dashboard.
class UserEditScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserEditScreen({super.key, required this.userId});

  @override
  ConsumerState<UserEditScreen> createState() => _UserEditScreenState();
}

class _UserEditScreenState extends ConsumerState<UserEditScreen> {
  Map<String, dynamic> _policy = {};
  List<Map<String, dynamic>> _folders = const [];
  List<Map<String, dynamic>> _ratings = const [];
  List<Map<String, dynamic>> _authProviders = const [];
  List<Map<String, dynamic>> _resetProviders = const [];
  List<Map<String, dynamic>> _devices = const [];
  List<Map<String, dynamic>> _channels = const [];
  String _name = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<String> get _enabledFolders =>
      ((_policy['EnabledFolders'] as List?) ?? const [])
          .map((e) => '$e')
          .toList();

  void _toggleFolder(String id, bool on) => _toggleIn('EnabledFolders', id, on);

  /// The ids in one of the policy's id lists (libraries, devices, channels).
  List<String> _ids(String key) =>
      ((_policy[key] as List?) ?? const []).map((e) => '$e').toList();

  void _toggleIn(String key, String id, bool on) {
    final set = _ids(key).toSet();
    if (on) {
      set.add(id);
    } else {
      set.remove(id);
    }
    setState(() => _policy[key] = set.toList());
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Typed: the client's methods are extensions, which a dynamic call can't
  // reach at runtime.
  ({Session session, JellyfinClient client})? _ctx() {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return null;
    return (session: s, client: ref.read(jellyfinClientProvider));
  }

  Future<void> _load() async {
    final c = _ctx();
    if (c == null) return;
    try {
      final u = await c.client.getUser(
          baseUrl: c.session.baseUrl,
          token: c.session.accessToken,
          userId: widget.userId);
      List<Map<String, dynamic>> folders = const [];
      List<Map<String, dynamic>> ratings = const [];
      try {
        folders = await c.client.getVirtualFolders(
            baseUrl: c.session.baseUrl, token: c.session.accessToken);
      } catch (_) {}
      try {
        ratings = await c.client.getParentalRatings(
            baseUrl: c.session.baseUrl, token: c.session.accessToken);
      } catch (_) {}
      // The rest only fill in optional sections; a server without one of them
      // just leaves that section out.
      Future<List<Map<String, dynamic>>> optional(
          Future<List<Map<String, dynamic>>> Function() fetch) async {
        try {
          return await fetch();
        } catch (_) {
          return const [];
        }
      }

      final b = c.session.baseUrl, t = c.session.accessToken;
      final extra = await Future.wait([
        optional(() => c.client.getAuthProviders(baseUrl: b, token: t)),
        optional(() => c.client.getPasswordResetProviders(baseUrl: b, token: t)),
        optional(() => c.client.getDevices(baseUrl: b, token: t)),
        optional(() => c.client.getChannelsForAccess(baseUrl: b, token: t)),
      ]);
      if (!mounted) return;
      setState(() {
        _name = u['Name'] as String? ?? '';
        _policy = Map<String, dynamic>.from((u['Policy'] as Map?) ?? {});
        _folders = folders;
        _ratings = ratings;
        _authProviders = extra[0];
        _resetProviders = extra[1];
        _devices = extra[2];
        _channels = extra[3];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final c = _ctx();
    if (c == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await c.client.updateUserPolicy(
          baseUrl: c.session.baseUrl,
          token: c.session.accessToken,
          userId: widget.userId,
          policy: _policy);
      ref.invalidate(adminUsersProvider);
      showSnackOn(messenger, l.adminSaved, kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetPassword() async {
    final c = _ctx();
    if (c == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final newPw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminSetPassword),
        content: TvTextField(
          controller: controller,
          obscure: true,
          autofocus: true,
          label: l.adminNewPasswordHint,
          hint: l.adminNewPasswordHint,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(l.adminSet)),
        ],
      ),
    );
    if (newPw == null) return;
    try {
      await c.client.setUserPassword(
          baseUrl: c.session.baseUrl,
          token: c.session.accessToken,
          userId: widget.userId,
          newPassword: newPw.isEmpty ? null : newPw);
      showSnackOn(messenger, l.adminPasswordUpdated, kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  Future<void> _delete() async {
    final c = _ctx();
    if (c == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirm(context,
        title: l.adminDeleteUser,
        message: l.adminDeleteUserConfirm(_name),
        confirmLabel: l.commonDelete,
        destructive: true);
    if (!ok) return;
    try {
      await c.client.deleteUser(
          baseUrl: c.session.baseUrl,
          token: c.session.accessToken,
          userId: widget.userId);
      ref.invalidate(adminUsersProvider);
      if (mounted) {
        context.pop();
        showSnackOn(messenger, l.adminDeletedUser(_name),
            kind: SnackKind.success);
      }
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_name.isEmpty ? l.adminUser : _name)),
        body: const Center(child: AppSpinner()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_name.isEmpty ? l.adminUser : _name)),
        body: Center(child: Text(_error!)),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_name.isEmpty ? l.adminUser : _name),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? AppSpinner.inline()
                  : Text(l.commonSave),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l.adminTabProfile),
              Tab(text: l.adminTabAccess),
              Tab(text: l.adminTabParental),
              Tab(text: l.adminTabPassword),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _profileTab(),
            _accessTab(),
            _parentalTab(),
            _passwordTab(),
          ],
        ),
      ),
    );
  }

  // ---- tabs ----

  Widget _profileTab() {
    final l = AppLocalizations.of(context);
    return PageWidth(builder: (c, inset) => ListView(
      padding: pageInsetsSafe(c, inset),
      children: [
        _section(l.adminSectionManagement),
        for (final t in _managementToggles(l)) _toggle(t),
        _section(l.adminSectionPlayback),
        for (final t in _playbackToggles(l)) _toggle(t),
        _section(l.adminSectionLiveTv),
        for (final t in _liveTvToggles(l)) _toggle(t),
        _section(l.adminSectionRemote),
        for (final t in _remoteToggles(l)) _toggle(t),
        ..._deletionSection(l),
        _section(l.adminSectionSyncPlay),
        _dropdown('SyncPlayAccess', l.adminSyncPlayAccess, {
          'CreateAndJoinGroups': l.adminSyncPlayCreateAndJoin,
          'JoinGroups': l.adminSyncPlayJoin,
          'None': l.adminSyncPlayNone,
        }),
        // Only worth a choice when the server has more than one, as in the
        // web dashboard; most have just the built-in provider.
        if (_authProviders.length > 1 || _resetProviders.length > 1)
          _section(l.adminSectionSignIn),
        if (_authProviders.length > 1)
          _dropdown('AuthenticationProviderId', l.adminAuthProvider, {
            for (final p in _authProviders)
              '${p['Id']}': '${p['Name'] ?? p['Id']}',
          }),
        if (_resetProviders.length > 1)
          _dropdown('PasswordResetProviderId', l.adminPasswordResetProvider, {
            for (final p in _resetProviders)
              '${p['Id']}': '${p['Name'] ?? p['Id']}',
          }),
        _section(l.adminSectionLimits),
        _intField('MaxActiveSessions', l.adminMaxSimultaneousStreams,
            hint: l.adminHintZeroUnlimited),
        _intField('LoginAttemptsBeforeLockout', l.adminFailedLoginsBeforeLockout,
            hint: l.adminFailedLoginsHint),
        _bitrateField(),
        const SizedBox(height: 24),
      ],
    ));
  }

  Widget _accessTab() {
    final l = AppLocalizations.of(context);
    return PageWidth(builder: (c, inset) => ListView(
      padding: pageInsetsSafe(c, inset),
      children: [
        _section(l.adminLibrariesTitle),
        SwitchListTile(
          title: Text(l.adminAccessAllLibraries),
          value: _policy['EnableAllFolders'] == true,
          onChanged: (v) => setState(() => _policy['EnableAllFolders'] = v),
        ),
        if (_policy['EnableAllFolders'] != true)
          for (final f in _folders)
            CheckboxListTile(
              dense: true,
              title: Text('${f['Name'] ?? '-'}'),
              value: _enabledFolders.contains('${f['ItemId']}'),
              onChanged: (v) => _toggleFolder('${f['ItemId']}', v ?? false),
            ),
        _section(l.adminDevicesTitle),
        SwitchListTile(
          title: Text(l.adminAccessAllDevices),
          value: _policy['EnableAllDevices'] == true,
          onChanged: (v) => setState(() {
            _policy['EnableAllDevices'] = v;
            // As the dashboard saves it: the list only means something when
            // access is limited.
            if (v) _policy['EnabledDevices'] = <String>[];
          }),
        ),
        if (_policy['EnableAllDevices'] != true) ...[
          for (final d in _devices)
            CheckboxListTile(
              dense: true,
              title: Text([
                (d['CustomName'] as String?)?.isNotEmpty == true
                    ? d['CustomName']
                    : d['Name'],
                d['AppName'],
              ].where((e) => e != null && '$e'.isNotEmpty).join(' · ')),
              subtitle: (d['LastUserName'] as String?)?.isNotEmpty == true
                  ? Text('${d['LastUserName']}')
                  : null,
              value: _ids('EnabledDevices').contains('${d['Id']}'),
              onChanged: (v) =>
                  _toggleIn('EnabledDevices', '${d['Id']}', v ?? false),
            ),
          _help(l.adminDeviceAccessHelp),
        ],
        // Channels come from server plugins; with none, there's nothing to
        // limit, and the dashboard hides the section too.
        if (_channels.isNotEmpty) ...[
          _section(l.adminSectionChannels),
          SwitchListTile(
            title: Text(l.adminAccessAllChannels),
            value: _policy['EnableAllChannels'] == true,
            onChanged: (v) => setState(() {
              _policy['EnableAllChannels'] = v;
              if (v) _policy['EnabledChannels'] = <String>[];
            }),
          ),
          if (_policy['EnableAllChannels'] != true) ...[
            for (final ch in _channels)
              CheckboxListTile(
                dense: true,
                title: Text('${ch['Name'] ?? ch['Id']}'),
                value: _ids('EnabledChannels').contains('${ch['Id']}'),
                onChanged: (v) =>
                    _toggleIn('EnabledChannels', '${ch['Id']}', v ?? false),
              ),
            _help(l.adminChannelAccessHelp),
          ],
        ],
        const SizedBox(height: 24),
      ],
    ));
  }

  Widget _parentalTab() {
    final l = AppLocalizations.of(context);
    return PageWidth(builder: (c, inset) => ListView(
      padding: pageInsetsSafe(c, inset),
      children: [
        _section(l.adminSectionMaxRating),
        _ratingDropdown(l),
        _help(l.adminRatingHelp),
        _section(l.adminBlockUnrated),
        _help(l.adminBlockUnratedHelp),
        for (final t in _unratedTypes(l))
          CheckboxListTile(
            dense: true,
            title: Text(t.$2),
            value: _ids('BlockUnratedItems').contains(t.$1),
            onChanged: (v) => _toggleIn('BlockUnratedItems', t.$1, v ?? false),
          ),
        // Anything else already blocked, such as "Other", which an earlier
        // Fathom saved from a single on/off switch. Shown so it can be seen and
        // cleared; without this the restriction was invisible here.
        for (final extra in _ids('BlockUnratedItems')
            .where((v) => !_unratedTypes(l).any((t) => t.$1 == v)))
          CheckboxListTile(
            dense: true,
            title: Text(extra == 'Other' ? l.adminUnratedOther : extra),
            value: true,
            onChanged: (v) => _toggleIn('BlockUnratedItems', extra, v ?? false),
          ),
        ..._tagSection('AllowedTags', l.adminAllowedTags, l.adminAllowedTagsHelp),
        ..._tagSection('BlockedTags', l.adminBlockedTags, l.adminBlockedTagsHelp),
        // An administrator isn't bound by a schedule, so the dashboard hides it.
        if (_policy['IsAdministrator'] != true) ..._scheduleSection(l),
        const SizedBox(height: 24),
      ],
    ));
  }

  /// The kinds of unrated item the dashboard lets you block. Anything else
  /// already in the list (set some other way) is left alone.
  static List<(String, String)> _unratedTypes(AppLocalizations l) => [
        ('Book', l.adminUnratedBooks),
        ('ChannelContent', l.adminUnratedChannels),
        ('LiveTvChannel', l.adminUnratedLiveTv),
        ('Movie', l.adminUnratedMovies),
        ('Music', l.adminUnratedMusic),
        ('Trailer', l.adminUnratedTrailers),
        ('Series', l.adminUnratedShows),
      ];

  /// The maximum rating.
  ///
  /// Jellyfin 12 rates with a score and a sub-score (TV-Y7 and TV-Y7-FV share
  /// score 7 and differ by sub-score), and a user's limit is saved as both.
  /// Every rating is offered by name, as in the dashboard, and choosing one
  /// sets the pair. A server without sub-scores keeps the older single value,
  /// one entry per score.
  Widget _ratingDropdown(AppLocalizations l) {
    final scored = [
      for (final r in _ratings)
        if (r['RatingScore'] is Map && (r['RatingScore'] as Map)['score'] != null)
          r
    ];
    if (scored.isEmpty) return _legacyRatingDropdown(l);

    int score(Map r) => ((r['RatingScore'] as Map)['score'] as num).toInt();
    int? subScore(Map r) =>
        ((r['RatingScore'] as Map)['subScore'] as num?)?.toInt();

    final max = (_policy['MaxParentalRating'] as num?)?.toInt();
    final maxSub = (_policy['MaxParentalSubRating'] as num?)?.toInt();
    int? selected;
    if (max != null) {
      // Exact match first, then the highest rating within the limit.
      for (var i = 0; i < scored.length; i++) {
        if (score(scored[i]) == max && subScore(scored[i]) == maxSub) {
          selected = i;
        }
      }
      if (selected == null) {
        for (var i = 0; i < scored.length; i++) {
          if (score(scored[i]) <= max) selected = i;
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DropdownButtonFormField<int?>(
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: l.adminMaxParentalRating,
            border: const OutlineInputBorder()),
        items: [
          DropdownMenuItem<int?>(value: null, child: Text(l.adminRatingNone)),
          for (var i = 0; i < scored.length; i++)
            DropdownMenuItem<int?>(
              value: i,
              child: Text('${scored[i]['Name'] ?? score(scored[i])}'),
            ),
        ],
        onChanged: (i) => setState(() {
          _policy['MaxParentalRating'] = i == null ? null : score(scored[i]);
          _policy['MaxParentalSubRating'] =
              i == null ? null : subScore(scored[i]);
        }),
      ),
    );
  }

  Widget _legacyRatingDropdown(AppLocalizations l) {
    final current = (_policy['MaxParentalRating'] as num?)?.toInt();
    // The older rating list has several names per value; one entry per value.
    final seen = <int>{};
    final ratings = [
      for (final r in _ratings)
        if ((r['Value'] as num?) != null &&
            seen.add((r['Value'] as num).toInt()))
          r
    ];
    final values = ratings.map((r) => (r['Value'] as num).toInt()).toSet();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DropdownButtonFormField<int?>(
        initialValue: values.contains(current) ? current : null,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: l.adminMaxParentalRating,
            border: const OutlineInputBorder()),
        items: [
          DropdownMenuItem<int?>(value: null, child: Text(l.adminRatingNone)),
          for (final r in ratings)
            DropdownMenuItem<int?>(
              value: (r['Value'] as num).toInt(),
              child: Text('${r['Name'] ?? r['Value']}'),
            ),
        ],
        onChanged: (v) => setState(() => _policy['MaxParentalRating'] = v),
      ),
    );
  }

  List<Widget> _tagSection(String key, String title, String help) {
    final l = AppLocalizations.of(context);
    final tags = _ids(key);
    return [
      _section(title),
      _help(help),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags)
              InputChip(
                label: Text(tag),
                onDeleted: () => setState(
                    () => _policy[key] = tags.where((t) => t != tag).toList()),
                deleteButtonTooltipMessage: l.commonRemove,
              ),
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: Text(l.adminAddTag),
              onPressed: () => _addTag(key),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _addTag(String key) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminAddTag),
        content: TvTextField(
          controller: controller,
          autofocus: true,
          label: l.adminTag,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(l.commonAdd)),
        ],
      ),
    );
    final value = tag?.trim() ?? '';
    if (value.isEmpty || !mounted) return;
    final tags = _ids(key);
    if (tags.contains(value)) return;
    setState(() => _policy[key] = [...tags, value]);
  }

  List<Map<String, dynamic>> get _schedules => [
        for (final e in ((_policy['AccessSchedules'] as List?) ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ];

  List<Widget> _scheduleSection(AppLocalizations l) {
    final schedules = _schedules;
    return [
      _section(l.adminAccessSchedule),
      _help(l.adminAccessScheduleHelp),
      for (var i = 0; i < schedules.length; i++)
        ListTile(
          leading: const Icon(Icons.schedule_rounded),
          title: Text(_dayLabel(l, '${schedules[i]['DayOfWeek']}')),
          subtitle: Text(
              '${_hourLabel((schedules[i]['StartHour'] as num?)?.toDouble() ?? 0)}'
              ' – '
              '${_hourLabel((schedules[i]['EndHour'] as num?)?.toDouble() ?? 0)}'),
          trailing: IconButton(
            tooltip: l.commonRemove,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => setState(() => _policy['AccessSchedules'] = [
                  for (var j = 0; j < schedules.length; j++)
                    if (j != i) schedules[j],
                ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addSchedule,
            icon: const Icon(Icons.add_rounded),
            label: Text(l.adminAddSchedule),
          ),
        ),
      ),
    ];
  }

  /// The days a schedule can cover, in Jellyfin's own terms: a single day, or
  /// every day, weekdays, or weekends.
  List<String> get _scheduleDays => const [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Everyday',
        'Weekday',
        'Weekend',
      ];

  String _dayLabel(AppLocalizations l, String day) {
    switch (day) {
      case 'Everyday':
        return l.adminEveryDay;
      case 'Weekday':
        return l.adminWeekdays;
      case 'Weekend':
        return l.adminWeekends;
    }
    final index = _scheduleDays.indexOf(day);
    if (index < 0 || index > 6) return day;
    // 2006-01-01 was a Sunday, so day N of that week is the Nth weekday.
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.EEEE(locale).format(DateTime(2006, 1, 1 + index));
  }

  /// A schedule hour (half-hour steps, 24 meaning midnight at the end of the
  /// day) as a time of day in the viewer's format.
  String _hourLabel(double hours) {
    final whole = hours.floor() % 24;
    final minutes = ((hours - hours.floor()) * 60).round();
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: whole, minute: minutes),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  Future<void> _addSchedule() async {
    final l = AppLocalizations.of(context);
    // Half-hour steps from midnight to midnight, as the dashboard offers.
    final hours = [for (var i = 0; i <= 48; i++) i / 2];
    var day = 'Everyday';
    var start = 0.0;
    var end = 24.0;
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l.adminAddSchedule),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: day,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: l.adminScheduleDay,
                    border: const OutlineInputBorder()),
                items: [
                  for (final d in _scheduleDays)
                    DropdownMenuItem(value: d, child: Text(_dayLabel(l, d))),
                ],
                onChanged: (v) => setLocal(() => day = v ?? day),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<double>(
                initialValue: start,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: l.adminScheduleStart,
                    border: const OutlineInputBorder()),
                items: [
                  for (final h in hours.take(48))
                    DropdownMenuItem(value: h, child: Text(_hourLabel(h))),
                ],
                onChanged: (v) => setLocal(() => start = v ?? start),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<double>(
                initialValue: end,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: l.adminScheduleEnd,
                    border: const OutlineInputBorder()),
                items: [
                  for (final h in hours.skip(1))
                    DropdownMenuItem(value: h, child: Text(_hourLabel(h))),
                ],
                onChanged: (v) => setLocal(() => end = v ?? end),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.commonCancel)),
            FilledButton(
                onPressed: end > start ? () => Navigator.pop(ctx, true) : null,
                child: Text(l.commonAdd)),
          ],
        ),
      ),
    );
    if (added != true || !mounted) return;
    setState(() => _policy['AccessSchedules'] = [
          ..._schedules,
          {'DayOfWeek': day, 'StartHour': start, 'EndHour': end},
        ]);
  }

  Widget _passwordTab() {
    final l = AppLocalizations.of(context);
    return PageWidth(builder: (c, inset) => ListView(
      padding: pageInsetsSafe(c, inset),
      children: [
        ListTile(
          leading: const Icon(Icons.password_rounded),
          title: Text(l.adminSetResetPassword),
          onTap: _resetPassword,
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error),
          title: Text(l.adminDeleteUser,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: _delete,
        ),
      ],
    ));
  }

  // ---- shared field builders ----

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      );

  Widget _toggle(_Toggle t) => SwitchListTile(
        title: Text(t.$2),
        subtitle: t.$3.isEmpty ? null : Text(t.$3),
        value: _policy[t.$1] == true,
        onChanged: (v) => setState(() => _policy[t.$1] = v),
      );

  /// Which libraries this user may delete from: all of them, or a chosen few.
  /// Saved as the dashboard saves it, with the list empty whenever "all" is on.
  List<Widget> _deletionSection(AppLocalizations l) {
    final all = _policy['EnableContentDeletion'] == true;
    return [
      _section(l.adminSectionDeletion),
      SwitchListTile(
        title: Text(l.adminDeleteFromAll),
        value: all,
        onChanged: (v) => setState(() {
          _policy['EnableContentDeletion'] = v;
          if (v) _policy['EnableContentDeletionFromFolders'] = <String>[];
        }),
      ),
      if (!all) ...[
        for (final f in _folders)
          CheckboxListTile(
            dense: true,
            title: Text('${f['Name'] ?? '?'}'),
            value: _ids('EnableContentDeletionFromFolders')
                .contains('${f['ItemId']}'),
            onChanged: (v) => _toggleIn(
                'EnableContentDeletionFromFolders', '${f['ItemId']}', v ?? false),
          ),
        for (final ch in _channels)
          CheckboxListTile(
            dense: true,
            title: Text('${ch['Name'] ?? ch['Id']}'),
            value: _ids('EnableContentDeletionFromFolders')
                .contains('${ch['Id']}'),
            onChanged: (v) => _toggleIn(
                'EnableContentDeletionFromFolders', '${ch['Id']}', v ?? false),
          ),
      ],
    ];
  }

  Widget _dropdown(String key, String label, Map<String, String> options) {
    final current = '${_policy[key] ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: DropdownButtonFormField<String>(
        initialValue: options.containsKey(current) ? current : null,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final e in options.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) setState(() => _policy[key] = v);
        },
      ),
    );
  }

  Widget _help(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).hintColor)),
      );

  Widget _intField(String key, String label, {String? hint}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: TextFormField(
          initialValue: '${(_policy[key] as num?)?.toInt() ?? 0}',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))
          ],
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder()),
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) _policy[key] = n;
          },
        ),
      );

  // RemoteClientBitrateLimit is stored in bits/sec; show it in Mbps.
  Widget _bitrateField() {
    final l = AppLocalizations.of(context);
    final bps = (_policy['RemoteClientBitrateLimit'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: bps > 0 ? '${(bps / 1000000).round()}' : '0',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
            labelText: l.adminRemoteStreamingLimit,
            suffixText: 'Mbps',
            hintText: l.adminHintZeroUnlimited,
            border: const OutlineInputBorder()),
        onChanged: (v) {
          final mbps = int.tryParse(v);
          if (mbps != null) {
            _policy['RemoteClientBitrateLimit'] = mbps * 1000000;
          }
        },
      ),
    );
  }
}
