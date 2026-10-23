import 'package:flutter/material.dart';

import 'models/models.dart';

/// Набор цветов, шрифтов и форм для одной темы оформления.
///
/// Игровые темы («Сказка», «Лагуна») — сочные цвета, крупные скругления,
/// объёмные кнопки. Взрослые («Графит», «Полночь») — сдержанная палитра,
/// строгая типографика PT Sans / PT Serif, плоские карточки.
class RqPalette {
  const RqPalette({
    required this.skin,
    required this.brightness,
    required this.playful,
    required this.fontBody,
    required this.fontDisplay,
    required this.radius,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.doneSurface,
    required this.line,
    required this.ink,
    required this.inkSoft,
    required this.primary,
    required this.primaryDark,
    required this.onAccent,
    required this.gold,
    required this.xp,
    required this.xpDark,
    required this.coin,
    required this.danger,
    required this.track,
    required this.disabled,
    required this.heroGradient,
    required this.highlightBg,
    required this.highlightBorder,
    required this.warnBg,
    required this.warnBorder,
    required this.tintCard,
    required this.tintCardBorder,
    required this.tiers,
    required this.stats,
  });

  final AppSkin skin;
  final Brightness brightness;
  final bool playful;
  final String fontBody;
  final String fontDisplay;
  final double radius;

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color doneSurface;
  final Color line;
  final Color ink;
  final Color inkSoft;
  final Color primary;
  final Color primaryDark;

  /// Цвет текста на цветных кнопках.
  final Color onAccent;
  final Color gold;
  final Color xp;
  final Color xpDark;
  final Color coin;
  final Color danger;
  final Color track;
  final Color disabled;
  final List<Color> heroGradient;
  final Color highlightBg;
  final Color highlightBorder;
  final Color warnBg;
  final Color warnBorder;
  final Color tintCard;
  final Color tintCardBorder;
  final Map<GoalTier, Color> tiers;
  final Map<HeroStat, Color> stats;

  bool get dark => brightness == Brightness.dark;

  static RqPalette of(AppSkin skin) => switch (skin) {
        AppSkin.fairy || AppSkin.auto => fairy,
        AppSkin.lagoon => lagoon,
        AppSkin.graphite => graphite,
        AppSkin.midnight => midnight,
        AppSkin.forest => forest,
        AppSkin.bordeaux => bordeaux,
        AppSkin.espresso => espresso,
      };

  // ---------- Игровые темы ----------

