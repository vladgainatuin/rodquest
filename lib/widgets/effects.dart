import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

// Визуальные эффекты версии 0.7: конфетти, монеты в копилку, «удар по боссу»,
// огонь серии и пешка на карте квестов. Все эффекты короткие (не бесконечные)
// и отключаются, если в системе выключены анимации.

/// Можно ли показывать движение (в системе не выключены анимации).
bool motionAllowed(BuildContext context) => !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

// ---------- Фигуры: пешка, пламя, корона ----------

/// Пешка в рамке 100×140 (как на логотипе и в заставке).
Path pawnPath(Rect box) {
  final sx = box.width / 100, sy = box.height / 140;
  Offset p(double x, double y) => Offset(box.left + x * sx, box.top + y * sy);
  return Path()
    ..addOval(Rect.fromCircle(center: p(50, 30), radius: 22 * sx))
    ..addRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(30, 54), p(70, 64)), Radius.circular(5 * sx)))
    ..moveTo(p(34, 64).dx, p(34, 64).dy)
    ..cubicTo(p(34, 88).dx, p(34, 88).dy, p(26, 104).dx, p(26, 104).dy, p(18, 114).dx, p(18, 114).dy)
    ..lineTo(p(82, 114).dx, p(82, 114).dy)
    ..cubicTo(p(74, 104).dx, p(74, 104).dy, p(66, 88).dx, p(66, 88).dy, p(66, 64).dx, p(66, 64).dy)
    ..close()
    ..addRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(10, 112), p(90, 130)), Radius.circular(9 * sx)));
}

/// Нарисовать пешку с обводкой; [box] — рамка 100×140.
void paintPawn(Canvas canvas, Rect box, Color fill, Color outline) {
  final path = pawnPath(box);
  canvas.drawPath(
    path,
    Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = box.width * 0.09
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.drawPath(path, Paint()..color = fill);
}

/// Корона в рамке 34×28.
Path crownPath(Rect box) {
  final sx = box.width / 34, sy = box.height / 28;
  Offset p(double x, double y) => Offset(box.left + x * sx, box.top + y * sy);
  final path = Path()..moveTo(p(3, 22).dx, p(3, 22).dy);
  for (final pt in [p(1, 4), p(10, 12), p(17, 1), p(24, 12), p(33, 4), p(31, 22)]) {
    path.lineTo(pt.dx, pt.dy);
  }
  path
    ..close()
    ..addRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(3, 23), p(31, 27)), Radius.circular(2 * sx)));
  return path;
}

class PawnIcon extends StatelessWidget {
  const PawnIcon({super.key, required this.color, this.size = 26, this.outline = Colors.white});

  final Color color;
  final Color outline;

  /// Ширина; высота — в 1,4 раза больше.
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size * 1.4), painter: _PawnPainter(color, outline));
}

class _PawnPainter extends CustomPainter {
  _PawnPainter(this.color, this.outline);

  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) => paintPawn(canvas, Offset.zero & size, color, outline);

  @override
  bool shouldRepaint(_PawnPainter old) => old.color != color || old.outline != outline;
}

// ---------- Огонь серии ----------

/// Плашка серии с живым пламенем: оно дрожит несколько секунд после появления,
/// и чем длиннее серия, тем крупнее и ярче огонь.
class StreakFlame extends StatefulWidget {
  const StreakFlame({super.key, required this.streak, required this.unit});

  final int streak;
  final String unit;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  int _flickers = 0;

