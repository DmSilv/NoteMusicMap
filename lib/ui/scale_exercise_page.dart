import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'grid_widgets.dart';
import 'needle.dart';
import 'note_widgets.dart';
import 'theme.dart';
import 'widgets.dart';

/// Exercício de escala guiado: o app mostra a próxima nota, acompanha a
/// afinação de cada uma e, no fim, dá a pontuação e orientações.
class ScaleExercisePage extends StatelessWidget {
  final AppState app;
  const ScaleExercisePage({super.key, required this.app});

  String get _title =>
      '${noteName(app.scaleTonicMidi, app.cfg)} ${app.scaleType.label.toLowerCase()} · '
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
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        children: [
          Text('Toque agora', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: c),
            ),
            child: KeyedSubtree(
              key: ValueKey('${e.index}-$m'),
              child: NoteLabel.midi(m, app.cfg, size: 84, color: onTarget ? AppColors.inTune : AppColors.text),
            ),
          ),
          const SizedBox(height: 4),
          Text('${hz.toStringAsFixed(2)} Hz', style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 12),
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
      ),
    );
  }

  Widget _live(ScaleExercise e) {
    final cur = app.current;
    final zone = app.zone.cents;
    final onTarget = cur?.midi == e.expected;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          SmoothNeedle(cents: onTarget ? cur?.cents : null, zone: zone),
          CorrectionHint(cents: onTarget ? cur?.cents : null, zone: zone),
          // Espaço reservado: a linha aparece/some só com opacidade, sem empurrar a tela.
          SizedBox(
            height: 40,
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: (cur != null && !onTarget) ? 1 : 0,
                child: Text(
                  cur == null
                      ? ' '
                      : 'Você está em ${noteName(cur.midi, app.cfg, withOctave: true)}; procure ${noteName(e.expected!, app.cfg, withOctave: true)}.',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(color: AppColors.textDim, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
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
