// Aparelho tirado da conta por outro: o servidor recusa (403) e o app precisa reconhecer isso.
import 'dart:convert';

import 'package:afina/link/link_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

LinkService svc(int status, Map<String, dynamic> body) => LinkService(
      client: MockClient((req) async => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'})),
      endpoint: Uri.parse('http://teste.local/api/link'),
    );

void main() {
  const code = 'ABCD-EFGH';
  final secret = 'a' * 64;

  test('403 "pertence a outro aparelho" = este aparelho saiu da conta', () async {
    final r = await svc(403, {'error': 'Este código pertence a outro aparelho.'}).sync(code, secret, name: 'Ana');
    expect(r.ok, isFalse);
    expect(r.revoked, isTrue);
  });

  test('outros 403 (bloqueado, sem vínculo) NÃO são "saiu da conta"', () async {
    final a = await svc(403, {'error': 'blocked', 'message': 'Este perfil foi bloqueado.'}).sync(code, secret, name: 'Ana');
    expect(a.revoked, isFalse);
    final b = await svc(403, {'error': 'Sem vínculo com esta pessoa.'}).sync(code, secret, name: 'Ana');
    expect(b.revoked, isFalse);
  });

  test('erro de servidor e resposta boa não são "saiu da conta"', () async {
    expect((await svc(500, {'error': 'x'}).sync(code, secret, name: 'Ana')).revoked, isFalse);
    expect((await svc(200, {'asTeacher': [], 'asStudent': []}).sync(code, secret, name: 'Ana')).revoked, isFalse);
  });
}