  /// Сколько раз дрогнуть (туда-обратно) — не бесконечно, чтобы не тратить батарею.
  static const _maxFlickers = 10;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (!mounted) return;
      if (s == AnimationStatus.completed && _flickers < _maxFlickers) {
        _flickers++;
        _c.reverse();
      } else if (s == AnimationStatus.dismissed && _flickers < _maxFlickers) {
        _flickers++;
        _c.forward();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && motionAllowed(context)) _c.forward();
    });
  }

  @override
  void didUpdateWidget(StreakFlame old) {
    super.didUpdateWidget(old);
    // Серия выросла — огонь снова вспыхивает.
    if (widget.streak > old.streak && motionAllowed(context)) {
      _flickers = 0;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = RqColors.tier(GoalTier.daily);
    final heat = (widget.streak / 30).clamp(0.0, 1.0);
    final size = 13.0 + heat * 5;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      decoration: BoxDecoration(
        color: RqColors.tint(color, 0.13 + heat * 0.1),
        borderRadius: BorderRadius.circular(RqColors.playful ? 10 : 6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              size: Size(size * 0.8, size),
              painter: _FlamePainter(_c.value, heat),
            ),
          ),
          const SizedBox(width: 4),
          Text('${widget.streak} ${widget.unit}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: RqColors.strong(color))),
        ],
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter(this.t, this.heat);

  final double t;
  final double heat;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Дрожание: чуть выше и с наклоном, от основания.
    canvas.translate(size.width / 2, size.height);
    canvas.scale(1 + t * 0.05, 1 + t * 0.12);
    canvas.skew((t - 0.5) * 0.12, 0);
    canvas.translate(-size.width / 2, -size.height);
    final sx = size.width / 80, sy = size.height / 100;
    Offset p(double x, double y) => Offset(x * sx, y * sy);
    Path flame(List<double> v) {
      final path = Path()..moveTo(p(v[0], v[1]).dx, p(v[0], v[1]).dy);
      for (var i = 2; i + 5 < v.length; i += 6) {
        path.cubicTo(p(v[i], v[i + 1]).dx, p(v[i], v[i + 1]).dy, p(v[i + 2], v[i + 3]).dx, p(v[i + 2], v[i + 3]).dy,
            p(v[i + 4], v[i + 5]).dx, p(v[i + 4], v[i + 5]).dy);
      }
      return path..close();
    }

    final outer = flame([40, 4, 46, 24, 66, 36, 66, 62, 66, 82, 54, 96, 40, 96, 26, 96, 14, 82, 14, 62, 14, 46, 24, 38, 28, 26, 32, 40, 38, 42, 40, 4]);
    final inner = flame([40, 42, 44, 54, 54, 60, 54, 74, 54, 86, 48, 92, 40, 92, 32, 92, 26, 86, 26, 74, 26, 66, 32, 60, 34, 54, 36, 62, 39, 62, 40, 42]);
    canvas.drawPath(outer, Paint()..color = Color.lerp(const Color(0xFFFF7A59), const Color(0xFFFF4D2E), heat)!);
    canvas.drawPath(inner, Paint()..color = const Color(0xFFFFB300));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.t != t || old.heat != heat;
}

// ---------- Пешка на карте квестов ----------

/// Дорожка из клеток: пешка стоит на клетке по прогрессу цели и прыгает
/// вперёд, когда прогресс растёт. Последняя клетка — корона (цель).
class PawnTrack extends StatelessWidget {
  const PawnTrack({super.key, required this.progress, required this.color, this.tiles = 6});

  final double progress;
  final Color color;
  final int tiles;

  @override
  Widget build(BuildContext context) {
    final target = (progress.clamp(0.0, 1.0) * (tiles - 1));
    return Semantics(
      label: 'Прогресс ${(progress * 100).round()}%',
      child: SizedBox(
        height: 38,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: motionAllowed(context) ? const Duration(milliseconds: 900) : Duration.zero,
          curve: Curves.easeInOut,
          builder: (context, pos, _) => CustomPaint(
            size: const Size(double.infinity, 38),
            painter: _TrackPainter(pos, tiles, color, RqColors.track, RqColors.gold),
          ),
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.pos, this.tiles, this.color, this.empty, this.gold);

  final double pos;
  final int tiles;
  final Color color;
  final Color empty;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    const tileW = 22.0, tileH = 11.0;
    final y = size.height - tileH / 2 - 3;
    final step = (size.width - tileW) / (tiles - 1);
    for (var i = 0; i < tiles; i++) {
      final cx = tileW / 2 + i * step;
      final last = i == tiles - 1;
      final reached = i <= pos + 0.001;
      final c = last ? gold : (reached ? color : empty);
      final r = Rect.fromCenter(center: Offset(cx, y), width: tileW, height: tileH);
      canvas.drawOval(r.shift(const Offset(0, 2.5)), Paint()..color = Color.lerp(c, Colors.black, 0.18)!);
      canvas.drawOval(r, Paint()..color = c);
      if (last) {
        canvas.drawPath(crownPath(Rect.fromCenter(center: Offset(cx, y - 12), width: 17, height: 14)), Paint()..color = gold);
      }
      if (i < tiles - 1) {
        final dot = Paint()..color = empty;
        for (var d = 1; d < 4; d++) {
          canvas.drawCircle(Offset(cx + step * d / 4, y), 1.6, dot);
        }
      }
    }
    // Пешка: позиция между клетками и прыжок по дуге.
    final frac = pos - pos.floorToDouble();
    final hop = math.sin(frac * math.pi) * 10;
    final px = tileW / 2 + pos * step;
    const pw = 16.0;
    final box = Rect.fromLTWH(px - pw / 2, y - pw * 1.4 + 2 - hop, pw, pw * 1.4);
    paintPawn(canvas, box, color, Colors.white);
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.pos != pos || old.color != color || old.tiles != tiles;
}

// ---------- Конфетти ----------

/// Залп конфетти из точки [origin] (по умолчанию — над центром экрана).
void showConfetti(BuildContext context, {Offset? origin}) {
  if (!motionAllowed(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Confetti(origin: origin, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _Confetti extends StatefulWidget {
  const _Confetti({required this.origin, required this.onDone});

  final Offset? origin;
  final VoidCallback onDone;

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _Bit {
  _Bit(math.Random r, this.color)
      : angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.3,
        speed = 260 + r.nextDouble() * 320,
        spin = (r.nextDouble() - 0.5) * 18,
        w = 6 + r.nextDouble() * 5,
        h = 9 + r.nextDouble() * 6,
        round = r.nextDouble() < 0.3;

  final double angle;
  final double speed;
  final double spin;
  final double w;
  final double h;
  final bool round;
  final Color color;
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward().whenComplete(widget.onDone);
  late final List<_Bit> _bits;

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    final p = RqColors.p;
    final colors = p.playful
        ? [p.danger, p.gold, const Color(0xFF2F8CFF), p.xp, const Color(0xFF9A5CF7), const Color(0xFFFF7A59)]
        : [p.primary, p.gold, p.xp];
    final n = p.playful ? 32 : 16;
    _bits = [for (var i = 0; i < n; i++) _Bit(r, colors[i % colors.length])];
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final origin = widget.origin ?? Offset(size.width / 2, size.height * 0.55);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(size: size, painter: _ConfettiPainter(_bits, _c.value, origin)),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t, this.origin);

  final List<_Bit> bits;
  final double t;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    final time = t * 1.6;
    const gravity = 620.0;
    final fade = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3);
    for (final b in bits) {
      final x = origin.dx + math.cos(b.angle) * b.speed * time * 0.9;
      final y = origin.dy + math.sin(b.angle) * b.speed * time + gravity * time * time / 2;
      final paint = Paint()..color = b.color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * time);
      final r = Rect.fromCenter(center: Offset.zero, width: b.w, height: b.round ? b.w : b.h);
      if (b.round) {
        canvas.drawOval(r, paint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1.5)), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// ---------- Монеты в копилку ----------

/// Куда летят монеты: счётчик монет в шапке регистрирует себя здесь.
class CoinTarget {
  CoinTarget._();

  static BuildContext? _context;

  /// Номер «удара» — счётчик подпрыгивает, когда номер меняется.
  static final pulse = ValueNotifier<int>(0);

  static void attach(BuildContext context) => _context = context;

  static void detach(BuildContext context) {
    if (_context == context) _context = null;
  }

  static Offset? get center {
    final c = _context;
    if (c == null || !c.mounted) return null;
    final box = c.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }
}

/// Монеты дугой летят к счётчику в шапке; счётчик подпрыгивает.
void showCoinFlight(BuildContext context, int coins) {
  if (coins <= 0) return;
  final target = CoinTarget.center;
  if (target == null || !motionAllowed(context)) {
    CoinTarget.pulse.value++;
    return;
  }
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoinFlight(count: math.min(6, math.max(2, coins ~/ 3)), target: target, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _CoinFlight extends StatefulWidget {
  const _CoinFlight({required this.count, required this.target, required this.onDone});

  final int count;
  final Offset target;
  final VoidCallback onDone;

  @override
  State<_CoinFlight> createState() => _CoinFlightState();
}

class _CoinFlightState extends State<_CoinFlight> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  bool _pulsed = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_pulsed && _c.value > 0.62) {
        _pulsed = true;
        CoinTarget.pulse.value++;
      }
    });
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final start = Offset(size.width / 2, size.height * 0.62);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) =>
            CustomPaint(size: size, painter: _CoinPainter(_c.value, widget.count, start, widget.target, RqColors.coin)),
      ),
    );
  }
}

class _CoinPainter extends CustomPainter {
  _CoinPainter(this.t, this.count, this.start, this.end, this.color);

  final double t;
  final int count;
  final Offset start;
  final Offset end;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final control = Offset((start.dx + end.dx) / 2 - 60, math.min(start.dy, end.dy) - 120);
    for (var i = 0; i < count; i++) {
      // Каждая следующая монета вылетает чуть позже.
      final local = ((t - i * 0.06) / 0.6).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final k = Curves.easeIn.transform(local);
      final a = Offset.lerp(start, control, k)!;
      final b = Offset.lerp(control, end, k)!;
      final pos = Offset.lerp(a, b, k)! + Offset((i - count / 2) * 6 * (1 - k), 0);
      final r = 11 - 3 * k;
      canvas.drawCircle(pos, r + 2, Paint()..color = Colors.white);
      canvas.drawCircle(pos, r, Paint()..color = color);
      canvas.drawCircle(
        pos,
        r * 0.55,
        Paint()
          ..color = const Color(0xFFFFD873)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_CoinPainter old) => old.t != t;
}

/// Обёртка счётчика монет в шапке: цель для летящих монет, подпрыгивает при «ударе».
class CoinTargetBox extends StatefulWidget {
  const CoinTargetBox({super.key, required this.child});

  final Widget child;

  @override
  State<CoinTargetBox> createState() => _CoinTargetBoxState();
}

class _CoinTargetBoxState extends State<CoinTargetBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  void _bump() {
    if (mounted) _c.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    CoinTarget.attach(context);
    CoinTarget.pulse.addListener(_bump);
  }

  @override
  void dispose() {
    CoinTarget.pulse.removeListener(_bump);
    CoinTarget.detach(context);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) =>
          Transform.scale(scale: 1 + math.sin(_c.value * math.pi) * 0.25, child: child),
      child: widget.child,
    );
  }
}

