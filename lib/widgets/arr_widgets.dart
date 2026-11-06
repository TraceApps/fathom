import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import 'cached_image.dart';

// The colors Sonarr and Radarr use on their poster bars and chips.
const arrDownloadedColor = Color(0xFF27C24C);
const arrMissingColor = Color(0xFFF05050);
const arrUnreleasedColor = Color(0xFF5D9CEC);
const arrContinuingColor = Color(0xFF5D9CEC);
const arrQueuedColor = Color(0xFF7A43B6);
const arrWarningColor = Color(0xFFFFA500);

Color arrStateColor(ArrState s, ColorScheme scheme) => switch (s) {
  ArrState.downloaded => arrDownloadedColor,
  ArrState.missing => arrMissingColor,
  ArrState.unreleased => arrUnreleasedColor,
  ArrState.continuing => arrContinuingColor,
  ArrState.ended => arrDownloadedColor,
  ArrState.unmonitored => scheme.outline,
};

String arrStateLabel(AppLocalizations l, ArrState s) => switch (s) {
  ArrState.downloaded => l.arrDownloaded,
  ArrState.missing => l.arrMissing,
  ArrState.unreleased => l.arrNotReleased,
  ArrState.continuing => l.arrContinuing,
  ArrState.ended => l.arrEnded,
  ArrState.unmonitored => l.arrUnmonitored,
};

/// "4.3 GB", "812 MB". Sonarr and Radarr count in powers of 1024.
String arrSize(num bytes) {
  const k = 1024;
  if (bytes >= k * k * k * k) {
    return '${(bytes / (k * k * k * k)).toStringAsFixed(2)} TB';
  }
  if (bytes >= k * k * k) {
    return '${(bytes / (k * k * k)).toStringAsFixed(1)} GB';
  }
  if (bytes >= k * k) return '${(bytes / (k * k)).toStringAsFixed(0)} MB';
  if (bytes >= k) return '${(bytes / k).toStringAsFixed(0)} KB';
  return '${bytes.toInt()} B';
}

String arrDate(BuildContext context, DateTime d) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(d);

String arrTime(BuildContext context, DateTime d) =>
    DateFormat.jm(Localizations.localeOf(context).toString()).format(d);

/// "2h 14m", "47m".
String arrDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

/// A picture of a title from Sonarr or Radarr. Their own copies need the API
/// key; pictures from TMDB or TheTVDB don't, but get it harmlessly anyway.
class ArrArt extends StatelessWidget {
  final ArrClient? client;
  final List<ArrImage> images;
  final String type; // poster, fanart
  final int width;
  final IconData placeholderIcon;
  final Alignment alignment;

  const ArrArt({
    super.key,
    required this.client,
    required this.images,
    this.type = 'poster',
    this.width = 342,
    this.placeholderIcon = Icons.movie_rounded,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final url = client?.imageUrl(images, type, width: width);
    final scheme = Theme.of(context).colorScheme;
    final ph = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(placeholderIcon, color: scheme.onSurfaceVariant),
    );
    if (url == null) return ph;
    final local = !url.startsWith('http') || url.startsWith(client!.baseUrl);
    return CachedImage(
      url: url,
      alignment: alignment,
      cacheWidth: type == 'poster' ? width.toDouble() : null,
      headers: local ? client!.imageHeaders : null,
      errorBuilder: (_) => ph,
    );
  }
}

/// The thin colored bar across a poster's foot, as on Sonarr's and Radarr's
/// posters: how much of a show is there, or where a movie stands.
class ArrPosterBar extends StatelessWidget {
  final Color color;
  final double fraction; // 0 to 1, how much of the bar is filled
  const ArrPosterBar({super.key, required this.color, this.fraction = 1});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: 5,
        width: double.infinity,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(0, 1).toDouble(),
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}

/// A small rounded status label, tinted by its color.
class ArrChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const ArrChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          // A long label (a long quality name, a translation) shortens
          // instead of spilling out of a narrow row.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label and its value, one row of a detail page's facts.
class ArrFact extends StatelessWidget {
  final String label;
  final String value;
  const ArrFact({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// A banner for an app that didn't answer, shown above what the other did.
class ArrErrorBanner extends StatelessWidget {
  final Map<ArrKind, String> errors;
  const ArrErrorBanner({super.key, required this.errors});

  @override
  Widget build(BuildContext context) {
    if (errors.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          for (final e in errors.entries)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: scheme.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.value,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Section heading on Arr pages.
TextStyle? arrSectionStyle(ThemeData theme) =>
    theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

/// Opens Fathom's own page for a show or movie.
void arrOpenTitle(BuildContext context, ArrKind kind, int? id) {
  if (id == null) return;
  context.push(kind == ArrKind.sonarr ? '/arr/series/$id' : '/arr/movie/$id');
}

/// How a history event reads: its name, icon and color, the way the apps
/// show them.
(String, IconData, Color) arrHistoryEvent(
  AppLocalizations l,
  ColorScheme scheme,
  String eventType,
) => switch (eventType) {
  'grabbed' => (
    l.arrEventGrabbed,
    Icons.cloud_download_rounded,
    arrUnreleasedColor,
  ),
  'downloadFolderImported' || 'seriesFolderImported' || 'movieFolderImported' =>
    (l.arrEventImported, Icons.download_done_rounded, arrDownloadedColor),
  'downloadFailed' => (l.arrEventFailed, Icons.error_rounded, arrMissingColor),
  'episodeFileDeleted' || 'movieFileDeleted' => (
    l.arrEventDeleted,
    Icons.delete_rounded,
    arrMissingColor,
  ),
  'episodeFileRenamed' || 'movieFileRenamed' => (
    l.arrEventRenamed,
    Icons.drive_file_rename_outline_rounded,
    scheme.outline,
  ),
  'downloadIgnored' => (l.arrEventIgnored, Icons.block_rounded, scheme.outline),
  _ => (l.arrEventOther, Icons.history_rounded, scheme.outline),
};
