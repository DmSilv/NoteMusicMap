import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

// Cordas soltas do violino: Sol3, Ré4, Lá4, Mi5.
const _open = {55, 62, 69, 76};

void main() {
  test('a tabela confere com a sequência: índices existentes e dedos de 0 a 4', () {
    for (final e in violinFingeringEntries()) {
      final tonic = 55 + ((e.tonicPc - 55) % 12 + 12) % 12; // oitava perto da corda Sol, como o app
      final seq = scaleSequence(tonic, e.type, octaves: e.octaves);
      for (final m in e.marks.entries) {
        expect(m.key, inInclusiveRange(0, seq.length - 1), reason: 'índice ${m.key}');
        expect(int.parse(m.value), inInclusiveRange(0, 4));
      }
    }
  });

  test('todo "0" cai numa corda solta do violino (pega número lido na nota errada)', () {
    for (final e in violinFingeringEntries()) {
      final tonic = 55 + ((e.tonicPc - 55) % 12 + 12) % 12;
      final seq = scaleSequence(tonic, e.type, octaves: e.octaves);
      for (final m in e.marks.entries.where((m) => m.value == '0')) {
        expect(_open.contains(seq[m.key]), isTrue, reason: 'índice ${m.key} = nota ${seq[m.key]}');
      }
    }
  });

  test('o 4º dedo no lugar da corda solta: Si♭ maior sobe com 4º dedo no Ré4 e no Lá4 e desce com as cordas soltas', () {
    final seq = scaleSequence(58, ScaleType.major, octaves: 3);
    final f = violinFingering(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.both)!;
    expect(f.length, seq.length);
    expect(seq[2], 62); // Ré4
    expect(f[2], '4');
    expect(seq[6], 69); // Lá4
    expect(f[6], '4');
    expect(seq[36], 69);
    expect(f[36], '0');
    expect(seq[40], 62);
    expect(f[40], '0');
  });

  test('só subindo e só descendo recortam a mesma tabela', () {
    final both = violinFingering(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.both)!;
    final up = violinFingering(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.up)!;
    final down = violinFingering(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.down)!;
    expect(up, both.sublist(0, up.length));
    expect(down, both.sublist(up.length - 1));
    expect(down.first, both[up.length - 1]);
  });

  test('sem tabela, null (nada é inventado)', () {
    expect(violinFingering(tonicMidi: 60, type: ScaleType.major, octaves: 1, direction: ScaleDirection.both), isNull);
    expect(hasViolinFingering(58, ScaleType.major, 3), isTrue);
    expect(hasViolinFingering(58, ScaleType.major, 2), isFalse);
  });

  test('Mi♭ maior (Flesch nº 5): mesmo molde dos pontos de mudança do Si♭ maior, 8va nas 6 notas do topo', () {
    final seq = scaleSequence(63, ScaleType.major, octaves: 3);
    expect(seq.first, 63); // Mi♭4
    final f = violinFingeringPlan(tonicMidi: 63, type: ScaleType.major, octaves: 3, direction: ScaleDirection.both)!;
    final b = violinFingeringPlan(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.both)!;
    for (final i in [9, 15, 17, 21, 22, 26, 29]) {
      expect(f.fingers[i], b.fingers[i], reason: 'índice $i');
    }
    expect(f.fingers[0], '2');
    expect(f.fingers.where((x) => x != null).length, 8);
    expect(f.ottava, (18, 23));
    expect(b.ottava, isNull); // a página do Si♭ maior não usa 8va
    // 18 a 23 = dois grupos inteiros de tercina (3 notas por grupo)
    expect(18 % 3, 0);
    expect((23 + 1) % 3, 0);
  });

  test('o 8va do livro acompanha a direção pedida', () {
    final up = violinFingeringPlan(tonicMidi: 63, type: ScaleType.major, octaves: 3, direction: ScaleDirection.up)!;
    final down = violinFingeringPlan(tonicMidi: 63, type: ScaleType.major, octaves: 3, direction: ScaleDirection.down)!;
    expect(up.ottava, (18, 21)); // só a subida: do Si♭6 ao Mi♭7
    expect(down.ottava, (0, 2)); // só a descida começa no Mi♭7
  });

  test('Mi♭ menor melódica (Flesch nº 5): a subida segue o molde das maiores, a descida tem o seu', () {
    final seq = scaleSequence(63, ScaleType.melodicMinor, octaves: 3);
    expect(seq.length, 43);
    final p = violinFingeringPlan(tonicMidi: 63, type: ScaleType.melodicMinor, octaves: 3, direction: ScaleDirection.both)!;
    final maj = violinFingeringPlan(tonicMidi: 63, type: ScaleType.major, octaves: 3, direction: ScaleDirection.both)!;
    for (final i in [0, 9, 15, 17, 21]) {
      expect(p.fingers[i], maj.fingers[i], reason: 'subida, nota \$i');
    }
    expect(p.fingers[22], '3'); // na maior seria 4
    expect(p.fingers[24], '3');
    expect(p.fingers[27], '3');
    expect(p.fingers[34], '2');
    expect(p.fingers.where((x) => x != null).length, 9);
    expect(p.ottava, (18, 23));
    // o topo é o Mi♭ e a descida usa as notas naturais (Ré♭ e Dó♭ nas notas 22 e 23)
    expect(seq[21], seq[0] + 36);
    expect(seq[22], seq[21] - 2);
    expect(seq[23], seq[21] - 4);
  });

  group('dedilhado vindo do servidor (painel do administrador)', () {
    tearDown(() => setViolinFingeringFromJson(null));

    String items(List<String> xs) => '{"v":1,"items":[${xs.join(",")}]}';

    test('uma correção vale no lugar da tabela do app, e apagar volta ao app', () {
      expect(violinFingering(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.both)![9], '1');
      final n = setViolinFingeringFromJson(items(['{"pc":10,"alt":false,"type":"major","oct":3,"marks":{"9":"2","0":"1"},"ottava":[18,23]}']));
      expect(n, 1);
      final p = violinFingeringPlan(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.both)!;
      expect(p.fingers[9], '2');
      expect(p.fingers[0], '1');
      expect(p.fingers[2], isNull); // o que não está na correção some (ela substitui a tabela inteira)
      expect(p.ottava, (18, 23));
      setViolinFingeringFromJson(items([]));
      expect(violinFingering(tonicMidi: 58, type: ScaleType.major, octaves: 3, direction: ScaleDirection.both)![9], '1');
    });

    test('uma escala incluída no painel aparece (Ré maior, 2 oitavas), na outra grafia também', () {
      expect(hasViolinFingering(62, ScaleType.major, 2), isFalse);
      setViolinFingeringFromJson(items([
        '{"pc":2,"alt":false,"type":"major","oct":2,"marks":{"0":"1"},"ottava":null}',
        '{"pc":1,"alt":true,"type":"major","oct":1,"marks":{"3":"4"}}',
      ]));
      expect(hasViolinFingering(62, ScaleType.major, 2), isTrue);
      expect(hasViolinFingering(61, ScaleType.major, 1, alt: true), isTrue);
      expect(hasViolinFingering(61, ScaleType.major, 1), isFalse);
      expect(violinFingeringRemoteCount, 2);
    });

    test('entrada inválida é ignorada, sem derrubar as boas', () {
      final n = setViolinFingeringFromJson(items([
        '{"pc":99,"alt":false,"type":"major","oct":3,"marks":{}}',
        '{"pc":2,"alt":false,"type":"xyz","oct":3,"marks":{}}',
        '{"pc":2,"alt":false,"type":"major","oct":9,"marks":{}}',
        '{"pc":2,"alt":false,"type":"major","oct":1,"marks":{"99":"1"}}',
        '{"pc":2,"alt":false,"type":"major","oct":1,"marks":{"1":"7"}}',
        '{"pc":0,"alt":true,"type":"major","oct":1,"marks":{}}',
        '{"pc":2,"alt":false,"type":"major","oct":1,"marks":{},"ottava":[5,2]}',
        '{"pc":4,"alt":false,"type":"major","oct":1,"marks":{"1":"2"}}',
        '3',
      ]));
      expect(n, 1);
      expect(hasViolinFingering(64, ScaleType.major, 1), isTrue);
    });

    test('resposta que não é JSON não derruba o app (fica sem correções)', () {
      expect(setViolinFingeringFromJson('<html>erro</html>'), 0);
      expect(setViolinFingeringFromJson(null), 0);
      expect(violinFingeringRemoteCount, 0);
      expect(hasViolinFingering(58, ScaleType.major, 3), isTrue); // a tabela do app continua
    });
  });
}
