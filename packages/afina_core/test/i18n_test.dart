import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    Lang.current = AppLang.pt;
    Lang.monthFirst = false;
  });

  group('idioma do aparelho', () {
    test('inglês só se o aparelho estiver em inglês; o resto fica em português', () {
      expect(Lang.forDevice('en-US'), AppLang.en);
      expect(Lang.forDevice('en'), AppLang.en);
      expect(Lang.forDevice('EN_gb'), AppLang.en);
      expect(Lang.forDevice('pt-BR'), AppLang.pt);
      expect(Lang.forDevice('es-MX'), AppLang.pt);
      expect(Lang.forDevice(''), AppLang.pt);
      expect(Lang.forDevice(null), AppLang.pt);
    });

    test('a escolha em Ajustes vale mais do que o aparelho; "auto" segue o aparelho', () {
      expect(Lang.resolve('pt', 'en-US'), AppLang.pt);
      expect(Lang.resolve('en', 'pt-BR'), AppLang.en);
      expect(Lang.resolve('auto', 'en-US'), AppLang.en);
      expect(Lang.resolve('auto', 'pt-BR'), AppLang.pt);
      expect(Lang.resolve(null, 'en-GB'), AppLang.en);
      expect(Lang.resolve('xx', 'pt-BR'), AppLang.pt);
    });
  });

  group('tr()', () {
    test('em português devolve o próprio texto, com os marcadores preenchidos', () {
      Lang.current = AppLang.pt;
      expect(tr('Salvar'), 'Salvar');
      expect(tr('{0} aula{1} em {2}', [3, 's', 'novembro']), '3 aulas em novembro');
    });

    test('em inglês usa o dicionário; sem tradução, cai no português (nunca fica em branco)', () {
      Lang.current = AppLang.en;
      expect(tr('Salvar'), 'Save');
      expect(tr('Este texto não existe no dicionário'), 'Este texto não existe no dicionário');
      expect(tr('Este {0} não existe', ['x']), 'Este x não existe');
    });

    test('a tradução pode trocar a ordem dos marcadores', () {
      Lang.current = AppLang.en;
      // "{0} de {1}, {2}" (dia, mês, dia da semana) vira "{2}, {1} {0}"
      expect(tr('{0} de {1}, {2}', [12, 'November', 'Thu']), 'Thu, November 12');
      Lang.current = AppLang.pt;
      expect(tr('{0} de {1}, {2}', [12, 'novembro', 'qui']), '12 de novembro, qui');
    });

    test('o contexto (@@) distingue sentidos e nunca aparece na tela', () {
      Lang.current = AppLang.pt;
      expect(tr('{0} de {1}@@mês', ['novembro', 2026]), 'novembro de 2026');
      expect(tr('{0} de {1}@@dia', ['Aula', '12/11']), 'Aula de 12/11');
      Lang.current = AppLang.en;
      expect(tr('{0} de {1}@@dia', ['Lesson', '12/11']), 'Lesson on 12/11');
      expect(tr('{0} de {1}', [3, 5]), '3 of 5');
    });

    test('marcador sem argumento fica como está', () {
      expect(fillSlots('a {0} b {1}', ['x']), 'a x b {1}');
    });

    test('mensagens do servidor: traduz se souber, senão devolve como veio', () {
      Lang.current = AppLang.en;
      expect(trOrNull('Este horário já passou.'), 'This slot has already passed.');
      expect(trOrNull('Mensagem nova do servidor.'), 'Mensagem nova do servidor.');
      expect(trOrNull(null), isNull);
    });
  });

  group('datas', () {
    test('dia primeiro por padrão; mês primeiro só no inglês dos EUA, Canadá e Filipinas', () {
      final d = DateTime(2026, 11, 12);
      expect(fmtDayMonth(d), '12/11');
      expect(fmtDayMonthYear(d), '12/11/2026');
      Lang.current = AppLang.en;
      Lang.setRegionFrom('en-GB');
      expect(Lang.monthFirst, isFalse);
      expect(fmtDayMonth(d), '12/11');
      Lang.setRegionFrom('en-US');
      expect(Lang.monthFirst, isTrue);
      expect(fmtDayMonth(d), '11/12');
      expect(fmtDayMonthYear(d), '11/12/2026');
      Lang.setRegionFrom('en_CA');
      expect(Lang.monthFirst, isTrue);
      Lang.current = AppLang.pt;
      Lang.setRegionFrom('en-US');
      expect(Lang.monthFirst, isFalse, reason: 'em português a data é sempre dia/mês');
    });

    test('os textos de data do núcleo seguem a ordem', () {
      final d = DateTime(2026, 11, 9); // segunda
      expect(fmtLessonDay(d), 'segunda, 09/11');
      Lang.current = AppLang.en;
      Lang.setRegionFrom('en-US');
      expect(fmtLessonDay(d), 'Monday, 11/09');
    });
  });

  group('nomes que não dependem do texto', () {
    test('escala menor/maior vem do tipo, não do rótulo (que muda com o idioma)', () {
      Lang.current = AppLang.en;
      expect(ScaleType.naturalMinor.isMinor, isTrue);
      expect(ScaleType.minorTriad1.isMinor, isTrue);
      expect(ScaleType.major.isMinor, isFalse);
      expect(ScaleType.major.label, 'Major');
      expect(ScaleType.naturalMinor.label, 'Natural minor');
    });

    test('notas em inglês: C D E F G A B', () {
      Lang.current = AppLang.en;
      expect(noteNamesSharp.take(3).toList(), ['C', 'C♯', 'D']);
      Lang.current = AppLang.pt;
    });

    test('nome automático de aluno vale nos dois idiomas', () {
      expect(isDefaultStudentName('Aluno K7QM', 'K7QM'), isTrue);
      expect(isDefaultStudentName('Student K7QM', 'K7QM'), isTrue);
      expect(isDefaultStudentName('Ana', 'K7QM'), isFalse);
    });
  });
}
