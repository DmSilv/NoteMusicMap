import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'package:afina_core/afina_core.dart';
import 'perf.dart';
import 'theme.dart';
import 'widgets.dart';

class _Sig {
  final String label;
  final int beats;
  final int sub;
  final List<Accent> accents;
  const _Sig(this.label, this.beats, this.sub, this.accents);
}

const _fo = Accent.strong, _me = Accent.medium, _fr = Accent.weak;
const List<_Sig> _sigs = [
  _Sig('2/4', 2, 1, [_fo, _fr]),
  _Sig('3/4', 3, 1, [_fo, _fr, _fr]),
  _Sig('4/4', 4, 1, [_fo, _fr, _fr, _fr]),
  _Sig('5/4', 5, 1, [_fo, _fr, _fr, _me, _fr]),
  _Sig('6/8', 2, 3, [_fo, _me]),
  _Sig('7/8', 7, 1, [_fo, _fr, _fr, _me, _fr, _me, _fr]),
  _Sig('12/8', 4, 3, [_fo, _fr, _me, _fr]),
];

String tempoName(double bpm) {
  if (bpm < 40) return 'Grave';
  if (bpm < 60) return 'Largo';
  if (bpm < 66) return 'Larghetto';
  if (bpm < 76) return 'Adagio';
  if (bpm < 108) return 'Andante';
  if (bpm < 120) return 'Moderato';
  if (bpm < 156) return 'Allegro';
  if (bpm < 176) return 'Vivace';
  if (bpm < 200) return 'Presto';
  return 'Prestissimo';
}

class MetronomePage extends StatefulWidget {
  final AppState app;
  final bool active;
  const MetronomePage({super.key, required this.app, this.active = true});

  @override
  State<MetronomePage> createState() => _MetronomePageState();
}

