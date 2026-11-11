import 'dart:math' as math;

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
    // Botões mais "quadrados" (cantos de 8 px em vez de pílula/círculo): ficam mais
    // fáceis de ver e de acertar no celular.
    // Alvo de toque mínimo de 48 px (design system).
    filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(shape: _squareShape, minimumSize: WidgetStateProperty.all(const Size(64, 48)))),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(shape: _squareShape, minimumSize: WidgetStateProperty.all(const Size(64, 48)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(shape: _squareShape, minimumSize: WidgetStateProperty.all(const Size(64, 48)))),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(shape: _squareShape)),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(shape: _squareShape)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.2),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        shape: _squareShape,
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

/// Forma dos botões: retângulo de cantos pouco arredondados.
final WidgetStateProperty<OutlinedBorder> _squareShape = WidgetStateProperty.all(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)));

/// Cor para um desvio em cents. [zone] = meia-largura da faixa "afinada".
Color intonationColor(double cents, double zone) {
  final a = cents.abs();
  if (a <= zone) {
    // dentro da zona: verde, levemente mais claro no centro exato
    return Color.lerp(AppColors.inTune, AppColors.inTuneBright, 1 - a / zone)!;
  }
  // Fora da zona: três famílias de cor fáceis de ler e degraus bem marcados, em vez de um
  // degradê com muitos matizes. Grave = azuis (claro → médio → escuro); agudo = amarelo →
  // laranja → vermelho-alaranjado. Quanto mais longe, mais forte. Cada degrau tem um
  // trecho firme (plateau) e uma transição curta, para a cor não oscilar entre leituras.
  final u = a / zone; // 1 = borda da zona afinada
  final steps = cents < 0 ? _flatSteps : _sharpSteps;
  const from = [1.0, 1.9, 3.2]; // onde começa a transição para cada degrau
  const width = [0.18, 0.3, 0.4]; // largura da transição
  var c = AppColors.inTune;
  for (var i = 0; i < 3; i++) {
    final t = ((u - from[i]) / width[i]).clamp(0.0, 1.0);
    final sm = t * t * (3 - 2 * t);
    if (sm > 0) c = Color.lerp(c, steps[i], sm)!;
  }
  return c;
}

const _flatSteps = [Color(0xFF8FBCEB), Color(0xFF3E86E0), Color(0xFF1C47B5)];
const _sharpSteps = [Color(0xFFF4C46C), Color(0xFFF08A24), Color(0xFFD2401D)];

/// Desvio em notação musical: ♯ = agudo (acima), ♭ = grave (abaixo).
/// O número é quantos centésimos de semitom faltam para a nota ideal.
String fmtCents(double c) {
  final r = c.round();
  if (r == 0) return '0';
  return r > 0 ? '♯$r' : '♭${-r}';
}

/// Diferença em Hz entre o som medido e a nota ideal, a partir do desvio em
/// cents e da frequência alvo (positivo = agudo).
double hzOff(double cents, double targetHz) => targetHz * (math.pow(2, cents / 1200) - 1);

/// "+1,8 Hz" / "−2,1 Hz" (vírgula decimal, sinal tipográfico).
String fmtHz(double hz) {
  final r = (hz * 10).round() / 10;
  if (r == 0) return '0 Hz';
  final s = r.abs().toStringAsFixed(1).replaceAll('.', ',');
  return '${r > 0 ? '+' : '−'}$s Hz';
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
