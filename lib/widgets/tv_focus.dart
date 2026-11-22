import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mergeSort;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/tv_mode.dart';

/// The nav rail's D-pad landing node. A content row escapes to it when the
/// remote presses LEFT past the first card; the rail assigns it to the active
/// destination so LEFT always lands on the current section. Global because the
/// rail and the content rows live in different subtrees.
final FocusNode tvNavBarNode = FocusNode(debugLabel: 'tvNavRail');

/// The content card the remote last left when it jumped to the rail, so RIGHT
/// out of the rail returns to where you were rather than the top of the page.
FocusNode? tvLastContentFocus;

/// The scope wrapping the routed content on TV. Lets the rail hand focus back
/// into content (RIGHT) and lets [TvAutofocus] focus a fresh screen's first
/// item without accidentally grabbing a rail node.
final FocusScopeNode tvContentScope = FocusScopeNode(debugLabel: 'tvContent');

/// The focusable content nodes in reading order (top-to-bottom, left-to-right).
List<FocusNode> tvContentNodesInOrder() => _tvNodesInOrder(_tvFrontPage());

/// [page]'s stops in reading order.
List<FocusNode> _tvNodesInOrder(FocusNode page) {
  return page.traversalDescendants
      .where((n) => n.canRequestFocus && n.context != null)
      .toList()
    ..sort((a, b) {
      final dy = a.rect.top.compareTo(b.rect.top);
      return dy != 0 ? dy : a.rect.left.compareTo(b.rect.left);
    });
}

/// The page in front. A page that another was opened over stays built under
/// it, its stops where they were on the screen: "the first stop on screen" out
/// of everything built can then be one nobody sees, and the remote goes
/// nowhere visible. Each page of the shell's navigator is a scope of its own,
/// and the one in front is the one the content last gave the focus to.
FocusNode _tvFrontPage() {
  final front = tvContentScope.focusedChild;
  return front is FocusScopeNode ? front : tvContentScope;
}

/// Whether [n] is somewhere a page may open on: under the header band and not
/// a list's own toolbar, or a [TvLandingSpot].
bool _tvLands(FocusNode n) =>
    _tvLandingSpot(n) || (n.rect.top >= _tvHeaderCutoff && !_tvInChrome(n));

bool _tvLandingSpot(FocusNode n) =>
    n.context?.findAncestorWidgetOfExactType<TvLandingSpot>() != null;

/// Where the remote is on [page] (or was, when it has gone to the rail), if
/// that's a stop on the screen.
FocusNode? _tvRemembered(FocusNode page) {
  if (page is! FocusScopeNode) return null;
  var n = page.focusedChild;
  while (n is FocusScopeNode) {
    n = n.focusedChild;
  }
  if (n == null || n.context == null || !n.canRequestFocus) return null;
  return _tvOnScreen(n) ? n : null;
}

/// Scrolls [target]'s list up or down until it shows with [room] to spare:
/// the edge of the card it's in, not only the stop itself.
void _tvRevealVertically(FocusNode target, {double room = 16}) {
  final at = target.context;
  if (at == null) return;
  var scrollable = Scrollable.maybeOf(at);
  while (scrollable != null && scrollable.position.axis != Axis.vertical) {
    scrollable = Scrollable.maybeOf(scrollable.context);
  }
  final box = scrollable?.context.findRenderObject();
  if (scrollable == null || box is! RenderBox || !box.hasSize) return;
  final position = scrollable.position;
  final view = box.localToGlobal(Offset.zero) & box.size;
  final r = target.rect;
  final double by;
  if (r.top - room < view.top) {
    by = r.top - room - view.top;
  } else if (r.bottom + room > view.bottom) {
    by = r.bottom + room - view.bottom;
  } else {
    return;
  }
  position.animateTo(
    (position.pixels + by)
        .clamp(position.minScrollExtent, position.maxScrollExtent),
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
  );
}

/// The logical screen size, for on-screen visibility checks.
Size _tvScreenSize() {
  final v = WidgetsBinding.instance.platformDispatcher.views.first;
  return v.physicalSize / v.devicePixelRatio;
}

/// Whether a focus node is currently on-screen (its rect overlaps the display).
/// Used so entering content from the rail always lands on something the user can
/// SEE, never a scrolled-off node (which read as a "phantom" focus).
bool _tvOnScreen(FocusNode n) {
  if (n.context == null) return false;
  final r = n.rect;
  if (r.isEmpty) return false;
  return r.overlaps(Offset.zero & _tvScreenSize());
}

/// The height of the top-chrome band (app bar back button, filter icons, section
/// header). Focus should start on the content BELOW it, not on the back button.
double get _tvHeaderCutoff => _tvScreenSize().height * 0.16;

/// The look (about 200 ms apart) from which an opening page with nothing but
/// its toolbar under the header takes that as all there is: soon enough not
/// to leave the remote waiting on an empty list.
const _tvToolbarAfter = 4;

