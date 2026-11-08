import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:vibration/vibration.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:record/record.dart' show AudioRecorder;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'ai/coach_ai.dart';
import 'dev/frame_meter.dart';
import 'audio/audio_out.dart';
import 'platform/hard_reset.dart';
import 'platform/web_vibrate.dart';
import 'audio/pitch_source.dart';
import 'data/repository.dart';
import 'feedback/feedback_service.dart';
import 'link/link_service.dart';
import 'voice/dictation.dart';
import 'package:afina_core/afina_core.dart';

/// Ativa a simulação de execução (sem som), só para testes: --dart-define=DEV_DEMO=true.
const bool kDevDemo = bool.fromEnvironment('DEV_DEMO');

/// Identificador desta versão (a Vercel grava o commit); vazio em builds locais.
const String kBuildId = String.fromEnvironment('BUILD_ID');

/// O último tempo marcado pelo metrônomo (para a tela acender a bolinha).
class MetroBeat {
  final int beat;
  final int bar;
  final Accent accent;

  /// Silêncio do modo desafio: a tela não mostra nada.
  final bool hidden;
  const MetroBeat(this.beat, this.bar, this.accent, {this.hidden = false});
  static const idle = MetroBeat(-1, -1, Accent.weak);
}

/// Jeito de marcar o tempo de estudo.
enum StudyMode { pomodoro, stopwatch, custom }

enum TunerMode { strings, chromatic }

/// Quão permissivo é o microfone.
/// rigorous: só notas limpas e fortes. free: aceita sons fracos, com ar,
/// vibrato forte ou ruído de fundo (pode errar mais a oitava).
enum MicSensitivity {
  rigorous('Rigoroso', 0.88, 0.006, 3),
  normal('Normal', 0.72, 0.0018, 2),
  free('Livre', 0.55, 0.0008, 1);

  final String label;
  final double minClarity;
  final double minRms;
  final int onsetFrames;
  const MicSensitivity(this.label, this.minClarity, this.minRms, this.onsetFrames);
}

/// Estado central do app. Sem login, sem rede: tudo fica no aparelho.
class AppState extends ChangeNotifier {
  // ---------------- Afinação ----------------
  double refA = 440;
  TuningSystem system = TuningSystem.equal;
  int tonicPc = 9; // Lá
  Anchor anchor = Anchor.a4;
  bool preferFlats = false;
  int transpose = 0;
  String instrumentId = 'violino';
  TunerMode tunerMode = TunerMode.strings;
  /// Faixa "afinada" (±cents): padrão único do app, sem níveis.
  double get zoneCents => kInTuneCents;
  HistoryMode history = HistoryMode.medium;
  double holdSeconds = 0; // 0 = a cor fica até zerar a grade (histórico das notas tocadas)

  TuningConfig get cfg => TuningConfig(
        refA: refA,
        system: system,
        tonicPc: tonicPc,
        anchor: anchor,
        preferFlats: preferFlats,
        transpose: transpose,
      );
  Instrument get instrument => instrumentById(instrumentId);

  // ---------------- Notificadores finos (desempenho) ----------------
  /// Muda a cada leitura do microfone (~30x/s). Quem não mostra dados ao vivo
  /// não deve escutar isto.
  final ValueNotifier<int> liveTick = ValueNotifier(0);

  /// Mudanças ao vivo OU de configuração: para telas com dados ao vivo.
  late final Listenable live = Listenable.merge([this, liveTick]);

  /// Muda a cada tique do Pomodoro (500 ms).
  final ValueNotifier<int> pomoTick = ValueNotifier(0);

  /// Pomodoro mudou (tique ou ação do usuário): para o cartão e o mini-cronômetro.
  late final Listenable pomoLive = Listenable.merge([this, pomoTick]);

  /// Só muda quando o tema muda: o MaterialApp escuta apenas isto.
  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

  // ---------------- Pomodoro ----------------
  PomodoroTimer pomo = PomodoroTimer();
  Map<String, int> pomoDays = {}; // yyyy-MM-dd -> pomodoros concluídos
  bool pomoChime = true;
  bool pomoVibrate = true;
  double pomoVolume = 0.5;
  Timer? _pomoTimer;
  final ChimePlayer _chime = ChimePlayer();

  int get _nowMs => DateTime.now().millisecondsSinceEpoch;
  int get pomoRemainingMs => pomo.remainingMs(_nowMs);
  double get pomoProgress => pomo.progress(_nowMs);
  int get pomoToday => pomoDays[dayKey(DateTime.now())] ?? 0;

  // ---------------- Perfil (identidade sem cadastro) ----------------
  /// Dados do perfil (sessões, alunos) passam por aqui. Hoje é local; na nuvem
  /// será outro [Repository], sem mexer nas telas.
  Repository? _repo;

  /// Quem é você neste app: id, código e a capacidade "professor". Todo mundo
  /// começa como aluno; o modo professor é só uma chave a mais, no mesmo perfil.
  Profile profile = Profile.create(math.Random.secure());

  void setProfileName(String? name) {
    final n = name?.trim();
    profile.name = (n == null || n.isEmpty) ? null : n;
    _repo?.saveProfile(profile);
    notifyListeners();
  }

  /// Anota que o usuário viu/copiou a chave de recuperação (para o lembrete sumir).
  void markRecoveryShown() {
    profile.recoveryShownAt = DateTime.now();
    _repo?.saveProfile(profile);
    notifyListeners();
  }

  /// Assume um perfil a partir da chave de recuperação. O histórico e os alunos
  /// que já estão neste aparelho continuam e passam a ser deste perfil.
  /// Devolve false se a chave estiver errada. O modo professor deste aparelho
  /// não muda.
  bool restoreProfile(String key) {
    final p = profileFromRecoveryKey(key);
    if (p == null) return false;
    p.teacher = profile.teacher;
    p.recoveryShownAt = DateTime.now();
    profile = p;
    // Os vínculos são da identidade: recomeça a lista de professores e deixa os alunos serem reavaliados.
    myTeachers = [];
    _unlinkStudents.clear();
    _unlinkTeachers.clear();
    for (final s in students) {
      if (s.linkState != 'ended') s.linkState = null;
    }
    _saveLinks();
    _saveTeacher();
    _repo?.saveProfile(profile);
    notifyListeners();
    return true;
  }

  // ---------------- Área do professor (local, sem login) ----------------
  /// A capacidade "professor" mora no perfil (desligada por padrão).
  bool get teacherMode => profile.teacher;
  set teacherMode(bool v) => profile.teacher = v;
  String? teacherPinHash;
  String teacherSalt = 'nm';
  bool teacherUnlocked = false; // vale só nesta abertura do app
  List<Student> students = [];
  String? activeStudentId;

  Student? get activeStudent {
    for (final s in students) {
      if (s.id == activeStudentId) return s;
    }
    return null;
  }

  Student? studentById(String id) {
    for (final s in students) {
      if (s.id == id) return s;
    }
    return null;
  }

  void setTeacherMode(bool v) {
    teacherMode = v;
    if (!v) {
      activeStudentId = null; // sem modo professor, tudo volta a ser do próprio usuário
      teacherUnlocked = false;
    }
    _saveTeacher();
    notifyListeners();
  }

  bool get teacherLocked => teacherPinHash != null && !teacherUnlocked;

  bool unlockTeacher(String pin) {
    final ok = teacherPinHash != null && hashPin(pin, teacherSalt) == teacherPinHash;
    if (ok) {
      teacherUnlocked = true;
      notifyListeners();
    }
    return ok;
  }

  void setTeacherPin(String? pin) {
    teacherPinHash = (pin == null || pin.isEmpty) ? null : hashPin(pin, teacherSalt);
    teacherUnlocked = true;
    _saveTeacher();
    notifyListeners();
  }

  /// Aluno que já está na lista com este código (ou null).
  Student? studentByCode(String code) {
    final c = formatShareCode(code);
    if (c == null) return null;
    for (final s in students) {
      if (s.code == c) return s;
    }
    return null;
  }

  /// Confere o cadastro de um aluno (nome e código) com as regras do núcleo:
  /// não pode ser você mesmo, nem o seu professor, nem repetir outro aluno.
  StudentEntryCheck checkStudent(String name, String code, {String? exceptId}) => checkStudentEntry(
        name: name,
        codeInput: code,
        ownCode: profile.shareCode,
        ownName: profile.name,
        existing: students,
        exceptId: exceptId,
      );

  /// Só o código (ao editar o código de um aluno). Devolve o problema, ou null se está certo
  /// (vazio também está certo: o código é opcional). [exceptId] ignora o próprio aluno.
  String? checkStudentCode(String input, {String? exceptId}) {
    if (input.trim().isEmpty) return null;
    final name = (exceptId == null ? null : studentById(exceptId)?.name) ?? 'aluno';
    return checkStudent(name, input, exceptId: exceptId).code;
  }

  /// Confere um código de professor antes de registrá-lo como "meu professor".
  String? checkTeacherCode(String code) {
    final c = formatShareCode(code);
    if (c == null) return 'Código inválido. Confira com o professor.';
    if (c == profile.shareCode) return 'Este é o seu próprio código: você não pode ser o seu próprio professor.';
    return null;
  }

  void setStudentCode(String id, String? input) {
    final s = studentById(id);
    if (s == null) return;
    if (input != null && input.trim().isNotEmpty && checkStudentCode(input, exceptId: id) != null) return;
    final old = s.code;
    final wasLinked = s.linkState == 'active' || s.linkState == 'pending';
    s.code = (input == null || input.trim().isEmpty) ? null : formatShareCode(input);
    if (old != s.code) {
      if (old != null && wasLinked && linkEnabled) {
        _unlinkStudents.add(old); // o código antigo deixa de ser aluno deste professor
        _saveLinks();
      }
      s.linkState = null;
    }
    _saveTeacher();
    notifyListeners();
    if (s.code != null && old != s.code) unawaited(linkStudentOnline(s));
  }

  /// Cadastra o aluno. Quem chama deve validar antes com [checkStudent]; por segurança,
  /// um código que não passa nas regras (por exemplo, o seu próprio) é descartado aqui.
  Student addStudent(String name, {String? code}) {
    final okCode = (code == null || code.trim().isEmpty) ? null : formatShareCode(code);
    final s = Student(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        name: name.trim(),
        code: okCode != null && checkStudentEntry(
                    name: 'x-validacao',
                    codeInput: okCode,
                    ownCode: profile.shareCode,
                    existing: students)
                .code == null
            ? okCode
            : null);
    students.add(s);
    activeStudentId ??= s.id;
    _saveTeacher();
    notifyListeners();
    if (s.code != null) unawaited(linkStudentOnline(s));
    return s;
  }

