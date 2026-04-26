import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pwa_install_stub.dart'
    if (dart.library.js) 'pwa_install_web.dart';
import 'splash_screen.dart';

const List<String> kGovernorates = <String>[
  'بغداد',
  'البصرة',
  'الموصل',
  'صلاح الدين',
  'ذي قار',
  'الديوانية',
  'بابل',
  'كربلاء',
  'النجف',
  'الأنبار',
  'كركوك',
  'ديالى',
  'واسط',
  'ميسان',
  'المثنى',
  'أربيل',
  'دهوك',
  'السليمانية',
  'حلبجة',
];

const String kDropdownAddCustom = '__add_custom__';

enum _MedicalFieldType {
  physician,
  radiology,
  dentist,
  pharmacy,
  lab,
}

const List<String> kPhysicianSpecializations = <String>[
  'الباطنية والصدرية والقلبية',
  'الباطنية - الجهاز الهضمي',
  'الباطنية - أمراض الكلى',
  'الباطنية - أمراض الدم',
  'الباطنية - الأورام والغدد',
  'الباطنية - غدد الصماء والسكري',
  'الباطنية - اختصاص دقيق جهاز التنفسي والصدرية',
  'القلبية',
  'جراحة القلب والصدر والاوعية الدموية',
  'اختصاص دقيق أيكو القلب والشرابي',
  'قسطرة الشرابي والاوردة الاشعة التداخلية',
  'اختصاص دقيق تشوهات القلب الولادية',
  'الجراحة العامة الأطباء فقط',
  'جراحة عامه الطبيبات فقط',
  'الجراحة التجميلية',
  'جراحة الجملة العصبية',
  'جراحة الكسور والمفاصل',
  'جراحة المجاري البولية',
  'جراحة أطفال',
  'طب وجراحة العيون',
  'الانف والاذن والحنجرة',
  'النسائية',
  'اختصاص طب الأطفال',
  'النفسية',
  'طب الجملة العصبية',
  'عيادات الفسلجة العصبية لتخطيط الاعصاب والعضلات والدماغ',
  'أختصاص التخدير وطب الألم والعناية المركزة',
  'الجلدية والتناسلية والتجميلية',
  'طب الأسرة',
  'طب المجتمع وطب عام',
  'اختصاص التغذية',
  'المفاصل',
  'الطب الرياضي والعلاج التكميلي',
  'الطب النووي والغدة الدرقية',
  'السمع والنطق والتوازن',
  'مراكز العقيم وأطفال الانابيب',
  'مراكز لعلاج التوحد والنطق والتأتأة والقوقعة وتنمية القدرات',
  'عيادات ومراكز العلاج الطبيعي والتأهيل الطبي',
  'عيادات ومراكز لفحص هشاشة العظام',
  'مراكز للأطراف والمساند الصناعية',
  'الممرضين',
];

const List<String> kImagingModalityOptions = <String>[
  'اشعة وسونار',
  'اشعة وسونار ورنين',
  'اشعة وسونار ومفراس',
  'اشعة وسونار ومفراس ورنين',
];

const String _kAdminPasswordFromDefine =
    String.fromEnvironment('ADMIN_PASSWORD');

/// Optional local **debug** password when `ADMIN_PASSWORD` is not set via
/// `--dart-define` or `.vscode/launch.json`. Keep empty in git.
const String kAdminPasswordDebugOnly = '';

/// Resolved admin password: compile-time define wins; otherwise [kAdminPasswordDebugOnly]
/// in debug builds only (release always ignores the fallback).
String get kAdminPassword {
  if (_kAdminPasswordFromDefine.isNotEmpty) {
    return _kAdminPasswordFromDefine;
  }
  if (kDebugMode && kAdminPasswordDebugOnly.isNotEmpty) {
    return kAdminPasswordDebugOnly;
  }
  return '';
}

/// Allowed `public.reports.status` values used by the app (must match
/// `reports_status_check` and RLS in Supabase migrations; also `reviewed`).
const String kReportStatusPending = 'pending';
const String kReportStatusResolved = 'resolved';
const String kReportStatusDismissed = 'dismissed';

String _normalizeAdminPassword(String value) {
  // يوحّد الأرقام العربية/الفارسية مع الإنجليزية ويزيل المحارف المخفية.
  const Map<String, String> digitMap = <String, String>{
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };
  final StringBuffer normalized = StringBuffer();
  for (final int rune in value.trim().runes) {
    final String ch = String.fromCharCode(rune);
    if (ch == '\u200e' || ch == '\u200f' || ch == '\u202a' || ch == '\u202c') {
      continue;
    }
    normalized.write(digitMap[ch] ?? ch);
  }
  return normalized.toString();
}

/// أسماء جداول Supabase المربوطة بـ (اقتراح تعديل) و(إضافة عيادة) والعرض.
const String kSupabaseReportsTable = 'reports';
const String kSupabaseReportTotalsTable = 'doctor_report_totals';
const String kSupabasePendingDoctorsTable = 'pending_doctors';
const String kSupabaseDoctorsTable = 'doctors';

// مفاتيح لعمود public.reports.info_issue_type
const Map<String, String> kInfoCorrectionTypeLabels = <String, String>{
  'wrong_phone': 'رقم الهاتف',
  'wrong_map_link': 'رابط الخرائط',
  'wrong_address': 'نص العنوان',
  'wrong_name_or_spec': 'الاسم أو التخصص',
  'other': 'معلومة أخرى',
};

/// حمولة `insert` لجدول [kSupabaseReportsTable]. يحدّث الـ trigger العدد في [kSupabaseReportTotalsTable].
Map<String, dynamic> buildReportRowPayload({
  required int doctorId,
  required String infoIssueType,
  required String errorLocation,
  required String suggestedCorrection,
  String doctorName = '',
}) {
  return <String, dynamic>{
    'doctor_id': doctorId,
    'doctor_name': doctorName.trim(),
    'info_issue_type': infoIssueType.trim(),
    'error_location': errorLocation.trim(),
    'suggested_correction': suggestedCorrection.trim(),
    'status': kReportStatusPending,
  };
}

String reportInsertErrorMessage(Object error) {
  if (error is PostgrestException) {
    return error.message;
  }
  return error.toString();
}

const List<String> kBasraAreas = <String>[
  'ابي الخصيب',
  'الأربع شوارع',
  'الاصمعي',
  'البراضعية',
  'البصرة القديمة',
  'التنومة',
  'الجبيلة',
  'الجزائر',
  'الجزيرة',
  'الجمعيات',
  'الجمهورية',
  'الجنينة',
  'الحكيمية',
  'الحيانية',
  'الخليلية',
  'الدير',
  'الزبير',
  'الطويسة',
  'العباسية',
  'العشار',
  'الفاو',
  'القبلة',
  'القرنة',
  'الكرمة',
  'المدينة',
  'المشرق الجديد',
  'المطيحة',
  'المعقل',
  'النجيبية',
  'الهارثة',
  'ام قصر',
  'بريهة',
  'حي الأصدقاء',
  'خمسة ميل',
  'خور الزبير',
  'سفوان',
  'شارع العسكري',
  'عشار',
  'كرمة علي',
  'مجمع الامل السكنية',
  'ياسين خريبط',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://hygujebngiwemwujjcgm.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh5Z3VqZWJuZ2l3ZW13dWpqY2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3Njg1MjAsImV4cCI6MjA5MTM0NDUyMH0.p9hhJZ8L45ZqwQKuq5TCPWEa2xxBNl0AqHPQUjP1Xvs',
  );

  runApp(const IraqHealthApp());
}

class IraqHealthApp extends StatelessWidget {
  const IraqHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primaryMedicalBlue = Color(0xFF42A5F5);
    const Color softBackground = Color(0xFFF7FBFF);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'المدار الطبي',
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.cairoTextTheme(),
        fontFamily: GoogleFonts.cairo().fontFamily,
        scaffoldBackgroundColor: softBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryMedicalBlue,
          primary: primaryMedicalBlue,
          surface: Colors.white,
        ),
      ),
      routes: <String, WidgetBuilder>{
        '/add-clinic': (_) => const Directionality(
              textDirection: TextDirection.rtl,
              child: AddClinicPage(),
            ),
        '/report': (_) => const Directionality(
              textDirection: TextDirection.rtl,
              child: ReportPage(),
            ),
        '/admin': (BuildContext ctx) {
          final bool fromHomeBypass =
              ModalRoute.of(ctx)?.settings.arguments == true;
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AdminDashboardPage(autoAuthenticated: fromHomeBypass),
          );
        },
      },
      onGenerateRoute: (RouteSettings settings) {
        if (settings.name == '/home') {
          return PageRouteBuilder<dynamic>(
            settings: settings,
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (BuildContext context, Animation<double> a,
                Animation<double> s) {
              return const Directionality(
                textDirection: TextDirection.rtl,
                child: IraqHealthHomePage(),
              );
            },
            transitionsBuilder: (BuildContext context,
                Animation<double> anim,
                Animation<double> s,
                Widget child) {
              return FadeTransition(opacity: anim, child: child);
            },
          );
        }
        return null;
      },
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: SplashScreen(),
      ),
    );
  }
}

class IraqHealthHomePage extends StatefulWidget {
  const IraqHealthHomePage({super.key});

  @override
  State<IraqHealthHomePage> createState() => _IraqHealthHomePageState();
}

class _IraqHealthHomePageState extends State<IraqHealthHomePage> {
  static const int _batchSize = 1000;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _searchFieldVisible = false;

  String? _selectedGovernorate;
  String? _selectedArea;
  String? _selectedSpecialization;
  bool _isLoading = true;
  String? _errorMessage;

