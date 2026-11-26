import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/tv_mode.dart';
import 'app_snack.dart';

/// An on-screen keyboard driven entirely by the D-pad, for Android TV.
///
/// Flutter receives the remote's D-pad keys but the *system* TV keyboard can't
/// be driven through it, so on TV we hide the system IME and edit the bound
/// [controller] with this instead. Every key is a normal focusable widget, so
/// the framework's arrow-key focus traversal and the app-wide Select→Activate
/// mapping (see FathomApp) make it fully remote-navigable. Editing is cursor-
/// aware (◀ ▶ keys move the caret; inserts/backspace act at the caret).
class TvKeyboard extends StatefulWidget {
  const TvKeyboard({
    super.key,
    required this.controller,
    this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback? onSubmit;

  @override
  State<TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<TvKeyboard> {
  bool _shift = false;
  bool _symbols = false;

  // Number row carries a secondary symbol hint (small, top-right) like stock.
  static const _numberRow = '1234567890';
  static const _numberHints = '!@#\$%^&*()';
  // Bottom letter/symbol row (8 chars) sits between shift and backspace.
  static const _lettersBottom = 'zxcvbnm,';
  static const _symbolsBottom = '.,<>[]{}\\';
  // Symbol page middle rows (10 wide each). '-' and '_' live on the action row
  // on both pages, so they're not repeated here.
  static const _symbolRows = ['@#\$%&*()/=', '+"\':;!?~`|'];

  int get _caret {
    final sel = widget.controller.selection;
    final len = widget.controller.text.length;
    if (sel.start < 0) return len;
    return sel.start.clamp(0, len);
  }

  void _insert(String ch) {
    final c = widget.controller;
    final text = c.text;
    final sel = c.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final newText = text.replaceRange(start, end, ch);
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + ch.length),
    );
  }

  void _backspace() {
    final c = widget.controller;
    final text = c.text;
    final sel = c.selection;
    var start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    if (start == end) {
      if (start == 0) return;
      start -= 1; // delete the char before the caret
    }
    final newText = text.replaceRange(start, end, '');
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start),
    );
  }

  void _move(int delta) {
    final c = widget.controller;
    final len = c.text.length;
    final next = (_caret + delta).clamp(0, len);
    c.selection = TextSelection.collapsed(offset: next);
    setState(() {});
  }

  Widget _charKey(String ch) {
    final c = _shift && !_symbols ? ch.toUpperCase() : ch;
    return _TvKey(label: c, onTap: () => _insert(c));
  }

  @override
  Widget build(BuildContext context) {
    final middleRows = _symbols ? _symbolRows : const ['qwertyuiop', 'asdfghjkl.'];
    final bottom = _symbols ? _symbolsBottom : _lettersBottom;
    return FocusTraversalGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Number row (with symbol hints on the letters page) — always present.
          Row(
            children: [
              for (var i = 0; i < _numberRow.length; i++)
                _TvKey(
                  autofocus: i == 0,
                  label: _numberRow[i],
                  hint: _symbols ? null : _numberHints[i],
                  onTap: () => _insert(_numberRow[i]),
                ),
            ],
          ),
          for (final row in middleRows)
            Row(children: [for (final ch in row.split('')) _charKey(ch)]),
          // Bottom row: shift + 8 chars + backspace, to match stock.
          Row(
            children: [
              _TvKey(
                icon: _shift
                    ? Icons.keyboard_capslock_rounded
                    : Icons.arrow_upward_rounded,
                highlighted: _shift,
                onTap: _symbols ? () {} : () => setState(() => _shift = !_shift),
              ),
              for (final ch in bottom.split('')) _charKey(ch),
              _TvKey(icon: Icons.backspace_outlined, onTap: _backspace),
            ],
          ),
          // Action row: 123?/ABC, caret ◀ ▶, space, - _, submit (→).
          Row(
            children: [
              _TvKey(
                flex: 2,
                label: _symbols ? 'ABC' : '123?',
                onTap: () => setState(() => _symbols = !_symbols),
              ),
              _TvKey(icon: Icons.chevron_left_rounded, onTap: () => _move(-1)),
              _TvKey(icon: Icons.chevron_right_rounded, onTap: () => _move(1)),
              _TvKey(
                  flex: 5,
                  icon: Icons.space_bar_rounded,
                  onTap: () => _insert(' ')),
              _TvKey(label: '-', onTap: () => _insert('-')),
              _TvKey(label: '_', onTap: () => _insert('_')),
              _TvKey(
                flex: 2,
                icon: Icons.arrow_forward_rounded,
                primary: true,
                onTap: () => widget.onSubmit?.call(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single key: a focusable, remote-activatable button with a strong focus
/// highlight, and an optional secondary symbol hint in the top-right.
class _TvKey extends StatefulWidget {
  const _TvKey({
    this.label,
    this.icon,
    this.hint,
    required this.onTap,
    this.autofocus = false,
    this.flex = 1,
    this.primary = false,
    this.highlighted = false,
  });

  final String? label;
  final IconData? icon;
  final String? hint;
  final VoidCallback onTap;
  final bool autofocus;
  final int flex;
  final bool primary;
  final bool highlighted;

  @override
  State<_TvKey> createState() => _TvKeyState();
}

class _TvKeyState extends State<_TvKey> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    if (_focused) {
      bg = scheme.primary;
      fg = scheme.onPrimary;
    } else if (widget.primary) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else if (widget.highlighted) {
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurface;
    }
    return Expanded(
      flex: widget.flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: FocusableActionDetector(
          autofocus: widget.autofocus,
          onFocusChange: (v) => setState(() => _focused = v),
          mouseCursor: SystemMouseCursors.click,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _focused ? scheme.primary : Colors.transparent,
                  width: 2,
                ),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.5),
                            blurRadius: 10)
                      ]
                    : null,
              ),
              child: widget.icon != null
                  ? Icon(widget.icon, color: fg, size: 22)
                  : widget.hint == null
                      ? Text(
                          widget.label ?? '',
                          style: TextStyle(
                            color: fg,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      // Number keys: digit bottom-left, symbol hint top-right,
                      // offset so they don't overlap (stock keyboard style).
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned(
                              left: 12,
                              bottom: 8,
                              child: Text(
                                widget.label ?? '',
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 10,
                              child: Text(
                                widget.hint!,
                                style: TextStyle(
                                  color: fg.withValues(alpha: 0.5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the [TvKeyboard] in a slide-up sheet bound to [controller]. Returns
/// when the user closes it (submit or Back). Used by [TvTextField] on TV.
Future<void> showTvKeyboard(
  BuildContext context, {
  required TextEditingController controller,
  String? label,
  bool obscure = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _KeyboardPreview(
                      controller: controller,
                      label: label,
                      obscure: obscure,
                    ),
                  ),
                  // Voice entry, for remotes with a mic button. Hidden when the
                  // field is obscured (dictating a password aloud is a footgun)
                  // or when no recognition service is available on the device.
                  if (!obscure) ...[
                    const SizedBox(width: 10),
                    _VoiceButton(controller: controller),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TvKeyboard(
                controller: controller,
                onSubmit: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The text-entry preview above the sheet keyboard: shows the live value with a
/// blinking caret at the cursor position.
class _KeyboardPreview extends StatefulWidget {
  const _KeyboardPreview(
      {required this.controller, this.label, this.obscure = false});
  final TextEditingController controller;
  final String? label;
  final bool obscure;

  @override
  State<_KeyboardPreview> createState() => _KeyboardPreviewState();
}

class _KeyboardPreviewState extends State<_KeyboardPreview> {
  Timer? _blink;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _blink = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _blink?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary, width: 2),
      ),
      child: Row(
        children: [
          if (widget.label != null)
            Text('${widget.label}:  ',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (_, value, _) {
                final len = value.text.length;
                final caret = value.selection.start < 0
                    ? len
                    : value.selection.start.clamp(0, len);
                final display = widget.obscure ? '•' * len : value.text;
                final before = display.substring(0, caret.clamp(0, display.length));
                final after = display.substring(caret.clamp(0, display.length));
                final style = TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w600);
                return RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(children: [
                    TextSpan(text: before, style: style),
                    TextSpan(
                      text: '▏',
                      style: style.copyWith(
                        color: _on ? scheme.primary : Colors.transparent,
                      ),
                    ),
                    TextSpan(text: after, style: style),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Inserts [text] into [c] at the caret (or replaces the selection), matching
/// the on-screen keyboard's own editing so voice and key presses stay in sync.
void _insertAtCaret(TextEditingController c, String text) {
  final existing = c.text;
  final sel = c.selection;
  final start = sel.start < 0 ? existing.length : sel.start;
  final end = sel.end < 0 ? existing.length : sel.end;
  // A space between the previous word and the dictated phrase, unless we're at
  // the very start or already right after a space.
  final needsSpace = start > 0 && !existing.substring(0, start).endsWith(' ');
  final insert = needsSpace ? ' $text' : text;
  final newText = existing.replaceRange(start, end, insert);
  c.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: start + insert.length),
  );
}

/// A mic button on the keyboard sheet that dictates into the bound controller.
/// A no-op-with-a-message when the device has no speech recogniser; requests the
/// microphone permission on first use.
class _VoiceButton extends StatefulWidget {
  const _VoiceButton({required this.controller});
  final TextEditingController controller;

  @override
  State<_VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<_VoiceButton> {
  final SpeechToText _speech = SpeechToText();
  bool _initTried = false;
  bool _available = false;
  bool _listening = false;
  bool _focused = false;

  @override
  void dispose() {
    if (_speech.isListening) _speech.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_initTried) {
      _initTried = true;
      _available = await _speech.initialize(
        onStatus: (s) {
          if (mounted && (s == 'done' || s == 'notListening')) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    }
    if (!_available) {
      if (mounted) {
        showSnack(context, AppLocalizations.of(context).tvVoiceUnavailable);
      }
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        if (r.finalResult && r.recognizedWords.isNotEmpty) {
          _insertAtCaret(widget.controller, r.recognizedWords);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _listening || _focused;
    return FocusableActionDetector(
      onFocusChange: (v) => setState(() => _focused = v),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _toggle();
            return null;
          },
        ),
      },
      child: Semantics(button: true, label: AppLocalizations.of(context).tvVoiceInput, child: GestureDetector(
        onTap: _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _listening
                ? scheme.primary
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? scheme.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: Icon(
            _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
            color: _listening ? scheme.onPrimary : scheme.onSurface,
            size: 26,
          ),
        ),
      )),
    );
  }
}

/// A text field that works with a D-pad remote. On a TV it renders as a
/// focusable tile that opens [showTvKeyboard] on Select (the system keyboard
/// can't be driven by the remote); everywhere else it's a normal [TextField].
class TvTextField extends StatelessWidget {
  const TvTextField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    // These are forwarded to the normal (non-TV) TextField so desktop/mobile keep
    // their original behaviour; the TV tile + on-screen keyboard don't use them.
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.helperText,
    this.suffixText,
    this.maxLines = 1,
    this.textAlign = TextAlign.start,
    this.style,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final String? helperText;
  final String? suffixText;
  final int? maxLines;
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) {
      return TextField(
        controller: controller,
        obscureText: obscure,
        enabled: enabled,
        autofocus: autofocus,
        keyboardType: keyboardType,
        autocorrect: false,
        onSubmitted: onSubmitted,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        autofillHints: autofillHints,
        textAlign: textAlign,
        style: style,
        maxLines: obscure ? 1 : maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          suffixText: suffixText,
          prefixIcon: icon != null ? Icon(icon) : null,
        ),
      );
    }
    return _TvFieldTile(
      controller: controller,
      label: label,
      icon: icon,
      hint: hint,
      obscure: obscure,
      autofocus: autofocus,
      onOpen: enabled
          ? () => showTvKeyboard(context,
              controller: controller, label: label, obscure: obscure)
          : null,
    );
  }
}

class _TvFieldTile extends StatefulWidget {
  const _TvFieldTile({
    required this.controller,
    required this.label,
    this.icon,
    this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.onOpen,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final String? hint;
  final bool obscure;
  final bool autofocus;
  final VoidCallback? onOpen;

  @override
  State<_TvFieldTile> createState() => _TvFieldTileState();
}

class _TvFieldTileState extends State<_TvFieldTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      enabled: widget.onOpen != null,
      onFocusChange: (v) => setState(() => _focused = v),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onOpen?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? scheme.primary : Colors.transparent,
              width: 2,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.4),
                        blurRadius: 10)
                  ]
                : null,
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: scheme.onSurfaceVariant, size: 20),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (_, value, _) {
                    final empty = value.text.isEmpty;
                    final shown =
                        widget.obscure ? '•' * value.text.length : value.text;
                    return Column(
                      // As tall as its two lines: in a dialog there's height
                      // to spare, and the tile would fill it.
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.label,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          empty ? (widget.hint ?? '') : shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: empty
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
