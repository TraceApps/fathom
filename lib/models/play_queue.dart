import 'base_item.dart';

/// Videos to play one after another (a playlist's movies and episodes, in
/// order or shuffled), handed to the player with the one to start on.
/// Carried in the player's route rather than kept anywhere, so it ends when
/// the player closes and never follows a title opened later.
class PlayQueue {
  const PlayQueue(this.items, this.index);

  final List<BaseItemDto> items;
  final int index;

  BaseItemDto get current => items[index];

  /// The same queue, on another of its items.
  PlayQueue at(int i) => PlayQueue(items, i);
}
