// Dois aparelhos da mesma conta trocando dados pelo espelho (servidor simulado em memória).
import 'dart:convert';
import 'dart:math';

import 'package:afina/link/link_service.dart';
import 'package:afina/link/mirror_engine.dart';
import 'package:afina_core/afina_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Servidor simulado: guarda seções com versão, ignora versão antiga e conta a revisão.
class FakeMirrorServer {
  final Map<String, ({int u, String? d, bool x})> secs = {};
  int mr = 0;
  bool down = false;
  int calls = 0;

  http.Client client() => MockClient((req) async {
        calls++;
        if (down) return http.Response('{"error":"x"}', 500);
        final b = jsonDecode(req.body) as Map;
        Map<String, dynamic> ok(Map<String, dynamic> m) => {'ok': true, ...m};
        late Map<String, dynamic> out;
        switch (b['action']) {
          case 'mi_list':
            out = ok({'mr': mr, 'secs': {for (final e in secs.entries) e.key: {'u': e.value.u, if (e.value.x) 'x': 1}}});
          case 'mi_get':
            out = ok({
              'mitems': {
                for (final s in (b['secs'] as List).cast<String>())
                  if (secs[s] != null) s: secs[s]!.x ? {'u': secs[s]!.u, 'x': 1} : {'u': secs[s]!.u, 'd': secs[s]!.d}
              }
            });
          case 'mi_put':
            final cur = secs[b['sec']];
            if (cur != null && cur.u >= (b['u'] as int)) {
              out = ok({'stale': true, 'u': cur.u});
            } else {
              secs[b['sec'] as String] = (u: b['u'] as int, d: b['d'] as String, x: false);
              out = ok({'mr': ++mr});
            }
          case 'mi_del':
            final cur = secs[b['sec']];
            if (cur != null && cur.u >= (b['u'] as int)) {
              out = ok({'stale': true});
            } else {
              secs[b['sec'] as String] = (u: b['u'] as int, d: null, x: true);
              out = ok({'mr': ++mr});
            }
          default:
            out = ok({});
        }
        return http.Response(jsonEncode(out), 200, headers: {'content-type': 'application/json'});
      });
}

class FakeMemory implements MirrorMemory {
  final Map<String, String> m = {};
  @override
  String? read(String key) => m[key];
  @override
  void write(String key, String value) => m[key] = value;
  @override
  void remove(String key) => m.remove(key);
}

/// Um aparelho: os alunos dele e o motor.
class Device {
  Device(FakeMirrorServer server, this.name) {
    engine = MirrorEngine(
      links: LinkService(client: server.client(), endpoint: Uri.parse('http://teste.local/api/link')),
      account: () => ('ACCT-CODE', 'a' * 64),
      memory: () => mem,
      build: build,
      apply: apply,
      deleteLocal: (sec) => students.removeWhere((s) => studentSection(s) == sec),
      changed: () {},
      onError: (e, st) => throw StateError('rodada falhou: $e $st'),
    )..on = true;
  }

  final String name;
  final FakeMemory mem = FakeMemory();
  final List<Student> students = [];
  late final MirrorEngine engine;

  Map<String, LocalSection> build() => {for (final s in students) studentSection(s): LocalSection(studentToSection(s), pristine: isPristineStudent(s))};

  void apply(String sec, String data, {required bool merge}) {
    final remote = studentFromSection(data)!;
    final cur = students.where((s) => studentSection(s) == sec).firstOrNull;
    if (cur == null) {
      students.add(remote);
    } else if (merge) {
      mergeStudentFrom(cur, remote, preferOther: isPristineStudent(cur));
    } else {
      cur.tasks
        ..clear()
        ..addAll(remote.tasks);
      cur.notes
        ..clear()
        ..addAll(remote.notes);
      cur.name = remote.name;
    }
  }

  Student? student(String code) => students.where((s) => s.code == code).firstOrNull;
}

