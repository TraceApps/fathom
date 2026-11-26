import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/error_text.dart';
import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../state/admin_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'tv_keyboard.dart';
import 'app_snack.dart';
import 'app_spinner.dart';

/// Opens the schedule-recording dialog for a Live TV program: pre/post padding
/// (start early / stop late) and a one-off or whole-series choice.
Future<void> showRecordDialog(
  BuildContext context,
  WidgetRef ref, {
  required String programId,
  bool allowSeries = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _RecordDialog(programId: programId, allowSeries: allowSeries),
  );
}

class _RecordDialog extends ConsumerStatefulWidget {
  final String programId;
  final bool allowSeries;
  const _RecordDialog({required this.programId, required this.allowSeries});

  @override
  ConsumerState<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends ConsumerState<_RecordDialog> {
  Map<String, dynamic>? _defaults;
  final _pre = TextEditingController(text: '0');
  final _post = TextEditingController(text: '0');
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pre.dispose();
    _post.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    try {
      final d = await ref.read(jellyfinClientProvider).getTimerDefaults(
          baseUrl: s.baseUrl, token: s.accessToken, programId: widget.programId);
      _pre.text = '${((d['PrePaddingSeconds'] as num?)?.toInt() ?? 0) ~/ 60}';
      _post.text = '${((d['PostPaddingSeconds'] as num?)?.toInt() ?? 0) ~/ 60}';
      if (mounted) setState(() => _defaults = d);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _record({required bool series}) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    final defaults = _defaults;
    if (s == null || defaults == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final preMin = int.tryParse(_pre.text) ?? 0;
    final postMin = int.tryParse(_post.text) ?? 0;
    final timer = <String, dynamic>{
      ...defaults,
      'PrePaddingSeconds': preMin * 60,
      'PostPaddingSeconds': postMin * 60,
      'IsPrePaddingRequired': preMin > 0,
      'IsPostPaddingRequired': postMin > 0,
    };
    setState(() => _busy = true);
    try {
      final client = ref.read(jellyfinClientProvider);
      if (series) {
        await client.createSeriesTimer(
            baseUrl: s.baseUrl, token: s.accessToken, timer: timer);
        ref.invalidate(adminSeriesTimersProvider);
      } else {
        await client.createTimer(
            baseUrl: s.baseUrl, token: s.accessToken, timer: timer);
        ref.invalidate(adminTimersProvider);
      }
      nav.pop();
      showSnackOn(messenger,
          series ? l.playerSeriesRecordingSet : l.playerRecordingSet);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _padField(TextEditingController c, String label) => Expanded(
        child: TvTextField(
          controller: c,
          label: label,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          suffixText: AppLocalizations.of(context).playerMinutesSuffix,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.playerRecord),
      content: _error != null
          ? Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error))
          : _defaults == null
              ? const SizedBox(
                  height: 60, child: Center(child: AppSpinner()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ('${_defaults!['Name'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('${_defaults!['Name']}',
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                    Text(l.playerPadding,
                        style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _padField(_pre, l.playerStartBefore),
                        const SizedBox(width: 12),
                        _padField(_post, l.playerStopAfter),
                      ],
                    ),
                  ],
                ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        if (widget.allowSeries)
          TextButton(
            onPressed: (_busy || _defaults == null)
                ? null
                : () => _record(series: true),
            child: Text(l.playerRecordSeries),
          ),
        FilledButton(
          onPressed:
              (_busy || _defaults == null) ? null : () => _record(series: false),
          child: _busy
              ? AppSpinner.inline()
              : Text(l.playerRecord),
        ),
      ],
    );
  }
}
