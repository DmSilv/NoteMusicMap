// Conversa com o desenvolvedor: leitura das mensagens vindas do servidor.
import 'package:afina/link/link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mensagem do servidor: limpa o texto, separa quem escreveu e o pedido de crédito', () {
    final a = DevMsg.tryFrom({'i': 'a1', 'f': 'a', 't': 1800000000000, 'x': 'Oi!\u0000 Posso citar?', 'ask': 1, 'ref': 'mais escalas'})!;
    expect(a.admin, true);
    expect(a.asksCredit, true);
    expect(a.text.contains('\u0000'), false);
    expect(a.ref, 'mais escalas');
    final u = DevMsg.tryFrom({'i': 'u1', 'f': 'u', 't': 1, 'x': 'Pode'})!;
    expect(u.admin, false);
    expect(u.asksCredit, false);
    expect(DevMsg.tryFrom({'f': 'a', 'x': '  '}), isNull);
    expect(DevMsg.tryFrom('lixo'), isNull);
  });
}
