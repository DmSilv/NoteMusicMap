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
import 'platform/web_push.dart';
import 'platform/web_vibrate.dart';
import 'audio/pitch_source.dart';
import 'data/repository.dart';
import 'feedback/feedback_service.dart';
import 'link/link_service.dart';
import 'stats/error_service.dart';
import 'stats/stats_service.dart';
import 'voice/dictation.dart';
import 'package:afina_core/afina_core.dart';
import 'package:afina_core/afina_core.dart' as core show linkNeedsAttention, linkShouldBeOn;

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

  /// O que o modo desafio faz neste compasso.
  final ChallengeKind challenge;

  /// BPM que está tocando AGORA (o treino "Acelerar aos poucos" muda isso sozinho), e o que falta para o próximo aumento
  /// (compassos ou segundos, conforme [trainerByTime]); [trainerAtMax] = já chegou ao teto.
  final double bpm;
  final double? trainerLeft;
  final bool trainerByTime;
  final bool trainerAtMax;
  const MetroBeat(this.beat, this.bar, this.accent,
      {this.hidden = false, this.challenge = ChallengeKind.normal, this.bpm = 0, this.trainerLeft, this.trainerByTime = false, this.trainerAtMax = false});
  static const idle = MetroBeat(-1, -1, Accent.weak);
}

/// Jeito de marcar o tempo de estudo.
enum StudyMode { pomodoro, stopwatch, custom }

enum TunerMode { strings, chromatic, pedal }

/// Situação das notificações de lembrete neste aparelho.
enum PushStatus { unknown, unsupported, needsInstall, denied, linkOff, serverOff, off, on }

/// Quão permissivo é o microfone.
/// rigorous: só notas limpas e fortes. free: aceita sons fracos, com ar,
/// vibrato forte ou ruído de fundo (pode errar mais a oitava).
enum MicSensitivity {
  rigorous(/*tr*/'Rigoroso', 0.88, 0.006, 3),
  normal(/*tr*/'Normal', 0.72, 0.0018, 2),
  free(/*tr*/'Livre', 0.55, 0.0008, 1);

  final String _label;
  String get label => tr(_label);
  final double minClarity;
  final double minRms;
  final int onsetFrames;
  const MicSensitivity(this._label, this.minClarity, this.minRms, this.onsetFrames);
}

/// Tipos de aviso: teacher (um professor te adicionou), lesson (aula/agenda nova), task (decisão do
/// professor), done (aluno marcou tarefa), pick (aluno pegou horário).
const kNoticeKinds = ['teacher', 'lesson', 'task', 'done', 'pick', 'support'];

/// Aviso para o usuário (aluno ou professor).
class AppNotice {
  final String kind; // um de [kNoticeKinds]
  final String text;
  final int atMs;
  bool seen;
  AppNotice(this.kind, this.text, this.atMs, {this.seen = false});

  Map<String, dynamic> toJson() => {'k': kind, 't': text, 'a': atMs, 's': seen};
  static AppNotice? tryFrom(Object? j) {
    try {
      final m = (j as Map).cast<String, dynamic>();
      final k = kNoticeKinds.contains(m['k']) ? m['k'] as String : 'teacher';
      final t = cleanText(m['t'] as String?, max: kMaxNote);
      if (t.isEmpty) return null;
      return AppNotice(k, t, ((m['a'] as num?)?.toInt() ?? 0).clamp(0, 4102444800000), seen: m['s'] == true);
    } catch (_) {
      return null;
    }
  }
}

/// Estado central do app. Sem login, sem rede: tudo fica no aparelho.
class AppState extends ChangeNotifier {
  // ---------------- Afinação ----------------
  double refA = 440;
  TuningSystem system = TuningSystem.equal;
  int tonicPc = 9; // Lá
  Anchor anchor = Anchor.a4;
  bool preferFlats = false;

  /// Grafia automática (padrão): alterna ♯ e ♭ e segue a tonalidade da escala.
  /// Desligada, vale só [preferFlats] (sempre ♯ ou sempre ♭).
  bool spellingAuto = true;

  /// Para textos de análise: null = automático, senão true = bemóis, false = sustenidos.
  bool? get flatsForText => spellingAuto ? null : preferFlats;

  /// Tonalidade ativa para a grafia: a da escala/exercício em andamento, ou nada.
  bool? get _keyFlats {
    if (!(scaleMode || exercise != null)) return null;
    final minor = scaleType.isMinor;
    return keyUsesFlats(scaleTonicMidi % 12, minor: minor);
  }
  int transpose = 0;
  String instrumentId = 'violino';
  TunerMode tunerMode = TunerMode.strings;
  /// Faixa "afinada" (±cents): padrão único do app, sem níveis.
  double get zoneCents => kInTuneCents;
  /// Faixa "afinada" da GRADE: um pouco mais folgada (a cor é a média de várias leituras, com ataque e vibrato),
  /// para acertar a nota e ver o verde sem ter que ficar parado no centro exato.
  double get gridZoneCents => kGridInTuneCents;
  HistoryMode history = HistoryMode.medium;
  double holdSeconds = 0; // 0 = a cor fica até zerar a grade (histórico das notas tocadas)

  TuningConfig get cfg => TuningConfig(
        refA: refA,
        system: system,
        tonicPc: tonicPc,
        anchor: anchor,
        preferFlats: preferFlats,
        transpose: transpose,
        autoSpelling: spellingAuto,
        keyFlats: spellingAuto ? _keyFlats : null,
        targetOverrides: _openTargets(),
      );

