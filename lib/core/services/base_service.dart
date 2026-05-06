import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Abstract base for all Supabase service classes — provides a shared client,
/// centralized error handling, and a lightweight debug logger.
abstract class BaseService {
  const BaseService(this.db);

  final SupabaseClient db;

  /// Logs to the debug console (no-op in release builds).
  void log(String message) => debugPrint('[${runtimeType.toString()}] $message');

  /// Wraps a Supabase call and converts PostgrestException into a readable message.
  Future<T?> guard<T>(Future<T> Function() fn, {String context = ''}) async {
    try {
      return await fn();
    } on PostgrestException catch (e) {
      log('PostgrestException${context.isNotEmpty ? " in $context" : ""}: ${e.message} (${e.code})');
      rethrow;
    } catch (e) {
      log('Error${context.isNotEmpty ? " in $context" : ""}: $e');
      rethrow;
    }
  }
}
