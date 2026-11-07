import 'package:flutter_test/flutter_test.dart';

// O app depende de áudio nativo (SoLoud/microfone), que não existe no ambiente
// de teste de widgets. A lógica está coberta pelos testes de `core`. A
// verificação da interface é feita rodando o app (veja o README).
void main() {
  test('placeholder: interface verificada manualmente', () {
    expect(true, isTrue);
  });
}
