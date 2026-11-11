import 'package:afina_core/afina_core.dart';
import 'package:test/test.dart';

LibItem item(String id, String title, String folder) => LibItem(id: id, title: title, folder: folder, url: 'https://drive.google.com/file/d/$id/view');

void main() {
  group('links do acervo', () {
    test('aceita só https dos sites da lista', () {
      expect(libraryUrl('https://drive.google.com/file/d/abc/view'), isNotNull);
      expect(libraryUrl('https://www.youtube.com/watch?v=abc'), isNotNull);
      expect(libraryUrl('https://imslp.org/wiki/Violin_Concerto'), isNotNull);
      expect(libraryUrl('http://drive.google.com/file/d/abc'), isNull);
      expect(libraryUrl('https://drive.google.com.golpe.com/x'), isNull);
      expect(libraryUrl('https://golpe.com/drive.google.com'), isNull);
      expect(libraryUrl('https://user:senha@drive.google.com/x'), isNull);
      expect(libraryUrl('javascript:alert(1)'), isNull);
      expect(libraryUrl('https://drive.google.com/x y'), isNull);
      expect(libraryUrl(''), isNull);
      expect(libraryUrl(null), isNull);
    });

    test('lê o item vindo do servidor e descarta o que está ruim', () {
      final ok = LibItem.tryFrom({'id': 'ab12', 'k': 'r', 'f': 'Vivaldi', 't': 'Verão', 'u': 'https://drive.google.com/file/d/x/view', 'to': ['AAAA-BBBB'], 'x': 1});
      expect(ok, isNotNull);
      expect(ok!.isRepertoire, isTrue);
      expect(ok.to, ['AAAA-BBBB']);
      expect(ok.hidden, isTrue);
      expect(LibItem.tryFrom({'id': 'ab12', 't': 'x', 'u': 'https://golpe.com/x'}), isNull);
      expect(LibItem.tryFrom({'id': 'AB!', 't': 'x', 'u': 'https://drive.google.com/x/y/z'}), isNull);
      expect(LibItem.tryFrom('lixo'), isNull);
    });

    test('o item vai ao servidor com a declaração do professor', () {
      final w = item('ab12', 'Estudos op. 45', 'Wohlfahrt').toWire();
      expect(w['ok'], true);
      expect(w['f'], 'Wohlfahrt');
      expect(w.containsKey('to'), isFalse);
    });

    test('pastas em ordem alfabética, sem repetir', () {
      final l = [item('a1', 'A', 'Vivaldi'), item('b2', 'B', 'Kayser'), item('c3', 'C', 'Vivaldi')];
      expect(libraryFolders(l), ['Kayser', 'Vivaldi']);
    });
  });

  group('tarefa "Material do professor"', () {
    final items = [item('a1', 'Estudos op. 45', 'Wohlfahrt'), item('b2', 'Verão', 'Vivaldi'), item('c3', 'Inverno', 'Vivaldi')];

    test('acha o item exato pelo título e pela pasta', () {
      final m = const MaterialRef(title: 'Estudos op. 45', folder: 'Wohlfahrt').resolve(items);
      expect(m.item?.id, 'a1');
    });
    test('sem a pasta, acha pelo título (sem diferenciar maiúsculas)', () {
      expect(const MaterialRef(title: 'verão').resolve(items).item?.id, 'b2');
    });
    test('pasta inteira: o assunto é o nome da pasta', () {
      final m = const MaterialRef(title: 'Vivaldi').resolve(items);
      expect(m.item, isNull);
      expect(m.folder, 'Vivaldi');
    });
    test('item apagado: cai na pasta; pasta apagada: acervo todo', () {
      final m = const MaterialRef(title: 'Primavera', folder: 'Vivaldi').resolve(items);
      expect(m.item, isNull);
      expect(m.folder, 'Vivaldi');
      expect(const MaterialRef(title: 'Nada', folder: 'Outra').resolve(items).found, isFalse);
      expect(const MaterialRef().isAll, isTrue);
    });
    test('o texto mostrado ao aluno', () {
      expect(const MaterialRef().label, 'Material do professor');
      expect(const MaterialRef(folder: 'Vivaldi').label, 'Vivaldi');
      expect(const MaterialRef(title: 'Verão', folder: 'Vivaldi').label, 'Verão · Vivaldi');
    });
    test('a tarefa de material volta do servidor com o tipo certo', () {
      final a = Assignment(id: 't1', title: 'Verão · Vivaldi', kind: TaskKind.material, subject: 'Verão', detail: 'Vivaldi', created: DateTime(2026));
      final b = Assignment.tryFrom(a.toJson())!;
      expect(b.kind, TaskKind.material);
      expect(b.subject, 'Verão');
    });
  });
}
