import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  test('aluno desativado: o campo vai e volta do JSON, e o padrão é ativo', () {
    final s = Student(id: 'a1', name: 'Ana');
    expect(s.paused, isFalse);
    expect(s.toJson().containsKey('pz'), isFalse, reason: 'ativo não grava o campo (compatível com versões antigas)');
    s.paused = true;
    final back = Student.tryFrom(s.toJson())!;
    expect(back.paused, isTrue);
    final old = Student.tryFrom({'id': 'a2', 'name': 'Bia'})!;
    expect(old.paused, isFalse);
  });
}