  static const fairy = RqPalette(
    skin: AppSkin.fairy,
    brightness: Brightness.light,
    playful: true,
    fontBody: 'Nunito',
    fontDisplay: 'Nunito',
    radius: 22,
    background: Color(0xFFFFF8EE),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFFFCF6),
    doneSurface: Color(0xFFFBFFF9),
    line: Color(0xFFEDE3D3),
    ink: Color(0xFF2B2140),
    inkSoft: Color(0xFF7A7090),
    primary: Color(0xFF6C4CF5),
    primaryDark: Color(0xFF4B2FCC),
    onAccent: Color(0xFFFFFFFF),
    gold: Color(0xFFFFB300),
    xp: Color(0xFF29C46A),
    xpDark: Color(0xFF1C9A50),
    coin: Color(0xFFF2A100),
    danger: Color(0xFFFF5C6C),
    track: Color(0xFFF1EBE0),
    disabled: Color(0xFFCFC7DA),
    heroGradient: [Color(0xFF7B5CFF), Color(0xFF5A3BE6)],
    highlightBg: Color(0xFFFFF6DB),
    highlightBorder: Color(0xFFFFD873),
    warnBg: Color(0xFFFFF4EC),
    warnBorder: Color(0xFFFFC9A8),
    tintCard: Color(0xFFF1ECFF),
    tintCardBorder: Color(0xFFCFC2FF),
    tiers: {
      GoalTier.legend: Color(0xFFFFB300),
      GoalTier.epic: Color(0xFF9A5CF7),
      GoalTier.quest: Color(0xFF2F8CFF),
      GoalTier.task: Color(0xFF29C46A),
      GoalTier.daily: Color(0xFFFF7A59),
    },
    stats: {
      HeroStat.strength: Color(0xFFFF5C6C),
      HeroStat.intellect: Color(0xFF2F8CFF),
      HeroStat.charisma: Color(0xFFFF9F1C),
      HeroStat.mastery: Color(0xFF29C46A),
    },
  );

  static const lagoon = RqPalette(
    skin: AppSkin.lagoon,
    brightness: Brightness.light,
    playful: true,
    fontBody: 'Nunito',
    fontDisplay: 'Nunito',
    radius: 22,
    background: Color(0xFFEFFBF8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF6FEFC),
    doneSurface: Color(0xFFF4FFF8),
    line: Color(0xFFD3EDE6),
    ink: Color(0xFF13343B),
    inkSoft: Color(0xFF5B7C82),
    primary: Color(0xFF00A3A3),
    primaryDark: Color(0xFF007A7E),
    onAccent: Color(0xFFFFFFFF),
    gold: Color(0xFFFF9F1C),
    xp: Color(0xFF3BB273),
    xpDark: Color(0xFF2A8A57),
    coin: Color(0xFFF29100),
    danger: Color(0xFFFF5A5F),
    track: Color(0xFFE2F3EF),
    disabled: Color(0xFFC5DAD6),
    heroGradient: [Color(0xFF12C2B5), Color(0xFF0A8F9E)],
    highlightBg: Color(0xFFFFF3D6),
    highlightBorder: Color(0xFFFFD27A),
    warnBg: Color(0xFFFFF1EA),
    warnBorder: Color(0xFFFFC4A3),
    tintCard: Color(0xFFE3F7F4),
    tintCardBorder: Color(0xFFA9E2D9),
    tiers: {
      GoalTier.legend: Color(0xFFFF9F1C),
      GoalTier.epic: Color(0xFF7B61FF),
      GoalTier.quest: Color(0xFF1E88E5),
      GoalTier.task: Color(0xFF3BB273),
      GoalTier.daily: Color(0xFFFF6B6B),
    },
    stats: {
      HeroStat.strength: Color(0xFFFF6B6B),
      HeroStat.intellect: Color(0xFF1E88E5),
      HeroStat.charisma: Color(0xFFFF9F1C),
      HeroStat.mastery: Color(0xFF3BB273),
    },
  );

  // ---------- Взрослые темы ----------

  static const graphite = RqPalette(
    skin: AppSkin.graphite,
    brightness: Brightness.light,
    playful: false,
    fontBody: 'PTSans',
    fontDisplay: 'PTSerif',
    radius: 14,
    background: Color(0xFFF5F4F1),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFAF9F7),
    doneSurface: Color(0xFFF7FAF8),
    line: Color(0xFFE3E0DA),
    ink: Color(0xFF1E2226),
    inkSoft: Color(0xFF6B7178),
    primary: Color(0xFF24364B),
    primaryDark: Color(0xFF172433),
    onAccent: Color(0xFFFFFFFF),
    gold: Color(0xFFB8893B),
    xp: Color(0xFF3E8E63),
    xpDark: Color(0xFF2E6E4B),
    coin: Color(0xFFB8893B),
    danger: Color(0xFFC2483D),
    track: Color(0xFFECE9E3),
    disabled: Color(0xFFC9CCD1),
    heroGradient: [Color(0xFF2A3D54), Color(0xFF1B2838)],
    highlightBg: Color(0xFFF7F1E4),
    highlightBorder: Color(0xFFE2D2AE),
    warnBg: Color(0xFFFBF1EC),
    warnBorder: Color(0xFFE8C9B8),
    tintCard: Color(0xFFEEF1F5),
    tintCardBorder: Color(0xFFCBD3DD),
    tiers: {
      GoalTier.legend: Color(0xFFB8893B),
      GoalTier.epic: Color(0xFF6B5B95),
      GoalTier.quest: Color(0xFF3F6E9C),
      GoalTier.task: Color(0xFF4E8C6A),
      GoalTier.daily: Color(0xFFB5654A),
    },
    stats: {
      HeroStat.strength: Color(0xFFB5554B),
      HeroStat.intellect: Color(0xFF3F6E9C),
      HeroStat.charisma: Color(0xFFC08A3E),
      HeroStat.mastery: Color(0xFF4E8C6A),
    },
  );

  static const midnight = RqPalette(
    skin: AppSkin.midnight,
    brightness: Brightness.dark,
    playful: false,
    fontBody: 'PTSans',
    fontDisplay: 'PTSerif',
    radius: 14,
    background: Color(0xFF121417),
    surface: Color(0xFF1B1E23),
    surfaceAlt: Color(0xFF20242A),
    doneSurface: Color(0xFF1A2420),
    line: Color(0xFF2C3138),
    ink: Color(0xFFECEDEF),
    inkSoft: Color(0xFF9BA1A9),
    primary: Color(0xFF8FA8C8),
    primaryDark: Color(0xFF5F7898),
    onAccent: Color(0xFF111418),
    gold: Color(0xFFD4AF6A),
    xp: Color(0xFF6BBF8E),
    xpDark: Color(0xFF8FD6AC),
    coin: Color(0xFFD4AF6A),
    danger: Color(0xFFE07A6F),
    track: Color(0xFF2A2E35),
    disabled: Color(0xFF3A3F47),
    heroGradient: [Color(0xFF2B3442), Color(0xFF1A1F27)],
    highlightBg: Color(0xFF2A2519),
    highlightBorder: Color(0xFF5A4A28),
    warnBg: Color(0xFF2C211D),
    warnBorder: Color(0xFF5C3D30),
    tintCard: Color(0xFF1F2631),
    tintCardBorder: Color(0xFF34404F),
    tiers: {
      GoalTier.legend: Color(0xFFD4AF6A),
      GoalTier.epic: Color(0xFFA593D6),
      GoalTier.quest: Color(0xFF7FA7D6),
      GoalTier.task: Color(0xFF7CC09A),
      GoalTier.daily: Color(0xFFE09A7A),
    },
    stats: {
      HeroStat.strength: Color(0xFFE08A80),
      HeroStat.intellect: Color(0xFF7FA7D6),
      HeroStat.charisma: Color(0xFFE0B26A),
      HeroStat.mastery: Color(0xFF7CC09A),
    },
  );

  // ---------- Взрослые темы v0.5 ----------

  /// «Хвоя» — строгая светлая, глубокий зелёный и бронза.
  static const forest = RqPalette(
    skin: AppSkin.forest,
    brightness: Brightness.light,
    playful: false,
    fontBody: 'PTSans',
    fontDisplay: 'PTSerif',
    radius: 12,
    background: Color(0xFFF2F4F0),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF8FAF6),
    doneSurface: Color(0xFFF3F8F3),
    line: Color(0xFFDDE3DA),
    ink: Color(0xFF1C2620),
    inkSoft: Color(0xFF66726A),
    primary: Color(0xFF2E5A43),
    primaryDark: Color(0xFF1E3F2E),
    onAccent: Color(0xFFFFFFFF),
    gold: Color(0xFFA8823A),
    xp: Color(0xFF3F8A5A),
    xpDark: Color(0xFF2D6A44),
    coin: Color(0xFFA8823A),
    danger: Color(0xFFB8483E),
    track: Color(0xFFE6EBE3),
    disabled: Color(0xFFC6CEC6),
    heroGradient: [Color(0xFF2F5E46), Color(0xFF1C3B2B)],
    highlightBg: Color(0xFFF4F0E2),
    highlightBorder: Color(0xFFDCCFA6),
    warnBg: Color(0xFFF8EFEA),
    warnBorder: Color(0xFFE4C7B6),
    tintCard: Color(0xFFEAF1EC),
    tintCardBorder: Color(0xFFC3D5C8),
    tiers: {
      GoalTier.legend: Color(0xFFA8823A),
      GoalTier.epic: Color(0xFF5E6B9A),
      GoalTier.quest: Color(0xFF3B7088),
      GoalTier.task: Color(0xFF4A8A5E),
      GoalTier.daily: Color(0xFFAE6A48),
    },
    stats: {
      HeroStat.strength: Color(0xFFAE5548),
      HeroStat.intellect: Color(0xFF3B7088),
      HeroStat.charisma: Color(0xFFB98A3E),
      HeroStat.mastery: Color(0xFF4A8A5E),
    },
  );

  /// «Бордо» — деловая светлая с винным акцентом.
  static const bordeaux = RqPalette(
    skin: AppSkin.bordeaux,
    brightness: Brightness.light,
    playful: false,
    fontBody: 'PTSans',
    fontDisplay: 'PTSerif',
    radius: 10,
    background: Color(0xFFF7F3F2),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFBF8F7),
    doneSurface: Color(0xFFF6F8F5),
    line: Color(0xFFE6DDDA),
    ink: Color(0xFF241B1D),
    inkSoft: Color(0xFF75686A),
    primary: Color(0xFF7A2E3A),
    primaryDark: Color(0xFF581F29),
    onAccent: Color(0xFFFFFFFF),
    gold: Color(0xFFB08A4A),
    xp: Color(0xFF4C8A62),
    xpDark: Color(0xFF376A49),
    coin: Color(0xFFB08A4A),
    danger: Color(0xFFC0392B),
    track: Color(0xFFEEE7E5),
    disabled: Color(0xFFD1C8C7),
    heroGradient: [Color(0xFF7E3340), Color(0xFF4E1C25)],
    highlightBg: Color(0xFFF8F0E4),
    highlightBorder: Color(0xFFE3D0AE),
    warnBg: Color(0xFFFBEEEB),
    warnBorder: Color(0xFFEBC6BE),
    tintCard: Color(0xFFF5EBEC),
    tintCardBorder: Color(0xFFDDC2C6),
    tiers: {
      GoalTier.legend: Color(0xFFB08A4A),
      GoalTier.epic: Color(0xFF7A2E3A),
      GoalTier.quest: Color(0xFF3E5F8A),
      GoalTier.task: Color(0xFF4C8A62),
      GoalTier.daily: Color(0xFFB4683E),
    },
    stats: {
      HeroStat.strength: Color(0xFFA9463E),
      HeroStat.intellect: Color(0xFF3E5F8A),
      HeroStat.charisma: Color(0xFFB08A4A),
      HeroStat.mastery: Color(0xFF4C8A62),
    },
  );

  /// «Эспрессо» — тёмная тёплая, для вечера.
  static const espresso = RqPalette(
    skin: AppSkin.espresso,
    brightness: Brightness.dark,
    playful: false,
    fontBody: 'PTSans',
    fontDisplay: 'PTSerif',
    radius: 14,
    background: Color(0xFF17130F),
    surface: Color(0xFF221C17),
    surfaceAlt: Color(0xFF29221C),
    doneSurface: Color(0xFF1E231B),
    line: Color(0xFF3A3029),
    ink: Color(0xFFF1E9E1),
    inkSoft: Color(0xFFB0A397),
    primary: Color(0xFFD2A679),
    primaryDark: Color(0xFFA57B52),
    onAccent: Color(0xFF1A140F),
    gold: Color(0xFFE0B46E),
    xp: Color(0xFF8CC49A),
    xpDark: Color(0xFFA9D9B4),
    coin: Color(0xFFE0B46E),
    danger: Color(0xFFE5806F),
    track: Color(0xFF342B24),
    disabled: Color(0xFF4A4038),
    heroGradient: [Color(0xFF3A2C22), Color(0xFF211A14)],
    highlightBg: Color(0xFF2E2619),
    highlightBorder: Color(0xFF5E4C2C),
    warnBg: Color(0xFF30221D),
    warnBorder: Color(0xFF603F33),
    tintCard: Color(0xFF2A231D),
    tintCardBorder: Color(0xFF473A30),
    tiers: {
      GoalTier.legend: Color(0xFFE0B46E),
      GoalTier.epic: Color(0xFFB79AD0),
      GoalTier.quest: Color(0xFF8DB2D6),
      GoalTier.task: Color(0xFF8CC49A),
      GoalTier.daily: Color(0xFFE39E7C),
    },
    stats: {
      HeroStat.strength: Color(0xFFE5907F),
      HeroStat.intellect: Color(0xFF8DB2D6),
      HeroStat.charisma: Color(0xFFE0B46E),
      HeroStat.mastery: Color(0xFF8CC49A),
    },
  );
}

