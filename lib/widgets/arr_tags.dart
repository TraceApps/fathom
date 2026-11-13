import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../theme/app_theme.dart';
import 'app_snack.dart';

/// A title's tags as chips: every tag the app has, ticked when the title has
/// it, and New Tag to make one. Used by Edit and Add.
class ArrTagPicker extends ConsumerStatefulWidget {
  final ArrClient client;
  final List<int> selected;
  final ValueChanged<List<int>>? onChanged;

  const ArrTagPicker({
    super.key,
    required this.client,
    required this.selected,
    required this.onChanged,
  });

  @override
  ConsumerState<ArrTagPicker> createState() => _ArrTagPickerState();
}

class _ArrTagPickerState extends ConsumerState<ArrTagPicker> {
  bool _creating = false;

  void _toggle(int id, bool on) {
    // Ids of tags deleted since (from saved defaults) can't be seen here, so
    // they go when the tags are changed rather than linger unseen.
    final known = ref.read(arrTagsProvider(widget.client.kind)).asData?.value;
    final live = known == null ? null : {for (final t in known) t.id};
    final next = [
      for (final t in widget.selected)
        if (live == null || live.contains(t)) t,
    ];
    on ? next.add(id) : next.remove(id);
    widget.onChanged?.call(next);
  }

  Future<void> _newTag() async {
    final messenger = ScaffoldMessenger.of(context);
    final label = await showDialog<String>(
      context: context,
      builder: (_) => const _NewTagDialog(),
    );
    if (label == null || label.trim().isEmpty || !mounted) return;
    setState(() => _creating = true);
    try {
      final tag = await widget.client.createTag(label);
      ref.invalidate(arrTagsProvider(widget.client.kind));
      if (!widget.selected.contains(tag.id)) _toggle(tag.id, true);
    } catch (e) {
      showSnackOn(messenger, e.toString(), kind: SnackKind.error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tags =
        ref.watch(arrTagsProvider(widget.client.kind)).asData?.value ??
        const <ArrTag>[];
    final enabled = widget.onChanged != null && !_creating;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(l.arrTags, style: theme.textTheme.labelLarge),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tags)
                FilterChip(
                  label: Text(t.label),
                  selected: widget.selected.contains(t.id),
                  onSelected: enabled ? (v) => _toggle(t.id, v) : null,
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: Text(l.arrNewTag),
                onPressed: enabled ? _newTag : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              l.arrTagsHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewTagDialog extends StatefulWidget {
  const _NewTagDialog();

  @override
  State<_NewTagDialog> createState() => _NewTagDialogState();
}

class _NewTagDialogState extends State<_NewTagDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    void done() => Navigator.pop(context, _text.text);
    return AlertDialog(
      title: Text(l.arrNewTag),
      content: TextField(
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l.arrTagLabel,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => done(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: done,
          child: Text(l.commonAdd),
        ),
      ],
    );
  }
}