  /// Remove vários alunos de uma vez (com histórico, tarefas e observações).
  int removeStudents(Set<String> ids) {
    final before = students.length;
    for (final s in students.where((s) => ids.contains(s.id))) {
      _unlinkStudentOnline(s);
    }
    students.removeWhere((s) => ids.contains(s.id));
    if (ids.contains(activeStudentId)) activeStudentId = null;
    _saveTeacher();
    notifyListeners();
    return before - students.length;
  }

  void removeStudent(String id) {
    final gone = studentById(id);
    if (gone != null) _unlinkStudentOnline(gone);
    students.removeWhere((s) => s.id == id);
    if (activeStudentId == id) activeStudentId = null;
    _saveTeacher();
    notifyListeners();
  }

  void setActiveStudent(String? id) {
    activeStudentId = id;
    _saveTeacher();
    notifyListeners();
  }

  void addTeacherNote(Student s, String text) {
    if (text.trim().isEmpty) return;
    s.notes.insert(0, TeacherNote(DateTime.now(), text.trim()));
    _saveTeacher();
    notifyListeners();
  }

  void addAssignment(Student s,
      {required String title,
      TaskKind kind = TaskKind.scale,
      String subject = '',
      String detail = '',
      String note = '',
      int scaleTypeIndex = 0,
      int tonicPc = 0,
      int octaves = 1,
      double goal = 0.8}) {
    s.tasks.insert(
        0,
        Assignment(
            id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
            title: title,
            kind: kind,
            subject: subject.trim(),
            detail: detail.trim(),
            note: note.trim(),
            scaleTypeIndex: scaleTypeIndex,
            tonicPc: tonicPc,
            octaves: octaves,
            goal: goal,
            created: DateTime.now()));
    if (kind == TaskKind.method) _learnFromTask(subject, detail);
    _saveTeacher();
    notifyListeners();
  }

  /// Muda assunto, detalhe e observação de uma tarefa já passada.
  void editAssignment(Student s, String id, {String? subject, String? detail, String? note}) {
    final i = s.tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    s.tasks[i] = s.tasks[i].copyWith(subject: subject?.trim(), detail: detail?.trim(), note: note?.trim());
    if (s.tasks[i].kind == TaskKind.method) _learnFromTask(s.tasks[i].subject, s.tasks[i].detail);
    _saveTeacher();
    notifyListeners();
  }

  // ---------------- Biblioteca de métodos e lições ----------------
  /// Métodos do professor, cada um com as suas lições. Cresce sozinha com o que
  /// ele digita nas tarefas e também por cadastro e importação.
  List<MethodEntry> methodLibrary = [];

  /// Nomes para sugerir numa tarefa: os do professor primeiro, depois os conhecidos.
  List<String> methodNames() => [
        for (final m in methodLibrary) m.name,
        for (final m in kMethodSuggestions)
          if (findMethod(methodLibrary, m) == null) m,
      ];

  void _saveMethods() => _repo?.saveMethods(methodLibrary);

  /// Cadastra um método (com lições, uma por linha ou separadas por ';'). false se o nome está vazio.
  bool addMethod(String name, [String lessonsText = '']) {
    if (name.trim().isEmpty) return false;
    final lessons = lessonsText.split(RegExp(r'[;\n]')).map((l) => l.trim()).where((l) => l.isNotEmpty);
    final r = mergeMethods(methodLibrary, [MethodEntry(name, lessons.toList())]);
    _saveMethods();
    notifyListeners();
    return !r.nothing;
  }

  void renameMethod(MethodEntry m, String name, String lessonsText) {
    final n = name.trim();
    if (n.isEmpty) return;
    m.name = n;
    m.lessons
      ..clear()
      ..addAll(MethodEntry.tryFrom({'name': n, 'lessons': lessonsText.split(RegExp(r'[;\n]'))})?.lessons ?? []);
    _saveMethods();
    notifyListeners();
  }

  void removeMethod(MethodEntry m) {
    methodLibrary.remove(m);
    _saveMethods();
    notifyListeners();
  }

  /// Importa de um texto colado. Devolve o aviso para o usuário.
  String importMethods(String text) {
    if (text.length > 300000) return 'Esse texto é grande demais. Importe em partes menores.';
    final found = parseMethodsText(text);
    if (found.isEmpty) return 'Não encontrei métodos nesse texto. Use um método por linha, ou "Método: lição 1; lição 2".';
    if (found.length > 500 || found.fold<int>(0, (a, m) => a + m.lessons.length) > 8000) {
      return 'Muitos itens de uma vez (máximo 500 métodos e 8000 lições). Importe em partes.';
    }
    final r = mergeMethods(methodLibrary, found);
    _saveMethods();
    notifyListeners();
    if (r.nothing) return 'Esses métodos e lições já estavam na sua lista.';
    return 'Importado: ${r.methods} método${r.methods == 1 ? '' : 's'} novo${r.methods == 1 ? '' : 's'} '
        'e ${r.lessons} lição${r.lessons == 1 ? '' : 'ões'}.';
  }

  String exportMethods() => exportMethodsText(methodLibrary);
  String exportMethodsAsJson() => exportMethodsJson(methodLibrary);

  /// A biblioteca aprende com a tarefa passada (método e lição novos entram sozinhos).
  void _learnFromTask(String method, String lesson) {
    if (learnMethod(methodLibrary, method, lesson).nothing) return;
    _saveMethods();
  }

  // ---------------- Código do aluno vindo de um QR/link ----------------
  /// Código lido de `?aluno=K7QM-4TXD` na abertura do app (ou null).
  String? incomingStudentCode;

  /// Código de professor lido de `?professor=…` na abertura do app (ou null).
  String? incomingTeacherCode;

  // ---------------- Vínculos online (professor ⇄ aluno) ----------------
  final LinkService links = LinkService();

  /// Professores deste usuário (como aluno). Com `since == 0` ainda não foi confirmado
  /// pelo servidor (sem conexão); os demais vêm do servidor.
  List<LinkedPerson> myTeachers = [];

  /// Códigos dos professores (para as regras de cadastro).
  Set<String> get teacherCodes => {for (final t in myTeachers) t.code};

  /// O professor mais recente (ou null).
  String? get myTeacherCode => myTeachers.isEmpty ? null : myTeachers.last.code;

  /// O vínculo online está ligado? Fica ligado na primeira vez que o usuário vincula
  /// alguém (ler QR ou digitar código), e pode ser desligado no perfil.
  bool linkEnabled = false;

  /// null = ainda não tentou; true = o servidor respondeu; false = sem conexão.
  bool? linkOnline;

  /// O servidor não tem o vínculo online configurado (sem Redis): não insistir.
  bool linkUnavailable = false;

  final Set<String> _unlinkStudents = {}; // alunos removidos aqui, a avisar o servidor
  final Set<String> _unlinkTeachers = {}; // professores removidos aqui
  Timer? _linkTimer;
  int _linkWatchers = 0;
  bool _linkSyncing = false;

  void _loadLinks(SharedPreferences p) {
    linkEnabled = p.getBool('link_on') ?? false;
    try {
      final raw = p.getString('my_teachers');
      myTeachers = raw == null ? [] : [for (final x in (jsonDecode(raw) as List)) ?LinkedPerson.tryFrom(x)];
    } catch (_) {
      myTeachers = [];
    }
    // Versão antiga guardava um professor só, neste aparelho: vira "ainda não confirmado".
    final old = p.getString('my_teacher');
    if (old != null) {
      if (!myTeachers.any((t) => t.code == old)) myTeachers.add(LinkedPerson(old, '', 0));
      p.remove('my_teacher');
      _saveLinks();
    }
    _unlinkStudents
      ..clear()
      ..addAll(p.getStringList('unlink_students') ?? const []);
    _unlinkTeachers
      ..clear()
      ..addAll(p.getStringList('unlink_teachers') ?? const []);
    // Ao abrir o app, atualiza uma vez (se o vínculo estiver ligado).
    if (linkEnabled) Future<void>.delayed(const Duration(seconds: 3), syncLinks);
  }

  void _saveLinks() {
    final p = _prefs;
    if (p == null) return;
    p.setBool('link_on', linkEnabled);
    p.setString('my_teachers', jsonEncode([for (final t in myTeachers) t.toJson()]));
    p.setStringList('unlink_students', _unlinkStudents.toList());
    p.setStringList('unlink_teachers', _unlinkTeachers.toList());
  }

  void setLinkEnabled(bool v) {
    linkEnabled = v;
    if (!v) {
      _linkTimer?.cancel();
      _linkTimer = null;
    }
    _saveLinks();
    notifyListeners();
    if (v) {
      linkUnavailable = false;
      unawaited(syncLinks());
      if (_linkWatchers > 0) _startLinkTimer();
    }
  }

  /// Enquanto uma tela de vínculos está aberta, atualiza a cada 15 s (a atualização
  /// "em tempo real" do vínculo é essa consulta, não uma conexão contínua).
  void watchLinks() {
    _linkWatchers++;
    if (linkEnabled && !linkUnavailable) {
      unawaited(syncLinks());
      _startLinkTimer();
    }
  }

  void unwatchLinks() {
    if (_linkWatchers > 0) _linkWatchers--;
    if (_linkWatchers == 0) {
      _linkTimer?.cancel();
      _linkTimer = null;
    }
  }

  void _startLinkTimer() {
    _linkTimer ??= Timer.periodic(const Duration(seconds: 15), (_) => syncLinks());
  }

  void _markLinkUnavailable() {
    linkUnavailable = true;
    linkOnline = false;
    _linkTimer?.cancel();
    _linkTimer = null;
    notifyListeners();
  }

