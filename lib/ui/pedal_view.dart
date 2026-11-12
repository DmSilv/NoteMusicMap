import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'note_widgets.dart';
import 'theme.dart';
import 'widgets.dart';

/// Modo "Pedal" do Afinador: escolha notas num teclado e elas soam juntas, sustentadas. Serve para
/// tocar uma melodia por cima (bordão) e para treinar o ouvido com intervalos e acordes. Soa no
/// sistema de afinação escolhido: em Justo, uma quinta fica pura e o tremor (batimento) some.
class PedalView extends StatefulWidget {
  final AppState app;
  const PedalView({super.key, required this.app});

  @override
  State<PedalView> createState() => _PedalViewState();
}

class _PedalViewState extends State<PedalView> {
  AppState get app => widget.app;
  int _octave = 3; // o teclado vai do Dó desta oitava ao Dó seguinte

  int get _base => 12 * (_octave + 1);

  /// Altura reservada para as notas ligadas (até 4 botões, em 2 linhas): constante, para o teclado ficar parado.
  static const double _chipsHeight = 86;

  @override
  void initState() {
    super.initState();
    app.markTab('pedal');
    app.preloadPedalRange(_base, _base + 12);
  }

  void _shift(int d) {
    final o = (_octave + d).clamp(2, 6);
    if (o == _octave) return;
    setState(() => _octave = o);
    app.preloadPedalRange(_base, _base + 12);
  }

  void _tap(int midi) {
    final msg = app.pedalToggle(midi);
    if (msg != null) app.say(msg);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final names = app.cfg.copyWith(transpose: 0);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Pedal: notas que soam juntas'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                tr('Ligue até {0} notas que ficam soando: toque por cima ou treine o ouvido.', [kMaxPedalVoices]),
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.3),
              ),
              const SizedBox(height: 12),
              _active(names),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(
                  tooltip: tr('Oitava abaixo'),
                  onPressed: _octave > 2 ? () => _shift(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(tr('Oitava {0}  ·  Dó{1} a Dó{2}', [_octave, _octave, _octave + 1]),
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: tr('Oitava acima'),
                  onPressed: _octave < 6 ? () => _shift(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ]),
              _Keyboard(app: app, base: _base, names: names, onTap: _tap),
              const SizedBox(height: 14),
              Text(tr('Atalhos'), style: TextStyle(fontWeight: FontWeight.w800)),
              Text(
                app.pedalNotes.isEmpty
                    ? tr('Montam em cima do Lá da oitava {0}. Com uma nota ligada, montam em cima da mais grave.', [_octave])
                    : tr('Montam em cima da nota mais grave que está ligada.'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in PedalPreset.values)
                  ActionChip(
                    label: Text(p.label),
                    onPressed: () => app.setPedalNotes(
                        pedalPreset(p, app.pedalNotes.isNotEmpty ? app.pedalNotes.first : _base + 9)),
                  ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: app.pedalNotes.isEmpty ? null : app.clearPedal,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(tr('Parar tudo')),
                  ),
                ),
              ]),
            ]),
          ),
          if (app.pedalNotes.length >= 2) ...[
            const SizedBox(height: 12),
            _intervals(names),
          ],
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Som'), style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              ChipGrid(
                labels: [Text(tr('Diapasão')), Text(tr('Flauta')), Text(tr('Violino'))],
                selected: app.toneTimbre.index,
                onSelected: (i) => app.setToneTimbre(ToneTimbre.values[i]),
              ),
              Row(children: [
                Icon(Icons.volume_down, size: 20, color: AppColors.textDim),
                Expanded(
                  child: Slider(
                    min: 0.2,
                    max: 1.0,
                    value: app.toneVolume.clamp(0.2, 1.0),
                    onChanged: app.setToneVolume,
                  ),
                ),
                Icon(Icons.volume_up, size: 20, color: AppColors.textDim),
              ]),
              Text(_systemLine(), style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.3)),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.headphones, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Para tocar junto com o microfone ligado (Grade, Escalas), use fone: o microfone escuta o pedal no alto-falante.'),
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.3),
                  ),
                ),
              ]),
            ]),
          ),
        ]);
      },
    );
  }

  String _systemLine() {
    final sys = switch (app.system) {
      TuningSystem.equal => tr('Igual'),
      TuningSystem.pythagorean => tr('Pitagórico'),
      TuningSystem.just => tr('Justo'),
    };
    final tonic = app.system == TuningSystem.equal ? '' : tr(', tônica {0}', [noteName(60 + app.tonicPc, app.cfg.copyWith(transpose: 0))]);
    return tr('Soando no sistema {0}{1}, com o Lá em {2} Hz. Mude o Lá e o sistema logo abaixo. Em Justo, uma quinta fica pura e o tremor some.', [sys, tonic, app.refA.toStringAsFixed(app.refA == app.refA.roundToDouble() ? 0 : 1)]);
  }

  /// Notas ligadas (chips) e o que elas formam entre si.
  Widget _active(TuningConfig names) {
    final notes = app.pedalNotes;
    if (notes.isEmpty) {
      return SizedBox(
        height: _chipsHeight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.piano, color: AppColors.textDim),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('Nenhuma nota ligada. Toque numa tecla ou escolha um atalho.'), style: TextStyle(color: AppColors.textDim))),
          ]),
        ),
      );
    }
    final f = pedalFrequencies(notes, app.cfg);
    return SizedBox(
      height: _chipsHeight,
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < notes.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _tap(notes[i]),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                NoteLabel.midi(notes[i], names, size: 17, color: AppColors.text),
                const SizedBox(width: 6),
                Text('${f[i].toStringAsFixed(1).replaceAll('.', ',')} Hz', style: TextStyle(color: AppColors.textDim, fontSize: 11.5)),
                const SizedBox(width: 4),
                Icon(Icons.close, size: 16, color: AppColors.textDim),
              ]),
            ),
          ),
      ]),
    );
  }

  /// O que as notas ligadas formam entre si (intervalo, razão pura e tremor). Fica ABAIXO do teclado:
  /// cresce à vontade sem empurrar as teclas.
  Widget _intervals(TuningConfig names) {
    final notes = app.pedalNotes;
    if (notes.length < 2) return const SizedBox.shrink();
    final f = pedalFrequencies(notes, app.cfg);
    final lines = <Widget>[];
    {
      for (var i = 1; i < notes.length; i++) {
        final iv = pedalInterval(notes.first, notes[i], f.first, f[i]);
        lines.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: '${noteName(notes.first, names, withOctave: true)} → ${noteName(notes[i], names, withOctave: true)}: ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: '${iv.name}${iv.simple ? ' (${iv.ratio})' : ''}'),
            if (iv.simple)
              TextSpan(
                text: iv.isSmooth ? tr(' · sem tremor') : tr(' · treme {0} Hz', [iv.beatHz.toStringAsFixed(1).replaceAll('.', ',')]),
                style: TextStyle(color: iv.isSmooth ? AppColors.inTune : AppColors.flat, fontWeight: FontWeight.w700),
              ),
          ]), style: const TextStyle(fontSize: 13, height: 1.3)),
        ));
      }
      final tremor = [
        for (var i = 1; i < notes.length; i++) pedalInterval(notes.first, notes[i], f.first, f[i])
      ].any((x) => x.simple && !x.isSmooth);
      if (tremor && app.system != TuningSystem.just) {
        lines.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(tr('Dica: mude o sistema para Justo e ouça o tremor sumir.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12, fontStyle: FontStyle.italic)),
        ));
      }
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('O que está soando'), style: TextStyle(fontWeight: FontWeight.w800)),
        ...lines,
      ]),
    );
  }
}

