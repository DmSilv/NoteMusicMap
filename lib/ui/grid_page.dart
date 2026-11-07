import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'grid_fullscreen.dart';
import 'grid_widgets.dart';
import 'note_widgets.dart';
import 'perf.dart';
import 'scale_exercise_page.dart';
import 'theme.dart';
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
  int? _selected;

  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
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
    final (lo, hi) = app.gridOctaves;
    final cur = app.current;
    final zone = app.zone.cents;
    final scale = app.scaleMode ? app.scaleNotes.toSet() : <int>{};
    final now = app.now;

    return Column(
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Área fixa: a nota troca com animação sem mexer no resto.
              SizedBox(
                width: 108,
                height: 56,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: NoteReadout(note: cur, cfg: app.cfg, zone: zone, size: 42),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NeedleGauge(cents: cur?.cents, zone: zone),
                    CorrectionHint(cents: cur?.cents, zone: zone),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            backgroundColor: app.listening ? AppColors.surface2 : AppColors.accent,
            foregroundColor: app.listening ? AppColors.text : AppColors.onAccent,
          ),
          onPressed: () => app.listening ? app.stopListening() : app.startListening(),
          icon: Icon(app.listening && !app.demo ? Icons.mic_off : Icons.mic),
          label: Text(app.listening ? (app.demo ? 'Parar demonstração' : 'Parar') : 'Ouvir',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        if (app.micError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(app.micError!, style: TextStyle(color: AppColors.sharp)),
          ),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Oitavas ${lo - 1} a ${hi - 1}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: 'O que significam as cores?',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.help_outline),
                    onPressed: _explainColors,
                  ),
                  IconButton(
                    tooltip: 'Zerar grade',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.restart_alt),
                    onPressed: () async {
                      await confirmResetGrid(context, app);
                      if (mounted) setState(() => _selected = null);
                    },
                  ),
                  IconButton(
                    tooltip: 'Grade em tela cheia',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                        backgroundColor: AppColors.accent.withValues(alpha: 0.2)),
                    icon: const Icon(Icons.fullscreen),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => GridFullscreen(app: app),
                    )),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 26),
                  for (var pc = 0; pc < 12; pc++)
                    Expanded(
                      child: Center(
                        child: Text(
                          noteName(pc + 60, app.cfg.copyWith(transpose: 0)),
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDim),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (var oct = hi; oct >= lo; oct--)
                Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text('${oct - 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                    ),
                    for (var pc = 0; pc < 12; pc++)
                      Expanded(
                        child: _cell(
                          midi: oct * 12 + pc,
                          now: now,
                          zone: zone,
                          playing: cur?.midi == oct * 12 + pc,
                          inScale: scale.isEmpty || scale.contains(oct * 12 + pc),
                          isTarget: scale.contains(oct * 12 + pc),
                        ),
                      ),
                  ],
                ),
              if (_selected != null) _detail(_selected!, now),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: IntonationLegend(zone: zone, compact: true),
              ),
              const SizedBox(height: 6),
              OctaveNav(
                app: app,
                compact: true,
                showHint: true,
                onMore: () => showOctaveSheet(context, app),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =====================================================================
  // Seção 2: Escala
  // =====================================================================
  /// "Lá♭" -> "Lá bemol" (leitura natural).
  String _spoken(String n) => n.replaceAll('♭', ' bemol').replaceAll('♯', ' sustenido');

  /// Opção da tônica: "Lá bemol (Sol sustenido)" nas teclas pretas, para achar rápido.
  String _tonicLabel(int pc) {
    final a = _spoken(noteName(pc + 60, app.cfg.copyWith(transpose: 0)));
    final b = _spoken(noteName(pc + 60, app.cfg.copyWith(transpose: 0, preferFlats: !app.cfg.preferFlats)));
    return a == b ? a : '$a  ·  $b';
  }

  /// "Escala de Fá Maior" / "Escala de Lá bemol menor harmônica".
  String _scaleTitle(int tonicPc) {
    final type = app.scaleType;
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
        app.cfg.copyWith(transpose: 0, preferFlats: flats.contains(tonicPc) || (app.preferFlats && !minor && tonicPc != 6))));
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
          Text('ESCALA ESCOLHIDA',
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
            'começa em ${noteName(app.scaleTonicMidi, app.cfg, withOctave: true)}',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
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
                  child: Text('Escalas guiadas',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                'Como no estudo de escalas de Carl Flesch: escolha o tom, o tipo e 1, 2 ou 3 oitavas. '
                'O app mostra a próxima nota, sobe e desce com você e dá a taxa de acerto no fim.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
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
              _tile(Icons.stacked_line_chart, 'Tipo de escala', app.scaleType.label,
                  () => _pick<ScaleType>(
                        'Tipo de escala',
                        [for (final t in ScaleType.values) (t, t.label)],
                        app.scaleType,
                        (t) => app.setScale(type: t),
                        hint:
                            'Na menor melódica, a escala sobe com 6ª e 7ª maiores e desce como menor natural.',
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
                '${app.scaleNotes.length * 2 - 1} notas no total, subindo e descendo. '
                'Sistema: ${switch (app.system) { TuningSystem.equal => 'temperamento igual', TuningSystem.pythagorean => 'pitagórico', TuningSystem.just => 'entonação justa' }}.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ],
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
    final zoneLabel = switch (app.zone) {
      ZoneLevel.beginner => 'Iniciante (tolera ±10)',
      ZoneLevel.intermediate => 'Intermediário (±5)',
      ZoneLevel.advanced => 'Avançado (±3)',
    };
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
              _tile(Icons.check_circle_outline, 'Nível de exigência', zoneLabel,
                  () => _pick<ZoneLevel>(
                        'Nível de exigência',
                        const [
                          (ZoneLevel.beginner, 'Iniciante · afinado até ±10'),
                          (ZoneLevel.intermediate, 'Intermediário · afinado até ±5'),
                          (ZoneLevel.advanced, 'Avançado · afinado até ±3'),
                        ],
                        app.zone,
                        (z) => app.setTuning(zone: z),
                        hint:
                            'Define a largura da faixa verde. Os números são centésimos de semitom: ♯ é agudo, ♭ é grave.',
                      )),
              const Divider(height: 1),
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
          builder: (context, _) => Padding(
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
              IntonationLegend(zone: app.zone.cents),
              const SizedBox(height: 12),
              Text(
                'Cada quadrado é uma nota. Ele ganha cor conforme você toca: azul quando a '
                'nota está grave (♭), verde quando está afinada e laranja quando está aguda (♯). '
                'O número é o quanto falta, em centésimos de semitom. Quanto mais forte a cor, '
                'mais longe do ideal: corrija e veja o quadrado virar verde. '
                'Toque num quadrado para ver o valor exato.',
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
  Widget _cell({
    required int midi,
    required double now,
    required double zone,
    required bool playing,
    required bool inScale,
    required bool isTarget,
  }) {
    final v = app.grid.view(midi, now);
    var fill = AppColors.surface2;
    if (v != null) {
      final a = (0.5 + 0.5 * v.confidence) * v.alpha;
      fill = Color.lerp(AppColors.surface2, intonationColor(v.avgCents, zone), a)!;
    }
    final dim = !inScale && v == null;
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: GestureDetector(
        onTap: () => setState(() => _selected = _selected == midi ? null : midi),
        child: AspectRatio(
          aspectRatio: 0.82,
          // Transição lenta e suave: a cor "escorre" de uma para a outra.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              color: dim ? AppColors.surface.withValues(alpha: 0.6) : fill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: playing
                    ? AppColors.text
                    : (isTarget && v == null ? AppColors.textDim : Colors.transparent),
                width: playing ? 2.2 : 1,
              ),
            ),
            child: isTarget && v == null
                ? Center(child: Icon(Icons.circle, size: 5, color: AppColors.textDim))
                : null,
          ),
        ),
      ),
    );
  }

  Widget _detail(int midi, double now) {
    final v = app.grid.view(midi, now);
    final name = noteName(midi, app.cfg, withOctave: true);
    final off = app.system == TuningSystem.equal ? null : offsetFromEqual(midi, app.cfg);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        v == null
            ? '$name: ainda não tocada${off == null ? '' : ' · alvo ${fmtCents(off)} do temperado'}'
            : '$name: média ${fmtCents(v.avgCents)} · ${v.seconds.toStringAsFixed(1)} s tocando'
                '${off == null ? '' : ' · alvo ${fmtCents(off)} do temperado'}',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

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
              '${noteName(app.scaleTonicMidi, app.cfg)} ${app.scaleType.label.toLowerCase()}',
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
    final zone = app.zone.cents;
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
          Text(n.avgCents == null ? '' : fmtCents(n.avgCents!),
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