class _MetronomePageState extends State<MetronomePage>
    with SingleTickerProviderStateMixin {
  bool _showAdvanced = false;

  AppState get app => widget.app;

  // Os cliques (e a vibração) são lidos pelo app, não por esta tela: assim continuam
  // mesmo quando a pessoa está em outra aba. Aqui só se desenha o último tempo marcado.
  ValueNotifier<MetroBeat> get _beat => app.metroBeat;

  void _applySig(_Sig s) {
    final m = app.metro;
    app.setMetro(MetronomeConfig(
      bpm: m.bpm,
      beatsPerBar: s.beats,
      subdivision: s.sub,
      accents: s.accents,
      subdivisionMask: List<bool>.filled(s.sub, true),
      sound: m.sound,
      volume: m.volume,
      countInBars: m.countInBars,
      trainer: m.trainer,
      silent: m.silent,
      challenge: m.challenge,
    ));
  }

  String get _currentSigLabel {
    final m = app.metro;
    for (final s in _sigs) {
      if (s.beats == m.beatsPerBar && s.sub == m.subdivision) return s.label;
    }
    return '${m.beatsPerBar}/4';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.active ? app : kNeverNotifies,
      builder: (context, _) {
        final m = app.metro;
        final running = app.metroRunning;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            AppCard(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _roundBtn(Icons.remove, () => app.setBpm(m.bpm - 1), 'Diminuir 1 BPM',
                          onLong: () => app.setBpm(m.bpm - 5)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: GestureDetector(
                          onTap: () => _editBpm(context),
                          child: Column(
                            children: [
                              Text(m.bpm.round().toString(),
                                  semanticsLabel: '${m.bpm.round()} batidas por minuto',
                                  style: const TextStyle(
                                      fontSize: 84, fontWeight: FontWeight.w800, height: 1.0)),
                              Text('BPM · ${tempoName(m.bpm)}',
                                  style: TextStyle(color: AppColors.textDim)),
                            ],
                          ),
                        ),
                      ),
                      _roundBtn(Icons.add, () => app.setBpm(m.bpm + 1), 'Aumentar 1 BPM',
                          onLong: () => app.setBpm(m.bpm + 5)),
                    ],
                  ),
                  Slider(
                    min: 30,
                    max: 240,
                    value: m.bpm.clamp(30, 240),
                    onChanged: (v) => app.setBpm(v),
                  ),
                  Row(
                    children: [
                      for (final d in [-10, -5, 5, 10])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ActionChip(
                              label: SizedBox(
                                width: double.infinity,
                                child: Text(d > 0 ? '+$d' : '$d',
                                    textAlign: TextAlign.center),
                              ),
                              onPressed: () => app.setBpm(m.bpm + d),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: app.tapTempo,
                      icon: const Icon(Icons.touch_app),
                      label: const Text('Toque no ritmo (Tap tempo)'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ---- Indicador de tempos ----
            AppCard(
              child: ValueListenableBuilder<MetroBeat>(
                valueListenable: _beat,
                builder: (context, b, _) => Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < m.beatsPerBar; i++)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: _BeatDot(
                                index: i,
                                accent: m.accents[i],
                                active: running && !b.hidden && b.beat == i,
                                flash: app.flashEnabled,
                                onTap: () => app.cycleAccent(i),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      running
                          ? (b.hidden
                              ? 'Continue no seu andamento…'
                              : (b.bar < 0
                                  ? 'Contagem inicial'
                                  : (app.challengeOn ? 'Modo desafio' : 'Compasso ${b.bar + 1}')))
                          : 'Toque numa bolinha para mudar o acento (forte · médio · fraco · mudo)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ---- Play ----
            Center(
              child: Semantics(
                button: true,
                label: running ? 'Parar metrônomo' : 'Iniciar metrônomo',
                child: GestureDetector(
                  onTap: app.toggleMetronome,
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: running ? AppColors.surface2 : AppColors.accent,
                      border: Border.all(
                          color: running ? AppColors.accent : Colors.transparent, width: 3),
                    ),
                    child: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        size: 64,
                        color: running ? AppColors.accent : AppColors.onAccent),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ---- Compasso ----
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Compasso', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final s in _sigs)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: _currentSigLabel == s.label,
                        onSelected: (_) => _applySig(s),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  const Text('Subdivisão', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final e in const {1: 'Tempo', 2: 'Colcheias', 3: 'Tercinas', 4: 'Semicolcheias'}.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: m.subdivision == e.key,
                        onSelected: (_) => app.setSubdivision(e.key),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  const Text('Som', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, children: [
                    for (final e in const {
                      ClickSound.click: 'Clique',
                      ClickSound.wood: 'Madeira',
                      ClickSound.beep: 'Bipe',
                      ClickSound.clave: 'Clave',
                      ClickSound.drum: 'Tambor',
                    }.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: m.sound == e.key,
                        onSelected: (_) => app.setMetro(m.copyWith(sound: e.key)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.volume_down, size: 20, color: AppColors.textDim),
                    Expanded(
                      child: Slider(
                        min: 0.1,
                        max: 1.0,
                        value: m.volume.clamp(0.1, 1.0),
                        onChanged: (v) => app.setMetro(m.copyWith(volume: v)),
                      ),
                    ),
                    Icon(Icons.volume_up, size: 20, color: AppColors.textDim),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Piscar na batida'),
                    value: app.flashEnabled,
                    onChanged: (v) => app.setTuning(flashEnabled: v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Vibrar na batida (celular)'),
                    value: app.hapticEnabled,
                    onChanged: (v) => app.setTuning(hapticEnabled: v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ---- Treino ----
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Treino de andamento e pulso',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
                      ],
                    ),
                  ),
                  if (_showAdvanced) ...[
                    const SizedBox(height: 8),
                    Text('Contagem inicial', style: TextStyle(color: AppColors.textDim)),
                    Wrap(spacing: 6, children: [
                      for (final n in [0, 1, 2])
                        ChoiceChip(
                          label: Text(n == 0 ? 'Sem' : '$n compasso${n > 1 ? 's' : ''}'),
                          selected: m.countInBars == n,
                          onSelected: (_) => app.setMetro(m.copyWith(countInBars: n)),
                        ),
                    ]),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Acelerar aos poucos'),
                      subtitle: Text(m.trainer == null
                          ? 'Sobe o BPM automaticamente a cada alguns compassos'
                          : 'A cada ${m.trainer!.everyBars} compassos: +${m.trainer!.stepBpm.round()} BPM, até ${m.trainer!.maxBpm.round()}'),
                      value: m.trainer != null,
                      onChanged: (v) => app.setMetro(m.copyWith(
                          trainer: v
                              ? TempoTrainer(
                                  everyBars: 4,
                                  stepBpm: 4,
                                  maxBpm: (m.bpm + 40).clamp(40, 320))
                              : null)),
                    ),
                    if (m.trainer != null) ...[
                      _stepper('Compassos entre aumentos', m.trainer!.everyBars.toDouble(), 1, 16,
                          (v) => app.setMetro(m.copyWith(
                              trainer: TempoTrainer(
                                  everyBars: v.round(),
                                  stepBpm: m.trainer!.stepBpm,
                                  maxBpm: m.trainer!.maxBpm)))),
                      _stepper('Aumento (BPM)', m.trainer!.stepBpm, 1, 20,
                          (v) => app.setMetro(m.copyWith(
                              trainer: TempoTrainer(
                                  everyBars: m.trainer!.everyBars,
                                  stepBpm: v.roundToDouble(),
                                  maxBpm: m.trainer!.maxBpm)))),
                      _stepper('Teto (BPM)', m.trainer!.maxBpm, 40, 320,
                          (v) => app.setMetro(m.copyWith(
                              trainer: TempoTrainer(
                                  everyBars: m.trainer!.everyBars,
                                  stepBpm: m.trainer!.stepBpm,
                                  maxBpm: v.roundToDouble())))),
                    ],
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Compassos em silêncio'),
                      subtitle: Text(m.silent == null
                          ? 'Treina o pulso interno: o metrônomo cala e volta'
                          : 'Toca ${m.silent!.playBars}, silencia ${m.silent!.muteBars}'),
                      value: m.silent != null,
                      onChanged: (v) => app.setMetro(m.copyWith(
                          silent: v ? const SilentBars(playBars: 2, muteBars: 1) : null)),
                    ),
                    if (m.silent != null) ...[
                      _stepper('Compassos tocando', m.silent!.playBars.toDouble(), 1, 8,
                          (v) => app.setMetro(m.copyWith(
                              silent: SilentBars(
                                  playBars: v.round(), muteBars: m.silent!.muteBars)))),
                      _stepper('Compassos em silêncio', m.silent!.muteBars.toDouble(), 1, 8,
                          (v) => app.setMetro(m.copyWith(
                              silent: SilentBars(
                                  playBars: m.silent!.playBars, muteBars: v.round())))),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _challengeCard(m),
          ],
        );
      },
    );
  }

  /// Modo desafio ("sabotagem"): surpresas temporárias para treinar o pulso interno.
  Widget _challengeCard(MetronomeConfig m) {
    final on = app.challengeOn;
    final c = app.challengeCfg;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(Icons.psychology_alt_outlined, color: on ? AppColors.accent : AppColors.textDim),
            title: const Text('Modo desafio', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              'De surpresa, o metrônomo acelera, desacelera ou fica mudo por alguns compassos, e sempre volta '
              'aos ${m.bpm.round()} BPM. Treina manter o tempo por dentro.',
              style: const TextStyle(fontSize: 12.5),
            ),
            value: on,
            onChanged: (v) => app.setChallenge(on: v),
          ),
          if (on) ...[
            const SizedBox(height: 4),
            Text('Intensidade', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              for (final (lv, label) in const [(1, 'Leve'), (2, 'Médio'), (3, 'Intenso')])
                ChoiceChip(
                  label: Text(label),
                  selected: c.level == lv,
                  onSelected: (_) => app.setChallenge(cfg: c.copyWith(level: lv)),
                ),
            ]),
            const SizedBox(height: 4),
            Text(
              switch (c.level) {
                1 => 'Mudanças pequenas (cerca de 10%), silêncios de 1 a 2 compassos, surpresas mais espaçadas.',
                3 => 'Mudanças grandes (20 a 35%), silêncios de 2 a 4 compassos, surpresas frequentes.',
                _ => 'Mudanças médias (12 a 22%), silêncios de 2 a 3 compassos.',
              },
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Mudar o andamento'),
              subtitle: const Text('Acelera ou desacelera por alguns compassos', style: TextStyle(fontSize: 12)),
              value: c.tempoChanges,
              onChanged: (v) => app.setChallenge(cfg: c.copyWith(tempoChanges: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Ficar em silêncio'),
              subtitle: const Text('Sem som e sem marcação na tela, depois volta de surpresa',
                  style: TextStyle(fontSize: 12)),
              value: c.silences,
              onChanged: (v) => app.setChallenge(cfg: c.copyWith(silences: v)),
            ),
            if (!c.active)
              Text('Ligue pelo menos uma surpresa para o desafio funcionar.',
                  style: TextStyle(color: AppColors.sharp, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }

  Widget _stepper(String label, double value, double min, double max, ValueChanged<double> on) {
    return Row(
      children: [
        Expanded(flex: 4, child: Text('$label: ${value.round()}', style: const TextStyle(fontSize: 13))),
        Expanded(
          flex: 5,
          child: Slider(
            min: min,
            max: max,
            divisions: (max - min).round(),
            value: value.clamp(min, max),
            onChanged: on,
          ),
        ),
      ],
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap, String tip, {VoidCallback? onLong}) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onLongPress: onLong,
        child: IconButton.filledTonal(
          iconSize: 30,
          onPressed: onTap,
          icon: Icon(icon),
        ),
      ),
    );
  }

  Future<void> _editBpm(BuildContext context) async {
    final ctl = TextEditingController(text: app.metro.bpm.round().toString());
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Digitar BPM'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'BPM'),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text)),
              child: const Text('OK')),
        ],
      ),
    );
    if (v != null) app.setBpm(v);
  }
}

class _BeatDot extends StatelessWidget {
  final int index;
  final Accent accent;
  final bool active;
  final bool flash;
  final VoidCallback onTap;
  const _BeatDot({
    required this.index,
    required this.accent,
    required this.active,
    required this.flash,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = switch (accent) {
      Accent.strong => 60.0,
      Accent.medium => 52.0,
      Accent.weak => 44.0,
      Accent.mute => 36.0,
    };
    final base = switch (accent) {
      Accent.strong => AppColors.accent,
      Accent.medium => AppColors.flat,
      Accent.weak => AppColors.textDim,
      Accent.mute => AppColors.outline,
    };
    final lit = active && flash;
    return Semantics(
      button: true,
      label:
          'Tempo ${index + 1}, acento ${switch (accent) { Accent.strong => 'forte', Accent.medium => 'médio', Accent.weak => 'fraco', Accent.mute => 'mudo' }}',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          height: 66,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lit ? base : base.withValues(alpha: accent == Accent.mute ? 0.25 : 0.28),
                border: Border.all(color: base, width: 2),
                boxShadow: lit
                    ? [BoxShadow(color: base.withValues(alpha: 0.6), blurRadius: 18, spreadRadius: 2)]
                    : null,
              ),
              child: Center(
                child: Text('${index + 1}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: lit ? AppColors.onAccent : AppColors.text)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
