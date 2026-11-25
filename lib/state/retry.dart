import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// When a provider that failed is asked again by itself, for the whole app.
///
/// Riverpod's own rule asks ten more times, over about forty seconds or more,
/// for any failure at all, and the page shows its spinner all that while. A
/// refused API key isn't going to be accepted on the eleventh try, the user
/// waits a minute to be told, and the server (or YouTube, or a download
/// client that counts refused sign-ins) is asked eleven times over.
///
/// So: twice at most, quickly, and only for what a moment can mend: a
/// connection that dropped or timed out. An answer from the server, whatever
/// it says, is the answer. The clients' own exceptions (their readable
/// message is all that's left of the failure) aren't retried either: a page
/// that failed says so at once, with its Retry.
Duration? fathomRetry(int retryCount, Object error) {
  if (retryCount >= 2) return null;
  final transient = switch (error) {
    DioException(:final type) =>
      type == DioExceptionType.connectionError ||
          type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.receiveTimeout ||
          type == DioExceptionType.sendTimeout,
    SocketException() || TimeoutException() => true,
    _ => false,
  };
  if (!transient) return null;
  return Duration(milliseconds: retryCount == 0 ? 400 : 1200);
}
