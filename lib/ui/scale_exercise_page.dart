import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'grid_widgets.dart';
import 'needle.dart';
import 'note_widgets.dart';
import 'theme.dart';
import 'transitions.dart';
import 'widgets.dart';

/// Exercício de escala guiado: o app mostra a próxima nota, acompanha a
/// afinação de cada uma e, no fim, dá a pontuação e orientações.
class ScaleExercisePage extends StatelessWidget {
  final AppState app;
  const ScaleExercisePage({super.key, required this.app});

  String get _title =>
      '${app.scaleType.display(noteName(app.scaleTonicMidi, app.cfg))} · '
      '${app.scaleOctaves} oitava${app.scaleOctaves > 1 ? 's' : ''}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escala guiada'),
        leading: IconButton(
          tooltip: 'Encerrar exercício',
          icon: const Icon(Icons.close),
          onPressed: () {
            app.stopExercise();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: app.live,
          builder: (context, _) {
            final e = app.exercise;
            if (e == null) return const SizedBox.shrink();
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              children: [
                _header(e),
                const SizedBox(height: 10),
                if (!app.listening) _needMic(context) else if (!e.finished) ...[
                  _target(e),
                  const SizedBox(height: 10),
                  _live(e),
                ],
                if (e.finished) _result(context, e),
                const SizedBox(height: 10),
                _steps(e),
                const SizedBox(height: 10),
                if (!e.finished) _controls(context, e),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(ScaleExercise e) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(children: [
            Text(
              e.finished
                  ? 'Concluído'
                  : 'Nota ${e.index + 1} de ${e.sequence.length} · ${e.ascendingNow ? 'subindo' : 'descendo'}',
              style: TextStyle(color: AppColors.textDim),
            ),
            if (!e.finished) ...[
              const SizedBox(width: 6),
              Icon(e.ascendingNow ? Icons.north_east : Icons.south_east,
                  size: 16, color: AppColors.textDim),
            ],
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: e.finished ? 1 : e.progress,
              backgroundColor: AppColors.surface2,
              color: AppColors.accent,
            ),
          ),
          if (!e.finished) ...[
            const SizedBox(height: 12),
            // Como o app acompanha: no seu ritmo (sem esperar) ou esperando cada nota.
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                segments: const [
                  ButtonSegment(
                      value: true,
                      icon: Icon(Icons.play_arrow, size: 18),
                      label: Text('Seguir meu ritmo')),
                  ButtonSegment(
                      value: false,
                      icon: Icon(Icons.hourglass_bottom, size: 16),
                      label: Text('Esperar cada nota')),
                ],
                selected: {e.flow},
                onSelectionChanged: (v) => app.setExerciseFlow(v.first),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              e.flow
                  ? 'Toque a escala sem parar: o app acompanha e mede cada nota, sem pedir para segurar.'
                  : 'O app espera você segurar cada nota até a barra encher antes de seguir.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _needMic(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          const Icon(Icons.mic_none, size: 40),
          const SizedBox(height: 8),
          const Text('Para começar, deixe o app ouvir seu instrumento.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('O som é analisado no aparelho e não é gravado.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => app.startListening(),
            icon: const Icon(Icons.mic),
            label: const Text('Ouvir meu instrumento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (kDevDemo) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => app.startExercise(demoMode: true),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('[dev] Simular (silencioso)'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _target(ScaleExercise e) {
    final m = e.expected!;
    final hz = targetFreq(m, app.cfg);
    final cur = app.current;
    final onTarget = cur?.midi == m;
    // Prévia das próximas notas: no modo contínuo dá para tocar olhando adiante.
    final next = [
      for (var k = 1; k <= 3; k++)
        if (e.index + k < e.sequence.length) e.sequence[e.index + k]
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        children: [
          Text('Toque agora', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (c, a) => fadeThroughTransition(c, a),
            child: KeyedSubtree(
              key: ValueKey('${e.index}-$m'),
              child: NoteLabel.midi(m, app.cfg, size: 84, color: onTarget ? AppColors.inTune : AppColors.text),
            ),
          ),
          const SizedBox(height: 4),
          Text('${hz.toStringAsFixed(2)} Hz', style: TextStyle(color: AppColors.textDim)),
          // Altura fixa: perto do fim a prévia tem menos notas, sem mexer na tela.
          SizedBox(
            height: 38,
            child: next.isEmpty
                ? null
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Depois', style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                      const SizedBox(width: 8),
                      for (final n in next)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(noteName(n, app.cfg, withOctave: true),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 6),
          if (e.flow)
            _flowStatus(e, onTarget)
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: e.holdProgress,
                backgroundColor: AppColors.surface2,
                color: AppColors.inTune,
              ),
            ),
            const SizedBox(height: 4),
            Text(onTarget ? 'Segure a nota…' : 'Aguardando a nota certa',
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  /// Estado do modo "seguir meu ritmo": um ponto que acende quando o app está
  /// ouvindo a nota certa (no lugar da barra de segurar).
  Widget _flowStatus(ScaleExercise e, bool onTarget) {
    final hearing = e.hearing || onTarget;
    final color = hearing ? AppColors.inTune : AppColors.textDim;
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hearing ? color : Colors.transparent,
              border: Border.all(color: color, width: 1.8),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            hearing ? 'Ouvindo… pode seguir para a próxima' : 'Aguardando a nota certa',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _live(ScaleExercise e) {
    final cur = app.current;
    final zone = app.zone.cents;
    final onTarget = cur?.midi == e.expected;
    final cue = e.cue(cur?.midi, cur?.cents ?? 0);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          SmoothNeedle(cents: onTarget ? cur?.cents : null, zone: zone),
          // Uma linha só, de altura fixa: a dica de afinação (nota certa) ou o
          // aviso leve (nota ainda não é a certa) trocam de lugar com fade, sem
          // empurrar a tela.
          SizedBox(
            height: 44,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: cue != null
                    ? KeyedSubtree(key: const ValueKey('cue'), child: _cueLine(cue))
                    : KeyedSubtree(
                        key: const ValueKey('hint'),
                        child: CorrectionHint(cents: onTarget ? cur?.cents : null, zone: zone),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Aviso leve: "Ainda não é Lá3: suba um pouco" (azul = grave, laranja = agudo).
  Widget _cueLine(NoteCue? cue) {
    if (cue == null) return const Text(' ');
    final exp = noteName(cue.expectedMidi, app.cfg, withOctave: true);
    final heard = noteName(cue.heardMidi, app.cfg, withOctave: true);
    if (!cue.near) {
      return Text(
        cue.inScale ? 'Você está em $heard; procure $exp.' : '$heard não é da escala; procure $exp.',
        textAlign: TextAlign.center,
        maxLines: 2,
        style: TextStyle(color: AppColors.textDim, fontSize: 13),
      );
    }
    final how = switch (cue.amount) { 0 => ' um pouco', 1 => '', _ => ' bastante' };
    final color = cue.goUp ? AppColors.flat : AppColors.sharp;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(cue.goUp ? Icons.arrow_upward : Icons.arrow_downward, size: 18, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Ainda não é $exp: ${cue.goUp ? 'suba' : 'desça'}$how',
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _steps(ScaleExercise e) {
    final zone = app.zone.cents;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < e.sequence.length; i++)
            _stepChip(
              noteName(e.sequence[i], app.cfg),
              i < e.results.length ? e.results[i] : null,
              current: i == e.index && !e.finished,
              zone: zone,
            ),
        ],
      ),
    );
  }

  Widget _stepChip(String label, StepResult? r, {required bool current, required double zone}) {
    Color fill = AppColors.surface2;
    Color text = AppColors.textDim;
    Widget? icon;
    if (r != null) {
      if (r.skipped || r.cents == null) {
        icon = Icon(Icons.close, size: 14, color: AppColors.textDim);
      } else {
        final leg = legibleCell(intonationColor(r.cents!, zone));
        fill = leg.fill;
        text = leg.text;
      }
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: 38,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: current ? AppColors.accent : Colors.transparent, width: current ? 2.5 : 1),
      ),
      child: icon ??
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: current ? FontWeight.w800 : FontWeight.w700,
                  color: current ? AppColors.text : text)),
    );
  }

  Widget _controls(BuildContext context, ScaleExercise e) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: app.skipExerciseNote,
            icon: const Icon(Icons.skip_next),
            label: const Text('Pular nota'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => app.startExercise(demoMode: app.demo),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Recomeçar'),
          ),
        ),
      ],
    );
  }

  Widget _result(BuildContext context, ScaleExercise e) {
    final sc = e.score;
    final pct = (sc.accuracy * 100).round();
    final good = pct >= 80;
    final color = good ? AppColors.inTune : (pct >= 50 ? AppColors.flat : AppColors.sharp);
    final tips = app.demo ? const <Insight>[] : app.insights.take(3).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$pct%',
                  style: TextStyle(fontSize: 56, fontWeight: FontWeight.w800, height: 1.0, color: color)),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('taxa de acerto',
                      style: TextStyle(color: AppColors.textDim, fontSize: 15)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${sc.inTune} de ${sc.total} notas afinadas (tolerância ±${app.zone.cents.round()})'),
          Text('Desvio médio: ${sc.meanAbsCents.toStringAsFixed(1)}',
              style: TextStyle(color: AppColors.textDim)),
          if (app.demo)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Era uma demonstração: ela não entra no seu histórico.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            ),
          if (tips.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('Orientações do treinador', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final t in tips) InsightTile(insight: t),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => app.startExercise(demoMode: app.demo),
                icon: const Icon(Icons.replay),
                label: const Text('Repetir'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  app.stopExercise();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.check),
                label: const Text('Concluir'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Uma orientação do treinador, com ícone e cor pelo tipo.
class InsightTile extends StatelessWidget {
  final Insight insight;
  const InsightTile({super.key, required this.insight});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (insight.kind) {
      InsightKind.warn => (Icons.priority_high, AppColors.sharp),
      InsightKind.tip => (Icons.lightbulb_outline, AppColors.flat),
      InsightKind.good => (Icons.emoji_events_outlined, AppColors.inTune),
      InsightKind.info => (Icons.info_outline, AppColors.textDim),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(insight.text, style: const TextStyle(height: 1.3))),
        ],
      ),
    );
  }
}

/// Copia o resumo para a área de transferência (para colar numa IA).
Future<void> copyAiSummary(AppState app) async {
  await Clipboard.setData(ClipboardData(text: app.aiSummary()));
  app.say('Resumo copiado. Cole numa IA de sua escolha e peça orientações.');
}
