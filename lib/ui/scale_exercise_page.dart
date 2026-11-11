import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'guidance_banner.dart';
import 'needle.dart';
import 'note_widgets.dart';
import 'octave_colors.dart';
import 'theme.dart';
import 'transitions.dart';
import 'tuning_pick.dart';
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
          // Qual afinação está valendo (toque para trocar).
          Builder(builder: (context) => ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.straighten, size: 16, color: AppColors.accent),
                label: Text('Afinação: ${tuningSummary(app)}', style: const TextStyle(fontSize: 12.5)),
                onPressed: () => pickTuningSystem(context, app, tonicPc: app.scaleTonicMidi % 12),
              )),
          const SizedBox(height: 6),
          Row(children: [
            Text(
              e.finished
                  ? 'Concluído'
                  : (e.flow
                      ? 'Notas tocadas: ${e.board.length} de ${e.freeNotes.length}'
                      : 'Nota ${e.index + 1} de ${e.sequence.length} · ${e.ascendingNow ? 'subindo' : 'descendo'}'),
              style: TextStyle(color: AppColors.textDim),
            ),
            if (!e.finished && !e.flow) ...[
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
                      label: Text('Execução livre')),
                  ButtonSegment(
                      value: false,
                      icon: Icon(Icons.hourglass_bottom, size: 16),
                      label: Text('Guiado')),
                ],
                selected: {e.flow},
                onSelectionChanged: (v) => app.setExerciseFlow(v.first),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              e.flow
                  ? 'Toque qualquer nota da escala, em qualquer ordem: o app reconhece e valida a afinação de cada uma.'
                  : 'Uma nota por vez: a próxima só aparece quando a atual estiver afinada e segurada.',
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

  Widget _target(ScaleExercise e) => e.flow ? _freeCard(e) : _guidedCard(e);

  /// Modo guiado: uma nota por vez; a próxima só vem quando esta ficar afinada.
  Widget _guidedCard(ScaleExercise e) {
    final m = e.expected!;
    final hz = targetFreq(m, app.cfg);
    final cur = app.current;
    final onTarget = cur?.midi == m;
    final next = [
      for (var k = 1; k <= 3; k++)
        if (e.index + k < e.sequence.length) e.sequence[e.index + k]
    ];
    final status = e.tunedNow
        ? 'Afinada! Segure só mais um instante…'
        : (onTarget ? 'Quase: ajuste a afinação. A barra só enche quando estiver afinada.' : 'Aguardando a nota certa');
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          Text('Toque agora', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (c, a) => fadeThroughTransition(c, a),
            child: KeyedSubtree(
              key: ValueKey('${e.index}-$m'),
              child: NoteLabel.midi(m, app.cfg,
                  size: 84, color: e.tunedNow ? AppColors.inTune : AppColors.text),
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
                      for (final n in next) _miniNote(noteName(n, app.cfg, withOctave: true)),
                    ],
                  ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: e.holdProgress,
              backgroundColor: AppColors.surface2,
              color: AppColors.inTune,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: Center(
              child: Text(status,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                      color: e.tunedNow ? AppColors.inTune : AppColors.textDim,
                      fontSize: 12.5,
                      fontWeight: e.tunedNow ? FontWeight.w700 : FontWeight.w400)),
            ),
          ),
          const SizedBox(height: 4),
          _rule('A próxima nota só aparece quando esta estiver afinada (dentro da faixa verde) '
              'e segurada por meio segundo.'),
        ],
      ),
    );
  }

  /// Modo livre: qualquer nota da escala, em qualquer ordem.
  Widget _freeCard(ScaleExercise e) {
    final cur = app.current;
    final heard = e.currentFreeMidi;
    final pending = [for (final m in e.freeNotes) if (!e.board.containsKey(m)) m];
    final live = (cur != null && cur.midi == heard) ? cur.cents : null;
    final color = live == null ? AppColors.text : intonationColor(live, app.zoneCents);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          Text('Toque qualquer nota da escala', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 6),
          SizedBox(
            height: 92,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (c, a) => fadeThroughTransition(c, a),
                child: heard == null
                    ? Text('–',
                        key: const ValueKey('none'),
                        style: TextStyle(fontSize: 84, fontWeight: FontWeight.w800, color: AppColors.textDim))
                    : KeyedSubtree(
                        key: ValueKey('h$heard'),
                        child: NoteLabel.midi(heard, app.cfg, size: 84, color: color)),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: Center(
              child: e.allPlayed
                  ? Text('Todas as notas foram tocadas! Toque em Concluir ou refine as que ficaram fora.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.inTune, fontSize: 13, fontWeight: FontWeight.w600))
                  : Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Faltam', style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                        const SizedBox(width: 8),
                        for (final n in pending.take(4)) _miniNote(noteName(n, app.cfg, withOctave: true)),
                        if (pending.length > 4)
                          Text('+${pending.length - 4}', style: TextStyle(color: AppColors.textDim)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 4),
          _rule('Execução livre: toque as notas na ordem que quiser. Cada uma é reconhecida '
              'e a afinação é validada; notas de fora da escala são ignoradas.'),
        ],
      ),
    );
  }

  Widget _miniNote(String label) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );

  /// Linha fixa que explica a regra do modo atual.
  Widget _rule(String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.textDim),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.25))),
        ],
      );

  Widget _live(ScaleExercise e) {
    final cur = app.current;
    final zone = app.zoneCents;
    final valid = cur != null && (e.flow ? e.freeNotes.contains(cur.midi) : cur.midi == e.expected);
    final cents = valid ? cur.cents : null;
    final cue = e.cue(cur?.midi, cur?.cents ?? 0);
    final exp = e.expected;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          SmoothNeedle(cents: cents, zone: zone),
          const SizedBox(height: 6),
          GuidanceBanner(
            cents: cents,
            zone: zone,
            cue: cue,
            noteLabel: (m) => noteName(m, app.cfg, withOctave: true),
            idleTitle: e.flow ? 'TOQUE UMA NOTA' : 'TOQUE ${exp == null ? '' : noteName(exp, app.cfg, withOctave: true).toUpperCase()}',
            idleDetail: e.flow
                ? 'Qualquer nota da escala, na ordem que quiser.'
                : 'A próxima nota só vem quando esta estiver afinada.',
            tunedTitle: e.flow ? 'AFINADA!' : 'AFINADA — SEGURE',
            tunedDetail: e.flow ? 'Muito bem! Pode tocar outra nota.' : 'Segure até a barra encher.',
          ),
        ],
      ),
    );
  }

  /// Agrupa os quadradinhos por oitava: cada trecho seguido na mesma oitava vira um bloco com a
  /// cor e o nome da oitava, para a pessoa saber onde está.
  Widget _octaveBlocks(List<int> midis, Widget Function(int i, Color oc) chip) {
    final lo = midis.reduce((a, b) => a < b ? a : b);
    final n = app.scaleOctaves;
    final blocks = <(int, List<Widget>)>[];
    for (var i = 0; i < midis.length; i++) {
      final o = octaveIndex(midis[i], lo, n);
      if (blocks.isEmpty || blocks.last.$1 != o) blocks.add((o, <Widget>[]));
      blocks.last.$2.add(chip(i, octaveColor(o)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (o, chips) in blocks)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: octaveColor(o).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: octaveColor(o).withValues(alpha: 0.55)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (n > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: octaveColor(o), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(octaveName(o), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: octaveColor(o))),
                ]),
              ),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ]),
        ),
    ]);
  }

  Widget _steps(ScaleExercise e) {
    final zone = app.zoneCents;
    final cur = app.current;
    if (e.flow) {
      // Painel da escala: cada nota muda de cor conforme a última medida;
      // a que está soando agora acompanha o ponteiro ao vivo.
      return AppCard(
        padding: const EdgeInsets.all(12),
        child: _octaveBlocks(e.freeNotes, (i, oc) {
          final m = e.freeNotes[i];
          return _noteChip(
            noteName(m, app.cfg),
            (cur != null && cur.midi == m && e.currentFreeMidi == m) ? cur.cents : e.board[m]?.cents,
            current: e.currentFreeMidi == m,
            zone: zone,
            octave: oc,
          );
        }),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: _octaveBlocks(
        e.sequence,
        (i, oc) => i < e.results.length && (e.results[i].skipped || e.results[i].cents == null)
            ? _noteChip(noteName(e.sequence[i], app.cfg), null, current: false, zone: zone, skipped: true, octave: oc)
            : _noteChip(
                noteName(e.sequence[i], app.cfg),
                i < e.results.length ? e.results[i].cents : null,
                current: i == e.index && !e.finished,
                zone: zone,
                octave: oc,
              ),
      ),
    );
  }

  Widget _noteChip(String label, double? cents,
      {required bool current, required double zone, bool skipped = false, Color? octave}) {
    Color fill = AppColors.surface2;
    Color text = AppColors.textDim;
    Widget? icon;
    if (skipped) {
      icon = Icon(Icons.close, size: 14, color: AppColors.textDim);
    } else if (cents != null) {
      final leg = legibleCell(intonationColor(cents, zone));
      fill = leg.fill;
      text = leg.text;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: 40,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: current ? AppColors.accent : (octave?.withValues(alpha: 0.7) ?? Colors.transparent),
            width: current ? 2.5 : 1.5),
      ),
      child: icon ??
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: current ? FontWeight.w800 : FontWeight.w700,
                  color: current && cents == null ? AppColors.text : text)),
    );
  }

  Widget _controls(BuildContext context, ScaleExercise e) {
    return Row(
      children: [
        Expanded(
          child: e.flow
              ? FilledButton.icon(
                  onPressed: e.board.isEmpty ? null : app.finishExerciseNow,
                  icon: const Icon(Icons.flag),
                  label: const Text('Concluir'),
                )
              : OutlinedButton.icon(
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
                  child: Text(e.flow ? 'taxa de acerto' : 'acertos de primeira',
                      style: TextStyle(color: AppColors.textDim, fontSize: 15)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${sc.inTune} de ${sc.total} notas afinadas'),
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