/// Доступ к цветам текущей темы. Тема выбирается по активному герою
/// (см. [RodquestApp]); при смене темы всё дерево виджетов перестраивается.
class RqColors {
  const RqColors._();

  static RqPalette p = RqPalette.fairy;

  static bool get playful => p.playful;
  static Color get background => p.background;
  static Color get surface => p.surface;
  static Color get surfaceAlt => p.surfaceAlt;
  static Color get doneSurface => p.doneSurface;
  static Color get ink => p.ink;
  static Color get inkSoft => p.inkSoft;
  static Color get line => p.line;
  static Color get primary => p.primary;
  static Color get primaryDark => p.primaryDark;
  static Color get onAccent => p.onAccent;
  static Color get gold => p.gold;
  static Color get xp => p.xp;
  static Color get xpDark => p.xpDark;
  static Color get coin => p.coin;
  static Color get danger => p.danger;
  static Color get track => p.track;
  static Color get disabled => p.disabled;

  static Color tier(GoalTier t) => p.tiers[t]!;
  static Color stat(HeroStat s) => p.stats[s]!;

  /// Более тёмный оттенок — для «объёмной» тени кнопок и карточек.
  static Color shade(Color c, [double amount = 0.22]) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  /// Насыщенный вариант цвета для текста на светлой/тёмной подложке.
  static Color strong(Color c) {
    final hsl = HSLColor.fromColor(c);
    final l = p.dark ? hsl.lightness + 0.12 : hsl.lightness - 0.12;
    return hsl.withLightness(l.clamp(0.0, 1.0)).toColor();
  }

