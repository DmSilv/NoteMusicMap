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
                  const SizedBox(height: 8),
                  _live(e),
                ],
                if (e.finished) _result(context, e),
                const SizedBox(height: 10),
                _header(e),
                const SizedBox(height: 8),
                _scaleMap(e),
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
            label: tr('Direção'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: double.infinity, child: directionPicker(app, onChanged: () => app.startExercise(demoMode: app.demo))),
              const DsGap(Ds.s8),
              Text(tr('Muda a ordem das notas e recomeça o exercício.'), style: Ds.support()),
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

  /// Esta nota aparece na SUBIDA da escala? (só as notas da descida, como o Si♭ da menor melódica, levam o nome de descida.)
  bool _ascOf(ScaleExercise e, int m) {
    for (var i = 0; i < e.sequence.length; i++) {
      if (e.sequence[i] == m && e.ascendingAt(i)) return true;
    }
    return false;
  }

  /// Nome da nota como está escrito na escala (Si♭ ao descer, Si natural ao subir) e a oitava, para o rótulo grande.
  Widget _bigNote(int midi, {required bool asc, required double size, required Color color}) {
    final p = app.scaleNoteParts(midi, ascending: asc);
    return NoteLabel(name: p.name, octave: p.octave, size: size, color: color);
  }

  /// Etiqueta "▲ Subindo" / "▼ Descendo": o músico sempre sabe para onde a escala vai.
  Widget _dirTag(bool asc) {
    final color = asc ? AppColors.flat : AppColors.sharp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16, color: color),
        const SizedBox(width: 4),
        Text(asc ? tr('subindo') : tr('descendo'), style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  /// Modo guiado: uma nota por vez; a próxima só vem quando esta ficar afinada.
  Widget _guidedCard(ScaleExercise e) {
    final m = e.expected!;
    final asc = e.ascendingAt(e.index);
    final hz = targetFreq(m, app.cfg);
    final cur = app.current;
    final onTarget = cur?.midi == m;
    final next = [
      for (var k = 1; k <= 3; k++)
        if (e.index + k < e.sequence.length) (e.sequence[e.index + k], e.ascendingAt(e.index + k))
    ];
    final status = e.tunedNow
        ? tr('Afinada! Segure só mais um instante…')
        : (onTarget ? tr('Quase: ajuste a afinação. A barra só enche quando estiver afinada.') : tr('Aguardando a nota certa'));
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          Row(children: [
            Text(tr('Toque agora'), style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const Spacer(),
            Text('${hz.toStringAsFixed(1)} Hz', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const SizedBox(width: Ds.s8),
            _dirTag(asc),
          ]),
          SizedBox(
            height: 76,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (c, a) => fadeThroughTransition(c, a),
                child: KeyedSubtree(
                  key: ValueKey('${e.index}-$m'),
                  child: _bigNote(m, asc: asc, size: 66, color: e.tunedNow ? AppColors.inTune : AppColors.text),
                ),
              ),
            ),
          ),
          // Altura fixa: perto do fim a prévia tem menos notas, sem mexer na tela.
          SizedBox(
            height: 30,
            child: next.isEmpty
                ? null
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(tr('Depois'), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                      const SizedBox(width: 8),
                      for (final n in next) _miniNote(app.scaleNoteName(n.$1, ascending: n.$2, withOctave: true)),
                    ],
                  ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: e.holdProgress,
              backgroundColor: AppColors.surface2,
              color: AppColors.inTune,
            ),
          ),
          SizedBox(
            height: 28,
            child: Center(
              child: Text(status,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          Row(children: [
            Text(tr('Sua vez!'), style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const Spacer(),
            Text(tr('{0} de {1} notas', [e.board.length, e.freeNotes.length]), style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          ]),
          SizedBox(
            height: 76,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (c, a) => fadeThroughTransition(c, a),
                child: heard == null
                    ? Text('–',
                        key: const ValueKey('none'),
                        style: TextStyle(fontSize: 60, fontWeight: FontWeight.w800, color: AppColors.textDim))
                    : KeyedSubtree(key: ValueKey('h$heard'), child: _bigNote(heard, asc: _ascOf(e, heard), size: 66, color: color)),
              ),
            ),
          ),
          SizedBox(
            height: 30,
            child: Center(
              child: e.allPlayed
                  ? Text(tr('Todas as notas foram tocadas! Toque em Concluir ou refine as que ficaram fora.'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(color: AppColors.inTune, fontSize: 12.5, fontWeight: FontWeight.w600))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(tr('Faltam'), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                        const SizedBox(width: 8),
                        for (final n in pending.take(4)) _miniNote(app.scaleNoteName(n, ascending: _ascOf(e, n), withOctave: true)),
                        if (pending.length > 4) Text('+${pending.length - 4}', style: TextStyle(color: AppColors.textDim)),
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
    final asc = e.flow ? (e.currentFreeMidi == null ? e.direction != ScaleDirection.down : _ascOf(e, e.currentFreeMidi!)) : e.ascendingNow;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        children: [
          SmoothNeedle(cents: cents, zone: zone),
          const SizedBox(height: 4),
          GuidanceBanner(
            compact: true,
            cents: cents,
            zone: zone,
            cue: cue,
            noteLabel: (m) => app.scaleNoteName(m, ascending: _ascOf(e, m) || (!e.flow && asc), withOctave: true),
            idleTitle: e.flow ? tr('TOQUE UMA NOTA') : tr('TOQUE {0}', [exp == null ? '' : app.scaleNoteName(exp, ascending: asc, withOctave: true).toUpperCase()]),
            idleDetail: e.flow ? tr('Qualquer uma da escala!') : tr('Afine para liberar a próxima.'),
            tunedTitle: e.flow ? tr('AFINADA!') : tr('AFINADA — SEGURE'),
            tunedDetail: e.flow ? tr('Muito bem! Pode tocar outra nota.') : tr('Segure até a barra encher.'),
          ),
        ],
      ),
    );
  }

  /// MAPA DA ESCALA: uma linha por oitava, com o nome da primeira nota ("Sol3") e todas as notas dela, cada
  /// uma com o número da oitava. Fica sempre inteiro na tela (sem rolar) para o músico saber onde está.
  Widget _scaleMap(ScaleExercise e) {
    final zone = app.zoneCents;
    final cur = app.current;
    final n = app.scaleOctaves;
    final notes = e.freeNotes; // distintas, do grave ao agudo
    final lo = notes.first;
    final rows = <int, List<int>>{};
    for (final m in notes) {
      rows.putIfAbsent(octaveIndex(m, lo, n), () => []).add(m);
    }
    // Notas só da descida (ex.: Si♭ da menor melódica) pedem o nome de descida.
    bool ascOf(int m) => _ascOf(e, m);
    // Último resultado de cada nota (guiado).
    final last = <int, StepResult>{};
    if (!e.flow) {
      for (final r in e.results) {
        last[r.midi] = r;
      }
    }
    final current = e.flow ? e.currentFreeMidi : (e.finished ? null : e.expected);
    final order = rows.keys.toList()..sort();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(children: [
        for (final o in order.reversed) // agudos em cima, como na partitura e na grade
          _mapRow(
            octave: o,
            first: rows[o]!.first,
            notes: rows[o]!,
            hasCurrent: current != null && rows[o]!.contains(current),
            chip: (m) {
              double? cents;
              var skipped = false;
              if (e.flow) {
                cents = (cur != null && cur.midi == m && e.currentFreeMidi == m) ? cur.cents : e.board[m]?.cents;
              } else {
                final r = last[m];
                if (r != null) {
                  skipped = r.skipped || r.cents == null;
                  cents = r.cents;
                }
              }
              final sp = app.scaleNoteParts(m, ascending: ascOf(m));
              return _noteChip(sp.name, sp.octave, cents, current: current == m, zone: zone, skipped: skipped);
            },
          ),
      ]),
    );
  }

  Widget _mapRow({required int octave, required int first, required List<int> notes, required bool hasCurrent, required Widget Function(int) chip}) {
    final c = octaveColor(octave);
    final label = app.scaleNoteName(first, ascending: true, withOctave: true);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: hasCurrent ? 0.14 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: hasCurrent ? 0.7 : 0.16)),
      ),
      child: Row(children: [
        SizedBox(
          width: 46,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: hasCurrent ? AppColors.text : AppColors.textDim)),
            Text(tr('oitava'), style: TextStyle(fontSize: 9.5, color: AppColors.textDim)),
          ]),
        ),
        Expanded(
          child: Wrap(spacing: 3, runSpacing: 3, children: [for (final m in notes) chip(m)]),
        ),
      ]),
    );
  }

  Widget _noteChip(String name, int octave, double? cents,
      {required bool current, required double zone, bool skipped = false}) {
    Color fill = AppColors.surface2;
    Color text = AppColors.textDim;
    if (!skipped && cents != null) {
      final leg = legibleCell(intonationColor(cents, zone));
      fill = leg.fill;
      text = leg.text;
    }
    if (current && cents == null) text = AppColors.text;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: 31,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: current ? AppColors.accent : Colors.transparent, width: current ? 2.5 : 1),
      ),
      child: skipped
          ? Icon(Icons.close, size: 14, color: AppColors.textDim)
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text(name, style: TextStyle(fontSize: 11.5, height: 1.05, fontWeight: current ? FontWeight.w900 : FontWeight.w700, color: text)),
              Text('$octave', style: TextStyle(fontSize: 9.5, height: 1.0, color: text.withValues(alpha: 0.75))),
            ]),
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

/// Escolha da direção do exercício: subir, descer ou os dois. [onChanged] roda depois de aplicar.
Widget directionPicker(AppState app, {VoidCallback? onChanged}) => SegmentedButton<ScaleDirection>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: ScaleDirection.up, icon: const Icon(Icons.north_rounded, size: 18), label: Text(tr('Subir'))),
        ButtonSegment(value: ScaleDirection.down, icon: const Icon(Icons.south_rounded, size: 18), label: Text(tr('Descer'))),
        ButtonSegment(value: ScaleDirection.both, icon: const Icon(Icons.swap_vert_rounded, size: 18), label: Text(tr('Os dois'))),
      ],
      selected: {app.scaleDirection},
      onSelectionChanged: (s) {
        app.setScale(direction: s.first);
        onChanged?.call();
      },
    );
