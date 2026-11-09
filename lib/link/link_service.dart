import 'dart:async';
import 'dart:convert';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ai/coach_ai.dart' show kApiBase;

/// Uma pessoa vinculada (o professor de um aluno, ou o aluno de um professor).
class LinkedPerson {
  final String code;
  final String name;
  final int since; // ms desde 1970
  const LinkedPerson(this.code, this.name, this.since);

  Map<String, dynamic> toJson() => {'code': code, 'name': name, 'since': since};
  static LinkedPerson? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      // O que vem do servidor também é conferido: código bem formado, apelido limpo.
      final code = formatShareCode((m['code'] as String?) ?? '');
      if (code == null) return null;
      final since = ((m['since'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000);
      return LinkedPerson(code, cleanText(m['name'] as String?, max: kMaxName), since);
    } catch (_) {
      return null;
    }
  }
}

/// Resposta de uma chamada de vínculo.
class LinkReply {
  /// O servidor aceitou.
  final bool ok;

  /// O vínculo online não está configurado no servidor (sem Redis): segue só no aparelho.
  final bool unavailable;

  /// Sem internet ou servidor fora do ar: tentar de novo depois.
  final bool offline;
  final String? error;
  final List<LinkedPerson> asTeacher;
  final List<LinkedPerson> asStudent;
  final bool created;

  /// Revisão das aulas deste perfil (muda quando um professor publica uma aula).
  final int lr;

  /// Aulas recebidas (resposta de `lessons`).
  final List<SharedLesson> lessons;

  /// O aluno ainda não abriu o app com o vínculo online ligado: tentar de novo depois.
  final bool notReady;

  /// Contadores de novidade: dr = tarefas marcadas pelos alunos, kr = vínculos mudaram.
  final int dr;
  final int kr;

  /// Marcações de "feita" dos alunos (resposta de `dones`).
  final List<DoneEntry> dones;

  /// O pedido foi recusado de vez (4xx): não adianta repetir.
  final bool rejected;
  const LinkReply({
    this.ok = false,
    this.unavailable = false,
    this.offline = false,
    this.error,
    this.asTeacher = const [],
    this.asStudent = const [],
    this.created = false,
    this.lr = 0,
    this.lessons = const [],
    this.notReady = false,
    this.dr = 0,
    this.kr = 0,
    this.dones = const [],
    this.rejected = false,
  });
}

/// Fala com `/api/link`: registra o vínculo professor-aluno dos dois lados e traz
/// as listas atualizadas. Nada além de códigos, apelidos e datas passa por aqui.
class LinkService {
  LinkService({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  Uri? _endpoint() {
    if (kApiBase.isNotEmpty) return Uri.parse('$kApiBase/api/link');
    if (kIsWeb) return Uri.base.resolve('/api/link');
    return null;
  }

  Future<LinkReply> _post(Map<String, dynamic> body) async {
    final ep = _endpoint();
    if (ep == null) return const LinkReply(unavailable: true);
    try {
      final r = await _http
          .post(ep, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      Map<String, dynamic> j = {};
      try {
        j = (jsonDecode(r.body) as Map).cast<String, dynamic>();
      } catch (_) {}
      if (r.statusCode == 503 || r.statusCode == 404) return LinkReply(unavailable: true, error: j['message'] as String?);
      if (r.statusCode == 409 && j['error'] == 'student_not_ready') {
        return LinkReply(notReady: true, error: j['message'] as String?);
      }
      if (r.statusCode != 200) {
        // 5xx: servidor com problema, tentar depois. 4xx: o pedido foi recusado de vez.
        return LinkReply(
            offline: r.statusCode >= 500,
            rejected: r.statusCode >= 400 && r.statusCode < 500 && r.statusCode != 429,
            error: (j['error'] as String?) ?? 'Não foi possível vincular.');
      }
      List<LinkedPerson> list(Object? v) => [for (final x in (v as List? ?? const [])) ?LinkedPerson.tryFrom(x)];
      return LinkReply(
        ok: true,
        asTeacher: list(j['asTeacher']),
        asStudent: list(j['asStudent']),
        created: j['created'] == true,
        lr: ((j['lr'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        dr: ((j['dr'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        kr: ((j['kr'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        dones: [
          for (final x in ((j['dones'] as List?) ?? const []).take(1500)) ?DoneEntry.tryFromWire(x)
        ],
        lessons: [
          for (final x in ((j['lessons'] as List?) ?? const []).take(kMaxLessonKept))
            ?_lessonFrom(x)
        ],
      );
    } catch (_) {
      return const LinkReply(offline: true);
    }
  }

  /// Uma aula vinda do servidor: confere o professor (código bem formado) e limpa tudo.
  static SharedLesson? _lessonFrom(Object? x) {
    try {
      final m = (x as Map).cast<String, dynamic>();
      final by = formatShareCode((m['by'] as String?) ?? '');
      if (by == null) return null;
      return SharedLesson.tryFromWire(m, teacherCode: by);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _auth(String code, String secret, String? name) => {
        'code': code,
        'secret': secret,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      };

  /// Traz os vínculos de [code] (e publica o apelido, se houver).
  Future<LinkReply> sync(String code, String secret, {String? name}) =>
      _post({..._auth(code, secret, name), 'action': 'sync'});

  /// Cria o vínculo. [role] é o papel de QUEM PEDE: 'teacher' (li o QR do aluno) ou
  /// 'student' (li o QR do professor).
  Future<LinkReply> link(String code, String secret, {required String role, required String other, String? name}) =>
      _post({..._auth(code, secret, name), 'action': 'link', 'role': role, 'other': other});

  Future<LinkReply> unlink(String code, String secret, {required String role, required String other}) =>
      _post({..._auth(code, secret, null), 'action': 'unlink', 'role': role, 'other': other});

  /// PROFESSOR: publica uma aula encerrada para o aluno [other] (já vinculado).
  Future<LinkReply> publishLesson(String code, String secret,
          {required String other, required Map<String, dynamic> lesson}) =>
      _post({..._auth(code, secret, null), 'action': 'lesson', 'other': other, 'lesson': lesson});

  /// Só os contadores de novidade (1 comando no servidor): o app baixa listas só se algo mudou.
  Future<LinkReply> rev(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'rev'});

  /// ALUNO: avisa que fez (ou desmarcou) a tarefa [task] da aula [lesson] do professor [teacher].
  Future<LinkReply> markDone(String code, String secret,
          {required String teacher, required String lesson, required String task, required bool done}) =>
      _post({..._auth(code, secret, null), 'action': 'done', 'other': teacher, 'lesson': lesson, 'task': task, 'done': done});

  /// PROFESSOR: busca o que os alunos marcaram como feito.
  Future<LinkReply> dones(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'dones'});

  /// ALUNO: busca as aulas dos professores a que está vinculado.
  Future<LinkReply> lessons(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'lessons'});

  void dispose() => _http.close();
}
