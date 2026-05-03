import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  Future<void> logSearchUsed(String query) async {
    debugPrint('[Analytics] search: $query');
  }

  Future<void> logFilterUsed(String filterName, {String? value}) async {
    debugPrint('[Analytics] filter: $filterName=$value');
  }

  Future<void> logCallClicked(String doctorName) async {
    debugPrint('[Analytics] call: $doctorName');
  }

  Future<void> logWhatsappClicked(String doctorName) async {
    debugPrint('[Analytics] whatsapp: $doctorName');
  }

  Future<void> logLocationUsed(String type, {String? detail}) async {
    debugPrint('[Analytics] location: $type detail=$detail');
  }

  Future<void> logDoctorOpened(String name, String spec) async {
    debugPrint('[Analytics] doctorOpened: $name ($spec)');
  }
}
