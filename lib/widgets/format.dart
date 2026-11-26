import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// A time of day as the viewer reads one: their language's form (3:05 PM,
/// 15:05), and 24 hours when the device is set to that. Times from a server
/// arrive in UTC; this shows the viewer's own.
String clockTime(BuildContext context, DateTime t) {
  final locale = Localizations.localeOf(context).toString();
  final format = MediaQuery.alwaysUse24HourFormatOf(context)
      ? DateFormat.Hm(locale)
      : DateFormat.jm(locale);
  return format.format(t.toLocal());
}

/// A day and a time without the year, for lists of recent things: "Nov 26,
/// 3:05 PM", the day as the viewer's language writes it.
String shortDateTime(BuildContext context, DateTime t) {
  final locale = Localizations.localeOf(context).toString();
  final day = DateFormat.MMMd(locale).format(t.toLocal());
  return '$day, ${clockTime(context, t)}';
}
