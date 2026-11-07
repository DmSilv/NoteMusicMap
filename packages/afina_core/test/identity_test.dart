import 'dart:math';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  test('perfil novo: UUID v4, segredo de 256 bits, código válido e professor desligado', () {
    final p = Profile.create(Random(1));
    expect(isUuid(p.id), isTrue);
    expect(p.id[14], '4');
    expect(p.secret, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(isValidShareCode(p.shareCode), isTrue);
    expect(p.shareCode, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$')));
    expect(p.teacher, isFalse);
  });

  test('perfis sorteados são diferentes', () {
    final r = Random(7);
    final ids = {for (var i = 0; i < 200; i++) Profile.create(r).id};
    expect(ids.length, 200);
  });

  test('código: sem 0, O, 1 e I; aceita minúsculas, espaço e hífen', () {
    expect(kCodeAlphabet.length, 32);
    for (final c in ['0', 'O', '1', 'I']) {
      expect(kCodeAlphabet.contains(c), isFalse);
    }
    final code = newShareCode(Random(3));
    final loose = code.toLowerCase().replaceAll('-', ' ');
    expect(isValidShareCode(loose), isTrue);
    expect(formatShareCode(loose), code);
  });

  test('código: erro de digitação ou troca de vizinhos é detectado', () {
    final r = Random(11);
    var caught = 0, total = 0;
    for (var i = 0; i < 300; i++) {
      final s = normalizeShareCode(newShareCode(r));
      // Troca de um caractere por outro diferente do alfabeto.
      final pos = r.nextInt(8);
      final other = kCodeAlphabet[(kCodeAlphabet.indexOf(s[pos]) + 1 + r.nextInt(31)) % 32];
      final bad = s.replaceRange(pos, pos + 1, other);
      total++;
      if (!isValidShareCode(bad)) caught++;
    }
    expect(caught, total); // um caractere errado nunca passa
    expect(isValidShareCode(''), isFalse);
    expect(isValidShareCode('ABCD-EFG'), isFalse);
    expect(isValidShareCode('0000-0000'), isFalse);
  });

  test('chave de recuperação recria exatamente o mesmo perfil', () {
    final p = Profile.create(Random(5));
    final key = recoveryKeyFor(p);
    expect(key, startsWith('NM1-'));
    final q = profileFromRecoveryKey(key)!;
    expect(q.id, p.id);
    expect(q.secret, p.secret);
    expect(q.shareCode, p.shareCode);
    // Maiúsculas, espaços e quebras de linha não atrapalham.
    expect(profileFromRecoveryKey('  ${key.toUpperCase().replaceAll('-', '-\n')}  ')!.id, p.id);
  });

  test('chave de recuperação com erro, incompleta ou de outro tipo é recusada', () {
    final p = Profile.create(Random(9));
    final key = recoveryKeyFor(p);
    final i = key.indexOf('-') + 3;
    final flipped = key.substring(0, i) + (key[i] == 'a' ? 'b' : 'a') + key.substring(i + 1);
    expect(profileFromRecoveryKey(flipped), isNull);
    expect(profileFromRecoveryKey(key.substring(0, key.length - 12)), isNull);
    expect(profileFromRecoveryKey('qualquer coisa'), isNull);
    expect(profileFromRecoveryKey(''), isNull);
  });

  group('leitura de QR e links', () {
    final code = newShareCode(Random(21));
    final low = code.toLowerCase();

    test('link do aluno, link do professor, notemusic: e código puro', () {
      final a = parseScannedCode('https://notemusicmap.vercel.app/?aluno=$code')!;
      expect((a.code, a.kind), (code, 'aluno'));
      final p = parseScannedCode('https://exemplo.com/?x=1&professor=$low')!;
      expect((p.code, p.kind), (code, 'professor'));
      expect(parseScannedCode('notemusic:$code')!.kind, 'codigo');
      expect(parseScannedCode('  $low ')!.code, code);
    });

    test('lixo, código com erro e links sem código viram null', () {
      expect(parseScannedCode(''), isNull);
      expect(parseScannedCode('https://notemusicmap.vercel.app/'), isNull);
      expect(parseScannedCode('https://x.com/?aluno=ABCD-1234'), isNull);
      expect(parseScannedCode('olá mundo'), isNull);
      expect(parseScannedCode('AAAA-AAAB'), isNull);
    });
  });

  test('perfil: salvar e ler preserva tudo, inclusive professor ligado', () {
    final p = Profile.create(Random(2), now: DateTime(2026, 11, 7))
      ..name = 'Ana'
      ..teacher = true
      ..recoveryShownAt = DateTime(2026, 11, 8);
    final q = Profile.tryFrom(p.toJson())!;
    expect(q.id, p.id);
    expect(q.secret, p.secret);
    expect(q.shareCode, p.shareCode);
    expect(q.name, 'Ana');
    expect(q.teacher, isTrue);
    expect(q.recoveryShownAt, DateTime(2026, 11, 8));
    expect(Profile.tryFrom({'id': 'x'}), isNull);
    final adulterado = p.toJson()..['code'] = 'AAAA-AAAB';
    expect(Profile.tryFrom(adulterado), isNull);
  });

  group('id da sessão', () {
    SessionRecord rec({String? id, String origin = kOriginSelf, String title = 'Sol maior · 1 oitava'}) =>
        SessionRecord(
            id: id,
            origin: origin,
            date: DateTime(2026, 11, 7, 10, 30),
            title: title,
            octaves: 1,
            zone: 5,
            accuracy: 0.8,
            meanAbsCents: 6,
            steps: const [StepRecord(55, true, 0, 4)]);

    test('sessão antiga sem id recebe um id estável (igual em qualquer aparelho)', () {
      final j = rec().toJson()..remove('id');
      final a = SessionRecord.tryFromJson(j)!;
      final b = SessionRecord.tryFromJson(j)!;
      expect(a.id, b.id);
      expect(a.id, startsWith('L'));
      expect(rec(title: 'Ré maior · 1 oitava').id, isNot(a.id));
    });

    test('id e origem sobrevivem a salvar e ler', () {
      final r = rec(id: newUuid(Random(4)), origin: kOriginTeacherDevice);
      final back = SessionRecord.tryFromJson(r.toJson())!;
      expect(back.id, r.id);
      expect(back.origin, kOriginTeacherDevice);
      expect(rec().toJson().containsKey('origin'), isFalse); // padrão não pesa no JSON
    });

    test('juntar sessões não duplica pelo mesmo id', () {
      final a = rec(id: 'x1');
      final dupe = SessionRecord(
          id: 'x1',
          date: DateTime(2030),
          title: 'Outro',
          octaves: 1,
          zone: 5,
          accuracy: 1,
          meanAbsCents: 1,
          steps: const []);
      final into = [a];
      expect(mergeSessions(into, [dupe]), 0);
      expect(into.length, 1);
    });
  });
}
