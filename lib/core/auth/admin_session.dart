import 'package:supabase_flutter/supabase_flutter.dart';

/// مطابق لتحقق قاعدة البيانات [jwt_is_admin]: App Metadata أو User Metadata.
bool sessionUserIsAdmin(User? user) {
  if (user == null) {
    return false;
  }
  if (user.appMetadata['role'] == 'admin') {
    return true;
  }
  final Map<String, dynamic>? um = user.userMetadata;
  return um != null && um['role'] == 'admin';
}
