import 'package:flutter/material.dart';

/// Paleta do app, com tema escuro e claro.
///
/// As cores que mudam com o tema são `getters` lidos a cada construção de
/// tela. [AppColors.dark] é definido uma vez por troca de tema em `main.dart`
/// (que recria a árvore de widgets com uma chave nova).
///
/// Cores de entonação: azul = grave, verde = afinado, laranja = agudo.
/// Evitam vermelho/verde para ficar legíveis com daltonismo.
class AppColors {
  static bool dark = true;

  static Color get bg => dark ? const Color(0xFF0F1419) : const Color(0xFFF3F6F9);
  static Color get surface => dark ? const Color(0xFF171E26) : const Color(0xFFFFFFFF);
  static Color get surface2 => dark ? const Color(0xFF202A35) : const Color(0xFFE6ECF2);
  static Color get outline => dark ? const Color(0xFF2E3B49) : const Color(0xFFC9D4DE);
  static Color get text => dark ? const Color(0xFFE8EEF4) : const Color(0xFF111B25);
  static Color get textDim => dark ? const Color(0xFF8FA0B1) : const Color(0xFF4C5C6C);

  static Color get inTune => dark ? const Color(0xFF1FE68F) : const Color(0xFF0B7F57);
  static Color get inTuneBright => dark ? const Color(0xFF5CFFB8) : const Color(0xFF1AA676);
  static Color get flat => dark ? const Color(0xFF2E9BFF) : const Color(0xFF1E62BD);
  static Color get sharp => dark ? const Color(0xFFFF9226) : const Color(0xFFB05400);
  static Color get accent => inTune;

  /// Texto/ícone sobre botões na cor de destaque.
  static Color get onAccent => dark ? const Color(0xFF062B1E) : const Color(0xFFFFFFFF);

  /// Texto sobre células coloridas da grade (sempre escuro: as cores são médias).
  static const Color onCell = Color(0xFF0B1116);
}

ThemeData buildTheme({required bool dark}) {
  AppColors.dark = dark;
  final scheme = dark
      ? ColorScheme.dark(
          primary: AppColors.accent,
          onPrimary: AppColors.onAccent,
          surface: AppColors.surface,
          onSurface: AppColors.text,
          secondary: AppColors.flat,
          secondaryContainer: AppColors.accent.withValues(alpha: 0.22),
          onSecondaryContainer: AppColors.text,
          outline: AppColors.outline,
        )
      : ColorScheme.light(
          primary: AppColors.accent,
          onPrimary: AppColors.onAccent,
          surface: AppColors.surface,
          onSurface: AppColors.text,
          secondary: AppColors.flat,
          secondaryContainer: AppColors.accent.withValues(alpha: 0.22),
          onSecondaryContainer: AppColors.text,
          outline: AppColors.outline,
        );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    cardColor: AppColors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.text,
      titleTextStyle:
          TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface2,
      selectedColor: AppColors.accent.withValues(alpha: 0.24),
      side: BorderSide(color: AppColors.outline),
      labelStyle: TextStyle(color: AppColors.text),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.accent.withValues(alpha: 0.24)
                : AppColors.surface2),
        foregroundColor: WidgetStateProperty.all(AppColors.text),
        side: WidgetStateProperty.all(BorderSide(color: AppColors.outline)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accent,
      thumbColor: AppColors.accent,
      inactiveTrackColor: AppColors.outline,
    ),
    dividerColor: AppColors.outline,
    dividerTheme: DividerThemeData(color: AppColors.outline, thickness: 1),
    dialogTheme: DialogThemeData(backgroundColor: AppColors.surface),
    textTheme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
        .textTheme
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text),
  );
}

/// Cor para um desvio em cents. [zone] = meia-largura da faixa "afinada".
Color intonationColor(double cents, double zone) {
  final a = cents.abs();
  if (a <= zone) {
    // dentro da zona: verde, levemente mais claro no centro exato
    return Color.lerp(AppColors.inTune, AppColors.inTuneBright, 1 - a / zone)!;
  }
  // Fora da zona, a cor desliza do verde para azul/laranja. A mistura é feita
  // em HSL (pelo matiz), então azul→verde passa por tons de ciano, sem ficar
  // cinza/"sujo" como ficaria misturando em RGB. A curva suave (smoothstep)
  // evita saltos de cor entre leituras vizinhas.
  final x = ((a - zone) / 16).clamp(0.0, 1.0);
  final smooth = x * x * (3 - 2 * x);
  final t = 0.25 + 0.75 * smooth;
  final end = cents < 0 ? AppColors.flat : AppColors.sharp;
  return HSLColor.lerp(
          HSLColor.fromColor(AppColors.inTune), HSLColor.fromColor(end), t)!
      .toColor();
}

/// Desvio em notação musical: ♯ = agudo (acima), ♭ = grave (abaixo).
/// O número é quantos centésimos de semitom faltam para a nota ideal.
String fmtCents(double c) {
  final r = c.round();
  if (r == 0) return '0';
  return r > 0 ? '♯$r' : '♭${-r}';
}

/// Cor de texto/ícone com melhor contraste sobre [fill] (escuro ou claro).
/// Usada nas células da grade, cujo fundo muda de tom com a afinação.
Color readableOn(Color fill) {
  final l = fill.computeLuminance();
  const darkText = AppColors.onCell;
  const lightText = Color(0xFFF5F8FB);
  final cDark = (l + 0.05) / (darkText.computeLuminance() + 0.05);
  final cLight = (lightText.computeLuminance() + 0.05) / (l + 0.05);
  return cDark >= cLight ? darkText : lightText;
}

/// Garante texto legível sobre uma célula colorida: escolhe texto claro ou
/// escuro e, se mesmo assim o contraste ficar abaixo de [minRatio] (WCAG 4,5
/// para texto pequeno), clareia ou escurece o fundo até atingir.
({Color fill, Color text}) legibleCell(Color fill, {double minRatio = 4.5}) {
  const darkText = AppColors.onCell;
  const lightText = Color(0xFFFFFFFF);
  double cr(Color a, Color b) {
    final x = a.computeLuminance() + 0.05, y = b.computeLuminance() + 0.05;
    return x > y ? x / y : y / x;
  }

  // Azuis e verdes: texto BRANCO fica bem mais agradável do que preto. Escurece
  // um pouco o fundo (até 8 passos) para o branco chegar ao contraste mínimo.
  // Fundos claros demais (verde vivo do tema escuro, amarelos) seguem com texto
  // escuro logo abaixo.
  final hue = HSLColor.fromColor(fill).hue;
  if (hue >= 90 && hue <= 260) {
    var g = fill;
    for (var i = 0; i < 8; i++) {
      if (cr(g, lightText) >= minRatio) return (fill: g, text: lightText);
      final hs = HSLColor.fromColor(g);
      g = hs.withLightness((hs.lightness - 0.02).clamp(0.0, 1.0)).toColor();
    }
  }

  var f = fill;
  for (var i = 0; i < 40; i++) {
    final cd = cr(f, darkText), cl = cr(f, lightText);
    final useDark = cd >= cl;
    if ((useDark ? cd : cl) >= minRatio) {
      return (fill: f, text: useDark ? darkText : lightText);
    }
    // Clareia o fundo se o texto for escuro; escurece se o texto for claro.
    final hsl = HSLColor.fromColor(f);
    final l = (hsl.lightness + (useDark ? 0.02 : -0.02)).clamp(0.0, 1.0);
    f = hsl.withLightness(l).toColor();
  }
  return (fill: f, text: cr(f, darkText) >= cr(f, lightText) ? darkText : lightText);
}
