import 'package:flutter/material.dart';

import '../app_state.dart';
import 'package:afina_core/afina_core.dart';
import 'theme.dart';
import 'widgets.dart';

class TunerPage extends StatefulWidget {
  final AppState app;
  const TunerPage({super.key, required this.app});

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  int? _playingString; // índice da corda cujo tom está tocando
  bool _playingA = false;

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
  void dispose() {
    app.tone.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
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
              ],
            ),
            const SizedBox(height: 12),
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
                      _stat('Desvio', cents == null ? '—' : fmtCents(cents), color),
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
            TextButton.icon(
              onPressed: () => app.listening && app.demo ? app.stopListening() : app.startListening(demoMode: true),
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: Text(app.listening && app.demo
                  ? 'Parar demonstração'
                  : 'Demonstração (sem instrumento)'),
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
          const Text('Referência Lá', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          // Cinco botões de largura igual: sempre cabem, em qualquer tela.
          Row(
            children: [
              for (final hz in [438.0, 440.0, 442.0, 443.0, 445.0])
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
              SizedBox(
                width: 110,
                child: Text('${app.refA.toStringAsFixed(0)} Hz',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              IconButton(
                tooltip: 'Mais 1 Hz',
                onPressed: () => app.setTuning(refA: app.refA + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (!stringsMode) ...[
            const Divider(height: 24),
            const Text('Sistema de afinação', style: TextStyle(fontWeight: FontWeight.w700)),
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
            if (app.system != TuningSystem.equal) ...[
              const SizedBox(height: 10),
              Text('Tônica (tom da peça)', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
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