/// The node a fresh screen should focus first: the first on-screen content item
/// BELOW the top chrome, so the remote lands on the actual movie/show/album/track
/// — not the back button.
///
/// Grids and detail screens load their data ASYNC, so for the first frames the
/// only focusables are the app bar chrome. When [preferBelowHeader] is true we
/// return null in that case, so the caller keeps retrying until real content
/// appears rather than settling on the back button. Set it false as a last
/// resort (short screens with no content below the header, e.g. an empty state)
/// so there's always some landing spot.
///
/// [allowToolbar] accepts a list's own toolbar ([TvChrome]) under the header
/// when there's nothing else, even with [preferBelowHeader]: a list that has
/// stayed empty for a moment is most likely empty, not loading.
FocusNode? tvFirstVisibleContentNode({
  bool preferBelowHeader = false,
  bool allowToolbar = false,
}) =>
    _tvFirstVisibleIn(_tvFrontPage(),
        preferBelowHeader: preferBelowHeader, allowToolbar: allowToolbar);

FocusNode? _tvFirstVisibleIn(
  FocusNode page, {
  bool preferBelowHeader = false,
  bool allowToolbar = false,
}) {
  final nodes = _tvNodesInOrder(page);
  final visible = [for (final n in nodes) if (_tvOnScreen(n)) n];
  if (visible.isEmpty) return null;
  final headerCutoff = _tvHeaderCutoff;
  for (final n in visible) {
    if (n.rect.top >= headerCutoff && !_tvInChrome(n)) return n;
  }
  // Nothing below the header yet: either still loading (retry) or a genuinely
  // short screen (accept a list's own toolbar, then the top node).
  if (preferBelowHeader && !allowToolbar) return null;
  for (final n in visible) {
    if (n.rect.top >= headerCutoff) return n;
  }
  if (preferBelowHeader) return null;
  return visible.first;
}

/// The focus node of a [TvChrome]: what's under it is a screen's furniture,
/// not its content.
class _TvChromeNode extends FocusNode {
  _TvChromeNode()
      : super(
            debugLabel: 'tvChrome',
            canRequestFocus: false,
            skipTraversal: true);
}

/// Whether [node] is part of a screen's furniture (see [TvChrome]).
bool _tvInChrome(FocusNode node) {
  for (final a in node.ancestors) {
    if (a is _TvChromeNode) return true;
  }
  return false;
}

/// Marks a toolbar that sits below the app bar (a list's switch, search field
/// and filters) as furniture on TV: a screen that opens puts the remote on
/// the first thing in the list under it, not on the toolbar, which stays one
/// UP away. Off TV it's a pass-through.
class TvChrome extends StatefulWidget {
  const TvChrome({super.key, required this.child});
  final Widget child;

  @override
  State<TvChrome> createState() => _TvChromeState();
}

class _TvChromeState extends State<TvChrome> {
  final _TvChromeNode _node = _TvChromeNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    return Focus(
      focusNode: _node,
      canRequestFocus: false,
      skipTraversal: true,
      child: widget.child,
    );
  }
}

