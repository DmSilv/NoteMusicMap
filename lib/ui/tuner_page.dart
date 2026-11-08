import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'package:afina_core/afina_core.dart';
import 'perf.dart';
import 'ref_a_dialog.dart';
import 'theme.dart';
import 'widgets.dart';

class TunerPage extends StatefulWidget {
  final AppState app;
  final bool active;
  const TunerPage({super.key, required this.app, this.active = true});

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
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
        final zone = app.zone.cents;
        final inZone = cents != null && cents.abs() <= zone;
        final color = cents == null ? AppColors.textDim : intonationColor(cents, zone);
        final hint = cents == null
            ? ''
            : inZone
                ? 'Afinado'
                : (cents < 0 ? 'Grave: suba a afinação' : 'Agudo: desça a afinação');

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<TunerMode>(
                    segments: const [
                      ButtonSegment(value: TunerMode.strings, label: Text('Cordas soltas'), icon: Icon(Icons.queue_music)),
                      ButtonSegment(value: TunerMode.chromatic, label: Text('Cromático'), icon: Icon(Icons.graphic_eq)),
                    ],
                    selected: {app.tunerMode},
                    onSelectionChanged: (s) => app.setTuning(tunerMode: s.first),
                    showSelectedIcon: false,
                  ),
                ),
                const HelpButton(
                  title: 'Cordas soltas ou Cromático?',
                  sections: Help.modes,
                  footer: Help.modesFooter,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  stringsMode
                      ? 'Para AFINAR o instrumento: toque uma corda solta e ajuste até ficar verde.'
                      : 'Para ESTUDAR: reconhece qualquer nota e mostra se está afinada.',
                  key: ValueKey(stringsMode),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (stringsMode) _instrumentPicker(),
            const SizedBox(height: 8),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _stat(
                          'Desvio',
                          cents == null || targetHz == null ? '—' : fmtHz(hzOff(cents, targetHz)),
                          color),
                      _stat('Frequência', hz == null ? '—' : '${hz.toStringAsFixed(1)} Hz', AppColors.text),
                      _stat('Alvo', targetHz == null ? '—' : '${targetHz.toStringAsFixed(2)} Hz', AppColors.text),
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
            const SizedBox(height: 12),
            // ---- Cordas ----
            if (stringsMode) _stringsRow(inst, hitString),
            if (stringsMode)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  inst.fretted
                      ? 'Instrumento com trastes: afinação em temperamento igual. Toque numa corda para ouvir a nota.'
                      : 'Cordas em quintas puras (3:2) a partir do Lá. Toque numa corda para ouvir a nota.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ),
            const SizedBox(height: 8),
            // ---- Controle do microfone ----
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: app.listening ? AppColors.surface2 : AppColors.accent,
                      foregroundColor: app.listening ? AppColors.text : AppColors.onAccent,
                    ),
                    onPressed: () => app.listening && !app.demo
                        ? app.stopListening()
                        : app.startListening(),
                    icon: Icon(app.listening && !app.demo ? Icons.mic_off : Icons.mic),
                    label: Text(app.listening && !app.demo ? 'Parar' : 'Ouvir',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                  onPressed: _toggleA,
                  icon: Icon(_playingA ? Icons.stop : Icons.volume_up),
                  label: Text(_playingA ? 'Parar' : 'Ouvir Lá ${app.refA.toStringAsFixed(0)}'),
                ),
              ],
            ),
            if (app.micError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(app.micError!, style: TextStyle(color: AppColors.sharp)),
              ),
            if (kDevDemo)
              TextButton.icon(
                onPressed: () => app.listening && app.demo ? app.stopListening() : app.startListening(demoMode: true),
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('[dev] Simulação silenciosa'),
              ),
            const SizedBox(height: 4),
            MicSettingsCard(app: app),
            const SizedBox(height: 12),
            _tuningCard(stringsMode),
          ],
        );
      },
    );
  }

  Widget _stat(String label, String value, Color c) => Column(
        children: [
          Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      );

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
    return Row(
      children: [
        for (var i = 0; i < inst.strings.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _StringChip(
                label: noteName(inst.strings[i].midi, app.cfg),
                octave: ((inst.strings[i].midi + app.cfg.transpose) ~/ 12 - 1).toString(),
                hz: inst.stringFreq(i, app.refA),
                active: hit == i,
                playing: _playingString == i,
                onTap: () => _toggleString(i),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tuningCard(bool stringsMode) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
                child: Text('Referência Lá', style: TextStyle(fontWeight: FontWeight.w700))),
            const HelpButton(title: 'Lá de referência', sections: Help.refA),
          ]),
          const SizedBox(height: 8),
          // Cinco botões de largura igual: sempre cabem, em qualquer tela.
          Row(
            children: [
              for (final hz in const [415.0, 432.0, 440.0, 442.0, 443.0])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      padding: EdgeInsets.zero,
                      labelPadding: EdgeInsets.zero,
                      label: SizedBox(
                        width: double.infinity,
                        child: Text(hz.toStringAsFixed(0), textAlign: TextAlign.center),
                      ),
                      selected: app.refA == hz,
                      onSelected: (_) => app.setTuning(refA: hz),
                    ),
                  ),
                ),
            ],
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
              'As cordas soltas usam a afinação própria do instrumento: quintas puras nos de arco e '
              'afinação igual nos de trastes. O "sistema de afinação" só vale no modo Cromático.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
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
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                    label: const Text('Igual (piano, violão)'),
                    selected: app.system == TuningSystem.equal,
                    onSelected: (_) => app.setTuning(system: TuningSystem.equal)),
                ChoiceChip(
                    label: const Text('Pitagórico (melodia)'),
                    selected: app.system == TuningSystem.pythagorean,
                    onSelected: (_) => app.setTuning(system: TuningSystem.pythagorean)),
                ChoiceChip(
                    label: const Text('Justo (acordes)'),
                    selected: app.system == TuningSystem.just,
                    onSelected: (_) => app.setTuning(system: TuningSystem.just)),
              ],
            ),
            const SizedBox(height: 6),
            SystemAdvice(app: app),
            if (app.system != TuningSystem.equal) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: Text('Tônica (tom da peça)',
                        style: TextStyle(color: AppColors.textDim, fontSize: 13))),
                const HelpButton(title: 'Tônica e Lá fixo', sections: Help.tonic),
              ]),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var pc = 0; pc < 12; pc++)
                    ChoiceChip(
                      label: Text(noteName(pc + 60, app.cfg.copyWith(transpose: 0))),
                      selected: app.tonicPc == pc,
                      onSelected: (_) => app.setTuning(tonicPc: pc),
                    ),
                ],
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
          Row(
            children: [
              const Expanded(child: Text('Mostrar bemóis (♭) em vez de sustenidos (♯)')),
              Switch(
                value: app.preferFlats,
                onChanged: (v) => app.setTuning(preferFlats: v),
              ),
            ],
          ),
        ],
      ),
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
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: active || playing ? 2 : 1),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(octave, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                ],
              ),
              const SizedBox(height: 2),
              Text('${hz.toStringAsFixed(1)} Hz',
                  style: TextStyle(fontSize: 11, color: AppColors.textDim)),
              Icon(playing ? Icons.volume_up : Icons.volume_mute,
                  size: 14, color: playing ? AppColors.flat : AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}
