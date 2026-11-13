import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';
import 'transitions.dart';

/// Seletor de oitavas: uma faixa fixa com as oitavas 0 a 8 sempre visíveis.
/// As que estão na grade ficam numa "janela" destacada. Toque num número ou
/// arraste o dedo para mover a janela; as setas movem uma oitava por vez.
class OctaveNav extends StatelessWidget {
  final AppState app;

  /// Mantido por compatibilidade; o seletor tem um só visual agora.
  final bool compact;

  /// Se informado, mostra um botão com mais opções (quantas oitavas, seguir nota).
  final VoidCallback? onMore;

  /// Mostra uma linha de ajuda sob a faixa.
  final bool showHint;

  const OctaveNav({
    super.key,
    required this.app,
    this.compact = false,
    this.onMore,
    this.showHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = app.gridOctaves;
    final canDown = lo > AppState.minOct;
    final canUp = hi < AppState.maxOct;

    Widget arrow(IconData i, String tip, VoidCallback? on) => IconButton(
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(backgroundColor: AppColors.surface2, shape: const CircleBorder()),
          icon: Icon(i, size: 22),
          onPressed: on,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            arrow(Icons.chevron_left_rounded, tr('Oitava abaixo'),
                canDown ? () => app.shiftOctaves(-1) : null),
            const SizedBox(width: 8),
            Expanded(
              child: OctaveChips(
                first: lo - 1,
                last: hi - 1,
                played: {for (final m in app.grid.playedMidis) (m ~/ 12) - 1},
                onPick: app.goToOctave,
              ),
            ),
            const SizedBox(width: 8),
            arrow(Icons.chevron_right_rounded, tr('Oitava acima'),
                canUp ? () => app.shiftOctaves(1) : null),
            if (onMore != null) ...[
              const SizedBox(width: 8),
              arrow(Icons.tune, tr('Mais opções de oitavas'), onMore),
            ],
          ],
        ),
        if (showHint)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr('Toque num número para escolher as oitavas; o pontinho marca onde você já tocou. A oitava 4 é a do Lá 440 Hz.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// Oitavas 0 a 8 como botões separados e grandes. As escolhidas (de [first] a
/// [last]) ficam preenchidas; um pontinho embaixo do número marca as oitavas em
/// que você já tocou alguma nota. Toque num número, ou arraste o dedo por cima,
/// para escolher.
class OctaveChips extends StatelessWidget {
  final int first;
  final int last;
  final Set<int> played;
  final ValueChanged<int> onPick;
  const OctaveChips({
    super.key,
    required this.first,
    required this.last,
    required this.played,
    required this.onPick,
  });

  static const int _count = 9; // oitavas 0..8

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cell = box.maxWidth / _count;

      void goTo(double dx) => onPick((dx / cell).floor().clamp(0, _count - 1));

      return Semantics(
        label: first == last
            ? tr('Oitava {0}. Toque num número para mudar.', [first])
            : tr('Oitavas {0} a {1}. Toque num número para mudar.', [first, last]),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => goTo(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => goTo(d.localPosition.dx),
          child: SizedBox(
            height: 48,
            child: Stack(children: [
              // trilho com as nove oitavas
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14)),
                ),
              ),
              // a "janela" das oitavas que aparecem na grade (desliza ao mudar)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                left: first * cell + 3,
                width: (last - first + 1) * cell - 6,
                top: 4,
                bottom: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppColors.accent, width: 1.5),
                  ),
                ),
              ),
              Row(children: [
                for (var label = 0; label < _count; label++) Expanded(child: _num(label)),
              ]),
            ]),
          ),
        ),
      );
    });
  }

  Widget _num(int label) {
    final on = label >= first && label <= last;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$label',
          style: TextStyle(
            fontSize: 15,
            height: 1.0,
            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
            color: on ? AppColors.text : AppColors.textDim,
          ),
        ),
        const SizedBox(height: 4),
        // Pontinho = já tocou nessa oitava; "Lá" marca a oitava do Lá 440 Hz.
        SizedBox(
          height: 8,
          child: played.contains(label)
              ? Container(width: 5, height: 5, decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle))
              : (label == 4 ? Text(tr('Lá'), style: TextStyle(fontSize: 9, height: 1.0, color: AppColors.textDim)) : null),
        ),
      ],
    );
  }
}

/// Legenda de cores e o que fazer para corrigir.
class IntonationLegend extends StatelessWidget {
  final double zone;
  final bool compact;
  const IntonationLegend({super.key, required this.zone, this.compact = false});