/// Um teclado de uma oitava (Dó a Dó). Teclas ligadas ficam destacadas, em qualquer oitava.
class _Keyboard extends StatelessWidget {
  final AppState app;
  final int base; // MIDI do Dó da esquerda
  final TuningConfig names;
  final void Function(int midi) onTap;
  const _Keyboard({required this.app, required this.base, required this.names, required this.onTap});

  static const _white = [0, 2, 4, 5, 7, 9, 11, 12];
  // preto depois da branca de índice -> semitons acima do Dó
  static const _black = {0: 1, 1: 3, 3: 6, 4: 8, 5: 10};

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final kw = w / _white.length;
      const hw = 150.0, hb = 92.0;
      final bw = kw * 0.62;
      final on = app.pedalNotes.toSet();
      return SizedBox(
        height: hw,
        child: Stack(children: [
          for (var i = 0; i < _white.length; i++)
            Positioned(
              left: i * kw,
              width: kw,
              top: 0,
              height: hw,
              child: _key(
                midi: base + _white[i],
                active: on.contains(base + _white[i]),
                black: false,
                withOctave: _white[i] == 0 || _white[i] == 12,
              ),
            ),
          for (final e in _black.entries)
            Positioned(
              left: (e.key + 1) * kw - bw / 2,
              width: bw,
              top: 0,
              height: hb,
              child: _key(midi: base + e.value, active: on.contains(base + e.value), black: true, withOctave: false),
            ),
        ]),
      );
    });
  }

  Widget _key({required int midi, required bool active, required bool black, required bool withOctave}) {
    final bg = black
        ? (active ? AppColors.accent : const Color(0xFF0A0F12))
        : (active ? AppColors.accent.withValues(alpha: 0.9) : const Color(0xFFE9EEF1));
    final fg = black ? (active ? AppColors.onAccent : Colors.white) : const Color(0xFF16202A);
    return Semantics(
      button: true,
      selected: active,
      label: '${noteName(midi, names, withOctave: true)}${active ? tr(', ligada') : ''}',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: black ? 0 : 1),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(black ? 6 : 8)),
          elevation: black ? 3 : 0,
          child: InkWell(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(black ? 6 : 8)),
            onTap: () => onTap(midi),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: NoteLabel.midi(midi, names, withOctave: withOctave, size: black ? 10 : 13, color: fg, weight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