/// A stop up in the header band that a page opens on by choice: the search
/// field of a page that's for searching. [TvAutofocus] leaves the remote
/// there, where it otherwise moves it down onto the first thing under the
/// header (or, with nothing there, onto a toolbar or the Back button).
class TvLandingSpot extends StatelessWidget {
  const TvLandingSpot({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Focuses the content's first item when a screen opens on TV, so the remote
/// always has a landing spot (and RIGHT from the rail into a fresh screen has
/// somewhere to go). No-op if content already holds focus (e.g. a screen set its
/// own autofocus). Rebuilt per route — key it by the location.
class TvAutofocus extends StatefulWidget {
  const TvAutofocus({super.key, required this.child});
  final Widget child;

  @override
  State<TvAutofocus> createState() => _TvAutofocusState();
}

class _TvAutofocusState extends State<TvAutofocus> {
  @override
  void initState() {
    super.initState();
    if (!isTvDevice) return;
    // Opening a screen should land focus IN that screen's content, so the remote
    // always has a visible spot (and doesn't get stranded on the rail after
    // Flutter's focus-recovery grabs it when the previous screen's card
    // unmounts). Many screens (detail/album/grids) load their data ASYNC, so the
    // first focusable may not exist for several frames — retry until it does.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryFocus(0));
  }

  /// The toolbar this put the remote on while the list was still empty.
  FocusNode? _parked;

  void _tryFocus(int attempt) {
    if (!mounted) return;
    // The last attempt accepts a header-band fallback, so a screen with nothing
    // below the header (empty state, a short settings page) still gets a landing
    // spot instead of never focusing.
    final lastTry = attempt >= 15;
    void again() {
      if (attempt < 16) {
        Future.delayed(
            const Duration(milliseconds: 200), () => _tryFocus(attempt + 1));
      }
    }

    // Something over the whole shell (a dialog) has the remote: it stays there.
    if (ModalRoute.of(context)?.isCurrent == false) return again();
    final page = _tvFrontPage();
    final pf = FocusManager.instance.primaryFocus;
    // Put on a toolbar to wait, and moved on from it since: it's the
    // person's now.
    if (_parked != null && pf != _parked) return;
    // "Settled" means focus is on a real content item BELOW the top chrome. Focus
    // sitting on the app bar back button (which is inside the content scope, and
    // is all that exists while a grid/detail loads async) does NOT count — keep
    // trying so it moves onto the movie/album once it appears.
    final onContent = pf != null &&
        pf.context != null &&
        page.traversalDescendants.contains(pf);
    if (onContent && _tvLands(pf)) return;
    final node = tvFirstVisibleContentNode(
        preferBelowHeader: !lastTry, allowToolbar: attempt >= _tvToolbarAfter);
    if (node != null) {
      node.requestFocus();
      if (_tvInChrome(node) && !lastTry) {
        // On a list's toolbar for now: down onto the list if it comes.
        _parked = node;
        return again();
      }
      if (!lastTry) return; // landed below the header: done
    }
    // Nothing below the header yet (still loading): retry for a few seconds.
    again();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opens the page it wraps with the remote on its first stop under the header,
/// on a TV. [TvAutofocus] only does that when the section changes: a page
/// opened over another (a title out of a list) is no change of section, and
/// without this it opens with nothing lit until a key is pressed.
///
/// It leaves the remote alone once it's somewhere on the page, by the page's
/// own choice (an autofocus) or the person's, and when something has been
/// opened over the page in the meantime. Coming back to the page needs nothing:
/// the remote returns to where it was by itself.
///
/// A dialog can use it the same way, with its row of buttons in a [TvChrome]:
/// it then opens on its first choice, and on a button only when it has no
/// choices.
///
/// What a page is still loading can turn out to come first (a choice that
/// has nothing to offer until its list arrives). For a few seconds, and only
/// until a key is pressed, the remote moves up to it.
class TvPageLanding extends StatefulWidget {
  const TvPageLanding({super.key, required this.child});
  final Widget child;

  @override
  State<TvPageLanding> createState() => _TvPageLandingState();
}

class _TvPageLandingState extends State<TvPageLanding> {
  /// The stop this opened the page on, while it's still its to correct.
  FocusNode? _chosen;

  /// When that was, on the clock the frames run by.
  Duration? _chosenAt;

  /// A key was pressed on the page: where the remote is, is the person's.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    if (!isTvDevice) return;
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _try(0));
  }

  @override
  void dispose() {
    if (isTvDevice) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // The press only: the page can open on a key that's still held, and its
  // release comes after.
  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) _touched = true;
    return false;
  }

  /// Looks again after each frame for a stop that comes before the chosen
  /// one, now that more of the page is there.
  void _watch() {
    WidgetsBinding.instance.addPostFrameCallback((now) {
      final chosen = _chosen;
      if (!mounted || _touched || chosen == null) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      final since = _chosenAt ??= now;
      if (now - since > const Duration(seconds: 3)) return;
      final page = FocusScope.of(context);
      if (!page.hasFocus || _tvRemembered(page) != chosen) return;
      final first = _tvFirstVisibleIn(page, preferBelowHeader: true);
      if (first != null && first != chosen) {
        first.requestFocus();
        _chosen = first;
      }
      _watch();
    });
  }

  void _try(int attempt) {
    if (!mounted) return;
    // A page or a dialog over this one: the remote is theirs now.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final lastTry = attempt >= 15;
    void again() {
      if (attempt < 16) {
        Future.delayed(
            const Duration(milliseconds: 200), () => _try(attempt + 1));
      }
    }

    final page = FocusScope.of(context);
    // The remote is off the page (on the rail), or the page isn't given the
    // focus yet: nothing to move, look again in a moment.
    if (!page.hasFocus) return again();
    if (_tvRemembered(page) != null) return;
    final node = _tvFirstVisibleIn(page,
        preferBelowHeader: !lastTry, allowToolbar: attempt >= _tvToolbarAfter);
    if (node != null) {
      node.requestFocus();
      _chosen = node;
      _watch();
      if (!lastTry) return;
    }
    // Nothing under the header yet (still loading): look again.
    again();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The routed content of the shell on a TV: one scope for it all (the rail
/// hands the remote back into it), LEFT off its edge going to the rail, and a
/// landing for each section.
class TvContent extends StatelessWidget {
  const TvContent({super.key, required this.location, required this.child});

  /// The section showing: the landing is made anew when it changes.
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) => FocusScope(
        node: tvContentScope,
        // On TV, LEFT with no same-row neighbour escapes to the nav rail from
        // ANY screen (grids, lists, detail pages), so the rail is never a dead
        // end. Home's rows opt out via their own TvFocusRow groups. TvAutofocus
        // (keyed by route) gives each fresh screen a focused landing spot.
        child: FocusTraversalGroup(
          policy: TvContentTraversalPolicy(),
          child: TvAutofocus(
            key: ValueKey(location),
            child: Material(color: Colors.transparent, child: child),
          ),
        ),
      );
}

/// A horizontal content row (poster/landscape strip) turned into a self-contained
/// D-pad group: LEFT/RIGHT walk the cards, LEFT past the first card jumps to the
/// nav rail, and UP/DOWN hand off to the neighbouring row. Wrap a row's
/// horizontal `ListView` in this ONLY on TV; elsewhere use the list directly so
/// desktop/mouse traversal is unchanged.
class TvFocusRow extends StatefulWidget {
  const TvFocusRow({super.key, this.stacked = false, required this.child});
  final Widget child;

  /// For rows piled one over another that don't line up: a card's buttons at
  /// its right edge, its strip of posters under them at the left. UP and DOWN
  /// then go to the stacked row right above or below, wherever on it the
  /// remote is, where a plain row only moves to what's straight above or
  /// below the card it's on (and would step over the buttons).
  final bool stacked;

  @override
  State<TvFocusRow> createState() => _TvFocusRowState();
}

class _TvFocusRowState extends State<TvFocusRow> {
  // A non-focusable anchor for the row: never a focus target itself, but its
  // geometry is the reference the policy uses to hand UP/DOWN to the row above
  // or below.
  final _TvRowNode _groupNode = _TvRowNode();

  @override
  void dispose() {
    _groupNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _groupNode.stacked = widget.stacked;
    return FocusTraversalGroup(
      policy: _TvRowPolicy(_groupNode),
      child: Focus(
        focusNode: _groupNode,
        canRequestFocus: false,
        skipTraversal: true,
        child: widget.child,
      ),
    );
  }
}

/// A [TvFocusRow]'s anchor.
class _TvRowNode extends FocusNode {
  _TvRowNode()
      : super(
            debugLabel: 'tvRow',
            canRequestFocus: false,
            skipTraversal: true);

  /// See [TvFocusRow.stacked].
  bool stacked = false;

  /// What the remote was on when it last left this row upward or downward:
  /// where it comes back to.
  FocusNode? last;
}

class _TvRowPolicy extends WidgetOrderTraversalPolicy {
  _TvRowPolicy(this.groupNode);
  final _TvRowNode groupNode;

  static List<FocusNode> _cardsOf(FocusNode group) => group.descendants
      .where((n) => n != group && n.canRequestFocus && n.context != null)
      .toList()
    ..sort((a, b) => a.rect.left.compareTo(b.rect.left));

  List<FocusNode> _cards() => _cardsOf(groupNode);

  /// The stacked row right above or below this one.
  _TvRowNode? _stackedRow({required bool up}) {
    final here = groupNode.rect.center.dy;
    _TvRowNode? best;
    for (final n in groupNode.nearestScope?.descendants ??
        const <FocusNode>[]) {
      if (n is! _TvRowNode || n == groupNode || !n.stacked) continue;
      if (n.context == null) continue;
      final y = n.rect.center.dy;
      if (up ? y >= here : y <= here) continue;
      final nearer = best == null ||
          (up ? y > best.rect.center.dy : y < best.rect.center.dy);
      if (nearer) best = n;
    }
    return best;
  }

  // Scroll the row just enough to keep the newly-focused card on-screen at the
  // leading/trailing edge. This is what lets the remote walk PAST the cards that
  // were on-screen at open: revealing a card scrolls the lazy list, which builds
  // the next cards into the cache so the following press can reach them. Without
  // this the row dead-ends at the last card that happened to be built.
  void _reveal(FocusNode n, {required bool forward}) {
    final ctx = n.context;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignmentPolicy: forward
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.up:
      case TraversalDirection.down:
        if (groupNode.stacked) {
          final up = direction == TraversalDirection.up;
          groupNode.last = currentNode;
          final to = _stackedRow(up: up);
          final cards = to == null ? const <FocusNode>[] : _cardsOf(to);
          if (to != null && cards.isNotEmpty) {
            final last = to.last;
            final target = last != null && cards.contains(last)
                ? last
                : cards.first;
            target.requestFocus();
            _tvRevealVertically(target);
            return true;
          }
        }
        // Hand vertical moves up to the surrounding scope, anchored on the row
        // itself, so focus lands on the neighbouring row rather than the next
        // card in this one.
        return super.inDirection(groupNode, direction);
      case TraversalDirection.left:
      case TraversalDirection.right:
        final nodes = _cards();
        if (nodes.isEmpty) return super.inDirection(currentNode, direction);
        final index = nodes.indexOf(currentNode);
        if (index == -1) {
          nodes.first.requestFocus();
          return true;
        }
        if (direction == TraversalDirection.left) {
          if (index > 0) {
            nodes[index - 1].requestFocus();
            _reveal(nodes[index - 1], forward: false);
          } else {
            // Past the first card: jump to the nav rail.
            tvLastContentFocus = currentNode;
            if (tvNavBarNode.canRequestFocus &&
                tvNavBarNode.context?.mounted == true) {
              tvNavBarNode.requestFocus();
            }
          }
        } else {
          if (index < nodes.length - 1) {
            nodes[index + 1].requestFocus();
            _reveal(nodes[index + 1], forward: true);
          }
        }
        return true;
    }
  }
}

/// The focus node of a [TvRowActions]: the buttons under it belong to the
/// row they sit in.
class _TvRowActionsNode extends FocusNode {
  _TvRowActionsNode()
      : super(
            debugLabel: 'tvRowActions',
            canRequestFocus: false,
            skipTraversal: true,
            descendantsAreTraversable: false);
}

/// Marks the buttons inside a list row that is itself a button (a download's
/// Remove, a missing episode's Search) on TV. The row is then one stop for UP
/// and DOWN, which move from row to row without catching on a button of the
/// next one; RIGHT steps from the row onto its buttons and along them, LEFT
/// back to the row. [TvContentTraversalPolicy] does the moving. Off TV it's a
/// pass-through.
class TvRowActions extends StatefulWidget {
  const TvRowActions({super.key, required this.child});
  final Widget child;

  @override
  State<TvRowActions> createState() => _TvRowActionsState();
}

class _TvRowActionsState extends State<TvRowActions> {
  final _TvRowActionsNode _node = _TvRowActionsNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    return Focus(
      focusNode: _node,
      canRequestFocus: false,
      skipTraversal: true,
      // Out of the page's own UP, DOWN, LEFT and RIGHT: a row's buttons are
      // reached from their row.
      descendantsAreTraversable: false,
      child: widget.child,
    );
  }
}

/// The [TvRowActions] a button sits in, if it sits in one.
FocusNode? _tvRowActionsOf(FocusNode node) {
  for (final a in node.ancestors) {
    if (a is _TvRowActionsNode) return a;
    if (a is FocusScopeNode) return null;
  }
  return null;
}

/// The row a [TvRowActions] belongs to: the nearest thing around it that the
/// remote can stop on.
FocusNode? _tvRowOf(FocusNode actions) {
  for (final a in actions.ancestors) {
    if (a is FocusScopeNode) return null;
    if (a.canRequestFocus && !a.skipTraversal && a.context != null) return a;
  }
  return null;
}

/// The buttons under [node] that are marked as a row's ([TvRowActions]),
/// from the left.
List<FocusNode> _tvRowButtons(FocusNode node) {
  final buttons = [
    for (final n in node.descendants)
      if (n.canRequestFocus && n.context != null && _tvRowActionsOf(n) != null)
        n,
  ];
  mergeSort<FocusNode>(buttons, compare: (a, b) {
    final dx = a.rect.left.compareTo(b.rect.left);
    return dx != 0 ? dx : a.rect.top.compareTo(b.rect.top);
  });
  return buttons;
}

/// The content area's traversal policy on TV. It makes the nav rail reachable
/// from EVERY screen: when LEFT is pressed and there's no focusable on the same
/// row to the left, focus jumps to the rail (instead of wrapping to the
/// previous grid row or dead-ending). And it moves in and out of the buttons a
/// list row holds ([TvRowActions]). Everything else falls back to normal
/// reading-order traversal, which handles grids and lists fine.
///
/// Home's rows opt out of this by being their own [TvFocusRow] groups (their
/// policy handles LEFT-escape themselves); this policy governs every other
/// screen whose cards sit directly in the content group (grids, lists, details).
class TvContentTraversalPolicy extends ReadingOrderTraversalPolicy {
  /// A move from one of a row's buttons: along them, back to the row, or (UP
  /// and DOWN) on from the row as if the remote had been on it.
  bool _fromRowButton(
      FocusNode current, FocusNode actions, TraversalDirection direction) {
    final row = _tvRowOf(actions);
    if (row == null) return super.inDirection(current, direction);
    final buttons = _tvRowButtons(row);
    final at = buttons.indexOf(current);
    switch (direction) {
      case TraversalDirection.left:
        (at > 0 ? buttons[at - 1] : row).requestFocus();
      case TraversalDirection.right:
        if (at >= 0 && at < buttons.length - 1) buttons[at + 1].requestFocus();
      case TraversalDirection.up:
      case TraversalDirection.down:
        // The move is worked out from whatever the scope holds as focused:
        // the row, from here on.
        row.requestFocus();
        super.inDirection(row, direction);
    }
    return true;
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final actions = _tvRowActionsOf(currentNode);
    if (actions != null) return _fromRowButton(currentNode, actions, direction);
    // From a stop only: with nothing lit (the page itself holds the remote)
    // every row's buttons are under it, wherever they are on the page.
    if (direction == TraversalDirection.right &&
        currentNode is! FocusScopeNode &&
        !currentNode.skipTraversal) {
      final buttons = _tvRowButtons(currentNode);
      if (buttons.isNotEmpty) {
        buttons.first.requestFocus();
        return true;
      }
    }
    if (direction == TraversalDirection.left) {
      final cur = currentNode.rect;
      FocusNode? best;
      double bestDist = double.infinity;
      for (final n in currentNode.nearestScope?.traversalDescendants ??
          const <FocusNode>[]) {
        if (n == currentNode || !n.canRequestFocus || n.context == null) {
          continue;
        }
        final r = n.rect;
        // Same-row band (vertical overlap) and genuinely to the left.
        final sameRow = cur.top < r.bottom && r.top < cur.bottom;
        if (!sameRow || r.center.dx >= cur.center.dx) continue;
        final dist = (cur.left - r.right).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = n;
        }
      }
      if (best != null) {
        best.requestFocus();
        return true;
      }
      // Nothing to the left on this row: escape to the nav rail.
      if (tvNavBarNode.canRequestFocus &&
          tvNavBarNode.context?.mounted == true) {
        tvLastContentFocus = currentNode;
        tvNavBarNode.requestFocus();
        return true;
      }
    }
    return super.inDirection(currentNode, direction);
  }
}

/// The nav-rail traversal policy: normal within the rail, but RIGHT past its
/// edge returns to the content the remote came from (or the first card).
class TvRailPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    // Keep vertical moves INSIDE the rail. Directional traversal otherwise
    // crosses the group boundary, so DOWN off the last tile (the account /
    // profile tile) geometrically lands on the content hero — the reported bug.
    // Move to the nearest rail tile above/below in the same column; if there's
    // none (the top or bottom of the rail) consume the key so focus stays on the
    // tile until the user presses RIGHT (into content) or UP.
    if (direction == TraversalDirection.up ||
        direction == TraversalDirection.down) {
      final cur = currentNode.rect;
      FocusNode? best;
      double bestDist = double.infinity;
      for (final n in currentNode.nearestScope?.traversalDescendants ??
          const <FocusNode>[]) {
        if (n == currentNode || !n.canRequestFocus || n.context == null) {
          continue;
        }
        // The page's own stops, even one scrolled in under the rail.
        if (n.ancestors.contains(tvContentScope)) continue;
        final r = n.rect;
        // Same rail column: the candidate overlaps the current tile's span
        // (the content area sits to the right, excluded). Overlap, not centre:
        // the collapse button at the header's right is narrower than the
        // tiles under it, whose centres fall outside it.
        if (r.right <= cur.left || r.left >= cur.right) continue;
        final isBelow = direction == TraversalDirection.down
            ? r.top > cur.top + 1
            : r.top < cur.top - 1;
        if (!isBelow) continue;
        final dist = (r.top - cur.top).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = n;
        }
      }
      if (best != null) {
        best.requestFocus();
        return true;
      }
      return true; // top/bottom of the rail: stay, don't fall into content
    }
    if (direction == TraversalDirection.right) {
      // RIGHT is the way into the page, and the page decides where. Asking
      // the framework first had it pick whatever stood nearest the tile, out
      // of everything built: rarely where the remote had left, sometimes a
      // header's button, and sometimes a stop of a page hidden under the one
      // in front, where the remote then moved about unseen.
      //
      // Prefer returning to exactly where the remote left content, but only if
      // it's still on-screen (so RIGHT never lands on a scrolled-off "phantom")
      // AND below the top chrome (so it never returns to the app bar back/filter
      // buttons, which read as "focus stuck at the top": the exact complaint),
      // unless that's where its page opens by choice.
      final target = tvLastContentFocus;
      if (target != null &&
          target.canRequestFocus &&
          target.context?.mounted == true &&
          _tvFrontPage().traversalDescendants.contains(target) &&
          _tvOnScreen(target) &&
          (target.rect.top >= _tvHeaderCutoff || _tvLandingSpot(target))) {
        target.requestFocus();
        return true;
      }
      // Otherwise land on the first VISIBLE content item below the header, so a
      // single RIGHT always shows an obvious highlight on real content (no
      // double-press, never the back button).
      tvFirstVisibleContentNode()?.requestFocus();
      // With nothing to stop on yet (a page still loading), the remote stays
      // on the rail.
      return true;
    }
    return super.inDirection(currentNode, direction);
  }
}

