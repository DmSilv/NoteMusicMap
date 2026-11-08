/// Treinador: analisa o histórico de escalas e devolve orientações em
/// português, como "Suas notas Mi estão ficando baixas: tente colocá-las um
/// pouco mais altas".
///
/// É uma análise por regras (estatística sobre as suas execuções), feita
/// inteiramente no aparelho: funciona offline, não envia nada e dá sempre a
/// mesma resposta para os mesmos dados. Não é um modelo de linguagem.
/// [buildAiPrompt] monta um resumo opcional para quem quiser pedir uma
/// conversa mais livre a uma IA de sua escolha.
library;

import 'dart:math' as math;

import 'tuning.dart';

class StepRecord {
  final int midi;
  final bool ascending;
  final int octaveIndex;

  /// Desvio médio em cents; null = nota pulada.
  final double? cents;
  const StepRecord(this.midi, this.ascending, this.octaveIndex, this.cents);

  Map<String, dynamic> toJson() => {
        'm': midi,
        'a': ascending ? 1 : 0,
        'o': octaveIndex,
        'c': cents == null ? null : double.parse(cents!.toStringAsFixed(2)),
      };

  factory StepRecord.fromJson(Map<String, dynamic> j) => StepRecord(
        (j['m'] as num).toInt(),
        j['a'] == 1,
        (j['o'] as num?)?.toInt() ?? 0,
        (j['c'] as num?)?.toDouble(),
      );
}

/// Quem executou o exercício: o próprio dono do perfil ou o aparelho do
/// professor (aula). Hoje só marca a origem; no futuro decide o vínculo.
const String kOriginSelf = 'self';
const String kOriginTeacherDevice = 'teacher_device';

/// Id estável para sessões antigas (sem id): mesma data e título → mesmo id em
/// qualquer aparelho, então reenviar não duplica. Só aritmética pequena (web).
String legacySessionId(DateTime date, String title) {
  var h = 7;
  for (final c in title.codeUnits) {
    h = (h * 31 + c) % 2147483647;
  }
  return 'L${date.microsecondsSinceEpoch.toRadixString(36)}-${h.toRadixString(36)}';
}

class SessionRecord {
  /// Identificador único e permanente (UUID v4; "L…" nas sessões antigas).
  /// A sessão nunca é editada depois de salva, só acrescentada: por isso o id
  /// torna a sincronização futura idempotente.
  final String id;
  final String origin;
  final DateTime date;

  /// Ex.: "Sol maior · 2 oitavas".
  final String title;
  final int octaves;
  final double zone;
  final double accuracy; // 0..1
  final double meanAbsCents;
  final List<StepRecord> steps;

  SessionRecord({
    String? id,
    this.origin = kOriginSelf,
    required this.date,
    required this.title,
    required this.octaves,
    required this.zone,
    required this.accuracy,
    required this.meanAbsCents,
    required this.steps,
  }) : id = id ?? legacySessionId(date, title);

  Map<String, dynamic> toJson() => {
        'v': 2,
        'id': id,
        if (origin != kOriginSelf) 'origin': origin,
        'date': date.toIso8601String(),
        'title': title,
        'oct': octaves,
        'zone': zone,
        'acc': double.parse(accuracy.toStringAsFixed(4)),
        'mad': double.parse(meanAbsCents.toStringAsFixed(2)),
        'steps': [for (final s in steps) s.toJson()],
      };

