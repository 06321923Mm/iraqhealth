import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'analytics_service.dart';
import 'app_navigation.dart';
import 'auth/auth_gate.dart';
import 'doctor_constants.dart';
import 'doctor_dashboard/my_clinic_screen.dart';
import 'core/auth/admin_session.dart';
import 'core/config/app_endpoints.dart';
import 'env/app_env.dart';
import 'data/doctor_coordinates.dart';
import 'doctor_location_repository.dart';
import 'doctor_model.dart';
import 'location_picker_screen.dart';
import 'medical_field.dart';
import 'widgets/doctor_map_location_field.dart';
import 'widgets/medical_category_selector.dart';
import 'arabic_search_normalize.dart';
import 'favorites_provider.dart';
import 'search_suggestions.dart';
import 'firebase_options.dart';
import 'pwa_install_stub.dart'
    if (dart.library.js) 'pwa_install_web.dart';
import 'supabase_write_errors.dart';
import 'edit_suggestion/edit_suggestion_schema_service.dart';
import 'edit_suggestion/schema_models.dart';
import 'widgets/doctor_list_skeleton.dart';
import 'widgets/dynamic_edit_suggestion_form.dart';
import 'features/admin/presentation/layouts/admin_layout.dart';
import 'services/auth_service.dart';
import 'services/fcm_token_service.dart';
import 'core/cache/connectivity_service.dart';
import 'core/cache/hive_cache_service.dart';
import 'core/cache/sp_doctors_cache.dart';
import 'services/crashlytics_service.dart';

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

bool get _canBypassAdminPasswordInDebug => kDebugMode && kAdminPassword.isEmpty;

/// Allowed `public.reports.status` values — must match `reports_status_check`
/// constraint and RLS policies in Supabase migrations.
const String kReportStatusPending = 'pending';
const String kReportStatusReviewed = 'reviewed';
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
const String kSupabaseClinicClaimRequestsTable = 'clinic_claim_requests';
const String kSupabaseDoctorsTable = 'doctors';

/// أعمدة doctors المسموح للـ anon بتحديثها (مُطابِقة لـ GRANT في Supabase).
/// تُستخدم للتحقق قبل «الموافقة السريعة» على اقتراحات التعديل.
const Set<String> kAdminUpdatableDoctorColumns = <String>{
  'name',
  'spec',
  'addr',
  'ph',
  'ph2',
  'notes',
  'area',
  'gove',
  'latitude',
  'longitude',
};