  // Cordas soltas de arco: no temperamento igual a grade mede o Sol, Ré, Lá e Mi soltos
  // pelo mesmo alvo do afinador de cordas (quintas puras). Guardado para não recalcular
  // a cada leitura do microfone.
  String? _openKey;
  Map<int, double>? _openMap;
  Map<int, double>? _openTargets() {
    if (system != TuningSystem.equal || instrument.fretted) return null;
    final key = '$instrumentId|$refA';
    if (key != _openKey) {
      _openKey = key;
      _openMap = instrument.openTargets(refA);
    }
    return _openMap;
  }
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
  /// Idioma em uso (português ou inglês). A raiz do app escuta e refaz as telas ao mudar.
  final ValueNotifier<AppLang> langNotifier = ValueNotifier(AppLang.pt);
  /// O que a pessoa escolheu em Ajustes: 'auto' (segue o aparelho), 'pt' ou 'en'.
  String langPref = 'auto';

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
    _adoptProfile(p);
    return true;
  }

  /// Liberação pelo suporte: o administrador gerou um código de uso único para o perfil [codeText].
  /// Este aparelho gera um segredo novo, o servidor confere o código e passa a reconhecer só este
  /// aparelho. Devolve null se deu certo, ou o texto do problema.
  Future<String?> claimWithSupport(String codeText, String supportText) async {
    final code = formatShareCode(codeText);
    if (code == null) return tr('O código do perfil está incorreto. Confira as letras e números.');
    final sup = normalizeSupportCode(supportText);
    if (sup == null) return tr('O código de suporte tem 8 letras e números (ex.: K7QM-4TXD).');
    final p = Profile.withCode(math.Random.secure(), code);
    final r = await links.claim(code, p.secret, sup);
    if (r.unavailable) return tr('O vínculo online não está disponível agora. Tente mais tarde.');
    if (r.offline) return tr('Sem conexão com o servidor. Tente de novo quando a internet voltar.');
    if (!r.ok) return r.error ?? tr('Não foi possível liberar a conta.');
    p.name = profile.name; // é a mesma pessoa, no mesmo aparelho: o nome continua
    _adoptProfile(p);
    return null;
  }

  void _adoptProfile(Profile p) {
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
    if (v && !linkEnabled) {
      // Professor precisa receber os avisos dos alunos: liga o vínculo junto.
      linkEnabled = true;
      _linkPrefOn();
      _saveLinks();
      linkUnavailable = false;
      unawaited(syncLinks());
    }
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
    final name = (exceptId == null ? null : studentById(exceptId)?.name) ?? tr('aluno');
    return checkStudent(name, input, exceptId: exceptId).code;
  }

  /// Confere um código de professor antes de registrá-lo como "meu professor".
  String? checkTeacherCode(String code) {
    final c = formatShareCode(code);
    if (c == null) return tr('Código inválido. Confira com o professor.');
    if (c == profile.shareCode) return tr('Este é o seu próprio código: você não pode ser o seu próprio professor.');
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
    final lessonGone = _lesson != null && ids.contains(_lesson!.studentId);
    students.removeWhere((s) => ids.contains(s.id));
    if (ids.contains(activeStudentId)) activeStudentId = null;
    if (lessonGone) {
      _lesson = null;
      _saveLessons();
    }
    _saveTeacher();
    notifyListeners();
    return before - students.length;
  }

  void removeStudent(String id) {
    final gone = studentById(id);
    if (gone != null) _unlinkStudentOnline(gone);
    final lessonGone = _lesson?.studentId == id;
    students.removeWhere((s) => s.id == id);
    if (activeStudentId == id) activeStudentId = null;
    if (lessonGone) {
      // A aula era dele: sem aluno não há o que encerrar nem enviar.
      _lesson = null;
      _saveLessons();
      say(tr('A aula em andamento foi descartada junto com o aluno.'));
    }
    _saveTeacher();
    notifyListeners();
  }

  void setActiveStudent(String? id) {
    activeStudentId = id;
    _saveTeacher();
    notifyListeners();
  }

  /// Registra que o aluno não veio à aula que começaria em [lessonMs] (só neste aparelho, na ficha do aluno).
  /// Registrar de novo a mesma aula troca o registro (de "faltou" para "avisou", por exemplo).
  void recordAbsence(Student s, {required int lessonMs, required AbsenceKind kind}) {
    s.absences = addAbsence(s.absences, Absence(lessonMs: lessonMs, kind: kind, recordedMs: DateTime.now().millisecondsSinceEpoch));
    _saveTeacher();
    notifyListeners();
  }

  /// Desfaz o último registro de falta feito (para um engano). Devolve true se havia algo para desfazer.
  bool undoLastAbsence(Student s) {
    if (s.absences.isEmpty) return false;
    final last = s.absences.reduce((a, b) => b.recordedMs > a.recordedMs ? b : a);
    s.absences = [for (final a in s.absences) if (!identical(a, last)) a];
    _saveTeacher();
    notifyListeners();
    return true;
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
            created: DateTime.now(),
            sent: false)); // ainda não enviada ao aluno
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
    if (text.length > 300000) return tr('Esse texto é grande demais. Importe em partes menores.');
    final found = parseMethodsText(text);
    if (found.isEmpty) return tr('Não encontrei métodos nesse texto. Use um método por linha, ou "Método: lição 1; lição 2".');
    if (found.length > 500 || found.fold<int>(0, (a, m) => a + m.lessons.length) > 8000) {
      return tr('Muitos itens de uma vez (máximo 500 métodos e 8000 lições). Importe em partes.');
    }
    final r = mergeMethods(methodLibrary, found);
    _saveMethods();
    notifyListeners();
    if (r.nothing) return tr('Esses métodos e lições já estavam na sua lista.');
    return tr('Importado: {0} método{1} novo{2} e {3} {4}.', [r.methods, r.methods == 1 ? '' : 's', r.methods == 1 ? '' : 's', r.lessons, r.lessons == 1 ? tr('lição') : tr('lições')]);
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

  /// Ficha do aparelho que acompanha o vínculo online (só com as estatísticas anônimas ligadas).
  Map<String, String>? _deviceCard() {
    if (!stats.enabled) return null;
    return {
      'pl': StatsService.platformTag(),
      'in': StatsService.installTag(),
      'v': StatsService.versionTag(),
      ...stats.deviceExtras(),
      // Minutos estudados nos últimos 7 dias (só números por dia; nunca o que foi tocado).
      'sm': [
        for (var i = 6; i >= 0; i--) ((studySeconds[AppState.dayKey(DateTime.now().subtract(Duration(days: i)))] ?? 0) / 60).round().clamp(0, 9999),
      ].join(','),
    };
  }

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

  /// Escolha explícita da pessoa ("on"/"off"); null = nunca mexeu (vale a regra automática).
  String? linkPref;

  bool get _hasStudentsWithCode => students.any((s) => s.code != null);

  /// Desligado, mas há quem dependa dele (modo professor, professor ou aluno vinculado).
  bool get linkNeedsAttention => core.linkNeedsAttention(
      enabled: linkEnabled,
      teacherMode: teacherMode,
      hasTeachers: myTeachers.isNotEmpty,
      hasStudentsWithCode: _hasStudentsWithCode);

  /// Sem nome o professor não sabe quem é o aluno (e o aluno, quem é o professor).
  bool get needsNickname => (profile.name ?? '').trim().isEmpty;

  void _linkPrefOn() {
    linkPref = 'on';
    _prefs?.setString('link_pref', 'on');
  }

  /// null = ainda não tentou; true = o servidor respondeu; false = sem conexão.
  bool? _linkOnline;

  /// Última vez que o servidor respondeu bem (para "Última atualização há 3 min").
  DateTime? linkOkAt;
  bool? get linkOnline => _linkOnline;
  set linkOnline(bool? v) {
    _linkOnline = v;
    if (v == true) linkOkAt = DateTime.now();
  }

  /// Quantos itens esperam para ir ao servidor (aulas, tarefas marcadas, agenda, desfazer vínculo).
  int get linkQueueSize =>
      doneOutbox.length +
      _unlinkStudents.length +
      _unlinkTeachers.length +
      agenda.where((s) => s.pending == true).length +
      students.fold<int>(0, (a, s) => a + s.lessons.where((l) => l.sent == false).length);

  /// O estado do vínculo em linguagem simples (para a tela).
  LinkStatusInfo get linkStatus => describeLink(
      enabled: linkEnabled,
      serverUnavailable: linkUnavailable,
      online: _linkOnline,
      queued: linkQueueSize,
      lastOkAt: linkOkAt,
      now: DateTime.now());

  /// "Reconectar agora": zera o que ficou emperrado (servidor marcado como indisponível, esperas
  /// e intervalos) e tenta de novo. Não apaga nada da fila. Devolve a frase para mostrar à pessoa.
  Future<String> reconnectLink() async {
    if (!linkEnabled) return tr('O vínculo online está desligado. Ligue para conectar.');
    linkUnavailable = false;
    _linkOnline = null;
    _idleTicks = 0;
    _skipTicks = 0;
    _workBackoffSec = 0;
    _nextWork = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
    await syncLinks();
    if (linkEnabled && !linkUnavailable) {
      // O que estava na fila tenta sair agora, sem esperar o relógio.
      await flushLessons();
      await flushDones();
      await flushAgenda();
    }
    notifyListeners();
    if (linkUnavailable) return tr('O servidor ainda não está disponível. Tente de novo em alguns minutos.');
    if (_linkOnline == true) {
      final q = linkQueueSize;
      return q > 0 ? tr('Conectado. {0} {1} para ser enviado.', [q, q == 1 ? tr('item ainda espera') : tr('itens ainda esperam')]) : tr('Conectado.');
    }
    return tr('Ainda sem conexão. Confira a internet e tente de novo.');
  }

  /// O servidor não tem o vínculo online configurado (sem Redis): não insistir.
  bool linkUnavailable = false;

  final Set<String> _unlinkStudents = {}; // alunos removidos aqui, a avisar o servidor
  final Set<String> _unlinkTeachers = {}; // professores removidos aqui
  Timer? _linkTimer;
  int _linkWatchers = 0;
  bool _linkSyncing = false;

  void _loadLinks(SharedPreferences p) {
    linkEnabled = p.getBool('link_on') ?? false;
    linkPref = p.getString('link_pref');
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
    // Ligado por padrão para quem tem professor, aluno ou modo professor; só fica desligado
    // se a pessoa escolheu desligar (e confirmou o aviso).
    final shouldOn = core.linkShouldBeOn(
        pref: linkPref,
        legacyOn: linkEnabled,
        teacherMode: teacherMode,
        hasTeachers: myTeachers.isNotEmpty,
        hasStudentsWithCode: _hasStudentsWithCode);
    if (shouldOn != linkEnabled) {
      linkEnabled = shouldOn;
      p.setBool('link_on', linkEnabled);
    }
    _unlinkStudents
      ..clear()
      ..addAll(p.getStringList('unlink_students') ?? const []);
    _unlinkTeachers
      ..clear()
      ..addAll(p.getStringList('unlink_teachers') ?? const []);
    _loadLessons(p);
    _loadAgenda(p);
    _loadNotices(p);
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

  // ---------------- Avisos para o aluno ----------------
  // Quando um professor adiciona o aluno (ou encerra uma aula para ele), o aluno
  // recebe um aviso que fica na tela de perfil até ele dispensar. Os avisos nascem
  // da atualização do vínculo (não há "push": o app consulta o servidor).

  /// Avisos do aluno, mais recente primeiro (no máximo 20).
  List<AppNotice> notices = [];

  int get unseenNotices => notices.where((n) => !n.seen).length;

  /// Aviso do suporte do painel (vínculo encerrado, item de agenda apagado): mostra uma vez só.
  void _supportNotice(LinkReply r) {
    if (r.snAt <= 0 || r.snKind.isEmpty) return;
    final seen = _prefs?.getInt('sn_seen') ?? 0;
    if (r.snAt <= seen) return;
    _prefs?.setInt('sn_seen', r.snAt);
    final who = r.snText.isEmpty ? tr('outra pessoa') : r.snText;
    addNotice(
        'support',
        r.snKind == 'unlink'
            ? tr('O suporte encerrou o seu vínculo com {0}.', [who])
            : tr('O suporte removeu {0} da sua agenda.', [who]));
    notifyListeners();
  }

  void addNotice(String kind, String text) {
    notices.insert(0, AppNotice(kind, cleanText(text, max: kMaxNote), DateTime.now().millisecondsSinceEpoch));
    if (notices.length > 20) notices.removeRange(20, notices.length);
    _saveNotices();
  }

  void dismissNotice(AppNotice n) {
    n.seen = true;
    _saveNotices();
    notifyListeners();
  }

  /// Apaga todos os avisos (central de avisos).
  void clearNotices() {
    if (notices.isEmpty) return;
    notices.clear();
    _saveNotices();
    notifyListeners();
  }

  void markNoticesSeen() {
    if (unseenNotices == 0) return;
    for (final n in notices) {
      n.seen = true;
    }
    _saveNotices();
    notifyListeners();
  }

  void _loadNotices(SharedPreferences p) {
    try {
      final raw = p.getString('notices');
      notices = raw == null
          ? []
          : [for (final x in (jsonDecode(raw) as List).take(20)) ?AppNotice.tryFrom(x)];
    } catch (_) {
      notices = [];
    }
  }

  void _saveNotices() => _prefs?.setString('notices', jsonEncode([for (final n in notices) n.toJson()]));

  DateTime? _lastLinkSync;

  /// O app voltou para a frente (o usuário reabriu ou trocou de aba): atualiza o vínculo
  /// se já faz um tempo, para o aluno ver na hora que um professor o adicionou.
  void onResume() {
    if (!linkEnabled || linkUnavailable) return;
    final t = _lastLinkSync;
    if (t == null || DateTime.now().difference(t).inSeconds > 20) unawaited(syncLinks());
  }

  // ---------------- Pedal (bordão) ----------------
  final PedalPlayer pedal = PedalPlayer();

  /// Notas do pedal que estão soando (MIDI, do grave ao agudo).
  List<int> pedalNotes = [];

  /// Liga ou desliga uma nota. Devolve um aviso se não deu (limite de notas).
  String? pedalToggle(int midi) {
    // O pedal e o microfone juntos se confundem: ao ligar o pedal, o microfone para.
    if (listening && !pedalNotes.contains(midi)) unawaited(stopListening(quiet: true));
    if (tone.running) tone.stop();
    final r = togglePedalNote(pedalNotes, midi);
    if (r.result == PedalToggle.full) return tr('No máximo {0} notas ao mesmo tempo. Toque numa nota ligada para tirar.', [kMaxPedalVoices]);
    if (r.result == PedalToggle.outOfRange) return tr('Essa nota está fora do teclado do pedal.');
    pedalNotes = r.notes;
    _applyPedal();
    return null;
  }

  /// Troca todas as notas de uma vez (atalhos como "Quinta" ou "Acorde maior").
  void setPedalNotes(List<int> midis) {
    if (listening && midis.isNotEmpty) unawaited(stopListening(quiet: true));
    if (tone.running) tone.stop();
    pedalNotes = ([...midis]..sort()).take(kMaxPedalVoices).toList();
    _applyPedal();
  }

  void clearPedal() {
    if (pedalNotes.isEmpty && !pedal.running) return;
    pedalNotes = [];
    unawaited(pedal.stop());
    notifyListeners();
  }

  /// Aplica as notas ao som, nas frequências do sistema de afinação escolhido.
  void _applyPedal() {
    pedal
      ..timbre = tone.timbre
      ..volume = tone.volume;
    final f = pedalFrequencies(pedalNotes, cfg);
    unawaited(pedal.setNotes([for (var i = 0; i < pedalNotes.length; i++) (pedalNotes[i], f[i])]));
    notifyListeners();
  }

  /// Prepara as notas de uma oitava do teclado para tocarem na hora.
  void preloadPedalRange(int fromMidi, int toMidi) {
    final f = pedalFrequencies([for (var m = fromMidi; m <= toMidi; m++) m], cfg);
    unawaited(pedal.preload(f));
  }

  // ---------------- Estatísticas anônimas de uso ----------------
  /// Aviso anônimo de acesso (para o painel do administrador). Desligável em Configurações.
  final StatsService stats = StatsService();
  Timer? _statsTimer;

  bool get statsEnabled => stats.enabled;

  void setStatsEnabled(bool v) {
    stats.setEnabled(v, _prefs);
    notifyListeners();
    if (v) unawaited(stats.open(_prefs));
  }

  /// A cada ~5 min, com o app à frente, "estou online". Não faz nada em segundo plano.
  void _startStats() {
    stats.micProbe = () => yesNoTag(micGranted);
    links.deviceProbe = _deviceCard;
    unawaited(stats.open(_prefs));
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_foreground) unawaited(stats.beat(_prefs));
    });
  }

  /// Uma aba ou tela foi aberta (conta aparelhos distintos por aba, uma vez por dia).
  void markTab(String name) {
    stats.markTab(name, _prefs);
    final label = _tabLabels[name];
    if (label != null) {
      crumb(label);
      markWhere(label);
    }
  }

  static final _tabLabels = {
    'tuner': tr('Afinador'),
    'pedal': tr('Pedal'),
    'metronome': tr('Metrônomo'),
    'grid': tr('Grade'),
    'scales': tr('Escalas'),
    'study': tr('Meu espaço'),
    'profile': tr('Minha conta'),
    'teacher': tr('Alunos'),
    'agenda': tr('Agenda'),
    'settings': tr('Ajustes'),
  };

  // ---------------- Agenda de aulas ----------------
  /// PROFESSOR: aulas que marcou (cada regra semanal é UMA entrada).
  List<ClassSlot> agenda = [];

  /// ALUNO: aulas marcadas pelos professores (sem as canceladas).
  List<ClassSlot> myAgenda = [];
  int _agendaRev = 0;
  bool _agendaSending = false;
  bool _agendaPulling = false;

  void _loadAgenda(SharedPreferences p) {
    List<ClassSlot> read(String key, {bool dropCanceled = false}) {
      try {
        final raw = p.getString(key);
        if (raw == null) return [];
        return [
          for (final x in (jsonDecode(raw) as List).take(kMaxSlotsPerTeacher))
            if (ClassSlot.tryFrom(x) case final s? when !(dropCanceled && s.canceled)) s
        ];
      } catch (_) {
        return [];
      }
    }

    agenda = read('agenda');
    myAgenda = read('agenda_in', dropCanceled: true);
    _agendaRev = p.getInt('agenda_rev') ?? 0;
    openSlots = read('open_slots');
    errorLog = ErrorLog.fromJsonString(p.getString('error_log'));
    reportMode = ReportMode.values.where((m) => m.name == p.getString('report_mode')).firstOrNull ?? ReportMode.critical;
    hubViewPref = switch (p.getString('hub_view')) {
      'student' => HubView.student,
      'teacher' => HubView.teacher,
      _ => null,
    };
    _picksRev = p.getInt('picks_rev') ?? 0;
  }

  void _saveAgenda() {
    final p = _prefs;
    if (p == null) return;
    p.setString('agenda', jsonEncode([for (final s in agenda) s.toJson()]));
    p.setString('agenda_in', jsonEncode([for (final s in myAgenda) s.toJson()]));
    p.setInt('agenda_rev', _agendaRev);
    p.setString('open_slots', jsonEncode([for (final s in openSlots) s.toJson()]));
    p.setInt('picks_rev', _picksRev);
  }

  /// As aulas marcadas (não canceladas) do professor com o aluno [code].
  List<ClassSlot> slotsOf(String code) => [for (final s in agenda) if (!s.canceled && s.studentCode == code) s];

  bool _canSendTo(Student s) => s.code != null && s.linkState != 'ended';

  /// Marca ou muda uma aula. Devolve o motivo se não der (aluno, horário que passou, choque
  /// com outra aula); null se salvou.
  String? saveSlot(ClassSlot s) {
    crumb(tr('Marcar aula'));
    final st = studentByCode(s.studentCode);
    if (st == null) return tr('Escolha o aluno.');
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = agenda.where((x) => x.id == s.id).firstOrNull;
    // Mudou o dia ou a hora de uma regra semanal: as datas já canceladas acompanham (senão a aula cancelada voltaria).
    if (old != null && s.weekly && old.startMs != s.startMs) s = s.copyWith(skipped: remapSkipped(old.startMs, s.startMs, s.skipped));
    if (!s.weekly && s.startMs < now - 5 * kMsMinute && (old == null || old.startMs != s.startMs)) {
      return tr('Esse horário já passou. Escolha uma data de hoje em diante.');
    }
    final clash = findConflict(s, agenda, now);
    if (clash != null) {
      final who = studentByCode(clash.slot.studentCode)?.name ?? tr('outro aluno');
      return tr('Choca com a aula de {0} ({1}). Escolha outro horário.', [who, fmtSlotWhen(clash.start, DateTime.now())]);
    }
    final stamp = old == null ? now : (now > old.updatedMs ? now : old.updatedMs + 1);
    final saved = s.copyWith(updatedMs: stamp, pending: _canSendTo(st) ? true : null);
    final i = agenda.indexWhere((x) => x.id == s.id);
    if (i >= 0) {
      agenda[i] = saved;
    } else if (agenda.length >= kMaxSlotsPerTeacher) {
      return tr('Limite de aulas marcadas atingido. Cancele algumas antigas.');
    } else {
      agenda.add(saved);
    }
    _saveAgenda();
    notifyListeners();
    if (saved.pending == true) unawaited(flushAgenda());
    return null;
  }

  /// Cancela a aula inteira (regra semanal ou aula única). O aluno é avisado.
  void cancelSlot(String id) {
    final i = agenda.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final st = studentByCode(agenda[i].studentCode);
    final now = DateTime.now().millisecondsSinceEpoch;
    agenda[i] = agenda[i].copyWith(
        canceled: true,
        updatedMs: now > agenda[i].updatedMs ? now : agenda[i].updatedMs + 1,
        pending: st != null && _canSendTo(st) ? true : null);
    _saveAgenda();
    notifyListeners();
    if (agenda[i].pending == true) unawaited(flushAgenda());
  }

  /// Cancela só a aula do dia [startMs] de uma regra semanal.
  void skipOccurrence(String id, int startMs) {
    final i = agenda.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final s = agenda[i];
    if (!s.weekly) return cancelSlot(id);
    if (s.skipped.length >= kMaxSlotSkips) return;
    final st = studentByCode(s.studentCode);
    final now = DateTime.now().millisecondsSinceEpoch;
    agenda[i] = s.copyWith(
        skipped: [...s.skipped, startMs],
        updatedMs: now > s.updatedMs ? now : s.updatedMs + 1,
        pending: st != null && _canSendTo(st) ? true : null);
    _saveAgenda();
    notifyListeners();
    if (agenda[i].pending == true) unawaited(flushAgenda());
  }

  /// PROFESSOR: envia ao servidor as aulas marcadas que ainda não foram (e o servidor agenda o lembrete).
  Future<void> flushAgenda() async {
    if (_agendaSending || !linkEnabled || linkUnavailable) return;
    _agendaSending = true;
    var changed = false;
    try {
      for (var i = 0; i < agenda.length; i++) {
        final s = agenda[i];
        if (s.pending != true) continue;
        final st = studentByCode(s.studentCode);
        if (st == null || !_canSendTo(st)) {
          agenda[i] = s.copyWith(pending: null);
          changed = true;
          continue;
        }
        if (st.linkState != 'active') continue; // espera o vínculo ser confirmado
        final r = await links.schedPut(profile.shareCode, profile.secret, student: s.studentCode, slot: s);
        if (r.unavailable) {
          _markLinkUnavailable();
          break;
        }
        if (r.offline) {
          linkOnline = false;
          break;
        }
        if (r.notReady) {
          deliveryIssue[s.studentCode] = 'not_ready';
          changed = true;
          continue; // o aluno ainda não ligou o vínculo: tenta de novo mais tarde
        }
        if (r.ok || r.rejected) {
          // aceito (ou recusado de vez: não adianta insistir); a aula só deixa de estar na fila
          agenda[i] = agenda[i].copyWith(pending: false);
          deliveryIssue.remove(s.studentCode);
          changed = true;
          if (!r.ok) fail(tr('Não foi possível avisar {0} da aula.', [st.name]), where: tr('Agenda do professor'), detail: r.error);
        }
      }
    } finally {
      _agendaSending = false;
      // Aulas canceladas e já enviadas, com mais de 30 dias, saem da lista guardada.
      final cut = DateTime.now().millisecondsSinceEpoch - 30 * kMsDay;
      final before = agenda.length;
      agenda.removeWhere((s) => s.canceled && s.pending != true && s.updatedMs < cut);
      if (changed || agenda.length != before) {
        _saveAgenda();
        notifyListeners();
      }
    }
  }

  // ---------------- Horários disponíveis (professor) e pegar horário (aluno) ----------------
  /// PROFESSOR: horários que deixou livres para os alunos pegarem.
  List<ClassSlot> openSlots = [];
  bool _openSending = false;
  bool _picksPulling = false;

  /// Horários livres ainda válidos (sem os cancelados e os que já passaram).
  List<ClassSlot> get openSlotsActive {
    final now = DateTime.now().millisecondsSinceEpoch;
    final l = [for (final s in openSlots) if (!s.canceled && s.nextStart(now) != null) s];
    l.sort((a, b) => a.nextStart(now)!.compareTo(b.nextStart(now)!));
    return l;
  }

  /// Cria ou muda um horário disponível. Devolve o motivo se não der; null se salvou.
  String? saveOpenSlot(ClassSlot s) {
    crumb(tr('Publicar horário livre'));
    final now = DateTime.now().millisecondsSinceEpoch;
    final p = checkNewOpenSlot(s, open: openSlots.where((x) => !x.canceled), classes: agenda.where((x) => !x.canceled), nowMs: now);
    if (p != null) return slotProblemText(p);
    final saved = s.copyWith(updatedMs: now, pending: true);
    final i = openSlots.indexWhere((x) => x.id == s.id);
    i >= 0 ? openSlots[i] = saved : openSlots.add(saved);
    _saveAgenda();
    notifyListeners();
    unawaited(flushOpenSlots());
    return null;
  }

  /// Apaga um horário disponível (some para os alunos).
  void removeOpenSlot(String id) {
    final i = openSlots.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    openSlots[i] = openSlots[i].copyWith(canceled: true, updatedMs: now, pending: true);
    _saveAgenda();
    notifyListeners();
    unawaited(flushOpenSlots());
  }

  Future<void> flushOpenSlots() async {
    if (_openSending || !linkEnabled || linkUnavailable) return;
    _openSending = true;
    var changed = false;
    try {
      for (var i = 0; i < openSlots.length; i++) {
        final s = openSlots[i];
        if (s.pending != true) continue;
        final r = await links.availPut(profile.shareCode, profile.secret, slot: s);
        if (r.unavailable) {
          _markLinkUnavailable();
          break;
        }
        if (r.offline) {
          linkOnline = false;
          break;
        }
        if (r.ok || r.rejected) {
          openSlots[i] = s.copyWith(pending: false);
          changed = true;
          if (!r.ok) fail(tr('Não foi possível publicar o horário: {0}', [_slotError(r.error)]), where: tr('Horários livres'), detail: r.error);
        }
      }
    } finally {
      _openSending = false;
      openSlots.removeWhere((s) => s.canceled && s.pending != true);
      if (changed) {
        _saveAgenda();
        notifyListeners();
      }
    }
  }

  static String _slotError(String? code) => switch (code) {
        'slot_gone' => tr('Este horário não está mais disponível.'),
        'slot_taken' => tr('Alguém acabou de pegar este horário.'),
        'slot_past' => tr('Este horário já passou.'),
        'slot_soon' => tr('Falta pouco para este horário: peça direto ao professor.'),
        'slot_conflict' => tr('Este horário bate com outra aula do professor.'),
        'pick_limit' => tr('Você já tem muitas aulas marcadas com este professor.'),
        _ => code ?? tr('tente de novo.'),
      };

  /// PROFESSOR: traz as aulas que alunos pegaram e as coloca na agenda.
  Future<void> pullPicks() async {
    if (_picksPulling || !linkEnabled || linkUnavailable || students.isEmpty) return;
    _picksPulling = true;
    try {
      final r = await links.picks(profile.shareCode, profile.secret);
      if (r.unavailable) return _markLinkUnavailable();
      if (!r.ok) {
        if (r.offline) linkOnline = false;
        return;
      }
      linkOnline = true;
      final now = DateTime.now();
      final notes = <String>[];
      for (final s in r.picks) {
        if (agenda.any((x) => x.id == s.id)) continue;
        final st = studentByCode(s.studentCode);
        if (st == null) continue;
        agenda.add(s.copyWith(pending: false));
        // O horário disponível que originou essa aula já foi levado no servidor: tira daqui também.
        openSlots.removeWhere((o) => o.startMs == s.startMs && o.durationMin == s.durationMin && o.weekly == s.weekly);
        final at = s.nextStart(now.millisecondsSinceEpoch);
        notes.add(tr('{0} pegou o horário{1}.', [st.name, at == null ? '' : tr(' de {0}', [fmtSlotWhen(DateTime.fromMillisecondsSinceEpoch(at), now)])]));
      }
      _picksRev = r.ar;
      _saveAgenda();
      notifyListeners();
      if (notes.isNotEmpty) {
        final msg = notes.length == 1 ? notes.first : tr('{0} alunos pegaram horários.', [notes.length]);
        addNotice('pick', msg);
        say(msg);
      }
    } finally {
      _picksPulling = false;
    }
  }

  /// ALUNO: horários livres do professor [teacher] (null = não deu para consultar).
  Future<List<ClassSlot>?> loadOpenSlots(String teacher) async {
    final r = await links.avail(profile.shareCode, profile.secret, teacher: teacher);
    if (r.unavailable) {
      _markLinkUnavailable();
      return null;
    }
    if (!r.ok) {
      if (r.offline) linkOnline = false;
      return null;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return pickableSlots(r.open, nowMs: now);
  }

  /// ALUNO: pega o horário [slot] do professor [teacher]. Devolve o motivo se não der; null se pegou.
  Future<String?> takeOpenSlot(String teacher, ClassSlot slot) async {
    // Trava contra toque duplo: só um pedido por vez (o servidor também impede dois alunos, mas assim
    // o mesmo aluno não dispara duas aulas).
    if (_taking) return tr('Aguarde: o pedido anterior ainda está sendo enviado.');
    _taking = true;
    try {
      return await _takeOpenSlot(teacher, slot);
    } finally {
      _taking = false;
    }
  }

  bool _taking = false;

  Future<String?> _takeOpenSlot(String teacher, ClassSlot slot) async {
    crumb(tr('Pegar horário'));
    final now = DateTime.now().millisecondsSinceEpoch;
    final mine = myAgenda.where((s) => s.teacherCode == teacher && s.nextStart(now) != null).length;
    final p = checkPick(slot, teacherClasses: const [], studentUpcoming: mine, nowMs: now);
    if (p != null && p != SlotProblem.conflict) return slotProblemText(p);
    final r = await links.availTake(profile.shareCode, profile.secret, teacher: teacher, slotId: slot.id);
    if (r.unavailable) return tr('Sem conexão com o servidor. Tente de novo.');
    if (r.offline) return tr('Sem internet. Tente de novo.');
    if (!r.ok) return _slotError(r.error);
    unawaited(pullAgenda(announce: false));
    return null;
  }

  /// ALUNO: traz as aulas marcadas. Avisa se há aula nova, mudada ou cancelada.
  Future<void> pullAgenda({bool announce = true}) async {
    if (_agendaPulling || !linkEnabled || linkUnavailable) return;
    _agendaPulling = true;
    try {
      final r = await links.sched(profile.shareCode, profile.secret);
      if (r.unavailable) return _markLinkUnavailable();
      if (!r.ok) {
        if (r.offline) linkOnline = false;
        return;
      }
      linkOnline = true;
      final before = {for (final s in myAgenda) '${s.teacherCode}:${s.id}': s};
      final names = {for (final t in myTeachers) t.code: t.name};
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final next = <ClassSlot>[];
      final notes = <String>[];
      for (final s in r.slots) {
        final key = '${s.teacherCode}:${s.id}';
        final who = (s.teacherName.isNotEmpty ? s.teacherName : (names[s.teacherCode] ?? '')).trim();
        final label = who.isEmpty ? tr('Seu professor') : who;
        final old = before[key];
        if (s.canceled) {
          if (old != null && old.nextStart(nowMs) != null) notes.add(tr('{0} cancelou a aula marcada.', [label]));
          continue;
        }
        next.add(s);
        final nextAt = s.nextStart(nowMs);
        if (nextAt == null) continue;
        if (old == null) {
          notes.add(tr('{0} marcou uma aula: {1}.', [label, fmtSlotWhen(DateTime.fromMillisecondsSinceEpoch(nextAt), now)]));
        } else if (s.updatedMs > old.updatedMs && (s.startMs != old.startMs || s.skipped.length > old.skipped.length)) {
          notes.add(tr('{0} mudou a aula: agora {1}.', [label, fmtSlotWhen(DateTime.fromMillisecondsSinceEpoch(nextAt), now)]));
        }
      }
      myAgenda = next;
      _agendaRev = r.sr;
      _saveAgenda();
      notifyListeners();
      if (announce && notes.isNotEmpty) {
        final msg = notes.length == 1 ? notes.first : tr('{0} novidades na sua agenda de aulas.', [notes.length]);
        addNotice('lesson', msg);
        say(msg);
      }
    } finally {
      _agendaPulling = false;
    }
  }

  // ---------------- Visões do Meu espaço (aluno | professor) ----------------
  /// Escolha da pessoa (null = nunca escolheu).
  HubView? hubViewPref;

  /// Tem o lado de aluno: professor, aula recebida ou agenda marcada por um professor.
  bool get hasTeacherSide => myTeachers.isNotEmpty || myLessons.isNotEmpty || myAgenda.isNotEmpty;

  bool get canSwitchHub => canSwitchHubView(teacherMode: teacherMode, hasTeacherSide: hasTeacherSide);

  /// Visão que o Meu espaço mostra agora.
  HubView get hubView => resolveHubView(teacherMode: teacherMode, hasTeacherSide: hasTeacherSide, preferred: hubViewPref);

  void setHubView(HubView v) {
    hubViewPref = v;
    _prefs?.setString('hub_view', v.name);
    notifyListeners();
  }

  /// A próxima aula da visão [v]: do professor (as que ele marcou) ou do aluno (as que recebeu).
  SlotOccurrence? nextClassFor(HubView v) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return v == HubView.teacher ? nextOccurrence(visibleAgenda, now) : nextOccurrence(myAgenda, now);
  }

  /// PROFESSOR: as aulas que valem para mostrar (sem canceladas e sem as de alunos que já não existem).
  /// Hub, agenda e próxima aula usam SEMPRE esta lista, para os números nunca divergirem.
  List<ClassSlot> get visibleAgenda => visibleTeacherSlots(agenda, {for (final s in students) ?s.code});

  /// A próxima aula (ou a que está em andamento) para mostrar ao usuário agora: do professor
  /// (as que ele marcou) ou do aluno (as que recebeu); vale a que vier primeiro.
  SlotOccurrence? get nextClass {
    final now = DateTime.now().millisecondsSinceEpoch;
    final mine = nextOccurrence(visibleAgenda, now);
    final theirs = nextOccurrence(myAgenda, now);
    if (mine == null) return theirs;
    if (theirs == null) return mine;
    return mine.startMs <= theirs.startMs ? mine : theirs;
  }

  // ---------------- Notificações do navegador (lembrete de aula) ----------------
  PushStatus pushStatus = PushStatus.unknown;
  bool _pushBusy = false;

  /// Confere o que dá para fazer neste aparelho (suporte, permissão, servidor pronto, inscrição).
  Future<void> refreshPush() async {
    if (_pushBusy) return;
    _pushBusy = true;
    try {
      if (!webPushSupported()) {
        pushStatus = webIsIos() && !webPushStandalone() ? PushStatus.needsInstall : PushStatus.unsupported;
      } else if (webPushPermission() == 'denied') {
        pushStatus = PushStatus.denied;
      } else if (!linkEnabled || linkUnavailable) {
        pushStatus = PushStatus.linkOff;
      } else {
        final k = await links.pushKey(profile.shareCode, profile.secret);
        if (k.unavailable || (k.ok && k.pushKey.isEmpty)) {
          pushStatus = PushStatus.serverOff;
        } else if (!k.ok) {
          pushStatus = PushStatus.unknown;
        } else {
          final cur = await webPushCurrent();
          pushStatus = webPushPermission() == 'granted' && cur != null ? PushStatus.on : PushStatus.off;
        }
      }
    } finally {
      _pushBusy = false;
      notifyListeners();
    }
  }

  /// Liga os lembretes neste aparelho (precisa vir de um toque). Devolve uma mensagem se não deu.
  Future<String?> enablePush() async {
    if (!webPushSupported()) {
      return webIsIos() && !webPushStandalone()
          ? tr('No iPhone, instale o app na tela inicial (Compartilhar › Adicionar à Tela de Início) e abra por lá.')
          : tr('Este navegador não permite notificações.');
    }
    if (!linkEnabled) return tr('Ligue o "Vínculo online" no perfil primeiro: é ele que leva a agenda ao outro lado.');
    final k = await links.pushKey(profile.shareCode, profile.secret);
    if (!k.ok || k.pushKey.isEmpty) return tr('Os lembretes ainda não estão ativos no servidor.');
    final perm = await webPushRequestPermission();
    if (perm != 'granted') {
      await refreshPush();
      return tr('Sem a permissão do navegador não dá para avisar. Libere as notificações deste site nas configurações do navegador.');
    }
    final subJson = await webPushSubscribe(k.pushKey);
    if (subJson == null) return tr('Não foi possível ativar neste aparelho.');
    try {
      final sub = (jsonDecode(subJson) as Map).cast<String, dynamic>();
      final r = await links.pushSub(profile.shareCode, profile.secret, sub);
      if (!r.ok) return r.error ?? tr('O servidor não aceitou a ativação. Tente de novo.');
    } catch (_) {
      return tr('Não foi possível ativar neste aparelho.');
    }
    _prefs?.setBool('push_on', true);
    await refreshPush();
    return null;
  }

  Future<void> disablePush() async {
    final ep = await webPushUnsubscribe();
    if (ep != null && linkEnabled) await links.pushUnsub(profile.shareCode, profile.secret, ep);
    _prefs?.setBool('push_on', false);
    await refreshPush();
  }

  // ---------------- Consulta barata de novidades (custo por usuário) ----------------
  // O app NÃO baixa listas a cada 30 s: pergunta `rev` (1 comando no servidor) e só faz a
  // atualização completa (vários comandos) quando um contador mudou ou há algo local a enviar.
  bool _foreground = true;
  int _linkRev = 0; // kr visto: vínculos
  int _doneRev = 0; // dr visto: tarefas marcadas pelos alunos
  int _verdictRev = 0; // vr visto: decisões do professor
  int _picksRev = 0; // ar visto: horários que alunos pegaram
  int _workBackoffSec = 0;
  int _idleTicks = 0; // consultas seguidas sem novidade: o intervalo vai esticando (até 4x)
  int _skipTicks = 0;
  DateTime _nextWork = DateTime.fromMillisecondsSinceEpoch(0);

  /// Sem tela à frente (aba escondida, app em segundo plano) não consulta nada.
  void setForeground(bool v) {
    _foreground = v;
    if (!v) clearPedal(); // em segundo plano o pedal para (bateria)
    if (v) {
      onResume();
      final t = stats.lastOpen;
      if (t == null || DateTime.now().difference(t).inMinutes >= 30) unawaited(stats.open(_prefs)); // nova sessão
      // Ao voltar ao app, confere se há versão nova (no máximo a cada 2 minutos).
      final lc = _lastUpdateCheck;
      if (lc == null || DateTime.now().difference(lc).inMinutes >= 2) unawaited(checkForUpdate());
    }
  }

  /// Há algo só aqui que precisa ir ao servidor (desfazer vínculo, aula/tarefa na fila, marcação)?
  bool _hasLocalWork() =>
      _unlinkStudents.isNotEmpty ||
      _unlinkTeachers.isNotEmpty ||
      doneOutbox.isNotEmpty ||
      agenda.any((s) => s.pending == true) ||
      myTeachers.any((t) => t.since == 0) ||
      students.any((s) =>
          s.code != null &&
          (s.linkState == null || s.linkState == 'pending' || s.lessons.any((l) => l.sent == false)));

  /// Uma "batida" do relógio de consulta: barata quando nada mudou.
  Future<void> _linkTick() async {
    if (!_foreground || !linkEnabled || linkUnavailable || _linkSyncing) return;
    if (_skipTicks > 0) {
      _skipTicks--;
      return;
    }
    final now = DateTime.now();
    if (_hasLocalWork() && !now.isBefore(_nextWork)) {
      await syncLinks();
      // Se continua pendente (aluno que não ligou o vínculo, sem rede…), espera cada vez mais.
      if (_hasLocalWork()) {
        _workBackoffSec = _workBackoffSec == 0 ? 30 : (_workBackoffSec * 2).clamp(30, 600);
        _nextWork = DateTime.now().add(Duration(seconds: _workBackoffSec));
      } else {
        _workBackoffSec = 0;
      }
      return;
    }
    final r = await links.rev(profile.shareCode, profile.secret);
    if (r.unavailable) return _markLinkUnavailable();
    if (!r.ok) {
      if (r.offline) {
        linkOnline = false;
        notifyListeners();
      }
      return;
    }
    linkOnline = true;
    _supportNotice(r);
    final lessonsNew = myTeachers.isNotEmpty && r.lr != lessonsRev;
    final donesNew = students.isNotEmpty && r.dr != _doneRev;
    final agendaNew = myTeachers.isNotEmpty && r.sr != _agendaRev;
    final verdictsNew = myTeachers.isNotEmpty && r.vr != _verdictRev;
    final picksNew = students.isNotEmpty && r.ar != _picksRev;
    if (lessonsNew || donesNew || agendaNew || verdictsNew || picksNew || r.kr != _linkRev) {
      _idleTicks = 0;
      await syncLinks();
    } else {
      // Nada mudou: espera um pouco mais na próxima (mais barato para o servidor e para a bateria).
      _idleTicks = (_idleTicks + 1).clamp(0, 9);
      _skipTicks = _idleTicks ~/ 3;
    }
  }

  // ---------------- ALUNO: avisar o professor que fez a tarefa ----------------
  /// Marcações a enviar ("professor|aula|tarefa|1 ou 0"), guardadas até o servidor aceitar.
  final List<String> doneOutbox = [];
  bool _donesSending = false;

  void _queueDone(String teacher, String lesson, String task, bool done) {
    final key = '$teacher|$lesson|$task|';
    doneOutbox.removeWhere((e) => e.startsWith(key));
    doneOutbox.add('$key${done ? 1 : 0}');
    if (doneOutbox.length > 500) doneOutbox.removeRange(0, doneOutbox.length - 500);
    _prefs?.setStringList('done_outbox', doneOutbox);
  }

  Future<void> flushDones() async {
    if (_donesSending || !linkEnabled || linkUnavailable || doneOutbox.isEmpty) return;
    _donesSending = true;
    try {
      for (final e in [...doneOutbox]) {
        final p = e.split('|');
        if (p.length != 4) {
          doneOutbox.remove(e);
          continue;
        }
        final r = await links.markDone(profile.shareCode, profile.secret,
            teacher: p[0], lesson: p[1], task: p[2], done: p[3] == '1');
        if (r.unavailable) return _markLinkUnavailable();
        if (r.offline) {
          linkOnline = false;
          break;
        }
        if (r.ok || r.rejected) doneOutbox.remove(e); // aceito, ou recusado de vez (professor desvinculado)
      }
    } finally {
      _donesSending = false;
      _prefs?.setStringList('done_outbox', doneOutbox);
    }
  }

  // ---------------- PROFESSOR: ver e validar o que o aluno marcou ----------------
  /// Tarefas que [s] marcou como feitas e esperam a validação do professor.
  List<Assignment> awaitingOf(Student s) => awaitingValidation(s);

  /// Total de tarefas esperando validação (todos os alunos).
  int get awaitingTotal => students.fold<int>(0, (a, s) => a + awaitingValidation(s).length);

  /// Traz o que os alunos marcaram e aplica nas fichas. Avisa o professor se houver novidade.
  Future<void> pullDones() async {
    if (_donesPulling || !linkEnabled || linkUnavailable || students.isEmpty) return;
    _donesPulling = true;
    try {
      final r = await links.dones(profile.shareCode, profile.secret);
      if (r.unavailable) return _markLinkUnavailable();
      if (!r.ok) {
        if (r.offline) linkOnline = false;
        return;
      }
      linkOnline = true;
      final byStudent = <String, List<DoneEntry>>{};
      for (final e in r.dones) {
        (byStudent[e.studentCode] ??= []).add(e);
      }
      var fresh = 0;
      String? who;
      for (final s in students) {
        final c = s.code;
        if (c == null) continue;
        final n = applyClaims(s, byStudent[c] ?? const []);
        if (n > 0) {
          fresh += n;
          who = s.name;
        }
      }
      for (final e in r.dones) {
        _claimLesson[e.taskId] = e.lessonId;
      }
      if (_claimLesson.length > 3000) {
        for (final k in _claimLesson.keys.take(_claimLesson.length - 3000).toList()) {
          _claimLesson.remove(k);
        }
      }
      _prefs?.setString('claim_lessons', jsonEncode(_claimLesson));
      _doneRev = r.dr;
      _prefs?.setInt('done_rev', _doneRev);
      _saveTeacher();
      notifyListeners();
      if (fresh > 0) {
        final msg = fresh == 1 && who != null
            ? tr('{0} marcou 1 tarefa como feita. Valide na ficha ou ao começar a próxima aula.', [who])
            : tr('{0} tarefas marcadas como feitas pelos alunos. Valide na ficha de cada um.', [fresh]);
        addNotice('done', msg);
        say(msg);
      }
    } finally {
      _donesPulling = false;
    }
  }

  bool _donesPulling = false;

  /// Confirma (finaliza) ou devolve (volta a pendente) uma tarefa que o aluno marcou.
  void validateAssignment(Student s, String taskId, {required bool ok}) {
    crumb(ok ? tr('Validar tarefa') : tr('Devolver tarefa'));
    if (!validateTask(s, taskId, ok: ok)) return;
    _saveTeacher();
    // O aluno passa a ver a decisão oficial (vai pela fila e reenvia sozinha se estiver sem conexão).
    final lesson = _claimLesson[taskId];
    if (lesson != null && s.code != null && linkEnabled) {
      _queueVerdict(s.code!, lesson, taskId, ok ? Verdict.ok : Verdict.back);
      unawaited(flushVerdicts());
    }
    notifyListeners();
  }

  /// Decisões a enviar ("aluno|aula|tarefa|ok ou back"), guardadas até o servidor aceitar.
  final List<String> verdictOutbox = [];
  bool _verdictsSending = false;

  /// Em qual aula veio a marcação de cada tarefa (o professor só guarda o id da tarefa).
  final Map<String, String> _claimLesson = {};

  static Map<String, String> _decodeClaimLessons(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map;
      return {for (final e in m.entries) if (e.value is String) e.key as String: e.value as String};
    } catch (_) {
      return {};
    }
  }

  void _queueVerdict(String student, String lesson, String task, Verdict v) {
    final key = '$student|$lesson|$task|';
    verdictOutbox.removeWhere((e) => e.startsWith(key));
    verdictOutbox.add('$key${verdictWire(v)}');
    if (verdictOutbox.length > 500) verdictOutbox.removeRange(0, verdictOutbox.length - 500);
    _prefs?.setStringList('verdict_outbox', verdictOutbox);
  }

  Future<void> flushVerdicts() async {
    if (_verdictsSending || !linkEnabled || linkUnavailable || verdictOutbox.isEmpty) return;
    _verdictsSending = true;
    try {
      for (final e in [...verdictOutbox]) {
        final p = e.split('|');
        final v = p.length == 4 ? verdictFromWire(p[3]) : null;
        if (v == null) {
          verdictOutbox.remove(e);
          continue;
        }
        final r = await links.sendVerdict(profile.shareCode, profile.secret,
            student: p[0], lesson: p[1], task: p[2], verdict: v);
        if (r.unavailable) return _markLinkUnavailable();
        if (r.offline) {
          linkOnline = false;
          break;
        }
        if (r.ok || r.rejected) verdictOutbox.remove(e);
      }
    } finally {
      _verdictsSending = false;
      _prefs?.setStringList('verdict_outbox', verdictOutbox);
    }
  }

  // ---------------- ALUNO: ver o status oficial (decisão do professor) ----------------
  /// "professor:aula:tarefa" -> 'ok' | 'back'.
  final Map<String, String> verdictsByKey = {};
  bool _verdictsPulling = false;

  Verdict? verdictOf(SharedLesson l, Assignment t) => verdictFromWire(verdictsByKey['${l.teacherCode}:${l.id}:${t.id}']);

  /// Estado da tarefa para o aluno: o professor é a fonte oficial; "fiz" é só um sinal.
  StudentTaskState taskStateOf(SharedLesson l, Assignment t) =>
      studentTaskState(claimed: lessonTaskDone(l, t), verdict: verdictOf(l, t));

  Future<void> pullVerdicts() async {
    if (_verdictsPulling || !linkEnabled || linkUnavailable || myTeachers.isEmpty) return;
    _verdictsPulling = true;
    try {
      final r = await links.verdicts(profile.shareCode, profile.secret);
      if (r.unavailable) return _markLinkUnavailable();
      if (!r.ok) {
        if (r.offline) linkOnline = false;
        return;
      }
      linkOnline = true;
      var validated = 0, returned = 0;
      final next = <String, String>{};
      for (final e in r.verdicts) {
        next[e.key] = verdictWire(e.verdict);
        if (verdictsByKey[e.key] != next[e.key]) {
          e.verdict == Verdict.ok ? validated++ : returned++;
        }
        // Validada = feita; devolvida = volta a pendente (o aluno precisa refazer e marcar de novo).
        final k = '${e.lessonId}:${e.taskId}';
        e.verdict == Verdict.ok ? lessonTasksDone.add(k) : lessonTasksDone.remove(k);
      }
      verdictsByKey
        ..clear()
        ..addAll(next);
      _verdictRev = r.vr;
      _prefs?.setInt('verdict_rev', _verdictRev);
      _prefs?.setStringList('verdicts', [for (final e in verdictsByKey.entries) '${e.key}|${e.value}']);
      _saveLessons();
      notifyListeners();
      if (returned > 0) {
        final msg = returned == 1 ? tr('Seu professor devolveu 1 tarefa para refazer.') : tr('Seu professor devolveu {0} tarefas para refazer.', [returned]);
        addNotice('task', msg);
        say(msg);
      } else if (validated > 0) {
        say(validated == 1 ? tr('Seu professor validou 1 tarefa.') : tr('Seu professor validou {0} tarefas.', [validated]));
      }
    } finally {
      _verdictsPulling = false;
    }
  }

  // ---------------- Aulas ----------------
  // PROFESSOR: começa a aula na ficha do aluno, pode pausar e, ao encerrar, o que ele
  // passou nela (tarefas e observações) é enviado ao aluno. ALUNO: recebe e vê em
  // "Minhas aulas".

  ActiveLesson? _lesson;

  /// Aula em andamento (do professor), ou null. Uma aula cujo aluno foi excluído
  /// não existe mais: assim ela nunca fica "presa" bloqueando uma aula nova.
  ActiveLesson? get lesson {
    final l = _lesson;
    if (l != null && studentById(l.studentId) == null) {
      _lesson = null;
      if (activeStudentId == l.studentId) activeStudentId = null;
      _saveLessons();
    }
    return _lesson;
  }

  /// ALUNO: aulas recebidas dos professores, mais recente primeiro.
  List<SharedLesson> myLessons = [];

  /// Revisão das aulas já trazida do servidor.
  int lessonsRev = 0;

  /// ALUNO: tarefas de aula marcadas como feitas ("idAula:idTarefa").
  final Set<String> lessonTasksDone = {};

  bool _lessonSending = false;
  bool _lessonsPulling = false;

  void _loadLessons(SharedPreferences p) {
    try {
      final raw = p.getString('lesson_active');
      _lesson = raw == null ? null : ActiveLesson.tryFrom(jsonDecode(raw));
    } catch (_) {
      _lesson = null;
    }
    try {
      final raw = p.getString('lessons_in');
      myLessons = raw == null
          ? []
          : [
              for (final x in (jsonDecode(raw) as List).take(kMaxLessonKept))
                ?SharedLesson.tryFromWire(x,
                    teacherCode: formatShareCode(((x as Map)['by'] as String?) ?? '') ?? '',
                    teacherName: cleanText(x['tn'] as String?, max: kMaxName))
            ];
    } catch (_) {
      myLessons = [];
    }
    lessonsRev = p.getInt('lessons_rev') ?? 0;
    doneOutbox
      ..clear()
      ..addAll((p.getStringList('done_outbox') ?? const []).take(500));
    _doneRev = p.getInt('done_rev') ?? 0;
    _verdictRev = p.getInt('verdict_rev') ?? 0;
    verdictOutbox
      ..clear()
      ..addAll((p.getStringList('verdict_outbox') ?? const []).take(500));
    verdictsByKey
      ..clear()
      ..addEntries([
        for (final e in (p.getStringList('verdicts') ?? const []).take(2000))
          if (e.lastIndexOf('|') > 0) MapEntry(e.substring(0, e.lastIndexOf('|')), e.substring(e.lastIndexOf('|') + 1))
      ]);
    _claimLesson
      ..clear()
      ..addAll(_decodeClaimLessons(p.getString('claim_lessons')));
    lessonTasksDone
      ..clear()
      ..addAll((p.getStringList('lessons_done') ?? const []).take(2000));
  }

  void _saveLessons() {
    final p = _prefs;
    if (p == null) return;
    if (_lesson == null) {
      p.remove('lesson_active');
    } else {
      p.setString('lesson_active', jsonEncode(_lesson!.toJson()));
    }
    p.setString('lessons_in', jsonEncode([for (final l in myLessons) l.toJson()]));
    p.setInt('lessons_rev', lessonsRev);
    p.setStringList('lessons_done', lessonTasksDone.toList());
  }

  /// O aluno da aula em andamento (ou null).
  Student? get lessonStudent => lesson == null ? null : studentById(_lesson!.studentId);

  /// Começa a aula com [s]. Devolve o motivo se não der (já há outra aula em andamento).
  String? startLesson(Student s) {
    crumb(tr('Começar aula'));
    final cur = lesson;
    if (cur != null) {
      final other = studentById(cur.studentId);
      return cur.studentId == s.id
          ? tr('A aula com {0} já está em andamento.', [s.name])
          : tr('Há uma aula em andamento com {0}. Encerre-a antes de começar outra.', [other?.name ?? tr('outro aluno')]);
    }
    _lesson = ActiveLesson(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      studentId: s.id,
      startedAt: DateTime.now(),
    );
    // O aluno da aula passa a ser o "aluno em aula agora": o que ele tocar entra no histórico dele.
    activeStudentId = s.id;
    _saveTeacher();
    _saveLessons();
    notifyListeners();
    return null;
  }

  void pauseLesson() {
    _lesson?.pause(DateTime.now());
    _saveLessons();
    notifyListeners();
  }

  void resumeLesson() {
    _lesson?.resume(DateTime.now());
    _saveLessons();
    notifyListeners();
  }

  /// Descarta a aula em andamento SEM enviar nada (as tarefas já criadas continuam na ficha).
  void cancelLesson() {
    final l = _lesson;
    if (l == null) return;
    _lesson = null;
    if (activeStudentId == l.studentId) activeStudentId = null;
    _saveTeacher();
    _saveLessons();
    notifyListeners();
  }

  /// Há uma aula em andamento com este aluno?
  bool hasLessonWith(String studentId) => lesson?.studentId == studentId;

  /// Quantas tarefas e observações a aula em andamento já tem (o que será enviado).
  ({int tasks, int notes}) lessonTally() {
    final l = lesson, s = lessonStudent;
    if (l == null || s == null) return (tasks: 0, notes: 0);
    final r = buildLessonRecord(s, l, DateTime.now());
    return (tasks: r.taskCount, notes: r.noteCount);
  }

  /// Encerra a aula e a coloca para enviar ao aluno. Devolve o registro (ou null).
  LessonRecord? endLesson() {
    crumb(tr('Encerrar aula'));
    final l = lesson;
    if (l == null) return null;
    final s = studentById(l.studentId);
    final end = DateTime.now();
    _lesson = null;
    if (activeStudentId == l.studentId) activeStudentId = null; // terminou a aula: volta para o seu histórico
    _saveLessons();
    if (s == null) {
      notifyListeners();
      return null;
    }
    final rec = buildLessonRecord(s, l, end, teacherName: profile.name ?? '');
    // Aluno com código: a enviar pelo vínculo online. Sem código: fica só aqui.
    rec.sent = (s.code != null && s.linkState != 'ended') ? false : null;
    if (rec.sent == null) rec.wire = null;
    s.lessons.insert(0, rec);
    while (s.lessons.length > 200) {
      final i = s.lessons.lastIndexWhere((x) => x.sent != false);
      s.lessons.removeAt(i < 0 ? s.lessons.length - 1 : i);
    }
    // As tarefas que foram no pacote deixam de estar "a enviar" (já estão na fila de envio).
    if (rec.sent == false) _markTasksSent(s, taskIdsOf(rec));
    _saveTeacher();
    notifyListeners();
    if (rec.sent == false) unawaited(flushLessons());
    return rec;
  }

  void _markTasksSent(Student s, Set<String> ids) {
    for (var i = 0; i < s.tasks.length; i++) {
      if (ids.contains(s.tasks[i].id)) s.tasks[i] = s.tasks[i].copyWith(sent: true);
    }
  }

  /// Como uma tarefa nova chega a [s] agora (em aula, na hora, na fila ou só na ficha).
  TaskDelivery deliveryFor(Student s) => taskDeliveryFor(s,
      inLessonWithThis: hasLessonWith(s.id),
      linkOn: linkEnabled,
      serverUp: !linkUnavailable,
      studentReady: deliveryIssue[s.code] != 'not_ready');

  /// Por que o envio para um aluno está parado (código do aluno -> 'not_ready' | 'offline').
  /// Só na memória: some ao fechar o app e é refeito na próxima tentativa.
  final Map<String?, String> deliveryIssue = {};

  /// Quantas tarefas de [s] ainda esperam envio.
  int pendingTaskCount(Student s) => pendingTasks(s).length;

  /// Envia as tarefas pendentes de [s] fora de uma aula (a aula leva as suas sozinha).
  /// Devolve a mensagem para o professor.
  String sendPendingTasks(Student s) {
    final rule = deliveryFor(s);
    if (rule.mode == DeliveryMode.inLesson) {
      return tr('Há uma aula em andamento com {0}: as tarefas vão quando você encerrar a aula.', [s.name]);
    }
    if (!rule.canSend) return rule.text;
    final rec = buildTasksPackage(s, DateTime.now(), teacherName: profile.name ?? '');
    if (rec == null) return tr('Nenhuma tarefa esperando envio.');
    rec.sent = false;
    s.lessons.insert(0, rec);
    while (s.lessons.length > 200) {
      final i = s.lessons.lastIndexWhere((x) => x.sent != false);
      s.lessons.removeAt(i < 0 ? s.lessons.length - 1 : i);
    }
    _markTasksSent(s, taskIdsOf(rec));
    _saveTeacher();
    notifyListeners();
    unawaited(flushLessons());
    final n = rec.taskCount;
    final what = tr('{0} tarefa{1}', [n, n == 1 ? '' : 's']);
    return rule.mode == DeliveryMode.now ? tr('Enviando {0} para {1}…', [what, s.name]) : tr('{0} na fila de envio. {1}', [what, rule.text]);
  }

  /// Envia ao servidor as aulas encerradas que ainda não foram. Roda ao encerrar, a cada
  /// atualização do vínculo e quando o professor toca em "Enviar".
  Future<void> flushLessons() async {
    if (_lessonSending || !linkEnabled || linkUnavailable) return;
    _lessonSending = true;
    var changed = false;
    try {
      outer:
      for (final s in students) {
        final c = s.code;
        if (c == null) continue;
        if (s.linkState == 'ended') {
          // O aluno encerrou o vínculo: as aulas que esperavam envio ficam só neste aparelho.
          for (final r in s.lessons) {
            if (r.sent == false) {
              r.sent = null;
              r.wire = null;
              changed = true;
            }
          }
          continue;
        }
        if (s.linkState != 'active') continue;
        for (final r in s.lessons) {
          if (r.sent != false || r.wire == null) continue;
          final rep = await links.publishLesson(profile.shareCode, profile.secret, other: c, lesson: r.wire!);
          if (rep.ok) {
            r.sent = true;
            r.wire = null;
            changed = true;
            deliveryIssue.remove(c);
            if (_celebrateDeliveryFor == c && _celebrateAt != null && DateTime.now().difference(_celebrateAt!) < const Duration(seconds: 90)) {
              _celebrateDeliveryFor = null;
              celebrate(tr('Tarefa enviada'), detail: tr('Para {0}', [s.name]));
            } else {
              say(tr('Enviado para {0}.', [s.name]));
            }
          } else if (rep.unavailable) {
            _markLinkUnavailable();
            break outer;
          } else if (rep.offline) {
            linkOnline = false;
            deliveryIssue[c] = 'offline';
            changed = true;
            break outer;
          } else if (rep.notReady) {
            // O aluno ainda não ligou o vínculo no app dele: guarda o motivo para a ficha explicar.
            if (deliveryIssue[c] != 'not_ready') changed = true;
            deliveryIssue[c] = 'not_ready';
            continue;
          } else {
            // O servidor recusou de vez (pacote inválido): não adianta insistir.
            r.sent = null;
            r.wire = null;
            changed = true;
            fail(tr('Não foi possível enviar a aula de {0}.', [s.name]), where: tr('Aulas'), detail: rep.error);
          }
        }
      }
    } finally {
      _lessonSending = false;
      if (changed) {
        _saveTeacher();
        notifyListeners();
      }
    }
  }

  /// ALUNO: traz as aulas dos professores do servidor.
  Future<void> pullLessons({bool announce = true}) async {
    if (_lessonsPulling || !linkEnabled || linkUnavailable) return;
    _lessonsPulling = true;
    try {
      final r = await links.lessons(profile.shareCode, profile.secret);
      if (r.unavailable) return _markLinkUnavailable();
      if (!r.ok) {
        if (r.offline) linkOnline = false;
        notifyListeners();
        return;
      }
      linkOnline = true;
      final known = {for (final l in myLessons) '${l.teacherCode}:${l.id}'};
      final fresh = [for (final l in r.lessons) if (!known.contains('${l.teacherCode}:${l.id}')) l];
      final names = {for (final t in myTeachers) t.code: t.name};
      myLessons = [
        for (final l in r.lessons)
          SharedLesson(
            id: l.id,
            teacherCode: l.teacherCode,
            teacherName: l.teacherName.isNotEmpty ? l.teacherName : (names[l.teacherCode] ?? ''),
            atMs: l.atMs,
            durationSec: l.durationSec,
            tasks: l.tasks,
            notes: l.notes,
          )
      ];
      lessonsRev = r.lr;
      _saveLessons();
      notifyListeners();
      if (announce && fresh.isNotEmpty) {
        final msg = newLessonsMessage(fresh);
        addNotice('lesson', msg);
        say(msg);
      }
    } finally {
      _lessonsPulling = false;
    }
  }

  bool lessonTaskDone(SharedLesson l, Assignment t) => lessonTasksDone.contains('${l.id}:${t.id}');

  void toggleLessonTask(SharedLesson l, Assignment t) {
    final k = '${l.id}:${t.id}';
    final nowDone = !lessonTasksDone.remove(k);
    if (nowDone) lessonTasksDone.add(k);
    // Marcou de novo uma tarefa devolvida: aguarda uma nova decisão do professor.
    final vk = '${l.teacherCode}:${l.id}:${t.id}';
    if (nowDone && verdictsByKey[vk] == 'back') {
      verdictsByKey.remove(vk);
      _prefs?.setStringList('verdicts', [for (final e in verdictsByKey.entries) '${e.key}|${e.value}']);
    }
    _saveLessons();
    // Avisa o professor (ele valida): vai pela fila e reenvia sozinha se estiver sem conexão.
    if (l.teacherCode.isNotEmpty) {
      _queueDone(l.teacherCode, l.id, t.id, nowDone);
      unawaited(flushDones());
    }
    notifyListeners();
  }

  /// ALUNO: tarefas de aula ainda não feitas.
  int get openLessonTasks => myLessons.fold<int>(
      0, (a, l) => a + l.tasks.where((t) => !lessonTasksDone.contains('${l.id}:${t.id}')).length);

  void setLinkEnabled(bool v) {
    crumb(v ? tr('Ligar vínculo') : tr('Desligar vínculo'));
    linkEnabled = v;
    linkPref = v ? 'on' : 'off';
    _prefs?.setString('link_pref', linkPref!);
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
  /// [fast]: quem ainda espera um professor o adicionar (aluno sem professor) consulta a cada 10 s.
  void watchLinks({bool fast = false}) {
    _idleTicks = 0;
    _skipTicks = 0;
    _linkWatchers++;
    if (fast) _fastWatchers++;
    if (linkEnabled && !linkUnavailable) {
      unawaited(syncLinks());
      _restartLinkTimer();
    }
  }

  void unwatchLinks({bool fast = false}) {
    if (_linkWatchers > 0) _linkWatchers--;
    if (fast && _fastWatchers > 0) _fastWatchers--;
    if (_linkWatchers == 0) {
      _linkTimer?.cancel();
      _linkTimer = null;
    } else {
      _restartLinkTimer();
    }
  }

  int _fastWatchers = 0;

  void _startLinkTimer() => _restartLinkTimer();

  void _restartLinkTimer() {
    _linkTimer?.cancel();
    final secs = _fastWatchers > 0 ? 10 : 30;
    _linkTimer = Timer.periodic(Duration(seconds: secs), (_) => _linkTick());
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
    if (needsNickname) return tr('Antes de vincular, informe o seu nome em Minha conta: o professor precisa saber quem você é.');
    final problem = checkTeacherCode(code);
    if (problem != null) return problem;
    final c = formatShareCode(code)!;
    if (myTeachers.any((t) => t.code == c)) return tr('Este professor já está na sua lista.');
    myTeachers.add(LinkedPerson(c, '', 0));
    linkEnabled = true;
    _linkPrefOn();
    _saveLinks();
    notifyListeners();
    final r = await links.link(profile.shareCode, profile.secret, role: 'student', other: c, name: profile.name);
    if (r.unavailable) {
      _markLinkUnavailable();
      say(tr('O vínculo online ainda não está disponível. O professor foi registrado só neste aparelho.'));
    } else if (r.offline) {
      say(tr('Sem conexão: vou vincular com o professor assim que a internet voltar.'));
    } else if (!r.ok) {
      myTeachers.removeWhere((t) => t.code == c);
      _saveLinks();
      notifyListeners();
      return r.error ?? tr('Não foi possível vincular.');
    } else {
      linkOnline = true;
      await syncLinks();
      final t = myTeachers.where((x) => x.code == c).firstOrNull;
      say(tr('Vinculado{0}. Ele já aparece para você e você aparece para ele.', [t != null && t.name.isNotEmpty ? tr(' a {0}', [t.name]) : tr(' ao professor')]));
    }
    return null;
  }

  /// Tira um professor da sua lista (e do servidor).
  void removeMyTeacher(String code) {
    myTeachers.removeWhere((t) => t.code == code);
    myLessons.removeWhere((l) => l.teacherCode == code);
    _saveLessons();
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
      say(tr('O vínculo online ainda não está disponível. {0} ficou só neste aparelho.', [s.name]));
    } else if (r.offline) {
      s.linkState = 'pending';
      say(tr('Sem conexão: vou vincular {0} assim que a internet voltar.', [s.name]));
    } else if (!r.ok) {
      s.linkState = null;
      say(r.error ?? tr('Não foi possível vincular {0}.', [s.name]));
    } else {
      s.linkState = 'active';
      linkOnline = true;
      say(tr('{0} vinculado. Ele já vê você como professor.', [s.name]));
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
  // ---------------- Acervo e Repertório (só links; só professores liberados no servidor) ----------------
  /// Este perfil é um professor liberado para o acervo (o servidor decide: LIBRARY_TESTERS).
  bool libraryOn = false;

  /// Professores vinculados que têm acervo (para o aluno).
  Set<String> libraryTeachers = {};
  final Map<String, List<LibItem>> _libCache = {}; // código do professor (ou '' = o próprio) -> itens

  bool get libraryVisible => libraryOn || libraryTeachers.isNotEmpty;

  /// Recursos liberados para este perfil pelas chaves do painel (o servidor decide; nunca ligam sozinhos).
  Set<String> features = {};

  /// O recurso [id] está liberado para este perfil?
  bool hasFeature(String id) => features.contains(id);

  // ---------------- Tutoriais ("Comece por aqui" e tours) ----------------
  /// O cartão "Comece por aqui" foi escondido pelo professor.
  bool startCardHidden = false;
  Set<String> _toursSeen = {};

  void hideStartCard() {
    startCardHidden = true;
    _prefs?.setBool('start_hidden', true);
    notifyListeners();
  }

  /// Desfaz o "Esconder": o cartão "Comece por aqui" volta (os tutoriais já vistos continuam como estavam).
  void showStartCard() {
    startCardHidden = false;
    _prefs?.setBool('start_hidden', false);
    notifyListeners();
  }

  bool tourSeen(String id) => _toursSeen.contains(id);

  void markTourSeen(String id) {
    if (_toursSeen.add(id)) _prefs?.setStringList('tours_seen', _toursSeen.toList());
  }

  /// "Rever tutoriais": o cartão volta e os tutoriais contam como não vistos.
  void resetTutorials() {
    startCardHidden = false;
    _toursSeen = {};
    _prefs?.setBool('start_hidden', false);
    _prefs?.remove('tours_seen');
    notifyListeners();
  }

  /// Aula online (modo e link da aula) está liberada para este perfil?
  bool get onlineClassesOn => hasFeature('aula_online');

  /// O professor escolhe o lembrete de cada aula (recurso liberado pela chave `lembrete_escolha`)?
  bool get remindChoiceOn => hasFeature('lembrete_escolha');

  /// Antecedência do lembrete para aulas e horários livres NOVOS (a última escolha do professor; fica neste aparelho).
  int remindDefault = kReminderMinutes;

  void setRemindDefault(int minutes) {
    if (!kRemindOptions.contains(minutes) || minutes == remindDefault) return;
    remindDefault = minutes;
    _prefs?.setInt('remind_default', minutes);
  }

  /// Link padrão da aula online do professor: fica no aparelho (e no servidor, para horários livres sem link).
  String meetDefault = '';

  /// Guarda (ou limpa, com texto vazio) o link padrão. Devolve o motivo se não der; null se guardou.
  Future<String?> setMeetDefault(String raw) async {
    final t = raw.trim();
    final link = t.isEmpty ? '' : meetingUrl(t);
    if (link == null) return tr('Use um link https de uma sala (Meet, Zoom, Teams…).');
    meetDefault = link;
    _prefs?.setString('meet_default', link);
    notifyListeners();
    if (linkEnabled && !linkUnavailable) {
      final r = await links.meetSet(profile.shareCode, profile.secret, link);
      if (!r.ok && !r.offline) return tr('O link ficou neste aparelho, mas não foi guardado no servidor agora.');
    }
    return null;
  }

  /// Aplica DE UMA VEZ as mudanças de um plano (remarcar, trocar, pausar): se algo não couber na agenda,
  /// nada muda. Cada aluno afetado é avisado. Devolve o motivo se não der; null se aplicou.
  String? commitPlan(SlotPlan plan, {String crumbName = 'Mudar agenda'}) {
    crumb(crumbName);
    final now = DateTime.now().millisecondsSinceEpoch;
    final err = validatePlan(plan, agenda, now, nameOf: (c) => studentByCode(c)?.name ?? tr('outro aluno'));
    if (err != null) return err;
    final novas = plan.changed.where((c) => !agenda.any((x) => x.id == c.id)).length;
    if (agenda.length + novas > kMaxSlotsPerTeacher) return tr('Limite de aulas marcadas atingido. Cancele algumas antigas.');
    for (final c in plan.changed) {
      final st = studentByCode(c.studentCode);
      final i = agenda.indexWhere((x) => x.id == c.id);
      final u = i < 0 ? now : (now > agenda[i].updatedMs ? now : agenda[i].updatedMs + 1);
      final saved = c.copyWith(updatedMs: u, pending: st != null && _canSendTo(st) ? true : null);
      if (i >= 0) {
        agenda[i] = saved;
      } else {
        agenda.add(saved);
      }
    }
    _saveAgenda();
    notifyListeners();
    unawaited(flushAgenda());
    return null;
  }

  /// Troca só o link de uma aula online já marcada (professor). Devolve o motivo se não der; null se salvou.
  String? setSlotLink(String id, String raw) {
    final s = agenda.where((x) => x.id == id).firstOrNull;
    if (s == null) return tr('Aula não encontrada.');
    final t = raw.trim();
    final l = t.isEmpty ? '' : meetingUrl(t);
    if (l == null) return tr('Use um link https de uma sala (Meet, Zoom, Teams…).');
    return saveSlot(s.copyWith(mode: kModeOnline, link: l));
  }

  void _applyFeatures(LinkReply r) {
    final f = r.ff.toSet();
    var changed = false;
    if (r.ml.isNotEmpty && meetDefault.isEmpty) {
      meetDefault = r.ml; // outro aparelho do mesmo professor já guardou o link padrão
      _prefs?.setString('meet_default', r.ml);
      changed = true;
    }
    if (!(f.length == features.length && f.containsAll(features))) {
      features = f;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _applyLibraryFlags(LinkReply r) {
    final t = r.lbT.toSet();
    if (r.lb == libraryOn && t.length == libraryTeachers.length && t.containsAll(libraryTeachers)) return;
    libraryOn = r.lb;
    libraryTeachers = t;
    notifyListeners();
  }

  List<LibItem> libCached([String? teacher]) => _libCache[teacher ?? ''] ?? const [];

  /// Busca os itens (do professor [teacher], ou os próprios). Devolve null se não deu (sem internet ou sem acesso).
  Future<List<LibItem>?> libLoad({String? teacher}) async {
    final r = await links.libList(profile.shareCode, profile.secret, teacher: teacher);
    if (!r.ok) return null;
    _libCache[teacher ?? ''] = r.libItems;
    notifyListeners();
    return r.libItems;
  }

  static String _libError(LinkReply r) => switch (r.error) {
        'bad_url' => tr('Use um link https do Google Drive, Dropbox, OneDrive, IMSLP, CPDL ou YouTube.'),
        'declaration' => tr('Confirme que você tem o direito de compartilhar este material.'),
        'library_off' => tr('O acervo não está liberado para você.'),
        _ => r.offline ? tr('Sem conexão. Tente de novo.') : (r.error ?? tr('Não foi possível salvar.')),
      };

  /// Salva (cria ou muda) um item. Devolve a mensagem de erro, ou null se deu certo.
  Future<String?> libSave(LibItem it) async {
    final r = await links.libPut(profile.shareCode, profile.secret, it);
    if (!r.ok) return _libError(r);
    await libLoad();
    return null;
  }

  Future<String?> libRemove(String id) async {
    final r = await links.libDel(profile.shareCode, profile.secret, id);
    if (!r.ok) return _libError(r);
    _libCache[''] = [for (final i in libCached()) if (i.id != id) i];
    notifyListeners();
    return null;
  }

  Future<bool> libReport(String teacher, String id) async =>
      (await links.libReport(profile.shareCode, profile.secret, teacher: teacher, id: id)).ok;

  Future<void> syncLinks() async {
    if (_linkSyncing || linkUnavailable || !linkEnabled) return;
    _linkSyncing = true;
    _lastLinkSync = DateTime.now();
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
      _supportNotice(r);
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
      _applyLibraryFlags(r);
      _applyFeatures(r);
      // Aulas: o aluno busca quando o servidor avisa que há novidade; o professor envia as pendentes.
      if (r.lr != lessonsRev && myTeachers.isNotEmpty) unawaited(pullLessons());
      // Marcações de tarefa: o aluno envia as pendentes; o professor busca as novas.
      if (doneOutbox.isNotEmpty) unawaited(flushDones());
      if (students.isNotEmpty && r.dr != _doneRev) {
        unawaited(pullDones());
      } else {
        _doneRev = r.dr;
      }
      // Horários disponíveis: o professor envia os pendentes e busca o que alunos pegaram.
      if (openSlots.any((s) => s.pending == true)) unawaited(flushOpenSlots());
      if (students.isNotEmpty && r.ar != _picksRev) {
        unawaited(pullPicks());
      } else if (students.isEmpty) {
        _picksRev = r.ar;
      }
      // Decisões do professor: ele envia as pendentes; o aluno busca se mudou.
      if (verdictOutbox.isNotEmpty) unawaited(flushVerdicts());
      if (myTeachers.isNotEmpty && r.vr != _verdictRev) {
        unawaited(pullVerdicts());
      } else if (myTeachers.isEmpty) {
        _verdictRev = r.vr;
      }
      // Agenda: o professor envia as aulas marcadas pendentes; o aluno busca se mudou.
      if (agenda.any((s) => s.pending == true)) unawaited(flushAgenda());
      if (myTeachers.isNotEmpty && r.sr != _agendaRev) {
        unawaited(pullAgenda());
      } else if (myTeachers.isEmpty) {
        _agendaRev = r.sr;
      }
      _linkRev = r.kr;
      if (students.any((x) => x.lessons.any((l) => l.sent == false))) unawaited(flushLessons());
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
          name: x.name.isEmpty ? tr('Aluno {0}', [x.code]) : x.name,
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
        final auto = s.name == (s.remoteName ?? '') || isDefaultStudentName(s.name, x.code);
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
    if (lost.isNotEmpty) {
      myLessons.removeWhere((l) => lost.any((t) => t.code == l.teacherCode));
      _saveLessons();
    }
    final newTeachers = [for (final x in serverTeachers) if (!before.contains(x.code)) x];

    _saveLinks();
    _saveTeacher();
    notifyListeners();
    if (newStudents.isNotEmpty) {
      say(newStudents.length == 1
          ? tr('{0} entrou na sua lista de alunos.', [newStudents.first])
          : tr('{0} alunos novos entraram na sua lista.', [newStudents.length]));
    }
    if (newTeachers.isNotEmpty) {
      for (final t in newTeachers) {
        addNotice('teacher', tr('{0} adicionou você como aluno. Agora as aulas e tarefas dele aparecem em Minhas aulas.', [t.name.isEmpty ? tr('Um professor') : t.name]));
      }
      notifyListeners();
      final n = newTeachers.first;
      say(tr('{0} se vinculou a você.', [n.name.isEmpty ? tr('Um professor') : n.name]));
    }
    if (endedStudents.isNotEmpty) {
      say(tr('{0}: vínculo encerrado pelo aluno. O histórico ficou com você.', [endedStudents.join(', ')]));
    }
    if (lost.isNotEmpty) {
      say(tr('{0} encerrou o vínculo com você.', [lost.first.name.isEmpty ? tr('Um professor') : lost.first.name]));
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
    if (text.length > 3000000) return tr('Esse texto é grande demais para ser os dados de um aluno.');
    final imp = importStudent(text);
    if (imp == null || imp.name.isEmpty) return tr('Não consegui ler esses dados. Cole o texto exatamente como foi copiado.');
    // Mesmas regras do cadastro: nada de aluno com o seu código ou o do seu professor.
    final c = imp.code;
    if (c != null && c == profile.shareCode) {
      return tr('Esses dados têm o seu próprio código: você não pode ser aluno de si mesmo. Importação cancelada.');
    }
    // Mesmo código de um aluno já cadastrado = é a mesma pessoa: soma ao histórico dele.
    final sameCode = c == null ? null : studentByCode(c);
    final cur = studentById(imp.id) ?? sameCode;
    if (cur == null) {
      students.add(imp);
      activeStudentId ??= imp.id;
      _saveTeacher();
      notifyListeners();
      return tr('{0} adicionado com {1} sessões.', [imp.name, imp.sessions.length]);
    }
    final n = mergeSessions(cur.sessions, imp.sessions);
    _saveTeacher();
    notifyListeners();
    return tr('{0} sessões novas somadas ao histórico de {1}.', [n, cur.name]);
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
        say(tr('Sessão de {0} min concluída! Bom trabalho.', [customMinutes]));
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
            ? tr('Foco concluído! Pausa de {0} min.', [e.next == PomoPhase.longBreak ? pomo.config.longMin : pomo.config.shortMin])
            : tr('Pausa terminou. Hora de voltar ao foco.'));
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
            () => say(tr('O tempo do foco acabou enquanto o app estava fechado.')));
      }
    }
  }

  // ---------------- Avisos ----------------
  /// Quem exibe os avisos (a tela registra aqui um SnackBar).
  void Function(String message)? onMessage;

  /// Mostra um aviso curto ao usuário quando uma função é ligada/desligada.
  void say(String message) => onMessage?.call(message);

  /// Quem mostra o momento de sucesso (a tela principal liga isto).
  void Function(String title, String detail)? onSuccess;

  /// Batida bem leve ao dar certo (pegar horário, marcar aula, enviar tarefa).
  bool successHaptic = true;
  void setSuccessHaptic(bool v) {
    successHaptic = v;
    _prefs?.setBool('ok_haptic', v);
    if (v) buzz(ms: 22);
    notifyListeners();
  }

  /// Estudante cuja entrega de tarefa deve ser comemorada quando chegar de verdade ao servidor.
  String? _celebrateDeliveryFor;
  DateTime? _celebrateAt;
  void celebrateNextDelivery(String? code) {
    _celebrateDeliveryFor = code;
    _celebrateAt = DateTime.now();
  }

  /// Algo importante deu certo: mostra o momento de sucesso (e uma batida leve, se ligada).
  void celebrate(String title, {String detail = ''}) {
    if (successHaptic) buzz(ms: 22);
    final f = onSuccess;
    if (f == null) {
      say(detail.isEmpty ? title : '$title $detail');
    } else {
      f(title, detail);
    }
  }

  // ---------------- Problemas e avisos de erro ----------------
  /// Histórico dos últimos problemas (guardado no aparelho, sem dados pessoais).
  ErrorLog errorLog = ErrorLog();

  /// Quem mostra o aviso de erro na tela (a tela principal liga isto).
  void Function(AppError e)? onError;
  DateTime? _lastErrorToast;
  String _where = '';

  /// A tela/aba em que a pessoa está (vai no registro do erro).
  void markWhere(String where) => _where = where;

  // ---- Relatórios de erro (para o painel do administrador) ----
  ReportMode reportMode = ReportMode.critical;
  final Breadcrumbs crumbs = Breadcrumbs();
  final ReportGate _reportGate = ReportGate();

  void setReportMode(ReportMode m) {
    reportMode = m;
    _prefs?.setString('report_mode', m.name);
    notifyListeners();
  }

  /// Anota um passo na trilha (só nomes fixos de telas e ações).
  void crumb(String step) => crumbs.add(step);

  ReportEnv _reportEnv() => ReportEnv(
        deviceId: stats.deviceId.length >= 16 ? stats.deviceId : ErrorReportService.tempId(),
        build: StatsService.versionTag(),
        platform: StatsService.platformTag(),
        install: StatsService.installTag(),
        link: linkStatus.health.name.toLowerCase(),
        view: canSwitchHub || teacherMode || hasTeacherSide ? hubView.name : '',
      );

  /// Envia o relatório de [e] ao servidor (a pessoa tocou em "Enviar" ou o modo automático pediu).
  Future<bool> sendReport(AppError e) async {
    try {
      return await ErrorReportService.send(buildErrorReport(e, _reportEnv(), crumbs.items));
    } catch (_) {
      return false;
    }
  }

  void _autoSend(AppError e) {
    if (!shouldAutoSend(reportMode, e.severity)) return;
    if (!_reportGate.allow(e.shortId, DateTime.now())) return;
    unawaited(sendReport(e));
  }

  /// Registra um erro inesperado: classifica, guarda e (se for novo e importante) avisa.
  void reportError(Object error, StackTrace? stack, {String where = ''}) {
    try {
      _record(classifyError(error, stack: stack, where: where.isEmpty ? _where : where));
    } catch (_) {
      // registrar erro nunca pode causar outro erro
    }
  }

  /// Uma ação falhou com uma frase própria: guarda no histórico e mostra a frase com o código.
  void fail(String message, {String code = 'API-04', String where = '', String? detail}) {
    final spec = kErrorCatalog[code] ?? kErrorCatalog['APP-00']!;
    final e = AppError(
      code: spec.code,
      severity: spec.severity,
      where: sanitizeDetail(where.isEmpty ? _where : where, max: 120),
      detail: sanitizeDetail('$message\n${detail ?? ''}'),
      atMs: DateTime.now().millisecondsSinceEpoch,
    );
    errorLog.add(e);
    _prefs?.setString('error_log', errorLog.toJsonString());
    Future.microtask(notifyListeners);
    _autoSend(e);
    say('$message (${e.shortId})');
  }

  void _record(AppError e) {
    final isNew = errorLog.add(e);
    _prefs?.setString('error_log', errorLog.toJsonString());
    Future.microtask(notifyListeners); // a lista de problemas e o contador em Ajustes se atualizam
    if (isNew) _autoSend(e);
    if (!isNew || e.severity == ErrorSeverity.info) return;
    final now = DateTime.now();
    final last = _lastErrorToast;
    if (last != null && now.difference(last) < const Duration(seconds: 8)) return;
    _lastErrorToast = now;
    onError?.call(e);
  }

  void clearErrors() {
    errorLog.clear();
    _prefs?.remove('error_log');
    Future.microtask(notifyListeners);
  }

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
          ? tr('Microfone liberado')
          : tr('Microfone sem permissão. Libere nas configurações do aparelho ou do navegador.'));
    }
    notifyListeners();
    return micGranted == true;
  }

  // ---------------- Instalar no celular (aviso da tela inicial) ----------------
  /// Esconde o aviso até este instante (ms).
  int installHideUntil = 0;

  /// A pessoa já instalou (ou disse que instalou): não mostrar mais.
  bool installDone = false;

  // ---------------- Tablet deitado: duas telas lado a lado ----------------
  /// Qual tela fica à esquerda e à direita (0 Afinador, 1 Metrônomo, 2 Grade, 3 Escalas, 4 Meu espaço).
  int splitLeft = 0;
  int splitRight = 1;

  void setSplit(int left, int right) {
    splitLeft = left.clamp(0, 4);
    splitRight = right.clamp(0, 4);
    if (splitLeft == splitRight) splitRight = (splitLeft + 1) % 5;
    _prefs?.setInt('split_l2', splitLeft);
    _prefs?.setInt('split_r2', splitRight);
  }

  // ---------------- Apelido (convite da tela inicial) ----------------
  /// Esconde o convite "Como posso te chamar?" até este instante (ms).
  int nickHideUntil = 0;

  void hideNickPrompt({int days = 7}) {
    nickHideUntil = DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch;
    _prefs?.setInt('nick_hide', nickHideUntil);
    notifyListeners();
  }

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
        return tr('iPhone e iPad: a Apple não deixa sites e apps da tela inicial vibrarem. Só um app da App Store poderia.');
      }
      if (!webVibrationSupported()) {
        return tr('Este navegador ou aparelho não oferece vibração a sites. No celular Android, use o Chrome; computadores não vibram.');
      }
    }
    return tr('Este aparelho não tem motor de vibração.');
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
        ? tr('Vibração testada: você deve ter sentido duas pulsações. Se não sentiu, veja se o celular não está no modo silencioso ou economia de bateria.')
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

  /// Troca a aba da barra de baixo (0 Afinador, 1 Metrônomo, 2 Grade, 3 Escalas, 4 Meu espaço). Definido pela tela principal.
  void Function(int)? goTab;

  /// Seção pedida para a aba Grade (0 grade, 1 escala, 2 ajustes); a Grade lê e limpa ao aparecer.
  int? requestGridSection;

  /// Leva à aba Grade já na seção [section] (ex.: "Escalas" do hub abre a seção Escala).
  void openGridSection(int section) {
    if (section == 1) {
      goTab?.call(3); // a seção Escala virou a aba Escalas
    } else {
      requestGridSection = section;
      goTab?.call(2);
    }
    notifyListeners();
  }

  /// O usuário dispensou o cartão "Estuda com um professor?" da aba Estudo.
  bool roleCardHidden = false;

  void hideRoleCard() {
    roleCardHidden = true;
    _prefs?.setBool('roleCardHidden', true);
    notifyListeners();
  }

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
        ? tr('Tudo pronto: microfone liberado{0}.', [vibrationAvailable == true ? tr(' e vibração disponível') : ''])
        : tr('Microfone sem permissão. Você pode liberar depois em Configurações.'));
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
    spellingAuto = true;
    transpose = 0;
    instrumentId = 'violino';
    _gridLow = null;
    gridOctCount = 4;
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
    flashEnabled = false;
    hapticEnabled = false;
    successHaptic = true;
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
    say(tr('Configurações restauradas para o padrão'));
    notifyListeners();
  }

  // ---------------- Aparência ----------------
  ThemeMode get themeMode => themeNotifier.value;
  set themeMode(ThemeMode m) => themeNotifier.value = m;

  /// Idioma do aparelho (ex.: "en-US", "pt-BR").
  static String get deviceLangTag => PlatformDispatcher.instance.locale.toLanguageTag();

  /// Aplica a escolha ('auto' | 'pt' | 'en') e avisa as telas.
  void _applyLang() {
    final l = Lang.resolve(langPref, deviceLangTag);
    Lang.current = l;
    Lang.setRegionFrom(deviceLangTag);
    langNotifier.value = l;
    webPushSetLang(l.name);
  }

  /// Troca o idioma. Na web a página recarrega (tudo, inclusive listas guardadas na memória, nasce no idioma novo);
  /// nos outros sistemas a troca vale na hora, nas telas que se refazem.
  Future<void> setLangPref(String pref) async {
    final next = const {'pt', 'en'}.contains(pref) ? pref : 'auto';
    if (next == langPref) return;
    final before = Lang.current;
    langPref = next;
    await _prefs?.setString('lang', langPref);
    _applyLang();
    notifyListeners();
    if (Lang.current != before) reloadWebPage();
  }

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
  int gridOctCount = 4;
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

  /// Para onde vai o exercício: só subindo, só descendo ou os dois (padrão).
  ScaleDirection scaleDirection = ScaleDirection.both;
  bool scaleMode = false;

  /// Partitura (clave de Sol, 4/4) nas escalas e arpejos: ligada, como se escreve o ritmo e quando mostrar o nome das notas.
  bool scaleStaff = true;
  StaffRhythm scaleRhythm = StaffRhythm.quarter;
  StaffNames scaleNames = StaffNames.none;

  /// Dica automática do nome de uma nota muito aguda quando a pessoa demora nela (modo guiado).
  bool scaleHints = true;

  /// Notas muito agudas (de Sol6 para cima) escritas uma oitava abaixo, com o sinal 8va e o nome da nota.
  bool scaleOttava = true;

  /// Dedilhado do Flesch em cima das notas (só violino, só nas escalas que já têm tabela conferida).
  bool scaleFingers = true;

  /// A tônica é escrita na outra grafia (Sol♭ em vez de Fá♯, Ré♯ menor em vez de Mi♭ menor...), quando as duas existem.
  bool scaleAlt = false;

  /// Cor da partitura, independente do tema do app: igual ao app, sempre clara ou sempre escura.
  StaffPaper scalePaper = StaffPaper.light;

  /// "alt" que de fato vale: só quando a tônica atual tem outra grafia.
  bool get scaleAltActive => scaleAlt && scaleType != ScaleType.chromatic && !scaleType.arpeggio && ScaleSpeller.hasAlt(scaleTonicMidi, minor: scaleType.isMinor);

  /// Dedilhado da escala de agora, na ordem das notas do exercício, ou null (outro instrumento, desligado ou sem tabela).
  List<String?>? get scaleFingering => scaleFingers ? scalePlan?.fingers : null;

  /// A escala como o livro escreve (dedilhado e 8va), quando o instrumento é o violino e há tabela.
  FingeringPlan? get scalePlan {
    if (instrument.id != 'violino') return null;
    return violinFingeringPlan(tonicMidi: scaleTonicMidi, type: scaleType, octaves: scaleOctaves, direction: scaleDirection, alt: scaleAlt);
  }

  /// Corda e posição em que a escala do livro começa (só violino, escala com tabela, subindo).
  StartHint? get scaleStartHint {
    if (instrument.id != 'violino' || scaleType.arpeggio) return null;
    return violinStartHint(tonicMidi: scaleTonicMidi, type: scaleType, octaves: scaleOctaves, direction: scaleDirection, alt: scaleAlt);
  }

  /// 8va do desenho: com tabela do livro, só onde o livro usa (e se o ajuste estiver ligado); sem tabela, a regra automática.
  bool get staffOttavaAuto => scaleOttava && scalePlan == null;
  (int, int)? get staffOttavaRange => scaleOttava ? scalePlan?.ottava : null;

  /// O instrumento é o violino e esta escala tem dedilhado (para mostrar o ajuste só quando faz sentido).
  bool get hasFingeringHere => instrument.id == 'violino' && hasViolinFingering(scaleTonicMidi, scaleType, scaleOctaves, alt: scaleAlt);

  /// A nota como está escrita na escala (Lá natural ao subir e Lá♭ ao descer em Dó menor melódica), com a oitava.
  /// Com instrumento transpositor a grafia segue a regra comum (o nome já muda pela transposição).
  ({String name, int octave}) scaleNoteParts(int midi, {required bool ascending}) {
    if (cfg.transpose != 0) return (name: noteName(midi, cfg), octave: ((midi + cfg.transpose) ~/ 12) - 1);
    final s = ScaleSpeller(scaleTonicMidi, scaleType, alt: scaleAlt).spell(midi, ascending: ascending);
    return (name: s.name(), octave: s.octave);
  }

  String scaleNoteName(int midi, {required bool ascending, bool withOctave = false}) {
    final p = scaleNoteParts(midi, ascending: ascending);
    return withOctave ? '${p.name}${p.octave}' : p.name;
  }
  List<int> get scaleNotes =>
      scaleMidis(scaleTonicMidi, scaleType, octaves: scaleOctaves);

  // ---------------- Exercício de escala guiado + histórico ----------------
  ScaleExercise? exercise;
  bool exerciseDone = false;
  SessionRecord? lastSession;

  /// Histórico estruturado (da mais recente para a mais antiga).
  List<SessionRecord> sessionRecords = [];

  List<Insight> get insights =>
      analyzePractice(sessionRecords, flats: flatsForText);

  String aiSummary() =>
      buildAiPrompt(sessionRecords, instrument: instrument.name, flats: flatsForText);

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
      direction: scaleDirection,
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
          tr('{0} · {1} oitava{2}', [scaleType.display(noteName(scaleTonicMidi, cfg)), scaleOctaves, scaleOctaves > 1 ? 's' : '']),
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
      say(tr('{0}: {1}% de acerto. Salvo no histórico do aluno{2}', [student.name, (sc.accuracy * 100).round(), tasksDone > 0 ? tr(' e tarefa concluída!') : '.']));
    } else if (!demo) {
      sessionRecords.insert(0, rec);
      if (sessionRecords.length > 200) sessionRecords.removeRange(200, sessionRecords.length);
      _repo?.saveSessions(sessionRecords);
      say(tr('Exercício concluído: {0}% de acerto. Salvo no histórico.', [(sc.accuracy * 100).round()]));
    } else {
      say(tr('Fim da demonstração. Ela não entra no seu histórico.'));
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
    pedal.setVolume(v);
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
    if (pedalNotes.isNotEmpty) _applyPedal();
    // Se estiver tocando, recomeça a mesma nota no novo timbre.
    if (tone.running) tone.play(tone.frequency);
    notifyListeners();
  }
  bool get metroRunning => metroPlayer.running;
  final TapTempo _tap = TapTempo();
  bool flashEnabled = false;
  bool hapticEnabled = false;

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
    spellingAuto = p.getBool('spellAuto') ?? true;
    transpose = p.getInt('transpose') ?? 0;
    instrumentId = p.getString('instrument') ?? 'violino';
    tunerMode = TunerMode.values[(p.getInt('tunerMode') ?? 0).clamp(0, TunerMode.values.length - 1)];
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
    scaleDirection = ScaleDirection.values[(p.getInt('scale_dir') ?? ScaleDirection.both.index).clamp(0, ScaleDirection.values.length - 1)];
    scaleStaff = p.getBool('scale_staff') ?? true;
    scaleRhythm = StaffRhythm.values[(p.getInt('scale_rhythm') ?? StaffRhythm.quarter.index).clamp(0, StaffRhythm.values.length - 1)];
    scaleHints = p.getBool('scale_hints') ?? true;
    scaleOttava = p.getBool('scale_8va') ?? true;
    scaleFingers = p.getBool('scale_fingers') ?? true;
    scaleAlt = p.getBool('scale_alt') ?? false;
    scalePaper = StaffPaper.values[(p.getInt('scale_paper') ?? StaffPaper.light.index).clamp(0, StaffPaper.values.length - 1)];
    // Dedilhados que o administrador corrigiu: o último que o app recebeu vale já na abertura (e funciona sem internet).
    setViolinFingeringFromJson(p.getString('fing_json'));
    scaleNames = StaffNames.values[(p.getInt('scale_names') ?? StaffNames.none.index).clamp(0, StaffNames.values.length - 1)];
    dailyGoalMinutes = p.getDouble('goal') ?? 20;
    themeMode = ThemeMode.values[p.getInt('theme') ?? 0];
    langPref = p.getString('lang') ?? 'auto';
    _applyLang();
    outputLatencyMs = p.getDouble('latency') ?? 0;
    metroPlayer.outputLatencyMs = outputLatencyMs;
    micRationaleSeen = p.getBool('micRationale') ?? false;
    onboarded = p.getBool('onboarded') ?? false;
    roleCardHidden = p.getBool('roleCardHidden') ?? false;
    await ai.load();
    await feedback.load(p);
    await dictation.load(p);
    tone.setVolume(p.getDouble('toneVol') ?? 0.9);
    tone.timbre = ToneTimbre.values[(p.getInt('timbre') ?? 0).clamp(0, ToneTimbre.values.length - 1)];
    sensitivity = MicSensitivity.values[p.getInt('sens') ?? 1];
    micGain = p.getDouble('gain') ?? 1.0;
    flashEnabled = p.getBool('flash') ?? false;
    hapticEnabled = p.getBool('haptic') ?? false;
    successHaptic = p.getBool('ok_haptic') ?? true;
    meetDefault = p.getString('meet_default') ?? '';
    final rd = p.getInt('remind_default');
    remindDefault = rd != null && kRemindOptions.contains(rd) ? rd : kReminderMinutes;
    startCardHidden = p.getBool('start_hidden') ?? false;
    _toursSeen = (p.getStringList('tours_seen') ?? const []).toSet();
    keepAwake = p.getBool('keepAwake') ?? true;
    showFreq = p.getBool('showFreq') ?? true;
    trainerSeconds = (p.getInt('tr_sec') ?? 30).clamp(0, 600);
    trainerBars = (p.getInt('tr_bars') ?? 4).clamp(1, 32);
    trainerStep = (p.getDouble('tr_step') ?? 5).clamp(1, 20).toDouble();
    trainerUp = (p.getDouble('tr_up') ?? 40).clamp(5, 280).toDouble();
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
    stats.load(p);
    _startStats();
    cameraGranted = p.getBool('cam_granted');
    installHideUntil = p.getInt('install_hide') ?? 0;
    nickHideUntil = p.getInt('nick_hide') ?? 0;
    autoMicEnabled = p.getBool('auto_mic') ?? true;
    // Chaves novas (split_l2/r2): as antigas tinham 4 telas e o índice 3 era Meu espaço.
    splitLeft = (p.getInt('split_l2') ?? 0).clamp(0, 4);
    splitRight = (p.getInt('split_r2') ?? 1).clamp(0, 4);
    if (splitLeft == splitRight) splitRight = (splitLeft + 1) % 5;
    updateHideUntil = p.getInt('upd_hide') ?? 0;
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
    unawaited(syncFingering());
    notifyListeners();
  }

  /// Busca os dedilhados que o administrador corrigiu ou incluiu no painel: um GET por abertura (a CDN guarda a resposta por 5 minutos,
  /// então quase não toca o banco). Sem internet, com resposta estranha ou sem o servidor, segue com o que já tem.
  Future<void> syncFingering() async {
    final Uri? ep = kApiBase.isNotEmpty ? Uri.parse('$kApiBase/api/fingering') : (kIsWeb ? Uri.base.resolve('/api/fingering') : null);
    if (ep == null) return;
    try {
      final r = await http.get(ep).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200 || r.body.length > 200000) return;
      final j = jsonDecode(r.body);
      if (j is! Map || j['items'] is! List) return; // não é a resposta esperada (ex.: página de erro): não apaga o que já vale
      setViolinFingeringFromJson(r.body);
      if (_prefs?.getString('fing_json') != r.body) {
        _prefs?.setString('fing_json', r.body);
        notifyListeners();
      }
    } catch (_) {
      // sem rede: fica o que já valia
    }
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setDouble('refA', refA);
    await p.setInt('system', system.index);
    await p.setInt('tonicPc', tonicPc);
    await p.setInt('anchor', anchor.index);
    await p.setBool('flats', preferFlats);
    await p.setBool('spellAuto', spellingAuto);
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
    bool? spellingAuto,
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
    if (spellingAuto != null) this.spellingAuto = spellingAuto;
    if (transpose != null) this.transpose = transpose;
    if (instrumentId != null) {
      this.instrumentId = instrumentId;
      _gridLow = null; // volta à faixa padrão do novo instrumento
    }
    if (tunerMode != null) {
      this.tunerMode = tunerMode;
      // Sair do Pedal para o Afinador silencia o pedal (senão o microfone escutaria o próprio pedal);
      // entrar nele para o microfone e o diapasão.
      if (tunerMode != TunerMode.pedal) clearPedal();
      if (tunerMode == TunerMode.pedal) {
        if (listening) unawaited(stopListening(quiet: true));
        if (tone.running) tone.stop();
      }
    }
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
      if (pedalNotes.isNotEmpty) _applyPedal(); // o pedal acompanha o novo Lá/sistema
    }
    _save();
    notifyListeners();
  }

  // ===================================================================
  // Escuta
  // ===================================================================
  Future<void> startListening({bool demoMode = false, bool demoGlide = false, bool auto = false}) async {
    if (!auto) _autoMic = false; // o usuário assumiu o microfone
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
          tr('Sem acesso ao microfone. Permita o acesso nas configurações do aparelho ou do navegador.');
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
    if (!demoMode && hapticEnabled && !auto) buzz(ms: 30);
    if (!auto) {
      say(demoMode
          ? tr('Simulação de desenvolvimento ligada (sem som)')
          : tr('Microfone ligado. Toque uma nota!'));
    }
    notifyListeners();
  }

  /// O microfone foi ligado sozinho pelo Afinador (e não pelo usuário).
  bool _autoMic = false;

  /// Preferência: ligar o microfone sozinho ao abrir o Afinador (só depois de o usuário liberar uma vez).
  bool autoMicEnabled = true;

  void setAutoMic(bool v) {
    autoMicEnabled = v;
    _prefs?.setBool('auto_mic', v);
    if (!v) autoRelease();
    notifyListeners();
  }

  /// Liga o microfone sozinho quando o Afinador está à frente, mas só se o usuário já o liberou antes
  /// (nunca abre o pedido de permissão) e nenhum exercício está usando o som.
  Future<void> autoListen() async {
    if (!autoMicEnabled || listening || exercise != null || !micRationaleSeen) return;
    if (micGranted != true) {
      await checkMicPermission(request: false, announce: false);
      if (micGranted != true) return;
    }
    if (listening || exercise != null) return;
    _autoMic = true;
    await startListening(auto: true);
    if (!listening) _autoMic = false;
  }

  /// Ao sair do Afinador, desliga o microfone se foi ele que ligou sozinho (Grade e Escalas ligam o seu).
  Future<void> autoRelease() async {
    if (!_autoMic) return;
    _autoMic = false;
    if (listening && !demo && exercise == null) await stopListening(quiet: true);
  }

  Future<void> stopListening({bool quiet = false}) async {
    _autoMic = false;
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
  void setScale({int? tonicPc, ScaleType? type, int? octaves, bool? enabled, ScaleDirection? direction, bool? alt}) {
    // trocar só o tipo (Maior -> Menor melódica) mantém o nome da tônica que a pessoa escolheu: Lá♭ maior vira Lá♭ menor, não Sol♯ menor
    if (type != null && tonicPc == null && alt == null && type != scaleType) {
      final keep = altKeepingSpelling(scaleTonicMidi, scaleType, scaleAlt, type);
      if (keep != null && keep != scaleAlt) {
        scaleAlt = keep;
        _prefs?.setBool('scale_alt', keep);
      }
    }
    if (alt != null) {
      scaleAlt = alt;
      _prefs?.setBool('scale_alt', alt);
    }
    if (tonicPc != null) {
      final low = instrument.strings.first.midi;
      scaleTonicMidi = low + (((tonicPc - low) % 12) + 12) % 12;
    }
    if (type != null) scaleType = type;
    if (octaves != null) scaleOctaves = octaves;
    if (direction != null) {
      scaleDirection = direction;
      _prefs?.setInt('scale_dir', direction.index);
    }
    if (enabled != null) {
      scaleMode = enabled;
    }
    notifyListeners();
  }

  /// Ajustes da partitura (só mudam como ela é escrita e mostrada; o exercício toca igual).
  void setStaff({bool? on, StaffRhythm? rhythm, StaffNames? names, bool? hints, bool? ottava, bool? fingers, StaffPaper? paper}) {
    if (paper != null) {
      scalePaper = paper;
      _prefs?.setInt('scale_paper', paper.index);
    }
    if (fingers != null) {
      scaleFingers = fingers;
      _prefs?.setBool('scale_fingers', fingers);
    }
    if (ottava != null) {
      scaleOttava = ottava;
      _prefs?.setBool('scale_8va', ottava);
    }
    if (hints != null) {
      scaleHints = hints;
      _prefs?.setBool('scale_hints', hints);
    }
    if (on != null) {
      scaleStaff = on;
      _prefs?.setBool('scale_staff', on);
    }
    if (rhythm != null) {
      scaleRhythm = rhythm;
      _prefs?.setInt('scale_rhythm', rhythm.index);
    }
    if (names != null) {
      scaleNames = names;
      _prefs?.setInt('scale_names', names.index);
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
    metroBeat.value = MetroBeat(last.beat, last.bar, last.accent,
        hidden: last.hidden,
        challenge: last.challenge,
        bpm: last.bpm,
        trainerLeft: last.trainerLeft,
        trainerByTime: last.trainerByTime,
        trainerAtMax: last.trainerAtMax);
    // Várias de uma vez (o app ficou parado um instante): vibra uma vez só, no tempo mais recente.
    if (hapticEnabled && last.audible && !last.hidden) {
      buzz(ms: last.accent == Accent.strong ? 70 : 45);
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
          if (st.silences > 0) tr('o metrônomo sumiu {0} vez{1}', [st.silences, st.silences > 1 ? 'es' : '']),
          if (st.tempoChanges > 0) tr('o andamento mudou {0} vez{1}', [st.tempoChanges, st.tempoChanges > 1 ? 'es' : '']),
        ];
        say(tr('Desafio concluído: {0}. Você segurou o pulso!', [partes.join(' e ')]));
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

  // ---------------- Acelerar aos poucos ----------------
  /// Último jeito escolhido (fica no aparelho): segundos entre aumentos (0 = por compassos), compassos, quanto sobe e quanto
  /// acima do BPM de partida fica o teto. Ao ligar o treino, ele já vem pronto assim.
  int trainerSeconds = 30;
  int trainerBars = 4;
  double trainerStep = 5;
  double trainerUp = 40;

  /// O treino pronto para ligar, a partir do BPM da tela e do último jeito escolhido.
  TempoTrainer trainerForNow() => TempoTrainer(
        everyBars: trainerBars,
        everySeconds: trainerSeconds,
        stepBpm: trainerStep,
        maxBpm: (metro.bpm + trainerUp).clamp(kTrainerMinBpm, kTrainerMaxBpm).toDouble(),
      );

  /// Liga (com o último jeito escolhido), muda ou desliga ([t] nulo) o "Acelerar aos poucos".
  void setTrainer(TempoTrainer? t) {
    if (t != null) {
      trainerSeconds = t.everySeconds;
      trainerBars = t.everyBars;
      trainerStep = t.stepBpm;
      trainerUp = (t.maxBpm - metro.bpm).clamp(t.stepBpm, 280).toDouble();
      _prefs?.setInt('tr_sec', trainerSeconds);
      _prefs?.setInt('tr_bars', trainerBars);
      _prefs?.setDouble('tr_step', trainerStep);
      _prefs?.setDouble('tr_up', trainerUp);
    }
    setMetro(metro.copyWith(trainer: t));
  }

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
  DateTime? _lastUpdateCheck;
  int updateHideUntil = 0;

  /// Mostra a faixa "Versão nova disponível" (a pessoa pode adiar por algumas horas).
  bool get showUpdatePrompt => updateAvailable && DateTime.now().millisecondsSinceEpoch >= updateHideUntil;

  void hideUpdatePrompt({int hours = 6}) {
    updateHideUntil = DateTime.now().add(Duration(hours: hours)).millisecondsSinceEpoch;
    _prefs?.setInt('upd_hide', updateHideUntil);
    notifyListeners();
  }

  /// Pergunta ao servidor qual é a versão publicada (web instalada no celular
  /// costuma ficar presa na antiga). Falhas de rede são ignoradas.
  Future<void> checkForUpdate() async {
    if (!kIsWeb || kBuildId.isEmpty || kBuildId == 'local') return;
    _lastUpdateCheck = DateTime.now();
    try {
      final r = await http
          .get(Uri.base.resolve('/build-id.txt?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 8));
      final id = r.statusCode == 200 ? r.body.trim() : '';
      final newer = id.isNotEmpty && id.length < 80 && !id.contains('<') && id != kBuildId;
      if (newer && !updateAvailable) {
        updateAvailable = true;
        say(tr('Há uma versão nova do app. Toque em Atualizar no alto da tela.'));
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
    if (!ok) say(tr('Este app se atualiza pela loja de aplicativos.'));
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
