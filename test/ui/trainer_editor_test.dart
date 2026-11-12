// "Acelerar aos poucos": perguntas simples, botões de escolha e resumo em frase.
import 'package:afina/ui/trainer_editor.dart';
import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<TempoTrainer>> _mostra(WidgetTester tester, TempoTrainer t, {double start = 80}) async {
  final changes = <TempoTrainer>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: TrainerEditor(value: t, startBpm: start, beatsPerBar: 4, onChanged: changes.add),
        ),
      ),
    ),
  );
  return changes;
}

void main() {
  const porTempo = TempoTrainer(everySeconds: 30, stepBpm: 5, maxBpm: 120);

  testWidgets('mostra as perguntas e o resumo em uma frase', (tester) async {
    await _mostra(tester, porTempo);
    expect(find.text('Quando aumentar'), findsOneWidget);
    expect(find.text('Quanto aumentar a cada vez'), findsOneWidget);
    expect(find.text('Até quantos BPM (o teto)'), findsOneWidget);
    expect(find.textContaining('Começa em 80 BPM. A cada 30 segundos sobe 5 BPM, até 120 BPM.'), findsOneWidget);
    expect(find.text('120'), findsOneWidget, reason: 'o teto aparece grande');
  });

  testWidgets('por tempo: escolher 1 minuto', (tester) async {
    final changes = await _mostra(tester, porTempo);
    for (final r in ['15 s', '30 s', '1 min', '2 min']) {
      expect(find.text(r), findsOneWidget, reason: r);
    }
    await tester.tap(find.text('1 min'));
    expect(changes.single.everySeconds, 60);
    expect(changes.single.stepBpm, 5, reason: 'o resto não muda');
  });

  testWidgets('trocar para compassos mostra as opções de compassos', (tester) async {
    final changes = await _mostra(tester, porTempo);
    await tester.tap(find.text('Por compassos'));
    expect(changes.single.byTime, isFalse);
    changes.clear();
    await _mostra(tester, const TempoTrainer(everyBars: 4, stepBpm: 5, maxBpm: 120));
    for (final r in ['2 compassos', '4 compassos', '8 compassos', '16 compassos']) {
      expect(find.text(r), findsOneWidget, reason: r);
    }
    expect(find.text('30 s'), findsNothing);
  });

  testWidgets('trocar para tempo volta com 30 segundos', (tester) async {
    final changes = await _mostra(tester, const TempoTrainer(everyBars: 4, stepBpm: 5, maxBpm: 120));
    await tester.tap(find.text('Por tempo'));
    expect(changes.single.everySeconds, 30);
  });

  testWidgets('quanto aumentar: +10 BPM', (tester) async {
    final changes = await _mostra(tester, porTempo);
    await tester.tap(find.text('+10 BPM'));
    expect(changes.single.stepBpm, 10);
  });

  testWidgets('teto: + e − de 5 em 5 e atalhos a partir do BPM de partida', (tester) async {
    final changes = await _mostra(tester, porTempo);
    await tester.tap(find.byTooltip('Aumentar o teto em 5'));
    expect(changes.last.maxBpm, 125);
    await tester.tap(find.byTooltip('Diminuir o teto em 5'));
    expect(changes.last.maxBpm, 115);
    expect(find.text('120 (+40)'), findsOneWidget, reason: 'atalho: partida 80 + 40');
    await tester.tap(find.text('140 (+60)'));
    expect(changes.last.maxBpm, 140);
  });

  testWidgets('os botões do teto desligam nos limites do metrônomo', (tester) async {
    await _mostra(tester, const TempoTrainer(everySeconds: 30, stepBpm: 5, maxBpm: 320), start: 300);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed, isNull);
    await _mostra(tester, const TempoTrainer(everySeconds: 30, stepBpm: 5, maxBpm: 40), start: 30);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove)).onPressed, isNull);
  });

  testWidgets('teto menor que o BPM de partida: avisa para aumentar o teto', (tester) async {
    await _mostra(tester, const TempoTrainer(everySeconds: 30, stepBpm: 5, maxBpm: 100), start: 120);
    expect(find.textContaining('Aumente o teto'), findsOneWidget);
  });

  testWidgets('um valor fora das opções (dado antigo) aparece como opção também', (tester) async {
    await _mostra(tester, const TempoTrainer(everyBars: 5, stepBpm: 3, maxBpm: 120));
    expect(find.text('5 compassos'), findsOneWidget);
    expect(find.text('+3 BPM'), findsOneWidget);
    final sel = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).where((c) => c.selected).length;
    expect(sel, greaterThanOrEqualTo(2), reason: 'o atual de cada pergunta aparece marcado');
  });
}
