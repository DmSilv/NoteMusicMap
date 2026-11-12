import 'dart:math';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'safe_input.dart';
import 'metro_section.dart';
import 'speed_trainer_card.dart';
import 'study_card.dart';
import 'package:afina_core/afina_core.dart';
import 'perf.dart';
import 'design_system.dart';
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
    return Stack(children: [
      Positioned.fill(child: _content()),
      // O clarão da batida: por cima de tudo, sem atrapalhar os toques.
      Positioned.fill(child: IgnorePointer(child: _BeatFlash(app: app))),
    ]);
  }

  Widget _content() {
    return ListenableBuilder(
      listenable: widget.active ? app : kNeverNotifies,
      builder: (context, _) {
        final m = app.metro;
        final running = app.metroRunning;
        return ValueListenableBuilder<int>(
          valueListenable: metroSection,
          builder: (context, section, _) => ListView(
          padding: Ds.screen,
          children: [
            // Duas visões na mesma aba: o metrônomo e o estudo (timers). O estudo fica escondido até a pessoa escolher.
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: kMetroSectionMetronome, icon: Icon(Icons.timer_outlined, size: 18), label: Text('Metrônomo')),
                ButtonSegment(value: kMetroSectionStudy, icon: Icon(Icons.auto_stories_rounded, size: 18), label: Text('Estudo e timers')),
              ],
              selected: {section},
              onSelectionChanged: (v) => metroSection.value = v.first,
            ),
            const DsGap(Ds.gap),
            if (section == kMetroSectionStudy)
              StudyCard(app: app)
            else ...[
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
                          // Acelerando: mostra o BPM que está tocando AGORA (e de onde partiu), não o de partida.
                          child: ValueListenableBuilder<MetroBeat>(
                            valueListenable: app.metroBeat,
                            builder: (context, beat, _) {
                              final live = m.trainer != null && app.metroRunning && beat.bar >= 0 && beat.bpm > 0;
                              final shown = live ? beat.bpm : m.bpm;
                              return Column(
                                children: [
                                  Text(shown.round().toString(),
                                      semanticsLabel: '${shown.round()} batidas por minuto',
                                      style: TextStyle(
                                          fontSize: 84, fontWeight: FontWeight.w800, height: 1.0, color: live ? AppColors.accent : null)),
                                  Text(live ? 'BPM · ${tempoName(shown)} · partiu de ${m.bpm.round()}' : 'BPM · ${tempoName(m.bpm)}',
                                      style: TextStyle(color: AppColors.textDim)),
                                ],
                              );
                            },
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
                              ? 'Sumiço! Segure o pulso…'
                              : (b.bar < 0
                                  ? 'Contagem inicial'
                                  : switch (b.challenge) {
                                      ChallengeKind.faster => 'Mais rápido! Acompanhe…',
                                      ChallengeKind.slower => 'Mais lento! Acompanhe…',
                                      _ => app.challengeOn ? 'No seu andamento' : 'Compasso ${b.bar + 1}',
                                    }))
                          : 'Toque numa bolinha para mudar o acento',
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
            const DsGap(Ds.sectionGap),
            SpeedTrainerCard(app: app),
            const DsGap(Ds.gap),
            _challengeQuick(m),
            const DsGap(Ds.gap),
            SizedBox(width: double.infinity, child: DsSettingsButton(onPressed: _openSettings, label: 'Ajustes do metrônomo')),
            ],
          ],
        ));
      },
    );
  }

  /// Modal com tudo o que é configuração do metrônomo.
  void _openSettings() {
    app.checkVibration(); // mostra se este aparelho vibra de verdade
    showDsSheet(
      context,
      title: 'Ajustes do metrônomo',
      listenable: app,
      children: (c) => _settingsList(app.metro),
    );
  }

  List<Widget> _settingsList(MetronomeConfig m) => [
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
                    title: const Text('Piscar a tela na batida'),
                    subtitle: const Text('Um clarão a cada tempo e a bolinha acende. Não usa a lanterna.',
                        style: TextStyle(fontSize: Ds.fontLabel)),
                    value: app.flashEnabled,
                    onChanged: (v) => app.setTuning(flashEnabled: v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Vibrar na batida'),
                    subtitle: Text(
                        app.vibrationAvailable == false
                            ? app.vibrationWhy()
                            : 'Uma pulsação a cada tempo. Funciona no celular Android.',
                        style: const TextStyle(fontSize: Ds.fontLabel)),
                    value: app.hapticEnabled && app.vibrationAvailable != false,
                    onChanged: app.vibrationAvailable == false ? null : (v) => app.setTuning(hapticEnabled: v),
                  ),
                  if (app.vibrationAvailable != false)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: app.testVibration,
                        icon: const Icon(Icons.vibration, size: 18),
                        label: const Text('Testar vibração'),
                      ),
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
                  const Text('Contagem e pulso interno',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  ...[
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
      ];

  /// Interruptor rápido do modo desafio (a intensidade fica nos ajustes).
  Widget _challengeQuick(MetronomeConfig m) {
    final on = app.challengeOn;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Ds.cardPad, vertical: Ds.s4),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(Icons.psychology_alt_outlined, color: on ? AppColors.accent : AppColors.textDim),
        title: const Text('Modo desafio', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
            on
                ? '${switch (app.challengeCfg.name) { ChallengeName.sumico => 'Sumiço', ChallengeName.elastico => 'Elástico', ChallengeName.total => 'Surpresa total' }} · ${switch (app.challengeCfg.level) { 1 => 'Leve', 3 => 'Intenso', _ => 'Médio' }}. Troque em Ajustes.'
                : 'Treine o pulso: o ritmo some ou muda de surpresa.',
            style: const TextStyle(fontSize: Ds.fontLabel)),
        value: on,
        onChanged: (v) => app.setChallenge(on: v),
      ),
    );
  }

  /// Modo desafio: escolha um dos 3 desafios e a dificuldade; a tela diz exatamente o que vai acontecer.
  Widget _challengeCard(MetronomeConfig m) {
    final on = app.challengeOn;
    final c = app.challengeCfg;
    final bpm = m.bpm.round();
    const names = [
      (ChallengeName.sumico, Icons.volume_off_rounded, 'Sumiço', 'O metrônomo some e volta'),
      (ChallengeName.elastico, Icons.swap_horiz_rounded, 'Elástico', 'O andamento estica e encolhe'),
      (ChallengeName.total, Icons.casino_rounded, 'Surpresa total', 'Qualquer um dos dois'),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: DsIconBadge(Icons.psychology_alt_rounded, size: 36, color: on ? AppColors.accent : AppColors.textDim),
            title: const Text('Modo desafio', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Treine o pulso por dentro. Sempre volta aos $bpm BPM.', style: const TextStyle(fontSize: Ds.fontLabel)),
            value: on,
            onChanged: (v) => app.setChallenge(on: v),
          ),
          if (on) ...[
            const DsGap(Ds.s12),
            for (final (n, icon, title, sub) in names)
              Padding(
                padding: const EdgeInsets.only(bottom: Ds.s8),
                child: Material(
                  color: c.name == n ? AppColors.accent.withValues(alpha: 0.14) : AppColors.surface2,
                  borderRadius: BorderRadius.circular(Ds.radiusControl),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Ds.radiusControl),
                    onTap: () => app.setChallenge(cfg: ChallengeConfig.named(n, level: c.level)),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: Ds.tap),
                      padding: const EdgeInsets.symmetric(horizontal: Ds.s12, vertical: Ds.s8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Ds.radiusControl),
                        border: Border.all(color: c.name == n ? AppColors.accent : Colors.transparent, width: 1.5),
                      ),
                      child: Row(children: [
                        Icon(icon, color: c.name == n ? AppColors.accent : AppColors.textDim),
                        const SizedBox(width: Ds.s12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(sub, style: Ds.support()),
                          ]),
                        ),
                        if (c.name == n) Icon(Icons.check_circle_rounded, color: AppColors.accent),
                      ]),
                    ),
                  ),
                ),
              ),
            const DsGap(Ds.s8),
            Text('Dificuldade', style: Ds.section()),
            const DsGap(Ds.s8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('Leve')),
                ButtonSegment(value: 2, label: Text('Médio')),
                ButtonSegment(value: 3, label: Text('Intenso')),
              ],
              selected: {c.level},
              onSelectionChanged: (s) => app.setChallenge(cfg: c.copyWith(level: s.first)),
            ),
            const DsGap(Ds.s16),
            Text('Vai acontecer', style: Ds.section()),
            const DsGap(Ds.s4),
            Text(c.describe(bpm), style: const TextStyle(fontSize: Ds.fontBody, height: 1.35)),
            const DsGap(Ds.s12),
            _ChallengePreview(cfg: c),
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
          inputFormatters: digitsFormatters(4),
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

