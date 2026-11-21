import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/arr_providers.dart';

/// Calls [onPoll] every [every] while the window is showing, and once on
/// the way back to it.
///
/// Under a page opened over this one nothing is asked for when [onPoll]
/// invalidates what the page watches: a page that isn't showing stops
/// listening, so the reload waits and runs once, on the way back.
class ArrPoll extends StatefulWidget {
  final Duration every;

  /// An answer is still on its way. Asking again before a slow server has
  /// answered would throw its answer away, and so never show one.
  final bool waiting;
  final VoidCallback onPoll;
  final Widget child;
  const ArrPoll({
    super.key,
    required this.every,
    required this.waiting,
    required this.onPoll,
    required this.child,
  });

  @override
  State<ArrPoll> createState() => _ArrPollState();
}

class _ArrPollState extends State<ArrPoll> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didUpdateWidget(ArrPoll old) {
    super.didUpdateWidget(old);
    // A new pace takes over at once, unless the window is out of sight:
    // coming back starts it.
    if (old.every != widget.every && _timer != null) _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.every, (_) {
      if (mounted && !widget.waiting) widget.onPoll();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Back from out of sight: catch up at once.
        if (_timer == null) {
          _start();
          widget.onPoll();
        }
      case AppLifecycleState.inactive:
        // Still showing (a desktop window that isn't the active one, a
        // split screen): keep going.
        break;
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Asks for the queue again every [every] while the window is showing: the
/// whole queue, or with [countOnly] just the Activity tab's count.
class ArrQueuePoll extends ConsumerWidget {
  final Duration every;
  final bool countOnly;
  final Widget child;
  const ArrQueuePoll({
    super.key,
    required this.every,
    this.countOnly = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => ArrPoll(
    every: every,
    waiting: countOnly
        ? ref.watch(arrQueueStatusProvider.select((a) => a.isLoading))
        : ref.watch(arrQueueProvider.select((a) => a.isLoading)),
    onPoll: () => countOnly
        ? ref.invalidate(arrQueueStatusProvider)
        : ref.invalidate(arrQueueProvider),
    child: child,
  );
}
