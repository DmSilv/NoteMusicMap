import 'dart:math' as math;

import 'package:afina/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  tearDown(() => AppColors.dark = true);

  test('tema claro suave: fundo e cartões não são brancos puros, mas o texto continua com contraste de sobra', () {
    AppColors.dark = false;
    // brilho: nenhum fundo chega perto do branco puro (que tem luminância 1)
    expect(_lum(AppColors.bg), lessThan(0.78));
    expect(_lum(AppColors.surface), lessThan(0.92));
    // o cartão se destaca do fundo e a borda aparece nos dois
    expect(_contrast(AppColors.surface, AppColors.bg), greaterThan(1.1));
    expect(_contrast(AppColors.outline, AppColors.surface), greaterThan(1.5));
    expect(_contrast(AppColors.outline, AppColors.bg), greaterThan(1.2));
    // leitura: texto 7:1 (AAA), texto apagado 4.5:1 (AA) sobre cartão e sobre fundo
    for (final bg in [AppColors.surface, AppColors.bg, AppColors.surface2]) {
      expect(_contrast(AppColors.text, bg), greaterThan(7));
      expect(_contrast(AppColors.textDim, bg), greaterThan(4.5));
    }
    // as cores da agulha continuam legíveis sobre o cartão
    for (final c in [AppColors.inTune, AppColors.flat, AppColors.sharp]) {
      expect(_contrast(c, AppColors.surface), greaterThan(4.0));
    }
  });

  test('tema escuro não mudou (o painel do administrador usa as mesmas cores)', () {
    AppColors.dark = true;
    expect(AppColors.bg, const Color(0xFF0F1419));
    expect(AppColors.surface, const Color(0xFF171E26));
    expect(AppColors.text, const Color(0xFFE8EEF4));
  });

  test('a folha de baixo lê as cores do tema (trocar claro/escuro com uma folha aberta não deixa o fundo para trás)', () {
    for (final dark in [true, false]) {
      final th = buildTheme(dark: dark);
      expect(th.bottomSheetTheme.backgroundColor, AppColors.surface);
      expect(th.bottomSheetTheme.modalBackgroundColor, AppColors.surface);
    }
  });
}
