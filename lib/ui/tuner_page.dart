import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'package:afina_core/afina_core.dart';
import 'perf.dart';
import 'ref_a_dialog.dart';
import 'note_widgets.dart';
import 'design_system.dart';
import 'theme.dart';
import 'tuning_guide.dart';
import 'pedal_view.dart';
import 'widgets.dart';

class TunerPage extends StatefulWidget {
  final AppState app;
  final bool active;
  const TunerPage({super.key, required this.app, this.active = true});

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  static const _refAs = [415.0, 432.0, 440.0, 442.0, 443.0];
  int? _playingString; // índice da corda cujo tom está tocando
  bool _playingA = false;

  // Nota exibida com pequeno atraso na TROCA: a leitura só muda para outra nota
  // depois de ela se manter estável por um instante. A agulha segue ao vivo.
  static const Duration _noteDelay = Duration(milliseconds: 180);
  String _shownName = '–';
  String _shownSub = '';
  String? _pendingKey;
  DateTime _pendingSince = DateTime.now();
  Timer? _settle;

  /// Devolve (nome, sub) a exibir, segurando a nota anterior durante a transição.
  (String, String) _steady(String name, String sub, bool hasNote) {
    final key = '$name|$sub';
    if (!hasNote) {
      // Silêncio: limpa na hora (o rastreador já segura a nota por um tempo).
      _pendingKey = null;
      _shownName = name;
      _shownSub = sub;
      return (name, sub);
    }
    if (key == '$_shownName|$_shownSub' || _shownName == '–') {
      _pendingKey = null;
      _shownName = name;
      _shownSub = sub;
      return (name, sub);
    }
    if (_pendingKey != key) {
      _pendingKey = key;
      _pendingSince = DateTime.now();
      _settle?.cancel();
      _settle = Timer(_noteDelay + const Duration(milliseconds: 20), () {
        if (mounted) setState(() {});
      });
    } else if (DateTime.now().difference(_pendingSince) >= _noteDelay) {
      _pendingKey = null;
      _shownName = name;
      _shownSub = sub;
      return (name, sub);
    }
    return (_shownName, _shownSub);
  }

  AppState get app => widget.app;

  Future<void> _toggleString(int i) async {
    if (_playingString == i) {
      await app.tone.stop();
      setState(() => _playingString = null);
      return;
    }
    final f = app.instrument.stringFreq(i, app.refA);
    setState(() {
      _playingString = i;
      _playingA = false;
    });
    if (app.tone.running) {
      app.tone.setFrequency(f);
    } else {
      await app.tone.play(f);
    }
  }

  Future<void> _toggleA() async {
    if (_playingA) {
      await app.tone.stop();
      setState(() => _playingA = false);
      return;
    }
    setState(() {
      _playingA = true;
      _playingString = null;
    });
    if (app.tone.running) {
      app.tone.setFrequency(app.refA);
    } else {
      await app.tone.play(app.refA);
    }
  }