/// On TV, scrolls the enclosing scroll view all the way to the top whenever
/// anything inside [child] gains focus. Used to wrap the home hero: when the
/// remote comes back UP to the hero's buttons, the framework only scrolls them
/// just into view (cutting off the art above), so this pulls the whole hero back
/// into frame like a fresh open. Off TV it's a pass-through.
class TvScrollToTopOnFocus extends StatefulWidget {
  const TvScrollToTopOnFocus({super.key, required this.child});
  final Widget child;

  @override
  State<TvScrollToTopOnFocus> createState() => _TvScrollToTopOnFocusState();
}

class _TvScrollToTopOnFocusState extends State<TvScrollToTopOnFocus> {
  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        // After the framework's own ensure-visible settles, override it by
        // scrolling fully to the top so the hero art isn't clipped.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final pos = Scrollable.maybeOf(context)?.position;
          if (pos != null && pos.pixels > 0) {
            pos.animateTo(0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic);
          }
        });
      },
      child: widget.child,
    );
  }
}

/// Wraps arbitrary card content (a landscape tile, a library card, a browse
/// tile) and makes it a first-class D-pad target: it owns the [FocusNode],
/// draws a bold accent ring + glow + slight scale-up when focused, and fires
/// [onTap] on the remote's centre/select (ActivateIntent). Mouse/touch taps are
/// left to whatever tappable the child already contains (keep its InkWell but
/// pass `canRequestFocus: false` so focus isn't split between two nodes).
///
/// Use for cards that render their own artwork/ripple. For plain buttons that
/// should keep their own colours, use [TvFocusAura] instead.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.scale = 1.05,
    this.autofocus = false,
    this.focusNode,
    this.showRing = true,
    this.onFocusChange,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final double scale;
  final bool autofocus;
  final FocusNode? focusNode;

  /// False when the child draws its own focus indicator from [onFocusChange]
  /// (a shape the rectangular ring doesn't fit, like the movie wheel).
  final bool showRing;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  // Handle the remote's OK/Select (and Enter/Space/gameButtonA) DIRECTLY on the
  // focused node. Going through ActivateIntent/Shortcuts proved unreliable here
  // (the intent didn't reach the tile's action from a lazy sliver list), but a
  // plain onKeyEvent on the focused node always fires — this is the definitive
  // activation path for D-pad Select.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.gameButtonA) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // TV only: off TV this is a pass-through, so desktop/mobile keep the child's
    // original tap/focus behaviour (no accent ring, no extra keyboard stop).
    if (!isTvDevice) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: _focused ? widget.scale : 1.0,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        onFocusChange: (v) {
          setState(() => _focused = v);
          widget.onFocusChange?.call(v);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: _focused && widget.showRing
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.75),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              widget.child,
              if (_focused && widget.showRing)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: widget.borderRadius,
                        border: Border.all(color: scheme.primary, width: 3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a focusable control (button, poster, tile) and draws a bold, glowing
/// "aura" plus a slight scale-up when it holds focus — the obvious D-pad
/// selection indicator for Android TV. The child keeps its own colours; the
/// aura is drawn *around* it.
///
/// The child owns the [FocusNode] (so its own tap/activate keeps working); this
/// widget only observes it. Use like:
/// ```dart
/// TvFocusAura(builder: (node) => FilledButton(focusNode: node, ...))
/// ```
class TvFocusAura extends StatefulWidget {
  const TvFocusAura({
    super.key,
    required this.builder,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.scale = 1.04,
  });

  final Widget Function(FocusNode node) builder;
  final BorderRadius borderRadius;
  final double scale;

  @override
  State<TvFocusAura> createState() => _TvFocusAuraState();
}

class _TvFocusAuraState extends State<TvFocusAura> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  void _onFocus() {
    if (_node.hasFocus != _focused) setState(() => _focused = _node.hasFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TV only: off TV, render the control with its node but no aura/scale, so
    // desktop/mobile keep the button exactly as it was.
    if (!isTvDevice) return widget.builder(_node);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: _focused ? widget.scale : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.75),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: widget.builder(_node),
      ),
    );
  }
}

