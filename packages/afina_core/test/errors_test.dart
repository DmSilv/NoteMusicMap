import 'dart:async';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

class SocketException implements Exception {
  @override
  String toString() => 'SocketException: Failed host lookup: notemusicmap.vercel.app';
}

void main() {
  group('catálogo', () {
    test('todo código tem título, frase e ação, e a chave bate com o código', () {
      for (final e in kErrorCatalog.entries) {
        expect(e.value.code, e.key);
        expect(e.value.title, isNotEmpty);
        expect(e.value.message, isNotEmpty);
        expect(e.value.action, isNotEmpty);
      }
    });

    test('só APP-99 (não abriu) é crítico; os demais não derrubam o app', () {
      final criticos = kErrorCatalog.values.where((s) => s.severity == ErrorSeverity.critical).map((s) => s.code);
      expect(criticos, ['APP-99']);
    });

    test('status HTTP viram o código certo', () {
      expect(errorCodeForStatus(429), 'NET-03');
      expect(errorCodeForStatus(503), 'NET-02');
      expect(errorCodeForStatus(404), 'NET-02');
      expect(errorCodeForStatus(500), 'API-05');
      expect(errorCodeForStatus(400), 'API-04');
      expect(errorCodeForStatus(403), 'API-04');
      expect(errorCodeForStatus(200), 'APP-00');
    });
  });

  group('classificação', () {
    test('rede, tempo esgotado, formato e inesperado', () {
      expect(classifyError(SocketException()).code, 'NET-01');
      expect(classifyError(TimeoutException('x')).code, 'NET-01');
      expect(classifyError(const FormatException('json ruim')).code, 'DATA-01');
      expect(classifyError(StateError('quebrou')).code, 'APP-00');
      expect(classifyError(Exception('Failed to fetch')).code, 'NET-01');
    });

    test('gravidade vem do catálogo; erro de rede é só informativo', () {
      expect(classifyError(SocketException()).severity, ErrorSeverity.info);
      expect(classifyError(StateError('x')).severity, ErrorSeverity.action);
    });

    test('guarda onde aconteceu e a hora', () {
      final e = classifyError(StateError('x'), where: 'Agenda › Marcar aula', nowMs: 123);
      expect(e.where, 'Agenda › Marcar aula');
      expect(e.atMs, 123);
    });
  });

  group('higienização (nunca sai dado pessoal)', () {
    test('código de perfil, e-mail, segredo, endereço e número longo', () {
      final s = sanitizeDetail(
          'falha com K7QM-4TXK, ana@exemplo.com, segredo ${'a1' * 32}, https://notemusicmap.vercel.app/api/link?code=ABCD-EFGH, tel 11987654321');
      expect(s.contains('K7QM-4TXK'), isFalse);
      expect(s.contains('@'), isFalse);
      expect(s.contains('a1a1a1a1'), isFalse);
      expect(s.contains('?code'), isFalse);
      expect(s.contains('11987654321'), isFalse);
      expect(s, contains('[código]'));
      expect(s, contains('[e-mail]'));
      expect(s, contains('[segredo]'));
      expect(s, contains('https://notemusicmap.vercel.app/…'));
    });

    test('limita o tamanho e tira caracteres invisíveis', () {
      expect(sanitizeDetail('x' * 5000).length, kMaxErrorDetail);
      expect(sanitizeDetail('a\u200bb\u0000c\u202ed'), 'abcd');
      expect(sanitizeDetail(null), '');
      expect(sanitizeDetail(''), '');
    });

    test('a pilha perde caminhos do computador e fica curta', () {
      final st = StackTrace.fromString('#0 f (C:\\Users\\dev\\proj\\lib\\a.dart:10:3)\n#1 g (/home/dev/x.dart:5:1)\n#2 h\n#3 i\n#4 j\n#5 k\n#6 l\n#7 m');
      final s = shortStack(st);
      expect(s.contains('Users'), isFalse);
      expect(s.contains('/home'), isFalse);
      expect(s.split('\n').length, 6);
    });

    test('um erro com dados pessoais na mensagem já sai higienizado', () {
      final e = classifyError(StateError('perfil K7QM-4TXK de ana@x.com'));
      expect(e.detail.contains('K7QM'), isFalse);
      expect(e.detail.contains('@'), isFalse);
    });
  });

  group('código curto', () {
    test('é estável, tem o formato E-XXXX e muda com o problema', () {
      final a = errorShortId('APP-00', 'StateError');
      expect(a, errorShortId('APP-00', 'StateError'));
      expect(RegExp(r'^E-[2-9A-HJ-NP-Z]{4}$').hasMatch(a), isTrue, reason: a);
      expect(errorShortId('NET-01', 'x'), isNot(errorShortId('APP-00', 'x')));
    });

    test('só a primeira linha do detalhe conta (a pilha varia, o problema é o mesmo)', () {
      expect(errorShortId('APP-00', 'StateError\nlinha 1'), errorShortId('APP-00', 'StateError\noutra pilha'));
    });
  });

  group('histórico', () {
    AppError err(String d, {int t = 1}) => AppError(code: 'APP-00', severity: ErrorSeverity.action, detail: d, atMs: t);

    test('mais novo primeiro e no máximo 20', () {
      final log = ErrorLog();
      for (var i = 0; i < 30; i++) {
        log.add(err('erro $i', t: i));
      }
      expect(log.items.length, ErrorLog.kMax);
      expect(log.items.first.detail, 'erro 29');
    });

    test('o mesmo problema em sequência vira uma linha só, com contagem', () {
      final log = ErrorLog();
      expect(log.add(err('igual')), isTrue);
      expect(log.add(err('igual', t: 2)), isFalse);
      expect(log.add(err('igual', t: 3)), isFalse);
      expect(log.items.length, 1);
      expect(log.repeatsOf(log.items.first), 3);
      expect(log.add(err('outro')), isTrue);
      expect(log.items.length, 2);
    });

    test('guarda e lê do disco; texto corrompido começa vazio', () {
      final log = ErrorLog()..add(err('a'))..add(err('b'));
      final back = ErrorLog.fromJsonString(log.toJsonString());
      expect(back.items.map((e) => e.detail), ['b', 'a']);
      expect(ErrorLog.fromJsonString('{{ não é json').items, isEmpty);
      expect(ErrorLog.fromJsonString(null).items, isEmpty);
      expect(ErrorLog.fromJsonString('[1, "x", {"c": 5}]').items, isEmpty);
    });

    test('código desconhecido vindo do disco vira APP-00', () {
      final e = AppError.tryFrom({'c': 'XXX-99', 's': 'critical', 't': 5});
      expect(e!.code, 'APP-00');
    });

    test('relatório para copiar traz código curto, onde e quando, sem dado pessoal', () {
      final log = ErrorLog()..add(classifyError(StateError('perfil K7QM-4TXK'), where: 'Meu espaço', nowMs: 1000));
      final r = log.report(appVersion: '1.0.0');
      expect(r, contains('Relatório de problemas'));
      expect(r, contains('1.0.0'));
      expect(r, contains('Onde: Meu espaço'));
      expect(r.contains('K7QM'), isFalse);
    });
  });
}