  @override
  void initState() {
    super.initState();
    // Prepara os tons logo depois de abrir, sem competir com a abertura da tela.
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _preload();
    });
    // Microfone sozinho ao abrir o Afinador (só se já foi liberado antes).
    if (widget.active && app.tunerMode != TunerMode.pedal) {
      WidgetsBinding.instance.addPostFrameCallback((_) => app.autoListen());
    }
  }

  /// Gera com antecedência o som de cada corda e do Lá de referência.
  void _preload() {
    // Só para testes automatizados: permite medir o áudio desde o primeiro som.
    if (const bool.fromEnvironment('NO_PRELOAD')) return;
    final inst = app.instrument;
    app.tone.preload([
      for (var i = 0; i < inst.strings.length; i++) inst.stringFreq(i, app.refA),
      app.refA,
    ]);
  }

  @override
  void didUpdateWidget(TunerPage old) {
    super.didUpdateWidget(old);
    // Saiu da aba: o tom de referência para (antes continuava tocando).
    if (old.active && !widget.active) {
      app.tone.stop();
      _playingString = null;
      _playingA = false;
      app.autoRelease();
    } else if (!old.active && widget.active && app.tunerMode != TunerMode.pedal) {
      app.autoListen();
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    app.tone.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.active ? app.live : kNeverNotifies,
      builder: (context, _) {
        final inst = app.instrument;
        final stringsMode = app.tunerMode == TunerMode.strings;
        if (app.tunerMode == TunerMode.pedal) return _pedalBody();
        final cur = app.current;

        // Leitura exibida
        String name = '–';
        String sub = app.listening ? 'Toque uma nota' : 'Toque no microfone para começar';
        double? cents;
        double? hz;
        double? targetHz;
        int? hitString;
        if (cur != null) {
          hz = cur.freq;
          if (stringsMode) {
            final s = nearestString(cur.freq, inst, app.refA);
            hitString = s.index;
            cents = s.cents;
            targetHz = s.target;
            final midi = inst.strings[s.index].midi;
            name = noteName(midi, app.cfg, withOctave: false);
            sub = 'corda ${s.index + 1} · ${noteName(midi, app.cfg, withOctave: true)}';
          } else {
            cents = cur.cents;
            targetHz = cur.target;
            name = noteName(cur.midi, app.cfg);
            sub = noteName(cur.midi, app.cfg, withOctave: true);
          }
        }
        (name, sub) = _steady(name, sub, cur != null);
        final zone = app.zoneCents;
        final inZone = cents != null && cents.abs() <= zone;
        final color = cents == null ? AppColors.textDim : intonationColor(cents, zone);
        final hint = cents == null
            ? ''
            : inZone
                ? 'Afinado'
                : (cents < 0 ? 'Grave: suba a afinação' : 'Agudo: desça a afinação');

        return ListView(
          padding: Ds.screen,
          children: [
            _modeRow(),
            const DsGap(Ds.s12),
            _instrumentRow(stringsMode),
            const DsGap(Ds.s12),
            // ---- Leitura ----
            AppCard(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: TextStyle(
                        fontSize: 96,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        color: color),
                    child: Text(name, semanticsLabel: 'Nota $name'),
                  ),
                  const SizedBox(height: 4),
                  Text(sub, style: TextStyle(color: AppColors.textDim, fontSize: 15)),
                  const SizedBox(height: 16),
                  NeedleGauge(cents: cents, zone: zone),
                  const SizedBox(height: 12),
                  // Três colunas de largura igual: esquerda, centro (no meio do cartão) e direita.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _stat(
                          'Desvio',
                          cents == null || targetHz == null ? '—' : fmtHz(hzOff(cents, targetHz)),
                          color,
                          CrossAxisAlignment.start),
                      _stat('Frequência', hz == null ? '—' : '${hz.toStringAsFixed(1)} Hz',
                          AppColors.text, CrossAxisAlignment.center),
                      _stat('Alvo', targetHz == null ? '—' : '${targetHz.toStringAsFixed(2)} Hz',
                          AppColors.text, CrossAxisAlignment.end),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 22,
                    child: Text(hint, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                  ),
                  LevelBar(level: app.level),
                ],
              ),
            ),
            const DsGap(Ds.s12),
            // ---- Cordas ----
            if (stringsMode) _stringsRow(inst, hitString),
            const DsGap(Ds.gap),
            _bottomBar(),
          ],
        );
      },
    );
  }

  /// Instrumento (lista escondida num toque) e o botão que abre os ajustes do afinador.
  Widget _instrumentRow(bool picker) => Row(children: [
        if (picker) Expanded(child: _instrumentPicker()) else const Spacer(),
        const SizedBox(width: Ds.s12),
        DsSettingsButton(onPressed: _openSettings),
      ]);

  /// Ação principal sempre à vista, acima da barra de abas.
  Widget _bottomBar() {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (app.micError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Ds.s8),
            child: Text(app.micError!, style: TextStyle(color: AppColors.sharp)),
          ),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Ds.primaryHeight),
                backgroundColor: app.listening ? AppColors.surface2 : AppColors.accent,
                foregroundColor: app.listening ? AppColors.text : AppColors.onAccent,
              ),
              onPressed: () => app.listening && !app.demo ? app.stopListening() : app.startListening(),
              icon: Icon(app.listening && !app.demo ? Icons.mic_off : Icons.mic),
              label: Text(app.listening && !app.demo ? 'Parar' : 'Ouvir',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: Ds.s12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.primaryHeight)),
            onPressed: _toggleA,
            icon: Icon(_playingA ? Icons.stop : Icons.volume_up),
            label: Text(_playingA ? 'Parar' : 'Lá ${app.refA.toStringAsFixed(0)}'),
          ),
        ]),
        if (kDevDemo)
          TextButton.icon(
            onPressed: () => app.listening && app.demo ? app.stopListening() : app.startListening(demoMode: true),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('[dev] Simulação silenciosa'),
          ),
      ]),
    );
  }

  /// Modal com tudo o que é configuração do afinador.
  void _openSettings() {
    showDsSheet(
      context,
      title: 'Ajustes do afinador',
      listenable: app,
      children: (c) => [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Microfone sozinho', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Liga ao abrir o Afinador (depois de liberado uma vez).', style: TextStyle(fontSize: Ds.fontLabel)),
          value: app.autoMicEnabled,
          onChanged: app.setAutoMic,
        ),
        const DsGap.section(),
        MicSettingsContent(app: app),
        const DsGap.section(),
        _tuningCard(app.tunerMode == TunerMode.strings),
      ],
    );
  }

  Widget _stat(String label, String value, Color c, CrossAxisAlignment align) {
    final a = switch (align) {
      CrossAxisAlignment.start => Alignment.centerLeft,
      CrossAxisAlignment.end => Alignment.centerRight,
      _ => Alignment.center,
    };
    return Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          const SizedBox(height: 2),
          // Nunca vaza nem quebra: se o número for largo, encolhe.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: a,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(
                    color: c,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }

  /// Escolha entre Cordas soltas, Cromático e Pedal.
  Widget _modeRow() {
    Widget seg(String t) => FittedBox(fit: BoxFit.scaleDown, child: Text(t, style: const TextStyle(fontSize: 13)));
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<TunerMode>(
            segments: [
              ButtonSegment(value: TunerMode.strings, label: seg('Cordas soltas')),
              ButtonSegment(value: TunerMode.chromatic, label: seg('Cromático')),
              ButtonSegment(value: TunerMode.pedal, label: seg('Pedal')),
            ],
            selected: {app.tunerMode},
            onSelectionChanged: (s) {
              app.setTuning(tunerMode: s.first);
              if (s.first == TunerMode.pedal) {
                app.autoRelease();
              } else {
                app.autoListen();
              }
            },
            showSelectedIcon: false,
          ),
        ),
        const HelpButton(
          title: 'Cordas soltas, Cromático ou Pedal?',
          sections: Help.modes,
          footer: Help.modesFooter,
        ),
      ],
    );
  }

  /// Modo Pedal: teclado de notas que soam juntas + Lá e sistema de afinação para ajustar ali mesmo.
  Widget _pedalBody() {
    return ListView(
      padding: Ds.screen,
      children: [
        _modeRow(),
        const DsGap(Ds.s12),
        _instrumentRow(false),
        const DsGap(Ds.s12),
        // Em telas largas o teclado não estica sem limite.
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(children: [
              PedalView(app: app),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _instrumentPicker() {
    return PickerField<String>(
      label: 'Instrumento',
      value: app.instrumentId,
      options: instrumentOptions(app.cfg),
      onChanged: (v) {
        app.tone.stop();
        setState(() {
          _playingString = null;
          _playingA = false;
        });
        app.setTuning(instrumentId: v);
        _preload();
      },
    );
  }

  Widget _stringsRow(Instrument inst, int? hit) {
    // Todos os cartões têm a MESMA altura (stretch) e o texto nunca quebra de linha
    // (FittedBox), então a fileira fica alinhada em qualquer instrumento e largura.
    // Ao trocar de instrumento ou de grafia das notas, a fileira inteira faz uma
    // transição suave; ao mudar o Lá de referência, os números deslizam até o novo valor.
    final names = [for (final st in inst.strings) noteName(st.midi, app.cfg)];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(anim), child: child),
      ),
      child: IntrinsicHeight(
        key: ValueKey('${app.instrumentId}|${names.join(',')}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < inst.strings.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _StringChip(
                    label: names[i],
                    octave: ((inst.strings[i].midi + app.cfg.transpose) ~/ 12 - 1).toString(),
                    hz: inst.stringFreq(i, app.refA),
                    active: hit == i,
                    playing: _playingString == i,
                    onTap: () => _toggleString(i),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tuningCard(bool stringsMode) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
                child: Text('Referência Lá', style: TextStyle(fontWeight: FontWeight.w700))),
            const HelpButton(title: 'Lá de referência', sections: Help.refA),
          ]),
          const SizedBox(height: 8),
          // Cinco botões de largura igual: sempre cabem, em qualquer tela.
          ChipGrid(
            labels: [for (final hz in _refAs) Text(hz.toStringAsFixed(0))],
            selected: _refAs.contains(app.refA) ? _refAs.indexOf(app.refA) : null,
            onSelected: (i) => app.setTuning(refA: _refAs[i]),
          ),
          const SizedBox(height: 6),
          // Ajuste fino em linha própria, centralizado.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Menos 1 Hz',
                onPressed: () => app.setTuning(refA: app.refA - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => showRefADialog(context, app),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${app.refA == app.refA.roundToDouble() ? app.refA.toStringAsFixed(0) : app.refA.toStringAsFixed(1)} Hz',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(width: 6),
                    Icon(Icons.edit, size: 15, color: AppColors.textDim),
                  ]),
                ),
              ),
              IconButton(
                tooltip: 'Mais 1 Hz',
                onPressed: () => app.setTuning(refA: app.refA + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (stringsMode) ...[
            const SizedBox(height: 8),
            Text(
              'Cordas soltas: quintas puras nos de arco, afinação igual nos de trastes. O sistema só vale no Cromático.',
              style: Ds.support(),
            ),
          ],
          if (!stringsMode) ...[
            const Divider(height: 24),
            Row(children: [
              const Expanded(
                  child: Text('Sistema de afinação',
                      style: TextStyle(fontWeight: FontWeight.w700))),
              const HelpButton(
                  title: 'Qual sistema de afinação?',
                  sections: Help.system,
                  footer: Help.systemFooter),
            ]),
            const SizedBox(height: 8),
            ChipGrid(
              labels: const [
                ChipLabel2('Igual', 'piano, violão'),
                ChipLabel2('Pitagórico', 'melodia'),
                ChipLabel2('Justo', 'acordes'),
              ],
              selected: TuningSystem.values.indexOf(app.system),
              onSelected: (i) => app.setTuning(system: TuningSystem.values[i]),
            ),
            const SizedBox(height: 6),
            SystemAdvice(app: app),
            TuningSystemGuide(app: app),
            if (app.system != TuningSystem.equal) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: Text('Tônica (tom da peça)',
                        style: TextStyle(color: AppColors.textDim, fontSize: 13))),
                const HelpButton(title: 'Tônica e Lá fixo', sections: Help.tonic),
              ]),
              const SizedBox(height: 6),
              ChipGrid(
                columns: 6,
                labels: [
                  for (var pc = 0; pc < 12; pc++)
                    NoteLabel.midi(pc + 60, app.cfg.copyWith(transpose: 0),
                        withOctave: false, size: 14, weight: FontWeight.w600, color: AppColors.text),
                ],
                selected: app.tonicPc,
                onSelected: (pc) => app.setTuning(tonicPc: pc),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Manter o Lá fixo na referência'),
                subtitle: const Text(
                    'Ligado: o Lá continua em 440 Hz e as outras notas se ajustam. Desligado: a tônica fica no temperado.',
                    style: TextStyle(fontSize: 12)),
                value: app.anchor == Anchor.a4,
                onChanged: (v) => app.setTuning(anchor: v ? Anchor.a4 : Anchor.tonic),
              ),
            ],
          ],
          const Divider(height: 24),
          const Text('Sustenidos e bemóis', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SpellingPicker(app: app),
        ],
      );
  }
}

