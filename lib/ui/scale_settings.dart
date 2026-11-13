import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'scale_exercise_page.dart' show directionPicker;
import 'staff_settings.dart';
import 'theme.dart';
import 'tuning_pick.dart';

/// Os ajustes da escala num lugar só, sem modal dentro de modal: tudo aparece na própria folha, em seções, e é a MESMA folha na aba
/// Escalas e na tela do exercício (a pessoa não precisa lembrar onde está cada coisa). Só a Afinação abre uma folha própria, porque
/// é uma escolha longa.
void showScaleSettings(BuildContext context, AppState app, {required bool exercise, VoidCallback? onReport}) {
  showDsSheet(
    context,
    title: exercise ? tr('Ajustes do exercício') : tr('Configurar escala'),
    listenable: exercise ? Listenable.merge([app, app.live]) : app,
    children: (c) => scaleSettingsRows(c, app, exercise: exercise, onReport: onReport),
  );
}

Widget _section(String t) => Padding(
      padding: const EdgeInsets.only(top: Ds.s4, bottom: Ds.s12),
      child: Row(children: [
        Text(t.toUpperCase(), style: TextStyle(color: AppColors.accent, fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
        const SizedBox(width: Ds.s12),
        Expanded(child: Divider(height: 1, color: AppColors.outline)),
      ]),
    );

/// A tônica como o músico pensa: a LETRA (Dó Ré Mi Fá Sol Lá Si) e o acidente (♭ ♮ ♯). Em duas linhas, em vez de uma lista de 17 botões; os
/// acidentes que não existem para aquela letra ficam apagados (não há Mi♯ maior) e a outra grafia (Sol♭ ou Fá♯) é só questão de escolher o acidente.
class _TonicPicker extends StatelessWidget {
  final AppState app;
  const _TonicPicker({required this.app});

  static const _letters = ['Dó', 'Ré', 'Mi', 'Fá', 'Sol', 'Lá', 'Si'];
  static const _glyph = {-1: '\uE260', 0: '\uE261', 1: '\uE262'};

  @override
  Widget build(BuildContext context) {
    final type = app.scaleType;
    final (cl, ca) = ScaleSpeller(app.scaleTonicMidi, type, alt: app.scaleAltActive).tonicSpelling;
    void pick(int l, int a) {
      final t = tonicForSpelling(l, a, type);
      if (t == null) return;
      app.setScale(tonicPc: t.pc, alt: t.alt);
      // Justa/pitagórica dependem da tônica: acompanha.
      if (app.system != TuningSystem.equal) app.setTuning(tonicPc: t.pc);
    }

    // trocar a letra mantém o acidente se ele existir; senão, usa o natural (ou o primeiro que existir)
    void pickLetter(int l) {
      for (final a in [ca, 0, -1, 1]) {
        if (tonicForSpelling(l, a, type) != null) return pick(l, a);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 2))),
          segments: [for (var i = 0; i < 7; i++) ButtonSegment(value: i, label: Text(tr(_letters[i]), maxLines: 1, softWrap: false))],
          selected: {cl},
          onSelectionChanged: (v) => pickLetter(v.first),
        ),
      ),
      const DsGap(Ds.s8),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final a in const [-1, 0, 1])
              ButtonSegment(
                value: a,
                enabled: tonicForSpelling(cl, a, type) != null,
                tooltip: a == -1 ? tr('Bemol') : (a == 0 ? tr('Natural') : tr('Sustenido')),
                label: Text(_glyph[a]!, style: const TextStyle(fontFamily: 'Leland', fontSize: 30, height: 1)),
              ),
          ],
          selected: {ca},
          onSelectionChanged: (v) => pick(cl, v.first),
        ),
      ),
    ]);
  }
}

/// A configuração só cabe na versão simples quando é Maior ou Menor melódica com a grafia comum; senão, "Mais opções" já abre aberto.
bool _needsAdvanced(AppState app) => !(app.scaleType == ScaleType.major || app.scaleType == ScaleType.melodicMinor) || app.scaleAltActive;

