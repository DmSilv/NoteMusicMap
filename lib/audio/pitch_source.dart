import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import 'package:afina_core/afina_core.dart';

/// Um quadro de análise: resultado (ou null se sem nota), tempo desde o
/// quadro anterior e nível do sinal.
class PitchFrame {
  final PitchResult? result;
  final double dt;
  final double level;
  const PitchFrame(this.result, this.dt, this.level);
}

abstract class PitchSource {
  Stream<PitchFrame> get frames;
  bool get running;
  int get sampleRate;

  /// Devolve false se não houver permissão/dispositivo.
  Future<bool> start();
  Future<void> stop();

  /// Ajusta a captação: [gain] multiplica o sinal; [minClarity] e [minRms]
  /// definem o quanto o detector aceita sons menos "limpos" ou mais fracos.
  void configure({double? gain, double? minClarity, double? minRms});
}

/// Microfone real. Todo o processamento é local; nada é gravado nem enviado.
class MicPitchSource implements PitchSource {
  static const _sr = 44100;
  static const _window = 4096;
  static const _hop = 1536; // ~35 ms entre leituras (mais fluido)

  final AudioRecorder _rec = AudioRecorder();
  final StreamController<PitchFrame> _ctl = StreamController.broadcast();
  StreamSubscription<Uint8List>? _sub;
  late final McLeodPitchDetector _det =
      McLeodPitchDetector(sampleRate: _sr, windowSize: _window);

  final Float64List _ring = Float64List(_window);
  final Float64List _scratch = Float64List(_window);
  int _w = 0;
  int _filled = 0;
  int _sinceDetect = 0;
  bool _running = false;
  final Stopwatch _sw = Stopwatch();
  int _lastUs = 0;

  /// Fator de correção medido pela calibração (1.0 = sem correção).
  double correction = 1.0;

  /// Ganho de software aplicado ao sinal antes da análise.
  double _gain = 1.0;

  @override
  void configure({double? gain, double? minClarity, double? minRms}) {
    if (gain != null) _gain = gain;
    if (minClarity != null) _det.minClarity = minClarity;
    if (minRms != null) _det.minRms = minRms;
  }

  @override
  Stream<PitchFrame> get frames => _ctl.stream;
  @override
  bool get running => _running;
  @override
  int get sampleRate => _sr;

  @override
  Future<bool> start() async {
    if (_running) return true;
    if (!await _rec.hasPermission()) return false;
    final stream = await _rec.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sr,
      numChannels: 1,
      // Processamentos "inteligentes" distorcem a altura e atrasam a resposta.
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
    ));
    _filled = 0;
    _w = 0;
    _sinceDetect = 0;
    _sw
      ..reset()
      ..start();
    _lastUs = 0;
    _sub = stream.listen(_onBytes);
    _running = true;
    return true;
  }

  void _onBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final n = bytes.lengthInBytes ~/ 2;
    for (var i = 0; i < n; i++) {
      final s = (bd.getInt16(i * 2, Endian.little) / 32768.0 * _gain)
          .clamp(-1.0, 1.0);
      // anel circular: escreve e avança
      _ring[_w] = s;
      _w = (_w + 1) % _window;
      if (_filled < _window) _filled++;
      _sinceDetect++;
      if (_filled == _window && _sinceDetect >= _hop) {
        _sinceDetect = 0;
        _analyze();
      }
    }
  }

  void _analyze() {
    final now = _sw.elapsedMicroseconds;
    final dt = (now - _lastUs) / 1e6;
    _lastUs = now;
    // Linearização: a amostra mais antiga está em _w.
    for (var i = 0; i < _window; i++) {
      _scratch[i] = _ring[(_w + i) % _window];
    }
    final r = _det.detect(_scratch);
    var level = 0.0;
    for (var i = _window - 512; i < _window; i++) {
      level += _scratch[i] * _scratch[i];
    }
    level = math.sqrt(level / 512);
    final fixed = r == null
        ? null
        : PitchResult(r.frequency * correction, r.clarity, r.rms);
    if (!_ctl.isClosed) _ctl.add(PitchFrame(fixed, dt, level));
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _sub?.cancel();
    _sub = null;
    await _rec.stop();
    _sw.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _rec.dispose();
    await _ctl.close();
  }
}

/// Fonte de demonstração: sintetiza um violino tocando uma escala com pequenas
/// desafinações e passa pelo MESMO detector real. Serve para experimentar o app
/// sem instrumento e para testar a interface.
class DemoPitchSource implements PitchSource {
  static const _sr = 44100;
  static const _window = 4096;

  /// Sequência de (frequência em Hz, duração em s).
  final List<(double, double)> script;
  DemoPitchSource(this.script);

  /// Avisado quando a nota virtual muda (frequência) ou cala (null), para o app
  /// poder TOCAR o violino virtual. O microfone real nunca toca nada.
  void Function(double? freq)? onNote;
  int _lastKey = -2;

  @override
  void configure({double? gain, double? minClarity, double? minRms}) {
    if (minClarity != null) _det.minClarity = minClarity;
    if (minRms != null) _det.minRms = minRms;
  }

  final StreamController<PitchFrame> _ctl = StreamController.broadcast();
  final McLeodPitchDetector _det =
      McLeodPitchDetector(sampleRate: _sr, windowSize: _window);
  Timer? _timer;
  bool _running = false;
  double _t = 0;
  double _phase = 0;

  @override
  Stream<PitchFrame> get frames => _ctl.stream;
  @override
  bool get running => _running;
  @override
  int get sampleRate => _sr;

  @override
  Future<bool> start() async {
    if (_running) return true;
    _running = true;
    _t = 0;
    const step = 0.05;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _t += step;
      final total = script.fold<double>(0, (a, b) => a + b.$2);
      final tt = _t % total;
      var acc = 0.0;
      double f = script.first.$1;
      var local = 0.0;
      var idx = 0;
      for (var k = 0; k < script.length; k++) {
        final s = script[k];
        if (tt < acc + s.$2) {
          f = s.$1;
          local = tt - acc;
          idx = k;
          break;
        }
        acc += s.$2;
      }
      // pequeno vibrato e silêncio curto entre notas
      final gap = local < 0.12;
      final key = gap ? -1 : idx;
      if (key != _lastKey) {
        _lastKey = key;
        onNote?.call(gap ? null : f);
      }
      final buf = Float64List(_window);
      for (var i = 0; i < _window; i++) {
        final time = _t + i / _sr;
        final vib = math.pow(2, 8 * math.sin(2 * math.pi * 5.5 * time) / 1200);
        _phase += 2 * math.pi * f * vib / _sr;
        var v = 0.0;
        const amps = [1.0, 0.7, 0.5, 0.35, 0.2, 0.12];
        for (var h = 0; h < amps.length; h++) {
          v += amps[h] * math.sin((h + 1) * _phase);
        }
        buf[i] = gap ? 0 : 0.12 * v;
      }
      final r = _det.detect(buf);
      if (!_ctl.isClosed) _ctl.add(PitchFrame(r, step, gap ? 0 : 0.1));
    });
    return true;
  }

  @override
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _lastKey = -2;
    onNote?.call(null);
  }
}
