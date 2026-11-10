import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'grid_fullscreen.dart';
import 'grid_board.dart';
import 'grid_widgets.dart';
import 'note_widgets.dart';
import 'perf.dart';
import 'scale_exercise_page.dart';
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
  const GridPage({super.key, required this.app, this.active = true});

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
    final asked = app.requestGridSection;
    if (asked != null) {
      _section = asked.clamp(0, 2);
      app.requestGridSection = null;
    }
    return ListenableBuilder(
      listenable: widget.active ? app.live : kNeverNotifies,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.grid_view_rounded), label: Text('Grade')),
                ButtonSegment(value: 1, icon: Icon(Icons.queue_music), label: Text('Escala')),
                ButtonSegment(value: 2, icon: Icon(Icons.tune), label: Text('Ajustes')),
              ],
              selected: {_section},
              onSelectionChanged: (s) => setState(() => _section = s.first),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_section),
                child: switch (_section) {
                  0 => _gridSection(),
                  1 => _scaleSection(),
                  _ => _settingsSection(),
                },
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
    final zone = app.zoneCents;
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
              tooltip: app.listening ? 'Parar de ouvir' : 'Ouvir',
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
              tooltip: 'Zerar a sessão',
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                backgroundColor: AppColors.sharp.withValues(alpha: 0.22),
                foregroundColor: AppColors.sharp,
                side: BorderSide(color: AppColors.sharp.withValues(alpha: 0.7), width: 1.5),
              ),
              icon: const Icon(Icons.restart_alt),
              onPressed: () => confirmResetGrid(context, app),
            ),
            IconButton(
              tooltip: 'Tela cheia',
              icon: const Icon(Icons.fullscreen),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => GridFullscreen(app: app),
              )),
            ),
            IconButton(
              tooltip: 'Como ler as cores',
              icon: const Icon(Icons.help_outline),
              onPressed: _explainColors,
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
            label: const Text('[dev] Glissando'),
          ),
        if (kDevDemo && !app.listening)
          TextButton.icon(
            onPressed: () => app.startListening(demoMode: true),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('[dev] Melodia (testa a troca de nota)'),
          ),
        if (app.micError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(app.micError!, style: TextStyle(color: AppColors.sharp)),
          ),
        const SizedBox(height: 8),
        // A grade em si: 12 colunas (Dó a Si) x oitavas, agudos em cima.
        SizedBox(height: rows * 62.0, child: GridBoard(app: app)),
        const SizedBox(height: 10),
        Center(child: SessionChips(app: app)),
        const SizedBox(height: 10),
        IntonationLegend(zone: zone, compact: true),
        const SizedBox(height: 10),
        OctaveNav(app: app, compact: true, onMore: () => showOctaveSheet(context, app)),
        const SizedBox(height: 8),
        _settingsSummary(),
      ],
    );
  }

  /// Resumo dos ajustes ativos ("Lá 440 Hz · Igual"); toque para mudar.
  Widget _settingsSummary() {
    final hz = app.refA == app.refA.roundToDouble()
        ? app.refA.toStringAsFixed(0)
        : app.refA.toStringAsFixed(1);
    final sys = switch (app.system) {
      TuningSystem.equal => 'Igual',
      TuningSystem.pythagorean => 'Pitagórico',
      TuningSystem.just => 'Justo',
    };
    final tr = app.transpose == 0 ? '' : ' · transpõe ${app.transpose > 0 ? '+' : ''}${app.transpose}';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _section = 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.tune, size: 15, color: AppColors.textDim),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Lá $hz Hz · $sys$tr',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ),
            Icon(Icons.chevron_right, size: 16, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // Seção 2: Escala
  // =====================================================================
  /// "Lá♭" -> "Lá bemol" (leitura natural).
  String _spoken(String n) => n.replaceAll('♭', ' bemol').replaceAll('♯', ' sustenido');

  /// Opção da tônica: "Lá bemol (Sol sustenido)" nas teclas pretas, para achar rápido.
  String _tonicLabel(int pc) {
    final base = app.cfg.copyWith(transpose: 0, keyFlats: null);
    final a = noteName(pc + 60, base);
    // A outra grafia da mesma tecla (Lá♭ <-> Sol♯), para achar rápido.
    final other = a.contains('♯') ? noteNamesFlat[pc] : (a.contains('♭') ? noteNamesSharp[pc] : a);
    return a == other ? _spoken(a) : '${_spoken(a)}  ·  ${_spoken(other)}';
  }

  /// "Escala de Fá Maior" / "Escala de Lá bemol menor harmônica".
  String _scaleTitle(int tonicPc) {
    final type = app.scaleType;
    if (type.arpeggio) {
      // Arpejos: grafia da raiz (Lá bemol, Fá sustenido) como nas tonalidades.
      final minorChord = type.label.contains('menor');
      final flatsA = minorChord ? const {3, 10} : const {1, 3, 8, 10};
      final raiz = _spoken(noteName(tonicPc + 60,
          app.cfg.copyWith(transpose: 0, autoSpelling: false, preferFlats: flatsA.contains(tonicPc) || (app.preferFlats && !minorChord && tonicPc != 6))));
      return type.display(raiz);
    }
    final tipo = switch (type) {
      ScaleType.major => 'Maior',
      ScaleType.chromatic => 'Cromática',
      ScaleType.majorPentatonic => 'Pentatônica Maior',
      _ => type.label.replaceFirst('Menor', 'menor'),
    };
    // Grafia usual das tonalidades: Lá bemol Maior, Fá sustenido menor etc.
    final minor = type == ScaleType.naturalMinor ||
        type == ScaleType.harmonicMinor ||
        type == ScaleType.melodicMinor;
    final flats = minor ? const {3, 10} : const {1, 3, 8, 10};
    final nota = _spoken(noteName(tonicPc + 60,
        app.cfg.copyWith(transpose: 0, autoSpelling: false, preferFlats: flats.contains(tonicPc) || (app.preferFlats && !minor && tonicPc != 6))));
    return type == ScaleType.chromatic ? 'Escala Cromática a partir de $nota' : 'Escala de $nota $tipo';
  }

  Widget _scaleHero(int tonicPc, TuningConfig names) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(app.scaleType.arpeggio ? 'ARPEJO ESCOLHIDO' : 'ESCALA ESCOLHIDA',
              style: TextStyle(color: AppColors.textDim, fontSize: 11.5, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(_scaleTitle(tonicPc),
                key: ValueKey(_scaleTitle(tonicPc) + app.scaleOctaves.toString()),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
          ),
          const SizedBox(height: 4),
          Text(
            '${app.scaleOctaves} ${app.scaleOctaves == 1 ? 'oitava' : 'oitavas'} · '
            'começa em ${noteName(app.scaleTonicMidi + app.scaleType.start, app.cfg, withOctave: true)}',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          if (app.scaleType.hint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(app.scaleType.hint, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ],
        ],
      ),
    );
  }

  Widget _scaleSection() {
    final tonicPc = app.scaleTonicMidi % 12;
    final names = app.cfg.copyWith(transpose: 0);
    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.queue_music),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Escalas e arpejos guiados',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                'Como no sistema de escalas de Carl Flesch: escolha o tom, o tipo e 1, 2 ou 3 oitavas. '
                'O app mostra a próxima nota, sobe e desce com você e dá a taxa de acerto no fim.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.trending_up), label: Text('Escalas')),
                    ButtonSegment(value: true, icon: Icon(Icons.stacked_bar_chart), label: Text('Arpejos')),
                  ],
                  selected: {app.scaleType.arpeggio},
                  onSelectionChanged: (v) => app.setScale(
                      type: v.first ? ScaleType.majorTriad : ScaleType.major),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _scaleHero(tonicPc, names),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _tile(Icons.music_note, 'Tônica (nota inicial)', _spoken(noteName(tonicPc + 60, names)),
                  () => _pick<int>(
                        'Tônica',
                        [for (var pc = 0; pc < 12; pc++) (pc, _tonicLabel(pc))],
                        tonicPc,
                        (pc) {
                          app.setScale(tonicPc: pc);
                          // Justa/pitagórica dependem da tônica: acompanha.
                          if (app.system != TuningSystem.equal) app.setTuning(tonicPc: pc);
                        },
                      )),
              const Divider(height: 1),
              _tile(Icons.stacked_line_chart,
                  app.scaleType.arpeggio ? 'Tipo de arpejo' : 'Tipo de escala', app.scaleType.label,
                  () => _pick<ScaleType>(
                        app.scaleType.arpeggio ? 'Tipo de arpejo' : 'Tipo de escala',
                        [
                          for (final t in app.scaleType.arpeggio ? ScaleType.arpeggios : ScaleType.scales)
                            (t, t.label)
                        ],
                        app.scaleType,
                        (t) => app.setScale(type: t),
                        hint: app.scaleType.arpeggio
                            ? 'Como em Flesch: tríades em posição fundamental e nas duas inversões, 7ª da dominante e 7ª diminuta, em 1, 2 e 3 oitavas.'
                            : 'Na menor melódica, a escala sobe com 6ª e 7ª maiores e desce como menor natural.',
                      )),
              const Divider(height: 1),
              _tile(Icons.layers, 'Oitavas', '${app.scaleOctaves}',
                  () => _pick<int>(
                        'Quantas oitavas',
                        const [(1, '1 oitava'), (2, '2 oitavas'), (3, '3 oitavas')],
                        app.scaleOctaves,
                        (o) => app.setScale(octaves: o),
                        hint:
                            'Mais oitavas = exercício mais longo. Comece por 1 e aumente aos poucos.',
                      )),
              const Divider(height: 1),
              _tile(Icons.straighten, 'Afinação', tuningSummary(app),
                  () => pickTuningSystem(context, app, tonicPc: tonicPc)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notas (subindo)',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              const SizedBox(height: 4),
              Text(app.scaleNotes.map((m) => noteName(m, app.cfg)).join('  ·  '),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                '${app.scaleNotes.length * 2 - 1} notas no total, subindo e descendo. ${tuningExplain(app)}',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Como o exercício acompanha: no seu ritmo (padrão) ou esperando cada nota.
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SwitchListTile(
            secondary: Icon(Icons.play_circle_outline, color: AppColors.textDim),
            title: const Text('Execução livre', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              app.exerciseFlow
                  ? 'Toque qualquer nota da escala, em qualquer ordem: o app reconhece e valida a afinação de cada uma, com aviso de suba ou desça.'
                  : 'Desligado (guiado): uma nota por vez; a próxima só aparece quando a atual estiver afinada e segurada.',
              style: const TextStyle(fontSize: 12.5),
            ),
            value: app.exerciseFlow,
            onChanged: app.setExerciseFlow,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: () {
            app.startExercise();
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ScaleExercisePage(app: app),
            ));
          },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar exercício guiado',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
            label: const Text('[dev] Simular exercício (silencioso)'),
          ),
        const SizedBox(height: 6),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                  child: Text('Marcar a escala na grade',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                Switch(value: app.scaleMode, onChanged: (v) => app.setScale(enabled: v)),
              ]),
              Text(
                'Para tocar livremente: as notas da escala ficam destacadas na aba Grade.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
              if (app.scaleMode) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _showReport,
                  icon: const Icon(Icons.assessment_outlined),
                  label: const Text('Ver relatório do que toquei'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // =====================================================================
  // Seção 3: Ajustes (cada item abre um modal)
  // =====================================================================
  Widget _settingsSection() {
    final histLabel = switch (app.history) {
      HistoryMode.short => '1 segundo',
      HistoryMode.medium => '3 segundos',
      HistoryMode.long => '30 segundos',
      HistoryMode.unlimited => 'Toda a sessão',
    };
    final holdLabel = app.holdSeconds <= 0
        ? 'Até zerar'
        : (app.holdSeconds >= 120 ? '2 minutos' : '${app.holdSeconds.round()} segundos');
    return Column(
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _tile(Icons.history, 'Memória da nota', histLabel,
                  () => _pick<HistoryMode>(
                        'Memória da nota',
                        const [
                          (HistoryMode.short, '1 segundo'),
                          (HistoryMode.medium, '3 segundos'),
                          (HistoryMode.long, '30 segundos'),
                          (HistoryMode.unlimited, 'Toda a sessão'),
                        ],
                        app.history,
                        (h) => app.setTuning(history: h),
                        hint:
                            'Quanto tempo o que você tocou antes ainda pesa na cor. Curta = reage rápido; longa = mostra a média.',
                      )),
              const Divider(height: 1),
              _tile(Icons.timer_outlined, 'Cor fica na tela por', holdLabel,
                  () => _pick<double>(
                        'Cor fica na tela por',
                        const [
                          (10.0, '10 segundos'),
                          (30.0, '30 segundos'),
                          (120.0, '2 minutos'),
                          (0.0, 'Até zerar'),
                        ],
                        app.holdSeconds,
                        (h) => app.setTuning(holdSeconds: h),
                      )),
              const Divider(height: 1),
              _tile(Icons.speed, 'Troca de nota', app.noteSwitch.label,
                  () => _pick<NoteSwitchSpeed>(
                        'Troca de nota',
                        [for (final v in NoteSwitchSpeed.values) (v, '${v.label} · ${v.hint}')],
                        app.noteSwitch,
                        app.setNoteSwitch,
                        hint:
                            'Velocidade com que o destaque (nome da nota, ponteiro e quadrado aceso) passa de uma nota para a próxima. As cores da grade continuam registrando tudo o que você toca.',
                      )),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _tile(Icons.mic_none, 'Captação do microfone',
                  '${app.sensitivity.label} · ganho ${app.micGain.toStringAsFixed(app.micGain < 10 ? 1 : 0)}×',
                  _micSheet),

              const Divider(height: 1),
              _tile(Icons.restart_alt, 'Zerar a grade', 'Apaga as cores acumuladas',
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
      backgroundColor: AppColors.surface,
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
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Como ler as cores',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              IntonationLegend(zone: app.zoneCents),
              const SizedBox(height: 12),
              Text(
                'Cada quadrado é uma nota. Ele ganha cor conforme você toca: azul quando a '
                'nota está grave, verde quando está afinada e laranja ou vermelho quando está aguda. '
                'Quanto mais forte a cor, mais longe do ideal: corrija e veja o quadrado virar verde. '
                'O "×3" diz quantas vezes você tocou aquela nota.\n\n'
                'A nota que está soando agora ganha uma borda forte, e o topo mostra '
                'quantos Hz ela está acima (+) ou abaixo (−) do ideal. '
                'No placar, toque em "notas / afinadas" para ver o resumo por nota. '
                'O destaque troca de nota com calma, para dar tempo de ler; ajuste em Ajustes › Troca de nota.',
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
      backgroundColor: AppColors.surface,
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
              app.scaleType.display(noteName(app.scaleTonicMidi, app.cfg)),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              r.played == 0
                  ? 'Nenhuma nota tocada ainda.'
                  : '${r.inTune} de ${r.played} notas tocadas estão afinadas (${(r.accuracy * 100).round()}%)',
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
                      app.say('Escala salva na aba Estudo');
                    },
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Salvar no estudo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportRow(NoteReport n) {
    final zone = app.zoneCents;
    final (label, color) = switch (n.status) {
      NoteStatus.notPlayed => ('não tocada', AppColors.textDim),
      NoteStatus.inTune => ('afinada', AppColors.inTune),
      NoteStatus.flat => ('grave', AppColors.flat),
      NoteStatus.sharp => ('aguda', AppColors.sharp),
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