void main() {
  final code = newShareCode(Random(7));
  Assignment task(String id) => Assignment(id: id, title: 'Tarefa $id', created: DateTime(2026, 11, 1));
  Student rich() => Student(id: 'a1', name: 'Ana Souza', code: code, tasks: [task('t1')], notes: [TeacherNote(DateTime(2026, 11, 2), 'Arco')]);
  Student bare() => Student(id: 'v1', name: 'Ana', code: code, remoteName: 'Ana');

  test('o aparelho novo (aluno só com o vínculo) recebe tudo do antigo e NÃO o sobrescreve', () async {
    final srv = FakeMirrorServer();
    final a = Device(srv, 'A')..students.add(rich());
    final b = Device(srv, 'B')..students.add(bare());
    await a.engine.round();
    await b.engine.round();
    expect(b.student(code)!.tasks.map((t) => t.id), ['t1']);
    expect(b.student(code)!.name, 'Ana Souza');
    // o aparelho novo roda de novo e o antigo também: nada se perde
    await b.engine.round();
    await a.engine.round();
    expect(a.student(code)!.tasks.map((t) => t.id), ['t1']);
    expect(a.student(code)!.name, 'Ana Souza');
  });

  test('mesmo se o aparelho novo roda ANTES do antigo, o aluno de fábrica dele não vai para o servidor', () async {
    final srv = FakeMirrorServer();
    final b = Device(srv, 'B')..students.add(bare());
    await b.engine.round();
    expect(srv.secs, isEmpty, reason: 'aluno de fábrica não é enviado');
    final a = Device(srv, 'A')..students.add(rich());
    await a.engine.round();
    await b.engine.round();
    expect(b.student(code)!.tasks, isNotEmpty);
  });

  test('uma tarefa nova num aparelho aparece no outro', () async {
    final srv = FakeMirrorServer();
    final a = Device(srv, 'A')..students.add(rich());
    final b = Device(srv, 'B')..students.add(bare());
    await a.engine.round();
    await b.engine.round();
    b.student(code)!.tasks.add(task('t2'));
    await b.engine.round();
    await a.engine.round();
    expect(a.student(code)!.tasks.map((t) => t.id), ['t1', 't2']);
  });

  test('aluno que passa do teto do espelho não é apagado no servidor nem no outro aparelho', () async {
    final srv = FakeMirrorServer();
    final a = Device(srv, 'A')..students.add(rich());
    final b = Device(srv, 'B')..students.add(bare());
    await a.engine.round();
    await b.engine.round();
    expect(b.student(code)!.tasks, hasLength(1));
    a.student(code)!.notes.addAll([for (var i = 0; i < 3000; i++) TeacherNote(DateTime(2026, 11, 3), 'nota longa número $i ' + 'x' * 60)]);
    expect(studentToSection(a.student(code)!).length, greaterThan(kMaxSectionChars));
    await a.engine.round();
    await a.engine.round();
    await b.engine.round();
    expect(srv.secs.values.where((s) => !s.x), hasLength(1), reason: 'segue no servidor');
    expect(b.student(code), isNotNull, reason: 'o outro aparelho não apaga');
    expect(a.student(code)!.notes.length, greaterThan(2000), reason: 'e não é trocado por nada');
  });

  test('os dois mudam ao mesmo tempo: o resultado soma as duas mudanças nos dois aparelhos', () async {
    final srv = FakeMirrorServer();
    final a = Device(srv, 'A')..students.add(rich());
    final b = Device(srv, 'B')..students.add(bare());
    await a.engine.round();
    await b.engine.round();
    a.student(code)!.tasks.add(task('doA'));
    b.student(code)!.tasks.add(task('doB'));
    await a.engine.round(); // A envia
    await b.engine.round(); // B vê que os dois mudaram: junta e envia
    await a.engine.round(); // A baixa a soma
    for (final d in [a, b]) {
      expect(d.student(code)!.tasks.map((t) => t.id).toSet(), {'t1', 'doA', 'doB'}, reason: d.name);
    }
  });

  test('apagar o aluno num aparelho apaga no outro, mas só se o outro não mexeu', () async {
    final srv = FakeMirrorServer();
    final a = Device(srv, 'A')..students.add(Student(id: 'x', name: 'Beto', tasks: [task('t1')]));
    final b = Device(srv, 'B');
    await a.engine.round();
    await b.engine.round();
    expect(b.students, hasLength(1));
    a.students.clear();
    await a.engine.round();
    await b.engine.round();
    expect(b.students, isEmpty);
  });

  test('apagar aqui não vence uma edição feita lá depois', () async {
    final srv = FakeMirrorServer();
    final a = Device(srv, 'A')..students.add(Student(id: 'x', name: 'Beto', tasks: [task('t1')]));
    final b = Device(srv, 'B');
    await a.engine.round();
    await b.engine.round();
    a.students.clear();
    b.students.single.tasks.add(task('t2'));
    await b.engine.round(); // B envia a edição
    await a.engine.round(); // A tenta apagar, mas o servidor já tem versão mais nova: volta
    expect(a.students, hasLength(1));
    expect(a.students.single.tasks.map((t) => t.id), ['t1', 't2']);
  });

  test('sem internet nada muda e depois tudo se acerta', () async {
    final srv = FakeMirrorServer();
    final a = Device(srv, 'A')..students.add(rich());
    srv.down = true;
    await a.engine.round();
    expect(srv.secs, isEmpty);
    srv.down = false;
    await a.engine.round();
    expect(srv.secs.keys, ['S:$code']);
  });

  test('rodada sem mudança custa só a consulta da lista (barato)', () async {
    final srv = FakeMirrorServer();
    final a = Device(srv, 'A')..students.add(rich());
    await a.engine.round();
    final before = srv.calls;
    await a.engine.round();
    expect(srv.calls - before, 1, reason: 'só mi_list');
  });

  test('proteção: se a lista local sumir de repente, o app não apaga o servidor inteiro', () async {
    final srv = FakeMirrorServer();
    final a = Device(srv, 'A');
    for (var i = 0; i < 6; i++) {
      a.students.add(Student(id: 's$i', name: 'Aluno $i', tasks: [task('t')]));
    }
    await a.engine.round();
    expect(srv.secs.values.where((s) => !s.x), hasLength(6));
    a.students.clear(); // por exemplo, uma leitura que falhou
    await a.engine.round();
    expect(srv.secs.values.where((s) => !s.x), hasLength(6), reason: 'apagar em massa é barrado');
  });
}
