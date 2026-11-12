// Modais da agenda (remarcar, trocar, confirmar) e o calendário do mês.
import 'package:afina/ui/agenda_calendar.dart';
import 'package:afina/ui/agenda_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _abre(WidgetTester tester, Future<void> Function(BuildContext) open) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(body: Center(child: ElevatedButton(onPressed: () => open(context), child: const Text('abrir')))),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

FilledButton _botao(WidgetTester tester, String texto) =>
    tester.widget<FilledButton>(find.ancestor(of: find.text(texto), matching: find.byWidgetPredicate((w) => w is FilledButton)));

// Uma aula bem no futuro (o seletor de data só aceita dias a partir de hoje) e longe do fim do mês.
final _from = DateTime(DateTime.now().year + 1, 3, 10, 15, 0);

void main() {
  group('remarcar', () {
    testWidgets('abre sem poder confirmar: ainda é o mesmo horário', (tester) async {
      await _abre(tester, (c) async => showMoveSheet(c, who: 'Ana', from: _from, weekly: true, check: (_) => null, commit: (_) => null));
      expect(find.text('Remarcar esta aula'), findsOneWidget);
      expect(find.textContaining('Ana ·'), findsOneWidget);
      expect(find.text('Escolha outro dia ou outra hora.'), findsOneWidget);
      expect(_botao(tester, 'Remarcar').onPressed, isNull);
      expect(find.textContaining('As outras semanas continuam'), findsOneWidget, reason: 'aula semanal avisa que as outras semanas ficam');
    });

    testWidgets('escolher outro dia mostra de → para e liga o botão; confirmar aplica e devolve o novo horário', (tester) async {
      DateTime? aplicado;
      DateTime? resultado;
      await _abre(tester, (c) async {
        resultado = await showMoveSheet(c, who: 'Ana', from: _from, weekly: false, check: (_) => null, commit: (to) {
          aplicado = to;
          return null;
        });
      });
      await tester.tap(find.text('Dia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('11'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Escolha outro dia ou outra hora.'), findsNothing);
      expect(_botao(tester, 'Remarcar').onPressed, isNotNull);
      expect(find.textContaining('As outras semanas continuam'), findsNothing, reason: 'aula avulsa não fala de semanas');
      await tester.tap(find.text('Remarcar'));
      await tester.pumpAndSettle();
      expect(aplicado, DateTime(_from.year, 3, 11, 15, 0));
      expect(resultado, aplicado);
      expect(find.text('Remarcar esta aula'), findsNothing, reason: 'o modal fecha');
    });

    testWidgets('horário que choca: mostra o motivo, não deixa confirmar e nada é aplicado', (tester) async {
      var aplicou = false;
      await _abre(tester, (c) async => showMoveSheet(c, who: 'Ana', from: _from, weekly: false, check: (_) => 'Choca com a aula de Bia.', commit: (_) {
            aplicou = true;
            return null;
          }));
      await tester.tap(find.text('Dia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('11'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Choca com a aula de Bia.'), findsOneWidget);
      expect(_botao(tester, 'Remarcar').onPressed, isNull);
      expect(aplicou, isFalse);
    });

    testWidgets('se ao aplicar a agenda já mudou, o modal continua aberto com o motivo', (tester) async {
      await _abre(tester, (c) async => showMoveSheet(c, who: 'Ana', from: _from, weekly: false, check: (_) => null, commit: (_) => 'A agenda mudou. Tente de novo.'));
      await tester.tap(find.text('Dia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('11'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remarcar'));
      await tester.pumpAndSettle();
      expect(find.text('A agenda mudou. Tente de novo.'), findsOneWidget);
      expect(find.text('Remarcar esta aula'), findsOneWidget);
    });
  });

  group('trocar', () {
    final opcoes = [SwapOption('Bruno', DateTime(2027, 3, 11, 16)), SwapOption('Clara', DateTime(2027, 3, 12, 9))];

    testWidgets('lista as aulas, só liga o botão depois de escolher e mostra o que muda nos dois', (tester) async {
      int? resultado;
      int? aplicado;
      await _abre(tester, (c) async {
        resultado = await showSwapSheet(c, aName: 'Ana', aStart: _from, options: opcoes, check: (_) => null, commit: (i) {
          aplicado = i;
          return null;
        });
      });
      expect(find.text('Trocar horário'), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Clara'), findsOneWidget);
      expect(find.text('Escolha uma aula acima para ver como fica.'), findsOneWidget);
      expect(_botao(tester, 'Trocar').onPressed, isNull);

      await tester.tap(find.text('Clara'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Os dois são avisados'), findsOneWidget);
      expect(find.textContaining('→'), findsNWidgets(2), reason: 'uma linha de → para cada aluno');
      expect(_botao(tester, 'Trocar').onPressed, isNotNull);

      await tester.tap(find.text('Trocar'));
      await tester.pumpAndSettle();
      expect(aplicado, 1);
      expect(resultado, 1);
    });

    testWidgets('troca que não cabe: mostra o motivo e não deixa confirmar', (tester) async {
      await _abre(tester, (c) async => showSwapSheet(c, aName: 'Ana', aStart: _from, options: opcoes, check: (i) => i == 0 ? 'Choca com outra aula.' : null, commit: (_) => null));
      await tester.tap(find.text('Bruno'));
      await tester.pumpAndSettle();
      expect(find.text('Choca com outra aula.'), findsOneWidget);
      expect(_botao(tester, 'Trocar').onPressed, isNull);
      await tester.tap(find.text('Clara'));
      await tester.pumpAndSettle();
      expect(find.text('Choca com outra aula.'), findsNothing);
      expect(_botao(tester, 'Trocar').onPressed, isNotNull);
    });
  });

  group('confirmar', () {
    testWidgets('só o botão de confirmar devolve true; "Voltar" devolve false', (tester) async {
      bool? r;
      await _abre(tester, (c) async => r = await showConfirmSheet(c, title: 'Pausar as aulas?', body: '3 aulas serão canceladas.', ok: 'Pausar', danger: true));
      expect(find.text('Pausar as aulas?'), findsOneWidget);
      expect(find.text('3 aulas serão canceladas.'), findsOneWidget);
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(r, isFalse);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pausar'));
      await tester.pumpAndSettle();
      expect(r, isTrue);
    });
  });

  group('calendário do mês', () {
    testWidgets('toque no dia escolhe o dia; dias com aula dizem quantas aulas têm', (tester) async {
      final handle = tester.ensureSemantics();
      DateTime? escolhido;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgendaMonthGrid(
              month: DateTime(2026, 11, 1),
              counts: const {10: 2, 12: 1},
              picked: DateTime(2026, 11, 12),
              today: DateTime(2026, 11, 12),
              onPick: (d) => escolhido = d,
            ),
          ),
        ),
      );
      expect(find.text('30'), findsOneWidget);
      expect(find.text('31'), findsNothing, reason: 'novembro tem 30 dias');
      expect(find.bySemanticsLabel('10 de novembro, 2 aulas'), findsOneWidget);
      expect(find.bySemanticsLabel('12 de novembro, 1 aula'), findsOneWidget);
      expect(find.bySemanticsLabel('15 de novembro, sem aulas'), findsOneWidget);
      await tester.tap(find.text('10'));
      expect(escolhido, DateTime(2026, 11, 10));
      handle.dispose();
    });

    testWidgets('a semana começa na segunda: 1º de novembro de 2026 (domingo) cai na última coluna', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AgendaMonthGrid(month: DateTime(2026, 11, 1), counts: const {}, picked: DateTime(2026, 11, 1), today: DateTime(2026, 11, 1), onPick: (_) {}))));
      final dom = tester.getCenter(find.text('dom'));
      final um = tester.getCenter(find.text('1'));
      expect((um.dx - dom.dx).abs() < 5, isTrue, reason: 'o dia 1 fica embaixo de "dom"');
    });
  });

  group('aluno não veio', () {
    testWidgets('com aula marcada: três caminhos, o botão só liga depois de escolher e muda o texto ao remarcar', (tester) async {
      AbsenceChoice? r;
      await _abre(tester, (c) async => r = await showAbsenceSheet(c, who: 'Ana', lessonLabel: 'Aula de hoje · seg 16/11 · 17:00', hasLesson: true, weekly: true));
      expect(find.text('Ana não veio?'), findsOneWidget);
      expect(find.text('Aula de hoje · seg 16/11 · 17:00'), findsOneWidget);
      expect(find.text('Faltou, sem avisar'), findsOneWidget);
      expect(find.text('Avisou que não vem'), findsOneWidget);
      expect(find.text('Quer remarcar'), findsOneWidget);
      expect(find.textContaining('só a aula de hoje é cancelada'), findsOneWidget, reason: 'aula semanal: cancela só a de hoje');
      expect(_botao(tester, 'Registrar falta').onPressed, isNull);

      await tester.tap(find.text('Quer remarcar'));
      await tester.pumpAndSettle();
      expect(find.text('Registrar e remarcar'), findsOneWidget);
      expect(_botao(tester, 'Registrar e remarcar').onPressed, isNotNull);

      await tester.tap(find.text('Faltou, sem avisar'));
      await tester.pumpAndSettle();
      expect(find.text('Registrar falta'), findsOneWidget);
      await tester.tap(find.text('Registrar falta'));
      await tester.pumpAndSettle();
      expect(r, AbsenceChoice.noShow);
    });

    testWidgets('sem aula marcada: só registrar (não oferece cancelar nem remarcar)', (tester) async {
      await _abre(tester, (c) async => showAbsenceSheet(c, who: 'Ana', hasLesson: false, weekly: false));
      expect(find.text('Faltou, sem avisar'), findsOneWidget);
      expect(find.text('Avisou que não vem'), findsOneWidget);
      expect(find.text('Quer remarcar'), findsNothing);
      expect(find.textContaining('é cancelada'), findsNothing);
    });

    testWidgets('voltar fecha sem escolher', (tester) async {
      AbsenceChoice? r = AbsenceChoice.noShow;
      await _abre(tester, (c) async => r = await showAbsenceSheet(c, who: 'Ana', hasLesson: true, weekly: false));
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(r, isNull);
    });
  });

  group('cancelar aula semanal', () {
    testWidgets('escolher entre só esta e todas, com o botão laranja só depois de escolher', (tester) async {
      CancelChoice? r;
      await _abre(tester, (c) async => r = await showCancelSheet(c, who: 'Ana', dateLabel: 'seg 16/11 · 17:00'));
      expect(find.text('Só esta aula'), findsOneWidget);
      expect(find.text('Todas as aulas'), findsOneWidget);
      expect(_botao(tester, 'Cancelar aula').onPressed, isNull);
      await tester.tap(find.text('Todas as aulas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Só esta aula'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar aula'));
      await tester.pumpAndSettle();
      expect(r, CancelChoice.one, reason: 'vale a última escolha');
    });
  });

}
