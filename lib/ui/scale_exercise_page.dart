import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'guidance_banner.dart';
import 'needle.dart';
import 'note_widgets.dart';
import 'octave_colors.dart';
import 'scale_settings.dart';
import 'staff_card.dart';
import 'staff_view.dart';
import 'theme.dart';
import 'toast.dart';
import 'transitions.dart';
import 'widgets.dart';

/// Exercício de escala guiado: o app mostra a próxima nota, acompanha a
/// afinação de cada uma e, no fim, dá a pontuação e orientações.
class ScaleExercisePage extends StatelessWidget {
  final AppState app;
  const ScaleExercisePage({super.key, required this.app});

  String get _title =>
      tr('{0} · {1} oitava{2}', [app.scaleType.display(app.scaleTonicName), app.scaleOctaves, app.scaleOctaves > 1 ? 's' : '']);

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
      bottomNavigationBar: ListenableBuilder(
        listenable: app.live,
        builder: (context, _) {
          final e = app.exercise;
          if (e == null || e.flow || e.finished || !app.listening) return const SizedBox.shrink();
          return DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.surface2))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_compact(context) && e.replayNeeded) ...[_eventCard(e, compact: true), const SizedBox(height: 8)],
                  _controls(context, e),
                ]),
              ),
            ),
          );
        },
      ),
      body: _ToastShift(
        child: SafeArea(
        child: ListenableBuilder(
          listenable: app.live,
          builder: (context, _) {
            final e = app.exercise;
            if (e == null) return const SizedBox.shrink();
            // Guiado ouvindo: a partitura vai para cima (é o que se lê), depois a nota no anel e a régua; os botões ficam no rodapé.
            final guided = app.listening && !e.flow && !e.finished;
            if (guided && _compact(context)) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
                children: [
                  _headerCompact(e),
                  const SizedBox(height: 6),
                  _notation(e, (MediaQuery.sizeOf(context).height - 480).clamp(110.0, 250.0)),
                  const SizedBox(height: 8),
                  _compactCard(context, e),
                ],
              );
            }
            if (guided) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                children: [
                  _header(e),
                  const SizedBox(height: 8),
                  _metroStrip(),
                  const SizedBox(height: 8),
                  _notation(e, (MediaQuery.sizeOf(context).height - 640).clamp(130.0, 220.0)),
                  const SizedBox(height: 12),
                  _guidedCard(e),
                  const SizedBox(height: 12),
                  _live(e),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              children: [
                if (!app.listening) _needMic(context) else if (!e.finished) ...[
                  _target(e),
                  const SizedBox(height: 12),
                  _live(e),
                ],
                if (e.finished) _result(context, e),
                const SizedBox(height: 16),
                _header(e),
                const SizedBox(height: 12),
                // A partitura usa a altura que sobra na tela (a linha "Cor da partitura" mora nos Ajustes do exercício).
                _notation(e, (MediaQuery.sizeOf(context).height - 540).clamp(200.0, 520.0)),
                const SizedBox(height: 10),
                if (!e.finished) _controls(context, e),
              ],
            );
          },
        ),
      ),
      ),
    );
  }

  /// Metrônomo ao lado da partitura: liga/desliga, BPM e o pulso na tela. O som pode ficar desligado (só o pulso visual),
  /// para o microfone não escutar o clique.
  Widget _metroStrip() {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final running = app.metroRunning;
        final silent = app.scaleMetroSilent;
        final bpm = app.metro.bpm.round();
        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(color: AppColors.surface2.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            IconButton(
              tooltip: running ? tr('Parar o metrônomo') : tr('Ligar o metrônomo'),
              onPressed: app.toggleScaleMetronome,
              icon: Icon(running ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 30, color: running ? AppColors.inTune : AppColors.textDim),
            ),
            Expanded(
              child: ValueListenableBuilder<MetroBeat>(
                valueListenable: app.metroBeat,
                builder: (c, b, _) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < app.metro.beatsPerBar.clamp(1, 8); i++)
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: running && b.beat == i ? (i == 0 ? AppColors.inTune : AppColors.text) : AppColors.surface2,
                      ),
                    ),
                ]),
              ),
            ),
            IconButton(tooltip: tr('Mais devagar'), onPressed: () => app.setBpm(app.metro.bpm - 4), icon: const Icon(Icons.remove_circle_outline_rounded)),
            SizedBox(width: 40, child: Text('$bpm', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            IconButton(tooltip: tr('Mais rápido'), onPressed: () => app.setBpm(app.metro.bpm + 4), icon: const Icon(Icons.add_circle_outline_rounded)),
            IconButton(
              tooltip: silent ? tr('Só o pulso na tela (sem som)') : tr('Com som'),
              onPressed: () => app.setScaleMetroSound(silent),
              icon: Icon(silent ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: silent ? AppColors.textDim : AppColors.text),
            ),
          ]),
        );
      },
    );
  }

  /// A partitura do exercício, com a nota de agora em destaque e as já tocadas pintadas pelo resultado.
  /// Sem partitura (ou com instrumento transpositor), cai no mapa de oitavas.
  Widget _notation(ScaleExercise e, double maxHeight) {
    if (!app.scaleStaff || app.cfg.transpose != 0) return _scaleMap(e);
    final marks = <int, StaffMark>{};
    int? cur;
    if (!e.flow) {
      // só os passos já concluídos (depois de trocar do modo livre para o guiado sobram resultados antigos)
      for (var i = 0; i < e.results.length && i < e.index; i++) {
        final r = e.results[i];
        final m = staffMarkOf(r.skipped ? null : r.cents, e.zone);
        if (m != null) marks[i] = m;
      }
      cur = e.finished ? null : e.index;
    } else {
      for (var i = 0; i < e.sequence.length; i++) {
        final m = staffMarkOf(e.board[e.sequence[i]]?.cents, e.zone);
        if (m != null) marks[i] = m;
      }
      final heard = e.currentFreeMidi;
      if (heard != null) {
        final i = e.sequence.indexOf(heard);
        if (i >= 0) cur = i;
      }
    }
    return StaffCard(
      tonicMidi: e.tonicMidi,
      type: app.scaleType,
      sequence: e.sequence,
      upCount: e.upCount,
      rhythm: app.scaleRhythm,
      names: app.scaleNames,
      current: cur,
      marks: marks,
      // travado no "sem escorregar": a nota anterior fica marcada em laranja na partitura ("Volte aqui")
      backTo: (!e.flow && !e.finished && e.replayNeeded && e.replayMidi != null) ? e.index - 1 : null,
      backLabel: tr('Volte aqui'),
      maxHeight: maxHeight,
      semanticLabel: (!e.flow && !e.finished && e.expected != null)
          ? tr('Partitura do exercício. Nota de agora: {0}', [app.scaleNoteName(e.expected!, ascending: e.ascendingAt(e.index), withOctave: true)])
          : tr('Partitura do exercício'),
      hints: !e.flow && app.scaleHints,
      ottava: app.staffOttavaAuto,
      ottavaRange: app.staffOttavaRange,
      fingers: app.scaleFingering,
      alt: app.scaleAltActive,
      paper: app.scalePaper,
      hintNow: !e.flow && !e.finished && e.waitingSeconds >= kHintAfterSeconds,
    );
  }

  /// Linha enxuta no topo: o que está sendo feito e quanto falta. O resto fica nos Ajustes.
  Widget _header(ScaleExercise e) {
    final status = e.finished
        ? tr('Concluído')
        : (e.flow
            ? tr('{0} de {1} notas diferentes', [e.board.length, e.freeNotes.length])
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

  /// Ajustes do exercício: a mesma folha da aba Escalas (tudo no mesmo lugar).
  void _openSettings(BuildContext context) => showScaleSettings(context, app, exercise: true);

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

  /// Dedo (e, na 1ª nota, a corda e a posição) da nota de agora, como o livro marca. Só no violino e nas escalas com tabela;
  /// nas notas que o livro não marca, fica vazio.
  String? _fingerNow(ScaleExercise e) {
    final f = app.scaleFingering;
    if (f == null || e.flow) return null;
    final parts = <String>[];
    final hint = e.index == 0 ? app.scaleStartHint : null;
    if (hint != null) parts.add(tr('corda Sol (IV), {0}ª posição', [hint.position]));
    final mark = e.index < f.length ? f[e.index] : null;
    final n = int.tryParse(mark ?? '');
    if (n != null) parts.add(n == 0 ? tr('corda solta') : tr('{0}º dedo', [n]));
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Modo guiado: a nota da vez dentro de um anel que enche enquanto ela é segurada afinada. O que fazer (suba, desça, volte)
  /// fica num lugar só, no aviso logo abaixo ([_live]); a seta ao lado da nota só diz para que lado ajustar.
  Widget _guidedCard(ScaleExercise e) {
    final back = e.replayMidi; // travado: precisa voltar à nota anterior
    final m = back ?? e.expected!;
    final asc = e.ascendingAt(back != null ? e.index - 1 : e.index);
    final next = [
      for (var k = 1; k <= 3; k++)
        if (e.index + k < e.sequence.length) (e.sequence[e.index + k], e.ascendingAt(e.index + k))
    ];
    final locked = e.replayNeeded && back != null;
    final cur = app.current;
    final cents = (cur != null && cur.midi == m) ? cur.cents : null;
    final off = cents == null ? 0 : (cents > e.zone ? 1 : (cents < -e.zone ? -1 : 0)); // 1 = alto (desça), -1 = baixo (suba)
    final noteColor = locked ? AppColors.sharp : (e.tunedNow ? AppColors.inTune : AppColors.text);
    final finger = _fingerNow(e);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          // Em cima do anel: a legenda "Toque agora" vira o visto de "Afinado" por um instante (mesma altura, a tela não pula).
          SizedBox(
            height: 24,
            child: Center(
              child: e.justCompleted && !locked
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle_rounded, size: 22, color: AppColors.inTune),
                      const SizedBox(width: 6),
                      Text(tr('Afinado'), style: TextStyle(color: AppColors.inTune, fontSize: 14, fontWeight: FontWeight.w800)),
                    ])
                  : Text(locked ? ' ' : tr('Toque agora'), style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: locked ? 0 : e.holdProgress),
                  duration: const Duration(milliseconds: 140),
                  builder: (c, v, _) => CustomPaint(
                    size: const Size(140, 140),
                    painter: _RingPainter(progress: v, color: locked ? AppColors.sharp : AppColors.inTune, track: AppColors.surface2),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (c, a) => fadeThroughTransition(c, a),
                    child: KeyedSubtree(key: ValueKey('${e.index}-$m'), child: _bigNote(m, asc: asc, size: 46, color: noteColor)),
                  ),
                  const SizedBox(height: 2),
                  Text(locked ? tr('volte') : tr('segure'), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                ]),
                if (off != 0 && !locked)
                  Positioned(
                    right: -8,
                    top: 54,
                    child: Icon(off > 0 ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 30, color: AppColors.text, semanticLabel: off > 0 ? tr('desça') : tr('suba')),
                  ),
              ],
            ),
          ),
          // Dedo do livro (altura fixa só quando esta escala tem tabela, para a tela não pular de nota em nota).
          if (app.scaleFingering != null)
            SizedBox(
              height: 24,
              child: Center(child: Text(finger ?? '', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
            ),
          const SizedBox(height: 6),
          // As próximas notas, num bloco só delas. Altura fixa: perto do fim há menos notas, sem mexer na tela.
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: AppColors.surface2.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
            child: next.isEmpty
                ? null
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(tr('Depois'), style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                      const SizedBox(width: 12),
                      for (final n in next) ...[_miniNote(app.scaleNoteName(n.$1, ascending: n.$2, withOctave: true)), const SizedBox(width: 6)],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Régua do desvio: a faixa verde é a tolerância do nível escolhido; a marca mostra onde a nota está agora.
  Widget _zoneMeter(double? cents, double zone) {
    const range = 50.0;
    final inZone = cents != null && cents.abs() <= zone;
    final c = (cents ?? 0).clamp(-range, range).toDouble();
    return Semantics(
      label: cents == null ? tr('Régua de afinação, sem nota') : tr('Régua de afinação: {0} cents', [cents.round()]),
      child: Column(children: [
        SizedBox(
          height: 26,
          child: LayoutBuilder(builder: (ctx, bc) {
            final w = bc.maxWidth;
            final zl = w * (0.5 - zone / (2 * range));
            final zw = w * zone / range;
            final x = w * (0.5 + c / (2 * range));
            return Stack(clipBehavior: Clip.none, children: [
              Positioned(left: 0, right: 0, top: 6, height: 14, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(7)))),
              Positioned(
                left: zl,
                width: zw,
                top: 6,
                height: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.inTune.withValues(alpha: 0.26),
                    border: Border.all(color: AppColors.inTune.withValues(alpha: 0.75), width: 1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 120),
                left: x - 2.5,
                top: 1,
                width: 5,
                height: 24,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: cents == null ? 0 : 1,
                  child: DecoratedBox(decoration: BoxDecoration(color: inZone ? AppColors.inTune : AppColors.text, borderRadius: BorderRadius.circular(3))),
                ),
              ),
            ]);
          }),
        ),
        const SizedBox(height: 2),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(tr('baixo'), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          Text(tr('zona ±{0}', [zone.round()]), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          Text(tr('alto'), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ]),
      ]),
    );
  }

  /// A primeira frase do aviso de volta: o que o app ouviu na chegada.
  String _lockWhat(ScaleExercise e, String nextName) {
    final c = e.lockCents.round();
    final far = e.lockCents.abs() > e.zone * 1.7;
    switch (e.lockReason) {
      case LockReason.wrongNote:
        final wrong = e.lockWrongMidi;
        return tr('Ops! Você tocou {0}, mas a próxima é {1}.', [wrong == null ? '?' : app.scaleNoteName(wrong, ascending: e.ascendingNow, withOctave: true), nextName]);
      case LockReason.sharp:
        return far ? tr('Chegou bem alto ({0} cents).', ['+$c']) : tr('Chegou um pouco alto ({0} cents).', ['+$c']);
      case LockReason.flat:
        return far ? tr('Chegou bem baixo ({0} cents).', ['$c']) : tr('Chegou um pouco baixo ({0} cents).', ['$c']);
      case LockReason.unstable:
        return tr('A afinação oscilou ao chegar (variou {0} cents).', [e.lockSpread.round()]);
      case null:
        return tr('A nota entrou fora do ponto.');
    }
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
            Text(tr('{0} de {1} notas diferentes', [e.board.length, e.freeNotes.length]), style: TextStyle(color: AppColors.textDim, fontSize: 13)),
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

  /// Livre: agulha e aviso em caixa. Guiado: régua e frase curta, e um cartão só quando algo exige uma ação ([_guidedFeedback]).
  Widget _live(ScaleExercise e) {
    if (!e.flow) return _guidedFeedback(e);
    final cur = app.current;
    final zone = app.zoneCents;
    final valid = cur != null && e.freeNotes.contains(cur.midi);
    final cents = valid ? cur.cents : null;
    final cue = e.cue(cur?.midi, cur?.cents ?? 0);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        children: [
          SmoothNeedle(cents: cents, zone: zone),
          const SizedBox(height: 12),
          GuidanceBanner(
            compact: true,
            cents: cents,
            zone: zone,
            cue: cue,
            noteLabel: (m) => app.scaleNoteName(m, ascending: _ascOf(e, m), withOctave: true),
            idleTitle: tr('TOQUE UMA NOTA'),
            idleDetail: tr('Qualquer uma da escala!'),
            tunedDetail: tr('Pode tocar outra nota.'),
          ),
        ],
      ),
    );
  }

  /// Guiado: a régua e UMA frase curta, sem atraso, dizem como ajustar a nota agora. Só quando algo exige uma ação (voltar,
  /// nota errada) aparece o cartão colorido logo abaixo. Verde = afinado, laranja = volte, vermelho = nota errada.
  Widget _guidedFeedback(ScaleExercise e) {
    final f = _fb(e);
    return Column(
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(children: [
            _zoneMeter(f.cents, f.zone),
            const SizedBox(height: 6),
            SizedBox(
              height: 22,
              child: Center(
                child: Text(f.hint, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: f.hintColor, fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
        if (e.replayNeeded) ...[const SizedBox(height: 12), _eventCard(e)],
      ],
    );
  }

  /// Celular (altura útil menor que 900): tudo precisa caber sem rolar, mesmo travado com o aviso, então o anel e a régua ficam lado a lado.
  bool _compact(BuildContext context) => MediaQuery.sizeOf(context).height < 900;

  ({double? cents, double zone, String hint, Color hintColor}) _fb(ScaleExercise e) {
    final cur = app.current;
    final zone = e.zone;
    final back = e.replayMidi;
    final locked = e.replayNeeded && back != null;
    final target = back ?? e.expected;
    final cents = (cur != null && cur.midi == target) ? cur.cents : null;
    // A nota anterior ainda soando (o aluno não largou o arco/dedo) não é erro: o aviso fica quieto até ele tocar outra coisa.
    final holdingPrev = !locked && e.index > 0 && cur?.midi == e.sequence[e.index - 1];
    final cue = locked ? e.cueTo(back, cur?.midi, cur?.cents ?? 0) : (holdingPrev ? null : e.cue(cur?.midi, cur?.cents ?? 0));
    final (hint, hintColor) = _hintFor(e, cents: cents, zone: zone, cue: cue, locked: locked);
    return (cents: cents, zone: zone, hint: hint, hintColor: hintColor);
  }

  /// Compacto: "Nota 4 de 15" e o metrônomo na mesma linha, com o progresso fino embaixo.
  Widget _headerCompact(ScaleExercise e) {
    final status = tr('Nota {0} de {1} · {2}', [e.index + 1, e.sequence.length, e.ascendingNow ? '↑' : '↓']);
    Widget tight(IconData i, String tip, VoidCallback f, {Color? color, double size = 24}) => IconButton(
          tooltip: tip,
          onPressed: f,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          icon: Icon(i, size: size, color: color),
        );
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final running = app.metroRunning;
        final silent = app.scaleMetroSilent;
        return Column(children: [
          Row(children: [
            Expanded(child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            tight(running ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, running ? tr('Parar o metrônomo') : tr('Ligar o metrônomo'), app.toggleScaleMetronome,
                color: running ? AppColors.inTune : AppColors.textDim, size: 28),
            ValueListenableBuilder<MetroBeat>(
              valueListenable: app.metroBeat,
              builder: (c, b, _) => Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: running && b.beat >= 0 ? (b.beat == 0 ? AppColors.inTune : AppColors.text) : AppColors.surface2),
              ),
            ),
            tight(Icons.remove_circle_outline_rounded, tr('Mais devagar'), () => app.setBpm(app.metro.bpm - 4)),
            Text('${app.metro.bpm.round()}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            tight(Icons.add_circle_outline_rounded, tr('Mais rápido'), () => app.setBpm(app.metro.bpm + 4)),
            tight(silent ? Icons.volume_off_rounded : Icons.volume_up_rounded, silent ? tr('Só o pulso na tela (sem som)') : tr('Com som'), () => app.setScaleMetroSound(silent),
                color: silent ? AppColors.textDim : AppColors.text, size: 22),
          ]),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(minHeight: 4, value: e.progress, backgroundColor: AppColors.surface2, color: AppColors.accent),
          ),
        ]);
      },
    );
  }

  /// Compacto: o anel (menor) à esquerda; à direita a régua, a frase e as próximas notas.
  Widget _compactCard(BuildContext context, ScaleExercise e) {
    final f = _fb(e);
    final back = e.replayMidi;
    final locked = e.replayNeeded && back != null;
    final m = back ?? e.expected!;
    final asc = e.ascendingAt(back != null ? e.index - 1 : e.index);
    final next = [
      for (var k = 1; k <= 3; k++)
        if (e.index + k < e.sequence.length) (e.sequence[e.index + k], e.ascendingAt(e.index + k))
    ];
    final noteColor = locked ? AppColors.sharp : (e.tunedNow ? AppColors.inTune : AppColors.text);
    final finger = _fingerNow(e);
    final ring = MediaQuery.sizeOf(context).height >= 780 ? 128.0 : 104.0;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
          width: ring,
          height: ring,
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: locked ? 0 : e.holdProgress),
              duration: const Duration(milliseconds: 140),
              builder: (c, v, _) => CustomPaint(
                size: Size(ring, ring),
                painter: _RingPainter(progress: v, color: locked ? AppColors.sharp : AppColors.inTune, track: AppColors.surface2),
              ),
            ),
            KeyedSubtree(key: ValueKey('c${e.index}-$m'), child: _bigNote(m, asc: asc, size: ring >= 120 ? 44 : 36, color: noteColor)),
            if (e.justCompleted && !locked) Positioned(right: -2, top: -2, child: Icon(Icons.check_circle_rounded, size: 26, color: AppColors.inTune, semanticLabel: tr('Afinado'))),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _zoneMeter(f.cents, f.zone),
            const SizedBox(height: 4),
            SizedBox(
              height: 36,
              child: Text(f.hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: f.hintColor, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.25)),
            ),
            SizedBox(
              height: 26,
              child: next.isEmpty
                  ? null
                  : Row(children: [
                      if (finger != null && finger.isNotEmpty) ...[Flexible(child: Text(finger, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))), const SizedBox(width: 8)],
                      Text(tr('Depois'), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                      const SizedBox(width: 6),
                      for (final n in next.take(2)) ...[_miniNote(app.scaleNoteName(n.$1, ascending: n.$2, withOctave: true)), const SizedBox(width: 2)],
                    ]),
            ),
          ]),
        ),
      ]),
    );
  }

  /// A frase sob a régua, na hora (sem segurar a mensagem anterior): o que fazer com a nota que está soando.
  (String, Color) _hintFor(ScaleExercise e, {required double? cents, required double zone, required NoteCue? cue, required bool locked}) {
    final dim = AppColors.textDim;
    final backMidi = e.replayMidi;
    final nextName = e.expected == null ? '' : app.scaleNoteName(e.expected!, ascending: e.ascendingNow, withOctave: true);
    String dir(double c) {
      final little = c.abs() <= zone * 1.7;
      final n = c > 0 ? '+${c.round()}' : '${c.round()}';
      if (c > 0) return little ? tr('Alto: desça um pouco ({0} cents).', [n]) : tr('Alto: desça ({0} cents).', [n]);
      return little ? tr('Baixo: suba um pouco ({0} cents).', [n]) : tr('Baixo: suba ({0} cents).', [n]);
    }

    if (locked) {
      // Travado: o que vale é a nota anterior; o cartão abaixo diz o que fazer, aqui só o ajuste fino dela.
      if (cents == null) return ('', dim);
      if (cents.abs() <= zone * 1.5) {
        final backName = backMidi == null ? '' : app.scaleNoteName(backMidi, ascending: e.ascendingAt(e.index - 1), withOctave: true);
        return (tr('Isso! Segure {0}.', [backName]), AppColors.inTune);
      }
      return (dir(cents), dim);
    }
    if (e.justCompleted) {
      final c = e.lastDoneCents;
      final n = c == null ? '' : (c > 0 ? '+${c.round()}' : '${c.round()}');
      return (c == null ? tr('Muito bem!') : tr('Muito bem! Chegou com {0} cents.', [n]), AppColors.inTune);
    }
    if (cents != null) {
      return cents.abs() <= zone ? (tr('Afinado: segure.'), AppColors.inTune) : (dir(cents), AppColors.text);
    }
    if (cue != null) {
      final exp = app.scaleNoteName(cue.expectedMidi, ascending: e.ascendingNow, withOctave: true);
      final heard = app.scaleNoteName(cue.heardMidi, ascending: e.ascendingNow, withOctave: true);
      if (!cue.inScale) return (tr('{0} não faz parte desta escala. Procure {1}.', [heard, exp]), dim);
      if (!cue.near) return (tr('Você tocou {0}. Procure {1}.', [heard, exp]), dim);
      final how = cue.amount == 0 ? tr(' um pouco') : (cue.amount == 1 ? '' : tr(' bastante'));
      return (cue.goUp ? tr('Ainda não é {0}. Suba{1}.', [exp, how]) : tr('Ainda não é {0}. Desça{1}.', [exp, how]), AppColors.text);
    }
    if (e.recentShort) return (tr('Segure um pouco mais: o anel precisa fechar.'), AppColors.text);
    return (tr('Toque {0} e segure até o anel fechar.', [nextName]), dim);
  }

  /// O único aviso em caixa: o exercício travou e pede uma ação. Laranja = volte; vermelho = tocou outra nota.
  Widget _eventCard(ScaleExercise e, {bool compact = false}) {
    final back = e.replayMidi;
    final reason = e.lockReason;
    final wrong = reason == LockReason.wrongNote;
    final color = wrong ? AppColors.wrong : AppColors.sharp;
    final nextName = app.scaleNoteName(e.expected!, ascending: e.ascendingNow, withOctave: true);
    final backName = back == null ? '' : app.scaleNoteName(back, ascending: e.ascendingAt(e.index - 1), withOctave: true);
    final String title;
    final String detail;
    if (back == null) {
      title = tr('Solte e toque de novo');
      detail = _lockWhat(e, nextName);
    } else if (wrong) {
      final heard = e.lockWrongMidi;
      title = tr('Você tocou {0}, e a próxima é {1}', [heard == null ? '?' : app.scaleNoteName(heard, ascending: e.ascendingNow, withOctave: true), nextName]);
      detail = tr('Volte para {0} e toque {1} de novo.', [backName, nextName]);
    } else {
      title = tr('Volte para {0} e toque {1} de novo', [backName, nextName]);
      detail = _lockWhat(e, nextName);
    }
    final tip = e.locksHere >= 2 ? _tipFor(reason) : null;
    return Semantics(
      liveRegion: true,
      label: '$title. $detail',
      child: Container(
        padding: compact ? const EdgeInsets.fromLTRB(12, 8, 12, 4) : const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(wrong ? Icons.close_rounded : Icons.undo_rounded, color: color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: compact ? 2 : null, overflow: compact ? TextOverflow.ellipsis : null, style: TextStyle(color: color, fontSize: compact ? 14.5 : 16, fontWeight: FontWeight.w800, height: 1.2)),
                SizedBox(height: compact ? 2 : 4),
                Text(detail, maxLines: compact ? 2 : null, overflow: compact ? TextOverflow.ellipsis : null, style: TextStyle(fontSize: compact ? 13 : 14, height: 1.25)),
                if (tip != null && !compact) ...[
                  const SizedBox(height: 8),
                  Text(tip, style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.3)),
                ],
                if (tip != null && compact) _TipLine(tip: tip),
              ]),
            ),
          ]),
          if (e.canSkipReplay)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: Size(0, compact ? 36 : Ds.tap), padding: compact ? const EdgeInsets.symmetric(horizontal: 8) : null),
                onPressed: e.skipReplay,
                icon: const Icon(Icons.redo_rounded, size: 18),
                label: Text(tr('Tentar de novo sem voltar')),
              ),
            ),
        ]),
      ),
    );
  }

  /// Dica curta depois de repetir o mesmo tipo de erro. Textos provisórios, a validar com quem ensina: ficam todos aqui.
  String? _tipFor(LockReason? r) {
    switch (r) {
      case LockReason.sharp:
      case LockReason.flat:
        return tr('Dica: escute a nota antes de tocar e leve o dedo direto até ela, sem procurar.');
      case LockReason.unstable:
        return tr('Dica: firme o dedo e o arco no começo da nota, antes de segurar.');
      case LockReason.wrongNote:
        return tr('Dica: confira o nome da próxima nota na partitura antes de tocar.');
      case null:
        return null;
    }
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
          if (!e.flow && e.slips > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr('Voltas à nota anterior: {0} (altas {1}, baixas {2}, oscilou {3}, nota errada {4}).',
                    [e.slips, e.slipsSharp, e.slipsFlat, e.slipsUnstable, e.wrongStarts]),
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
            ),
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

/// Dica curta atrás de um toque ("Ver dica"), para o aviso de travar caber em telas baixas.
class _TipLine extends StatefulWidget {
  final String tip;
  const _TipLine({required this.tip});

  @override
  State<_TipLine> createState() => _TipLineState();
}

class _TipLineState extends State<_TipLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (_open) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: GestureDetector(onTap: () => setState(() => _open = false), child: Text(widget.tip, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.25))),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        onPressed: () => setState(() => _open = true),
        child: Text(tr('Ver dica'), style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

/// Enquanto a tela do exercício está aberta, os avisos do app descem para não cobrir o cabeçalho (nota X de N).
class _ToastShift extends StatefulWidget {
  final Widget child;
  const _ToastShift({required this.child});

  @override
  State<_ToastShift> createState() => _ToastShiftState();
}

class _ToastShiftState extends State<_ToastShift> {
  double _before = 0;

  @override
  void initState() {
    super.initState();
    _before = kToastExtraTop;
    kToastExtraTop = _before + 44;
  }

  @override
  void dispose() {
    kToastExtraTop = _before;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Anel de progresso ao redor da nota: o trecho preenchido é o tempo já segurado afinado.
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  const _RingPainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - 6;
    final c = size.center(Offset.zero);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = track;
    canvas.drawCircle(c, r, base);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -3.14159265 / 2, 2 * 3.14159265 * progress.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}
