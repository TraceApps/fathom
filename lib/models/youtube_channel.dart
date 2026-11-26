import '../l10n/l10n.dart';

/// A YouTube channel. Subscriptions are stored locally, so the fields we
/// persist are just enough to render the list without a network round-trip.
class YoutubeChannel {
  final String id;
  final String title;
  final String logoUrl;
  final String? bannerUrl;
  final int? subscribersCount;

  /// The subscriber count as YouTube words it, e.g. "1.26M subscribers".
  ///
  /// Search returns this text rather than a number, and it's kept verbatim so
  /// the label matches what YouTube shows instead of being re-rounded here.
  final String? subscribersText;

  /// e.g. "@johnnycarson", when the listing carries one.
  final String? handle;

  const YoutubeChannel({
    required this.id,
    required this.title,
    required this.logoUrl,
    this.bannerUrl,
    this.subscribersCount,
    this.subscribersText,
    this.handle,
  });

  String get url => 'https://www.youtube.com/channel/$id';

  /// YouTube's own wording when we have it, otherwise formatted from the count.
  String get subscribersLabel {
    final text = subscribersText;
    if (text != null && text.isNotEmpty) return text;
    final n = subscribersCount;
    if (n == null || n <= 0) return '';
    if (n >= 1000000000) {
      return tr.ytSubscribers('${(n / 1000000000).toStringAsFixed(1)}B');
    }
    if (n >= 1000000) return tr.ytSubscribers('${(n / 1000000).toStringAsFixed(1)}M');
    if (n >= 1000) return tr.ytSubscribers('${(n / 1000).toStringAsFixed(1)}K');
    return tr.ytSubscribers('$n');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'logoUrl': logoUrl,
        'bannerUrl': bannerUrl,
        'subscribersCount': subscribersCount,
        'subscribersText': subscribersText,
        'handle': handle,
      };

  factory YoutubeChannel.fromJson(Map<String, dynamic> j) => YoutubeChannel(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        logoUrl: j['logoUrl'] as String? ?? '',
        bannerUrl: j['bannerUrl'] as String?,
        subscribersCount: (j['subscribersCount'] as num?)?.toInt(),
        subscribersText: j['subscribersText'] as String?,
        handle: j['handle'] as String?,
      );
}
