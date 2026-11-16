import 'dart:math';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  Student s(String id, String name, {String? code, DateTime? created}) => Student(id: id, name: name, code: code, created: created);

  group('rótulo do aluno nas listas', () {
    test('nome único aparece como está', () {
      final all = [s('1', 'Ana'), s('2', 'Bruno')];
      expect(studentLabel(all[0], all), 'Ana');
    });

    test('dois com o mesmo nome e código: acrescenta o fim do código', () {
      final a = s('1', 'Lucas', code: 'K7QM-4TXD');
      final b = s('2', 'Lucas', code: 'ABCD-WX9Z');
      final c = s('3', 'Daniel', code: 'PQRS-1234');
      final all = [a, b, c];
      expect(studentLabel(a, all), 'Lucas · 4TXD');
      expect(studentLabel(b, all), 'Lucas · WX9Z');
      expect(studentLabel(c, all), 'Daniel');
    });

    test('ignora maiúsculas e espaços ao comparar', () {
      final a = s('1', 'Lucas', code: 'K7QM-4TXD');
      final b = s('2', '  lucas ', code: 'ABCD-WX9Z');
      expect(studentLabel(a, [a, b]), 'Lucas · 4TXD');
    });

    test('um com código e outro sem: o sem código vira "sem código"', () {
      final a = s('1', 'Lucas', code: 'K7QM-4TXD');
      final b = s('2', 'Lucas');
      final all = [a, b];
      expect(studentLabel(a, all), 'Lucas · 4TXD');
      expect(studentLabel(b, all), 'Lucas · sem código');
    });

    test('vários sem código são numerados pela ordem de cadastro', () {
      final a = s('1', 'Lucas', created: DateTime(2026, 1, 1));
      final b = s('2', 'Lucas', created: DateTime(2026, 2, 1));
      expect(studentLabel(a, [b, a]), 'Lucas · sem código 1');
      expect(studentLabel(b, [b, a]), 'Lucas · sem código 2');
    });

    test('se o fim do código coincidir, usa o código inteiro', () {
      final a = s('1', 'Lucas', code: 'AAAA-4TXD');
      final b = s('2', 'Lucas', code: 'BBBB-4TXD');
      expect(studentLabel(a, [a, b]), 'Lucas · AAAA-4TXD');
    });

    test('o nome guardado não muda', () {
      final a = s('1', 'Lucas', code: 'K7QM-4TXD');
      final b = s('2', 'Lucas', code: 'ABCD-WX9Z');
      studentLabel(a, [a, b]);
      expect(a.name, 'Lucas');
    });
  });

  group('cadastro com nome repetido', () {
    final c1 = newShareCode(Random(1)), c2 = newShareCode(Random(2));
    test('sem código: a mensagem sugere sobrenome ou código e cita o nome', () {
      final r = checkStudentEntry(name: 'Lucas Silva', codeInput: '', ownCode: 'ZZZZ-ZZZZ', existing: [s('1', 'Lucas Silva')]);
      expect(r.name, contains('Lucas'));
      expect(r.name, contains('código'));
    });

    test('os dois com código continuam permitidos (pessoas diferentes)', () {
      final r = checkStudentEntry(name: 'Lucas', codeInput: c2, ownCode: newShareCode(Random(9)), existing: [s('1', 'Lucas', code: c1)]);
      expect(r.name, isNull);
      expect(r.ok, isTrue);
    });
  });
}