  static SessionRecord? tryFromJson(Map<String, dynamic> j) {
    try {
      if (j['v'] != 2) return null; // formato antigo (relatório simples)
      return SessionRecord(
        id: j['id'] as String?,
        origin: (j['origin'] as String?) ?? kOriginSelf,
        date: DateTime.parse(j['date'] as String),
        title: (j['title'] as String?) ?? 'Escala',
        octaves: (j['oct'] as num?)?.toInt() ?? 1,
        zone: ((j['zone'] as num?) ?? 5).toDouble(),
        accuracy: ((j['acc'] as num?) ?? 0).toDouble(),
        meanAbsCents: ((j['mad'] as num?) ?? 0).toDouble(),
        steps: [
          for (final s in (j['steps'] as List? ?? const []))
            StepRecord.fromJson((s as Map).cast<String, dynamic>())
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

enum InsightKind { good, tip, warn, info }

class Insight {
  final InsightKind kind;
  final String text;

  /// Chave estável (para testes e para não repetir).
  final String key;
  const Insight(this.kind, this.key, this.text);
}

double _mean(Iterable<double> v) =>
    v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

String _fmt(double c) => c.abs().round().toString();

/// Analisa as sessões (da mais recente para a mais antiga) e devolve até
/// [maxInsights] orientações, das mais úteis para as menos.
List<Insight> analyzePractice(
  List<SessionRecord> sessions, {
  int window = 8,
  int maxInsights = 5,
  bool? flats = false,
}) {
  if (sessions.isEmpty) return const [];
  final recent = sessions.take(window).toList();
  final names = namesFor(flats);
  final zone = recent.first.zone;
  final out = <Insight>[];

  final steps = [for (final s in recent) ...s.steps];
  final played = steps.where((s) => s.cents != null).toList();

  // 1) Notas com tendência de ficar baixas ou altas (a regra principal).
  final byPc = <int, List<double>>{};
  for (final s in played) {
    byPc.putIfAbsent(s.midi % 12, () => []).add(s.cents!);
  }
  final biased = <(int, double, int)>[];
  byPc.forEach((pc, v) {
    if (v.length < 3) return;
    final m = _mean(v);
    if (m.abs() >= math.max(3.0, zone * 0.6)) biased.add((pc, m, v.length));
  });
  biased.sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
  for (final b in biased.take(3)) {
    final low = b.$2 < 0;
    out.add(Insight(
      InsightKind.warn,
      'bias-${names[b.$1]}',
      'Suas notas ${names[b.$1]} estão ficando ${low ? 'baixas' : 'altas'} '
      '(em média ${low ? '♭' : '♯'}${_fmt(b.$2)}). '
      '${low ? 'Tente colocá-las um pouco mais altas.' : 'Tente colocá-las um pouco mais baixas.'}',
    ));
  }

  // 2) Subida x descida.
  final up = [for (final s in played) if (s.ascending) s.cents!];
  final down = [for (final s in played) if (!s.ascending) s.cents!];
  if (up.length >= 6 && down.length >= 6) {
    final diff = _mean(down) - _mean(up);
    if (diff.abs() >= 4) {
      out.add(Insight(
        InsightKind.tip,
        'dir',
        'Na descida suas notas ficam mais ${diff < 0 ? 'baixas' : 'altas'} do que na '
        'subida (diferença de ${_fmt(diff)}). Ouça a escala descendo com a mesma atenção da subida.',
      ));
    }
  }

  // 3) Registro: oitava mais aguda x mais grave.
  final multi = recent.where((s) => s.octaves >= 2).toList();
  if (multi.isNotEmpty) {
    final lowOct = <double>[], highOct = <double>[];
    for (final s in multi) {
      for (final st in s.steps) {
        if (st.cents == null) continue;
        if (st.octaveIndex == 0) lowOct.add(st.cents!);
        if (st.octaveIndex >= s.octaves - 1) highOct.add(st.cents!);
      }
    }
    if (lowOct.length >= 5 && highOct.length >= 5) {
      final diff = _mean(highOct) - _mean(lowOct);
      if (diff.abs() >= 4) {
        out.add(Insight(
          InsightKind.tip,
          'register',
          'Nas oitavas mais agudas você tende a ficar mais ${diff < 0 ? 'baixo' : 'alto'} '
          '(${_fmt(diff)} de diferença). Confira a posição da mão e o peso do arco ali.',
        ));
      }
    }
  }

  // 4) Cansaço: o desvio cresce da primeira para a segunda metade.
  final drifts = <double>[];
  for (final s in recent) {
    final v = [for (final st in s.steps) if (st.cents != null) st.cents!.abs()];
    if (v.length < 8) continue;
    final h = v.length ~/ 2;
    drifts.add(_mean(v.sublist(h)) - _mean(v.sublist(0, h)));
  }
  if (drifts.length >= 2 && _mean(drifts) >= 3) {
    out.add(const Insight(
      InsightKind.tip,
      'drift',
      'Seu desvio costuma aumentar no fim da escala. Pode ser cansaço ou pressa: '
      'faça pausas curtas e relaxe a mão esquerda.',
    ));
  }

  // 5) Notas puladas.
  final skipped = steps.where((s) => s.cents == null).length;
  if (steps.isNotEmpty && skipped / steps.length >= 0.15) {
    out.add(const Insight(
      InsightKind.tip,
      'skipped',
      'Você pulou várias notas. Diminua a velocidade e toque cada nota até o app marcá-la.',
    ));
  }

  // 6) Tendência: últimas 3 sessões contra as 3 anteriores.
  if (sessions.length >= 4) {
    final last = sessions.take(3).map((s) => s.accuracy * 100);
    final prev = sessions.skip(3).take(3).map((s) => s.accuracy * 100);
    final d = _mean(last) - _mean(prev);
    if (d >= 5) {
      out.add(Insight(InsightKind.good, 'trend-up',
          'Você está evoluindo: +${d.round()} pontos de acerto nas últimas sessões. Continue assim!'));
    } else if (d <= -5) {
      out.add(Insight(InsightKind.info, 'trend-down',
          'Seu acerto caiu ${d.abs().round()} pontos nas últimas sessões. '
          'Tente tocar mais devagar e descansar entre as escalas.'));
    }
  }

  // 7) Elogio e nota mais difícil.
  final latest = sessions.first;
  if (latest.accuracy >= 0.9) {
    out.add(const Insight(InsightKind.good, 'excellent',
        'Excelente: mais de 90% das notas afinadas na última escala.'));
  }
  if (biased.isEmpty && byPc.isNotEmpty) {
    final hard = byPc.entries
        .where((e) => e.value.length >= 3)
        .map((e) => (e.key, _mean(e.value.map((x) => x.abs()))))
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    if (hard.isNotEmpty && hard.first.$2 > zone) {
      out.add(Insight(InsightKind.info, 'hardest',
          'A nota mais difícil para você é ${names[hard.first.$1]} '
          '(desvio médio de ${_fmt(hard.first.$2)}). Vale treiná-la sozinha, devagar.'));
    }
  }

  if (out.isEmpty) {
    out.add(const Insight(InsightKind.info, 'none',
        'Ainda não vejo um padrão claro. Faça mais algumas escalas e as orientações aparecem aqui.'));
  }

  // Ordem: avisos, dicas, informações, elogios.
  const rank = {InsightKind.warn: 0, InsightKind.tip: 1, InsightKind.info: 2, InsightKind.good: 3};
  out.sort((a, b) => rank[a.kind]!.compareTo(rank[b.kind]!));
  return out.take(maxInsights).toList();
}

/// Resumo em texto para colar numa IA de conversa (opcional). Só inclui
/// números agregados; nenhum áudio.
String buildAiPrompt(
  List<SessionRecord> sessions, {
  String instrument = 'instrumento de cordas',
  bool? flats = false,
}) {
  final names = namesFor(flats);
  final recent = sessions.take(10).toList();
  final b = StringBuffer()
    ..writeln('Sou instrumentista ($instrument) e pratico escalas e arpejos com um afinador que mede o desvio de cada nota em cents (♯ = agudo, ♭ = grave; 100 cents = 1 semitom).')
    ..writeln('Analise meus resultados e monte a orientação no formato combinado (visão geral, o que os números mostram, causas prováveis, plano de estudo e exercício para amanhã).')
    ..writeln();
  if (recent.isEmpty) {
    b.writeln('(ainda não há sessões registradas)');
    return b.toString();
  }
  b.writeln('Sessões (da mais recente para a mais antiga):');
  for (final s in recent) {
    final skipped = s.steps.where((x) => x.cents == null).length;
    b.writeln('- ${s.title}: ${(s.accuracy * 100).round()}% das notas afinadas (faixa de afinada ±${s.zone.round()}), '
        'desvio médio ${s.meanAbsCents.toStringAsFixed(1)} cents${skipped > 0 ? ', $skipped nota(s) puladas' : ''}.');
  }

  // Tendência: a sessão mais recente contra a mais antiga da lista.
  if (recent.length >= 2) {
    final d = (recent.first.accuracy - recent.last.accuracy) * 100;
    b
      ..writeln()
      ..writeln('Tendência: ${d >= 0 ? 'subiu' : 'caiu'} ${d.abs().round()} pontos percentuais entre a sessão mais antiga e a mais recente listadas.');
  }

  // Subindo × descendo e por oitava do exercício.
  final up = <double>[], down = <double>[];
  final byOct = <int, List<double>>{};
  for (final s in recent) {
    for (final st in s.steps) {
      final c = st.cents;
      if (c == null) continue;
      (st.ascending ? up : down).add(c);
      byOct.putIfAbsent(st.octaveIndex, () => []).add(c);
    }
  }
  if (up.isNotEmpty && down.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Desvio médio subindo: ${_mean(up).toStringAsFixed(1)} cents; descendo: ${_mean(down).toStringAsFixed(1)} cents.');
  }
  if (byOct.length > 1) {
    final ks = byOct.keys.toList()..sort();
    b.writeln('Desvio médio por oitava do exercício (0 = a mais grave): ${[
      for (final k in ks) '$k: ${_mean(byOct[k]!).toStringAsFixed(1)}'
    ].join('; ')}.');
  }

  final byPc = <int, List<double>>{};
  for (final s in recent) {
    for (final st in s.steps) {
      if (st.cents != null) byPc.putIfAbsent(st.midi % 12, () => []).add(st.cents!);
    }
  }
  b
    ..writeln()
    ..writeln('Desvio médio por nota (cents; negativo = grave, positivo = agudo):');
  final keys = byPc.keys.toList()..sort();
  for (final k in keys) {
    final v = byPc[k]!;
    b.writeln('- ${names[k]}: ${_mean(v).toStringAsFixed(1)} (${v.length} leituras)');
  }

  // Observações que o próprio app já calculou (regras do treinador).
  final tips = analyzePractice(sessions, flats: flats);
  if (tips.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Observações automáticas do app (use como pistas, sem repetir palavra por palavra):');
    for (final t in tips.take(5)) {
      b.writeln('- ${t.text}');
    }
  }
  return b.toString();
}