// ---------- Цепочка и «удар по боссу» ----------

/// Плашка «Цепочка завершена»: шаги загораются по очереди, корона
/// большой цели вздрагивает. [chain] — названия выполненных по цепочке целей.
void showChainBurst(BuildContext context, List<String> chain) {
  if (chain.isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ChainBurst(chain: chain, animate: motionAllowed(context), onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _ChainBurst extends StatefulWidget {
  const _ChainBurst({required this.chain, required this.animate, required this.onDone});

  final List<String> chain;
  final bool animate;
  final VoidCallback onDone;

  @override
  State<_ChainBurst> createState() => _ChainBurstState();
}

class _ChainBurstState extends State<_ChainBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RqColors.p;
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.82),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = widget.animate ? _c.value : 0.6;
              final appear = Curves.easeOutBack.transform((t / 0.15).clamp(0.0, 1.0));
              final fade = t < 0.85 ? 1.0 : (1 - (t - 0.85) / 0.15);
              return Opacity(
                opacity: fade.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, -30 * (1 - appear)),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
                      width: 320,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(p.radius),
                        border: Border.all(color: p.playful ? p.gold : p.highlightBorder, width: p.playful ? 3 : 1),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 6))],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 44,
                            child: CustomPaint(
                              size: const Size(288, 44),
                              painter: _ChainPainter(t, math.min(4, widget.chain.length + 2), p.xp, p.track, p.gold),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Цепочка завершена: ${widget.chain.last}',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: p.ink),
                          ),
                          if (widget.chain.length > 1)
                            Text(
                              widget.chain.join(' → '),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: p.inkSoft),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ChainPainter extends CustomPainter {
  _ChainPainter(this.t, this.steps, this.on, this.off, this.gold);

  final double t;
  final int steps;
  final Color on;
  final Color off;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final bossX = size.width - 24;
    final gap = (bossX - 16) / steps;
    // Шаг i загорается в момент 0.12 + i·0.1, «босс» — после всех шагов.
    double lit(int i) => ((t - 0.12 - i * 0.1) / 0.08).clamp(0.0, 1.0);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(16, y - 3, bossX, y + 3), const Radius.circular(3)), Paint()..color = off);
    for (var i = 0; i < steps; i++) {
      final x = 16 + i * gap;
      final l = lit(i);
      canvas.drawRect(Rect.fromLTRB(x, y - 3, x + gap * lit(i + 1).clamp(0.0, 1.0), y + 3), Paint()..color = on);
      final r = 11 * (1 + math.sin(l * math.pi) * 0.25);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = Color.lerp(Colors.white, on, l)!);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = Color.lerp(off, on, l)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    final hit = ((t - 0.12 - steps * 0.1) / 0.2).clamp(0.0, 1.0);
    final shake = math.sin(hit * math.pi * 4) * 0.18 * (1 - hit);
    final scale = 1 + math.sin(hit * math.pi) * 0.2;
    canvas.save();
    canvas.translate(bossX, y);
    canvas.rotate(shake);
    canvas.scale(scale);
    final box = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 40, height: 40), const Radius.circular(11));
    canvas.drawRRect(box.shift(const Offset(0, 3)), Paint()..color = Color.lerp(gold, Colors.black, 0.15)!);
    canvas.drawRRect(box, Paint()..color = gold);
    canvas.drawPath(crownPath(Rect.fromCenter(center: Offset.zero, width: 24, height: 20)), Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChainPainter old) => old.t != t;
}
