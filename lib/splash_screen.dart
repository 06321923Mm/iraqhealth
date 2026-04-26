import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color kSplashBackground = Color(0xFFF0F8FF);

Path _ekgPath(double w, double h) {
  const double step = 14;
  const double hAmp = 10;
  final Path p = Path()..moveTo(0, h * 0.5);
  double x = 0;
  while (x < w) {
    p
      // خط مستوٍ
      ..lineTo(x + step * 0.4, h * 0.5)
      // موجة صعود/هبوط
      ..lineTo(x + step * 0.5, h * 0.5 - hAmp * 0.2)
      ..lineTo(x + step * 0.6, h * 0.5);
    p
      ..lineTo(x + step * 0.9, h * 0.5)
      ..lineTo(x + step, h * 0.5 - hAmp);
    p
      ..lineTo(x + step * 1.1, h * 0.5 + hAmp * 0.5)
      ..lineTo(x + step * 1.2, h * 0.5);
    p.lineTo(x + step * 1.4, h * 0.5);
    p.lineTo(x + step * 1.4, h * 0.5);
    p.lineTo(x + step * 1.5, h * 0.5);
    p.lineTo(x + step * 1.8, h * 0.5 - hAmp * 0.3);
    p.lineTo(x + step * 2, h * 0.5);
    x += step * 2;
  }
  p.lineTo(w, h * 0.5);
  return p;
}

class EkgLinePainter extends CustomPainter {
  EkgLinePainter({required this.progress, required this.color})
      : assert(progress >= 0 && progress <= 1);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = _ekgPath(size.width, size.height);
    final List<ui.PathMetric> metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) {
      return;
    }
    final ui.PathMetric m = metrics.first;
    final double len = m.length;
    if (len <= 0) {
      return;
    }
    final double t = (len * progress).clamp(0, len);
    final Path trail = m.extractPath(0, t);
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(trail, paint);
    final ui.Tangent? tan = m.getTangentForOffset(t);
    if (tan != null && t > 1) {
      canvas.drawCircle(tan.position, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant EkgLinePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const int _kNavMs = 2500;

  late final AnimationController _main;
  late final AnimationController _pulse;
  late final Animation<double> _titleOp;
  late final Animation<double> _titleScale;
  late final Animation<double> _subOp;
  late final Animation<double> _ekgVal;

  @override
  void initState() {
    super.initState();
    _main = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kNavMs),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _titleOp = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0, 0.3, curve: Curves.easeOut),
      ),
    );
    _titleScale = Tween<double>(begin: 0.86, end: 1).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0, 0.3, curve: Curves.easeOutCubic),
      ),
    );
    _subOp = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.2, 0.4, curve: Curves.easeIn),
      ),
    );
    _ekgVal = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0, 0.92, curve: Curves.linear),
      ),
    );
    _main.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed && mounted) {
        _pulse.stop();
        Navigator.of(context).pushReplacementNamed('/home');
      }
    });
    _main.forward();
  }

  @override
  void dispose() {
    _main.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color lineColor = Color(0xFF42A5F5);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kSplashBackground,
        body: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_main, _pulse]),
          builder: (BuildContext context, Widget? child) {
            final double pulseS = 1.0 + (_pulse.value * 0.1);
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Transform.scale(
                      scale: pulseS,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          Container(
                            width: 40,
                            height: 3,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00ACC1)
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Container(
                            width: 3,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00ACC1)
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FadeTransition(
                      opacity: _titleOp,
                      child: Transform.scale(
                        scale: _titleScale.value,
                        child: Text(
                          'المدار الطبي',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1D3557),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FadeTransition(
                      opacity: _subOp,
                      child: Text(
                        'أهلاً بك في المدار الطبي',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          color: const Color(0xFF4A6FA5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 40,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: EkgLinePainter(
                          progress: _ekgVal.value,
                          color: lineColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
