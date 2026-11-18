import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

enum GuideKind { idle, tuned, raise, lower, other, back }

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
  final String? tunedTitle;
  final String? tunedDetail;

  /// Nomes para o aviso de nota errada.
  final String Function(int midi)? noteLabel;

  /// O exercício está travado: o aluno tem de VOLTAR a uma nota antes de seguir. Enquanto ele não está nessa nota, o banner
  /// mostra este aviso fixo (em vez de "suba/desça" em relação a uma nota que não é a que importa agora).
  final String? backTitle;
  final String? backDetail;

  /// Modo calmo (escala guiada): a troca de mensagem é mais lenta e a mensagem fica mais tempo na tela, o estado de espera
  /// não usa o ícone de "ouvido" (que ficava trocando a cada pausa) e o texto tem duas linhas e mais respiro.
  final bool calm;

  /// Versão baixa e de altura fixa (a mesma em todos os estados), para a tela de exercício caber sem rolar.
  final bool compact;

  const GuidanceBanner({
    super.key,
    this.compact = false,
    required this.cents,
    required this.zone,
    this.cue,
    this.targetName,
    required this.idleTitle,
    required this.idleDetail,
    this.tunedTitle,
    this.tunedDetail,
    this.noteLabel,
    this.backTitle,
    this.backDetail,
    this.calm = false,
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
  Duration get minShow => Duration(milliseconds: widget.calm ? 2200 : 1400);
  Duration get linger => Duration(milliseconds: widget.calm ? 4500 : 3200);

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

  String _amount(double a) => a <= 12 ? tr(' um pouco') : (a <= 30 ? '' : tr(' bastante'));

  _Guide? _compute() {
    final cue = widget.cue;
    final c = widget.cents;
    final label = widget.noteLabel;
    final back = widget.backTitle != null;
    // Travado e sem a nota certa soando (silêncio ou outra nota): mostra o que fazer, em vez do desvio de uma nota que não é a alvo.
    if (back && (cue != null || c == null)) {
      return _Guide(GuideKind.back, widget.backTitle!, widget.backDetail ?? '');
    }
    if (cue != null) {
      final exp = label?.call(cue.expectedMidi) ?? '${cue.expectedMidi}';
      final heard = label?.call(cue.heardMidi) ?? '${cue.heardMidi}';
      if (!cue.inScale) {
        return _Guide(GuideKind.other, tr('NOTA FORA DA ESCALA'), tr('{0} não faz parte desta escala. Procure {1}.', [heard, exp]));
      }
      if (!cue.near) {
        return _Guide(GuideKind.other, tr('OUTRA NOTA'), tr('Você tocou {0}. Procure {1}.', [heard, exp]));
      }
      final how = cue.amount == 0 ? tr(' um pouco') : (cue.amount == 1 ? '' : tr(' bastante'));
      return _Guide(
        cue.goUp ? GuideKind.raise : GuideKind.lower,
        cue.goUp ? tr('A NOTA ESTÁ BAIXA') : tr('A NOTA ESTÁ ALTA'),
        cue.goUp ? tr('Ainda não é {0}. Suba{1}.', [exp, how]) : tr('Ainda não é {0}. Desça{1}.', [exp, how]),
      );
    }
    if (c == null) return null;
    if (c.abs() <= widget.zone) {
      return _Guide(GuideKind.tuned, widget.tunedTitle ?? tr('MUITO BEM!'), widget.tunedDetail ?? tr('Segure assim.'));
    }
    final a = c.abs();
    return c < 0
        ? _Guide(GuideKind.raise, tr('A NOTA ESTÁ BAIXA'),
            tr('Suba{0} até ficar afinada.', [_amount(a)]))
        : _Guide(GuideKind.lower, tr('A NOTA ESTÁ ALTA'),
            tr('Desça{0} até ficar afinada.', [_amount(a)]));
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
      GuideKind.back => (AppColors.sharp, Icons.undo),
      GuideKind.idle => (AppColors.textDim, widget.calm ? Icons.music_note_rounded : Icons.hearing),
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
          height: widget.compact ? (widget.calm ? 80 : 60) : (data.kind == GuideKind.idle ? 68 : 92),
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: widget.calm ? 16 : 14, vertical: widget.calm ? 8 : 0),
          decoration: BoxDecoration(
            color: color.withValues(alpha: data.kind == GuideKind.idle ? 0.08 : 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: color.withValues(alpha: data.kind == GuideKind.idle ? 0.35 : 0.9),
                width: data.kind == GuideKind.idle ? 1.2 : 2.4),
          ),
          // Ícone e textos trocam JUNTOS (mesma chave): nunca ficam defasados.
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: widget.calm ? 380 : 200),
            child: Row(
              key: ValueKey('${data.kind}-${data.title}'),
              children: [
                SizedBox(
                  width: widget.compact ? 34 : (data.kind == GuideKind.idle ? 40 : 52),
                  child: AnimatedBuilder(
                    animation: _bounce,
                    builder: (context, child) {
                      final dy = moving
                          ? (data.kind == GuideKind.raise ? -1 : 1) * 7 * _bounce.value
                          : 0.0;
                      return Transform.translate(offset: Offset(0, dy), child: child);
                    },
                    child: Icon(icon, size: widget.compact ? (data.kind == GuideKind.idle ? 20 : 30) : (data.kind == GuideKind.idle ? 26 : 44), color: data.kind == GuideKind.idle ? color.withValues(alpha: 0.7) : color),
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
                            color: data.kind == GuideKind.idle ? AppColors.textDim : color,
                            fontSize: widget.compact ? (data.kind == GuideKind.idle ? 14 : 19) : (data.kind == GuideKind.idle ? 17 : 24),
                            fontWeight: data.kind == GuideKind.idle ? FontWeight.w700 : FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      SizedBox(height: widget.calm ? 4 : 2),
                      Text(
                        data.detail,
                        maxLines: widget.compact && !widget.calm ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: data.kind == GuideKind.idle ? AppColors.textDim : AppColors.text, fontSize: widget.compact ? 12 : (data.kind == GuideKind.idle ? 13 : 14.5), height: 1.2),
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
