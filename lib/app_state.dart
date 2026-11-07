import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:record/record.dart' show AudioRecorder;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'audio/audio_out.dart';
import 'audio/pitch_source.dart';
import 'package:afina_core/afina_core.dart';

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
    final wasIdle = pomo.phase == PomoPhase.idle;
    pomo.start(_nowMs);
    _runPomoTimer();
    _wake(true);
    say(wasIdle
        ? 'Foco iniciado: ${pomo.config.focusMin} min. Bons estudos!'
        : 'Timer retomado');
    _savePomo();
    notifyListeners();
  }

  void pomoPause() {
    pomo.pause(_nowMs);
    _pomoTimer?.cancel();
    _pomoTimer = null;
    _wake(listening || metroRunning);
    say('Timer pausado');
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
    say('Timer zerado');
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
    notifyListeners();
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
        if (pomoVibrate) HapticFeedback.mediumImpact();
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
  Future<bool> checkMicPermission() async {
    final r = AudioRecorder();
    try {
      micGranted = await r.hasPermission();
    } catch (_) {
      micGranted = false;
    } finally {
      await r.dispose();
    }
    say(micGranted == true
        ? 'Microfone liberado'
        : 'Microfone sem permissão. Libere nas configurações do aparelho ou do navegador.');
    notifyListeners();
    return micGranted == true;
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
    say(switch (m) {
      ThemeMode.system => 'Tema automático: segue o seu celular',
      ThemeMode.light => 'Tema claro',
      ThemeMode.dark => 'Tema escuro',
    });
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
  ThemeMode themeMode = ThemeMode.system;

  void cycleTheme() {
    const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    themeMode = order[(order.indexOf(themeMode) + 1) % order.length];
    say(switch (themeMode) {
      ThemeMode.system => 'Tema automático: segue o seu celular',
      ThemeMode.light => 'Tema claro',
      ThemeMode.dark => 'Tema escuro',
    });
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
    say(v ? 'A grade vai seguir a nota que você toca' : 'Seguir nota desligado');
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
    if (sensitivity != null && sensitivity != this.sensitivity) {
      say(switch (sensitivity) {
        MicSensitivity.rigorous => 'Captação rigorosa: só notas limpas e fortes',
        MicSensitivity.normal => 'Captação normal',
        MicSensitivity.free =>
          'Captação livre: pega sons fracos e ruído; pode errar a oitava',
      });
    }
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

  // ---------------- Metrônomo ----------------
  MetronomeConfig metro = MetronomeConfig.signature(4, bpm: 100);
  final MetronomePlayer metroPlayer = MetronomePlayer();
  final TonePlayer tone = TonePlayer();
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
    dailyGoalMinutes = p.getDouble('goal') ?? 20;
    themeMode = ThemeMode.values[p.getInt('theme') ?? 0];
    outputLatencyMs = p.getDouble('latency') ?? 0;
    metroPlayer.outputLatencyMs = outputLatencyMs;
    micRationaleSeen = p.getBool('micRationale') ?? false;
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
    _loadPomo(p);
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
      if (system != this.system) {
        say(switch (system) {
          TuningSystem.equal => 'Afinação igual (piano, violão)',
          TuningSystem.pythagorean => 'Afinação pitagórica: ideal para melodias',
          TuningSystem.just => 'Entonação justa: ideal para acordes',
        });
      }
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
  Future<void> startListening({bool demoMode = false}) async {
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
    final src = demoMode ? DemoPitchSource(_demoScript()) : MicPitchSource();
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
    say(demoMode
        ? 'Demonstração ligada: um violino virtual toca uma escala'
        : 'Microfone ligado. Toque uma nota!');
    notifyListeners();
  }

  Future<void> stopListening({bool quiet = false}) async {
    final wasDemo = demo;
    final wasOn = listening;
    await _sub?.cancel();
    _sub = null;
    await _source?.stop();
    _source = null;
    listening = false;
    current = null;
    level = 0;
    tracker.reset();
    _wake(metroRunning);
    if (!quiet && wasOn) say(wasDemo ? 'Demonstração parada' : 'Microfone desligado');
    notifyListeners();
  }

  void _onFrame(PitchFrame f) {
    level = f.level;
    final n = tracker.update(f.result, cfg);
    current = n;
    if (n != null) {
      grid.add(n.midi, n.cents, n.clarity, f.dt, now);
      _lastNoteSeen = now;
      if (gridFollow) _followNote(n.midi);
    }
    // Limita a taxa de redesenho (~30 fps) para poupar bateria.
    final t = DateTime.now();
    if (t.difference(_lastNotify).inMilliseconds >= 33) {
      _lastNotify = t;
      notifyListeners();
    }
  }

  /// Escala de demonstração: Sol maior no violino, com desafinações reais.
  List<(double, double)> _demoScript() {
    final c = TuningConfig(
        refA: refA, system: system, tonicPc: tonicPc, anchor: anchor);
    double f(int midi, double cents) =>
        targetFreq(midi, c) * math.pow(2, cents / 1200).toDouble();
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
      if (enabled != scaleMode) {
        say(enabled
            ? 'Exercício de escala ligado: toque as notas marcadas na grade'
            : 'Exercício de escala desligado');
      }
      scaleMode = enabled;
    }
    notifyListeners();
  }

  void resetGrid() {
    grid.clear();
    tracker.reset();
    current = null;
  }

  // ===================================================================
  // Metrônomo
  // ===================================================================
  Future<void> toggleMetronome() async {
    if (metroPlayer.running) {
      await metroPlayer.stop();
      _wake(listening);
      say('Metrônomo parado');
    } else {
      await metroPlayer.start(metro);
      _wake(true);
      say('Metrônomo ligado · ${metro.bpm.round()} BPM');
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
          '${noteName(scaleTonicMidi, cfg)} ${scaleType.label.toLowerCase()}',
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

  Future<void> clearHistory() async {
    studySeconds.clear();
    scaleSessions.clear();
    await _prefs?.remove('study');
    await _prefs?.remove('sessions');
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
    _studyTimer?.cancel();
    _saveStudy();
    super.dispose();
  }
}
