// اختبارات RLS (سياسات أمان الصفوف) لـ Supabase
// تُشغَّل ضد بيئة اختبار منفصلة — لا تلمس بيانات الإنتاج أبداً.
//
// طريقة التشغيل:
//   flutter test integration_test/rls_test.dart \
//     --dart-define=SUPABASE_TEST_URL=... \
//     --dart-define=SUPABASE_TEST_ANON_KEY=... \
//     --dart-define=SUPABASE_TEST_USER_EMAIL=... \
//     --dart-define=SUPABASE_TEST_USER_PASS=... \
//     --dart-define=SUPABASE_TEST_ADMIN_EMAIL=... \
//     --dart-define=SUPABASE_TEST_ADMIN_PASS=...

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<T> withRetry<T>(Future<T> Function() fn, {int retries = 3}) async {
  for (int i = 0; i < retries; i++) {
    try {
      return await fn();
    } catch (e) {
      if (i == retries - 1) rethrow;
      await Future.delayed(Duration(seconds: 2));
    }
  }
  throw Exception('unreachable');
}

// ── بيانات الاتصال من --dart-define ──────────────────────────────────────────
const String _url = String.fromEnvironment('SUPABASE_TEST_URL');
const String _anonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');
const String _userEmail = String.fromEnvironment('SUPABASE_TEST_USER_EMAIL');
const String _userPass = String.fromEnvironment('SUPABASE_TEST_USER_PASS');
const String _adminEmail = String.fromEnvironment('SUPABASE_TEST_ADMIN_EMAIL');
const String _adminPass = String.fromEnvironment('SUPABASE_TEST_ADMIN_PASS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseClient anonClient;
  late SupabaseClient userClient;
  late SupabaseClient adminClient;

  // يُجلب من قاعدة البيانات في setUpAll باستخدام anonClient
  late int testDoctorId;

  // يُحفظ أثناء الاختبار 3 ويُستخدم في الاختبار 7 والتنظيف
  int? insertedPendingId;

  setUpAll(() async {
    anonClient = SupabaseClient(_url, _anonKey);
    userClient = SupabaseClient(_url, _anonKey);
    adminClient = SupabaseClient(_url, _anonKey);

    // تسجيل دخول المستخدم العادي
    await userClient.auth.signInWithPassword(
      email: _userEmail,
      password: _userPass,
    );

    // تسجيل دخول المشرف
    await adminClient.auth.signInWithPassword(
      email: _adminEmail,
      password: _adminPass,
    );

    // جلب معرّف طبيب الاختبار الثابت
    final Map<String, dynamic> doctorRow = await anonClient
        .from('doctors')
        .select('id')
        .eq('name', 'دكتور اختبار')
        .limit(1)
        .single();
    testDoctorId = doctorRow['id'] as int;
  });

  tearDownAll(() async {
    // حذف صف pending_doctors إن لم يُحذف في الاختبار 7
    if (insertedPendingId != null) {
      try {
        await adminClient
            .from('pending_doctors')
            .delete()
            .eq('id', insertedPendingId!);
      } catch (_) {}
    }

    // إعادة حقل notes إلى القيمة الفارغة
    try {
      await adminClient
          .from('doctors')
          .update({'notes': ''})
          .eq('id', testDoctorId);
    } catch (_) {}

    anonClient.dispose();
    userClient.dispose();
    adminClient.dispose();
  });

  // ── مجموعة 1: صلاحيات الزائر غير المسجّل ───────────────────────────────
  group('anon RLS', () {
    test('1 - الزائر يستطيع قراءة بيانات الأطباء', () async {
      final List<dynamic> data =
          await anonClient.from('doctors').select().limit(5);
      expect(data, isA<List>());
    });

    test('2 - الزائر لا يستطيع تعديل بيانات الأطباء', () async {
      // RLS blocks UPDATE by returning 0 affected rows, not by throwing.
      final List<dynamic> result = await anonClient
          .from('doctors')
          .update({'name': 'هاكر'})
          .eq('id', testDoctorId)
          .select();
      expect(result, isEmpty);
    });
  });

  // ── مجموعة 2: صلاحيات المستخدم المسجّل ─────────────────────────────────
  group('authenticated user RLS', () {
    test('3 - المستخدم يستطيع إضافة طبيب في قائمة الانتظار', () async {
      final List<dynamic> result =
          await userClient.from('pending_doctors').insert(<String, dynamic>{
        'name': 'طبيب تجريبي',
        'spec': 'عام',
        'area': 'الكرادة',
        'gove': 'بغداد',
        'ph': '07700000001',
      }).select();
      expect(result, isA<List>());
      expect(result.isNotEmpty, true);
      insertedPendingId = result.first['id'] as int;
    });

    test('4 - المستخدم لا يستطيع تعديل بيانات الأطباء مباشرة', () async {
      // RLS blocks UPDATE by returning 0 affected rows, not by throwing.
      final List<dynamic> result = await userClient
          .from('doctors')
          .update({'name': 'تعديل غير مصرح'})
          .eq('id', testDoctorId)
          .select();
      expect(result, isEmpty);
    });

    test('5 - المستخدم لا يرى طلبات توثيق المستخدمين الآخرين', () async {
      final List<dynamic> data = await userClient
          .from('verification_requests')
          .select()
          .limit(10);
      expect(data, isA<List>());
      expect(data.isEmpty, true);
    });
  });

  // ── مجموعة 3: صلاحيات المشرف ────────────────────────────────────────────
  group('admin RLS', () {
    test('6 - المشرف يستطيع تعديل بيانات أي طبيب', () async {
      final List<dynamic> result = await withRetry(() => adminClient
          .from('doctors')
          .update({'notes': 'تحديث من الأدمن'})
          .eq('id', testDoctorId)
          .select());
      expect(result, isA<List>());
      expect(result.isNotEmpty, true);
    });

    test('7 - المشرف يستطيع حذف الأطباء من قائمة الانتظار', () async {
      if (insertedPendingId == null) return;
      await withRetry(() => adminClient
          .from('pending_doctors')
          .delete()
          .eq('id', insertedPendingId!));
      insertedPendingId = null; // علامة بأن الحذف نجح — التنظيف لن يكرره
    });
  });
}
