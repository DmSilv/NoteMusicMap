import 'dart:convert';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => customInstruments = []);

  group('instrumento criado pelo professor', () {
    test('passa a existir como os do catálogo: nome, sugestões e limpeza de ids', () {
      customInstruments = [TeachingInstrument('x_cavaquinho', 'Cavaquinho', methods: ['Método do Waldir'], repertoire: ['Brasileirinho'], custom: true)];
      expect(teachingById('x_cavaquinho')!.label, 'Cavaquinho');
      expect(catalogMethods(['x_cavaquinho']), ['Método do Waldir']);
      expect(catalogRepertoire(['piano', 'x_cavaquinho']).last, 'Brasileirinho');
      expect(cleanTeachingIds(['x_cavaquinho', 'piano', 'x_nao_existe']), ['piano', 'x_cavaquinho']);
      expect(allTeachingInstruments().length, kTeachingInstruments.length + 1);
    });

    test('o nome do professor não passa pela tradução (nem vira "{0}")', () {
      customInstruments = [TeachingInstrument('x_a', 'Viola {0} caipira', methods: const [], repertoire: const [], custom: true)];
      expect(teachingById('x_a')!.label, 'Viola {0} caipira');
    });

    test('ida e volta pelo JSON, com limpeza e limites', () {
      final i = TeachingInstrument('x_gaita', 'Gaita', methods: ['A', 'B'], repertoire: ['C'], custom: true);
      final back = customInstrumentsFromJson((jsonDecodeList(customInstrumentsToJson([i]))));
      expect(back.single.id, 'x_gaita');
      expect(back.single.methods, ['A', 'B']);
      expect(back.single.custom, isTrue);
      final lixo = customInstrumentsFromJson([
        {'id': 'piano', 'n': 'Roubando o id do catálogo'},
        {'id': 'x_ok', 'n': ''},
        {'id': 'X MAIUSCULO', 'n': 'x'},
        'texto',
        {'id': 'x_bom', 'n': 'Bom', 'm': List.generate(500, (k) => 'M$k')},
      ]);
      expect(lixo.map((x) => x.id), ['x_bom']);
      expect(lixo.single.methods.length, kMaxCustomItems);
    });

    test('id novo vem do nome e não repete', () {
      expect(newCustomInstrumentId('Cavaquinho', const []), 'x_cavaquinho');
      expect(newCustomInstrumentId('Cavaquinho', ['x_cavaquinho']), 'x_cavaquinho2');
      expect(newCustomInstrumentId('???', const []), 'x_outro');
      expect(newCustomInstrumentId('Um nome muito mas muito longo mesmo', const []).length, lessThanOrEqualTo(20));
    });
  });

  group('turma', () {
    test('ida e volta e limpeza', () {
      final t = Turma(id: 'tabc', name: 'Violino iniciantes', instrument: 'violino');
      final back = turmasFromJson(jsonDecodeList(turmasToJson([t])));
      expect(back.single.name, 'Violino iniciantes');
      expect(back.single.instrument, 'violino');
      expect(turmasFromJson([{'id': 'abc', 'n': 'sem t no começo'}, {'id': 'tok', 'n': ''}, {'id': 'tx', 'n': 'Ok', 'i': 'Instrumento Inválido!'}]).single.instrument, '');
    });

    test('id novo não repete e aluno guarda a turma (id inválido é descartado)', () {
      expect(newTurmaId(['t1'], 1), isNot('t1'));
      final s = Student(id: 's', name: 'Ana', turma: 'tabc');
      expect(Student.tryFrom(s.toJson())!.turma, 'tabc');
      expect(Student.tryFrom(s.toJson()..['tu'] = 'lixo!')!.turma, isNull);
      expect(Student(id: 's', name: 'Ana').toJson().containsKey('tu'), isFalse);
    });
  });

  group('ajustes da conta entre aparelhos', () {
    test('instrumentos próprios e turmas vão e voltam e somam', () {
      final a = AccountPrefs(
        teachInstruments: const ['piano'],
        custom: [TeachingInstrument('x_gaita', 'Gaita', methods: ['A'], repertoire: const [], custom: true)],
        turmas: [Turma(id: 't1', name: 'Manhã', instrument: 'piano')],
      );
      final b = AccountPrefs.fromSection(
          AccountPrefs(teachInstruments: const ['x_gaita'], custom: [TeachingInstrument('x_gaita', 'Gaita', methods: ['B'], repertoire: ['R'], custom: true)], turmas: [Turma(id: 't2', name: 'Tarde')]).toSection());
      expect(b.teachInstruments, ['x_gaita'], reason: 'o id próprio sobrevive à leitura');
      final m = a.merge(b);
      expect(m.custom.single.methods.toSet(), {'A', 'B'});
      expect(m.custom.single.repertoire, ['R']);
      expect(m.turmas.map((t) => t.id).toSet(), {'t1', 't2'});
      expect(m.teachInstruments.toSet(), {'piano', 'x_gaita'});
      expect(customInstruments, isEmpty, reason: 'a leitura não deixa lixo no registro global');
      expect(const AccountPrefs().isDefault, isTrue);
      expect(a.isDefault, isFalse);
    });
  });
}

List<dynamic> jsonDecodeList(String s) => jsonDecode(s) as List<dynamic>;