  static Color tint(Color c, [double alpha = 0.14]) => c.withValues(alpha: alpha);
}

ThemeData buildTheme([RqPalette? palette]) {
  final p = palette ?? RqColors.p;
  final font = p.fontBody;
  final display = p.fontDisplay;
  final heavy = p.playful ? FontWeight.w900 : FontWeight.w700;
  final bold = p.playful ? FontWeight.w800 : FontWeight.w700;
  final body = p.playful ? FontWeight.w600 : FontWeight.w400;
  final r = p.radius;
  final scheme = ColorScheme.fromSeed(
    seedColor: p.primary,
    primary: p.primary,
    onPrimary: p.onAccent,
    surface: p.surface,
    onSurface: p.ink,
    error: p.danger,
    brightness: p.brightness,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: font,
    brightness: p.brightness,
  );
  final text = base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink);
  final fieldRadius = BorderRadius.circular(p.playful ? 16 : 10);
  final fieldBorderWidth = p.playful ? 2.0 : 1.2;

  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: heavy, fontFamily: display),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: heavy, fontFamily: display),
      titleLarge: text.titleLarge?.copyWith(fontWeight: bold, fontFamily: display),
      titleMedium: text.titleMedium?.copyWith(fontWeight: bold),
      bodyMedium: text.bodyMedium?.copyWith(fontWeight: body),
      bodySmall: text.bodySmall?.copyWith(fontWeight: body, color: p.inkSoft),
      labelLarge: text.labelLarge?.copyWith(fontWeight: bold),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: display,
        fontSize: p.playful ? 24 : 22,
        fontWeight: heavy,
        color: p.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: RqColors.tint(p.primary, p.playful ? 0.16 : 0.12),
      surfaceTintColor: Colors.transparent,
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? p.primary : p.inkSoft,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: font,
          fontWeight: bold,
          fontSize: 12,
          color: states.contains(WidgetState.selected) ? p.primary : p.inkSoft,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: TextStyle(color: p.inkSoft),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: p.line, width: fieldBorderWidth),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: p.line, width: fieldBorderWidth),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: p.primary, width: fieldBorderWidth),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.surface,
      labelStyle: TextStyle(fontFamily: font, fontWeight: bold, color: p.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.playful ? 14 : 8)),
      side: BorderSide(color: p.line, width: p.playful ? 2 : 1),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.dark ? p.surfaceAlt : p.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.playful ? 16 : 10)),
      contentTextStyle: TextStyle(
        fontFamily: font,
        fontWeight: bold,
        color: p.dark ? p.ink : Colors.white,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r + 2)),
    ),
    listTileTheme: ListTileThemeData(textColor: p.ink, iconColor: p.inkSoft),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onAccent : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.primary : null,
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1),
  );
}
