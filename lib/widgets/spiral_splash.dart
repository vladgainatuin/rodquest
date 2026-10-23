import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'effects.dart';

/// Заставка версии 0.7: спиральное поле, как в «Игре в гуся». Три пешки
/// (семья) ход за ходом идут по 20 клеткам к короне в центре — к большой цели.
///
/// Показывается, пока загружаются данные, но не меньше [minDuration], чтобы
/// анимацию успели увидеть. Когда всё готово и время вышло — плавно исчезает
/// и вызывает [onDone].
class SpiralSplash extends StatefulWidget {
  const SpiralSplash({super.key, required this.ready, required this.onDone});

  /// Данные загружены.
  final bool ready;
  final VoidCallback onDone;

  static const minDuration = Duration(milliseconds: 2600);

  static const background = Color(0xFF2B2140);

  @override
  State<SpiralSplash> createState() => _SpiralSplashState();
}

class _SpiralSplashState extends State<SpiralSplash> with TickerProviderStateMixin {
  /// Один круг: 80% — ходы, 20% — пешки стоят у короны.
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 9));
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final _SpiralGeometry _geo = _SpiralGeometry();
  bool _minElapsed = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (motionAllowed(context)) {
        _loop.repeat();
      } else {
        _loop.value = 0.5;
      }
    });
    Future<void>.delayed(SpiralSplash.minDuration, () {
      _minElapsed = true;
      _maybeLeave();
    });
  }

  @override
  void didUpdateWidget(SpiralSplash old) {
    super.didUpdateWidget(old);
    if (widget.ready) _maybeLeave();
  }

  void _maybeLeave() {
    if (!mounted || _leaving || !widget.ready || !_minElapsed) return;
    _leaving = true;
    _fade.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpiralSplash.background,
      body: AnimatedBuilder(
        animation: Listenable.merge([_loop, _fade]),
        builder: (context, _) {
          final t = _loop.value;
          final progress = (t / 0.8).clamp(0.0, 1.0);
          return Opacity(
            opacity: 1 - _fade.value,
            child: LayoutBuilder(
              builder: (context, box) {
                final side = math.min(box.maxWidth - 24, box.maxHeight * 0.58).clamp(200.0, 520.0);
                return Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: _StarsPainter(t))),
                    Column(
                      children: [
                        const Spacer(flex: 3),
                        Center(
                          child: Semantics(
                            label: 'Родквест загружается',
                            child: CustomPaint(size: Size.square(side), painter: _BoardPainter(_geo, t)),
                          ),
                        ),
                        const Spacer(flex: 2),
                        const Text(
                          'Родквест',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 220,
                            height: 12,
                            child: Stack(
                              children: [
                                const Positioned.fill(child: ColoredBox(color: Color(0xFF3D3158))),
                                FractionallySizedBox(
                                  widthFactor: 0.04 + progress * 0.96,
                                  child: const DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Color(0xFFFFB300),
                                      borderRadius: BorderRadius.all(Radius.circular(6)),
                                    ),
                                    child: SizedBox.expand(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Ход за ходом — к большой цели',
                          style: TextStyle(fontFamily: 'Nunito', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFC9C0DD)),
                        ),
                        const Spacer(flex: 2),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Геометрия спирали в квадрате 390×390: центр (195, 195), радиус от 165 до 34,
/// 1,85 витка, 20 клеток через равные расстояния по дуге.
class _SpiralGeometry {
  _SpiralGeometry() {
    const n = 400;
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final a = -math.pi / 2 + t * turns * 2 * math.pi;
      final r = r0 + (r1 - r0) * t;
      _pts.add(Offset(195 + r * math.cos(a), 195 + r * math.sin(a)));
    }
    _len.add(0);
    for (var i = 1; i < _pts.length; i++) {
      _len.add(_len.last + (_pts[i] - _pts[i - 1]).distance);
    }
    for (var k = 0; k <= tiles; k++) {
      tilePoints.add(at(k / tiles));
    }
  }

  static const turns = 1.85;
  static const r0 = 165.0;
  static const r1 = 34.0;
  static const tiles = 20;

  final _pts = <Offset>[];
  final _len = <double>[];
  final tilePoints = <Offset>[];

  List<Offset> get points => _pts;

  /// Точка на спирали на доле [f] (0..1) её длины.
  Offset at(double f) {
    final target = _len.last * f.clamp(0.0, 1.0);
    var lo = 0, hi = _len.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_len[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == 0) return _pts.first;
    final seg = _len[lo] - _len[lo - 1];
    final k = seg == 0 ? 0.0 : (target - _len[lo - 1]) / seg;
    return Offset.lerp(_pts[lo - 1], _pts[lo], k)!;
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.geo, this.t);

  final _SpiralGeometry geo;
  final double t;

  static const _tileColors = [Color(0xFF29C46A), Color(0xFF2F8CFF), Color(0xFF9A5CF7), Color(0xFFFF7A59)];
  static const _gold = Color(0xFFFFB300);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 390;
    canvas.save();
    canvas.scale(s);

    // Дорожка.
    final track = Path()..addPolygon(geo.points, false);
    canvas.drawPath(
      track,
      Paint()
        ..color = const Color(0xFF3D3158)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 40
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Цель в центре: свечение, круг и покачивающаяся корона.
    const center = Offset(195, 195);
    final glow = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 4.5);
    canvas.drawCircle(center, 40 + glow * 8, Paint()..color = _gold.withValues(alpha: 0.25 + glow * 0.25));
    canvas.drawCircle(center, 30, Paint()..color = _gold);
    canvas.drawCircle(
      center,
      30,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    final bob = math.sin(t * math.pi * 2 * 6) * 2.5;
    canvas.drawPath(crownPath(Rect.fromCenter(center: center + Offset(0, bob), width: 34, height: 28)), Paint()..color = Colors.white);

    // Клетки с номерами.
    for (var k = 0; k < _SpiralGeometry.tiles; k++) {
      final c = geo.tilePoints[k];
      final color = _tileColors[k ~/ 5];
      canvas.drawCircle(c, 16, Paint()..color = color);
      canvas.drawCircle(
        c,
        16,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${k + 1}',
          style: const TextStyle(fontFamily: 'Nunito', fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }

    // Пешки: ход каждые 1/20 от 80% круга, прыжок по дуге между клетками.
    const pawns = [(Color(0xFF8B70FF), 0), (Color(0xFFFFFFFF), 1), (Color(0xFFFF5C6C), 2)];
    for (final (color, lead) in pawns) {
      final steps = (t / 0.8).clamp(0.0, 1.0) * _SpiralGeometry.tiles + lead;
      final clamped = math.min(steps, _SpiralGeometry.tiles.toDouble());
      final whole = clamped.floorToDouble();
      final frac = clamped - whole;
      // Быстрый прыжок в первой половине шага, затем пауза на клетке.
      final move = Curves.easeInOut.transform((frac / 0.6).clamp(0.0, 1.0));
      final pos = geo.at((whole + move) / _SpiralGeometry.tiles);
      final atGoal = clamped >= _SpiralGeometry.tiles;
      final hop = atGoal ? math.sin(t * math.pi * 2 * 10).abs() * 8 : math.sin(move * math.pi) * 14;
      const w = 24.0;
      final spread = atGoal ? (lead - 1) * 16.0 : 0.0;
      final box = Rect.fromLTWH(pos.dx - w / 2 + spread, pos.dy - w * 1.4 * 0.88 - hop, w, w * 1.4);
      canvas.drawOval(
        Rect.fromCenter(center: pos + Offset(spread, 2), width: 20, height: 6),
        Paint()..color = Colors.black.withValues(alpha: 0.25),
      );
      paintPawn(canvas, box, color, const Color(0xFF2B2140));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardPainter old) => old.t != t;
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.t);

  final double t;

  static const _stars = [
    (0.10, 0.08, 2.0, 0.0), (0.31, 0.05, 1.5, 0.5), (0.77, 0.07, 2.0, 0.2), (0.90, 0.15, 1.5, 0.7),
    (0.18, 0.20, 1.5, 0.4), (0.59, 0.13, 2.0, 0.9), (0.08, 0.74, 1.5, 0.3), (0.92, 0.76, 2.0, 0.6),
    (0.85, 0.70, 1.5, 0.1), (0.15, 0.82, 2.0, 0.8), (0.50, 0.04, 1.5, 0.35), (0.70, 0.88, 1.5, 0.55),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (x, y, r, phase) in _stars) {
      final a = 0.2 + 0.8 * (0.5 + 0.5 * math.sin((t * 5 + phase) * math.pi * 2));
      canvas.drawCircle(Offset(x * size.width, y * size.height), r, Paint()..color = Colors.white.withValues(alpha: a));
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.t != t;
}