/// Clarão rápido na tela a cada batida (forte = mais claro). Só com "Piscar a tela" ligado.
class _BeatFlash extends StatefulWidget {
  final AppState app;
  const _BeatFlash({required this.app});

  @override
  State<_BeatFlash> createState() => _BeatFlashState();
}

class _BeatFlashState extends State<_BeatFlash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  double _peak = 0;

  @override
  void initState() {
    super.initState();
    widget.app.metroBeat.addListener(_onBeat);
  }

  void _onBeat() {
    final b = widget.app.metroBeat.value;
    if (!widget.app.flashEnabled || !widget.app.metroRunning || b.hidden || b.beat < 0 || b.accent == Accent.mute) return;
    _peak = b.accent == Accent.strong ? 0.30 : 0.16;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    widget.app.metroBeat.removeListener(_onBeat);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => ColoredBox(color: Colors.white.withValues(alpha: _peak * (1 - _c.value))),
      );
}

/// Prévia de 16 compassos de exemplo: o que o desafio escolhido pode fazer (a sequência real é sorteada).
class _ChallengePreview extends StatelessWidget {
  final ChallengeConfig cfg;
  const _ChallengePreview({required this.cfg});

  @override
  Widget build(BuildContext context) {
    final r = RhythmChallenge(cfg, random: Random(cfg.level * 7 + cfg.name.index));
    final bars = [for (var i = 0; i < 16; i++) r.barFor(i)];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 44,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final b in bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: switch (b.kind) {
                      ChallengeKind.faster => 44.0,
                      ChallengeKind.slower => 18.0,
                      _ => 30.0,
                    },
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: switch (b.kind) {
                        ChallengeKind.faster => AppColors.sharp,
                        ChallengeKind.slower => AppColors.flat,
                        ChallengeKind.silence => Colors.transparent,
                        _ => AppColors.surface2,
                      },
                      border: b.kind == ChallengeKind.silence ? Border.all(color: AppColors.textDim, width: 1.5) : null,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const DsGap(Ds.s8),
      Wrap(spacing: Ds.s16, runSpacing: Ds.s4, children: [
        _key(AppColors.surface2, 'normal'),
        if (cfg.tempoChanges) _key(AppColors.sharp, 'mais rápido'),
        if (cfg.tempoChanges) _key(AppColors.flat, 'mais lento'),
        if (cfg.silences) _key(null, 'sumiço'),
      ]),
      const DsGap(Ds.s4),
      Text('Exemplo de 16 compassos. A ordem real é sorteada.', style: Ds.support()),
    ]);
  }

  Widget _key(Color? c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
            border: c == null ? Border.all(color: AppColors.textDim, width: 1.5) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontSize: Ds.fontLabel)),
      ]);
}
