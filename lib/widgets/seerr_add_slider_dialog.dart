import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/seerr_custom_slider.dart';
import '../state/seerr_providers.dart';
import 'tv_keyboard.dart';
import 'app_spinner.dart';

/// Create a custom Discover slider (movie/TV genre, or a keyword search).
Future<SeerrCustomSlider?> showSeerrAddSliderDialog(
    BuildContext context, WidgetRef ref) {
  return showDialog<SeerrCustomSlider>(
    context: context,
    builder: (_) => const _AddSliderDialog(),
  );
}

class _AddSliderDialog extends ConsumerStatefulWidget {
  const _AddSliderDialog();
  @override
  ConsumerState<_AddSliderDialog> createState() => _AddSliderDialogState();
}

class _AddSliderDialogState extends ConsumerState<_AddSliderDialog> {
  final _titleController = TextEditingController();
  final _keywordController = TextEditingController();
  String _type = 'movieGenre';
  int? _genreId;

  @override
  void initState() {
    super.initState();
    // The TV keyboard edits the controller directly (no per-keystroke onChanged),
    // so listen to keep the Add button's enabled state in sync as text changes.
    _keywordController.addListener(_onKeyword);
  }

  void _onKeyword() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _keywordController.removeListener(_onKeyword);
    _titleController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  bool get _isGenre => _type == 'movieGenre' || _type == 'tvGenre';

  bool get _valid =>
      _isGenre ? _genreId != null : _keywordController.text.trim().isNotEmpty;

  void _save() {
    final genres = _isGenre
        ? (_type == 'tvGenre'
            ? ref.read(seerrTvGenresProvider).asData?.value
            : ref.read(seerrMovieGenresProvider).asData?.value)
        : null;
    final genreName = genres
        ?.cast<dynamic>()
        .firstWhere((g) => g.id == _genreId, orElse: () => null)
        ?.name as String?;
    final defaultTitle = _isGenre
        ? (genreName ?? AppLocalizations.of(context).detailGenre)
        : _keywordController.text.trim();
    final title = _titleController.text.trim().isEmpty
        ? defaultTitle
        : _titleController.text.trim();
    Navigator.pop(
      context,
      SeerrCustomSlider(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        type: _type,
        data: _isGenre ? '$_genreId' : _keywordController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final genresAsync = _type == 'tvGenre'
        ? ref.watch(seerrTvGenresProvider)
        : ref.watch(seerrMovieGenresProvider);

    return AlertDialog(
      scrollable: true,
      title: Text(l.detailAddSlider),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TvTextField(
              controller: _titleController,
              label: l.detailTitle,
              hint: l.detailSliderTitleHint,
            ),
            const SizedBox(height: 16),
            Text(l.detailType, style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'movieGenre', label: Text(l.detailMovieGenre)),
                ButtonSegment(value: 'tvGenre', label: Text(l.detailTvGenre)),
                ButtonSegment(value: 'keyword', label: Text(l.detailKeyword)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _genreId = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_isGenre)
              genresAsync.when(
                loading: () => const Center(
                    child: Padding(
                        padding: EdgeInsets.all(8),
                        child: AppSpinner())),
                error: (e, _) => Text(errorText(e)),
                data: (genres) => DropdownButtonFormField<int>(
                  initialValue: _genreId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: l.detailGenre,
                      border: const OutlineInputBorder()),
                  items: [
                    for (final g in genres)
                      DropdownMenuItem(value: g.id, child: Text(g.name)),
                  ],
                  onChanged: (v) => setState(() => _genreId = v),
                ),
              )
            else
              TvTextField(
                controller: _keywordController,
                label: l.detailKeyword,
                hint: l.detailKeywordHint,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel)),
        FilledButton(
          onPressed: _valid ? _save : null,
          child: Text(l.commonAdd),
        ),
      ],
    );
  }
}
