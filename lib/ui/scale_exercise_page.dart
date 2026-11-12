import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'design_system.dart';
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
      tr('{0} · {1} oitava{2}', [app.scaleType.display(noteName(app.scaleTonicMidi, app.cfg)), app.scaleOctaves, app.scaleOctaves > 1 ? 's' : '']);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Escala guiada')),
        actions: [
          IconButton(tooltip: tr('Ajustes do exercício'), icon: const Icon(Icons.tune), onPressed: () => _openSettings(context)),
          const SizedBox(width: Ds.s4),
        ],
        leading: IconButton(
          tooltip: tr('Encerrar exercício'),
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
                if (!app.listening) _needMic(context) else if (!e.finished) ...[
                  _target(e),
                  const SizedBox(height: 10),
                  _live(e),
                ],
                if (e.finished) _result(context, e),
                const SizedBox(height: 14),
                _header(e),
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

  /// Linha enxuta no topo: o que está sendo feito e quanto falta. O resto fica nos Ajustes.
  Widget _header(ScaleExercise e) {
    final status = e.finished
        ? tr('Concluído')
        : (e.flow
            ? tr('{0} de {1} notas', [e.board.length, e.freeNotes.length])
            : tr('Nota {0} de {1} · {2}', [e.index + 1, e.sequence.length, e.ascendingNow ? tr('subindo') : tr('descendo')]));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Ds.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          Text(status, style: Ds.support()),
        ]),
        const SizedBox(height: Ds.s8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: e.finished ? 1 : e.progress,
            backgroundColor: AppColors.surface2,
            color: AppColors.accent,
          ),
        ),
      ]),
    );
  }

  /// Ajustes do exercício (modal): afinação e jeito de tocar.
  void _openSettings(BuildContext context) {
    showDsSheet(
      context,
      title: tr('Ajustes do exercício'),
      listenable: Listenable.merge([app, app.live]),
      children: (c) {
        final e = app.exercise;
        return [
          DsSettingRow(
            label: tr('Jeito de tocar'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: true, icon: Icon(Icons.shuffle_rounded, size: 18), label: Text(tr('Livre'))),
                    ButtonSegment(value: false, icon: Icon(Icons.format_list_numbered_rounded, size: 18), label: Text(tr('Guiado'))),
                  ],
                  selected: {e?.flow ?? true},
                  onSelectionChanged: (v) => app.setExerciseFlow(v.first),
                ),
              ),
              const DsGap(Ds.s8),
              Text((e?.flow ?? true) ? tr('Toque as notas na ordem que quiser.') : tr('Uma nota de cada vez, na ordem.'), style: Ds.support()),
            ]),
          ),
          DsSettingRow(
            label: tr('Afinação'),
            child: OutlinedButton.icon(
              onPressed: () => pickTuningSystem(c, app, tonicPc: app.scaleTonicMidi % 12),
              icon: const Icon(Icons.straighten, size: 20),
              label: Text(tuningSummary(app)),
            ),
          ),
        ];
      },
    );
  }

  Widget _needMic(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Text(tr('Deixe o app ouvir seu instrumento'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(tr('O som fica no aparelho e não é gravado.'), textAlign: TextAlign.center, style: Ds.support()),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
            onPressed: () => app.startListening(),
            icon: const Icon(Icons.mic, size: 20),
            label: Text(tr('Ouvir meu instrumento'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (kDevDemo) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => app.startExercise(demoMode: true),
              icon: const Icon(Icons.play_circle_outline),
              label: Text(tr('[dev] Simular (silencioso)')),
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
        ? tr('Afinada! Segure só mais um instante…')
        : (onTarget ? tr('Quase: ajuste a afinação. A barra só enche quando estiver afinada.') : tr('Aguardando a nota certa'));
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          Text(tr('Toque agora'), style: TextStyle(color: AppColors.textDim, fontSize: 13)),
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
                      Text(tr('Depois'), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
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
          Text(tr('Sua vez!'), style: TextStyle(color: AppColors.textDim, fontSize: 13)),
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
                  ? Text(tr('Todas as notas foram tocadas! Toque em Concluir ou refine as que ficaram fora.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.inTune, fontSize: 13, fontWeight: FontWeight.w600))
                  : Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(tr('Faltam'), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                        const SizedBox(width: 8),
                        for (final n in pending.take(4)) _miniNote(noteName(n, app.cfg, withOctave: true)),
                        if (pending.length > 4)
                          Text('+${pending.length - 4}', style: TextStyle(color: AppColors.textDim)),
                      ],
                    ),
            ),
          ),
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
            idleTitle: e.flow ? tr('TOQUE UMA NOTA') : 'TOQUE ${exp == null ? '' : noteName(exp, app.cfg, withOctave: true).toUpperCase()}',
            idleDetail: e.flow ? tr('Qualquer uma da escala!') : tr('Afine para liberar a próxima.'),
            tunedTitle: e.flow ? tr('AFINADA!') : tr('AFINADA — SEGURE'),
            tunedDetail: e.flow ? tr('Muito bem! Pode tocar outra nota.') : tr('Segure até a barra encher.'),
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
    if (n == 1) return Wrap(spacing: 6, runSpacing: 6, children: [for (var i = 0; i < midis.length; i++) chip(i, octaveColor(0))]);
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
            color: octaveColor(o).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: octaveColor(o).withValues(alpha: 0.16)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (n > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: octaveColor(o).withValues(alpha: 0.6), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(octaveName(o), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDim)),
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
            color: current ? AppColors.accent : Colors.transparent,
            width: current ? 2.5 : 1),
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
                  label: Text(tr('Concluir')),
                )
              : OutlinedButton.icon(
                  onPressed: app.skipExerciseNote,
                  icon: const Icon(Icons.skip_next),
                  label: Text(tr('Pular nota')),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => app.startExercise(demoMode: app.demo),
            icon: const Icon(Icons.restart_alt),
            label: Text(tr('Recomeçar')),
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
                  child: Text(e.flow ? tr('taxa de acerto') : tr('acertos de primeira'),
                      style: TextStyle(color: AppColors.textDim, fontSize: 15)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(tr('{0} de {1} notas afinadas', [sc.inTune, sc.total])),
          if (app.demo)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('Era uma demonstração: ela não entra no seu histórico.'),
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            ),
          if (tips.isNotEmpty) ...[
            const Divider(height: 24),
            Text(tr('Orientações do treinador'), style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final t in tips) InsightTile(insight: t),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => app.startExercise(demoMode: app.demo),
                icon: const Icon(Icons.replay),
                label: Text(tr('Repetir')),
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
                label: Text(tr('Concluir')),
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
  app.say(tr('Resumo copiado. Cole numa IA de sua escolha e peça orientações.'));
}
