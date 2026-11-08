/// Estabilizador da nota EXIBIDA (a que fica em destaque na tela).
///
/// A grade continua registrando cada nota que o microfone ouve (as cores são
/// fiéis ao que foi tocado). Só o DESTAQUE ao vivo (nome da nota, ponteiro e
/// quadrado aceso) passa por este filtro, para trocar de nota com calma e dar
/// tempo de ler.
library;

import 'pitch_grid.dart' show TrackedNote;

/// Velocidade com que o destaque troca de uma nota para outra.
enum NoteSwitchSpeed {
  /// Acompanha quase em tempo real (para passagens rápidas).
  fast('Rápida', 'Troca logo; bom para passagens rápidas', 0.04, 0.05, 0.10),

  /// Padrão: ignora notas de passagem e deixa cada nota tempo na tela.
  normal('Normal', 'Equilibrada: dá tempo de ler cada nota', 0.10, 0.18, 0.25),

  /// Mais lenta: ideal para estudar devagar e analisar cada nota.
  calm('Calma', 'Fica mais tempo em cada nota; ideal para estudar devagar', 0.30, 0.80, 0.50);

  final String label;
  final String hint;

  /// Quanto a nota nova precisa se manter (s) antes de assumir o destaque.
  final double commit;

  /// Tempo mínimo (s) que uma nota fica em destaque antes de dar lugar à próxima.
  final double dwell;

  /// Quanto o destaque espera (s) depois que o som some, antes de apagar.
  final double release;

  const NoteSwitchSpeed(this.label, this.hint, this.commit, this.dwell, this.release);
}

/// Filtra a sequência de notas detectadas e devolve a nota a destacar.
///
///  - a PRIMEIRA nota depois do silêncio aparece na hora (o ataque é imediato);
///  - enquanto a mesma nota continua, o desvio acompanha ao vivo;
///  - uma nota DIFERENTE só assume depois de se manter por [NoteSwitchSpeed.commit]
///    e de a nota atual ter ficado ao menos [NoteSwitchSpeed.dwell] na tela.
///    Notas de passagem e tremidas rápidas não chegam a aparecer;
///  - enquanto espera, a nota atual fica parada (o desvio congela), sem pular;
///  - ao calar, o destaque espera [NoteSwitchSpeed.release] antes de apagar.
class NoteDisplayFilter {
  NoteSwitchSpeed speed;

  TrackedNote? _shown;
  double _shownSince = 0;
  int? _pending;
  double _pendingSince = 0;
  double _lastHeard = double.negativeInfinity;

  // Passagem rápida: quando o músico troca de nota várias vezes em pouco tempo
  // (semicolcheias, grupos), o filtro acelera sozinho, sem esperar o usuário
  // mudar a opção "Troca de nota".
  int? _lastRaw;
  double _rawSince = 0;
  final List<double> _changes = [];

  /// Duração mínima (s) de uma nota de meio em semitom para contar como nota
  /// (abaixo disso é um glissando passando).
  static const double realNote = 0.12;

  /// Trocas de nota (diferentes) em [fastWindow] segundos que ativam o modo rápido.
  static const int fastChanges = 2;
  static const double fastWindow = 0.8;

  NoteDisplayFilter({this.speed = NoteSwitchSpeed.normal});

  /// Nota em destaque agora (ou null).
  TrackedNote? get shown => _shown;

  /// Velocidade em uso: a escolhida, ou a rápida durante uma passagem rápida
  /// (a opção "Calma" nunca é acelerada: quem escolheu estudar devagar fica assim).
  NoteSwitchSpeed _effective(double now) {
    if (speed == NoteSwitchSpeed.calm) return speed;
    _changes.removeWhere((t) => now - t > fastWindow);
    return _changes.length >= fastChanges ? NoteSwitchSpeed.fast : speed;
  }

  void reset() {
    _shown = null;
    _pending = null;
    _shownSince = 0;
    _pendingSince = 0;
    _lastHeard = double.negativeInfinity;
    _lastRaw = null;
    _changes.clear();
  }

  /// Alimenta com a nota do quadro atual ([n] pode ser null = silêncio) no
  /// instante [now] (segundos). Devolve a nota que deve ficar em destaque.
  TrackedNote? update(TrackedNote? n, double now) {
    if (n == null) {
      final sp = _effective(now);
      if (_shown != null && now - _lastHeard >= sp.release) {
        _shown = null;
        _pending = null;
      }
      return _shown;
    }
    final prev = _lastRaw;
    if (prev == null || n.midi != prev) {
      // Conta como "troca de verdade" (e não glissando) se for um salto de 2 ou
      // mais semitons, ou se a nota anterior durou o bastante para ser uma nota.
      if (prev != null &&
          ((n.midi - prev).abs() >= 2 || now - _rawSince >= realNote)) {
        _changes.add(now);
      }
      _rawSince = now;
    }
    _lastRaw = n.midi;
    final sp = _effective(now);
    _lastHeard = now;
    final s = _shown;
    if (s == null) {
      _shown = n;
      _shownSince = now;
      _pending = null;
      return n;
    }
    if (n.midi == s.midi) {
      _shown = n; // mesma nota: desvio ao vivo
      _pending = null;
      return n;
    }
    // Outra nota: espera ela provar que é para valer.
    if (_pending != n.midi) {
      _pending = n.midi;
      _pendingSince = now;
    }
    if (now - _pendingSince >= sp.commit && now - _shownSince >= sp.dwell) {
      _shown = n;
      _shownSince = now;
      _pending = null;
    }
    return _shown;
  }
}
