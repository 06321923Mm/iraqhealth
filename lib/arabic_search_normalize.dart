/// تطبيع نصوص البحث العربية (أسماء، تخصصات) ليتطابق «عبد الامام» مع «عبدالامام»
/// و«أإآ» مع «ا»، و«ى» مع «ي»، و«ة» نهاية الكلمة مع «ه».
String normalizeArabic(String text) {
  if (text.isEmpty) {
    return '';
  }
  String s = text.trim();
  if (s.isEmpty) {
    return '';
  }
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  const Map<String, String> alifMap = <String, String>{
    'أ': 'ا',
    'إ': 'ا',
    'آ': 'ا',
    'ٱ': 'ا',
  };
  for (final MapEntry<String, String> e in alifMap.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  s = s.replaceAll('ى', 'ي');
  final List<String> words = s.split(' ');
  for (int i = 0; i < words.length; i++) {
    final String w = words[i];
    if (w.isNotEmpty && w.endsWith('ة')) {
      words[i] = '${w.substring(0, w.length - 1)}ه';
    }
  }
  s = words.join(' ');
  const List<String> mergePrefixes = <String>['عبد', 'أبو', 'أم'];
  for (final String p in mergePrefixes) {
    if (s.startsWith('$p ')) {
      s = p + s.substring(p.length + 1);
      break;
    }
  }
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // الأحرف الإنجليزية في العنوان/المنطقة تبقى قابلة للمطابقة بلا اعتبار لحالة الحرف.
  return s.toLowerCase();
}

/// يقسّم نص البحث بعد التطبيع إلى كلمات غير فارغة (بحث مرن بترتيب غير مهم).
List<String> arabicSearchTokens(String text, {int maxTokens = 12}) {
  final String n = normalizeArabic(text);
  if (n.isEmpty) {
    return <String>[];
  }
  final List<String> parts = n
      .split(' ')
      .map((String t) => t.trim())
      .where((String t) => t.isNotEmpty)
      .toList();
  if (parts.length <= maxTokens) {
    return parts;
  }
  return parts.sublist(0, maxTokens);
}