  List<Doctor> _allDoctors = <Doctor>[];
  List<Doctor> _filteredDoctors = <Doctor>[];
  List<String> _areas = <String>[];
  List<String> _specializations = <String>[];
  int _adminTapCounter = 0;
  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showDisclaimerIfNeeded();
    });
    _loadDoctors();
  }

  Future<void> _showDisclaimerIfNeeded() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool alreadySeen = prefs.getBool('disclaimer_seen_v1') ?? false;
    if (alreadySeen || !mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('إخلاء مسؤولية'),
          content: const Text(
            'البيانات الطبية داخل التطبيق دقيقة بنسبة تقارب 90%، لكن قد تتغير المعلومات بمرور الوقت. يرجى التحقق المباشر من الجهة الطبية قبل الاعتماد النهائي.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('موافق'),
            ),
          ],
        );
      },
    );

    await prefs.setBool('disclaimer_seen_v1', true);
  }

  Future<void> _loadDoctors() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _allDoctors = <Doctor>[];
      _filteredDoctors = <Doctor>[];
      _areas = <String>[];
      _specializations = <String>[];
      final List<dynamic> allData = <dynamic>[];
      int from = 0;

      while (true) {
        final List<dynamic> response = await _supabase
            .from(kSupabaseDoctorsTable)
            .select('id, spec, name, addr, area, ph, ph2, notes, gove')
.eq('gove', _selectedGovernorate ?? 'البصرة')
.order('id', ascending: true)
            .range(from, from + _batchSize - 1);

        allData.addAll(response);
        if (response.length < _batchSize) {
          break;
        }
        from += _batchSize;
      }

      _allDoctors = allData
          .map((dynamic json) => Doctor.fromJson(json as Map<String, dynamic>))
          .toList();

      final Map<String, int> areaCounts = <String, int>{};
      final Map<String, int> specCounts = <String, int>{};
      for (final Doctor d in _allDoctors) {
        final String area = d.area.trim();
        if (area.isNotEmpty) {
          areaCounts[area] = (areaCounts[area] ?? 0) + 1;
        }
        final String spec = d.spec.trim();
        if (spec.isNotEmpty) {
          specCounts[spec] = (specCounts[spec] ?? 0) + 1;
        }
      }

      _areas = areaCounts.keys.toList()
        ..sort((String a, String b) {
          final int ca = areaCounts[a] ?? 0;
          final int cb = areaCounts[b] ?? 0;
          final int byCount = cb.compareTo(ca);
          if (byCount != 0) {
            return byCount;
          }
          return a.compareTo(b);
        });

      _specializations = specCounts.keys.toList()
        ..sort((String a, String b) {
          final int ca = specCounts[a] ?? 0;
          final int cb = specCounts[b] ?? 0;
          final int byCount = cb.compareTo(ca);
          if (byCount != 0) {
            return byCount;
          }
          return a.compareTo(b);
        });

      _moveIraqiDentalPracticeLabelToSixth(_specializations);

      if (_selectedArea != null && !_areas.contains(_selectedArea)) {
        _selectedArea = null;
      }
      if (_selectedSpecialization != null &&
          !_specializations.contains(_selectedSpecialization)) {
        _selectedSpecialization = null;
      }

      _applyFilters();
    } catch (error, stackTrace) {
      debugPrint('Supabase doctors fetch error: $error');
      debugPrint('Supabase doctors fetch stackTrace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = _humanReadableLoadError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// رسالة "قريباً" للمحافظات التي لا تحتوي على أطباء بعد.
  Widget _buildGovernorateComingSoon() {
    final String gove = _selectedGovernorate ?? 'هذه المحافظة';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.access_time_rounded,
                size: 52,
                color: Color(0xFF42A5F5),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'قريباً',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D3557),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'يتم العمل على إضافة أطباء محافظة $gove قريباً.\nانتظرونا!',
              style: const TextStyle(
                fontSize: 15,
                height: 1.7,
                color: Color(0xFF4A5568),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: _isLoading ? null : _loadDoctors,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث'),
            ),
          ],
        ),
      ),
    );
  }

  /// يحوّل أخطاء الشبكة/الـ Supabase إلى رسالة عربية مفهومة للمستخدم.
  String _humanReadableLoadError(Object error) {
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
      return 'تعذر تحميل بيانات الأطباء (خطأ في الخادم): ${error.message}';
    }
    return 'تعذر تحميل بيانات الأطباء حالياً. حاول مرة أخرى.';
  }

  Future<void> _upsertReportCount(int doctorId) async {
    try {
      final List<dynamic> pending = await _supabase
          .from(kSupabaseReportsTable)
          .select('id')
          .eq('doctor_id', doctorId)
          .eq('status', kReportStatusPending);
      await _supabase.from(kSupabaseReportTotalsTable).upsert(
        <String, dynamic>{
          'doctor_id': doctorId,
          'report_count': pending.length,
        },
        onConflict: 'doctor_id',
      );
    } catch (e) {
      debugPrint('_upsertReportCount failed for docId=$doctorId: $e');
    }
  }

  void _applyFilters() {
    final String searchTerm = _searchController.text.trim().toLowerCase();

    final List<Doctor> results = _allDoctors.where((Doctor doctor) {
      final bool matchesArea =
          _selectedArea == null || doctor.area == _selectedArea;
      final bool matchesSpecialization = _selectedSpecialization == null ||
          doctor.spec == _selectedSpecialization;
      final bool matchesSearch = searchTerm.isEmpty ||
          doctor.name.toLowerCase().contains(searchTerm) ||
          doctor.spec.toLowerCase().contains(searchTerm) ||
          doctor.area.toLowerCase().contains(searchTerm);

      return matchesArea && matchesSpecialization && matchesSearch;
    }).toList();

    setState(() {
      _filteredDoctors = results;
    });
  }

  /// يثبّت تبويب «طب الأسنان» في المركز السادس (index 5) بدل أن يبقى أولاً حسب العدد.
  void _moveIraqiDentalPracticeLabelToSixth(List<String> specs) {
    final int idx = specs.indexWhere(_isIraqiDentalPracticeChipLabel);
    if (idx < 0) {
      return;
    }
    final String item = specs.removeAt(idx);
    final int insertAt = specs.length < 5 ? specs.length : 5;
    specs.insert(insertAt, item);
  }

  bool _isIraqiDentalPracticeChipLabel(String spec) {
    final String normalized =
        spec.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    return normalized.contains('طب الاسنان') ||
        normalized.contains('طب الأسنان');
  }

  Future<void> _openDialer(String phoneNumber) async {
    final String cleaned = _normalizePhone(phoneNumber);
    if (cleaned.isEmpty) {
      return;
    }
    final Uri uri = Uri.parse('tel:$cleaned');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final String cleaned = _normalizePhone(phoneNumber);
    if (cleaned.isEmpty) {
      return;
    }
    final String withoutLeadingZero =
        cleaned.startsWith('0') ? cleaned.substring(1) : cleaned;
    final Uri uri = Uri.parse('https://wa.me/964$withoutLeadingZero');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openMap(String address) async {
    if (address.trim().isEmpty) {
      return;
    }
    final String value = address.trim();
    final bool isDirectMapLink =
        value.startsWith('http://') || value.startsWith('https://');
    final Uri uri = isDirectMapLink
        ? Uri.parse(value)
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(value)}',
          );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _handleAdminTitleTap() async {
    _adminTapCounter += 1;
    if (_adminTapCounter < 4) {
      return;
    }
    _adminTapCounter = 0;
    if (kAdminPassword.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'كلمة مرور الأدمن غير مكوّنة. أضف ADMIN_PASSWORD في .vscode/launch.json أو --dart-define=ADMIN_PASSWORD=...',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    String enteredPassword = '';
    final bool? allowed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('دخول الأدمن'),
          content: TextField(
            obscureText: true,
            onChanged: (String value) => enteredPassword = value,
            decoration: const InputDecoration(
              labelText: 'أدخل كلمة المرور',
              filled: true,
              fillColor: Color(0xFFF2F7FC),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(
                      _normalizeAdminPassword(enteredPassword) ==
                          _normalizeAdminPassword(kAdminPassword),
                    );
              },
              child: const Text('دخول'),
            ),
          ],
        );
      },
    );

    if (!mounted || allowed != true) {
      if (allowed == false && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('كلمة المرور غير صحيحة')),
        );
      }
      return;
    }
    Navigator.pushNamed(context, '/admin', arguments: true);
  }

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  void _showDoctorDetails(BuildContext context, Doctor doctor) {
    final String primaryPhone =
        doctor.ph.trim().isNotEmpty ? doctor.ph.trim() : doctor.ph2.trim();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 8,
              bottom: MediaQuery.paddingOf(ctx).bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(child: _buildSpecAvatar(doctor, radius: 44)),
                  const SizedBox(height: 16),
                  Text(
                    doctor.name.isNotEmpty ? doctor.name : '-',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1D3557),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _detailField('التخصص', doctor.spec),
                  _detailField('المنطقة', doctor.area),
                  _detailField('العنوان', doctor.addr),
                  _detailField('الهاتف الأول', doctor.ph),
                  _detailField('الهاتف الثاني', doctor.ph2),
                  _detailField('ملاحظات', doctor.notes),
                  _detailField('رقم السجل', doctor.id > 0 ? '${doctor.id}' : ''),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: primaryPhone.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  _openDialer(primaryPhone);
                                },
                          icon: const Icon(Icons.call_outlined),
                          label: const Text('اتصال'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: primaryPhone.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  _openWhatsApp(primaryPhone);
                                },
                          icon: FaIcon(
                            FontAwesomeIcons.whatsapp,
                            size: 20,
                            color: const Color(0xFF25D366),
                          ),
                          label: const Text('واتساب'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: doctor.addr.trim().isEmpty
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _openMap(doctor.addr);
                            },
                      icon: const Icon(Icons.place_rounded),
                      label: const Text('فتح الموقع على الخرائط'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showReportDoctorSheet(Doctor doctor) {
    if (doctor.id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر الإرسال: رقم السجل غير صالح.')),
      );
      return;
    }
    // Capture the parent's messenger before opening the sheet, so success
    // feedback can be shown safely after the sheet is gone (no stale ctx).
    final ScaffoldMessengerState parentMessenger =
        ScaffoldMessenger.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetCtx) {
        return _ReportDoctorSheet(
          doctor: doctor,
          onSubmitted: (int doctorId) {
            parentMessenger.showSnackBar(
              const SnackBar(
                content: Text('شكراً، تم حفظ الاقتراح بنجاح.'),
              ),
            );
            if (mounted) {
              _upsertReportCount(doctorId);
            }
          },
        );
      },
    );
  }

  Widget _detailField(String label, String value) {
    final String trimmed = value.trim();
    final String display = trimmed.isNotEmpty ? trimmed : '-';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF718096),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F7FC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SelectableText(
              display,
              style: const TextStyle(
                fontSize: 15,
                height: 1.35,
                color: Color(0xFF1D3557),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecAvatar(Doctor doctor, {required double radius}) {
    final _SpecVisual visual = _SpecVisual.forSpecialization(doctor.spec);
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: visual.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: visual.gradientColors.last.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: FaIcon(
            visual.faIcon,
            color: Colors.white,
            size: radius * 0.95,
          ),
        ),
      ),
    );
  }

  void _onInstallTap(BuildContext ctx) {
    triggerPwaInstall();
  }

  void _toggleSearchField() {
    setState(() {
      _searchFieldVisible = !_searchFieldVisible;
    });
    if (_searchFieldVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    } else {
      _searchFocusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryMedicalBlue = Color(0xFF42A5F5);
    const Color sectionShadow = Color(0x1A000000);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/add-clinic'),
        tooltip: 'إضافة عيادة',
        backgroundColor: primaryMedicalBlue,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      // في RTL تكون "البداية" يمين الشاشة — موضع مريح للإبهام.
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            floating: false,
            backgroundColor: primaryMedicalBlue,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 1,
            centerTitle: true,
            automaticallyImplyLeading: false,
            leading: kIsWeb
                ? IconButton(
                    tooltip: 'تنزيل التطبيق',
                    onPressed: () => _onInstallTap(context),
                    icon: const Icon(Icons.install_mobile_outlined),
                  )
                : null,
            title: GestureDetector(
              onTap: _handleAdminTitleTap,
              child: const Text(
                'المدار الطبي',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            actions: <Widget>[
              IconButton(
                tooltip:
                    _searchFieldVisible ? 'إغلاق البحث' : 'بحث',
                onPressed: _toggleSearchField,
                icon: Icon(
                  _searchFieldVisible ? Icons.close : Icons.search,
                ),
              ),
            ],
            expandedHeight: 202,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: EdgeInsets.zero,
              centerTitle: true,
              background: ColoredBox(
                color: primaryMedicalBlue,
                child: SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          8,
                          kToolbarHeight + 2,
                          8,
                          6,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _buildLocationFiltersCard(sectionShadow),
                            const SizedBox(height: 6),
                            _buildSpecializationFilterRow(
                              primaryMedicalBlue,
                              sectionShadow,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              alignment: AlignmentDirectional.topCenter,
              child: _searchFieldVisible
                  ? Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        12,
                        4,
                        12,
                        8,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: (_) => _applyFilters(),
                          decoration: InputDecoration(
                            hintText: 'ابحث عن طبيب أو تخصص',
                            filled: true,
                            fillColor: const Color(0xFFEEEEEE),
                            isDense: true,
                            prefixIcon: const Icon(Icons.search, size: 22),
                            suffixIcon: IconButton(
                              tooltip: 'إغلاق',
                              onPressed: () {
                                setState(() {
                                  _searchFieldVisible = false;
                                });
                                _searchFocusNode.unfocus();
                              },
                              icon: const Icon(Icons.close),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 2, 12, 4),
              child: Text(
                'أحدث العيادات المضافة',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D3557),
                ),
              ),
            ),
          ),
          if (_isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Semantics(
                  label: 'جارٍ التحميل',
                  child: const CircularProgressIndicator(),
                ),
              ),
            )
          else if (_errorMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFFB00020)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _loadDoctors,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_allDoctors.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildGovernorateComingSoon(),
            )
          else if (_filteredDoctors.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Center(
                  child: Text(
                    'لا توجد نتائج مطابقة للفلاتر الحالية.',
                    style: TextStyle(color: Color(0xFF4A5568)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 88),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    return _buildClinicCard(_filteredDoctors[index]);
                  },
                  childCount: _filteredDoctors.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// فلاتر المحافظة/المنطقة فقط (البحث النصي من أيقونة المكبّر في [SliverAppBar]).
  Widget _buildLocationFiltersCard(Color sectionShadow) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: sectionShadow,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildDropdownField(
              label: 'المحافظة',
              value: _selectedGovernorate,
              items: kGovernorates,
              onChanged: (String? value) {
                setState(() {
                  _selectedGovernorate = value;
                });
                _loadDoctors();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildAreaDropdownField(),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF2F7FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      hint: Text('اختر $label'),
      items: items
          .map(
            (String item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildAreaDropdownField() {
    return DropdownButtonFormField<String?>(
      initialValue: _selectedArea,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'المنطقة',
        filled: true,
        fillColor: const Color(0xFFF2F7FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      hint: const Text('اختر المنطقة'),
      items: <DropdownMenuItem<String?>>[
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('الكل'),
        ),
        ..._areas.map(
          (String area) => DropdownMenuItem<String?>(
            value: area,
            child: Text(area),
          ),
        ),
      ],
      onChanged: (String? value) {
        setState(() {
          _selectedArea = value;
        });
        _applyFilters();
      },
    );
  }

  Widget _buildSpecializationFilterRow(
    Color primaryMedicalBlue,
    Color sectionShadow,
  ) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: sectionShadow,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'فلتر التخصصات',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1D3557),
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 4, 0),
                  child: ChoiceChip(
                    label: const Text('الكل', style: TextStyle(fontSize: 12)),
                    selected: _selectedSpecialization == null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) {
                      setState(() {
                        _selectedSpecialization = null;
                      });
                      _applyFilters();
                    },
                  ),
                ),
                ..._specializations.map((String specialization) {
                  final bool isSelected =
                      _selectedSpecialization == specialization;
                  return Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 4, 0),
                    child: ChoiceChip(
                      selectedColor: primaryMedicalBlue.withValues(alpha: 0.15),
                      label: Text(
                        specialization,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: isSelected,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (_) {
                        setState(() {
                          _selectedSpecialization =
                              isSelected ? null : specialization;
                        });
                        _applyFilters();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicCard(Doctor doctor) {
    const Color chipTeal = Color(0xFF006064);
    const Color chipBg = Color(0xFFE0F7FA);
    const Color kCardBlue = Color(0xFF1565C0);
    final String primaryPhone =
        doctor.ph.trim().isNotEmpty ? doctor.ph.trim() : doctor.ph2.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: const Color(0x22000000),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDoctorDetails(context, doctor),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              // أولوية الصف: النص (يمين) ثم الأفاتار يسار الشاشة في وضع RTL
              textDirection: TextDirection.rtl,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        doctor.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Chip(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          side: const BorderSide(color: Color(0xFF00ACC1)),
                          backgroundColor: chipBg,
                          label: Text(
                            doctor.spec,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: chipTeal,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.place_rounded,
                            size: 16,
                            color: Colors.red.shade400,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              doctor.area,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF718096),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Semantics(
                        label: 'واتساب، الخرائط، الاتصال، اقتراح تعديل',
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                onPressed: primaryPhone.isEmpty
                                    ? null
                                    : () => _openWhatsApp(primaryPhone),
                                icon: const FaIcon(
                                  FontAwesomeIcons.whatsapp,
                                  size: 18,
                                  color: Color(0xFF25D366),
                                ),
                                tooltip: 'واتساب',
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  minimumSize: const Size(36, 36),
                                  maximumSize: const Size(40, 40),
                                ),
                              ),
                              IconButton(
                                onPressed: doctor.addr.trim().isEmpty
                                    ? null
                                    : () => _openMap(doctor.addr),
                                icon: Icon(
                                  Icons.add_location_alt_rounded,
                                  size: 20,
                                  color: Colors.blue.shade700,
                                ),
                                tooltip: 'الموقع على الخريطة',
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  minimumSize: const Size(36, 36),
                                  maximumSize: const Size(40, 40),
                                ),
                              ),
                              IconButton(
                                onPressed: primaryPhone.isEmpty
                                    ? null
                                    : () => _openDialer(primaryPhone),
                                icon: const Icon(
                                  Icons.call_outlined,
                                  size: 20,
                                ),
                                tooltip: 'اتصال',
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  minimumSize: const Size(36, 36),
                                  maximumSize: const Size(40, 40),
                                  foregroundColor: kCardBlue,
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    _showReportDoctorSheet(doctor),
                                icon: const Icon(
                                  Icons.edit_note_outlined,
                                  size: 20,
                                ),
                                tooltip: 'اقتراح تعديل',
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  minimumSize: const Size(36, 36),
                                  maximumSize: const Size(40, 40),
                                  foregroundColor: const Color(0xFF1D3557),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFFE3F2FD),
                  child: Icon(
                    Icons.person,
                    size: 32,
                    color: kCardBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal-bottom-sheet body for "اقتراح تعديل" on a doctor card.
///
/// Owns its [TextEditingController]s so Flutter's State lifecycle disposes them
/// after the route is fully removed — never mid-frame, which previously caused
/// `_dependents.isEmpty` and "controller used after dispose" red screens.
class _ReportDoctorSheet extends StatefulWidget {
  const _ReportDoctorSheet({
    required this.doctor,
    required this.onSubmitted,
  });

  final Doctor doctor;
  final void Function(int doctorId) onSubmitted;

  @override
  State<_ReportDoctorSheet> createState() => _ReportDoctorSheetState();
}

class _ReportDoctorSheetState extends State<_ReportDoctorSheet> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _whereWrongController = TextEditingController();
  final TextEditingController _suggestedController = TextEditingController();
  String _typeKey = kInfoCorrectionTypeLabels.keys.first;
  bool _submitting = false;

  @override
  void dispose() {
    _whereWrongController.dispose();
    _suggestedController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();

    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState? sheetMessenger =
        ScaffoldMessenger.maybeOf(context);
    final int docId = widget.doctor.id;

    setState(() => _submitting = true);

    try {
      await _supabase.from(kSupabaseReportsTable).insert(
            buildReportRowPayload(
              doctorId: docId,
              doctorName: widget.doctor.name,
              infoIssueType: _typeKey,
              errorLocation: _whereWrongController.text,
              suggestedCorrection: _suggestedController.text,
            ),
          );

      // Notify the parent BEFORE popping so the success SnackBar uses the
      // parent's still-mounted messenger.
      widget.onSubmitted(docId);

      if (navigator.mounted) {
        navigator.pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      sheetMessenger?.showSnackBar(
        SnackBar(
          content: Text(
            'تعذر الإرسال: ${reportInsertErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.paddingOf(context).bottom +
              20,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'اقتراح تعديل على المعلومات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1D3557),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.doctor.name,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF4A5568),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'اقترح تصحيح المعلومات الظاهرة فقط (رقم، عنوان، رابط).',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF718096),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: kInfoCorrectionTypeLabels.keys.first,
                  decoration: const InputDecoration(
                    labelText: 'أي حقل ناقص التصحيح؟',
                    filled: true,
                    fillColor: Color(0xFFF2F7FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                  items: kInfoCorrectionTypeLabels.entries
                      .map(
                        (MapEntry<String, String> e) =>
                            DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (String? v) {
                    if (v == null) return;
                    setState(() => _typeKey = v);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _whereWrongController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText:
                        'وين يظهر الخطأ بالضبط؟ (مثلاً: مربع الهاتف، سطر التخصص)',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: Color(0xFFF2F7FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                  validator: (String? value) {
                    if (value == null || value.trim().length < 3) {
                      return 'حدد مكان الخطأ في البطاقة (3 أحرف على الأقل)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _suggestedController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'ما التصحيح المقترح؟ (المعلومة الصحيحة)',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: Color(0xFFF2F7FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                  validator: (String? value) {
                    if (value == null || value.trim().length < 3) {
                      return 'اذكر التصحيح المقترح بوضوح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(
                    _submitting ? 'جارٍ الإرسال...' : 'إرسال الاقتراح',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AddClinicPage extends StatefulWidget {
  const AddClinicPage({super.key});

  @override
  State<AddClinicPage> createState() => _AddClinicPageState();
}

class _AddClinicPageState extends State<AddClinicPage> {
  static const int _kTotalSteps = 4;

  final SupabaseClient _supabase = Supabase.instance.client;

  final List<GlobalKey<FormState>> _stepFormKeys = List<GlobalKey<FormState>>.generate(
    _kTotalSteps,
    (_) => GlobalKey<FormState>(),
  );

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _physicianCustomSpecController = TextEditingController();
  final TextEditingController _imagingCustomController = TextEditingController();
  final TextEditingController _areaOtherGovernorateController = TextEditingController();
  final TextEditingController _basraCustomAreaController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _mapsUrlController = TextEditingController();
  final TextEditingController _phController = TextEditingController();
  final TextEditingController _ph2Controller = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  int _currentStep = 0;
  _MedicalFieldType? _medicalType;
  String? _selectedPhysicianSpec;
  String? _selectedImagingType;
  bool _physicianUseCustom = false;
  bool _imagingUseCustom = false;
  String _governorate = kGovernorates.first;
  String? _selectedBasraArea;
  bool _basraUseCustomArea = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _physicianCustomSpecController.dispose();
    _imagingCustomController.dispose();
    _areaOtherGovernorateController.dispose();
    _basraCustomAreaController.dispose();
    _addressController.dispose();
    _mapsUrlController.dispose();
    _phController.dispose();
    _ph2Controller.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _buildSpecForSubmit() {
    final _MedicalFieldType? t = _medicalType;
    if (t == null) {
      return '';
    }
    switch (t) {
      case _MedicalFieldType.physician:
        if (_physicianUseCustom) {
          return _physicianCustomSpecController.text.trim();
        }
        return _selectedPhysicianSpec ?? '';
      case _MedicalFieldType.radiology:
        if (_imagingUseCustom) {
          return _imagingCustomController.text.trim();
        }
        return _selectedImagingType ?? '';
      case _MedicalFieldType.dentist:
        return 'طبيب أسنان';
      case _MedicalFieldType.pharmacy:
        return 'صيدلية';
      case _MedicalFieldType.lab:
        return 'مختبر';
    }
  }

  String _buildAreaForSubmit() {
    if (_governorate == 'البصرة') {
      if (_basraUseCustomArea) {
        return _basraCustomAreaController.text.trim();
      }
      return _selectedBasraArea ?? '';
    }
    return _areaOtherGovernorateController.text.trim();
  }

  String _buildNotesForSubmit() {
    final String a = _addressController.text.trim();
    final String n = _notesController.text.trim();
    return 'العنوان: $a\n\nملاحظات: $n';
  }

  bool _validateStep1() {
    if (_medicalType == null) {
      return false;
    }
    if (_medicalType == _MedicalFieldType.physician) {
      if (_physicianUseCustom) {
        return _physicianCustomSpecController.text.trim().length >= 2;
      }
      return _selectedPhysicianSpec != null &&
          _selectedPhysicianSpec != kDropdownAddCustom &&
          _selectedPhysicianSpec!.isNotEmpty;
    }
    if (_medicalType == _MedicalFieldType.radiology) {
      if (_imagingUseCustom) {
        return _imagingCustomController.text.trim().length >= 2;
      }
      return _selectedImagingType != null &&
          _selectedImagingType != kDropdownAddCustom &&
          _selectedImagingType!.isNotEmpty;
    }
    return true;
  }

  bool _validateStep2() {
    if (_governorate.isEmpty) {
      return false;
    }
    if (_governorate == 'البصرة') {
      if (_basraUseCustomArea) {
        return _basraCustomAreaController.text.trim().length >= 2;
      }
      return _selectedBasraArea != null &&
          _selectedBasraArea != kDropdownAddCustom &&
          _selectedBasraArea!.isNotEmpty;
    }
    return _areaOtherGovernorateController.text.trim().length >= 2;
  }

  /// تحقق يدوي لجدول kSupabasePendingDoctorsTable بدون الاعتماد فقط على
  /// FormState للخطوات 1-2.
  bool _validateStep1CustomTextIfNeeded() {
    if (_medicalType == _MedicalFieldType.physician && _physicianUseCustom) {
      return _physicianCustomSpecController.text.trim().length >= 2;
    }
    if (_medicalType == _MedicalFieldType.radiology && _imagingUseCustom) {
      return _imagingCustomController.text.trim().length >= 2;
    }
    return true;
  }

  bool _validateStep2CustomTextIfNeeded() {
    if (_governorate == 'البصرة' && _basraUseCustomArea) {
      return _basraCustomAreaController.text.trim().length >= 2;
    }
    return true;
  }

  bool _validateContactFieldsForSupabase() {
    if (_addressController.text.trim().length < 3) {
      return false;
    }
    final String ph = _phController.text.trim();
    if (ph.isEmpty || ph.length < 6) {
      return false;
    }
    final String p2 = _ph2Controller.text.trim();
    if (p2.isNotEmpty && p2.length < 6) {
      return false;
    }
    final String maps = _mapsUrlController.text.trim();
    if (maps.isNotEmpty &&
        !maps.startsWith('http://') && !maps.startsWith('https://')) {
      return false;
    }
    if (_notesController.text.trim().length < 3) {
      return false;
    }
    return true;
  }

  /// جاهزية الإرسال إلى [kSupabasePendingDoctorsTable].
  bool _validateEntireClinicForPendingInsert() {
    if (_nameController.text.trim().length < 2) {
      return false;
    }
    if (!_validateStep1() || !_validateStep1CustomTextIfNeeded()) {
      return false;
    }
    if (!_validateStep2() || !_validateStep2CustomTextIfNeeded()) {
      return false;
    }
    if (!_validateContactFieldsForSupabase()) {
      return false;
    }
    return true;
  }

  void _goNext() {
    bool ok = false;
    switch (_currentStep) {
      case 0:
        ok = _stepFormKeys[0].currentState?.validate() ?? false;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى إدخال اسم العيادة أو الطبيب.')),
          );
        }
        break;
      case 1:
        final bool vForm = _stepFormKeys[1].currentState?.validate() ?? false;
        ok = vForm && _validateStep1();
        if (!ok) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('يرجى اختيار المجال الطبي وإكمال الحقول المطلوبة.'),
            ),
          );
        }
        break;
      case 2:
        final bool vForm = _stepFormKeys[2].currentState?.validate() ?? false;
        ok = vForm && _validateStep2();
        if (!ok) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى اختيار المحافظة والمنطقة.')),
          );
        }
        break;
    }
    if (!ok) {
      return;
    }
    if (_currentStep < _kTotalSteps - 1) {
      setState(() {
        _currentStep += 1;
      });
    }
  }

  void _goBack() {
    if (_currentStep <= 0) {
      return;
    }
    setState(() {
      _currentStep -= 1;
    });
  }

  Future<void> _submit() async {
    if (!_validateEntireClinicForPendingInsert()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تأكد من إكمال الخطوات الأربع بشكل صحيح (الاسم، المجال، الموقع، بيانات التواصل) ثم أعد الإرسال.',
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _isSubmitting = true;
    });
    try {
      final String spec = _buildSpecForSubmit();
      final String area = _buildAreaForSubmit();
      final String notes = _buildNotesForSubmit();
      final String maps = _mapsUrlController.text.trim();
      final String textAddr = _addressController.text.trim();
      final String ph2Text = _ph2Controller.text.trim();
      final Map<String, dynamic> payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'spec': spec,
        'addr': maps.isNotEmpty ? maps : textAddr,
        'area': area,
        'ph': _phController.text.trim(),
        'ph2': ph2Text,
        'notes': notes,
        'gove': _governorate,
      };
      await _supabase.from(kSupabasePendingDoctorsTable).insert(payload);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال الطلب بنجاح للمراجعة.')),
      );
      _resetForm();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إرسال الطلب: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _resetForm() {
    _nameController.clear();
    _physicianCustomSpecController.clear();
    _imagingCustomController.clear();
    _areaOtherGovernorateController.clear();
    _basraCustomAreaController.clear();
    _addressController.clear();
    _mapsUrlController.clear();
    _phController.clear();
    _ph2Controller.clear();
    _notesController.clear();
    setState(() {
      _currentStep = 0;
      _medicalType = null;
      _selectedPhysicianSpec = null;
      _selectedImagingType = null;
      _physicianUseCustom = false;
      _imagingUseCustom = false;
      _governorate = kGovernorates.first;
      _selectedBasraArea = null;
      _basraUseCustomArea = false;
    });
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF2F7FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _stepLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1D3557),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryMedicalBlue = Color(0xFF42A5F5);
    final double progress = (_currentStep + 1) / _kTotalSteps;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة'),
        backgroundColor: primaryMedicalBlue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'الخطوة ${_currentStep + 1} من $_kTotalSteps',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A5568),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      primaryMedicalBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (Widget child, Animation<double> anim) {
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                );
              },
              child: RepaintBoundary(
                key: ValueKey<int>(_currentStep),
                child: <Widget>[
                  _buildStep1Name(),
                  _buildStep2Medical(),
                  _buildStep3Location(),
                  _buildStep4Contact(),
                ][_currentStep],
              ),
            ),
          ),
          _buildNavBar(),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
    final bool isLast = _currentStep == _kTotalSteps - 1;
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              if (_currentStep > 0)
                TextButton(
                  onPressed: _goBack,
                  child: const Text('رجوع'),
                )
              else
                const SizedBox(width: 72),
              const Spacer(),
              if (isLast)
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: Text(_isSubmitting ? 'جارٍ الإرسال...' : 'إرسال الطلب'),
                )
              else
                FilledButton(
                  onPressed: _goNext,
                  child: const Text('التالي'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1Name() {
    return Form(
      key: _stepFormKeys[0],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _stepLabel('الخطوة ١: الاسم'),
          const Text(
            'أدخل الاسم الظاهر للجمهور كما تريد أن يظهر في التطبيق.',
            style: TextStyle(color: Color(0xFF718096), fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration('اسم الطبيب / المركز *'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => setState(() {}),
            validator: (String? v) {
              if (v == null || v.trim().length < 2) {
                return 'هذا الحقل مطلوب';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Medical() {
    return Form(
      key: _stepFormKeys[1],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _stepLabel('الخطوة ٢: المجال الطبي'),
          const Text(
            'اختر فئة العيادة. سيظهر لك اختيارات إضافية عند الحاجة.',
            style: TextStyle(color: Color(0xFF718096), fontSize: 14),
          ),
          const SizedBox(height: 12),
          ...<Widget>[
            _medicalSelectTile('طبيب', _MedicalFieldType.physician),
            _medicalSelectTile('اشعة وسونار', _MedicalFieldType.radiology),
            _medicalSelectTile('طبيب أسنان', _MedicalFieldType.dentist),
            _medicalSelectTile('صيدلية', _MedicalFieldType.pharmacy),
            _medicalSelectTile('مختبر', _MedicalFieldType.lab),
          ],
          const SizedBox(height: 12),
          if (_medicalType == _MedicalFieldType.physician) _physicianSpecSection(),
          if (_medicalType == _MedicalFieldType.radiology) _imagingSection(),
        ],
      ),
    );
  }

  Widget _medicalSelectTile(String title, _MedicalFieldType value) {
    final bool selected = _medicalType == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? const Color(0xFFE3F2FD)
            : const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          onTap: () {
            setState(() {
              _medicalType = value;
              _selectedPhysicianSpec = null;
              _selectedImagingType = null;
              _physicianUseCustom = false;
              _imagingUseCustom = false;
            });
          },
          leading: Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected ? const Color(0xFF1976D2) : const Color(0xFF94A3B8),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _physicianSpecSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 4),
        const Text('التخصص *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(
              'phys_${_physicianUseCustom}_$_selectedPhysicianSpec'),
          initialValue: _physicianUseCustom
              ? kDropdownAddCustom
              : _selectedPhysicianSpec,
          isExpanded: true,
          decoration: _inputDecoration('اختر التخصص'),
          items: <DropdownMenuItem<String>>[
            ...kPhysicianSpecializations.map(
              (String s) => DropdownMenuItem<String>(
                value: s,
                child: Text(
                  s,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ),
            const DropdownMenuItem<String>(
              value: kDropdownAddCustom,
              child: Text('إضافة تخصص جديد'),
            ),
          ],
          onChanged: (String? v) {
            if (v == null) {
              return;
            }
            setState(() {
              if (v == kDropdownAddCustom) {
                _physicianUseCustom = true;
                _selectedPhysicianSpec = kDropdownAddCustom;
              } else {
                _physicianUseCustom = false;
                _selectedPhysicianSpec = v;
              }
            });
          },
        ),
        if (_physicianUseCustom) ...<Widget>[
          const SizedBox(height: 10),
          TextFormField(
            controller: _physicianCustomSpecController,
            decoration: _inputDecoration('اكتب التخصص الجديد *'),
            onChanged: (_) => setState(() {}),
            validator: (String? v) {
              if (!_physicianUseCustom) {
                return null;
              }
              if (v == null || v.trim().length < 2) {
                return 'مطلوب';
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  Widget _imagingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 4),
        const Text('نوع الاشعة *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(
              'img_${_imagingUseCustom}_$_selectedImagingType'),
          initialValue: _imagingUseCustom
              ? kDropdownAddCustom
              : _selectedImagingType,
          isExpanded: true,
          decoration: _inputDecoration('اختر النوع'),
          items: <DropdownMenuItem<String>>[
            ...kImagingModalityOptions.map(
              (String s) => DropdownMenuItem<String>(
                value: s,
                child: Text(
                  s,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ),
            const DropdownMenuItem<String>(
              value: kDropdownAddCustom,
              child: Text('إضافة نوع جديد'),
            ),
          ],
          onChanged: (String? v) {
            if (v == null) {
              return;
            }
            setState(() {
              if (v == kDropdownAddCustom) {
                _imagingUseCustom = true;
                _selectedImagingType = kDropdownAddCustom;
              } else {
                _imagingUseCustom = false;
                _selectedImagingType = v;
              }
            });
          },
        ),
        if (_imagingUseCustom) ...<Widget>[
          const SizedBox(height: 10),
          TextFormField(
            controller: _imagingCustomController,
            decoration: _inputDecoration('اكتب النوع الجديد *'),
            onChanged: (_) => setState(() {}),
            validator: (String? v) {
              if (!_imagingUseCustom) {
                return null;
              }
              if (v == null || v.trim().length < 2) {
                return 'مطلوب';
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  Widget _buildStep3Location() {
    return Form(
      key: _stepFormKeys[2],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _stepLabel('الخطوة ٣: الموقع'),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(_governorate),
            initialValue: _governorate,
            isExpanded: true,
            decoration: _inputDecoration('المحافظة *'),
            items: kGovernorates
                .map(
                  (String g) => DropdownMenuItem<String>(
                    value: g,
                    child: Text(g),
                  ),
                )
                .toList(),
            onChanged: (String? g) {
              if (g == null) {
                return;
              }
              setState(() {
                _governorate = g;
                if (g != 'البصرة') {
                  _selectedBasraArea = null;
                  _basraUseCustomArea = false;
                }
              });
            },
          ),
          const SizedBox(height: 12),
          if (_governorate == 'البصرة') _basraAreaSection() else _otherGovernorateArea(),
        ],
      ),
    );
  }

  Widget _basraAreaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text('المنطقة (البصرة) *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey<String>(
              'bs_${_basraUseCustomArea}_$_selectedBasraArea'),
          initialValue:
              _basraUseCustomArea ? kDropdownAddCustom : _selectedBasraArea,
          isExpanded: true,
          decoration: _inputDecoration('اختر المنطقة'),
          items: <DropdownMenuItem<String>>[
            ...kBasraAreas.map(
              (String a) => DropdownMenuItem<String>(value: a, child: Text(a)),
            ),
            const DropdownMenuItem<String>(
              value: kDropdownAddCustom,
              child: Text('إضافة منطقة جديدة'),
            ),
          ],
          onChanged: (String? v) {
            if (v == null) {
              return;
            }
            setState(() {
              if (v == kDropdownAddCustom) {
                _basraUseCustomArea = true;
                _selectedBasraArea = kDropdownAddCustom;
              } else {
                _basraUseCustomArea = false;
                _selectedBasraArea = v;
              }
            });
          },
        ),
        if (_basraUseCustomArea) ...<Widget>[
          const SizedBox(height: 10),
          TextFormField(
            controller: _basraCustomAreaController,
            decoration: _inputDecoration('اسم المنطقة *'),
            onChanged: (_) => setState(() {}),
            validator: (String? v) {
              if (!_basraUseCustomArea) {
                return null;
              }
              if (v == null || v.trim().length < 2) {
                return 'مطلوب';
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  Widget _otherGovernorateArea() {
    return TextFormField(
      controller: _areaOtherGovernorateController,
      minLines: 1,
      maxLines: 2,
      decoration: _inputDecoration('المنطقة *'),
      onChanged: (_) => setState(() {}),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (String? v) {
        if (v == null || v.trim().length < 2) {
          return 'أدخل المنطقة أو الأحياء';
        }
        return null;
      },
    );
  }

  Widget _buildStep4Contact() {
    return Form(
      key: _stepFormKeys[3],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _stepLabel('الخطوة ٤: بيانات التواصل'),
          TextFormField(
            controller: _addressController,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration('عنوان العيادة (نص) *'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (String? v) {
              if (v == null || v.trim().length < 3) {
                return 'مطلوب';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _phController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration('رقم الهاتف *'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (String? v) {
              if (v == null || v.trim().isEmpty) {
                return 'مطلوب';
              }
              if (v.trim().length < 6) {
                return 'رقم غير مكتمل';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _ph2Controller,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration('الهاتف الثاني (اختياري)'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (String? v) {
              if (v == null || v.trim().isEmpty) {
                return null;
              }
              if (v.trim().length < 6) {
                return 'رقم غير مكتمل';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _mapsUrlController,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration('رابط خرائط Google (اختياري)'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (String? v) {
              final String t = v?.trim() ?? '';
              if (t.isEmpty) return null;
              if (!t.startsWith('http://') && !t.startsWith('https://')) {
                return 'رابط يبدأ بـ http:// أو https://';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _notesController,
            minLines: 3,
            maxLines: 6,
            textInputAction: TextInputAction.done,
            decoration: _inputDecoration('ملاحظات *'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (String? v) {
              if (v == null || v.trim().length < 3) {
                return 'مطلوب';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  // Context-independent messenger: never call ScaffoldMessenger.of(context) here.
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _doctorIdController = TextEditingController();
  final TextEditingController _doctorNameController = TextEditingController();
  final TextEditingController _whereWrongController = TextEditingController();
  final TextEditingController _suggestedController = TextEditingController();
  String _typeKey = kInfoCorrectionTypeLabels.keys.first;
  bool _isSubmitting = false;
  bool _isMounted = false;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
  }

  @override
  void dispose() {
    _isMounted = false;
    _doctorIdController.dispose();
    _doctorNameController.dispose();
    _whereWrongController.dispose();
    _suggestedController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _submitReport() async {
    // Stabilise keyboard / focus before any async work.
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    // Capture navigator before the async gap.
    final NavigatorState navigator = Navigator.of(context);

    if (_isMounted && mounted) {
      setState(() => _isSubmitting = true);
    }

    final int? doctorId = int.tryParse(_doctorIdController.text.trim());
    if (doctorId == null || doctorId <= 0) {
      if (_isMounted && mounted) {
        setState(() => _isSubmitting = false);
      }
      _showSnack('أدخل رقم سجل صحيح للعيادة.');
      return;
    }

    final Map<String, dynamic> reportRow = buildReportRowPayload(
      doctorId: doctorId,
      doctorName: _doctorNameController.text,
      infoIssueType: _typeKey,
      errorLocation: _whereWrongController.text,
      suggestedCorrection: _suggestedController.text,
    );

    try {
      await _supabase.from(kSupabaseReportsTable).insert(reportRow);

      _showSnack('شكراً، تم حفظ الاقتراح بنجاح.');

      if (navigator.canPop()) {
        navigator.pop();
      } else if (_isMounted && mounted) {
        // Only reached when there is no route to pop (very rare).
        // Clear controllers and reset state without touching the Form tree.
        _doctorIdController.clear();
        _doctorNameController.clear();
        _whereWrongController.clear();
        _suggestedController.clear();
        setState(() {
          _isSubmitting = false;
          _typeKey = kInfoCorrectionTypeLabels.keys.first;
        });
      }
    } catch (e) {
      debugPrint('SUBMISSION FAILED: $e');
      if (_isMounted && mounted) {
        setState(() => _isSubmitting = false);
      }
      _showSnack('تعذر الإرسال: ${reportInsertErrorMessage(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryMedicalBlue = Color(0xFF42A5F5);
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('اقتراح تعديل معلومات'),
        backgroundColor: primaryMedicalBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              const Text(
                'للاقتراحات التي تخص المعلومات الظاهرة فقط (ليس سلوكاً أو تقييماً).',
                style: TextStyle(
                  color: Color(0xFF718096),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _doctorIdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'رقم سجل العيادة (مطلوب)',
                  filled: true,
                  fillColor: Color(0xFFF2F7FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                validator: (String? value) {
                  final String v = value?.trim() ?? '';
                  if (v.isEmpty) {
                    return 'أدخل رقم سجل يظهر في بطاقة العيادة';
                  }
                  final int? n = int.tryParse(v);
                  if (n == null || n <= 0) {
                    return 'أدخل رقمًا صحيحًا';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _doctorNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم العيادة (كما تظهر في التطبيق) *',
                  filled: true,
                  fillColor: Color(0xFFF2F7FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().length < 2) {
                    return 'أدخل اسم العيادة (حرفان على الأقل)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: kInfoCorrectionTypeLabels.keys.first,
                decoration: const InputDecoration(
                  labelText: 'أي حقل ناقص التصحيح؟',
                  filled: true,
                  fillColor: Color(0xFFF2F7FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                items: kInfoCorrectionTypeLabels.entries
                    .map(
                      (MapEntry<String, String> e) => DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    )
                    .toList(),
                onChanged: (String? v) {
                  if (v == null) {
                    return;
                  }
                  setState(() {
                    _typeKey = v;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _whereWrongController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText:
                      'وين يظهر الخطأ بالضبط؟ (مثلاً: مربع الهاتف، سطر التخصص)',
                  filled: true,
                  fillColor: Color(0xFFF2F7FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().length < 3) {
                    return 'حدد مكان الخطأ (3 أحرف على الأقل)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _suggestedController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'ما التصحيح المقترح؟ (المعلومة الصحيحة)',
                  filled: true,
                  fillColor: Color(0xFFF2F7FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                validator: (String? value) {
                  if (value == null || value.trim().length < 3) {
                    return 'اذكر التصحيح المقترح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submitReport,
                  child: Text(
                    _isSubmitting ? 'جارٍ الإرسال...' : 'إرسال الاقتراح',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key, this.autoAuthenticated = false});

  /// `true` عند فتح المسار بـ [Navigator.pushNamed] مع `arguments: true` (بعد التحقق من الرئيسية).
  final bool autoAuthenticated;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _doctorSearchController = TextEditingController();
  late bool _authenticated;
  bool _isLoading = false;
  List<Map<String, dynamic>> _pendingDoctors = <Map<String, dynamic>>[];
  /// يُملأ من [kSupabaseReportsTable] (اقتراح تعديل من التطبيق).
  List<Map<String, dynamic>> _reportRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _searchedDoctors = <Map<String, dynamic>>[];
  bool _isSearchingDoctors = false;
  bool _doctorSearchPerformed = false;

  @override
  void initState() {
    super.initState();
    _authenticated = widget.autoAuthenticated;
    if (_authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadDashboardData();
        }
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _doctorSearchController.dispose();
    super.dispose();
  }

  /// ربط لوحة الأدمن بجدول [kSupabasePendingDoctorsTable] و [kSupabaseReportsTable].
  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });
    List<Map<String, dynamic>> nextPending = <Map<String, dynamic>>[];
    List<Map<String, dynamic>> nextReports = <Map<String, dynamic>>[];
    try {
      final List<dynamic> pending = await _supabase
          .from(kSupabasePendingDoctorsTable)
          .select()
          .order('id');
      nextPending = pending.cast<Map<String, dynamic>>();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر جلب طلبات العيادات: $error'),
          ),
        );
      }
    }
    try {
      final List<dynamic> reports = await _supabase
          .from(kSupabaseReportsTable)
          .select(
            'id, doctor_id, doctor_name, info_issue_type, error_location, suggested_correction, status, created_at',
          )
          .eq('status', kReportStatusPending)
          .order('created_at', ascending: false)
          .limit(200);
      nextReports = reports.cast<Map<String, dynamic>>();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر جلب اقتراحات التعديل: $error'),
          ),
        );
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingDoctors = nextPending;
      _reportRows = nextReports;
      _isLoading = false;
    });
  }

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    const List<String> kDoctorCols = <String>[
      'name', 'spec', 'addr', 'area', 'ph', 'notes', 'gove',
    ];
    final Map<String, dynamic> payload = <String, dynamic>{
      for (final String k in kDoctorCols) k: request[k],
      'ph2': (request['ph2'] ?? '').toString(),
    };
    try {
      await _supabase.from(kSupabaseDoctorsTable).insert(payload);
      await _supabase
          .from(kSupabasePendingDoctorsTable)
          .delete()
          .eq('id', request['id']);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت الموافقة وإضافة العيادة إلى القائمة.')),
      );
      await _loadDashboardData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشلت الموافقة: $error')),
      );
    }
  }

  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    try {
      await _supabase
          .from(kSupabasePendingDoctorsTable)
          .delete()
          .eq('id', request['id']);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض الطلب وحذفه من الانتظار.')),
      );
      await _loadDashboardData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الحذف: $error')),
      );
    }
  }

  String _fieldForIssueType(String? type) {
    switch (type) {
      case 'wrong_phone':
        return 'ph';
      case 'wrong_address':
        return 'addr';
      case 'wrong_name_or_spec':
        return 'name';
      default:
        return 'notes';
    }
  }

  /// يحسب عدد الاقتراحات المعلّقة للطبيب ويزامن [kSupabaseReportTotalsTable].
  /// لا يرمي exception — المزامنة ثانوية ولا تعيق العملية الرئيسية.
  Future<void> _syncReportTotal(int docId) async {
    try {
      final List<dynamic> pending = await _supabase
          .from(kSupabaseReportsTable)
          .select('id')
          .eq('doctor_id', docId)
          .eq('status', kReportStatusPending);
      await _supabase.from(kSupabaseReportTotalsTable).upsert(
        <String, dynamic>{
          'doctor_id': docId,
          'report_count': pending.length,
        },
        onConflict: 'doctor_id',
      );
    } catch (e) {
      debugPrint('_syncReportTotal failed for docId=$docId: $e');
    }
  }

  Future<void> _dismissReport(Map<String, dynamic> r) async {
    final int? docId = r['doctor_id'] is int
        ? r['doctor_id'] as int
        : int.tryParse(r['doctor_id'].toString());
    try {
      await _supabase
          .from(kSupabaseReportsTable)
          .update(<String, dynamic>{'status': kReportStatusDismissed})
          .eq('id', r['id']);
      if (docId != null) {
        await _syncReportTotal(docId);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض الاقتراح.')),
      );
      await _loadDashboardData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الرفض: $error')),
      );
    }
  }

  Future<void> _applyReportCorrection(Map<String, dynamic> r) async {
    final int? docId = r['doctor_id'] is int
        ? r['doctor_id'] as int
        : int.tryParse(r['doctor_id'].toString());
    if (docId == null) {
      return;
    }

    Map<String, dynamic>? docRow;
    try {
      final List<dynamic> res = await _supabase
          .from(kSupabaseDoctorsTable)
          .select('id, name, spec, addr, ph, ph2, notes')
          .eq('id', docId)
          .limit(1);
      if (res.isNotEmpty) {
        docRow = res.first as Map<String, dynamic>;
      }
    } catch (_) {}

    if (!mounted) {
      return;
    }

    const List<String> fields = <String>[
      'ph',
      'ph2',
      'addr',
      'name',
      'spec',
      'notes',
    ];
    const Map<String, String> fieldLabels = <String, String>{
      'ph': 'رقم الهاتف (ph)',
      'ph2': 'رقم الهاتف 2 (ph2)',
      'addr': 'العنوان (addr)',
      'name': 'الاسم (name)',
      'spec': 'التخصص (spec)',
      'notes': 'ملاحظات (notes)',
    };

    String selectedField = _fieldForIssueType(r['info_issue_type']?.toString());
    final TextEditingController valueCtrl = TextEditingController(
      text: (r['suggested_correction'] ?? '').toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx2, StateSetter setSt) {
            return AlertDialog(
              title: Text('تطبيق تصحيح — رقم الطبيب: $docId'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (docRow != null) ...<Widget>[
                      const Text(
                        'البيانات الحالية:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الاسم: ${docRow['name']}\n'
                        'التخصص: ${docRow['spec']}\n'
                        'الهاتف: ${docRow['ph']}\n'
                        'العنوان: ${docRow['addr']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'نوع الخطأ: ${_infoTypeLabelAr(r['info_issue_type']?.toString())}',
                    ),
                    const SizedBox(height: 2),
                    Text('موضع الخطأ: ${r['error_location'] ?? ''}'),
                    const SizedBox(height: 2),
                    Text('التصحيح المقترح: ${r['suggested_correction'] ?? ''}'),
                    const SizedBox(height: 12),
                    const Text('الحقل المراد تعديله:'),
                    DropdownButton<String>(
                      value: selectedField,
                      isExpanded: true,
                      items: fields
                          .map(
                            (String f) => DropdownMenuItem<String>(
                              value: f,
                              child: Text(fieldLabels[f] ?? f),
                            ),
                          )
                          .toList(),
                      onChanged: (String? v) {
                        if (v != null) {
                          setSt(() => selectedField = v);
                        }
                      },
                    ),
                    if (docRow != null)
                      Text(
                        'القيمة الحالية: ${docRow[selectedField] ?? ''}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: valueCtrl,
                      decoration: const InputDecoration(
                        labelText: 'القيمة الجديدة',
                        filled: true,
                        fillColor: Color(0xFFF2F7FC),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () async {
                    final String newValue = valueCtrl.text.trim();
                    final String field = selectedField;
                    Navigator.of(ctx).pop();
                    await _commitCorrection(r, docId, field, newValue);
                  },
                  child: const Text('تأكيد التعديل'),
                ),
              ],
            );
          },
        );
      },
    );
    valueCtrl.dispose();
  }

  Future<void> _commitCorrection(
    Map<String, dynamic> r,
    int docId,
    String field,
    String newValue,
  ) async {
    try {
      await _supabase
          .from(kSupabaseDoctorsTable)
          .update(<String, dynamic>{field: newValue})
          .eq('id', docId);
      await _supabase
          .from(kSupabaseReportsTable)
          .update(<String, dynamic>{'status': kReportStatusResolved})
          .eq('id', r['id']);
      await _syncReportTotal(docId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تطبيق التصحيح وتحديث جدول الأطباء.'),
        ),
      );
      await _loadDashboardData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل التطبيق: $error')),
      );
    }
  }

  // ─── إدارة الأطباء المباشرة ───────────────────────────────────────────────

  Future<void> _searchDoctors(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchedDoctors = <Map<String, dynamic>>[];
        _doctorSearchPerformed = false;
      });
      return;
    }
    setState(() => _isSearchingDoctors = true);
    try {
      final List<dynamic> results = await _supabase
          .from(kSupabaseDoctorsTable)
          .select()
          .ilike('name', '%${query.trim()}%')
          .limit(30);
      setState(() {
        _searchedDoctors = results.cast<Map<String, dynamic>>();
        _doctorSearchPerformed = true;
        _isSearchingDoctors = false;
      });
    } catch (e) {
      setState(() => _isSearchingDoctors = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في البحث: $e')),
        );
      }
    }
  }

  Future<void> _directAddDoctor(Map<String, dynamic> data) async {
    try {
      await _supabase.from(kSupabaseDoctorsTable).insert(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت الإضافة بنجاح.')),
      );
      if (_doctorSearchController.text.isNotEmpty) {
        await _searchDoctors(_doctorSearchController.text);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشلت الإضافة: $e')));
      }
    }
  }

  Future<void> _directEditDoctor(
      dynamic docId, Map<String, dynamic> updates) async {
    try {
      await _supabase
          .from(kSupabaseDoctorsTable)
          .update(updates)
          .eq('id', docId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم التعديل بنجاح.')),
      );
      if (_doctorSearchController.text.isNotEmpty) {
        await _searchDoctors(_doctorSearchController.text);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل التعديل: $e')));
      }
    }
  }

  Future<void> _deleteDoctor(dynamic docId, String name) async {
    try {
      await _supabase.from(kSupabaseDoctorsTable).delete().eq('id', docId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تم حذف "$name".')));
      setState(() {
        _searchedDoctors
            .removeWhere((Map<String, dynamic> d) => d['id'] == docId);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل الحذف: $e')));
      }
    }
  }

  Future<void> _confirmDeleteDoctor(dynamic docId, String name) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف الطبيب "$name" نهائياً؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteDoctor(docId, name);
    }
  }

  Future<void> _showAddDoctorDialog() async {
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext ctx) => const _AddEditDoctorDialog(),
    );
    if (result != null) {
      await _directAddDoctor(result);
    }
  }

  Future<void> _showEditDoctorDialog(Map<String, dynamic> doc) async {
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext ctx) => _AddEditDoctorDialog(doc: doc),
    );
    if (result != null) {
      await _directEditDoctor(doc['id'], result);
    }
  }

  Widget _buildManageDoctorsTab() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _doctorSearchController,
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم الطبيب...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _doctorSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _doctorSearchController.clear();
                              setState(() {
                                _searchedDoctors = <Map<String, dynamic>>[];
                                _doctorSearchPerformed = false;
                              });
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: const Color(0xFFF2F7FC),
                  ),
                  onSubmitted: _searchDoctors,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _searchDoctors(_doctorSearchController.text),
                icon: const Icon(Icons.search),
                label: const Text('بحث'),
              ),
            ],
          ),
        ),
        if (_isSearchingDoctors) const LinearProgressIndicator(),
        Expanded(
          child: _doctorSearchPerformed && _searchedDoctors.isEmpty
              ? const Center(child: Text('لا توجد نتائج.'))
              : !_doctorSearchPerformed
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.manage_accounts,
                              size: 72, color: Color(0xFFBBBBBB)),
                          const SizedBox(height: 12),
                          const Text(
                            'ابحث عن طبيب بالاسم للتعديل أو الحذف',
                            style: TextStyle(color: Color(0xFF4A5568)),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _showAddDoctorDialog,
                            icon: const Icon(Icons.person_add),
                            label: const Text('إضافة طبيب مباشرة'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _searchedDoctors.length,
                      itemBuilder: (BuildContext ctx, int i) {
                        final Map<String, dynamic> doc = _searchedDoctors[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(doc['name']?.toString() ?? ''),
                            subtitle: Text(
                              '${doc['spec'] ?? ''}  •  ${doc['area'] ?? ''}  •  ${doc['gove'] ?? ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Color(0xFF42A5F5)),
                                  tooltip: 'تعديل',
                                  onPressed: () =>
                                      _showEditDoctorDialog(doc),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  tooltip: 'حذف',
                                  onPressed: () => _confirmDeleteDoctor(
                                      doc['id'],
                                      doc['name']?.toString() ?? ''),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const Color primaryMedicalBlue = Color(0xFF42A5F5);
    // فصل شجرة ويدجت شاشة الدخول عن [DefaultTabController] يمنع فشل
    // `'_dependents.isEmpty': is not true` عند التبديل من كلمة مرور → تبويبات.
    if (!_authenticated) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('لوحة الأدمن'),
          backgroundColor: primaryMedicalBlue,
          foregroundColor: Colors.white,
        ),
        body: _buildPasswordGate(),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة الأدمن'),
          backgroundColor: primaryMedicalBlue,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: <Widget>[
              Tab(icon: Icon(Icons.rate_review), text: 'اقتراحات'),
              Tab(icon: Icon(Icons.pending_actions), text: 'طلبات'),
              Tab(icon: Icon(Icons.manage_accounts), text: 'الأطباء'),
            ],
          ),
        ),
        body: _buildDashboardBody(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddDoctorDialog,
          backgroundColor: primaryMedicalBlue,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add),
          label: const Text('إضافة طبيب'),
        ),
      ),
    );
  }

  Widget _buildPasswordGate() {
    final bool passwordReady = kAdminPassword.isNotEmpty;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 24),
            if (!passwordReady)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠️  كلمة المرور غير مكوّنة.\n'
                  'محلياً: أضف ADMIN_PASSWORD في إعدادات التشغيل (.vscode/launch.json).\n'
                  'على CI: Secret باسم ADMIN_PASSWORD في GitHub Actions.',
                  style: TextStyle(color: Colors.orange, fontSize: 13),
                ),
              ),
            TextField(
              controller: _passwordController,
              obscureText: true,
              onSubmitted: (_) => _tryLogin(),
              decoration: const InputDecoration(
                labelText: 'كلمة مرور الأدمن',
                filled: true,
                fillColor: Color(0xFFF2F7FC),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _tryLogin,
                child: const Text('دخول'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _tryLogin() {
    if (kAdminPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'كلمة المرور غير مكوّنة — راجع launch.json أو GitHub Secrets (ADMIN_PASSWORD).',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    if (_normalizeAdminPassword(_passwordController.text) ==
        _normalizeAdminPassword(kAdminPassword)) {
      setState(() => _authenticated = true);
      _loadDashboardData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كلمة المرور غير صحيحة')),
      );
    }
  }


  String _infoTypeLabelAr(String? key) {
    if (key == null || key.isEmpty) {
      return '';
    }
    return kInfoCorrectionTypeLabels[key] ?? key;
  }

  Widget _buildReportRowCard(Map<String, dynamic> r) {
    final String type = _infoTypeLabelAr(r['info_issue_type']?.toString());
    final String name = (r['doctor_name'] as String?)?.trim() ?? '';
    final String namePart = name.isNotEmpty ? ' — $name' : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            isThreeLine: true,
            title: Text('id: ${r['doctor_id']}$namePart  |  $type'),
            subtitle: Text(
              'الخطأ: ${r['error_location']}\n'
              'التصحيح المقترح: ${r['suggested_correction']}\n'
              'التاريخ: ${r['created_at'] ?? ''}',
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: () => _applyReportCorrection(r),
                    child: const Text('تطبيق التصحيح'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _dismissReport(r),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('رفض'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardBody() {
    if (_isLoading) {
      return const TabBarView(
        children: <Widget>[
          Center(child: CircularProgressIndicator()),
          SizedBox.shrink(),
          SizedBox.shrink(),
        ],
      );
    }
    return TabBarView(
      children: <Widget>[
        // ── تبويب 1: اقتراحات التعديل ─────────────────────────────────────
        RefreshIndicator(
          onRefresh: _loadDashboardData,
          child: _reportRows.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: const <Widget>[
                    SizedBox(height: 80),
                    Center(
                      child: Text(
                        'لا توجد اقتراحات تعديل.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF4A5568)),
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: _reportRows.map(_buildReportRowCard).toList(),
                ),
        ),

        // ── تبويب 2: طلبات الإضافة ─────────────────────────────────────────
        RefreshIndicator(
          onRefresh: _loadDashboardData,
          child: _pendingDoctors.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: const <Widget>[
                    SizedBox(height: 80),
                    Center(
                      child: Text(
                        'لا توجد طلبات بانتظار المراجعة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF4A5568)),
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: _pendingDoctors
                      .map(
                        (Map<String, dynamic> item) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                ListTile(
                                  title: Text(
                                      (item['name'] ?? 'بدون اسم').toString()),
                                  subtitle: Text(
                                    'التخصص: ${(item['spec'] ?? '').toString()}\n'
                                    'المنطقة: ${(item['area'] ?? '').toString()}\n'
                                    'المحافظة: ${(item['gove'] ?? '').toString()}',
                                  ),
                                  isThreeLine: true,
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 8, right: 8, bottom: 8),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: () =>
                                              _approveRequest(item),
                                          child: const Text('موافق (إضافة)'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () =>
                                              _rejectRequest(item),
                                          child:
                                              const Text('غير موافق (حذف)'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),

        // ── تبويب 3: إدارة الأطباء ─────────────────────────────────────────
        _buildManageDoctorsTab(),
      ],
    );
  }
}

// ── فورم الإضافة/التعديل المشترك للأدمن (نفس حقول فورم + العامة) ────────────

class _AddEditDoctorDialog extends StatefulWidget {
  const _AddEditDoctorDialog({this.doc});
  final Map<String, dynamic>? doc;

  @override
  State<_AddEditDoctorDialog> createState() => _AddEditDoctorDialogState();
}

class _AddEditDoctorDialogState extends State<_AddEditDoctorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _physicianCustomCtrl;
  late final TextEditingController _imagingCustomCtrl;
  late final TextEditingController _areaOtherCtrl;
  late final TextEditingController _basraCustomAreaCtrl;
  late final TextEditingController _textAddrCtrl;
  late final TextEditingController _phCtrl;
  late final TextEditingController _ph2Ctrl;
  late final TextEditingController _mapsUrlCtrl;
  late final TextEditingController _notesCtrl;

  _MedicalFieldType? _medicalType;
  String? _selectedPhysicianSpec;
  bool _physicianUseCustom = false;
  String? _selectedImagingType;
  bool _imagingUseCustom = false;
  String _selectedGove = kGovernorates.first;
  String? _selectedBasraArea;
  bool _basraUseCustomArea = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _physicianCustomCtrl = TextEditingController();
    _imagingCustomCtrl = TextEditingController();
    _areaOtherCtrl = TextEditingController();
    _basraCustomAreaCtrl = TextEditingController();
    _textAddrCtrl = TextEditingController();
    _phCtrl = TextEditingController();
    _ph2Ctrl = TextEditingController();
    _mapsUrlCtrl = TextEditingController();
    _notesCtrl = TextEditingController();

    final Map<String, dynamic>? doc = widget.doc;
    if (doc != null) {
      _nameCtrl.text = doc['name']?.toString() ?? '';
      _initSpec(doc['spec']?.toString() ?? '');
      final String gove = doc['gove']?.toString() ?? kGovernorates.first;
      _selectedGove = kGovernorates.contains(gove) ? gove : kGovernorates.first;
      _initArea(doc['area']?.toString() ?? '', _selectedGove);
      final String addr = doc['addr']?.toString() ?? '';
      if (addr.startsWith('http://') || addr.startsWith('https://')) {
        _mapsUrlCtrl.text = addr;
      } else {
        _textAddrCtrl.text = addr;
      }
      _parseNotes(doc['notes']?.toString() ?? '');
      _phCtrl.text = doc['ph']?.toString() ?? '';
      _ph2Ctrl.text = doc['ph2']?.toString() ?? '';
    }
  }

  void _initSpec(String spec) {
    if (spec.isEmpty) return;
    if (spec == 'طبيب أسنان') {
      _medicalType = _MedicalFieldType.dentist;
    } else if (spec == 'صيدلية') {
      _medicalType = _MedicalFieldType.pharmacy;
    } else if (spec == 'مختبر') {
      _medicalType = _MedicalFieldType.lab;
    } else if (kImagingModalityOptions.contains(spec)) {
      _medicalType = _MedicalFieldType.radiology;
      _selectedImagingType = spec;
    } else if (kPhysicianSpecializations.contains(spec)) {
      _medicalType = _MedicalFieldType.physician;
      _selectedPhysicianSpec = spec;
    } else {
      _medicalType = _MedicalFieldType.physician;
      _physicianUseCustom = true;
      _selectedPhysicianSpec = kDropdownAddCustom;
      _physicianCustomCtrl.text = spec;
    }
  }

  void _initArea(String area, String gove) {
    if (gove == 'البصرة') {
      if (kBasraAreas.contains(area)) {
        _selectedBasraArea = area;
      } else if (area.isNotEmpty) {
        _basraUseCustomArea = true;
        _selectedBasraArea = kDropdownAddCustom;
        _basraCustomAreaCtrl.text = area;
      }
    } else {
      _areaOtherCtrl.text = area;
    }
  }

  void _parseNotes(String raw) {
    final RegExpMatch? m = RegExp(
      r'^العنوان: (.*?)\n\nملاحظات: (.*)',
      dotAll: true,
    ).firstMatch(raw);
    if (m != null) {
      if (_textAddrCtrl.text.isEmpty) _textAddrCtrl.text = m.group(1) ?? '';
      _notesCtrl.text = m.group(2) ?? '';
    } else {
      _notesCtrl.text = raw;
    }
  }

  String _buildSpec() {
    switch (_medicalType) {
      case _MedicalFieldType.physician:
        return _physicianUseCustom
            ? _physicianCustomCtrl.text.trim()
            : _selectedPhysicianSpec ?? '';
      case _MedicalFieldType.radiology:
        return _imagingUseCustom
            ? _imagingCustomCtrl.text.trim()
            : _selectedImagingType ?? '';
      case _MedicalFieldType.dentist:
        return 'طبيب أسنان';
      case _MedicalFieldType.pharmacy:
        return 'صيدلية';
      case _MedicalFieldType.lab:
        return 'مختبر';
      case null:
        return '';
    }
  }

  String _buildArea() {
    if (_selectedGove == 'البصرة') {
      return _basraUseCustomArea
          ? _basraCustomAreaCtrl.text.trim()
          : _selectedBasraArea ?? '';
    }
    return _areaOtherCtrl.text.trim();
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF2F7FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _medTile(String title, _MedicalFieldType type) {
    final bool sel = _medicalType == type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: sel ? const Color(0xFFE3F2FD) : const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          onTap: () => setState(() {
            _medicalType = type;
            _selectedPhysicianSpec = null;
            _selectedImagingType = null;
            _physicianUseCustom = false;
            _imagingUseCustom = false;
          }),
          leading: Icon(
            sel
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color:
                sel ? const Color(0xFF1976D2) : const Color(0xFF94A3B8),
          ),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _physicianCustomCtrl.dispose();
    _imagingCustomCtrl.dispose();
    _areaOtherCtrl.dispose();
    _basraCustomAreaCtrl.dispose();
    _textAddrCtrl.dispose();
    _phCtrl.dispose();
    _ph2Ctrl.dispose();
    _mapsUrlCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.doc != null;
    return AlertDialog(
      title: Text(isEdit
          ? 'تعديل: ${widget.doc!['name'] ?? ''}'
          : 'إضافة طبيب / عيادة'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ── الاسم ───────────────────────────────────────────────────────
              TextField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                decoration: _dec('اسم الطبيب / المركز *'),
              ),
              const SizedBox(height: 12),
              // ── المجال الطبي ─────────────────────────────────────────────────
              const Text('المجال الطبي *',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF475569))),
              const SizedBox(height: 6),
              _medTile('طبيب', _MedicalFieldType.physician),
              _medTile('اشعة وسونار', _MedicalFieldType.radiology),
              _medTile('طبيب أسنان', _MedicalFieldType.dentist),
              _medTile('صيدلية', _MedicalFieldType.pharmacy),
              _medTile('مختبر', _MedicalFieldType.lab),
              // ── تخصص الطبيب ─────────────────────────────────────────────────
              if (_medicalType == _MedicalFieldType.physician) ...<Widget>[
                const SizedBox(height: 10),
                const Text('التخصص *',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                      'phys_${_physicianUseCustom}_$_selectedPhysicianSpec'),
                  initialValue: _physicianUseCustom
                      ? kDropdownAddCustom
                      : _selectedPhysicianSpec,
                  isExpanded: true,
                  decoration: _dec('اختر التخصص'),
                  items: <DropdownMenuItem<String>>[
                    ...kPhysicianSpecializations.map((String s) =>
                        DropdownMenuItem<String>(
                            value: s, child: Text(s))),
                    const DropdownMenuItem<String>(
                        value: kDropdownAddCustom,
                        child: Text('إضافة تخصص جديد')),
                  ],
                  onChanged: (String? v) {
                    if (v == null) return;
                    setState(() {
                      if (v == kDropdownAddCustom) {
                        _physicianUseCustom = true;
                        _selectedPhysicianSpec = kDropdownAddCustom;
                      } else {
                        _physicianUseCustom = false;
                        _selectedPhysicianSpec = v;
                      }
                    });
                  },
                ),
                if (_physicianUseCustom) ...<Widget>[
                  const SizedBox(height: 8),
                  TextField(
                      controller: _physicianCustomCtrl,
                      decoration: _dec('اكتب التخصص الجديد *')),
                ],
              ],
              // ── نوع الاشعة ───────────────────────────────────────────────────
              if (_medicalType == _MedicalFieldType.radiology) ...<Widget>[
                const SizedBox(height: 10),
                const Text('نوع الاشعة *',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                      'img_${_imagingUseCustom}_$_selectedImagingType'),
                  initialValue: _imagingUseCustom
                      ? kDropdownAddCustom
                      : _selectedImagingType,
                  isExpanded: true,
                  decoration: _dec('اختر النوع'),
                  items: <DropdownMenuItem<String>>[
                    ...kImagingModalityOptions.map((String s) =>
                        DropdownMenuItem<String>(
                            value: s, child: Text(s))),
                    const DropdownMenuItem<String>(
                        value: kDropdownAddCustom,
                        child: Text('إضافة نوع جديد')),
                  ],
                  onChanged: (String? v) {
                    if (v == null) return;
                    setState(() {
                      if (v == kDropdownAddCustom) {
                        _imagingUseCustom = true;
                        _selectedImagingType = kDropdownAddCustom;
                      } else {
                        _imagingUseCustom = false;
                        _selectedImagingType = v;
                      }
                    });
                  },
                ),
                if (_imagingUseCustom) ...<Widget>[
                  const SizedBox(height: 8),
                  TextField(
                      controller: _imagingCustomCtrl,
                      decoration: _dec('اكتب النوع الجديد *')),
                ],
              ],
              const SizedBox(height: 12),
              // ── المحافظة ─────────────────────────────────────────────────────
              DropdownButtonFormField<String>(
                key: ValueKey<String>(_selectedGove),
                initialValue: _selectedGove,
                isExpanded: true,
                decoration: _dec('المحافظة *'),
                items: kGovernorates
                    .map((String g) => DropdownMenuItem<String>(
                        value: g, child: Text(g)))
                    .toList(),
                onChanged: (String? v) {
                  if (v == null) return;
                  setState(() {
                    _selectedGove = v;
                    if (v != 'البصرة') {
                      _selectedBasraArea = null;
                      _basraUseCustomArea = false;
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              // ── المنطقة ──────────────────────────────────────────────────────
              if (_selectedGove == 'البصرة') ...<Widget>[
                const Text('المنطقة *',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                      'bs_${_basraUseCustomArea}_$_selectedBasraArea'),
                  initialValue: _basraUseCustomArea
                      ? kDropdownAddCustom
                      : _selectedBasraArea,
                  isExpanded: true,
                  decoration: _dec('اختر المنطقة'),
                  items: <DropdownMenuItem<String>>[
                    ...kBasraAreas.map((String a) =>
                        DropdownMenuItem<String>(
                            value: a, child: Text(a))),
                    const DropdownMenuItem<String>(
                        value: kDropdownAddCustom,
                        child: Text('إضافة منطقة جديدة')),
                  ],
                  onChanged: (String? v) {
                    if (v == null) return;
                    setState(() {
                      if (v == kDropdownAddCustom) {
                        _basraUseCustomArea = true;
                        _selectedBasraArea = kDropdownAddCustom;
                      } else {
                        _basraUseCustomArea = false;
                        _selectedBasraArea = v;
                      }
                    });
                  },
                ),
                if (_basraUseCustomArea) ...<Widget>[
                  const SizedBox(height: 8),
                  TextField(
                      controller: _basraCustomAreaCtrl,
                      decoration: _dec('اسم المنطقة *')),
                ],
              ] else
                TextField(
                    controller: _areaOtherCtrl,
                    decoration: _dec('المنطقة *')),
              const SizedBox(height: 8),
              // ── عنوان نصي ────────────────────────────────────────────────────
              TextField(
                controller: _textAddrCtrl,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.next,
                decoration: _dec('عنوان العيادة (نص) *'),
              ),
              const SizedBox(height: 8),
              // ── الهاتف ───────────────────────────────────────────────────────
              TextField(
                controller: _phCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: _dec('رقم الهاتف *'),
              ),
              const SizedBox(height: 8),
              // ── الهاتف الثاني ────────────────────────────────────────────────
              TextField(
                controller: _ph2Ctrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: _dec('الهاتف الثاني (اختياري)'),
              ),
              const SizedBox(height: 8),
              // ── رابط الخرائط ─────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _mapsUrlCtrl,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      decoration: _dec('رابط خرائط Google (اختياري)')
                          .copyWith(
                              prefixIcon:
                                  const Icon(Icons.map_outlined)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'افتح الخريطة',
                    icon: const Icon(Icons.open_in_new,
                        color: Color(0xFF42A5F5)),
                    onPressed: () async {
                      final String url = _mapsUrlCtrl.text.trim();
                      if (url.isNotEmpty) {
                        await launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ── ملاحظات ──────────────────────────────────────────────────────
              TextField(
                controller: _notesCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: _dec('ملاحظات *'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final String name = _nameCtrl.text.trim();
            final String textAddr = _textAddrCtrl.text.trim();
            final String ph = _phCtrl.text.trim();
            final String notes = _notesCtrl.text.trim();
            final String area = _buildArea();

            String? error;
            if (name.length < 2) {
              error = 'أدخل اسم الطبيب أو المركز';
            } else if (_medicalType == null) {
              error = 'اختر المجال الطبي';
            } else if (_medicalType == _MedicalFieldType.physician &&
                !_physicianUseCustom &&
                _selectedPhysicianSpec == null) {
              error = 'اختر التخصص';
            } else if (_medicalType == _MedicalFieldType.physician &&
                _physicianUseCustom &&
                _physicianCustomCtrl.text.trim().length < 2) {
              error = 'أدخل التخصص';
            } else if (_medicalType == _MedicalFieldType.radiology &&
                !_imagingUseCustom &&
                _selectedImagingType == null) {
              error = 'اختر نوع الاشعة';
            } else if (_medicalType == _MedicalFieldType.radiology &&
                _imagingUseCustom &&
                _imagingCustomCtrl.text.trim().length < 2) {
              error = 'أدخل نوع الاشعة';
            } else if (area.length < 2) {
              error = 'أدخل المنطقة';
            } else if (textAddr.length < 3) {
              error = 'أدخل عنوان العيادة';
            } else if (ph.length < 6) {
              error = 'أدخل رقم الهاتف';
            } else if (notes.length < 3) {
              error = 'أدخل الملاحظات';
            } else {
              final String maps = _mapsUrlCtrl.text.trim();
              if (maps.isNotEmpty &&
                  !maps.startsWith('http://') &&
                  !maps.startsWith('https://')) {
                error = 'رابط الخرائط غير صحيح';
              }
            }

            if (error != null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(error)));
              return;
            }

            final String mapsUrl = _mapsUrlCtrl.text.trim();
            Navigator.of(context).pop(<String, dynamic>{
              'name': name,
              'spec': _buildSpec(),
              'gove': _selectedGove,
              'area': area,
              'addr': mapsUrl.isNotEmpty ? mapsUrl : textAddr,
              'ph': ph,
              'ph2': _ph2Ctrl.text.trim(),
              'notes': 'العنوان: $textAddr\n\nملاحظات: $notes',
            });
          },
          child: Text(isEdit ? 'حفظ التعديل' : 'إضافة'),
        ),
      ],
    );
  }
}

class _SpecVisual {
  const _SpecVisual({
    required this.gradientColors,
    required this.faIcon,
  });

  final List<Color> gradientColors;
  final IconData faIcon;

  static _SpecVisual forSpecialization(String spec) {
    final String s = spec.toLowerCase().trim();

    bool has(String a, String b) => s.contains(a) || s.contains(b);

    if (_matchesToothIconOnly(spec)) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF26C6DA), Color(0xFF00838F)],
        faIcon: FontAwesomeIcons.tooth,
      );
    }
    if ((has('orthodont', 'تقويم') || has('فم', 'oral')) &&
        !_matchesToothIconOnly(spec)) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF4DD0E1), Color(0xFF006064)],
        faIcon: FontAwesomeIcons.userDoctor,
      );
    }
    if (has('قلب', 'cardio') || has('قسطرة', 'angio')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFFEF5350), Color(0xFFC62828)],
        faIcon: FontAwesomeIcons.heartPulse,
      );
    }
    if (has('عيون', 'ophthal') || has('بصريات', 'optom')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF42A5F5), Color(0xFF1565C0)],
        faIcon: FontAwesomeIcons.eye,
      );
    }
    if (has('أنف', 'ent') ||
        has('أذن', 'hns') ||
        has('حنجرة', 'laryng')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF7E57C2), Color(0xFF4527A0)],
        faIcon: FontAwesomeIcons.earListen,
      );
    }
    if (has('مخ', 'neuro') || has('أعصاب', 'nerve')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFFAB47BC), Color(0xFF6A1B9A)],
        faIcon: FontAwesomeIcons.brain,
      );
    }
    if (has('عظام', 'ortho') || has('مفاصل', 'joint')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFFFFB74D), Color(0xFFEF6C00)],
        faIcon: FontAwesomeIcons.bone,
      );
    }
    if (has('أطفال', 'pediat') || has('حديثي الولادة', 'neonat')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF66BB6A), Color(0xFF2E7D32)],
        faIcon: FontAwesomeIcons.baby,
      );
    }
    if (has('نساء', 'gyn') ||
        has('توليد', 'obstet') ||
        has('ولادة', 'matern')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFFEC407A), Color(0xFFAD1457)],
        faIcon: FontAwesomeIcons.personPregnant,
      );
    }
    if (has('جلد', 'derma')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF29B6F6), Color(0xFF0277BD)],
        faIcon: FontAwesomeIcons.handSparkles,
      );
    }
    if (has('صدر', 'chest') || has('رئة', 'pulm')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF4FC3F7), Color(0xFF0277BD)],
        faIcon: FontAwesomeIcons.lungs,
      );
    }
    if (has('كلى', 'nephro') || has('مسالك', 'urolog')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF5C6BC0), Color(0xFF283593)],
        faIcon: FontAwesomeIcons.handHoldingMedical,
      );
    }
    if (has('باطن', 'intern') || has('سكر', 'diabet') || has('غدد', 'endocr')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF26A69A), Color(0xFF00695C)],
        faIcon: FontAwesomeIcons.notesMedical,
      );
    }
    if (has('جراح', 'surg') || has('عمليات', 'operation')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF78909C), Color(0xFF37474F)],
        faIcon: FontAwesomeIcons.userDoctor,
      );
    }
    if (has('تخدير', 'anesth')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF8D6E63), Color(0xFF4E342E)],
        faIcon: FontAwesomeIcons.syringe,
      );
    }
    if (has('نفس', 'psych') || has('عقلي', 'mental')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF9575CD), Color(0xFF4527A0)],
        faIcon: FontAwesomeIcons.brain,
      );
    }

    return const _SpecVisual(
      gradientColors: <Color>[Color(0xFF64B5F6), Color(0xFF1E88E5)],
      faIcon: FontAwesomeIcons.userDoctor,
    );
  }

  /// أيقونة السن فقط عند وجود «أسنان»/إنجليزي dental، وليس لتسمية «طب الأسنان» العامة.
  static bool _matchesToothIconOnly(String spec) {
    final String t = spec.trim();
    final String lower = t.toLowerCase();
    if (lower.contains('طب الاسنان') || lower.contains('طب الأسنان')) {
      return false;
    }
    if (lower.contains('أسنان') || lower.contains('اسنان')) {
      return true;
    }
    if (lower.contains('dental') || lower.contains('dentist')) {
      return true;
    }
    return false;
  }
}

class Doctor {
  const Doctor({
    required this.id,
    required this.spec,
    required this.name,
    required this.addr,
    required this.area,
    required this.ph,
    required this.ph2,
    required this.notes,
  });

  final int id;
  final String spec;
  final String name;
  final String addr;
  final String area;
  final String ph;
  final String ph2;
  final String notes;

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(
      id: json['id'] is int ? json['id'] as int : 0,
      spec: (json['spec'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      addr: (json['addr'] ?? '').toString(),
      area: (json['area'] ?? '').toString(),
      ph: (json['ph'] ?? '').toString(),
      ph2: (json['ph2'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
    );
  }
}