// مفاتيح لعمود public.reports.info_issue_type
const Map<String, String> kInfoCorrectionTypeLabels = <String, String>{
  'wrong_phone': 'رقم الهاتف',
  'wrong_address': 'نص العنوان',
  'wrong_map_location': 'موقع العيادة على الخريطة',
  'wrong_name_or_spec': 'الاسم أو التخصص',
  'other': 'معلومة أخرى',
};

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppEnv.loadAppEnv();

  if (!kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    final PackageInfo pkgInfo = await PackageInfo.fromPlatform();
    CrashlyticsService.instance.setAppContext(
      version: pkgInfo.version,
      build: pkgInfo.buildNumber,
    );
    FlutterError.onError = (FlutterErrorDetails details) {
      CrashlyticsService.instance.logError(
        details.exception,
        details.stack,
        reason: 'flutter_framework_error',
        fatal: false,
      );
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      CrashlyticsService.instance.logError(error, stack, fatal: true);
      return true;
    };
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance.requestPermission();
  }

  // يُقرأ عنوان المشروع والمفتاح العام من AppEnv (assets/env/flutter.env أو --dart-define).
  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    anonKey: AppEnv.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  await HiveCacheService.init();

  runApp(
    ChangeNotifierProvider<FavoritesProvider>(
      create: (_) => FavoritesProvider(),
      child: const IraqHealthApp(),
    ),
  );
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
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
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
        if (settings.name == '/add-clinic') {
          return buildAdaptiveRtlRoute<Object?>(const AddClinicPage());
        }
        if (settings.name == '/report') {
          return buildAdaptiveRtlRoute<Object?>(const ReportPage());
        }
        if (settings.name == '/admin') {
          final User? guardUser = Supabase.instance.client.auth.currentUser;
          if (guardUser == null) {
            return buildAdaptiveRtlRoute<Object?>(const AuthGate());
          }
          if (!sessionUserIsAdmin(guardUser)) {
            return buildAdaptiveRtlRoute<Object?>(
              const Directionality(
                textDirection: TextDirection.rtl,
                child: IraqHealthHomePage(),
              ),
            );
          }
          return buildAdaptiveRtlRoute<Object?>(const AdminHubPage());
        }
        return null;
      },
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: AuthGate(),
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
  bool _isCachedData = false;
  String? _cacheTimestamp;

  bool _showOfflineBanner = false;
  bool _showRetryButton = false;
  DateTime? _lastSyncTime;
  bool _isRefreshing = false;

  List<Doctor> _allDoctors = <Doctor>[];
  List<Doctor> _filteredDoctors = <Doctor>[];
  List<String> _areas = <String>[];
  List<String> _specializations = <String>[];
  int _adminTapCounter = 0;
  Timer? _adminTapResetTimer;

  /// 0: الرئيسية، 1: أطبائي (المفضلة).
  int _homeNavIndex = 0;
  Timer? _suggestionDebounceTimer;
  Timer? _searchAnalyticsDebounceTimer;
  StreamSubscription<AuthState>? _authStateSub;
  StreamSubscription<bool>? _connectivitySub;
  List<SearchSuggestionRow> _searchSuggestions = <SearchSuggestionRow>[];

  static const List<String> _kPopularSearchSpecs = <String>[
    'القلبية',
    'اختصاص الأطفال',
    'الاشعة والسونار',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    // Rebuild when auth state flips so the "عيادتي" tab and admin-only
    // map controls appear / disappear immediately on login or logout.
    _authStateSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (AuthState _) {
        if (mounted) setState(() {});
      },
    );
    _connectivitySub = ConnectivityService.onlineStream().listen((bool online) {
      CrashlyticsService.instance.setNetworkState(online);
      if (online && _showOfflineBanner && mounted) {
        setState(() => _showOfflineBanner = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _showDisclaimerIfNeeded();
      if (mounted) _checkForUpdate();
    });
    _loadDoctors();
    // Register FCM token for push notifications (fire-and-forget, non-fatal).
    FcmTokenService.register().ignore();
  }

  Future<void> _checkForUpdate() async {
    if (kIsWeb) return;
    try {
      final http.Response response = await http
          .get(Uri.parse('https://iraqhealth.net/version.json'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || !mounted) return;

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final int remoteCode = (data['versionCode'] as num).toInt();
      final String remoteUrl = data['url'] as String;
      final String remoteName = data['versionName'] as String;

      final PackageInfo info = await PackageInfo.fromPlatform();
      final int localCode = int.tryParse(info.buildNumber) ?? 0;

      if (remoteCode <= localCode || !mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تحديث متاح'),
            content: Text('يوجد إصدار جديد ($remoteName) من المدار الطبي.\nيُنصح بالتحديث للحصول على أحدث البيانات والميزات.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('لاحقاً'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final Uri uri = Uri.parse(remoteUrl);
                  if (await canLaunchUrl(uri)) launchUrl(uri);
                },
                child: const Text('تحديث الآن'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {}
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
    final String gove = _selectedGovernorate ?? 'البصرة';
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isCachedData = false;
      _cacheTimestamp = null;
      _showOfflineBanner = false;
      _showRetryButton = false;
      _allDoctors = <Doctor>[];
      _filteredDoctors = <Doctor>[];
      _areas = <String>[];
      _specializations = <String>[];
    });

    // 1. Cache-first: serve from SpDoctorsCache immediately (no spinner).
    final List<Map<String, dynamic>>? cached = await SpDoctorsCache.load(gove);
    if (cached != null && cached.isNotEmpty) {
      if (!mounted) return;
      _allDoctors = cached
          .map((Map<String, dynamic> json) => Doctor.fromJson(json))
          .toList();
      _rebuildFiltersFromAllDoctors(gove);
      _applyFilters();
      setState(() => _isLoading = false);
    }

    // 2. Always trigger a background network refresh, whether cache hit or not.
    unawaited(_backgroundRefresh(gove, forceRefresh: true));
  }

  Future<void> _backgroundRefresh(
    String gove, {
    bool forceRefresh = false,
  }) async {
    if (_isRefreshing && !forceRefresh) return;
    if (mounted) setState(() => _isRefreshing = true);

    try {
      final bool online = await ConnectivityService.isOnline();

      if (!online) {
        if (!mounted) return;
        if (_allDoctors.isEmpty) {
          setState(() {
            _showRetryButton = true;
            _isLoading = false;
          });
        } else {
          setState(() => _showOfflineBanner = true);
        }
        return;
      }

      // Online: prefer keyset RPC, fall back to range pagination.
      List<dynamic> allData = <dynamic>[];
      try {
        allData = await _fetchDoctorsViaKeysetRpc(gove);
      } catch (keysetErr, keysetSt) {
        debugPrint(
          'Keyset RPC unavailable (${AppEndpoints.getDoctorsPageKeyset}), '
          'using range fallback: $keysetErr',
        );
        debugPrint('$keysetSt');
        allData = await _fetchDoctorsViaRange(gove);
      }

      final List<Doctor> doctors = allData
          .map((dynamic json) => Doctor.fromJson(json as Map<String, dynamic>))
          .toList();

      if (!mounted) return;

      if (doctors.isNotEmpty) {
        unawaited(
          SpDoctorsCache.save(gove, allData.cast<Map<String, dynamic>>()),
        );
      }

      setState(() {
        _allDoctors = doctors;
        _lastSyncTime = DateTime.now();
        _showOfflineBanner = false;
        _showRetryButton = false;
        _isLoading = false;
        _errorMessage = null;
      });
      _rebuildFiltersFromAllDoctors(gove);
      _applyFilters();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('آخر تحديث: الآن'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('_backgroundRefresh error: $error');
      debugPrint('$stackTrace');
      CrashlyticsService.instance.logApiFailure(
        AppEndpoints.getDoctorsPageKeyset,
        error,
        stackTrace,
      );
      if (!mounted) return;
      // Only surface errors when there's nothing cached to show.
      if (_allDoctors.isEmpty) {
        setState(() {
          _errorMessage = _humanReadableLoadError(error);
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  /// Builds [_areas] and [_specializations] from the current [_allDoctors] list.
  /// Called from both the online fetch path and the offline cache path.
  void _rebuildFiltersFromAllDoctors(String gove) {
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
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    _specializations = specCounts.keys.toList()
      ..sort((String a, String b) {
        final int ca = specCounts[a] ?? 0;
        final int cb = specCounts[b] ?? 0;
        final int byCount = cb.compareTo(ca);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    _moveIraqiDentalPracticeLabelToSixth(_specializations);
    if (_selectedArea != null && !_areas.contains(_selectedArea)) {
      _selectedArea = null;
    }
    if (_selectedSpecialization != null &&
        !_specializations.contains(_selectedSpecialization)) {
      _selectedSpecialization = null;
    }
  }

  static const String _kDoctorListSelectMinimal =
      'id, spec, name, addr, area, ph, ph2, notes, gove, latitude, longitude';

  /// Keyset pages via Supabase RPC (requires migration `get_doctors_page_keyset`).
  Future<List<dynamic>> _fetchDoctorsViaKeysetRpc(String gove) async {
    final List<dynamic> allData = <dynamic>[];
    int lastId = 0;
    while (true) {
      final dynamic raw = await _supabase.rpc(
        AppEndpoints.getDoctorsPageKeyset,
        params: <String, dynamic>{
          'p_gove': gove,
          'p_limit': _batchSize,
          'p_last_id': lastId,
        },
      );
      final List<dynamic> response = raw is List ? raw : <dynamic>[];

      if (response.isEmpty) {
        break;
      }
      allData.addAll(response);
      if (response.length < _batchSize) {
        break;
      }
      final dynamic lastRaw =
          (response.last as Map<String, dynamic>)['id'];
      final int? nextId = lastRaw is int
          ? lastRaw
          : int.tryParse(lastRaw?.toString() ?? '');
      if (nextId == null || nextId <= lastId) {
        break;
      }
      lastId = nextId;
    }
    return allData;
  }

  /// Legacy offset/range pagination — works without the keyset RPC.
  Future<List<dynamic>> _fetchDoctorsViaRange(String gove) async {
    final List<dynamic> allData = <dynamic>[];
    int from = 0;
    while (true) {
      final List<dynamic> response = await _supabase
          .from(kSupabaseDoctorsTable)
          .select(_kDoctorListSelectMinimal)
          .eq('gove', gove)
          .order('id', ascending: true)
          .range(from, from + _batchSize - 1);
      allData.addAll(response);
      if (response.length < _batchSize) {
        break;
      }
      from += _batchSize;
    }
    return allData;
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

  String _formatSyncAge(DateTime t) {
    final int minutes = DateTime.now().difference(t).inMinutes;
    if (minutes < 1) return 'الآن';
    if (minutes < 60) return '$minutes دقيقة';
    final int hours = DateTime.now().difference(t).inHours;
    return '$hours ساعة';
  }

  Widget _buildOfflineRetryView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 64, color: Color(0xFFB0BEC5)),
            const SizedBox(height: 16),
            const Text(
              'لا يوجد اتصال بالإنترنت',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D3557),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDoctors,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _upsertReportCount(int doctorId) async {
    try {
      final EditSuggestionSchemaService svc =
          EditSuggestionSchemaService(_supabase);
      final EditSuggestionSchemaBundle b = await svc.loadBundle();
      final String fkCol = b.primaryTarget?.fkColumn.isNotEmpty == true
          ? b.primaryTarget!.fkColumn
          : 'doctor_id';
      final String repTbl =
          b.ok && b.reportsTable.isNotEmpty ? b.reportsTable : kSupabaseReportsTable;
      final List<dynamic> pending = await _supabase
          .from(repTbl)
          .select('id')
          .eq(fkCol, doctorId)
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

  void _onSearchTextChanged() {
    _applyFilters();
    _searchAnalyticsDebounceTimer?.cancel();
    _searchAnalyticsDebounceTimer =
        Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) {
        return;
      }
      final String q = _searchController.text.trim();
      if (q.length >= 2) {
        unawaited(AnalyticsService.instance.logSearchUsed(q));
      }
    });
    _suggestionDebounceTimer?.cancel();
    _suggestionDebounceTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _searchSuggestions = computeLocalSearchSuggestions(
          query: _searchController.text,
          doctorNames: _allDoctors.map((Doctor d) => d.name).toList(),
          areas: _areas,
          specializations: _specializations,
        );
      });
    });
  }

  void _onSearchFocusChanged() {
    if (!_searchFocusNode.hasFocus) {
      setState(() => _searchSuggestions = <SearchSuggestionRow>[]);
    }
  }

  void _applySuggestionRow(SearchSuggestionRow row) {
    _searchAnalyticsDebounceTimer?.cancel();
    unawaited(AnalyticsService.instance.logSearchUsed(row.label));
    _searchController.text = row.label;
    _searchController.selection =
        TextSelection.collapsed(offset: row.label.length);
    setState(() => _searchSuggestions = <SearchSuggestionRow>[]);
    _applyFilters();
  }

  void _resetSearchAndFilters() {
    unawaited(AnalyticsService.instance.logFilterUsed('reset'));
    setState(() {
      _searchController.clear();
      _selectedArea = null;
      _selectedSpecialization = null;
      _searchSuggestions = <SearchSuggestionRow>[];
    });
    _applyFilters();
  }

  void _applyPopularSpecChip(String specLabel) {
    unawaited(
      AnalyticsService.instance
          .logFilterUsed('popular_spec', value: specLabel),
    );
    setState(() {
      _selectedSpecialization = specLabel;
      _searchController.clear();
      _searchSuggestions = <SearchSuggestionRow>[];
    });
    _applyFilters();
  }

  void _applyFilters() {
    final List<String> searchTokens = arabicSearchTokens(_searchController.text);

    final List<Doctor> results = _allDoctors.where((Doctor doctor) {
      // نُطبّق trim() دفاعياً تحسّباً لأي بيانات مستقبلية بفراغات زائدة، وذلك
      // ليتطابق العرض في الـchips (الذي يستخدم القيم المقصوصة) مع نتيجة الفلتر.
      final String docArea = doctor.area.trim();
      final String docSpec = doctor.spec.trim();
      final bool matchesArea =
          _selectedArea == null || docArea == _selectedArea;
      final bool matchesSpecialization =
          _selectedSpecialization == null || docSpec == _selectedSpecialization;
      final String normName = normalizeArabic(doctor.name);
      final String normSpec = normalizeArabic(docSpec);
      final String normArea = normalizeArabic(docArea);
      final String normAddr = normalizeArabic(doctor.addr.trim());
      final bool matchesSearch = searchTokens.isEmpty ||
          searchTokens.every(
            (String t) =>
                normName.contains(t) ||
                normSpec.contains(t) ||
                normArea.contains(t) ||
                normAddr.contains(t),
          );

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
    // يطابق التسميات العامة لطب الأسنان كما تظهر في قاعدة البيانات حالياً
    // (مثل «طب وتجميل الاسنان») وكذلك الصيغ الكلاسيكية «طب الأسنان».
    return normalized.contains('الاسنان') ||
        normalized.contains('الأسنان');
  }

  Future<void> _openDialer(
    String phoneNumber, {
    String doctorName = '',
  }) async {
    final String cleaned = _normalizePhone(phoneNumber);
    if (cleaned.isEmpty) {
      return;
    }
    if (doctorName.isNotEmpty) {
      unawaited(AnalyticsService.instance.logCallClicked(doctorName));
    }
    final Uri uri = Uri.parse('tel:$cleaned');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWhatsApp(
    String phoneNumber, {
    String doctorName = '',
  }) async {
    final String cleaned = _normalizePhone(phoneNumber);
    if (cleaned.isEmpty) {
      return;
    }
    if (doctorName.isNotEmpty) {
      unawaited(AnalyticsService.instance.logWhatsappClicked(doctorName));
    }
    final String withoutLeadingZero =
        cleaned.startsWith('0') ? cleaned.substring(1) : cleaned;
    final Uri uri = Uri.parse('https://wa.me/964$withoutLeadingZero');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openMap(
    String address, {
    String locationDetail = '',
  }) async {
    if (address.trim().isEmpty) {
      return;
    }
    if (!kIsWeb) {
      unawaited(
        AnalyticsService.instance.logLocationUsed(
          'address_text',
          detail: locationDetail,
        ),
      );
    }
    final String value = address.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return;
    }
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(value)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openGoogleMapsLatLng(
    double lat,
    double lng, {
    String locationDetail = '',
  }) async {
    if (!kIsWeb) {
      unawaited(
        AnalyticsService.instance.logLocationUsed(
          'coordinates',
          detail: locationDetail,
        ),
      );
    }
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _handleAdminTitleTap() async {
    _adminTapResetTimer?.cancel();
    _adminTapResetTimer = Timer(const Duration(seconds: 3), () {
      _adminTapCounter = 0;
    });
    _adminTapCounter += 1;
    if (_adminTapCounter < 4) {
      return;
    }
    _adminTapCounter = 0;
    _adminTapResetTimer?.cancel();
    if (kAdminPassword.isEmpty) {
      if (_canBypassAdminPasswordInDebug) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'وضع التطوير: تم فتح لوحة الأدمن بدون كلمة مرور (ADMIN_PASSWORD غير مكوّنة).',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pushNamed(context, '/admin', arguments: true);
        return;
      }
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
    final String displayName =
        doctor.name.isNotEmpty ? doctor.name : 'غير معروف';
    unawaited(
      AnalyticsService.instance.logDoctorOpened(displayName, doctor.spec),
    );
    final String primaryPhone =
        doctor.ph.trim().isNotEmpty ? doctor.ph.trim() : doctor.ph2.trim();
    final List<Doctor> docHolder = <Doctor>[doctor];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext bctx, void Function(void Function()) setModal) {
            final Doctor d = docHolder[0];
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 8,
                  bottom: MediaQuery.paddingOf(bctx).bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Center(child: _buildSpecAvatar(d, radius: 44)),
                      const SizedBox(height: 16),
                      Text(
                        d.name.isNotEmpty ? d.name : '-',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1D3557),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _detailField('التخصص', d.spec),
                      _detailField('المنطقة', d.area),
                      _detailField('العنوان', d.addr),
                      if (d.hasCoordinates &&
                          sessionUserIsAdmin(Supabase
                              .instance.client.auth.currentUser))
                        _detailField(
                          'الإحداثيات',
                          '${d.latitude!.toStringAsFixed(5)}, ${d.longitude!.toStringAsFixed(5)}',
                        ),
                      _detailField('الهاتف الأول', d.ph),
                      _detailField('الهاتف الثاني', d.ph2),
                      _detailField('ملاحظات', d.notes),
                      _detailField('رقم السجل', d.id > 0 ? '${d.id}' : ''),
                      if (d.id > 0 &&
                          sessionUserIsAdmin(Supabase
                              .instance.client.auth.currentUser)) ...<Widget>[
                        const SizedBox(height: 16),
                        const Text(
                          'هل موقع العيادة على الخريطة صحيح؟',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1D3557),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: FilledButton.tonal(
                                onPressed: () async {
                                  try {
                                    await DoctorLocationRepository.instance
                                        .recordLocationConfirmation(
                                      _supabase,
                                      d.id,
                                    );
                                    if (bctx.mounted) {
                                      ScaffoldMessenger.of(bctx).showSnackBar(
                                        const SnackBar(
                                          content: Text('شكراً لتأكيد الموقع'),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (bctx.mounted) {
                                      ScaffoldMessenger.of(bctx).showSnackBar(
                                        SnackBar(
                                          content: Text('تعذر التسجيل: $e'),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: const Text('نعم 👍'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final LocationPickResult? picked =
                                      await Navigator.of(bctx)
                                          .push<LocationPickResult>(
                                    MaterialPageRoute<LocationPickResult>(
                                      builder: (BuildContext _) =>
                                          LocationPickerScreen(
                                        initialLatitude: d.latitude ?? 30.5039,
                                        initialLongitude: d.longitude ?? 47.7806,
                                        title: 'تصحيح موقع العيادة',
                                      ),
                                    ),
                                  );
                                  if (picked == null || !bctx.mounted) {
                                    return;
                                  }
                                  try {
                                    await DoctorLocationRepository.instance
                                        .submitLocationCorrection(
                                      _supabase,
                                      doctorId: d.id,
                                      latitude: picked.latitude,
                                      longitude: picked.longitude,
                                    );
                                    docHolder[0] = d.withCoordinates(
                                      picked.latitude,
                                      picked.longitude,
                                    );
                                    setModal(() {});
                                    if (bctx.mounted) {
                                      ScaffoldMessenger.of(bctx).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'تم حفظ الموقع المُصحَّح. شكراً لك.',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (bctx.mounted) {
                                      ScaffoldMessenger.of(bctx).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'تعذر الحفظ: $e',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: const Text('لا ❌'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: primaryPhone.isEmpty
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      _openDialer(
                                        primaryPhone,
                                        doctorName: displayName,
                                      );
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
                                      _openWhatsApp(
                                        primaryPhone,
                                        doctorName: displayName,
                                      );
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
                      if (d.hasCoordinates &&
                          sessionUserIsAdmin(Supabase
                              .instance.client.auth.currentUser))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              unawaited(
                                _openGoogleMapsLatLng(
                                  d.latitude!,
                                  d.longitude!,
                                  locationDetail: displayName,
                                ),
                              );
                            },
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('فتح في خرائط Google (إحداثيات)'),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: d.addr.trim().isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _openMap(
                                  d.addr,
                                  locationDetail: displayName,
                                );
                              },
                        icon: const Icon(Icons.place_rounded),
                        label: const Text('فتح الموقع على الخرائط (النص)'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    _adminTapResetTimer?.cancel();
    _suggestionDebounceTimer?.cancel();
    _searchAnalyticsDebounceTimer?.cancel();
    _authStateSub?.cancel();
    _authStateSub = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _searchController.removeListener(_onSearchTextChanged);
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// تسجيل خروج متاح من الشاشة الرئيسية لجميع المستخدمين (زر «عيادتي» كان يقتصر على الأدمن).
  Future<void> _signOutFromHome() async {
    try {
      await AuthService(Supabase.instance.client).signOut();
    } catch (_) {
      await Supabase.instance.client.auth.signOut();
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryMedicalBlue = Color(0xFF42A5F5);
    const Color sectionShadow = Color(0x1A000000);
    final double listBottomInset =
        MediaQuery.paddingOf(context).bottom + 88 + 56;
    final bool isAdmin =
        sessionUserIsAdmin(Supabase.instance.client.auth.currentUser);
    // Clamp index when the "عيادتي" tab is hidden to avoid showing an empty stack.
    final int safeNavIndex =
        (!isAdmin && _homeNavIndex >= 2) ? 0 : _homeNavIndex;

    return Scaffold(
      floatingActionButton: safeNavIndex == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.pushNamed(context, '/add-clinic'),
              tooltip: 'إضافة عيادة',
              backgroundColor: primaryMedicalBlue,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
      // في RTL تكون "البداية" يمين الشاشة — موضع مريح للإبهام.
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: safeNavIndex,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryMedicalBlue.withValues(alpha: 0.2),
        onDestinationSelected: (int index) {
          setState(() => _homeNavIndex = index);
        },
        destinations: <NavigationDestination>[
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'الرئيسية',
          ),
          const NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'أطبائي',
          ),
          if (isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.store_outlined),
              selectedIcon: Icon(Icons.store_rounded),
              label: 'عيادتي',
            ),
        ],
      ),
      body: IndexedStack(
        index: safeNavIndex,
        children: <Widget>[
          RefreshIndicator(
            onRefresh: () => _backgroundRefresh(
              _selectedGovernorate ?? 'البصرة',
              forceRefresh: true,
            ),
          child: CustomScrollView(
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
              behavior: HitTestBehavior.opaque,
              onTap: _handleAdminTitleTap,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  'المدار الطبي',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
            actions: <Widget>[
              // Last sync timestamp
              if (_lastSyncTime != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Center(
                    child: Text(
                      'محدّث قبل ${_formatSyncAge(_lastSyncTime!)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              // Offline indicator
              StreamBuilder<bool>(
                stream: ConnectivityService.onlineStream(),
                builder:
                    (BuildContext context, AsyncSnapshot<bool> snap) {
                  final bool online = snap.data ?? true;
                  if (online) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      color: Colors.orange,
                      size: 20,
                    ),
                  );
                },
              ),
              // Manual refresh / spinner
              if (_isRefreshing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: () => _backgroundRefresh(
                    _selectedGovernorate ?? 'البصرة',
                    forceRefresh: true,
                  ),
                  icon: const Icon(Icons.refresh),
                ),
              IconButton(
                tooltip:
                    _searchFieldVisible ? 'إغلاق البحث' : 'بحث',
                onPressed: _toggleSearchField,
                icon: Icon(
                  _searchFieldVisible ? Icons.close : Icons.search,
                ),
              ),
              if (Supabase.instance.client.auth.currentSession != null)
                IconButton(
                  tooltip: 'تسجيل الخروج',
                  onPressed: _signOutFromHome,
                  icon: const Icon(Icons.logout_outlined),
                ),
              if (sessionUserIsAdmin(
                  Supabase.instance.client.auth.currentUser))
                IconButton(
                  tooltip: 'لوحة الإدارة',
                  onPressed: () =>
                      Navigator.pushNamed(context, '/admin'),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                ),
              if (kDebugMode && !kIsWeb)
                PopupMenuButton<String>(
                  tooltip: 'أدوات التطوير',
                  icon: const Icon(Icons.bug_report_outlined),
                  onSelected: (String value) {
                    if (value == 'crash') {
                      FirebaseCrashlytics.instance.crash();
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'crash',
                        child: Text('تعطّل التطبيق — اختبار Crashlytics'),
                      ),
                    ];
                  },
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
                        elevation: 2,
                        shadowColor: const Color(0x33000000),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              decoration: InputDecoration(
                                hintText: 'ابحث عن طبيب أو تخصص أو منطقة',
                                filled: true,
                                fillColor: const Color(0xFFEEEEEE),
                                isDense: true,
                                prefixIcon:
                                    const Icon(Icons.search, size: 22),
                                suffixIcon: IconButton(
                                  tooltip: 'إغلاق',
                                  onPressed: () {
                                    setState(() {
                                      _searchFieldVisible = false;
                                      _searchSuggestions =
                                          <SearchSuggestionRow>[];
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
                            if (_searchFocusNode.hasFocus &&
                                _searchSuggestions.isNotEmpty)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 220,
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: _searchSuggestions.length,
                                  separatorBuilder:
                                      (BuildContext context, int index) =>
                                          const Divider(height: 1),
                                  itemBuilder:
                                      (BuildContext ctx, int index) {
                                    final SearchSuggestionRow row =
                                        _searchSuggestions[index];
                                    final IconData icon = switch (row.kind) {
                                      SearchSuggestionKind.doctorName =>
                                        Icons.person_outline_rounded,
                                      SearchSuggestionKind.specialization =>
                                        Icons.medical_services_outlined,
                                      SearchSuggestionKind.area =>
                                        Icons.place_outlined,
                                    };
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(
                                        icon,
                                        size: 22,
                                        color: primaryMedicalBlue,
                                      ),
                                      title: Text(
                                        row.label,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () => _applySuggestionRow(row),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 2, 12, 4),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'أحدث العيادات المضافة',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D3557),
                      ),
                    ),
                  ),
                  if (_isCachedData && _cacheTimestamp != null)
                    Text(
                      'بيانات محفوظة · $_cacheTimestamp',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFB0BEC5),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Amber banner: visible when offline but cached data is shown.
          SliverToBoxAdapter(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _showOfflineBanner ? 40 : 0,
              color: Colors.amber.shade700,
              child: _showOfflineBanner
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.wifi_off_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'تتصفح النسخة المحفوظة',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            textDirection: TextDirection.rtl,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          if (_isLoading)
            SliverToBoxAdapter(
              child: Semantics(
                label: 'جارٍ التحميل',
                child: const DoctorListSkeleton(),
              ),
            )
          else if (_showRetryButton && _allDoctors.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildOfflineRetryView(),
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
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
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
              child: _buildSmartEmptySearchState(),
            )
          else
            SliverPadding(
              padding: EdgeInsetsDirectional.fromSTEB(
                8,
                0,
                8,
                listBottomInset,
              ),
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
          ), // RefreshIndicator
          _buildFavoritesTabContent(),
          if (isAdmin)
            const MyClinicScreen()
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildSmartEmptySearchState() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.search_off_rounded,
              size: 72,
              color: Colors.blue.shade200,
            ),
            const SizedBox(height: 16),
            const Text(
              'عذراً، لم نجد نتائج تطابق بحثك',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D3557),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'جرّب تعديل الكلمات أو إزالة بعض الفلاتر.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: _resetSearchAndFilters,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('إعادة ضبط البحث'),
            ),
            const SizedBox(height: 20),
            const Text(
              'تخصصات شائعة',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A5568),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _kPopularSearchSpecs
                  .map(
                    (String s) => ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _applyPopularSpecChip(s),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesTabContent() {
    const Color primaryMedicalBlue = Color(0xFF42A5F5);
    Widget body;
    if (_isLoading) {
      body = const Center(
        child: CircularProgressIndicator(),
      );
    } else if (_errorMessage != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    } else {
      body = Consumer<FavoritesProvider>(
      builder: (BuildContext context, FavoritesProvider fav, _) {
        if (fav.orderedFavoriteIds.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: const <Widget>[
              SizedBox(height: 24),
              Icon(
                Icons.favorite_border_rounded,
                size: 72,
                color: Color(0xFF90CAF9),
              ),
              SizedBox(height: 16),
              Text(
                'لم تحفظ أي عيادة بعد',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D3557),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'اضغط على أيقونة القلب في بطاقة العيادة لإضافتها إلى «أطبائي».',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF718096),
                  height: 1.35,
                ),
              ),
            ],
          );
        }
        final List<Doctor> ordered = <Doctor>[];
        for (final int id in fav.orderedFavoriteIds) {
          for (final Doctor d in _allDoctors) {
            if (d.id == id) {
              ordered.add(d);
              break;
            }
          }
        }
        if (ordered.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: const <Widget>[
              SizedBox(height: 24),
              Icon(Icons.cloud_off_outlined, size: 56, color: Color(0xFF90CAF9)),
              SizedBox(height: 16),
              Text(
                'المفضلة محفوظة لكن هذه العيادات غير ضمن القائمة الحالية. جرّب تغيير المحافظة أو تحديث البيانات.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF4A5568),
                  height: 1.35,
                ),
              ),
            ],
          );
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          itemCount: ordered.length,
          separatorBuilder: (BuildContext context, int index) =>
              const SizedBox(height: 4),
          itemBuilder: (BuildContext ctx, int i) => _buildClinicCard(ordered[i]),
        );
      },
    );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: primaryMedicalBlue,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          'أطبائي',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          if (Supabase.instance.client.auth.currentSession != null)
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: _signOutFromHome,
              icon: const Icon(Icons.logout_outlined),
            ),
        ],
      ),
      body: body,
    );
  }

  /// فلاتر المحافظة/المنطقة فقط (البحث النصي من أيقونة المكبّر في [SliverAppBar]).
  Widget _buildLocationFiltersCard(Color sectionShadow) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                if (value != null) {
                  unawaited(
                    AnalyticsService.instance
                        .logFilterUsed('governorate', value: value),
                  );
                }
                setState(() {
                  _selectedGovernorate = value;
                });
                CrashlyticsService.instance
                    .setScreen('home_${_selectedGovernorate ?? 'البصرة'}');
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
        unawaited(
          AnalyticsService.instance.logFilterUsed(
            'area',
            value: value ?? 'all',
          ),
        );
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
        color: Theme.of(context).colorScheme.surface,
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
                      unawaited(
                        AnalyticsService.instance
                            .logFilterUsed('specialization', value: 'all'),
                      );
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
                        final String? next =
                            isSelected ? null : specialization;
                        unawaited(
                          AnalyticsService.instance.logFilterUsed(
                            'specialization',
                            value: next ?? 'all',
                          ),
                        );
                        setState(() {
                          _selectedSpecialization = next;
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

  /// Trust-layer badge: green pill that surfaces the verification date when known.
  Widget _buildVerifiedBadge(DateTime? verificationDate) {
    String tooltip = 'حساب موثّق';
    if (verificationDate != null) {
      tooltip = 'موثّق منذ '
          '${verificationDate.day}/${verificationDate.month}/${verificationDate.year}';
    }
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF66BB6A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            Icon(Icons.verified_rounded, size: 14, color: Color(0xFF2E7D32)),
            SizedBox(width: 3),
            Text(
              'موثّق',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2E7D32),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Friendly Arabic relative-time label, e.g. "تحديث: قبل 5 د".
  String _formatLastStatusUpdate(DateTime when) {
    final Duration delta = DateTime.now().difference(when);
    if (delta.inMinutes < 1) return 'تحديث: الآن';
    if (delta.inMinutes < 60) return 'تحديث: قبل ${delta.inMinutes} د';
    if (delta.inHours < 24) return 'تحديث: قبل ${delta.inHours} س';
    if (delta.inDays < 7)   return 'تحديث: قبل ${delta.inDays} يوم';
    return 'تحديث: ${when.day}/${when.month}/${when.year}';
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
        color: Theme.of(context).colorScheme.surface,
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: <Widget>[
                                Text(
                                  doctor.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (doctor.isVerified)
                                  _buildVerifiedBadge(doctor.verificationDate),
                              ],
                            ),
                          ),
                          Consumer<FavoritesProvider>(
                            builder: (BuildContext context,
                                FavoritesProvider fav, _) {
                              final bool saved = fav.isFavorite(doctor.id);
                              return IconButton(
                                tooltip: saved
                                    ? 'إزالة من أطبائي'
                                    : 'حفظ في أطبائي',
                                onPressed: () {
                                  unawaited(fav.toggle(doctor.id));
                                },
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                icon: Icon(
                                  saved
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: saved
                                      ? const Color(0xFFE53935)
                                      : const Color(0xFF90A4AE),
                                  size: 22,
                                ),
                              );
                            },
                          ),
                        ],
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
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (doctor.lastStatusUpdate != null)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: 6),
                              child: Text(
                                _formatLastStatusUpdate(doctor.lastStatusUpdate!),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF90A4AE),
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
                                    : () => _openWhatsApp(
                                          primaryPhone,
                                          doctorName: doctor.name.isNotEmpty
                                              ? doctor.name
                                              : 'غير معروف',
                                        ),
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
                              if (sessionUserIsAdmin(Supabase
                                      .instance.client.auth.currentUser) &&
                                  doctor.hasCoordinates)
                                IconButton(
                                  onPressed: () {
                                    unawaited(_openGoogleMapsLatLng(
                                      doctor.latitude!,
                                      doctor.longitude!,
                                      locationDetail: doctor.name,
                                    ));
                                  },
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
                                    : () => _openDialer(
                                          primaryPhone,
                                          doctorName: doctor.name.isNotEmpty
                                              ? doctor.name
                                              : 'غير معروف',
                                        ),
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
/// Uses Supabase RPC schema introspection so table/column names are not
/// hardcoded in the client.
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
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final EditSuggestionSchemaService _schemaService =
      EditSuggestionSchemaService(Supabase.instance.client);
  EditSuggestionSchemaBundle? _bundle;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final EditSuggestionSchemaBundle b = await _schemaService.loadBundle();
      if (!mounted) return;
      setState(() {
        _bundle = b;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
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
                Text(
                  widget.doctor.name,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF4A5568),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'اقترح تصحيح المعلومات الظاهرة فقط (رقم، عنوان، موقع على الخريطة).',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_bundle != null)
                  DynamicEditSuggestionForm(
                    formKey: _formKey,
                    bundle: _bundle!,
                    schemaService: _schemaService,
                    targetPkValue: widget.doctor.id,
                    doctorNameSnapshot: widget.doctor.name,
                    initialLatitude: widget.doctor.latitude ?? 30.5039,
                    initialLongitude: widget.doctor.longitude ?? 47.7806,
                    statusPendingValue: kReportStatusPending,
                    compactIntro: true,
                    onSubmitted: () {
                      final NavigatorState navigator = Navigator.of(context);
                      widget.onSubmitted(widget.doctor.id);
                      if (navigator.mounted) {
                        navigator.pop();
                      }
                    },
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
  /// يُحدَّث من [MedicalCategorySelector]؛ لا تعتمد على [GlobalKey] لأن الخطوة ٢ تُزال من الشجرة بعد التقدّم.
  String _medicalStoredSpec = '';
  int? _selectedSpecializationId;
  final TextEditingController _areaOtherGovernorateController = TextEditingController();
  final TextEditingController _basraCustomAreaController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phController = TextEditingController();
  final TextEditingController _ph2Controller = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  int _currentStep = 0;
  String _governorate = kGovernorates.first;
  String? _selectedBasraArea;
  bool _basraUseCustomArea = false;
  bool _isSubmitting = false;
  double? _pickedLatitude;
  double? _pickedLongitude;

  @override
  void dispose() {
    _nameController.dispose();
    _areaOtherGovernorateController.dispose();
    _basraCustomAreaController.dispose();
    _addressController.dispose();
    _phController.dispose();
    _ph2Controller.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _buildSpecForSubmit() =>
      MedicalCategorySnapshot.fromStoredSpec(_medicalStoredSpec).toStoredSpec();

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
    return MedicalCategorySnapshot.fromStoredSpec(_medicalStoredSpec)
        .validateBeforeEncode();
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
          _selectedBasraArea != kFormDropdownCustomSentinel &&
          _selectedBasraArea!.isNotEmpty;
    }
    return _areaOtherGovernorateController.text.trim().length >= 2;
  }

  /// تحقق يدوي لجدول kSupabasePendingDoctorsTable بدون الاعتماد فقط على
  /// FormState للخطوات 1-2.
  bool _validateStep1CustomTextIfNeeded() => true;

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
    if (_pickedLatitude == null || _pickedLongitude == null) {
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
          break;
        }
        if (_pickedLatitude == null || _pickedLongitude == null) {
          ok = false;
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'يجب تحديد موقع العيادة على الخريطة من هذه الخطوة.',
              ),
            ),
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
    if (_pickedLatitude == null || _pickedLongitude == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'يجب تحديد موقع العيادة على الخريطة (الخطوة ٣) قبل الإرسال.',
            ),
          ),
        );
      }
      return;
    }
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
      final String textAddr = _addressController.text.trim();
      final String ph2Text = _ph2Controller.text.trim();
      final Map<String, dynamic> payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'spec': spec,
        'addr': textAddr,
        'area': area,
        'ph': _phController.text.trim(),
        'ph2': ph2Text,
        'notes': notes,
        'gove': _governorate,
        if (_selectedSpecializationId != null)
          'specialization_id': _selectedSpecializationId,
        ...DoctorCoordinates.supabasePair(
          latitude: _pickedLatitude,
          longitude: _pickedLongitude,
        ),
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
        SnackBar(content: Text(humanReadableSupabaseWriteError(error))),
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
    _areaOtherGovernorateController.clear();
    _basraCustomAreaController.clear();
    _addressController.clear();
    _phController.clear();
    _ph2Controller.clear();
    _notesController.clear();
    setState(() {
      _currentStep = 0;
      _governorate = kGovernorates.first;
      _selectedBasraArea = null;
      _basraUseCustomArea = false;
      _pickedLatitude = null;
      _pickedLongitude = null;
      _medicalStoredSpec = '';
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
        leading: BackButton(
          color: Colors.white,
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'الرئيسية',
            onPressed: () => popToAppRoot(context),
            icon: const Icon(Icons.home_rounded),
          ),
        ],
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
          MedicalCategorySelector(
            initialStoredSpec: _medicalStoredSpec,
            initialSpecializationId: _selectedSpecializationId,
            showIntroLabels: false,
            tileRadius: 12,
            decorateDropdownField: _inputDecoration,
            onComposedStoredSpecChanged: (String s) {
              if (_medicalStoredSpec == s) {
                return;
              }
              setState(() => _medicalStoredSpec = s);
            },
            onSpecializationIdChanged: (int? id) =>
                _selectedSpecializationId = id,
          ),
        ],
      ),
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
          const SizedBox(height: 20),
          addClinicStyleMapLocationBlock(
            latitude: _pickedLatitude,
            longitude: _pickedLongitude,
            onChanged: (double? latitude, double? longitude) {
              setState(() {
                _pickedLatitude = latitude;
                _pickedLongitude = longitude;
              });
            },
          ),
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
              _basraUseCustomArea ? kFormDropdownCustomSentinel : _selectedBasraArea,
          isExpanded: true,
          decoration: _inputDecoration('اختر المنطقة'),
          items: <DropdownMenuItem<String>>[
            ...kBasraAreas.map(
              (String a) => DropdownMenuItem<String>(value: a, child: Text(a)),
            ),
            const DropdownMenuItem<String>(
              value: kFormDropdownCustomSentinel,
              child: Text('إضافة منطقة جديدة'),
            ),
          ],
          onChanged: (String? v) {
            if (v == null) {
              return;
            }
            setState(() {
              if (v == kFormDropdownCustomSentinel) {
                _basraUseCustomArea = true;
                _selectedBasraArea = kFormDropdownCustomSentinel;
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
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final SupabaseClient _supabase = Supabase.instance.client;
  final EditSuggestionSchemaService _schemaService =
      EditSuggestionSchemaService(Supabase.instance.client);
  final TextEditingController _doctorIdController = TextEditingController();
  final TextEditingController _doctorNameController = TextEditingController();
  EditSuggestionSchemaBundle? _bundle;
  bool _schemaLoading = true;
  bool _isMounted = false;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _loadSchema();
  }

  Future<void> _loadSchema() async {
    final EditSuggestionSchemaBundle b = await _schemaService.loadBundle();
    if (!mounted) {
      return;
    }
    setState(() {
      _bundle = b;
      _schemaLoading = false;
    });
  }

  @override
  void dispose() {
    _isMounted = false;
    _doctorIdController.dispose();
    _doctorNameController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _onDynamicSubmitted() async {
    if (!_isMounted || !mounted) {
      return;
    }
    _showSnack('شكراً، تم حفظ الاقتراح بنجاح.');
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      _doctorIdController.clear();
      _doctorNameController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryMedicalBlue = Color(0xFF42A5F5);
    final int? docId = int.tryParse(_doctorIdController.text.trim());
    final bool idOk = docId != null && docId > 0;
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('اقتراح تعديل معلومات'),
          backgroundColor: primaryMedicalBlue,
          foregroundColor: Colors.white,
          leading: BackButton(
            color: Colors.white,
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'الرئيسية',
              onPressed: () => popToAppRoot(context),
              icon: const Icon(Icons.home_rounded),
            ),
          ],
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
                  onChanged: (_) => setState(() {}),
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
                  onChanged: (_) => setState(() {}),
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
                const SizedBox(height: 16),
                if (_schemaLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_bundle != null && _bundle!.ok && idOk)
                  FutureBuilder<List<dynamic>>(
                    future: _supabase
                        .from(kSupabaseDoctorsTable)
                        .select('latitude, longitude')
                        .eq('id', docId)
                        .limit(1),
                    builder: (BuildContext ctx, AsyncSnapshot<List<dynamic>> snap) {
                      double la = 30.5039;
                      double ln = 47.7806;
                      if (snap.hasData && snap.data!.isNotEmpty) {
                        final Map<String, dynamic> row =
                            snap.data!.first as Map<String, dynamic>;
                        la = DoctorCoordinates.readLatitude(row) ?? la;
                        ln = DoctorCoordinates.readLongitude(row) ?? ln;
                      }
                      return DynamicEditSuggestionForm(
                        formKey: _formKey,
                        bundle: _bundle!,
                        schemaService: _schemaService,
                        targetPkValue: docId,
                        doctorNameSnapshot: _doctorNameController.text.trim(),
                        initialLatitude: la,
                        initialLongitude: ln,
                        statusPendingValue: kReportStatusPending,
                        onSubmitted: _onDynamicSubmitted,
                      );
                    },
                  )
                else if (_bundle != null && !_bundle!.ok)
                  const Text(
                    'تعذر تحميل هيكل قاعدة البيانات. طبّق migration «edit_suggestion_schema_introspection».',
                  )
                else if (!idOk)
                  const Text(
                    'أدخل رقم سجل صحيحاً لعرض نموذج الاقتراح.',
                    style: TextStyle(color: Color(0xFF718096)),
                  ),
              ],
            ),
          ),
        ),
      ),
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
    // نطبيع النص العربي: نزيل الهمزات لمطابقة الصيغ المختلفة (أنف/انف،
    // أذن/اذن، أعصاب/اعصاب) ونحوّل تنوع الياء/الألف المقصورة، حتى تتطابق
    // المفاتيح أدناه مع القيم الفعلية في قاعدة بيانات Supabase.
    final String s = _normalizeArabicForMatch(spec);

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
    if (has('صيدل', 'pharm') || has('دواء', 'drug')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF66BB6A), Color(0xFF1B5E20)],
        faIcon: FontAwesomeIcons.prescriptionBottleMedical,
      );
    }
    if (has('مختبر', 'lab') || has('فحوص', 'analyses')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF26A69A), Color(0xFF00695C)],
        faIcon: FontAwesomeIcons.flaskVial,
      );
    }
    if (has('نووي', 'nuclear') || has('بتا سكان', 'pet scan')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFFFFA726), Color(0xFFE65100)],
        faIcon: FontAwesomeIcons.atom,
      );
    }
    if (has('اشعة', 'radio') || has('سونار', 'ultrasound')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF26C6DA), Color(0xFF00838F)],
        faIcon: FontAwesomeIcons.xRay,
      );
    }
    if (has('ممرض', 'nurse')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFFEC407A), Color(0xFFAD1457)],
        faIcon: FontAwesomeIcons.userNurse,
      );
    }
    if (has('قلب', 'cardio') || has('قسطرة', 'angio')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFFEF5350), Color(0xFFC62828)],
        faIcon: FontAwesomeIcons.heartPulse,
      );
    }
    if (has('عيون', 'ophthal') ||
        has('بصر', 'optom') ||
        has('عوينات', 'glasses')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF42A5F5), Color(0xFF1565C0)],
        faIcon: FontAwesomeIcons.eye,
      );
    }
    if (has('انف', 'ent') || has('اذن', 'hns') || has('حنجرة', 'laryng')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF7E57C2), Color(0xFF4527A0)],
        faIcon: FontAwesomeIcons.earListen,
      );
    }
    if (has('مخ', 'neuro') ||
        has('اعصاب', 'nerve') ||
        has('عصبي', 'neural') ||
        has('دماغ', 'brain')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFFAB47BC), Color(0xFF6A1B9A)],
        faIcon: FontAwesomeIcons.brain,
      );
    }
    if (has('عظام', 'ortho') ||
        has('مفاصل', 'joint') ||
        has('كسور', 'fracture')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFFFFB74D), Color(0xFFEF6C00)],
        faIcon: FontAwesomeIcons.bone,
      );
    }
    if (has('اطفال', 'pediat') || has('حديثي الولادة', 'neonat')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF66BB6A), Color(0xFF2E7D32)],
        faIcon: FontAwesomeIcons.baby,
      );
    }
    if (has('نسائ', 'gyn') ||
        has('توليد', 'obstet') ||
        has('ولادة', 'matern') ||
        has('عقيم', 'fertil')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFFEC407A), Color(0xFFAD1457)],
        faIcon: FontAwesomeIcons.personPregnant,
      );
    }
    if (has('جلد', 'derma') || has('ليزر', 'laser') || has('تجميل', 'cosmet')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF29B6F6), Color(0xFF0277BD)],
        faIcon: FontAwesomeIcons.handSparkles,
      );
    }
    if (has('صدر', 'chest') || has('رئة', 'pulm') || has('تنفس', 'respir')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF4FC3F7), Color(0xFF0277BD)],
        faIcon: FontAwesomeIcons.lungs,
      );
    }
    if (has('كلى', 'nephro') ||
        has('مسالك', 'urolog') ||
        has('بولي', 'urinary') ||
        has('مجاري', 'tract')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF5C6BC0), Color(0xFF283593)],
        faIcon: FontAwesomeIcons.handHoldingMedical,
      );
    }
    if (has('تغذية', 'nutrit')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF8BC34A), Color(0xFF558B2F)],
        faIcon: FontAwesomeIcons.appleWhole,
      );
    }
    if (has('باطن', 'intern') ||
        has('سكر', 'diabet') ||
        has('غدد', 'endocr') ||
        has('هضم', 'gastro') ||
        has('اورام', 'oncol') ||
        has('دم', 'blood')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF26A69A), Color(0xFF00695C)],
        faIcon: FontAwesomeIcons.notesMedical,
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
    if (has('جراح', 'surg') || has('عمليات', 'operation')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF78909C), Color(0xFF37474F)],
        faIcon: FontAwesomeIcons.userDoctor,
      );
    }
    if (has('مستشفى', 'hospital') || has('مستشفيات', 'hospitals')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF42A5F5), Color(0xFF1565C0)],
        faIcon: FontAwesomeIcons.hospital,
      );
    }
    if (has('مجمع', 'complex') || has('خيري', 'charity')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF7E57C2), Color(0xFF4527A0)],
        faIcon: FontAwesomeIcons.handHoldingHeart,
      );
    }
    if (has('تجهيز', 'equipment') || has('مساند', 'assist')) {
      return const _SpecVisual(
        gradientColors: <Color>[Color(0xFF78909C), Color(0xFF37474F)],
        faIcon: FontAwesomeIcons.briefcaseMedical,
      );
    }

    return const _SpecVisual(
      gradientColors: <Color>[Color(0xFF64B5F6), Color(0xFF1E88E5)],
      faIcon: FontAwesomeIcons.userDoctor,
    );
  }

  /// نُطبيع النص العربي: lowercase + trim + توحيد همزات الألف، حتى تتطابق
  /// المفاتيح أعلاه (كـ «انف») مع القيم الفعلية في قاعدة البيانات سواء كانت
  /// «أنف» أو «الانف» أو «إنف». ملاحظة: لا نُحوّل ى→ي ولا ة→ه لتفادي كسر
  /// مفاتيح كـ «كلى» أو «حنجرة» أو «ولادة».
  static String _normalizeArabicForMatch(String spec) {
    return spec
        .toLowerCase()
        .trim()
        .replaceAll(RegExp('[أإآ]'), 'ا');
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