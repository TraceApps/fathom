import 'package:flutter/material.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../theme/app_theme.dart';
import 'app_spinner.dart';
import 'arr_actions.dart';
import 'arr_widgets.dart';

/// Asks before deleting several of a show's episode files (a season, or a
/// pick from Manage Files), then deletes them. Offers to unmonitor those
/// episodes too, on by default: left monitored, Sonarr would look for them
/// again and could download them straight back. True when deleted.
Future<bool> showArrDeleteFilesDialog(
  BuildContext context, {
  required SonarrClient client,
  required ArrSeries series,
  required List<ArrFile> files,
  required List<int> episodeIds,
}) async {
  if (files.isEmpty) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _DeleteFilesDialog(
      client: client,
      series: series,
      files: files,
      episodeIds: episodeIds,
    ),
  );
  return ok ?? false;
}

class _DeleteFilesDialog extends StatefulWidget {
  final SonarrClient client;
  final ArrSeries series;
  final List<ArrFile> files;
  final List<int> episodeIds;
  const _DeleteFilesDialog({
    required this.client,
    required this.series,
    required this.files,
    required this.episodeIds,
  });

  @override
  State<_DeleteFilesDialog> createState() => _DeleteFilesDialogState();
}

class _DeleteFilesDialogState extends State<_DeleteFilesDialog> {
  bool _unmonitor = true;
  bool _busy = false;

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final c = widget.client;
    setState(() => _busy = true);
    final ok = await arrRun(context, () async {
      await c.deleteEpisodeFiles([for (final f in widget.files) f.id]);
      if (_unmonitor && widget.episodeIds.isNotEmpty) {
        await c.setEpisodesMonitored(widget.episodeIds, false);
      }
    }, done: l.arrFilesDeleted(widget.files.length));
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
    final size = widget.files.fold<int>(0, (t, f) => t + f.size);
    return ArrDialogFrame(
      client: widget.client,
      images: widget.series.images,
      heading: l.arrDeleteFiles,
      title: widget.series.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.arrDeleteFilesCount(widget.files.length, arrSize(size))),
          const SizedBox(height: 8),
          if (widget.episodeIds.isNotEmpty)
            ArrCheck(
              label: l.arrUnmonitorThem,
              hint: l.arrUnmonitorThemHint(widget.client.kind.appName),
              value: _unmonitor,
              onChanged: _busy ? null : (v) => setState(() => _unmonitor = v),
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