  /// Registra o professor (li o QR dele ou digitei o código) e vincula online.
  /// Devolve o motivo se não foi possível; null se registrou.
  Future<String?> addMyTeacher(String code) async {
    final problem = checkTeacherCode(code);
    if (problem != null) return problem;
    final c = formatShareCode(code)!;
    if (myTeachers.any((t) => t.code == c)) return 'Este professor já está na sua lista.';
    myTeachers.add(LinkedPerson(c, '', 0));
    linkEnabled = true;
    _saveLinks();
    notifyListeners();
    final r = await links.link(profile.shareCode, profile.secret, role: 'student', other: c, name: profile.name);
    if (r.unavailable) {
      _markLinkUnavailable();
      say('O vínculo online ainda não está disponível. O professor foi registrado só neste aparelho.');
    } else if (r.offline) {
      say('Sem conexão: vou vincular com o professor assim que a internet voltar.');
    } else if (!r.ok) {
      myTeachers.removeWhere((t) => t.code == c);
      _saveLinks();
      notifyListeners();
      return r.error ?? 'Não foi possível vincular.';
    } else {
      linkOnline = true;
      await syncLinks();
      final t = myTeachers.where((x) => x.code == c).firstOrNull;
      say('Vinculado${t != null && t.name.isNotEmpty ? ' a ${t.name}' : ' ao professor'}. Ele já aparece para você e você aparece para ele.');
    }
    return null;
  }

  /// Tira um professor da sua lista (e do servidor).
  void removeMyTeacher(String code) {
    myTeachers.removeWhere((t) => t.code == code);
    _unlinkTeachers.add(code);
    _saveLinks();
    notifyListeners();
    if (linkEnabled) unawaited(syncLinks());
  }

  /// Vincula online um aluno cadastrado com código (o professor leu o QR ou digitou o código).
  Future<void> linkStudentOnline(Student s) async {
    final code = s.code;
    if (code == null) return;
    linkEnabled = true;
    _saveLinks();
    final r = await links.link(profile.shareCode, profile.secret, role: 'teacher', other: code, name: profile.name);
    if (r.unavailable) {
      _markLinkUnavailable();
      s.linkState = null;
      say('O vínculo online ainda não está disponível. ${s.name} ficou só neste aparelho.');
    } else if (r.offline) {
      s.linkState = 'pending';
      say('Sem conexão: vou vincular ${s.name} assim que a internet voltar.');
    } else if (!r.ok) {
      s.linkState = null;
      say(r.error ?? 'Não foi possível vincular ${s.name}.');
    } else {
      s.linkState = 'active';
      linkOnline = true;
      say('${s.name} vinculado. Ele já vê você como professor.');
    }
    _saveTeacher();
    notifyListeners();
    if (r.ok) unawaited(syncLinks());
  }

  /// Avisa o servidor que o aluno saiu da sua lista (se der agora; senão, depois).
  void _unlinkStudentOnline(Student s) {
    final c = s.code;
    if (c == null || !linkEnabled || s.linkState == null || s.linkState == 'ended') return;
    _unlinkStudents.add(c);
    _saveLinks();
    unawaited(syncLinks());
  }

  /// Melhor esforço: desfaz todos os vínculos deste perfil no servidor (ao apagar tudo),
  /// para ninguém ficar vendo um professor/aluno que não existe mais.
  Future<void> _unlinkAllOnline() async {
    if (!linkEnabled || linkUnavailable) return;
    try {
      final own = profile.shareCode, secret = profile.secret;
      final r = await links.sync(own, secret).timeout(const Duration(seconds: 6));
      if (!r.ok) return;
      for (final x in r.asTeacher) {
        await links.unlink(own, secret, role: 'teacher', other: x.code).timeout(const Duration(seconds: 4));
      }
      for (final x in r.asStudent) {
        await links.unlink(own, secret, role: 'student', other: x.code).timeout(const Duration(seconds: 4));
      }
    } catch (_) {}
  }

  /// Atualiza tudo com o servidor: desfaz o que foi removido aqui, envia o que ficou
  /// pendente, e traz quem se vinculou a você (aparece sozinho na lista).
  Future<void> syncLinks() async {
    if (_linkSyncing || linkUnavailable || !linkEnabled) return;
    _linkSyncing = true;
    try {
      final own = profile.shareCode, secret = profile.secret;
      // 1) Desfazimentos pedidos aqui.
      for (final c in [..._unlinkStudents]) {
        final r = await links.unlink(own, secret, role: 'teacher', other: c);
        if (r.unavailable) return _markLinkUnavailable();
        if (r.offline) {
          linkOnline = false;
          notifyListeners();
          return;
        }
        _unlinkStudents.remove(c);
      }
      for (final c in [..._unlinkTeachers]) {
        final r = await links.unlink(own, secret, role: 'student', other: c);
        if (r.unavailable) return _markLinkUnavailable();
        if (r.offline) {
          linkOnline = false;
          notifyListeners();
          return;
        }
        _unlinkTeachers.remove(c);
      }
      // 2) Lista do servidor.
      var r = await links.sync(own, secret, name: profile.name);
      if (r.unavailable) return _markLinkUnavailable();
      if (!r.ok) {
        if (r.offline) linkOnline = false;
        notifyListeners();
        return;
      }
      linkOnline = true;
      // 3) Envia o que só existe aqui (cadastrado sem conexão ou antes do vínculo online).
      var sent = false;
      final srvStudents = {for (final x in r.asTeacher) x.code};
      for (final s in students) {
        final c = s.code;
        if (c == null || srvStudents.contains(c) || _unlinkStudents.contains(c)) continue;
        if (s.linkState == null || s.linkState == 'pending') {
          final a = await links.link(own, secret, role: 'teacher', other: c, name: profile.name);
          if (a.ok) {
            s.linkState = 'active';
            sent = true;
          }
        }
      }
      final srvTeachers = {for (final x in r.asStudent) x.code};
      for (final t in [...myTeachers]) {
        if (t.since == 0 && !srvTeachers.contains(t.code) && !_unlinkTeachers.contains(t.code)) {
          final a = await links.link(own, secret, role: 'student', other: t.code, name: profile.name);
          if (a.ok) sent = true;
        }
      }
      if (sent) {
        r = await links.sync(own, secret, name: profile.name);
        if (!r.ok) {
          notifyListeners();
          return;
        }
      }
      _applyLinkLists(r);
    } finally {
      _linkSyncing = false;
    }
  }

  void _applyLinkLists(LinkReply r) {
    final newStudents = <String>[];
    final endedStudents = <String>[];
    final srvStudents = {for (final x in r.asTeacher) x.code: x};
    // Quem se vinculou a mim como professor aparece sozinho na minha lista de alunos.
    for (final x in r.asTeacher) {
      if (_unlinkStudents.contains(x.code)) continue;
      var s = studentByCode(x.code);
      if (s == null) {
        s = Student(
          id: 'v${x.code.replaceAll('-', '').toLowerCase()}',
          name: x.name.isEmpty ? 'Aluno ${x.code}' : x.name,
          code: x.code,
          linkState: 'active',
          remoteName: x.name,
        );
        students.add(s);
        activeStudentId ??= s.id;
        newStudents.add(s.name);
      } else {
        s.linkState = 'active';
        // Acompanha o apelido novo do aluno enquanto o professor não renomeou.
        final auto = s.name == (s.remoteName ?? '') || s.name == 'Aluno ${x.code}';
        if (x.name.isNotEmpty && auto) s.name = x.name;
        s.remoteName = x.name;
      }
    }
    for (final s in students) {
      if (s.code != null && s.linkState == 'active' && !srvStudents.containsKey(s.code)) {
        s.linkState = 'ended';
        endedStudents.add(s.name);
      }
    }
    // Meus professores: o que o servidor diz (mais os ainda não confirmados).
    final before = {for (final t in myTeachers) t.code};
    final serverTeachers = [for (final x in r.asStudent) if (!_unlinkTeachers.contains(x.code)) x];
    final unconfirmed = [for (final t in myTeachers) if (t.since == 0 && !serverTeachers.any((x) => x.code == t.code)) t];
    final lost = [for (final t in myTeachers) if (t.since > 0 && !serverTeachers.any((x) => x.code == t.code)) t];
    myTeachers = [...serverTeachers, ...unconfirmed];
    final newTeachers = [for (final x in serverTeachers) if (!before.contains(x.code)) x];

    _saveLinks();
    _saveTeacher();
    notifyListeners();
    if (newStudents.isNotEmpty) {
      say(newStudents.length == 1
          ? '${newStudents.first} entrou na sua lista de alunos.'
          : '${newStudents.length} alunos novos entraram na sua lista.');
    }
    if (newTeachers.isNotEmpty) {
      final n = newTeachers.first;
      say('${n.name.isEmpty ? 'Um professor' : n.name} se vinculou a você.');
    }
    if (endedStudents.isNotEmpty) {
      say('${endedStudents.join(', ')}: vínculo encerrado pelo aluno. O histórico ficou com você.');
    }
    if (lost.isNotEmpty) {
      say('${lost.first.name.isEmpty ? 'Um professor' : lost.first.name} encerrou o vínculo com você.');
    }
  }

  void _readIncomingCode() {
    if (!kIsWeb) return;
    final q = Uri.base.queryParameters;
    if (q['aluno'] != null) incomingStudentCode = formatShareCode(q['aluno']!);
    if (q['professor'] != null) incomingTeacherCode = formatShareCode(q['professor']!);
  }

  void toggleAssignment(Student s, String id) {
    final i = s.tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    s.tasks[i] = s.tasks[i].copyWith(done: !s.tasks[i].done);
    _saveTeacher();
    notifyListeners();
  }

  void removeAssignment(Student s, String id) {
    s.tasks.removeWhere((t) => t.id == id);
    _saveTeacher();
    notifyListeners();
  }

  /// Importa um aluno colado (ou junta as sessões se o aluno já existe).
  /// Devolve uma mensagem para o usuário.
  String importStudentText(String text) {
    if (text.length > 3000000) return 'Esse texto é grande demais para ser os dados de um aluno.';
    final imp = importStudent(text);
    if (imp == null || imp.name.isEmpty) return 'Não consegui ler esses dados. Cole o texto exatamente como foi copiado.';
    // Mesmas regras do cadastro: nada de aluno com o seu código ou o do seu professor.
    final c = imp.code;
    if (c != null && c == profile.shareCode) {
      return 'Esses dados têm o seu próprio código: você não pode ser aluno de si mesmo. Importação cancelada.';
    }
    // Mesmo código de um aluno já cadastrado = é a mesma pessoa: soma ao histórico dele.
    final sameCode = c == null ? null : studentByCode(c);
    final cur = studentById(imp.id) ?? sameCode;
    if (cur == null) {
      students.add(imp);
      activeStudentId ??= imp.id;
      _saveTeacher();
      notifyListeners();
      return '${imp.name} adicionado com ${imp.sessions.length} sessões.';
    }
    final n = mergeSessions(cur.sessions, imp.sessions);
    _saveTeacher();
    notifyListeners();
    return '$n sessões novas somadas ao histórico de ${cur.name}.';
  }

