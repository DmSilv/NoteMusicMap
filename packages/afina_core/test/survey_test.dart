import 'dart:convert';

import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  String body(Object? s) => jsonEncode({'v': 1, 'survey': s});

  test('lê a pesquisa ativa com perguntas de escolha e de texto', () {
    final r = parseSurvey(body({
      'id': 'ab12cd34ef', 't': 'Pesquisa', 'te': 'Survey', 'k': 'rapida', 'max': 3,
      'qs': [
        {'id': 'mais_usa', 'k': 'choice', 'q': 'Qual?', 'r': 1, 'o': [{'v': 'A', 'e': 'a'}, {'v': 'B'}]},
        {'id': 'melhorar', 'k': 'text', 'q': 'O quê?'},
      ],
    }));
    expect(r.ok, isTrue);
    final s = r.survey!;
    expect(s.id, 'ab12cd34ef');
    expect(s.key, 'rapida');
    expect(s.questions.length, 2);
    expect(s.questions[0].required, isTrue);
    expect(s.questions[0].options[0].valueEn, 'a');
    expect(s.questions[1].isChoice, isFalse);
  });

  test('sem pesquisa ativa: ok com null; resposta estranha: não ok (o app mantém o que tinha)', () {
    expect(parseSurvey(body(null)).ok, isTrue);
    expect(parseSurvey(body(null)).survey, isNull);
    expect(parseSurvey('<html>erro</html>').ok, isFalse);
    expect(parseSurvey('{"items": []}').ok, isFalse);
    expect(parseSurvey(body({'id': 'Id Ruim!', 't': 'x', 'qs': []})).ok, isFalse);
  });

  test('pergunta de escolha sem 2 opções é ignorada; sem nenhuma pergunta vira "sem pesquisa"', () {
    final r = parseSurvey(body({
      'id': 'a', 't': 'x',
      'qs': [
        {'id': 'q1', 'k': 'choice', 'q': 'Só uma', 'o': [{'v': 'A'}]},
      ],
    }));
    expect(r.ok, isTrue);
    expect(r.survey, isNull);
  });
}
