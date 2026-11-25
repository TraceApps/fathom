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