  void _saveTeacher() {
    final p = _prefs;
    if (p == null) return;
    _repo?.saveProfile(profile);
    if (teacherPinHash == null) {
      p.remove('teacherPin');
    } else {
      p.setString('teacherPin', teacherPinHash!);
    }
    _repo?.saveStudents(students);
    if (activeStudentId == null) {
      p.remove('activeStudent');
    } else {
      p.setString('activeStudent', activeStudentId!);
    }
  }

  Future<void> _loadTeacher(SharedPreferences p) async {
    teacherPinHash = p.getString('teacherPin');
    activeStudentId = p.getString('activeStudent');
    students = await _repo!.loadStudents();
    methodLibrary = await _repo!.loadMethods();
  }

  // ---------------- Estudo: cronômetro e tempo personalizado ----------------
  StudyMode studyMode = StudyMode.pomodoro;
  final StudyClock stopwatch = StudyClock();
  final StudyClock customClock = StudyClock(countdownMs: 30 * 60000);
  int customMinutes = 30;
  Timer? _clockTimer;

  /// Algum relógio manual (cronômetro ou tempo personalizado) está rodando.
  bool get manualClockActive => stopwatch.running || customClock.running;

  void setStudyMode(StudyMode m) {
    studyMode = m;
    _prefs?.setInt('studyMode', m.index);
    notifyListeners();
  }

  StudyClock clockFor(StudyMode m) => m == StudyMode.stopwatch ? stopwatch : customClock;

  Future<void> clockStart(StudyClock c) async {
    if (identical(c, customClock)) {
      try {
        await ensureAudio(); // o toque libera o áudio para o aviso do fim
      } catch (_) {}
    }
    c.start(_nowMs);
    _runClockTimer();
    _wake(true);
    _saveClocks();
    notifyListeners();
  }

  void clockPause(StudyClock c) {
    c.pause(_nowMs);
    if (!manualClockActive) {
      _clockTimer?.cancel();
      _clockTimer = null;
      _wake(listening || metroRunning);
    }
    _saveClocks();
    pomoTick.value++;
    notifyListeners();
  }

  void clockReset(StudyClock c) {
    c.reset();
    if (!manualClockActive) {
      _clockTimer?.cancel();
      _clockTimer = null;
      _wake(listening || metroRunning);
    }
    _saveClocks();
    pomoTick.value++;
    notifyListeners();
  }

  void setCustomMinutes(int m) {
    customMinutes = m.clamp(1, 600);
    customClock.setCountdown(customMinutes * 60000);
    _prefs?.setInt('customMin', customMinutes);
    _saveClocks();
    pomoTick.value++;
    notifyListeners();
  }