  @override
  Widget build(BuildContext context) {
    const range = 30.0;
    final colors = [for (var c = -range; c <= range; c += 3) intonationColor(c, zone)];
    final z = (zone / range).clamp(0.0, 1.0);

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), gradient: LinearGradient(colors: colors)),
            ),
          ),
          const SizedBox(height: Ds.s8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _legendWord(Icons.arrow_upward_rounded, tr('Grave: suba'), AppColors.flat),
            _legendWord(Icons.check_circle_rounded, tr('Afinado'), AppColors.inTune),
            _legendWord(Icons.arrow_downward_rounded, tr('Agudo: desça'), AppColors.sharp, iconAfter: true),
          ]),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 14,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return Stack(children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: LinearGradient(colors: colors),
                  ),
                ),
              ),
              // zona "afinada"
              Positioned(
                left: w / 2 - w / 2 * z,
                width: w * z,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.text.withValues(alpha: 0.85), width: 1.5),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ]);
          }),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendTag(
              icon: Icons.arrow_upward,
              color: AppColors.flat,
              title: tr('Grave'),
              sub: compact ? tr('suba') : tr('afinação baixa: suba'),
            ),
            const SizedBox(width: 6),
            _LegendTag(
              icon: Icons.check_circle,
              color: AppColors.inTune,
              title: tr('Afinado'),
              sub: compact ? tr('faixa verde') : tr('dentro da faixa verde'),
            ),
            const SizedBox(width: 6),
            _LegendTag(
              icon: Icons.arrow_downward,
              color: AppColors.sharp,
              title: tr('Agudo'),
              sub: compact ? tr('desça') : tr('afinação alta: desça'),
            ),
          ],
        ),
        if (!compact)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              tr('A cor mostra a distância do som ideal. Quanto mais forte a cor, mais longe você está.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

Widget _legendWord(IconData icon, String text, Color color, {bool iconAfter = false}) {
  final t = Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13));
  final i = Icon(icon, size: 16, color: color);
  return Row(mainAxisSize: MainAxisSize.min, children: [
    if (!iconAfter) ...[i, const SizedBox(width: 4)],
    t,
    if (iconAfter) ...[const SizedBox(width: 4), i],
  ]);
}

class _LegendTag extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? sub;
  const _LegendTag({required this.icon, required this.color, required this.title, this.sub});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
                  if (sub != null)
                    Text(sub!,
                        style: TextStyle(color: AppColors.text, fontSize: 11, height: 1.2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// Dica de correção para a nota atual: "Grave −2,1 Hz · suba um pouco".
///
/// O número exibido DESLIZA até o valor medido (suavização por quadro) em vez
/// de piscar a cada leitura do microfone, e a cor e a direção (suba/desça)
/// seguem esse valor suave, então a dica não fica "tremendo" na fronteira da
/// zona afinada. Ocupa sempre a mesma altura.
class CorrectionHint extends StatefulWidget {
  final double? cents;

  /// Frequência ideal da nota (Hz), para mostrar o desvio em Hz.
  final double? target;
  final double zone;
  const CorrectionHint({super.key, required this.cents, required this.zone, this.target});

  @override
  State<CorrectionHint> createState() => _CorrectionHintState();
}

class _CorrectionHintState extends State<CorrectionHint> with SingleTickerProviderStateMixin {
  static const double _tau = 0.2; // s: constante de tempo do número exibido (acima de 1 ciclo de vibrato)

  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  Duration _last = Duration.zero;
  double _v = 0; // desvio exibido (suavizado)

  @override
  void initState() {
    super.initState();
    _v = widget.cents ?? 0;
  }

  @override
  void didUpdateWidget(CorrectionHint old) {
    super.didUpdateWidget(old);
    final c = widget.cents;
    if (c == null) return;
    if (old.cents == null) {
      _v = c; // nota nova depois do silêncio: aparece já no valor certo
    } else if ((c - _v).abs() > 0.05 && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    final c = widget.cents;
    if (c == null) {
      _ticker.stop();
      return;
    }
    _v += (c - _v) * (1 - math.exp(-dt / _tau));
    if ((c - _v).abs() <= 0.05) {
      _v = c;
      _ticker.stop();
    }
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repaint,
      builder: (context, _) {
        final has = widget.cents != null;
        final zone = widget.zone;
        final c = _v;
        String text;
        IconData icon;
        Color color;
        if (!has) {
          text = tr('Toque uma nota');
          icon = Icons.hearing;
          color = AppColors.textDim;
        } else if (c.abs() <= zone) {
          text = tr('Afinada');
          icon = Icons.check_circle;
          color = AppColors.inTune;
        } else {
          final a = c.abs();
          final how = a <= zone * 2.5 ? tr('um pouco') : (a <= zone * 6 ? '' : tr('bastante'));
          final dir = c < 0 ? tr('suba') : tr('desça');
          final off = widget.target == null ? '' : ' ${fmtHz(hzOff(c, widget.target!))}';
          text = '${c < 0 ? tr('Grave') : tr('Aguda')}$off · $dir ${how.isEmpty ? '' : how}'.trim();
          icon = c < 0 ? Icons.arrow_upward : Icons.arrow_downward;
          color = intonationColor(c, zone);
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          // Quem sai some depressa e quem entra só aparece depois: os dois
          // textos nunca ficam um em cima do outro.
          transitionBuilder: (child, animation) =>
              fadeThroughTransition(child, animation, scaleFrom: 0.97),
          child: Row(
            // só troca com animação quando muda a direção, não a cada cent
            key: ValueKey(icon.codePoint),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        );
      },
    );
  }
}

/// Placar leve da sessão: total de notas tocadas e % afinadas. Toque para abrir
/// o resumo por nota.
class SessionChips extends StatelessWidget {
  final AppState app;
  const SessionChips({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final s = app.grid.summary(app.gridZoneCents);
    final pct = (s.accuracy * 100).round();
    Widget chip(String big, String small, {Color? color}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(big,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: color ?? AppColors.text)),
              const SizedBox(width: 5),
              Text(small, style: TextStyle(fontSize: 12.5, color: AppColors.textDim)),
            ],
          ),
        );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: s.distinct == 0 ? null : () => showSessionSheet(context, app),
      child: Semantics(
        button: true,
        label: s.distinct == 0
            ? tr('Nenhuma nota tocada ainda')
            : tr('{0} notas tocadas, {1} por cento afinadas. Toque para ver por nota.', [s.notes, pct]),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip('${s.notes}', s.notes == 1 ? tr('nota') : tr('notas')),
            const SizedBox(width: 8),
            chip(s.distinct == 0 ? '—' : '$pct%', tr('afinadas'),
                color: s.distinct == 0 ? null : (pct >= 70 ? AppColors.inTune : null)),
            if (s.distinct > 0) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
            ],
          ],
        ),
      ),
    );
  }
}

