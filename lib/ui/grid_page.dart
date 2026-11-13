import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'grid_fullscreen.dart';
import 'grid_board.dart';
import 'grid_widgets.dart';
import 'note_widgets.dart';
import 'perf.dart';
import 'scale_exercise_page.dart';
import 'paper_picker.dart';
import 'scale_settings.dart';
import 'staff_card.dart';
import 'design_system.dart';
import 'theme.dart';
import 'tuning_pick.dart';
import 'widgets.dart';

/// Aba Grade, dividida em três seções simples:
///  - Grade: ouvir e ver as notas;
///  - Escala: exercício guiado e relatório;
///  - Ajustes: cada ajuste abre num modal próprio.
class GridPage extends StatefulWidget {
  final AppState app;
  final bool active;
  /// true = é a aba Escalas (só a seção de escalas, sem o seletor).
  final bool scalesOnly;
  const GridPage({super.key, required this.app, this.active = true, this.scalesOnly = false});

  @override
  State<GridPage> createState() => _GridPageState();
}

class _GridPageState extends State<GridPage> {
  int _section = 0; // 0 grade, 1 escala, 2 ajustes

  /// Oitava (rótulo 0..8) mostrada no teclado. Acompanha a nota que toca,
  /// a menos que o usuário tenha escolhido uma oitava há poucos segundos.

  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    if (widget.scalesOnly) {
      _section = 1;
    } else {
      final asked = app.requestGridSection;
      if (asked != null) {
        _section = asked.clamp(0, 2);
        app.requestGridSection = null;
      }
      if (_section == 1) _section = 0; // a seção Escala agora é uma aba própria
      // Pedido de abrir os ajustes (atalhos de outras telas): sobe o modal.
      if (_section == 2) {
        _section = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openGridSettings();
        });
      }
    }
    return ListenableBuilder(
      listenable: widget.active ? app.live : kNeverNotifies,
      builder: (context, _) {
        // Escalas: a partitura é o bloco principal e enche o espaço; o botão de iniciar fica fixo embaixo (não pula quando a página muda).
        if (widget.scalesOnly) return Padding(padding: Ds.screen, child: _scaleSection());
        return ListView(
          padding: Ds.screen,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_section),
                child: widget.scalesOnly ? _scaleSection() : _gridSection(),
              ),
            ),
          ],
        );
      },
    );
  }

  // =====================================================================
  // Seção 1: Grade
  // =====================================================================
  Widget _gridSection() {
    final cur = app.shown;
    final zone = app.gridZoneCents;
    final rows = app.gridOctaves.$2 - app.gridOctaves.$1 + 1;
    return Column(
      children: [
        // Cabeçalho enxuto: a nota que soa (grande), a dica e os botões.
        Row(
          children: [
            SizedBox(
              width: 84,
              height: 56,
              child: Align(
                alignment: Alignment.centerLeft,
                child: NoteReadout(note: cur, cfg: app.cfg, zone: zone, size: 40),
              ),
            ),
            Expanded(
              child: app.showFreq
                  ? Text(
                      cur == null ? ' ' : '${cur.freq.toStringAsFixed(1).replaceAll('.', ',')} Hz',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                    )
                  : const SizedBox.shrink(),
            ),
            IconButton.filled(
              tooltip: app.listening ? tr('Parar de ouvir') : tr('Ouvir'),
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                backgroundColor: app.listening ? AppColors.surface2 : AppColors.accent,
                foregroundColor: app.listening ? AppColors.text : AppColors.onAccent,
              ),
              icon: Icon(app.listening && !app.demo ? Icons.mic_off : Icons.mic),
              onPressed: () => app.listening ? app.stopListening() : app.startListening(),
            ),
            const SizedBox(width: 6),
            // Zerar a sessão: botão próprio e em destaque, logo ao lado do microfone.
            IconButton.filled(
              tooltip: tr('Zerar a sessão'),
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                backgroundColor: AppColors.sharp.withValues(alpha: 0.22),
                foregroundColor: AppColors.sharp,
                side: BorderSide(color: AppColors.sharp.withValues(alpha: 0.7), width: 1.5),
              ),
              icon: const Icon(Icons.restart_alt),
              onPressed: () => confirmResetGrid(context, app),
            ),
            const SizedBox(width: 6),
            // Ampliar a grade: ação da grade, junto dos outros botões de cima (antes era um link solto embaixo).
            IconButton.outlined(
              tooltip: tr('Ampliar a grade'),
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent.withValues(alpha: 0.7), width: 1.5),
              ),
              icon: const Icon(Icons.open_in_full_rounded, size: 20),
              onPressed: _openFullscreen,
            ),
          ],
        ),
        // A dica de correção tem uma linha só dela, com altura fixa (nada pula).
        SizedBox(
          height: 26,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CorrectionHint(cents: cur?.cents, zone: zone, target: cur?.target),
            ),
          ),
        ),
        if (kDevDemo)
          TextButton.icon(
            onPressed: () => app.listening && app.demo
                ? app.stopListening()
                : app.startListening(demoMode: true, demoGlide: true),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: Text(tr('[dev] Glissando')),
          ),
        if (kDevDemo && !app.listening)
          TextButton.icon(
            onPressed: () => app.startListening(demoMode: true),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: Text(tr('[dev] Melodia (testa a troca de nota)')),
          ),
        if (app.micError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(app.micError!, style: TextStyle(color: AppColors.sharp)),
          ),
        const SizedBox(height: 8),
        // A grade em si: 12 colunas (Dó a Si) x oitavas, agudos em cima.
        // Grade pequena (visão geral); "Ampliar" abre em tela cheia para tocar com mais conforto.
        SizedBox(height: rows * 52.0, child: GridBoard(app: app)),
        const DsGap(Ds.s12),
        // A ajuda das cores fica junto da legenda das cores.
        Row(children: [
          Expanded(child: IntonationLegend(zone: zone, compact: true)),
          IconButton(
            tooltip: tr('Como ler as cores'),
            icon: const Icon(Icons.help_outline),
            onPressed: _explainColors,
          ),
        ]),
        const DsGap(Ds.s16),
        OctaveNav(app: app),
        const DsGap(Ds.s16),
        Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: SessionChips(app: app))),
        const DsGap(Ds.gap),
        DsConfigCard(
          semanticLabel: tr('Ajustes da grade'),
          semanticValue: tuningSummary(app),
          onTap: _openGridSettings,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Ajustes da grade'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(tuningSummary(app), style: Ds.support()),
          ]),
        ),
      ],
    );
  }

  /// Afinação da grade: Lá de referência e sistema (igual, pitagórico, justo), como nas Escalas.
  void _openTuning() {
    const refs = [415.0, 432.0, 440.0, 442.0, 443.0];
    showDsSheet(
      context,
      title: tr('Afinação da grade'),
      listenable: app,
      children: (c) => [
        DsSettingRow(
          label: tr('Lá de referência: {0} Hz', [app.refA.toStringAsFixed(app.refA == app.refA.roundToDouble() ? 0 : 1)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
              for (final hz in refs)
                ChoiceChip(
                  label: Text(hz.toStringAsFixed(0)),
                  selected: app.refA == hz,
                  onSelected: (_) => app.setTuning(refA: hz),
                ),
            ]),
            Row(children: [
              IconButton(onPressed: () => app.setTuning(refA: app.refA - 1), icon: const Icon(Icons.remove_circle_outline)),
              Text(tr('ajuste fino'), style: Ds.support()),
              IconButton(onPressed: () => app.setTuning(refA: app.refA + 1), icon: const Icon(Icons.add_circle_outline)),
            ]),
          ]),
        ),
        DsSettingRow(
          label: tr('Sistema de afinação'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<TuningSystem>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: TuningSystem.equal, label: Text(tr('Igual'))),
                ButtonSegment(value: TuningSystem.pythagorean, label: Text(tr('Pitagórico'))),
                ButtonSegment(value: TuningSystem.just, label: Text(tr('Justo'))),
              ],
              selected: {app.system},
              onSelectionChanged: (s) => app.setTuning(
                  system: s.first, tonicPc: s.first == TuningSystem.equal ? null : app.scaleTonicMidi % 12),
            ),
            const DsGap(Ds.s8),
            Text(tuningExplain(app), style: Ds.support()),
          ]),
        ),
      ],
    );
  }

  void _openFullscreen() => Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => GridFullscreen(app: app),
      ));

  // =====================================================================
  // Seção 2: Escala
  // =====================================================================
  /// "Lá♭" -> "Lá bemol" (leitura natural).
  String _spoken(String n) => n.replaceAll('♭', ' bemol').replaceAll('♯', ' sustenido');

  /// "Escala de Fá Maior" / "Escala de Lá bemol menor harmônica".
  String _scaleTitle(int tonicPc) {
    final type = app.scaleType;
    if (type.arpeggio) {
      // Arpejos: a mesma grafia da raiz que a partitura usa (Lá bemol, Fá sustenido, 7ª diminuta de Dó sustenido).
      return type.display(_spoken(tonicNameFor(app.scaleTonicMidi, type, alt: app.scaleAlt)));
    }
    final tipo = switch (type) {
      ScaleType.major => tr('Maior'),
      ScaleType.chromatic => tr('Cromática'),
      ScaleType.majorPentatonic => tr('Pentatônica Maior'),
      _ => type.label.isEmpty ? type.label : type.label[0].toLowerCase() + type.label.substring(1),
    };
    // Grafia usual das tonalidades (Lá bemol Maior, Fá sustenido menor...), a mesma da partitura e do seletor de tônica. A cromática segue a preferência de bemóis.
    final minor = type == ScaleType.naturalMinor ||
        type == ScaleType.harmonicMinor ||
        type == ScaleType.melodicMinor;
    final flats = minor ? const {3, 10} : const {1, 3, 8, 10};
    final nota = _spoken(type == ScaleType.chromatic
        ? noteName(tonicPc + 60, app.cfg.copyWith(transpose: 0, autoSpelling: false, preferFlats: flats.contains(tonicPc) || (app.preferFlats && !minor && tonicPc != 6)))
        : tonicNameFor(app.scaleTonicMidi, type, alt: app.scaleAlt));
    return type == ScaleType.chromatic ? tr('Escala Cromática a partir de {0}', [nota]) : tr('Escala de {0} {1}', [nota, tipo]);
  }

  /// O cartão da escala (ou do arpejo) é o botão de configurar: tocar nele abre o modal (tônica, tipo, oitavas...).
  Widget _scaleHero(int tonicPc, TuningConfig names) {
    return DsConfigCard(
      semanticLabel: tr('Configurar escala'),
      onTap: _openScaleSettings,
      semanticValue: tr('{0}, {1} {2}, começa em {3}', [_scaleTitle(tonicPc), app.scaleOctaves, app.scaleOctaves == 1 ? tr('oitava') : tr('oitavas'), app.scaleNoteName(app.scaleTonicMidi + app.scaleType.start, ascending: true, withOctave: true)]),
      extra: app.scaleType.hint.isEmpty ? null : HelpButton(outlined: true, title: tr('Sobre este exercício'), sections: [(tr('O que é'), app.scaleType.hint)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(_scaleTitle(tonicPc),
                key: ValueKey(_scaleTitle(tonicPc) + app.scaleOctaves.toString()),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.15)),
          ),
          const SizedBox(height: 2),
          Text(
            tr('{0} {1} · começa em {2}', [app.scaleOctaves, app.scaleOctaves == 1 ? tr('oitava') : tr('oitavas'), app.scaleNoteName(app.scaleTonicMidi + app.scaleType.start, ascending: true, withOctave: true)]),
            style: Ds.support(),
          ),
          // como o Flesch manda começar: na corda Sol (IV), na posição que o número da 1ª nota dá
          if (app.scaleStartHint != null)
            Text(
              tr('corda Sol (IV), {0}ª posição', [app.scaleStartHint!.position]),
              style: Ds.support().copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }

  /// As notas do exercício como estão escritas: uma linha "subindo" e outra "descendo" (os nomes mudam na menor melódica).
  List<Widget> _scaleNoteLines() {
    final seq = scaleSequence(app.scaleTonicMidi, app.scaleType, octaves: app.scaleOctaves, direction: app.scaleDirection);
    final up = scaleMidis(app.scaleTonicMidi, app.scaleType, octaves: app.scaleOctaves);
    final dir = app.scaleDirection;
    String line(Iterable<int> ms, bool asc) => ms.map((m) => app.scaleNoteName(m, ascending: asc, withOctave: true)).join('  ·  ');
    final upLine = line(up, true);
    final downMidis = dir == ScaleDirection.up ? <int>[] : (dir == ScaleDirection.down ? seq : seq.sublist(up.length));
    final downLine = line(downMidis, false);
    Widget row(String label, IconData icon, Color c, String text) => Padding(
          padding: const EdgeInsets.only(bottom: Ds.s8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: Ds.s8),
            Expanded(child: Text(text, style: TextStyle(fontSize: Ds.fontBody, color: AppColors.textDim, height: 1.5))),
          ]),
        );
    final out = <Widget>[];
    if (dir != ScaleDirection.down) out.add(row(tr('subindo'), Icons.arrow_upward_rounded, AppColors.flat, upLine));
    if (dir != ScaleDirection.up) out.add(row(tr('descendo'), Icons.arrow_downward_rounded, AppColors.sharp, downLine));
    return out;
  }

  /// A partitura do exercício (ou, sem partitura, a lista de nomes das notas).
  Widget _scaleNotes() {
    if (app.scaleStaff && app.cfg.transpose == 0) {
      final seq = scaleSequence(app.scaleTonicMidi, app.scaleType, octaves: app.scaleOctaves, direction: app.scaleDirection);
      final upCount = app.scaleDirection == ScaleDirection.down ? 0 : scaleMidis(app.scaleTonicMidi, app.scaleType, octaves: app.scaleOctaves).length;
      return StaffCard(
        tonicMidi: app.scaleTonicMidi,
        type: app.scaleType,
        sequence: seq,
        upCount: upCount,
        rhythm: app.scaleRhythm,
        names: app.scaleNames,
        ottava: app.staffOttavaAuto,
        ottavaRange: app.staffOttavaRange,
        fingers: app.scaleFingering,
        alt: app.scaleAltActive,
        paper: app.scalePaper,
        expand: true,
        semanticLabel: tr('Partitura do exercício'),
      );
    }
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Ds.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('NOTAS DO EXERCÍCIO'), style: TextStyle(color: AppColors.textDim, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
            const SizedBox(height: Ds.s8),
            ..._scaleNoteLines(),
            const SizedBox(height: Ds.s4),
            Text(tr('{0} notas no total.', [scaleSequence(app.scaleTonicMidi, app.scaleType, octaves: app.scaleOctaves, direction: app.scaleDirection).length]), style: Ds.support()),
          ],
        ),
      ),
    );
  }

  Widget _scaleSection() {
    final tonicPc = app.scaleTonicMidi % 12;
    final names = app.cfg.copyWith(transpose: 0);
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, icon: Icon(Icons.stairs_rounded), label: Text(tr('Escalas'))),
              ButtonSegment(value: true, icon: Icon(Icons.piano_rounded), label: Text(tr('Arpejos'))),
            ],
            selected: {app.scaleType.arpeggio},
            onSelectionChanged: (v) => app.setScale(type: v.first ? ScaleType.majorTriad : ScaleType.major),
          ),
        ),
        const DsGap(Ds.gap),
        _scaleHero(tonicPc, names),
        const DsGap(Ds.s12),
        if (app.scaleStaff && app.cfg.transpose == 0) ...[
          PaperToggleRow(value: app.scalePaper, onChanged: (p) => app.setStaff(paper: p)),
          const DsGap(Ds.s8),
        ],
        Expanded(child: _scaleNotes()),
        const DsGap(Ds.gap),
        DsPrimaryButton(
          onPressed: () {
            app.startExercise();
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ScaleExercisePage(app: app),
            ));
          },
          icon: Icons.play_arrow,
          label: tr('Iniciar exercício guiado'),
        ),
        if (kDevDemo)
          TextButton.icon(
            onPressed: () {
              app.startExercise(demoMode: true);
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ScaleExercisePage(app: app),
              ));
            },
            icon: const Icon(Icons.play_circle_outline),
            label: Text(tr('[dev] Simular exercício (silencioso)')),
          ),
      ],
    );
  }

  /// Ajustes da escala: uma folha só, com tudo à vista (a mesma do exercício).
  void _openScaleSettings() => showScaleSettings(context, app, exercise: false, onReport: _showReport);

  /// Modal dos ajustes da grade (memória da nota, troca de nota, microfone, zerar).
  void _openGridSettings() {
    showDsSheet(
      context,
      title: tr('Ajustes da grade'),
      listenable: app,
      children: (c) => [_settingsSection()],
    );
  }

  // =====================================================================
  // Seção 3: Ajustes (cada item abre um modal)
  // =====================================================================
  Widget _settingsSection() {
    final histLabel = switch (app.history) {
      HistoryMode.short => tr('1 segundo'),
      HistoryMode.medium => tr('3 segundos'),
      HistoryMode.long => tr('30 segundos'),
      HistoryMode.unlimited => tr('Toda a sessão'),
    };
    final holdLabel = app.holdSeconds <= 0
        ? tr('Até zerar')
        : (app.holdSeconds >= 120 ? tr('2 minutos') : tr('{0} segundos', [app.holdSeconds.round()]));
    return Column(
      children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Oitavas na grade: {0}', [app.gridOctCount]), style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(
              min: 2,
              max: 7,
              divisions: 5,
              value: app.gridOctCount.toDouble(),
              onChanged: (v) => app.setOctCount(v.round()),
            ),
            Text(tr('Menos oitavas = quadrados maiores.'), style: Ds.support()),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Seguir a nota que eu toco')),
              subtitle: Text(tr('A grade muda de oitava sozinha.'), style: TextStyle(fontSize: Ds.fontLabel)),
              value: app.gridFollow,
              onChanged: app.setFollow,
            ),
          ]),
        ),
        const DsGap(Ds.gap),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _tile(Icons.straighten, tr('Afinação'), tuningSummary(app), _openTuning),
              const Divider(height: 1),
              _tile(Icons.history, tr('Memória da nota'), histLabel,
                  () => _pick<HistoryMode>(
                        tr('Memória da nota'),
                        [
                          (HistoryMode.short, tr('1 segundo')),
                          (HistoryMode.medium, tr('3 segundos')),
                          (HistoryMode.long, tr('30 segundos')),
                          (HistoryMode.unlimited, tr('Toda a sessão')),
                        ],
                        app.history,
                        (h) => app.setTuning(history: h),
                        hint:
                            tr('Quanto tempo o que você tocou antes ainda pesa na cor. Curta = reage rápido; longa = mostra a média.'),
                      )),
              const Divider(height: 1),
              _tile(Icons.timer_outlined, tr('Cor fica na tela por'), holdLabel,
                  () => _pick<double>(
                        tr('Cor fica na tela por'),
                        [
                          (10.0, tr('10 segundos')),
                          (30.0, tr('30 segundos')),
                          (120.0, tr('2 minutos')),
                          (0.0, tr('Até zerar')),
                        ],
                        app.holdSeconds,
                        (h) => app.setTuning(holdSeconds: h),
                      )),
              const Divider(height: 1),
              _tile(Icons.speed, tr('Troca de nota'), app.noteSwitch.label,
                  () => _pick<NoteSwitchSpeed>(
                        tr('Troca de nota'),
                        [for (final v in NoteSwitchSpeed.values) (v, '${v.label} · ${v.hint}')],
                        app.noteSwitch,
                        app.setNoteSwitch,
                        hint:
                            tr('Velocidade com que o destaque (nome da nota, ponteiro e quadrado aceso) passa de uma nota para a próxima. As cores da grade continuam registrando tudo o que você toca.'),
                      )),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _tile(Icons.mic_none, tr('Captação do microfone'),
                  tr('{0} · ganho {1}×', [app.sensitivity.label, app.micGain.toStringAsFixed(app.micGain < 10 ? 1 : 0)]),
                  _micSheet),

              const Divider(height: 1),
              _tile(Icons.restart_alt, tr('Zerar a grade'), tr('Apaga as cores acumuladas'),
                  () => confirmResetGrid(context, app)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(IconData icon, String title, String value, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textDim),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(value, style: TextStyle(color: AppColors.textDim)),
      trailing: Icon(Icons.chevron_right, color: AppColors.textDim),
      onTap: onTap,
    );
  }

  /// Modal de escolha única, com cartões. Fecha ao escolher.
  void _pick<T>(String title, List<(T, String)> options, T selected, ValueChanged<T> onPick,
      {String? hint}) {
    showOptionSheet<T>(
      context,
      title: title,
      hint: hint,
      showIcons: false,
      options: [for (final (v, l) in options) OptionItem<T>(v, l)],
      selected: selected,
      onPick: onPick,
    );
  }

  void _micSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: MicSettingsContent(app: app),
          ),
        ),
      ),
    );
  }

  void _explainColors() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Como ler as cores'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              IntonationLegend(zone: app.gridZoneCents),
              const SizedBox(height: 12),
              Text(
                tr('Cada quadrado é uma nota. Ele ganha cor conforme você toca: azul quando a nota está grave, verde quando está afinada e laranja ou vermelho quando está aguda. Quanto mais forte a cor, mais longe do ideal: corrija e veja o quadrado virar verde. O "×3" diz quantas vezes você tocou aquela nota.\n\nA nota que está soando agora ganha uma borda forte, e o topo mostra quantos Hz ela está acima (+) ou abaixo (−) do ideal. No placar, toque em "notas / afinadas" para ver o resumo por nota. O destaque troca de nota com calma, para dar tempo de ler; ajuste em Ajustes › Troca de nota.'),
                style: TextStyle(color: AppColors.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // Células e relatório
  // =====================================================================
  void _showReport() {
    final r = app.buildReport();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              app.scaleType.display(app.scaleTonicName),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              r.played == 0
                  ? tr('Nenhuma nota tocada ainda.')
                  : tr('{0} de {1} notas tocadas estão afinadas ({2}%)', [r.inTune, r.played, (r.accuracy * 100).round()]),
              style: TextStyle(color: AppColors.textDim),
            ),
            const SizedBox(height: 14),
            for (final n in r.notes) _reportRow(n),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: r.played == 0
                  ? null
                  : () async {
                      final nav = Navigator.of(ctx);
                      await app.saveScaleSession(r);
                      nav.pop();
                      app.say(tr('Escala salva na aba Estudo'));
                    },
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(tr('Salvar no estudo')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportRow(NoteReport n) {
    final zone = app.zoneCents;
    final (label, color) = switch (n.status) {
      NoteStatus.notPlayed => (tr('não tocada'), AppColors.textDim),
      NoteStatus.inTune => (tr('afinada'), AppColors.inTune),
      NoteStatus.flat => (tr('grave'), AppColors.flat),
      NoteStatus.sharp => (tr('aguda'), AppColors.sharp),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: n.avgCents == null ? AppColors.surface2 : intonationColor(n.avgCents!, zone),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
              width: 62,
              child: Text(n.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          Expanded(child: Text(label, style: TextStyle(color: color))),
          Text(n.avgCents == null || n.status == NoteStatus.inTune
                  ? ''
                  : fmtHz(hzOff(n.avgCents!, targetFreq(n.midi, app.cfg))),
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