class _StringChip extends StatelessWidget {
  final String label;
  final String octave;
  final double hz;
  final bool active;
  final bool playing;
  final VoidCallback onTap;
  const _StringChip({
    required this.label,
    required this.octave,
    required this.hz,
    required this.active,
    required this.playing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? AppColors.accent.withValues(alpha: 0.25)
        : AppColors.surface2;
    final border = playing
        ? AppColors.flat
        : (active ? AppColors.accent : AppColors.outline);
    return Semantics(
      button: true,
      label: 'Corda $label$octave, ${hz.toStringAsFixed(1)} hertz. Toque para ouvir.',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: active || playing ? 2 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Altura fixa para a linha da nota: o ♯/♭ usa outra fonte e, sem isto,
              // deixaria o cartão mais alto que os vizinhos.
              SizedBox(
                height: 26,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      NoteLabel(
                        name: label,
                        octave: int.tryParse(octave),
                        size: 20,
                        color: AppColors.text,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              // O número desliza até o novo valor quando o Lá de referência muda.
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: hz),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${v.toStringAsFixed(1)} Hz',
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textDim,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ),
              const SizedBox(height: 2),
              Icon(playing ? Icons.volume_up : Icons.volume_mute,
                  size: 14, color: playing ? AppColors.flat : AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}
