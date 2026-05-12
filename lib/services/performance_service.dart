// خدمة Firebase Performance المركزية — لقياس أوقات العمليات الحرجة
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

class PerformanceService {
  PerformanceService._();
  static final PerformanceService instance = PerformanceService._();

  FirebasePerformance get _perf => FirebasePerformance.instance;

  /// Wraps an async operation in a Performance trace.
  Future<T> trace<T>(String name, Future<T> Function() fn) async {
    if (kIsWeb) return fn();
    final Trace t = _perf.newTrace(name);
    try {
      await t.start();
      final T result = await fn();
      return result;
    } finally {
      try {
        await t.stop();
      } catch (_) {}
    }
  }

  /// Records a one-off metric value (e.g., count of doctors loaded).
  Future<void> recordMetric(String traceName, String metricName, int value) async {
    if (kIsWeb) return;
    final Trace t = _perf.newTrace(traceName);
    await t.start();
    t.setMetric(metricName, value);
    await t.stop();
  }

  /// Marks the app as fully interactive (called after first frame renders data).
  Future<void> markStartupComplete({required int doctorCount}) async {
    await recordMetric('app_startup', 'doctors_on_first_frame', doctorCount);
  }
}
