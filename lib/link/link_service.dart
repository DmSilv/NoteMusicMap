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

  /// Versão da foto que a pessoa escolheu mostrar a quem está vinculado (vazio = sem foto).
  final String pv;
  const LinkedPerson(this.code, this.name, this.since, [this.pv = '']);

  Map<String, dynamic> toJson() => {'code': code, 'name': name, 'since': since, if (pv.isNotEmpty) 'pv': pv};
  static LinkedPerson? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      // O que vem do servidor também é conferido: código bem formado, apelido limpo.
      final code = formatShareCode((m['code'] as String?) ?? '');
      if (code == null) return null;
      final since = ((m['since'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000);
      final pv = (m['pv'] as String?) ?? '';
      return LinkedPerson(code, cleanText(m['name'] as String?, max: kMaxName), since, RegExp(r'^[0-9a-f]{8}$').hasMatch(pv) ? pv : '');
    } catch (_) {
      return null;
    }
  }
}

/// Uma seção do espelho baixada do servidor: versão, texto (vazio se foi apagada) e se foi apagada.
class MirrorItem {
  final int u;
  final String? d;
  final bool deleted;
  const MirrorItem(this.u, this.d, {this.deleted = false});
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

  /// O servidor diz que este aparelho NÃO faz mais parte da conta (foi tirado da lista de aparelhos).
  final bool revoked;

  /// Agenda: revisão das aulas marcadas e as aulas marcadas (resposta de `sched`).
  final int sr;
  final List<ClassSlot> slots;

  /// Decisões do professor sobre tarefas (resposta de `verdicts`) e a revisão delas (vr).
  final int vr;
  final List<VerdictEntry> verdicts;

  /// Horários disponíveis: `ar` avisa o professor que um aluno pegou um; `open` são os horários
  /// livres de um professor (resposta de `avail`); `picks` as aulas que alunos pegaram (resposta
  /// de `picks`); `taken` a aula criada quando o aluno pega um horário.
  final int ar;
  final List<ClassSlot> open;
  final List<ClassSlot> picks;
  final ClassSlot? taken;

  /// Notificações: chave pública do servidor (vazia = lembretes desligados no servidor).
  final String pushKey;

  /// Aviso deixado pelo suporte do painel (quando, tipo e texto curto); 0 = nenhum.
  final int snAt;
  final String snKind;
  final String snText;

  /// Conversa particular com o administrador: hora da última mensagem dele (`cr`; 0 = nenhuma), as mensagens (`msg_get`) e se há pedido de crédito sem resposta.
  final int cr;
  final List<DevMsg> msgs;
  final bool askOpen;

  /// Acervo: este perfil está liberado (lb), professores vinculados com acervo (lbT) e os itens (lib_list).
  final bool lb;
  final List<String> lbT;
  final List<LibItem> libItems;

  /// Recursos liberados para este perfil pelas chaves do painel (ex.: 'aula_online'). Vazio = nenhum.
  final List<String> ff;

  /// Link padrão da aula online do professor (volta na sincronização, só com o recurso ligado).
  final String ml;

  /// Como ficou o lembrete da aula marcada: 'scheduled', 'off', 'none' ou 'error'.
  final String? reminder;

  /// Foto de uma pessoa vinculada (resposta de `photo_get`) e a versão dela (também em `photo_put`).
  final String photo;
  final String pv;

  /// Espelho da conta entre aparelhos: a conta tem 2+ aparelhos (`mo`) e a revisão do espelho (`mr`);
  /// as seções do servidor (`mi_list`) e as baixadas (`mi_get`); a gravação foi ignorada por ser antiga; o espelho está desligado.
  final bool mirrorOn;
  final int mirrorRev;
  final Map<String, RemoteSection> secs;
  final Map<String, MirrorItem> items;
  final bool stale;
  final bool mirrorOff;

  /// A pessoa aceitou a cópia na nuvem (só chega na sincronização completa).
  final bool cloudOn;

  /// Resumos de estudo dos alunos que compartilham (resposta de `study_get`): código do aluno -> resumo.
  final Map<String, StudyShare> study;
  const LinkReply({
    this.study = const {},
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
    this.revoked = false,
    this.sr = 0,
    this.vr = 0,
    this.ar = 0,
    this.open = const [],
    this.picks = const [],
    this.taken,
    this.verdicts = const [],
    this.slots = const [],
    this.pushKey = '',
    this.reminder,
    this.snAt = 0,
    this.snKind = '',
    this.snText = '',
    this.cr = 0,
    this.msgs = const [],
    this.askOpen = false,
    this.lb = false,
    this.lbT = const [],
    this.libItems = const [],
    this.ff = const [],
    this.ml = '',
    this.photo = '',
    this.pv = '',
    this.mirrorOn = false,
    this.mirrorRev = 0,
    this.secs = const {},
    this.items = const {},
    this.stale = false,
    this.mirrorOff = false,
    this.cloudOn = false,
  });
}

