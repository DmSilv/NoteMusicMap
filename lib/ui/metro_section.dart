import 'package:flutter/foundation.dart';

/// Qual visão a aba Metrônomo mostra: 0 = o metrônomo, 1 = estudo e timers (resumo, cronômetro, Pomodoro).
/// Um só valor para o app todo: as pílulas de Pomodoro e relógio da faixa de cima trocam para 1 antes de ir à aba.
final ValueNotifier<int> metroSection = ValueNotifier<int>(0);

const int kMetroSectionMetronome = 0;
const int kMetroSectionStudy = 1;
