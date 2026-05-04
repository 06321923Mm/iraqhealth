import 'package:supabase_flutter/supabase_flutter.dart';

String postgrestPermissionHint(PostgrestException e) {
  final String msg = e.message;
  final String lower = msg.toLowerCase();
  if (e.code == '42501' ||
      lower.contains('row-level security') ||
      lower.contains('permission denied')) {
    return 'لا توجد صلاحية INSERT (غالباً RLS أو GRANT). من Supabase → SQL Editor '
        'طبّق migrations المجلد supabase/migrations (مثلاً pending_doctors وreports). '
        'التفاصيل: $msg';
  }
  if (lower.contains('column') && lower.contains('does not exist')) {
    return 'عمود غير موجود في قاعدة البيانات. طبّق أحدث migrations من مجلد supabase/migrations.';
  }
  return msg;
}

/// أخطاء الإدراج/التحديث في Supabase (شبكة، صلاحيات، إلخ).
String humanReadableSupabaseWriteError(Object error) {
  final String text = error.toString().toLowerCase();
  final bool looksLikeNoInternet = text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('no address associated') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('clientexception') ||
      text.contains('handshakeexception') ||
      text.contains('timeout');
  if (looksLikeNoInternet) {
    return 'تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مرة أخرى.';
  }
  if (error is PostgrestException) {
    return 'تعذر الحفظ: ${postgrestPermissionHint(error)}';
  }
  return 'تعذر الحفظ. حاول مرة أخرى.';
}

String reportInsertErrorMessage(Object error) {
  if (error is PostgrestException) {
    return postgrestPermissionHint(error);
  }
  return error.toString();
}