/// Uma mensagem da conversa com o administrador (`admin` = veio dele).
class DevMsg {
  final String id;
  final bool admin;
  final int atMs;
  final String text;

  /// Trecho da sugestão a que o administrador está respondendo (opcional).
  final String ref;
  final bool asksCredit;
  const DevMsg({required this.id, required this.admin, required this.atMs, required this.text, this.ref = '', this.asksCredit = false});
  static DevMsg? tryFrom(Object? x) {
    if (x is! Map) return null;
    final t = cleanText(x['x'] as String?, max: kMaxDevAdminText, multiline: true);
    if (t.isEmpty) return null;
    return DevMsg(
      id: cleanText(x['i'] as String?, max: 16),
      admin: x['f'] == 'a',
      atMs: ((x['t'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
      text: t,
      ref: cleanText(x['ref'] as String?, max: 90),
      asksCredit: x['ask'] == 1,
    );
  }
}

const int kMaxDevMsgs = 30;
const int kMaxDevAdminText = 600;
const int kMaxDevReply = 280;

/// Fala com `/api/link`: registra o vínculo professor-aluno dos dois lados e traz
/// as listas atualizadas. Nada além de códigos, apelidos e datas passa por aqui.
class LinkService {
  LinkService({http.Client? client, Uri? endpoint}) : _http = client ?? http.Client(), _fixed = endpoint;
  final http.Client _http;

  /// Endereço fixo (usado nos testes, sem rede de verdade).
  final Uri? _fixed;

  Uri? _endpoint() {
    if (_fixed != null) return _fixed;
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
      if (r.statusCode == 503 || r.statusCode == 404) return LinkReply(unavailable: true, error: trOrNull(j['message'] as String?));
      if (r.statusCode == 409 && j['error'] == 'student_not_ready') {
        return LinkReply(notReady: true, error: trOrNull(j['message'] as String?));
      }
      if (r.statusCode == 409 && j['error'] == 'mirror_off') return const LinkReply(rejected: true, mirrorOff: true);
      if (r.statusCode != 200) {
        // 5xx: servidor com problema, tentar depois. 4xx: o pedido foi recusado de vez.
        return LinkReply(
            offline: r.statusCode >= 500,
            rejected: r.statusCode >= 400 && r.statusCode < 500 && r.statusCode != 429,
            // O portão do vínculo responde 403 com esta frase quando o segredo deste aparelho não está mais na conta.
            revoked: r.statusCode == 403 && j['error'] == 'Este código pertence a outro aparelho.',
            error: trOrNull(j['error'] as String?) ?? tr('Não foi possível vincular.'));
      }
      List<LinkedPerson> list(Object? v) => [for (final x in (v as List? ?? const [])) ?LinkedPerson.tryFrom(x)];
      return LinkReply(
        ok: true,
        asTeacher: list(j['asTeacher']),
        asStudent: list(j['asStudent']),
        created: j['created'] == true,
        lb: j['lb'] == 1 || j['lb'] == true,
        lbT: [for (final c in ((j['lbT'] as List?) ?? const []).take(60)) ?(c is String ? formatShareCode(c) : null)],
        ff: [for (final f in ((j['ff'] as List?) ?? const []).take(30)) if (f is String && RegExp(r'^[a-z][a-z0-9_]{1,30}$').hasMatch(f)) f],
        ml: meetingUrl(j['ml'] as String?) ?? '',
        mirrorOn: j['mo'] == 1,
        cloudOn: j['cn'] == 1,
        mirrorRev: ((j['mr'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        secs: _mirrorSecs(j['secs']),
        items: _mirrorItems(j['mitems']),
        stale: j['stale'] == true,
        study: _studyShares(j['study']),
        photo: cleanPhoto(j['photo'] as String?) ?? '',
        pv: RegExp(r'^[0-9a-f]{8}$').hasMatch((j['pv'] as String?) ?? '') ? j['pv'] as String : '',
        libItems: [for (final x in ((j['items'] as List?) ?? const []).take(kLibMaxItems)) ?LibItem.tryFrom(x)],
        lr: ((j['lr'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        dr: ((j['dr'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        sr: ((j['sr'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        vr: ((j['vr'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        ar: ((j['ar'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        open: [for (final x in ((j['open'] as List?) ?? const []).take(kMaxOpenSlots)) ?ClassSlot.tryFrom(x)],
        picks: [for (final x in ((j['slots'] as List?) ?? const []).take(kMaxSlotsPerTeacher)) if (j.containsKey('ar')) ?ClassSlot.tryFrom(x)],
        taken: j['slot'] == null ? null : ClassSlot.tryFrom(j['slot']),
        verdicts: [
          for (final x in ((j['verdicts'] as List?) ?? const []).take(1500)) ?VerdictEntry.tryFromWire(x)
        ],
        pushKey: j['key'] is String && (j['key'] as String).length < 200 ? j['key'] as String : '',
        reminder: j['reminder'] as String?,
        snAt: j['sn'] is Map ? (((j['sn'] as Map)['t'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000) : 0,
        snKind: j['sn'] is Map && ((j['sn'] as Map)['k'] == 'unlink' || (j['sn'] as Map)['k'] == 'agenda') ? (j['sn'] as Map)['k'] as String : '',
        snText: j['sn'] is Map ? cleanText(((j['sn'] as Map)['x'] as String?), max: 60) : '',
        cr: ((j['cr'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000),
        msgs: [for (final x in ((j['m'] as List?) ?? const []).take(kMaxDevMsgs)) ?DevMsg.tryFrom(x)],
        askOpen: j['askOpen'] == true,
        slots: [for (final x in ((j['slots'] as List?) ?? const []).take(kMaxSlotsPerTeacher)) ?_slotFrom(x)],
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

  static final _secRe = RegExp(r'^[A-Za-z0-9:_.-]{1,64}$');

  static Map<String, RemoteSection> _mirrorSecs(Object? v) {
    final out = <String, RemoteSection>{};
    if (v is! Map) return out;
    for (final e in v.entries.take(500)) {
      final k = e.key;
      final m = e.value;
      if (k is! String || !_secRe.hasMatch(k) || m is! Map) continue;
      final u = (m['u'] as num?)?.toInt() ?? 0;
      if (u <= 0) continue;
      out[k] = RemoteSection(u, deleted: m['x'] == 1);
    }
    return out;
  }

  static Map<String, StudyShare> _studyShares(Object? v) {
    final out = <String, StudyShare>{};
    if (v is! Map) return out;
    for (final e in v.entries.take(80)) {
      final s = StudyShare.tryFrom(e.value);
      final k = '${e.key}';
      if (s != null && isValidShareCode(k)) out[k] = s;
    }
    return out;
  }

  static Map<String, MirrorItem> _mirrorItems(Object? v) {
    final out = <String, MirrorItem>{};
    if (v is! Map) return out;
    for (final e in v.entries.take(40)) {
      final k = e.key;
      final m = e.value;
      if (k is! String || !_secRe.hasMatch(k) || m is! Map) continue;
      final u = (m['u'] as num?)?.toInt() ?? 0;
      final d = m['d'];
      if (u <= 0) continue;
      if (m['x'] == 1) {
        out[k] = MirrorItem(u, null, deleted: true);
      } else if (d is String && d.length <= kMaxSectionChars) {
        out[k] = MirrorItem(u, d);
      }
    }
    return out;
  }

  /// Uma aula marcada vinda do servidor: confere o professor e limpa tudo.
  static ClassSlot? _slotFrom(Object? x) {
    try {
      final m = (x as Map).cast<String, dynamic>();
      final by = formatShareCode((m['by'] as String?) ?? '');
      if (by == null) return null;
      return ClassSlot.tryFrom(m, teacherCode: by, teacherName: cleanText(m['tn'] as String?, max: kMaxName));
    } catch (_) {
      return null;
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

  /// Ficha do aparelho em categorias curtas (o AppState preenche; null = a pessoa desligou as estatísticas anônimas).
  Map<String, String>? Function()? deviceProbe;
  DateTime? _dvSent;

  Map<String, dynamic> _auth(String code, String secret, String? name) {
    // A ficha vai na primeira chamada da sessão e a cada 6 horas (o servidor só grava se mudou ou passou 1 dia).
    Map<String, String>? dv;
    final now = DateTime.now();
    if (_dvSent == null || now.difference(_dvSent!) > const Duration(hours: 6)) {
      dv = deviceProbe?.call();
      if (dv != null) _dvSent = now;
    }
    return {
      'code': code,
      'secret': secret,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      'dv': ?dv,
    };
  }

  /// Traz os vínculos de [code] (e publica o apelido, se houver).
  Future<LinkReply> sync(String code, String secret, {String? name}) =>
      _post({..._auth(code, secret, name), 'action': 'sync'});

  /// Cria o vínculo. [role] é o papel de QUEM PEDE: 'teacher' (li o QR do aluno) ou
  /// 'student' (li o QR do professor).
  Future<LinkReply> link(String code, String secret, {required String role, required String other, String? name}) =>
      _post({..._auth(code, secret, name), 'action': 'link', 'role': role, 'other': other});

  Future<LinkReply> unlink(String code, String secret, {required String role, required String other}) =>
      _post({..._auth(code, secret, null), 'action': 'unlink', 'role': role, 'other': other});

  // ---------------- espelho da conta entre aparelhos (só com 2+ aparelhos) ----------------
  Future<LinkReply> miList(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'mi_list'});

  Future<LinkReply> miGet(String code, String secret, List<String> secs) => _post({..._auth(code, secret, null), 'action': 'mi_get', 'secs': secs});

  Future<LinkReply> miPut(String code, String secret, String sec, int u, String data) =>
      _post({..._auth(code, secret, null), 'action': 'mi_put', 'sec': sec, 'u': u, 'd': data});

  Future<LinkReply> miDel(String code, String secret, String sec, int u) => _post({..._auth(code, secret, null), 'action': 'mi_del', 'sec': sec, 'u': u});

  /// Mostra (ou, com texto vazio, tira) a foto do perfil para quem está vinculado.
  Future<LinkReply> photoPut(String code, String secret, String photo) => _post({..._auth(code, secret, null), 'action': 'photo_put', 'photo': photo});

  /// ALUNO: guarda o resumo da semana de estudo para os professores vinculados verem (só quando a pessoa escolheu compartilhar).
  Future<LinkReply> studyPut(String code, String secret, Map<String, dynamic> study) =>
      _post({..._auth(code, secret, null), 'action': 'study_put', 'study': study});

  /// ALUNO: para de compartilhar e apaga o resumo guardado.
  Future<LinkReply> studyOff(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'study_put', 'on': false});

  /// PROFESSOR: os resumos dos alunos que escolheram compartilhar (código do aluno -> resumo).
  Future<LinkReply> studyGet(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'study_get'});

  /// A foto de uma pessoa vinculada a este perfil.
  Future<LinkReply> photoGet(String code, String secret, String other) => _post({..._auth(code, secret, null), 'action': 'photo_get', 'other': other});

  /// PROFESSOR: publica uma aula encerrada para o aluno [other] (já vinculado).
  Future<LinkReply> publishLesson(String code, String secret,
          {required String other, required Map<String, dynamic> lesson}) =>
      _post({..._auth(code, secret, null), 'action': 'lesson', 'other': other, 'lesson': lesson});

  /// Só os contadores de novidade (1 comando no servidor): o app baixa listas só se algo mudou.
  /// Liberação pelo suporte: este aparelho passa a ser o dono do perfil [code] com o [secret] novo,
  /// provando que tem o código de uso único [support] gerado no painel.
  Future<LinkReply> claim(String code, String secret, String support) =>
      _post({..._auth(code, secret, null), 'action': 'claim', 'support': support});

  Future<LinkReply> rev(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'rev'});

  /// Conversa particular com o administrador: lê, responde (curto) e aceita/recusa ser citado no boletim.
  Future<LinkReply> msgGet(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'msg_get'});
  Future<LinkReply> msgPut(String code, String secret, String text) => _post({..._auth(code, secret, null), 'action': 'msg_put', 'x': text});
  /// Relato de problema para o administrador (não abre conversa; ele decide).
  Future<LinkReply> rqPut(String code, String secret, String text, {String version = '', String platform = ''}) =>
      _post({..._auth(code, secret, null), 'action': 'rq_put', 'x': text, 'v': version, 'p': platform});
  /// Exclui a própria conta no servidor (tudo o que ele guarda deste perfil). Idempotente: conta que já não existe também dá ok.
  Future<LinkReply> accountDelete(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'account_delete', 'confirm': true});

  /// Aceita ([on]) ou desliga a cópia na nuvem (desligar apaga a cópia do servidor quando há um aparelho só).
  Future<LinkReply> cloudSet(String code, String secret, bool on) => _post({..._auth(code, secret, null), 'action': 'cloud_set', 'on': on});
  Future<LinkReply> msgOk(String code, String secret, bool yes) => _post({..._auth(code, secret, null), 'action': 'msg_ok', 'yes': yes});

  /// ALUNO: avisa que fez (ou desmarcou) a tarefa [task] da aula [lesson] do professor [teacher].
  Future<LinkReply> markDone(String code, String secret,
          {required String teacher, required String lesson, required String task, required bool done}) =>
      _post({..._auth(code, secret, null), 'action': 'done', 'other': teacher, 'lesson': lesson, 'task': task, 'done': done});

  /// PROFESSOR: valida ([verdict] ok), devolve (back) ou apaga a decisão (null) sobre uma tarefa do aluno.
  Future<LinkReply> sendVerdict(String code, String secret,
          {required String student, required String lesson, required String task, Verdict? verdict}) =>
      _post({
        ..._auth(code, secret, null),
        'action': 'verdict',
        'other': student,
        'lesson': lesson,
        'task': task,
        'verdict': verdict == null ? '' : verdictWire(verdict),
      });

  /// ALUNO: busca as decisões do professor sobre as suas tarefas.
  Future<LinkReply> verdicts(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'verdicts'});

  /// PROFESSOR: cria, muda ou apaga (slot cancelado) um horário disponível.
  Future<LinkReply> availPut(String code, String secret, {required ClassSlot slot}) =>
      _post({..._auth(code, secret, null), 'action': 'avail_put', 'slot': slot.toWire()});

  /// ALUNO: horários livres do professor [teacher].
  Future<LinkReply> avail(String code, String secret, {required String teacher}) =>
      _post({..._auth(code, secret, null), 'action': 'avail', 'other': teacher});

  /// ALUNO: pega o horário [slotId] do professor [teacher] (o primeiro que pega leva).
  Future<LinkReply> availTake(String code, String secret, {required String teacher, required String slotId}) =>
      _post({..._auth(code, secret, null), 'action': 'avail_take', 'other': teacher, 'slot': slotId});

  /// PROFESSOR: aulas que alunos pegaram.
  Future<LinkReply> picks(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'picks'});

  /// PROFESSOR: busca o que os alunos marcaram como feito.
  Future<LinkReply> dones(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'dones'});

  /// PROFESSOR: marca, muda ou cancela uma aula (o servidor agenda o lembrete).
  Future<LinkReply> schedPut(String code, String secret, {required String student, required ClassSlot slot}) =>
      _post({..._auth(code, secret, null), 'action': 'sched_put', 'other': student, 'slot': slot.toWire()});

  /// ALUNO: busca as aulas marcadas pelos professores.
  Future<LinkReply> sched(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'sched'});

  /// Notificações: o servidor está pronto? (devolve a chave pública).
  Future<LinkReply> pushKey(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'push_key'});

  /// Registra a inscrição de notificação deste aparelho.
  Future<LinkReply> pushSub(String code, String secret, Map<String, dynamic> sub) =>
      _post({..._auth(code, secret, null), 'action': 'push_sub', 'sub': sub});

  Future<LinkReply> pushUnsub(String code, String secret, String endpoint) =>
      _post({..._auth(code, secret, null), 'action': 'push_unsub', 'endpoint': endpoint});

  /// ACERVO: itens do professor [teacher] (o aluno vê o que é para ele); sem [teacher], os do próprio professor.
  Future<LinkReply> libList(String code, String secret, {String? teacher}) =>
      _post({..._auth(code, secret, null), 'action': 'lib_list', 'other': ?teacher});

  Future<LinkReply> libPut(String code, String secret, LibItem item) =>
      _post({..._auth(code, secret, null), 'action': 'lib_put', 'item': item.toWire()});

  Future<LinkReply> libDel(String code, String secret, String id) => _post({..._auth(code, secret, null), 'action': 'lib_del', 'id': id});

  /// ALUNO: denuncia um item (o painel avalia e pode esconder).
  Future<LinkReply> libReport(String code, String secret, {required String teacher, required String id}) =>
      _post({..._auth(code, secret, null), 'action': 'lib_report', 'other': teacher, 'id': id});

  /// PROFESSOR: guarda (ou limpa, com '') o link padrão da aula online.
  Future<LinkReply> meetSet(String code, String secret, String link) =>
      _post({..._auth(code, secret, null), 'action': 'meet_set', 'link': link});

  /// ALUNO: busca as aulas dos professores a que está vinculado.
  Future<LinkReply> lessons(String code, String secret) => _post({..._auth(code, secret, null), 'action': 'lessons'});

  void dispose() => _http.close();
}
