import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
import 'audio/pitch_source.dart';
import 'package:afina_core/afina_core.dart';

/// Ativa a simulação de execução (sem som), só para testes: --dart-define=DEV_DEMO=true.
const bool kDevDemo = bool.fromEnvironment('DEV_DEMO');

enum TunerMode { strings, chromatic }

/// Quão permissivo é o microfone.
/// rigorous: só notas limpas e fortes. free: aceita sons fracos, com ar,
/// vibrato forte ou ruído de fundo (pode errar mais a oitava).
enum MicSensitivity {
  rigorous('Rigoroso', 0.88, 0.006, 3),
  normal('Normal', 0.80, 0.003, 2),
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
  ZoneLevel zone = ZoneLevel.intermediate;
  HistoryMode history = HistoryMode.medium;
  double holdSeconds = 30;

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

  // ---------------- Vibração ----------------
  /// null = ainda não verificado.
  bool? vibrationAvailable;

  Future<bool> checkVibration() async {
    try {
      vibrationAvailable = await Vibration.hasVibrator();
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
      vibrationAvailable ??= await Vibration.hasVibrator();
      if (vibrationAvailable == true) {
        if (pattern != null) {
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
        ? 'Vibração testada: você deve ter sentido duas pulsações'
        : 'Este aparelho/navegador não tem vibração. O app segue funcionando sem ela.');
  }

  // ---------------- Primeiro uso ----------------
  /// Análise por IA do treinador (opcional, via Vercel).
  final CoachAi ai = CoachAi();

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
    gridOctCount = 4;
    gridFollow = false;
    tunerMode = TunerMode.strings;
    zone = ZoneLevel.intermediate;
    history = HistoryMode.medium;
    holdSeconds = 30;
    noteSwitch = NoteSwitchSpeed.normal;
    _display.speed = noteSwitch;
    exerciseFlow = true;
    grid.history = history;
    grid.holdSeconds = holdSeconds;
    dailyGoalMinutes = 20;
    flashEnabled = true;
    hapticEnabled = true;
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
  int gridOctCount = 4;
  bool gridFollow = false;

  /// Faixa [baixa, alta] de oitavas visíveis (inclusive).
  (int, int) get gridOctaves {
    final lo = (_gridLow ?? instrument.strings.first.midi ~/ 12)
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
      zone: zone.cents,
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
    final rec = SessionRecord(
      date: DateTime.now(),
      title:
          '${scaleType.display(noteName(scaleTonicMidi, cfg))} · $scaleOctaves oitava${scaleOctaves > 1 ? 's' : ''}',
      octaves: scaleOctaves,
      zone: zone.cents,
      accuracy: sc.accuracy,
      meanAbsCents: sc.meanAbsCents,
      steps: [
        for (final r in e.results)
          StepRecord(r.midi, r.ascending, r.octaveIndex, r.skipped ? null : r.cents)
      ],
    );
    lastSession = rec;
    // No modo demonstração não se guarda histórico (não é a execução do músico).
    if (!demo) {
      sessionRecords.insert(0, rec);
      if (sessionRecords.length > 200) sessionRecords.removeRange(200, sessionRecords.length);
      _prefs?.setString('sessions2', jsonEncode([for (final r in sessionRecords) r.toJson()]));
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
    zone = ZoneLevel.values[p.getInt('zone') ?? 1];
    history = HistoryMode.values[p.getInt('history') ?? 1];
    holdSeconds = p.getDouble('hold') ?? 30;
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
    tone.timbre = ToneTimbre.values[(p.getInt('timbre') ?? 0).clamp(0, ToneTimbre.values.length - 1)];
    sensitivity = MicSensitivity.values[p.getInt('sens') ?? 1];
    micGain = p.getDouble('gain') ?? 1.0;
    flashEnabled = p.getBool('flash') ?? true;
    hapticEnabled = p.getBool('haptic') ?? true;
    final bpm = p.getDouble('bpm') ?? 100;
    final beats = p.getInt('beats') ?? 4;
    final sub = p.getInt('sub') ?? 1;
    metro = MetronomeConfig.signature(beats,
        bpm: bpm,
        subdivision: sub,
        sound: ClickSound.values[p.getInt('sound') ?? 0],
        groupSize: beats == 6 ? 3 : (beats == 7 ? 2 : null));
    final sd = p.getString('study');
    if (sd != null) {
      studySeconds = (jsonDecode(sd) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    final ss = p.getString('sessions');
    if (ss != null) {
      scaleSessions = (jsonDecode(ss) as List).cast<Map<String, dynamic>>();
    }
    final s2 = p.getString('sessions2');
    if (s2 != null) {
      sessionRecords = [
        for (final j in (jsonDecode(s2) as List))
          ?SessionRecord.tryFromJson((j as Map).cast<String, dynamic>())
      ];
    }
    _loadPomo(p);
    // Mostra o estado real das permissões sem abrir nenhum pedido do sistema.
    if (onboarded) {
      checkMicPermission(request: false, announce: false);
      checkVibration();
    }
    grid = PitchGrid(history: history, holdSeconds: holdSeconds);
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
    await p.setInt('zone', zone.index);
    await p.setInt('history', history.index);
    await p.setDouble('hold', holdSeconds);
    await p.setInt('noteSwitch', noteSwitch.index);
    await p.setBool('exFlow', exerciseFlow);
    await p.setDouble('goal', dailyGoalMinutes);
    await p.setBool('flash', flashEnabled);
    await p.setBool('haptic', hapticEnabled);
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
    ZoneLevel? zone,
    HistoryMode? history,
    double? holdSeconds,
    double? dailyGoalMinutes,
    bool? flashEnabled,
    bool? hapticEnabled,
  }) {
    if (refA != null) this.refA = refA.clamp(400.0, 480.0);
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
    if (zone != null) this.zone = zone;
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
    if (!demoMode) buzz(ms: 30);
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
    final n = tracker.update(f.result, cfg);
    current = n;
    shown = _display.update(n, now);
    if (n != null) {
      grid.add(n.midi, n.cents, n.clarity, f.dt, now);
      _lastNoteSeen = now;
    }
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
    tracker.reset();
    current = null;
    shown = null;
    _display.reset();
    liveTick.value++;
  }

  // ===================================================================
  // Metrônomo
  // ===================================================================
  Future<void> toggleMetronome() async {
    if (metroPlayer.running) {
      await metroPlayer.stop();
      _wake(listening);
    } else {
      await metroPlayer.start(metro);
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
        silent: metro.silent));
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
    final active = metroPlayer.running || (listening && !demo && now - _lastNoteSeen < 3);
    if (!active) return;
    final k = dayKey(DateTime.now());
    studySeconds[k] = (studySeconds[k] ?? 0) + 1;
    if (DateTime.now().second % 15 == 0) _saveStudy();
  }

  Future<void> _saveStudy() async {
    await _prefs?.setString('study', jsonEncode(studySeconds));
  }

  double get todaySeconds => studySeconds[dayKey(DateTime.now())] ?? 0;

  ScaleReport buildReport() => buildScaleReport(grid, scaleNotes, cfg, zone, now);

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
    final p = _prefs ?? await SharedPreferences.getInstance();
    await p.clear();
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

  Future<void> clearHistory() async {
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
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    ai.dispose();
    _studyTimer?.cancel();
    _saveStudy();
    super.dispose();
  }
}
