import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

/// A slim inline error for a single content row (a horizontal section), with an
/// optional Retry. Far friendlier than a raw exception string, and small enough
/// not to blow out a row's height.
class SectionError extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  const SectionError({super.key, this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message ?? l.miscCouldntLoad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(l.commonRetry)),
        ],
      ),
    );
  }
}

/// How wide the button under an error or an empty page gets.
const kStateActionWidth = 320.0;

/// A consistent error state: icon, message, and an optional Retry action.
/// Use in async `error:` builders so failures look the same everywhere.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Stay centred when there's room, but scroll rather than overflow in a
    // short window (error messages can run long). minHeight is skipped when the
    // parent is unbounded.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight:
                  constraints.maxHeight.isFinite ? constraints.maxHeight : 0),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.errorContainer.withValues(alpha: 0.35),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.error_outline_rounded,
                        size: 42, color: scheme.error),
                  ),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 16),
                    // A button the width of a button: on a wide window it
                    // ran from one edge of the page to the other.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: kStateActionWidth),
                      child: FilledButton.tonalIcon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(l.commonRetry),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