/// Resumo leve da sessão: uma linha por nota tocada (da mais grave à mais aguda),
/// com a cor, quantas vezes foi tocada e o desvio médio em Hz.
void showSessionSheet(BuildContext context, AppState app) {
  final zone = app.gridZoneCents;
  final s = app.grid.summary(zone);
  // Ignora a retenção: a folha mostra tudo que foi tocado na sessão.
  final saved = app.grid.holdSeconds;
  app.grid.holdSeconds = null;
  final midis = app.grid.playedMidis.toList()..sort();
  final rows = <(int, CellView)>[
    for (final m in midis)
      if (app.grid.view(m, app.now) case final v?) (m, v)
  ];
  app.grid.holdSeconds = saved;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(tr('Sessão'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            tr('{0} {1} · {2} de {3} diferentes afinadas ({4}%)', [s.notes, s.notes == 1 ? tr('nota tocada') : tr('notas tocadas'), s.inTune, s.distinct, (s.accuracy * 100).round()]),
            style: TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          for (final (m, v) in rows) _sessionRow(app, m, v, zone),
          const SizedBox(height: 12),
          Text(
            tr('Cada nota mostra a média de tudo que você tocou nela. Para recomeçar, use o botão "Zerar" (ao lado do microfone).'),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ],
      ),
    ),
  );
}

Widget _sessionRow(AppState app, int midi, CellView v, double zone) {
  final c = v.avgCents;
  final inTune = c.abs() <= zone;
  final color = inTune ? AppColors.inTune : intonationColor(c, zone);
  final word = inTune ? tr('afinada') : (c < 0 ? tr('grave') : tr('aguda'));
  final hz = fmtHz(hzOff(c, targetFreq(midi, app.cfg)));
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: intonationColor(c, zone), shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 62,
          child: Text(noteName(midi, app.cfg, withOctave: true),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        SizedBox(
          width: 40,
          child: Text(tr('×{0}', [v.plays]), style: TextStyle(color: AppColors.textDim)),
        ),
        Expanded(child: Text(word, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        Text(inTune ? '' : hz,
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

/// Modal com as opções extras de oitavas: quantas mostrar e seguir a nota.
void showOctaveSheet(BuildContext context, AppState app) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Oitavas na grade'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Text(tr('Quantas oitavas mostrar: {0}', [app.gridOctCount]),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                min: 2,
                max: 7,
                divisions: 5,
                value: app.gridOctCount.toDouble(),
                onChanged: (v) => app.setOctCount(v.round()),
              ),
              Text(tr('Menos oitavas = quadrados maiores e mais fáceis de ler.'),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Seguir a nota que eu toco')),
                subtitle: Text(tr('A grade muda de oitava sozinha quando você sobe ou desce.')),
                value: app.gridFollow,
                onChanged: app.setFollow,
              ),
              const SizedBox(height: 4),
              Text(tr('Atalhos: toque no número da oitava (Dó4 é a oitava do Lá 440 Hz).'),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Pergunta antes de apagar as cores acumuladas da grade.
Future<void> confirmResetGrid(BuildContext context, AppState app) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Zerar a grade?')),
      content: Text(
          tr('As cores acumuladas das notas serão apagadas. Seu tempo de estudo e as escalas salvas não mudam.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Zerar'))),
      ],
    ),
  );
  if (ok == true) {
    app.resetGrid();
  }
}