  void _runClockTimer() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final done = customClock.tick(_nowMs);
      pomoTick.value++;
      if (done) {
        say('Sessão de $customMinutes min concluída! Bom trabalho.');
        if (pomoChime) {
          _chime.play(endOfFocus: true, volume: pomoVolume).catchError((_) {});
        }
        if (pomoVibrate) buzz(pattern: const [0, 260, 120, 260]);
        _saveClocks();
      }
      if (!manualClockActive) {
        _clockTimer?.cancel();
        _clockTimer = null;
        _wake(listening || metroRunning);
        notifyListeners();
      }
    });
  }

  void _saveClocks() {
    final p = _prefs;
    if (p == null) return;
    p.setString('clock_sw', jsonEncode(stopwatch.toJson(_nowMs)));
    p.setString('clock_custom', jsonEncode(customClock.toJson(_nowMs)));
  }

  void _loadClocks(SharedPreferences p) {
    studyMode = StudyMode.values[(p.getInt('studyMode') ?? 0).clamp(0, StudyMode.values.length - 1)];
    customMinutes = (p.getInt('customMin') ?? 30).clamp(1, 600);
    try {
      final sw = p.getString('clock_sw');
      if (sw != null) stopwatch.restore(jsonDecode(sw) as Map<String, dynamic>, _nowMs);
      final cu = p.getString('clock_custom');
      if (cu != null) customClock.restore(jsonDecode(cu) as Map<String, dynamic>, _nowMs);
    } catch (_) {}
    if (customClock.countdownMs != customMinutes * 60000) {
      customClock.setCountdown(customMinutes * 60000);
    }
    if (manualClockActive) _runClockTimer();
  }

  Future<void> pomoStart() async {
    // O toque do usuário libera o áudio no navegador, para o alarme tocar depois.
    if (pomoChime) {
      try {
        await ensureAudio();
      } catch (_) {}
    }
    pomo.start(_nowMs);
    _runPomoTimer();
    _wake(true);
    _savePomo();
    notifyListeners();
  }

  void pomoPause() {
    pomo.pause(_nowMs);
    _pomoTimer?.cancel();
    _pomoTimer = null;
    _wake(listening || metroRunning);
    _savePomo();
    notifyListeners();
  }

  void pomoSkip() {
    final e = pomo.skip(_nowMs);
    _handlePomoEvents([e], quiet: true);
    if (pomo.running) _runPomoTimer();
    _savePomo();
    notifyListeners();
  }

  void pomoReset() {
    pomo.reset();
    _pomoTimer?.cancel();
    _pomoTimer = null;
    _wake(listening || metroRunning);
    _savePomo();
    notifyListeners();
  }

  void setPomo({PomodoroConfig? config, bool? chime, bool? vibrate, double? volume}) {
    if (config != null) {
      pomo.config = config;
      if (pomo.phase == PomoPhase.idle) pomo.reset(); // atualiza a duração mostrada
    }
    if (chime != null) pomoChime = chime;
    if (vibrate != null) pomoVibrate = vibrate;
    if (volume != null) pomoVolume = volume.clamp(0.1, 1.0);
    _savePomo();
    notifyListeners();
  }

  /// Toca o alarme de teste (para o usuário ouvir o volume).
  Future<void> pomoTestChime() =>
      _chime.play(endOfFocus: true, volume: pomoVolume);

  void _runPomoTimer() {
    _pomoTimer?.cancel();
    _pomoTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pomoTick());
  }

  void _pomoTick() {
    final events = pomo.tick(_nowMs);
    if (events.isNotEmpty) {
      _handlePomoEvents(events);
      _savePomo();
    }
    if (!pomo.running) {
      _pomoTimer?.cancel();
      _pomoTimer = null;
      _wake(listening || metroRunning);
    }
    // O relógio só atualiza quem o mostra; o app inteiro só é avisado quando
    // uma fase termina (contagem, mensagens).
    pomoTick.value++;
    if (events.isNotEmpty || !pomo.running) notifyListeners();
  }

  void _handlePomoEvents(List<PomodoroEvent> events, {bool quiet = false}) {
    for (final e in events) {
      if (e.countedPomodoro) {
        final k = dayKey(DateTime.fromMillisecondsSinceEpoch(e.atMs));
        pomoDays[k] = (pomoDays[k] ?? 0) + 1;
      }
      final focusEnded = e.finished == PomoPhase.focus;
      if (!quiet) {
        say(focusEnded
            ? 'Foco concluído! Pausa de ${e.next == PomoPhase.longBreak ? pomo.config.longMin : pomo.config.shortMin} min.'
            : 'Pausa terminou. Hora de voltar ao foco.');
        if (pomoChime) {
          _chime.play(endOfFocus: focusEnded, volume: pomoVolume).catchError((_) {});
        }
        if (pomoVibrate) buzz(pattern: const [0, 260, 120, 260]);
      }
    }
  }

  Future<void> _savePomo() async {
    final p = _prefs;
    if (p == null) return;
    final c = pomo.config;
    await p.setString(
        'pomo_cfg',
        jsonEncode({
          'f': c.focusMin,
          's': c.shortMin,
          'l': c.longMin,
          'n': c.cyclesBeforeLong,
          'a': c.autoStart,
          'chime': pomoChime,
          'vib': pomoVibrate,
          'vol': pomoVolume,
        }));
    await p.setString('pomo_state', jsonEncode(pomo.toJson(_nowMs)));
    await p.setString('pomo_days', jsonEncode(pomoDays));
  }

  void _loadPomo(SharedPreferences p) {
    final cfg = p.getString('pomo_cfg');
    if (cfg != null) {
      final j = jsonDecode(cfg) as Map<String, dynamic>;
      pomo = PomodoroTimer(PomodoroConfig(
        focusMin: (j['f'] as num?)?.toInt() ?? 25,
        shortMin: (j['s'] as num?)?.toInt() ?? 5,
        longMin: (j['l'] as num?)?.toInt() ?? 15,
        cyclesBeforeLong: (j['n'] as num?)?.toInt() ?? 4,
        autoStart: j['a'] != false,
      ));
      pomoChime = j['chime'] != false;
      pomoVibrate = j['vib'] != false;
      pomoVolume = ((j['vol'] as num?) ?? 0.5).toDouble();
    }
    final days = p.getString('pomo_days');
    if (days != null) {
      pomoDays = (jsonDecode(days) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    }
    final st = p.getString('pomo_state');
    if (st != null) {
      final expired = pomo.restore(jsonDecode(st) as Map<String, dynamic>, _nowMs);
      if (pomo.running) _runPomoTimer();
      if (expired) {
        Future<void>.delayed(const Duration(seconds: 1),
            () => say('O tempo do foco acabou enquanto o app estava fechado.'));
      }
    }
  }

  // ---------------- Avisos ----------------
  /// Quem exibe os avisos (a tela registra aqui um SnackBar).
  void Function(String message)? onMessage;

  /// Mostra um aviso curto ao usuário quando uma função é ligada/desligada.
  void say(String message) => onMessage?.call(message);

  // ---------------- Permissões ----------------
  /// Resultado da última verificação do microfone: null = ainda não verificado.
  bool? micGranted;

  /// Mostra uma explicação antes do primeiro pedido de permissão. Registrado
  /// pela tela; devolve false se o usuário desistir.
  Future<bool> Function()? askMicRationale;
  bool micRationaleSeen = false;

  /// Pede (ou confirma) a permissão do microfone e guarda o resultado.
  /// Com [request] false só consulta, sem abrir o pedido do sistema.
  Future<bool> checkMicPermission({bool request = true, bool announce = true}) async {
    final r = AudioRecorder();
    try {
      micGranted = await r.hasPermission(request: request);
    } catch (_) {
      micGranted = false;
    } finally {
      await r.dispose();
    }
    if (announce) {
      say(micGranted == true
          ? 'Microfone liberado'
          : 'Microfone sem permissão. Libere nas configurações do aparelho ou do navegador.');
    }
    notifyListeners();
    return micGranted == true;
  }

  // ---------------- Instalar no celular (aviso da tela inicial) ----------------
  /// Esconde o aviso até este instante (ms).
  int installHideUntil = 0;

  /// A pessoa já instalou (ou disse que instalou): não mostrar mais.
  bool installDone = false;

  void hideInstall({int days = 3}) {
    installHideUntil = DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch;
    _prefs?.setInt('install_hide', installHideUntil);
    notifyListeners();
  }

  void markInstalled() {
    installDone = true;
    _prefs?.setBool('install_done', true);
    notifyListeners();
  }

  // ---------------- Câmera (só para ler QR) ----------------
  /// null = ainda não pedida; true = a câmera abriu; false = o usuário negou.
  bool? cameraGranted;

  void setCameraStatus(bool granted) {
    if (cameraGranted == granted) return;
    cameraGranted = granted;
    _prefs?.setBool('cam_granted', granted);
    notifyListeners();
  }

  // ---------------- Vibração ----------------
  /// null = ainda não verificado.
  bool? vibrationAvailable;

  /// Por que não vibra (texto para o usuário), quando [vibrationAvailable] é false.
  String vibrationWhy() {
    if (kIsWeb) {
      if (webIsIos()) {
        return 'iPhone e iPad: a Apple não deixa sites e apps da tela inicial vibrarem. Só um app da App Store poderia.';
      }
      if (!webVibrationSupported()) {
        return 'Este navegador ou aparelho não oferece vibração a sites. No celular Android, use o Chrome; '
            'computadores não vibram.';
      }
    }
    return 'Este aparelho não tem motor de vibração.';
  }

  /// A vibração existe neste aparelho? No app (Android/iOS) pergunta ao sistema;
  /// na web usa a API do navegador (o Chrome do Android tem; iPhone e computador não).
  Future<bool> _vibrationExists() async {
    if (kIsWeb) return webVibrationSupported();
    return Vibration.hasVibrator();
  }

  Future<bool> checkVibration() async {
    try {
      vibrationAvailable = await _vibrationExists();
    } catch (_) {
      vibrationAvailable = false;
    }
    notifyListeners();
    return vibrationAvailable == true;
  }

  /// Vibra por [ms] milissegundos ou segundo um [pattern] (espera, vibra, espera…).
  /// Se o aparelho não tiver motor de vibração, usa o toque tátil do sistema.
  Future<void> buzz({int ms = 25, List<int>? pattern}) async {
    try {
      vibrationAvailable ??= await _vibrationExists();
      if (vibrationAvailable == true) {
        if (kIsWeb) {
          webVibrate(pattern ?? [ms]);
        } else if (pattern != null) {
          await Vibration.vibrate(pattern: pattern);
        } else {
          await Vibration.vibrate(duration: ms);
        }
        return;
      }
    } catch (_) {}
    HapticFeedback.selectionClick();
  }

  Future<void> testVibration() async {
    await checkVibration();
    await buzz(pattern: const [0, 160, 110, 160]);
    say(vibrationAvailable == true
        ? 'Vibração testada: você deve ter sentido duas pulsações. Se não sentiu, veja se o celular não está no modo silencioso ou economia de bateria.'
        : vibrationWhy());
  }

  // ---------------- Primeiro uso ----------------
  /// Análise por IA do treinador (opcional, via Vercel).
  final CoachAi ai = CoachAi();

  /// Nota do app e pesquisa rápida.
  final FeedbackService feedback = FeedbackService();

  /// Escrita por voz nos campos de texto.
  late final Dictation dictation = Dictation()
    ..beforeListen = (() async => stopListening(quiet: true))
    ..onMessage = say;

  /// Nota em DESTAQUE na grade (nome, ponteiro e quadrado aceso). É a leitura
  /// bruta [current] passada por um filtro que troca de nota com calma: a grade
  /// continua registrando tudo o que você toca, só o destaque é mais lento.
  TrackedNote? shown;
  NoteSwitchSpeed noteSwitch = NoteSwitchSpeed.normal;
  late final NoteDisplayFilter _display = NoteDisplayFilter(speed: noteSwitch);

  /// Velocidade da troca de nota em destaque (Rápida, Normal ou Calma).
  void setNoteSwitch(NoteSwitchSpeed s) {
    noteSwitch = s;
    _display.speed = s;
    _prefs?.setInt('noteSwitch', s.index);
    notifyListeners();
  }

  /// Microfone captando agora (alimenta o aviso fixo na barra superior).
  final ValueNotifier<bool> micOn = ValueNotifier(false);

  bool onboarded = false;

  void markOnboarded() {
    onboarded = true;
    _prefs?.setBool('onboarded', true);
  }

  /// Pede de uma vez tudo o que o app usa: microfone e vibração.
  Future<void> requestAllPermissions() async {
    await checkMicPermission(announce: false);
    await checkVibration();
    if (vibrationAvailable == true) await buzz(pattern: const [0, 120, 90, 120]);
    say(micGranted == true
        ? 'Tudo pronto: microfone liberado${vibrationAvailable == true ? ' e vibração disponível' : ''}.'
        : 'Microfone sem permissão. Você pode liberar depois em Configurações.');
    notifyListeners();
  }

  // ---------------- Metrônomo: latência ----------------
  /// Compensa o atraso entre o som e a tela/vibração (ms).
  double outputLatencyMs = 0;

  void setLatency(double ms) {
    outputLatencyMs = ms.clamp(0.0, 250.0);
    metroPlayer.outputLatencyMs = outputLatencyMs;
    _prefs?.setDouble('latency', outputLatencyMs);
    notifyListeners();
  }

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _prefs?.setInt('theme', m.index);
    notifyListeners();
  }

  /// Volta todas as configurações ao padrão (não apaga o histórico de estudo).
  Future<void> resetSettings() async {
    refA = 440;
    system = TuningSystem.equal;
    tonicPc = 9;
    anchor = Anchor.a4;
    preferFlats = false;
    transpose = 0;
    instrumentId = 'violino';
    _gridLow = null;
    gridOctCount = 5;
    gridFollow = false;
    tunerMode = TunerMode.strings;
    history = HistoryMode.medium;
    holdSeconds = 0;
    noteSwitch = NoteSwitchSpeed.normal;
    _display.speed = noteSwitch;
    exerciseFlow = true;
    grid.history = history;
    grid.holdSeconds = holdSeconds <= 0 ? null : holdSeconds;
    dailyGoalMinutes = 20;
    flashEnabled = true;
    hapticEnabled = true;
    keepAwake = true;
    showFreq = true;
    sensitivity = MicSensitivity.normal;
    micGain = 1.0;
    outputLatencyMs = 0;
    metroPlayer.outputLatencyMs = 0;
    themeMode = ThemeMode.system;
    tone.timbre = ToneTimbre.fork;
    await _prefs?.setInt('timbre', 0);
    metro = MetronomeConfig.signature(4, bpm: 100);
    metroPlayer.update(metro);
    _applyMic();
    resetGrid();
    await _save();
    await _prefs?.setInt('sens', sensitivity.index);
    await _prefs?.setDouble('gain', micGain);
    await _prefs?.setInt('theme', themeMode.index);
    await _prefs?.setDouble('latency', 0);
    say('Configurações restauradas para o padrão');
    notifyListeners();
  }

  // ---------------- Aparência ----------------
  ThemeMode get themeMode => themeNotifier.value;
  set themeMode(ThemeMode m) => themeNotifier.value = m;

  void cycleTheme() {
    const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    themeMode = order[(order.indexOf(themeMode) + 1) % order.length];
    _prefs?.setInt('theme', themeMode.index);
    notifyListeners();
  }

  // ---------------- Microfone ----------------
  MicSensitivity sensitivity = MicSensitivity.normal;
  double micGain = 1.0;

  // ---- Navegação de oitavas da grade ----
  // "oitava" aqui é MIDI~/12 (Dó4 = 5). O rótulo para o usuário é oitava - 1.
  static const int minOct = 1; // Dó0
  static const int maxOct = 9; // Dó8
  int? _gridLow; // null = padrão do instrumento
  int gridOctCount = 5;
  bool gridFollow = false;

  /// Faixa [baixa, alta] de oitavas visíveis (inclusive).
  (int, int) get gridOctaves {
    // Padrão como no Tonemap: oitavas 3 a 7 (a grave do instrumento fica na base,
    // mas nunca mais acima da oitava 3, para sobrar espaço para os agudos).
    final lowLabel = instrument.strings.first.midi ~/ 12 - 1;
    final lo = (_gridLow ?? (lowLabel < 3 ? lowLabel : 3) + 1)
        .clamp(minOct, maxOct - gridOctCount + 1);
    return (lo, lo + gridOctCount - 1);
  }

  void shiftOctaves(int d) {
    _gridLow = (gridOctaves.$1 + d).clamp(minOct, maxOct - gridOctCount + 1);
    notifyListeners();
  }

  /// Vai para a oitava de rótulo [label] (ex.: 3 para Dó3), centralizando.
  void goToOctave(int label) {
    _gridLow = (label + 1 - gridOctCount ~/ 2)
        .clamp(minOct, maxOct - gridOctCount + 1);
    notifyListeners();
  }

  void setOctCount(int n) {
    final lo = gridOctaves.$1;
    gridOctCount = n.clamp(2, 7);
    _gridLow = lo.clamp(minOct, maxOct - gridOctCount + 1);
    notifyListeners();
  }

  void setFollow(bool v) {
    gridFollow = v;
    notifyListeners();
  }

  void _followNote(int midi) {
    final o = midi ~/ 12;
    final (lo, hi) = gridOctaves;
    if (o < lo || o > hi) {
      _gridLow = (o - gridOctCount ~/ 2)
          .clamp(minOct, maxOct - gridOctCount + 1);
    }
  }

  void setMic({MicSensitivity? sensitivity, double? gain}) {
    if (sensitivity != null) this.sensitivity = sensitivity;
    if (gain != null) micGain = gain.clamp(1.0, 30.0);
    _applyMic();
    _prefs?.setInt('sens', this.sensitivity.index);
    _prefs?.setDouble('gain', micGain);
    notifyListeners();
  }

  void _applyMic() {
    tracker.onsetFrames = sensitivity.onsetFrames;
    _source?.configure(
        gain: micGain,
        minClarity: sensitivity.minClarity,
        minRms: sensitivity.minRms);
  }

  // ---------------- Escuta ----------------
  PitchSource? _source;
  StreamSubscription<PitchFrame>? _sub;
  final PitchTracker tracker = PitchTracker();
  PitchGrid grid = PitchGrid();
  TrackedNote? current;
  double level = 0;

  // ---- Diagnóstico da captação (painel em Ajustes › Captação) ----
  /// Última medida do microfone (nível, pico, clareza e o motivo de recusa).
  MicDiag? diag;

  /// Maior pico recente (0..1), para avisar de distorção (clipping).
  double diagPeakHold = 0;

  bool listening = false;
  bool demo = false;
  String? micError;
  final Stopwatch _clock = Stopwatch()..start();
  double get now => _clock.elapsedMicroseconds / 1e6;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastNoteSeen = -100;

  // ---------------- Escala ----------------
  int scaleTonicMidi = 55; // Sol3
  ScaleType scaleType = ScaleType.major;
  int scaleOctaves = 1;
  bool scaleMode = false;
  List<int> get scaleNotes =>
      scaleMidis(scaleTonicMidi, scaleType, octaves: scaleOctaves);

  // ---------------- Exercício de escala guiado + histórico ----------------
  ScaleExercise? exercise;
  bool exerciseDone = false;
  SessionRecord? lastSession;

  /// Histórico estruturado (da mais recente para a mais antiga).
  List<SessionRecord> sessionRecords = [];

  List<Insight> get insights =>
      analyzePractice(sessionRecords, flats: preferFlats);

  String aiSummary() =>
      buildAiPrompt(sessionRecords, instrument: instrument.name, flats: preferFlats);

  /// Começa o exercício da escala escolhida (aba Grade › Escala).
  /// "Seguir meu ritmo": o exercício acompanha você tocando a escala sem parar,
  /// sem exigir que cada nota seja segurada. Desligado = espera cada nota.
  bool exerciseFlow = true;

  void setExerciseFlow(bool v) {
    exerciseFlow = v;
    exercise?.flow = v; // vale já no exercício em andamento
    _prefs?.setBool('exFlow', v);
    notifyListeners();
  }

  Future<void> startExercise({bool demoMode = false}) async {
    exercise = ScaleExercise(
      tonicMidi: scaleTonicMidi,
      type: scaleType,
      octaves: scaleOctaves,
      zone: kInTuneCents,
      flow: exerciseFlow,
    );
    exerciseDone = false;
    lastSession = null;
    resetGrid();
    if (!listening || demo != demoMode) {
      await startListening(demoMode: demoMode);
    }
    notifyListeners();
  }

  void stopExercise() {
    // A demonstração repete o roteiro sem parar: ao sair, ela também para
    // (senão o violino virtual continuaria tocando em segundo plano).
    final stopDemo = demo && listening;
    exercise = null;
    exerciseDone = false;
    if (stopDemo) stopListening(quiet: true);
    notifyListeners();
  }

  /// Execução livre: o músico decide quando acabou (botão "Concluir").
  void finishExerciseNow() {
    final e = exercise;
    if (e == null || e.finished) return;
    e.finish();
    _finishExercise();
    liveTick.value++;
  }

  void skipExerciseNote() {
    final e = exercise;
    if (e == null || e.finished) return;
    e.skip();
    if (e.finished) _finishExercise();
    liveTick.value++;
  }

  void _feedExercise(TrackedNote? n, double dt) {
    final e = exercise;
    if (e == null || e.finished) return;
    final r = e.feed(
      midi: n?.midi,
      cents: n?.cents ?? 0,
      clarity: n?.clarity ?? 0,
      dt: dt,
    );
    if (r != null) {
      if (hapticEnabled) buzz(ms: 18);
      if (e.finished) _finishExercise();
    }
  }

  void _finishExercise() {
    final e = exercise;
    if (e == null) return;
    exerciseDone = true;
    final sc = e.score;
    // No modo demonstração não se guarda histórico (não é a execução do músico).
    final student = (!demo && teacherMode) ? activeStudent : null;
    final rec = SessionRecord(
      id: newUuid(math.Random.secure()),
      origin: student != null ? kOriginTeacherDevice : kOriginSelf,
      date: DateTime.now(),
      title:
          '${scaleType.display(noteName(scaleTonicMidi, cfg))} · $scaleOctaves oitava${scaleOctaves > 1 ? 's' : ''}',
      octaves: scaleOctaves,
      zone: kInTuneCents,
      accuracy: sc.accuracy,
      meanAbsCents: sc.meanAbsCents,
      steps: [
        for (final r in e.finalResults)
          StepRecord(r.midi, r.ascending, r.octaveIndex, r.skipped ? null : r.cents)
      ],
    );
    lastSession = rec;
    if (student != null) {
      // Aula com aluno: o exercício vai para o histórico dele (não para o seu).
      student.sessions.insert(0, rec);
      if (student.sessions.length > 200) student.sessions.removeRange(200, student.sessions.length);
      var tasksDone = 0;
      for (var i = 0; i < student.tasks.length; i++) {
        final t = student.tasks[i];
        if (!t.done &&
            t.isScale && // só escala/arpejo é medida; as outras o professor marca
            t.scaleTypeIndex == scaleType.index &&
            t.tonicPc == scaleTonicMidi % 12 &&
            t.octaves == scaleOctaves &&
            sc.accuracy >= t.goal) {
          student.tasks[i] = t.copyWith(done: true);
          tasksDone++;
        }
      }
      _saveTeacher();
      say('${student.name}: ${(sc.accuracy * 100).round()}% de acerto. Salvo no histórico do aluno${tasksDone > 0 ? ' e tarefa concluída!' : '.'}');
    } else if (!demo) {
      sessionRecords.insert(0, rec);
      if (sessionRecords.length > 200) sessionRecords.removeRange(200, sessionRecords.length);
      _repo?.saveSessions(sessionRecords);
      say('Exercício concluído: ${(sc.accuracy * 100).round()}% de acerto. Salvo no histórico.');
    } else {
      say('Fim da demonstração. Ela não entra no seu histórico.');
    }
    notifyListeners();
  }

  // ---------------- Metrônomo ----------------
  MetronomeConfig metro = MetronomeConfig.signature(4, bpm: 100);
  final MetronomePlayer metroPlayer = MetronomePlayer();
  final TonePlayer tone = TonePlayer();


  /// Volume do diapasão (0,2 a 1).
  double get toneVolume => tone.volume;
  void setToneVolume(double v) {
    tone.setVolume(v);
    _prefs?.setDouble('toneVol', tone.volume);
    notifyListeners();
  }

  /// Toca o Sol3 por um instante para o músico ajustar o volume.
  Future<void> testLowTone() async {
    await tone.play(195.9954);
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if ((tone.frequency - 195.9954).abs() < 0.01) tone.stop();
    });
  }

  /// Timbre do som de referência (diapasão puro ou mais cheio).
  ToneTimbre get toneTimbre => tone.timbre;
  void setToneTimbre(ToneTimbre t) {
    tone.timbre = t;
    _prefs?.setInt('timbre', t.index);
    // Se estiver tocando, recomeça a mesma nota no novo timbre.
    if (tone.running) tone.play(tone.frequency);
    notifyListeners();
  }
  bool get metroRunning => metroPlayer.running;
  final TapTempo _tap = TapTempo();
  bool flashEnabled = true;
  bool hapticEnabled = true;

  /// Mantém a tela acesa enquanto ouve, toca o metrônomo ou usa o timer.
  bool keepAwake = true;

  /// Mostra a frequência (Hz) na grade.
  bool showFreq = true;

  void setKeepAwake(bool v) {
    keepAwake = v;
    _prefs?.setBool('keepAwake', v);
    _wake(listening || metroRunning);
    notifyListeners();
  }

  void setShowFreq(bool v) {
    showFreq = v;
    _prefs?.setBool('showFreq', v);
    notifyListeners();
  }

  // ---------------- Estudo ----------------
  Map<String, double> studySeconds = {}; // yyyy-MM-dd -> segundos
  List<Map<String, dynamic>> scaleSessions = [];
  double dailyGoalMinutes = 20;
  Timer? _studyTimer;

  SharedPreferences? _prefs;

  // ===================================================================
  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    refA = p.getDouble('refA') ?? 440;
    system = TuningSystem.values[p.getInt('system') ?? 0];
    tonicPc = p.getInt('tonicPc') ?? 9;
    anchor = Anchor.values[p.getInt('anchor') ?? 0];
    preferFlats = p.getBool('flats') ?? false;
    transpose = p.getInt('transpose') ?? 0;
    instrumentId = p.getString('instrument') ?? 'violino';
    tunerMode = TunerMode.values[p.getInt('tunerMode') ?? 0];
    history = HistoryMode.values[p.getInt('history') ?? 1];
    holdSeconds = p.getDouble('hold') ?? 0;
    // Uma vez: a grade passa a guardar o histórico das notas.
    if ((p.getInt('gridMig') ?? 0) < 1) {
      holdSeconds = 0;
      p.setInt('gridMig', 1);
    }
    noteSwitch = NoteSwitchSpeed.values[
        (p.getInt('noteSwitch') ?? NoteSwitchSpeed.normal.index).clamp(0, NoteSwitchSpeed.values.length - 1)];
    _display.speed = noteSwitch;
    exerciseFlow = p.getBool('exFlow') ?? true;
    dailyGoalMinutes = p.getDouble('goal') ?? 20;
    themeMode = ThemeMode.values[p.getInt('theme') ?? 0];
    outputLatencyMs = p.getDouble('latency') ?? 0;
    metroPlayer.outputLatencyMs = outputLatencyMs;
    micRationaleSeen = p.getBool('micRationale') ?? false;
    onboarded = p.getBool('onboarded') ?? false;
    await ai.load();
    await feedback.load(p);
    await dictation.load(p);
    tone.setVolume(p.getDouble('toneVol') ?? 0.9);
    tone.timbre = ToneTimbre.values[(p.getInt('timbre') ?? 0).clamp(0, ToneTimbre.values.length - 1)];
    sensitivity = MicSensitivity.values[p.getInt('sens') ?? 1];
    micGain = p.getDouble('gain') ?? 1.0;
    flashEnabled = p.getBool('flash') ?? true;
    hapticEnabled = p.getBool('haptic') ?? true;
    keepAwake = p.getBool('keepAwake') ?? true;
    showFreq = p.getBool('showFreq') ?? true;
    final bpm = p.getDouble('bpm') ?? 100;
    final beats = p.getInt('beats') ?? 4;
    final sub = p.getInt('sub') ?? 1;
    metro = MetronomeConfig.signature(beats,
        bpm: bpm,
        subdivision: sub,
        sound: ClickSound.values[p.getInt('sound') ?? 0],
        groupSize: beats == 6 ? 3 : (beats == 7 ? 2 : null));
    try {
      final raw = p.getString('challenge');
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final cfg = ChallengeConfig.tryFrom(j['cfg']);
        challengeOn = j['on'] == true;
        challengeCfg = cfg ?? challengeCfg;
        if (challengeOn) metro = metro.copyWith(challenge: challengeCfg);
      }
    } catch (_) {}
    final sd = p.getString('study');
    if (sd != null) {
      studySeconds = (jsonDecode(sd) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    final ss = p.getString('sessions');
    if (ss != null) {
      scaleSessions = (jsonDecode(ss) as List).cast<Map<String, dynamic>>();
    }
    final repo = _repo = LocalRepository(p);
    profile = await repo.loadOrCreateProfile();
    sessionRecords = await repo.loadSessions();
    _loadPomo(p);
    _loadClocks(p);
    await _loadTeacher(p);
    _loadLinks(p);
    cameraGranted = p.getBool('cam_granted');
    installHideUntil = p.getInt('install_hide') ?? 0;
    installDone = p.getBool('install_done') ?? false;
    _readIncomingCode();
    _scheduleUpdateChecks();
    // Mostra o estado real das permissões sem abrir nenhum pedido do sistema.
    if (onboarded) {
      checkMicPermission(request: false, announce: false);
      checkVibration();
    }
    grid = PitchGrid(history: history, holdSeconds: holdSeconds <= 0 ? null : holdSeconds);
    _studyTimer = Timer.periodic(const Duration(seconds: 1), (_) => _studyTick());
    notifyListeners();
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setDouble('refA', refA);
    await p.setInt('system', system.index);
    await p.setInt('tonicPc', tonicPc);
    await p.setInt('anchor', anchor.index);
    await p.setBool('flats', preferFlats);
    await p.setInt('transpose', transpose);
    await p.setString('instrument', instrumentId);
    await p.setInt('tunerMode', tunerMode.index);
    await p.setInt('history', history.index);
    await p.setDouble('hold', holdSeconds);
    await p.setInt('noteSwitch', noteSwitch.index);
    await p.setBool('exFlow', exerciseFlow);
    await p.setDouble('goal', dailyGoalMinutes);
    await p.setBool('flash', flashEnabled);
    await p.setBool('haptic', hapticEnabled);
    await p.setBool('keepAwake', keepAwake);
    await p.setBool('showFreq', showFreq);
    await p.setDouble('bpm', metro.bpm);
    await p.setInt('beats', metro.beatsPerBar);
    await p.setInt('sub', metro.subdivision);
    await p.setInt('sound', metro.sound.index);
  }

  /// Altera configurações de afinação e persiste.
  void setTuning({
    double? refA,
    TuningSystem? system,
    int? tonicPc,
    Anchor? anchor,
    bool? preferFlats,
    int? transpose,
    String? instrumentId,
    TunerMode? tunerMode,
    HistoryMode? history,
    double? holdSeconds,
    double? dailyGoalMinutes,
    bool? flashEnabled,
    bool? hapticEnabled,
  }) {
    if (refA != null) this.refA = refA.clamp(380.0, 480.0);
    if (system != null) {
      this.system = system;
    }
    if (tonicPc != null) this.tonicPc = tonicPc;
    if (anchor != null) this.anchor = anchor;
    if (preferFlats != null) this.preferFlats = preferFlats;
    if (transpose != null) this.transpose = transpose;
    if (instrumentId != null) {
      this.instrumentId = instrumentId;
      _gridLow = null; // volta à faixa padrão do novo instrumento
    }
    if (tunerMode != null) this.tunerMode = tunerMode;
    if (history != null) {
      this.history = history;
      grid.history = history;
    }
    if (holdSeconds != null) {
      this.holdSeconds = holdSeconds;
      grid.holdSeconds = holdSeconds <= 0 ? null : holdSeconds;
    }
    if (dailyGoalMinutes != null) this.dailyGoalMinutes = dailyGoalMinutes;
    if (flashEnabled != null) this.flashEnabled = flashEnabled;
    if (hapticEnabled != null) this.hapticEnabled = hapticEnabled;
    // O alvo mudou: o que foi acumulado deixa de fazer sentido.
    if (refA != null || system != null || tonicPc != null || anchor != null) {
      resetGrid();
    }
    _save();
    notifyListeners();
  }

  // ===================================================================
  // Escuta
  // ===================================================================
  Future<void> startListening({bool demoMode = false, bool demoGlide = false}) async {
    if (listening) await stopListening(quiet: true);
    micError = null;
    // Antes do primeiro pedido real de microfone, explica para que serve.
    if (!demoMode && !micRationaleSeen && askMicRationale != null) {
      final go = await askMicRationale!();
      if (!go) return;
      micRationaleSeen = true;
      _prefs?.setBool('micRationale', true);
    }
    demo = demoMode;
    PitchSource src;
    if (demoMode) {
      // Simulação silenciosa, só para desenvolvimento (kDevDemo): não toca nada.
      if (demoGlide) {
        // Teste do ponteiro: uma nota (Dó4) vai de 38 cents grave a 38 cents
        // aguda e volta, passando pelo centro.
        final c = TuningConfig(refA: refA, system: system, tonicPc: tonicPc, anchor: anchor);
        double hz(double cents) => targetFreq(60, c) * math.pow(2, cents / 1200).toDouble();
        src = DemoPitchSource([(hz(-38), 6.0), (hz(38), 6.0)], glideTo: {0: hz(38), 1: hz(-38)});
      } else {
        src = DemoPitchSource(_demoScript());
      }
    } else {
      // Janela e passo ajustados ao instrumento: violino e afins leem a cada
      // ~17 ms (notas rápidas), instrumentos graves usam janela maior.
      src = MicPitchSource(
          profile: DetectorProfile.forLowest(instrument.stringFreq(0, refA)));
    }
    final ok = await src.start();
    if (!demoMode) micGranted = ok;
    if (!ok) {
      micError =
          'Sem acesso ao microfone. Permita o acesso nas configurações do aparelho ou do navegador.';
      notifyListeners();
      return;
    }
    _source = src;
    _applyMic();
    listening = true;
    _sub = src.frames.listen(_onFrame);
    _wake(true);
    micOn.value = true;
    if (kDevDemo && demoMode) FrameMeter.instance.start();
    if (!demoMode && hapticEnabled) buzz(ms: 30);
    say(demoMode
        ? 'Simulação de desenvolvimento ligada (sem som)'
        : 'Microfone ligado. Toque uma nota!');
    notifyListeners();
  }

  Future<void> stopListening({bool quiet = false}) async {
    await _sub?.cancel();
    _sub = null;
    await _source?.stop();
    _source = null;
    listening = false;
    micOn.value = false;
    if (kDevDemo) FrameMeter.instance.stop();
    _gate.close();
    current = null;
    shown = null;
    _display.reset();
    level = 0;
    tracker.reset();
    _wake(metroRunning);
    notifyListeners();
  }

  void _onFrame(PitchFrame f) {
    level = f.level;
    final d = f.diag;
    if (d != null) {
      diag = d;
      diagPeakHold = d.peak > diagPeakHold ? d.peak : diagPeakHold * 0.995;
    }
    final n = tracker.update(f.result, cfg);
    current = n;
    shown = _display.update(n, now);
    _registerNote(n, f.dt);
    if (n != null) _lastNoteSeen = now;
    final sh = shown;
    if (gridFollow && sh != null) _followNote(sh.midi);
    _feedExercise(n, f.dt);
    // Limita a taxa de redesenho (~30 fps) para poupar bateria. Só quem mostra
    // dados ao vivo (afinador, grade) escuta [liveTick]; as demais telas não
    // são reconstruídas a cada leitura do microfone.
    final t = DateTime.now();
    if (t.difference(_lastNotify).inMilliseconds >= 33) {
      _lastNotify = t;
      liveTick.value++;
    }
  }

  // ---- Porta de registro da grade ----
  // Só vira nota da sessão (cor, ×N, placar) o que se mantém por um tempo mínimo.
  // Isso corta o que não foi tocado de verdade: a passagem entre duas notas (de Lá
  // para Si o dedo cruza o Lá♯), ruído do arco, e cordas soltas que ressoam por
  // simpatia. O destaque ao vivo não passa por aqui (continua imediato).
  final NoteGate _gate = NoteGate();

  /// Tempo (s) que uma nota precisa durar para entrar na sessão.
  double get minNoteSeconds => switch (sensitivity) {
        MicSensitivity.rigorous => 0.09,
        MicSensitivity.normal => 0.06,
        MicSensitivity.free => 0.04,
      };

  void _registerNote(TrackedNote? n, double dt) {
    _gate.minSeconds = minNoteSeconds;
    _gate.update(grid, n, dt, now);
  }

  /// Escala de demonstração: Sol maior no violino, com desafinações reais.
  List<(double, double)> _demoScript() {
    final c = TuningConfig(
        refA: refA, system: system, tonicPc: tonicPc, anchor: anchor);
    double f(int midi, double cents) =>
        targetFreq(midi, c) * math.pow(2, cents / 1200).toDouble();
    // Se há um exercício em andamento, a demonstração toca a escala escolhida
    // (com pequenas desafinações) para o músico ver como a tela reage.
    final ex = exercise;
    if (ex != null) {
      const offs = [1.0, -3.0, 2.0, -12.0, 4.0, 0.0, 7.0, -2.0, 1.0, 3.0, -9.0, 2.0, 0.0, -4.0, 1.0];
      return [
        for (var i = 0; i < ex.sequence.length; i++) ...[
          // Só no teste: antes da 4ª nota vem uma errada (meio tom acima, um
          // pouco baixa) para mostrar o aviso leve "ainda não é a nota".
          if (i == 3) (f(ex.sequence[i] + 1, -20.0), 1.2),
          (f(ex.sequence[i], offs[i % offs.length]), 1.0),
        ]
      ];
    }
    const notes = <(int, double)>[
      (55, 1), (57, -14), (59, 12), (60, 0), (62, 6), (64, -4), (66, 2), (67, 0),
    ];
    return [for (final n in notes) (f(n.$1, n.$2), 0.9)];
  }

  /// Configura o exercício de escala. [tonicPc] 0..11; a oitava é escolhida
  /// perto da corda mais grave do instrumento atual.
  void setScale({int? tonicPc, ScaleType? type, int? octaves, bool? enabled}) {
    if (tonicPc != null) {
      final low = instrument.strings.first.midi;
      scaleTonicMidi = low + (((tonicPc - low) % 12) + 12) % 12;
    }
    if (type != null) scaleType = type;
    if (octaves != null) scaleOctaves = octaves;
    if (enabled != null) {
      scaleMode = enabled;
    }
    notifyListeners();
  }

  void resetGrid() {
    grid.clear();
    _gate.reset();
    tracker.reset();
    current = null;
    shown = null;
    _display.reset();
    liveTick.value++;
  }

  // ===================================================================
  // Metrônomo
  // ===================================================================
  // ---------------- Modo desafio ("sabotagem") ----------------
  /// Ligado: de surpresa o andamento muda ou o metrônomo cala por alguns compassos,
  /// e sempre volta ao andamento configurado.
  bool challengeOn = false;
  ChallengeConfig challengeCfg = const ChallengeConfig();

  void setChallenge({bool? on, ChallengeConfig? cfg}) {
    if (on != null) challengeOn = on;
    if (cfg != null) challengeCfg = cfg;
    _prefs?.setString('challenge', jsonEncode({'on': challengeOn, 'cfg': challengeCfg.toJson()}));
    setMetro(metro.copyWith(challenge: (challengeOn && challengeCfg.active) ? challengeCfg : null));
  }

  // ---------------- Eventos do metrônomo (tela e vibração) ----------------
  /// O último tempo marcado. A tela acende a bolinha com isto.
  final ValueNotifier<MetroBeat> metroBeat = ValueNotifier(MetroBeat.idle);
  Timer? _metroPump;

  /// Lê os cliques que chegaram à hora de soar e: avisa a tela e vibra. Fica no app (e não
  /// na tela do metrônomo) para a vibração continuar quando a pessoa está em outra aba.
  void _pumpMetro() {
    final due = metroPlayer.dueEvents();
    ClickEvent? last;
    for (final ev in due) {
      if (ev.sub == 0) last = ev;
    }
    if (last == null) return;
    metroBeat.value = MetroBeat(last.beat, last.bar, last.accent, hidden: last.hidden);
    // Várias de uma vez (o app ficou parado um instante): vibra uma vez só, no tempo mais recente.
    if (hapticEnabled && last.audible && !last.hidden) {
      buzz(ms: last.accent == Accent.strong ? 50 : 30);
    }
  }

  Future<void> toggleMetronome() async {
    if (metroPlayer.running) {
      final st = metroPlayer.challengeStats;
      _metroPump?.cancel();
      _metroPump = null;
      await metroPlayer.stop();
      metroBeat.value = MetroBeat.idle;
      _wake(listening);
      if (metro.challenge != null && (st.tempoChanges + st.silences) > 0) {
        final partes = [
          if (st.tempoChanges > 0) '${st.tempoChanges} mudança${st.tempoChanges > 1 ? 's' : ''} de andamento',
          if (st.silences > 0) '${st.silences} silêncio${st.silences > 1 ? 's' : ''}',
        ];
        say('Desafio concluído: ${partes.join(' e ')}.');
      }
    } else {
      await metroPlayer.start(metro);
      _metroPump = Timer.periodic(const Duration(milliseconds: 10), (_) => _pumpMetro());
      _wake(true);
    }
    notifyListeners();
  }

  void setMetro(MetronomeConfig c) {
    metro = c;
    metroPlayer.update(c);
    _save();
    notifyListeners();
  }

  void setBpm(double bpm) =>
      setMetro(metro.copyWith(bpm: bpm.clamp(20, 320).roundToDouble()));

  void tapTempo() {
    final b = _tap.tap(DateTime.now().millisecondsSinceEpoch);
    if (b != null && b >= 20 && b <= 320) setBpm(b);
  }

  void setSignature(int beats, {int? group}) {
    final nm = MetronomeConfig.signature(beats,
        bpm: metro.bpm,
        subdivision: metro.subdivision,
        sound: metro.sound,
        groupSize: group ?? (beats == 6 ? 3 : (beats == 7 ? 2 : null)));
    setMetro(nm.copyWith(
        volume: metro.volume,
        countInBars: metro.countInBars,
        trainer: metro.trainer,
        silent: metro.silent,
        challenge: metro.challenge));
  }

  void setSubdivision(int s) {
    setMetro(metro.copyWith(
        subdivision: s, subdivisionMask: List<bool>.filled(s, true)));
  }

  void cycleAccent(int beat) {
    const order = [Accent.strong, Accent.medium, Accent.weak, Accent.mute];
    final acc = List<Accent>.of(metro.accents);
    acc[beat] = order[(order.indexOf(acc[beat]) + 1) % order.length];
    setMetro(metro.copyWith(accents: acc));
  }

  // ===================================================================
  // Estudo
  // ===================================================================
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _studyTick() {
    // Conta como estudo: metrônomo ligado, ou nota tocada nos últimos 3 s.
    final manual = manualClockActive || (pomo.running && pomo.phase == PomoPhase.focus);
    final active = manual || metroPlayer.running || (listening && !demo && now - _lastNoteSeen < 3);
    if (!active) return;
    final k = dayKey(DateTime.now());
    studySeconds[k] = (studySeconds[k] ?? 0) + 1;
    if (DateTime.now().second % 15 == 0) _saveStudy();
  }

  Future<void> _saveStudy() async {
    await _prefs?.setString('study', jsonEncode(studySeconds));
  }

  double get todaySeconds => studySeconds[dayKey(DateTime.now())] ?? 0;

  ScaleReport buildReport() => buildScaleReport(grid, scaleNotes, cfg, kInTuneCents, now);

  Future<void> saveScaleSession(ScaleReport r) async {
    scaleSessions.insert(0, {
      'date': DateTime.now().toIso8601String(),
      'scale':
          scaleType.display(noteName(scaleTonicMidi, cfg)),
      'accuracy': r.accuracy,
      'played': r.played,
      'total': r.notes.length,
      'notes': [
        for (final n in r.notes)
          {'n': n.name, 's': n.status.index, 'c': n.avgCents}
      ],
    });
    if (scaleSessions.length > 100) scaleSessions.removeRange(100, scaleSessions.length);
    await _prefs?.setString('sessions', jsonEncode(scaleSessions));
    await _saveStudy();
    notifyListeners();
  }

  /// Apaga TUDO que o app guardou neste aparelho (ajustes, histórico, IA,
  /// permissões já explicadas) e volta ao estado de primeiro uso. Na web também
  /// limpa o cache da página e recarrega, para pegar a versão mais nova.
  Future<void> resetEverything() async {
    await stopListening(quiet: true);
    await _unlinkAllOnline();
    final p = _prefs ?? await SharedPreferences.getInstance();
    await p.clear();
    students = [];
    methodLibrary = [];
    activeStudentId = null;
    teacherPinHash = null;
    teacherUnlocked = false;
    stopwatch.reset();
    customClock.setCountdown(30 * 60000);
    customMinutes = 30;
    studyMode = StudyMode.pomodoro;
    _clockTimer?.cancel();
    _clockTimer = null;
    ai.clear();
    await ai.load();
    studySeconds.clear();
    scaleSessions.clear();
    sessionRecords.clear();
    onboarded = false;
    await load();
    notifyListeners();
    await clearWebCachesAndReload();
  }

  /// true quando o servidor já tem uma versão mais nova que a deste aparelho.
  bool updateAvailable = false;
  Timer? _updateTimer;

  /// Pergunta ao servidor qual é a versão publicada (web instalada no celular
  /// costuma ficar presa na antiga). Falhas de rede são ignoradas.
  Future<void> checkForUpdate() async {
    if (!kIsWeb || kBuildId.isEmpty || kBuildId == 'local') return;
    try {
      final r = await http
          .get(Uri.base.resolve('/build-id.txt?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 8));
      final id = r.statusCode == 200 ? r.body.trim() : '';
      final newer = id.isNotEmpty && id.length < 80 && !id.contains('<') && id != kBuildId;
      if (newer && !updateAvailable) {
        updateAvailable = true;
        say('Há uma versão nova do app. Toque em Configurações › Atualizar o app.');
        notifyListeners();
      }
    } catch (_) {}
  }

  void _scheduleUpdateChecks() {
    _updateTimer?.cancel();
    Future<void>.delayed(const Duration(seconds: 10), checkForUpdate);
    _updateTimer = Timer.periodic(const Duration(minutes: 20), (_) => checkForUpdate());
  }

  /// Busca a versão mais nova do app (web/PWA) sem apagar dados. Devolve false
  /// quando não se aplica (celular/desktop nativo: atualiza pela loja).
  Future<bool> updateApp() async {
    final ok = await updateWebAppAndReload();
    if (!ok) say('Este app se atualiza pela loja de aplicativos.');
    return ok;
  }

  Future<void> clearHistory() async {
    ai.clear(); // a análise por IA guardada também sai
    studySeconds.clear();
    scaleSessions.clear();
    await _prefs?.remove('study');
    await _prefs?.remove('sessions');
    sessionRecords.clear();
    await _prefs?.remove('sessions2');
    notifyListeners();
  }

  /// Mantém a tela acesa durante o uso. Falhas (ex.: navegador nega) são
  /// ignoradas: o app funciona igual, só a tela pode apagar.
  Future<void> _wake(bool on) async {
    try {
      if (on && keepAwake) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    ai.dispose();
    feedback.dispose();
    links.dispose();
    _metroPump?.cancel();
    _linkTimer?.cancel();
    dictation.dispose();
    _studyTimer?.cancel();
    _saveStudy();
    super.dispose();
  }
}