/// A versão completa (era a única): tônica por letra e acidente e todos os tipos.
List<Widget> _advancedScaleRows(AppState app) => [
      DsSettingRow(label: tr('Tônica (nota inicial)'), child: _TonicPicker(app: app)),
      DsSettingRow(
        label: app.scaleType.arpeggio ? tr('Tipo de arpejo') : tr('Tipo de escala'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
            for (final t in app.scaleType.arpeggio ? ScaleType.arpeggios : ScaleType.scales)
              ChoiceChip(label: Text(t.label), selected: t == app.scaleType, onSelected: (_) => app.setScale(type: t)),
          ]),
          if (app.scaleType.hint.isNotEmpty) ...[
            const DsGap(Ds.s8),
            Text(app.scaleType.hint, style: Ds.support()),
          ],
          if (app.scaleType == ScaleType.melodicMinor) ...[
            const DsGap(Ds.s8),
            Text(tr('A menor melódica é a menor do sistema de Flesch: sobe com 6ª e 7ª elevadas (Lá e Si naturais em Dó menor) e desce como menor natural (Si♭ e Lá♭). Os nomes das notas já mudam na subida e na descida.'), style: Ds.support()),
          ],
        ]),
      ),
    ];

/// A escolha simples: Maior | Menor e as 12 tonalidades com o nome de sempre (Dó, Mi♭, Fá♯...). Menor é a melódica, a do método de Flesch.
class _SimpleKeyPicker extends StatelessWidget {
  final AppState app;
  const _SimpleKeyPicker({required this.app});

  static const _letters = ['Dó', 'Ré', 'Mi', 'Fá', 'Sol', 'Lá', 'Si'];

  /// Nome da tônica com o acidente na fonte de partitura (o texto comum pode cair numa fonte que não tem ♭ ♯).
  static InlineSpan _name(int letter, int acc, TextStyle base) {
    final fs = base.fontSize ?? 15;
    return TextSpan(style: base, children: [
      TextSpan(text: tr(_letters[letter])),
      if (acc != 0)
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          // o centro do glifo fica na linha de base dele: sobe um pouco para ficar junto da letra (o ♭ um pouco menos que o ♯)
          child: Padding(
            padding: const EdgeInsets.only(left: 2.5),
            child: Transform.translate(
              offset: Offset(0, -fs * (acc < 0 ? 0.15 : 0.36)),
              child: Text(acc < 0 ? '\uE260' : '\uE262', style: TextStyle(color: base.color, fontFamily: 'Leland', fontSize: fs * 1.5, height: 1)),
            ),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final type = app.scaleType;
    final isMajor = type == ScaleType.major;
    final isMinor = type.isMinor;
    final nameType = isMinor ? type : ScaleType.major;
    final cur = app.scaleTonicMidi % 12;
    void setQuality(int q) {
      if (q == 0) {
        app.setScale(type: ScaleType.major);
      } else if (!isMinor) {
        app.setScale(type: ScaleType.melodicMinor);
      }
    }

    void pick(int pc) {
      app.setScale(tonicPc: pc, alt: false);
      if (app.system != TuningSystem.equal) app.setTuning(tonicPc: pc);
    }

    const pcs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          emptySelectionAllowed: true,
          segments: [ButtonSegment(value: 0, label: Text(tr('Maior'))), ButtonSegment(value: 1, label: Text(tr('Menor')))],
          selected: {if (isMajor) 0 else if (isMinor) 1},
          onSelectionChanged: (v) {
            if (v.isNotEmpty) setQuality(v.first);
          },
        ),
      ),
      const DsGap(Ds.s12),
      LayoutBuilder(builder: (c, box) {
        const gap = Ds.s8;
        final w = (box.maxWidth - gap * 3) / 4;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final pc in pcs)
            SizedBox(
              width: w,
              height: 48,
              child: Builder(builder: (c) {
                final selected = pc == cur;
                // o nome da escala escolhida segue a grafia dela (Sol♭ se for essa); as outras mostram a grafia comum
                final (l, a) = ScaleSpeller(60 + pc, nameType, alt: selected && app.scaleAltActive).tonicSpelling;
                final fg = selected ? Theme.of(c).colorScheme.onPrimaryContainer : AppColors.text;
                return Material(
                  color: selected ? Theme.of(c).colorScheme.primaryContainer : AppColors.surface2,
                  borderRadius: BorderRadius.circular(Ds.radiusControl),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Ds.radiusControl),
                    onTap: () => pick(pc),
                    child: Center(child: Text.rich(_name(l, a, TextStyle(color: fg, fontSize: 16, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)))),
                  ),
                );
              }),
            ),
        ]);
      }),
      const DsGap(Ds.s8),
      Text(isMinor ? tr('O menor aqui é o melódico, o do método de Flesch.') : tr('Toque na nota em que a escala começa.'), style: Ds.support()),
    ]);
  }
}

