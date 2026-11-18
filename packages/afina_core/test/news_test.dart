import 'dart:convert';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  String body(List<Map<String, Object?>> items) => jsonEncode({'v': 1, 'items': items});

  test('lê a lista publicada, corta o tamanho e ignora o que está incompleto', () {
    final r = parseNews(body([
      {'id': 'a1', 't': 'Olá', 'b': 'Texto', 'p': 5},
      {'id': '', 't': 'sem id', 'b': 'x'},
      {'id': 'a2', 't': '', 'b': 'sem título'},
      {'id': 'a3', 't': 'x' * 200, 'b': 'y' * 900},
      {'id': 'a1', 't': 'repetido', 'b': 'x'},
    ]))!;
    expect(r.map((e) => e.id), ['a1', 'a3']);
    expect(r[1].title.length, kMaxNewsTitle);
    expect(r[1].body.length, kMaxNewsBody);
  });

  test('resposta estranha devolve null (o app mantém o que já tem)', () {
    expect(parseNews('<html>erro</html>'), isNull);
    expect(parseNews('{"items": 3}'), isNull);
    expect(parseNews('[]'), isNull);
    expect(parseNews('{"items": []}'), isEmpty);
  });

  test('no máximo $kMaxNewsShown novidades', () {
    final many = [for (var i = 0; i < 40; i++) {'id': 'n$i', 't': 'T$i', 'b': 'B'}];
    expect(parseNews(body(many))!.length, kMaxNewsShown);
  });

  test('inglês só quando existe título e texto em inglês', () {
    final both = NewsItem(id: 'a', title: 'Olá', body: 'Corpo', titleEn: 'Hi', bodyEn: 'Body');
    final half = NewsItem(id: 'b', title: 'Olá', body: 'Corpo', titleEn: 'Hi');
    final old = Lang.current;
    try {
      Lang.current = AppLang.en;
      expect(both.shownTitle, 'Hi');
      expect(both.shownBody, 'Body');
      expect(half.shownTitle, 'Olá', reason: 'meia tradução não mistura idiomas');
      expect(half.shownBody, 'Corpo');
      Lang.current = AppLang.pt;
      expect(both.shownTitle, 'Olá');
    } finally {
      Lang.current = old;
    }
  });

  test('a que aparece sozinha é a mais recente ainda não vista', () {
    final items = [
      const NewsItem(id: 'c', title: 'C', body: 'x'),
      const NewsItem(id: 'b', title: 'B', body: 'x'),
      const NewsItem(id: 'a', title: 'A', body: 'x'),
    ];
    expect(pendingNews(items, {})!.id, 'c');
    expect(pendingNews(items, {'c'})!.id, 'b');
    expect(pendingNews(items, {'a', 'b', 'c'}), isNull);
    expect(pendingNews(const [], {}), isNull);
  });

  test('rótulo de feedback: só idea/fix; o apelido só vem com o rótulo', () {
    final r = parseNews('{"items":[{"id":"a","t":"A","b":"x","fb":"idea","fn":"Ana"},{"id":"b","t":"B","b":"x","fb":"fix"},{"id":"c","t":"C","b":"x","fb":"outro","fn":"Eu"},{"id":"d","t":"D","b":"x","fn":"Eu"}]}')!;
    expect(r[0].feedback, 'idea');
    expect(r[0].credit, 'Ana');
    expect(r[1].feedback, 'fix');
    expect(r[1].credit, '');
    expect(r[2].feedback, '');
    expect(r[2].credit, '');
    expect(r[3].credit, '');
  });
}
