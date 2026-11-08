import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

enum GuideKind { idle, tuned, raise, lower, other }

/// Banner de orientação do exercício: GRANDE, colorido e que NÃO some
/// depressa. Diz claramente o que fazer (SUBA / DESÇA / AFINADA) e quanto falta.
///
///  - a orientação fica pelo menos [minShow] na tela antes de trocar (evita
///    piscar com a oscilação natural da afinação); chegar na faixa afinada
///    aparece na hora;
///  - se o som para, a última orientação continua visível, esmaecida, por
///    [linger] antes de voltar ao "toque a nota".
class GuidanceBanner extends StatefulWidget {
  /// Desvio (cents) da nota que o músico toca em relação ao ALVO dela; null se
  /// nenhuma nota válida está soando.
  final double? cents;
  final double zone;

  /// Aviso de nota errada (modo guiado) ou fora da escala (modo livre).
  final NoteCue? cue;

  /// Nome da nota alvo, para o texto ("Toque Lá3").
  final String? targetName;

  /// Texto do estado de espera.
  final String idleTitle;
  final String idleDetail;

  /// Texto do estado afinado.
  final String tunedTitle;
  final String tunedDetail;

  /// Nomes para o aviso de nota errada.
  final String Function(int midi)? noteLabel;

  const GuidanceBanner({
    super.key,
    required this.cents,
    required this.zone,
    this.cue,
    this.targetName,
    required this.idleTitle,
    required this.idleDetail,
    this.tunedTitle = 'AFINADA!',
    this.tunedDetail = 'Segure assim.',
    this.noteLabel,
  });

  @override
  State<GuidanceBanner> createState() => _GuidanceBannerState();
}

class _Guide {
  final GuideKind kind;
  final String title;
  final String detail;
  const _Guide(this.kind, this.title, this.detail);
}

class _GuidanceBannerState extends State<GuidanceBanner> with SingleTickerProviderStateMixin {
  static const Duration minShow = Duration(milliseconds: 1400);
  static const Duration linger = Duration(milliseconds: 3200);

  late final AnimationController _bounce =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  _Guide? _shown;
  DateTime _shownAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _heardAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  String _amount(double a) => a <= 12 ? ' um pouco' : (a <= 30 ? '' : ' bastante');

  _Guide? _compute() {
    final cue = widget.cue;
    final c = widget.cents;
    final label = widget.noteLabel;
    if (cue != null) {
      final exp = label?.call(cue.expectedMidi) ?? '${cue.expectedMidi}';
      final heard = label?.call(cue.heardMidi) ?? '${cue.heardMidi}';
      if (!cue.inScale) {
        return _Guide(GuideKind.other, 'FORA DA ESCALA', '$heard não é desta escala. Procure $exp.');
      }
      if (!cue.near) {
        return _Guide(GuideKind.other, 'OUTRA NOTA', 'Você está em $heard. Procure $exp.');
      }
      final how = cue.amount == 0 ? ' um pouco' : (cue.amount == 1 ? '' : ' bastante');
      return _Guide(
        cue.goUp ? GuideKind.raise : GuideKind.lower,
        cue.goUp ? 'SUBA A AFINAÇÃO' : 'DESÇA A AFINAÇÃO',
        'Ainda não é $exp: ${cue.goUp ? 'suba' : 'desça'}$how.',
      );
    }
    if (c == null) return null;
    if (c.abs() <= widget.zone) {
      return _Guide(GuideKind.tuned, widget.tunedTitle, widget.tunedDetail);
    }
    final a = c.abs();
    return c < 0
        ? _Guide(GuideKind.raise, 'SUBA A AFINAÇÃO',
            'Está abaixo da nota: suba${_amount(a)}.')
        : _Guide(GuideKind.lower, 'DESÇA A AFINAÇÃO',
            'Está acima da nota: desça${_amount(a)}.');
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final g = _compute();
    if (g != null) {
      _heardAt = now;
      final s = _shown;
      final farOut = widget.cents != null && widget.cents!.abs() > widget.zone * 1.8;
      final canSwitch = s == null ||
          g.kind == s.kind ||
          g.kind == GuideKind.tuned ||
          now.difference(_shownAt) >= minShow ||
          (s.kind == GuideKind.tuned && farOut);
      if (canSwitch) {
        if (s == null || g.kind != s.kind) _shownAt = now;
        _shown = g;
      }
    } else if (_shown != null && now.difference(_heardAt) > linger) {
      _shown = null;
    }

    final shown = _shown;
    final stale = shown != null && now.difference(_heardAt) > const Duration(milliseconds: 500);
    final data = shown ??
        _Guide(GuideKind.idle, widget.idleTitle, widget.idleDetail);

    final (color, icon) = switch (data.kind) {
      GuideKind.tuned => (AppColors.inTune, Icons.check_circle),
      GuideKind.raise => (AppColors.flat, Icons.arrow_upward),
      GuideKind.lower => (AppColors.sharp, Icons.arrow_downward),
      GuideKind.other => (AppColors.textDim, Icons.help_outline),
      GuideKind.idle => (AppColors.textDim, Icons.hearing),
    };
    final moving = data.kind == GuideKind.raise || data.kind == GuideKind.lower;

    return Semantics(
      liveRegion: true,
      label: '${data.title}. ${data.detail}',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: stale ? 0.6 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          height: 96,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: data.kind == GuideKind.idle ? 0.08 : 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: color.withValues(alpha: data.kind == GuideKind.idle ? 0.35 : 0.9),
                width: data.kind == GuideKind.idle ? 1.2 : 2.4),
          ),
          // Ícone e textos trocam JUNTOS (mesma chave): nunca ficam defasados.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Row(
              key: ValueKey('${data.kind}-${data.title}'),
              children: [
                SizedBox(
                  width: 56,
                  child: AnimatedBuilder(
                    animation: _bounce,
                    builder: (context, child) {
                      final dy = moving
                          ? (data.kind == GuideKind.raise ? -1 : 1) * 7 * _bounce.value
                          : 0.0;
                      return Transform.translate(offset: Offset(0, dy), child: child);
                    },
                    child: Icon(icon, size: 48, color: color),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          data.title,
                          maxLines: 1,
                          style: TextStyle(
                            color: data.kind == GuideKind.idle ? AppColors.text : color,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stale && data.kind != GuideKind.idle
                            ? 'Última orientação: ${data.detail}'
                            : data.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.text, fontSize: 14.5, height: 1.2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