List<Widget> scaleSettingsRows(BuildContext context, AppState app, {required bool exercise, VoidCallback? onReport}) {
  final e = app.exercise;
  return [
    if (!exercise) ...[
      _section(tr('Escala')),
      if (app.scaleType.arpeggio)
        ..._advancedScaleRows(app)
      else ...[
        // versão simples: quem só quer "Dó menor" ou "Mi♭ maior" escolhe direto, sem letra + acidente + tipo
        DsSettingRow(label: tr('Qual escala?'), child: _SimpleKeyPicker(app: app)),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey(_needsAdvanced(app)),
            initiallyExpanded: _needsAdvanced(app),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(tr('Mais opções'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: Ds.fontBody)),
            subtitle: Text(tr('Outro nome da tônica (Lá♭ em vez de Sol♯) e outros tipos de escala.'), style: Ds.support()),
            children: [const DsGap(Ds.s12), ..._advancedScaleRows(app)],
          ),
        ),
        const DsGap(Ds.s12),
      ],
      DsSettingRow(
        label: tr('Oitavas'),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [for (var o = 1; o <= 4; o++) ButtonSegment(value: o, label: Text('$o'))],
            selected: {app.scaleOctaves},
            onSelectionChanged: (v) => app.setScale(octaves: v.first),
          ),
        ),
      ),
    ],
    DsSettingRow(
      label: tr('Direção'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: double.infinity, child: directionPicker(app, onChanged: exercise ? () => app.startExercise(demoMode: app.demo) : null)),
        if (exercise) ...[
          const DsGap(Ds.s8),
          Text(tr('Muda a ordem das notas e recomeça o exercício.'), style: Ds.support()),
        ],
      ]),
    ),
    _section(tr('Como tocar')),
    DsSettingRow(
      label: tr('Jeito de tocar'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, icon: const Icon(Icons.shuffle_rounded, size: 18), label: Text(tr('Livre'))),
              ButtonSegment(value: false, icon: const Icon(Icons.format_list_numbered_rounded, size: 18), label: Text(tr('Guiado'))),
            ],
            selected: {e?.flow ?? app.exerciseFlow},
            onSelectionChanged: (v) => app.setExerciseFlow(v.first),
          ),
        ),
        const DsGap(Ds.s8),
        Text((e?.flow ?? app.exerciseFlow) ? tr('Toque as notas na ordem que quiser.') : tr('Uma nota de cada vez, na ordem.'), style: Ds.support()),
      ]),
    ),
    if (!exercise) ...[
      // o mesmo desenho de todo liga/desliga da folha: título, uma frase e a chave
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Marcar a escala na grade'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: Ds.fontBody)),
        subtitle: Text(tr('Destaca as notas na aba Grade.'), style: Ds.support()),
        value: app.scaleMode,
        onChanged: (v) => app.setScale(enabled: v),
      ),
      if (app.scaleMode && onReport != null)
        Padding(
          padding: const EdgeInsets.only(bottom: Ds.s12),
          child: Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: onReport, icon: const Icon(Icons.assessment_outlined), label: Text(tr('Ver relatório do que toquei')))),
        ),
    ],
    _section(tr('Partitura')),
    ...staffSettingRows(app),
    _section(tr('Afinação')),
    DsSettingRow(
      label: tr('Afinação'),
      child: OutlinedButton.icon(
        onPressed: () => pickTuningSystem(context, app, tonicPc: app.scaleTonicMidi % 12),
        icon: const Icon(Icons.straighten, size: 20),
        label: Text(tuningSummary(app)),
      ),
    ),
  ];
}