/// Draws an accent focus ring (and an optional slight scale) around a child that
/// ALREADY contains its own focusable — a `ListTile` or `InkWell` with an
/// `onTap`. Unlike [TvFocusable] it does NOT add a second focus node: it only
/// observes whether a descendant holds focus (`Focus.onFocusChange` reports the
/// node's `hasFocus`, which is true when a descendant is focused), so the row
/// stays a single D-pad stop and keeps its own Select/tap handling. Use for the
/// many content rows whose built-in focus tint is too faint to read across a
/// room. A no-op off TV, so desktop/mouse behaviour is unchanged.
class TvFocusRing extends StatefulWidget {
  const TvFocusRing({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.scale = 1.0,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double scale;

  @override
  State<TvFocusRing> createState() => _TvFocusRingState();
}

class _TvFocusRingState extends State<TvFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedScale(
        scale: _focused ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _focused ? scheme.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Keeps the remote somewhere on TV when what it was on goes away: a row that
/// leaves its list, a switch whose list is swapped for another, a button that
/// turns into a spinner. Flutter then hands focus to whatever held it earlier
/// on the page, or to nothing, and the next press starts from the top. With
/// this around a page, focus goes to what now stands nearest to where it was.
/// Off TV it's a pass-through.
class TvFocusKeeper extends StatefulWidget {
  const TvFocusKeeper({super.key, required this.child});
  final Widget child;

  @override
  State<TvFocusKeeper> createState() => _TvFocusKeeperState();
}

class _TvFocusKeeperState extends State<TvFocusKeeper> {
  final FocusNode _node = FocusNode(
      debugLabel: 'tvKeeper', canRequestFocus: false, skipTraversal: true);

  /// What the remote was last on in here, and where on the screen it stood.
  FocusNode? _last;
  Rect? _lastRect;

  @override
  void initState() {
    super.initState();
    if (isTvDevice) FocusManager.instance.addListener(_onFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  static bool _gone(FocusNode n) =>
      n.parent == null || n.context == null || !n.context!.mounted;

  /// Where [_last] stands, as of the frame being drawn: a list that scrolls
  /// moves it, and only lays it out in its new place with that frame.
  void _sample() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final last = _last;
      if (!mounted || last == null || _gone(last)) return;
      final rect = last.rect;
      if (!rect.isEmpty) _lastRect = rect;
    });
  }

  void _onFocus() {
    if (!mounted) return;
    final pf = FocusManager.instance.primaryFocus;
    if (pf == null || pf.context == null) return;
    final inside = pf.ancestors.contains(_node);
    final last = _last;
    if (last != null && _gone(last)) {
      // Only once focus is back in here, or on nothing (the page itself,
      // or something around this that's no stop for a remote): a dialog
      // over the page keeps the remote for as long as it's open.
      final onNothing = (pf is FocusScopeNode || pf.skipTraversal) &&
          _node.ancestors.contains(pf);
      if (!inside && !onNothing) return;
      final next = _nearest(_lastRect);
      if (next == null) return;
      _last = next;
      _lastRect = next.rect;
      if (next != pf) next.requestFocus();
      return;
    }
    if (inside && pf is! FocusScopeNode) {
      _last = pf;
      final rect = pf.rect;
      if (!rect.isEmpty) _lastRect = rect;
      _sample();
    }
  }

  /// What the remote can stop on in here that stands nearest to [rect]:
  /// what's in its place first, then what's closest to it.
  FocusNode? _nearest(Rect? rect) {
    if (rect == null) return null;
    FocusNode? best;
    var bestGap = double.infinity;
    var bestAway = double.infinity;
    for (final n in _node.traversalDescendants) {
      if (_gone(n) || !_tvOnScreen(n)) continue;
      final r = n.rect;
      final dx = (r.left > rect.right)
          ? r.left - rect.right
          : (rect.left > r.right ? rect.left - r.right : 0.0);
      final dy = (r.top > rect.bottom)
          ? r.top - rect.bottom
          : (rect.top > r.bottom ? rect.top - r.bottom : 0.0);
      final gap = dx * dx + dy * dy;
      final away = (r.center - rect.center).distanceSquared;
      if (gap < bestGap || (gap == bestGap && away < bestAway)) {
        best = n;
        bestGap = gap;
        bestAway = away;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _sample();
        return false;
      },
      child: Focus(
        focusNode: _node,
        canRequestFocus: false,
        skipTraversal: true,
        child: widget.child,
      ),
    );
  }
}

/// A stretch of a page that's only read (a paragraph, a list of facts), made
/// a stop for the remote on TV. A remote scrolls a page by moving from one
/// stop to the next: with nothing to stop on, what's below the last button
/// could never be brought into view. Shows a quiet outline while the remote
/// is on it. Off TV it's a pass-through.
class TvReadStop extends StatefulWidget {
  const TvReadStop({super.key, required this.child});
  final Widget child;

  @override
  State<TvReadStop> createState() => _TvReadStopState();
}

class _TvReadStopState extends State<TvReadStop> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      debugLabel: 'tvReadStop',
      onFocusChange: (v) => setState(() => _focused = v),
      // The outline is drawn a little outside the words, so they don't touch
      // its edge. That room is part of the stop: the page scrolls a stop
      // into view edge to edge, and would cut the outline off otherwise.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_focused)
            Positioned(
              left: -8,
              right: -8,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: scheme.primary.withValues(alpha: 0.08),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.7),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// The buttons over a page's collapsing header, on TV: a stop for the remote
/// only while the header is fully open. Once the page scrolls, the header's
/// picture is faded out and clipped but still laid out behind the page, and
/// its buttons with it; left in, the remote would step onto buttons nobody
/// can see. [TvPageEnds] opens the header again. Off TV it's a
/// pass-through.
class TvOpenHeaderOnly extends StatelessWidget {
  const TvOpenHeaderOnly({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return child;
    final bar =
        context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final open = bar == null || bar.currentExtent >= bar.maxExtent - 1;
    return ExcludeFocus(excluding: !open, child: child);
  }
}

/// The two ends of a scrolled page, on TV. UP from the page's first stop
/// opens its header again and puts the remote on the header's first button;
/// DOWN from its last stop scrolls on, so what's only read under it (a
/// heading, a line saying there's nothing yet) can still be brought into
/// view. In between, UP and DOWN move stop by stop as usual. Goes around the
/// page's scroll view. Off TV it's a pass-through.
class TvPageEnds extends StatefulWidget {
  const TvPageEnds({super.key, required this.child});
  final Widget child;

  @override
  State<TvPageEnds> createState() => _TvPageEndsState();
}

class _TvPageEndsState extends State<TvPageEnds> {
  // The header is on its way open: a held UP waits for it rather than
  // starting it over with every repeat.
  bool _opening = false;

  // A pinned bar stays at the top of a scrolled page: its own buttons (Back)
  // aren't somewhere to go from the page's first stop.
  static bool _inBar(FocusNode n) =>
      n.context?.findAncestorWidgetOfExactType<AppBar>() != null;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final up = e.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!up && e.logicalKey != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    if (_opening) return KeyEventResult.handled;
    final pf = FocusManager.instance.primaryFocus;
    final at = pf?.context;
    if (pf == null || at == null) return KeyEventResult.ignored;
    // The page's own scrolling, not a strip's inside it.
    var scrollable = Scrollable.maybeOf(at);
    while (scrollable != null &&
        scrollable.position.axis != Axis.vertical) {
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    final position = scrollable?.position;
    if (position == null) return KeyEventResult.ignored;
    // A button of a row counts as its row: UP and DOWN leave from the row.
    final actions = _tvRowActionsOf(pf);
    final from = (actions == null ? null : _tvRowOf(actions)) ?? pf;
    if (_inBar(from)) return KeyEventResult.ignored;
    final others = [
      for (final n in node.traversalDescendants)
        if (n != from && n.context != null && !_inBar(n)) n,
    ];
    if (!up) {
      // A stop below this one: an ordinary move.
      final middle = from.rect.center.dy;
      if (others.any((n) => n.rect.center.dy > middle + 8)) {
        return KeyEventResult.ignored;
      }
      // The end of the page: nowhere further. Kept here, since a stop that
      // has scrolled off the top has the pinned bar's Back button "below" it.
      if (position.pixels >= position.maxScrollExtent) {
        return KeyEventResult.handled;
      }
      // No further than keeps the stop in sight under the pinned bar: OK
      // must never press something scrolled away out of view.
      // A stop taller than the screen still scrolls on to its own end.
      final room = math.max(
        pf.rect.top - (_tvHeaderCutoff + 8),
        pf.rect.bottom - (_tvScreenSize().height - 16),
      );
      if (room <= 0) return KeyEventResult.handled;
      position.animateTo(
        math.min(
          position.pixels +
              math.min(position.viewportDimension * 0.6, room),
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return KeyEventResult.handled;
    }
    if (position.pixels <= position.minScrollExtent) {
      return KeyEventResult.ignored;
    }
    // A stop above this one: an ordinary move.
    final top = from.rect.top;
    if (others.any((n) => n.rect.top < top - 8)) {
      return KeyEventResult.ignored;
    }
    _opening = true;
    position
        .animateTo(
          position.minScrollExtent,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          // The header's buttons take the remote again once it's laid out
          // open: a frame after the scroll ends.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _opening = false;
            if (!mounted) return;
            if (FocusManager.instance.primaryFocus != pf) return;
            tvFirstVisibleContentNode()?.requestFocus();
          });
          WidgetsBinding.instance.scheduleFrame();
        });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return widget.child;
    return Focus(
      debugLabel: 'tvPageEnds',
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
