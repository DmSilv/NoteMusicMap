import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  group('instrumentos que o professor ensina', () {
    test('cada instrumento tem id único e nome; todos têm sugestões de métodos', () {
      final ids = [for (final i in kTeachingInstruments) i.id];
      expect(ids.toSet().length, ids.length);
      for (final i in kTeachingInstruments) {
        expect(i.label, isNotEmpty);
        expect(i.methods, isNotEmpty, reason: i.id);
        expect(i.methods.toSet().length, i.methods.length, reason: 'sem repetidos em ${i.id}');
        expect(i.repertoire.toSet().length, i.repertoire.length, reason: 'sem repetidos em ${i.id}');
      }
    });

    test('nenhuma sugestão é longa demais para o campo (cabe em um título)', () {
      for (final i in kTeachingInstruments) {
        for (final s in [...i.methods, ...i.repertoire]) {
          expect(s.length, lessThanOrEqualTo(60), reason: s);
          expect(s.trim(), s);
        }
      }
    });

    test('piano traz Hanon e Czerny; violino traz Suzuki e Ševčík', () {
      expect(catalogMethods(['piano']), containsAll(['Czerny']));
      expect(catalogMethods(['piano']).any((m) => m.startsWith('Hanon')), isTrue);
      expect(catalogMethods(['violino']), containsAll(['Suzuki', 'Ševčík']));
      expect(catalogMethods(['violino']), isNot(contains('Czerny')));
    });

    test('mais de um instrumento junta sem repetir, na ordem dada', () {
      final m = catalogMethods(['violino', 'viola']);
      expect(m.where((x) => x == 'Kayser').length, 1);
      expect(m.first, 'Suzuki');
      expect(catalogRepertoire(['piano', 'violino']).where((x) => x == 'Minueto em Sol (Bach)').length, 1);
    });

    test('id desconhecido ou lista vazia não dá nada nem quebra', () {
      expect(catalogMethods(const []), isEmpty);
      expect(catalogMethods(['tuba']), isEmpty);
      expect(teachingById('tuba'), isNull);
      expect(teachingById('piano')!.id, 'piano');
    });

    test('cleanTeachingIds filtra, tira repetidos e põe na ordem do catálogo', () {
      expect(cleanTeachingIds(['piano', 'tuba', 'violino', 'piano', 3, null]), ['violino', 'piano']);
      expect(cleanTeachingIds(null), isEmpty);
    });

    test('instrumentForTask: o do aluno, o único que ensina, ou nenhum', () {
      expect(instrumentForTask(studentInstrument: 'piano', teaches: ['violino', 'piano']), 'piano');
      expect(instrumentForTask(studentInstrument: 'flauta', teaches: ['violino', 'piano']), isNull);
      expect(instrumentForTask(studentInstrument: null, teaches: ['piano']), 'piano');
      expect(instrumentForTask(studentInstrument: null, teaches: ['violino', 'piano']), isNull);
      expect(instrumentForTask(studentInstrument: 'piano', teaches: const []), isNull);
    });
  });

  group('instrumento do aluno na ficha', () {
    test('vai e volta pelo JSON; valor inválido é descartado', () {
      final s = Student(id: 's', name: 'Ana', instrument: 'piano');
      expect(Student.tryFrom(s.toJson())!.instrument, 'piano');
      final j = s.toJson()..['ins'] = 'tuba';
      expect(Student.tryFrom(j)!.instrument, isNull);
      expect(Student(id: 's', name: 'Ana').toJson().containsKey('ins'), isFalse);
    });
  });
}
