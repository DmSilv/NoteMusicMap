import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'needle.dart';
import 'theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.outline),
        ),
        // Material transparente: switches/listas desenham o toque aqui dentro.
        child: Material(type: MaterialType.transparency, child: child),
      );
}

/// Botões de escolha com LARGURA IGUAL, em [columns] colunas e linhas completas:
/// sem botão "sobrando" sozinho na linha de baixo e sem bordas desencontradas.
/// O rótulo nunca quebra: se faltar espaço, encolhe um pouco (FittedBox).
class ChipGrid extends StatelessWidget {
  final List<Widget> labels;
  final int? selected;
  final ValueChanged<int> onSelected;
  final int? columns;
  final double spacing;
  const ChipGrid({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.columns,
    this.spacing = 6,
  });

  @override
  Widget build(BuildContext context) {
    final cols = (columns ?? labels.length).clamp(1, labels.length);
    final rows = <Widget>[];
    for (var start = 0; start < labels.length; start += cols) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(Row(children: [
        for (var c = 0; c < cols; c++) ...[
          if (c > 0) SizedBox(width: spacing),
          Expanded(
            child: start + c < labels.length
                ? ChoiceChip(
                    showCheckmark: false,
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    label: SizedBox(
                      width: double.infinity,
                      child: FittedBox(fit: BoxFit.scaleDown, child: labels[start + c]),
                    ),
                    selected: selected == start + c,
                    onSelected: (_) => onSelected(start + c),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// Rótulo de duas linhas para um botão de escolha: título e uma explicação curta.
class ChipLabel2 extends StatelessWidget {
  final String title;
  final String sub;
  const ChipLabel2(this.title, this.sub, {super.key});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2)),
          Text(sub, style: const TextStyle(fontSize: 10.5, height: 1.2)),
        ],
      );
}

/// Escala de -50 a +50 com faixa "afinada" e ponteiro de movimento fluido.
class NeedleGauge extends StatelessWidget {
  final double? cents;
  final double zone;
  const NeedleGauge({super.key, required this.cents, required this.zone});

  @override
  Widget build(BuildContext context) => SmoothNeedle(cents: cents, zone: zone);
}

/// Sensibilidade e ganho do microfone.
class MicSettingsCard extends StatelessWidget {
  final AppState app;
  const MicSettingsCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) => AppCard(child: MicSettingsContent(app: app));
}

/// Conteúdo dos ajustes de microfone (sem moldura), para usar em seções.
class MicSettingsContent extends StatelessWidget {
  final AppState app;
  const MicSettingsContent({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Captação do microfone', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ChipGrid(
            labels: [for (final s in MicSensitivity.values) Text(s.label)],
            selected: MicSensitivity.values.indexOf(app.sensitivity),
            onSelected: (i) => app.setMic(sensitivity: MicSensitivity.values[i]),
          ),
          const SizedBox(height: 8),
          Text(
            switch (app.sensitivity) {
              MicSensitivity.rigorous => 'Só notas limpas e fortes. Mais exato, mas perde sons fracos.',
              MicSensitivity.normal => 'Equilíbrio entre precisão e alcance.',
              MicSensitivity.free =>
                'Pega quase tudo: notas fracas, com ar, vibrato forte e ruído. Pode errar a oitava às vezes.',
            },
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.mic, size: 18, color: AppColors.textDim),
            Expanded(
              child: Slider(
                min: 1,
                max: 30,
                value: app.micGain.clamp(1.0, 30.0),
                onChanged: (v) => app.setMic(gain: v),
              ),
            ),
            SizedBox(
                width: 44,
                child: Text('${app.micGain.toStringAsFixed(app.micGain < 10 ? 1 : 0)}×',
                    textAlign: TextAlign.right)),
          ]),
          Text('Ganho: aumente se o instrumento estiver longe ou baixo.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          const SizedBox(height: 12),
          MicDiagPanel(app: app),
        ],
      ),
    );
  }
}

/// Medidor simples da captação: uma barra com o nível do som, o traço do mínimo
/// que o app precisa ouvir e uma frase dizendo o que fazer (aumentar o ganho,
/// reduzir, ou que está bom). Sem números técnicos nem registros.
class MicDiagPanel extends StatelessWidget {
  final AppState app;
  const MicDiagPanel({super.key, required this.app});

  static double _db(double v) => 20 * math.log(math.max(v, 1e-5)) / math.ln10;
  // Escala de -80 dB (silêncio) a 0 dB (máximo).
  static double _pos(double v) => ((_db(v) + 80) / 80).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, app.liveTick]),
      builder: (context, _) {
        final d = app.diag;
        final minRms = app.sensitivity.minRms;
        final on = app.listening && d != null;
        final clipping = app.diagPeakHold >= 0.98;

        String msg;
        Color color;
        if (!app.listening) {
          msg = 'Ligue o microfone e toque uma nota para ajustar.';
          color = AppColors.textDim;
        } else if (clipping) {
          msg = 'Som alto demais: diminua o ganho.';
          color = AppColors.sharp;
        } else if (d == null || d.rms < minRms) {
          msg = 'Som fraco: aumente o ganho ou chegue mais perto.';
          color = AppColors.sharp;
        } else if (d.reject == PitchReject.none) {
          msg = 'Captação boa.';
          color = AppColors.inTune;
        } else {
          msg = 'Ouvindo… sustente a nota.';
          color = AppColors.textDim;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text('Nível do som', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (!app.listening)
                TextButton.icon(
                  onPressed: app.startListening,
                  icon: const Icon(Icons.mic, size: 18),
                  label: const Text('Ligar'),
                ),
            ]),
            const SizedBox(height: 6),
            SizedBox(
              height: 14,
              child: LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth;
                final good = on && d.rms >= minRms && !clipping;
                return Stack(children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: w * (on ? _pos(d.rms) : 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: good ? AppColors.inTune : (clipping ? AppColors.sharp : AppColors.textDim),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  // Traço do mínimo: o som precisa passar dele para ser reconhecido.
                  Positioned(
                      left: w * _pos(minRms) - 1,
                      top: -1,
                      bottom: -1,
                      child: Container(width: 2.5, color: AppColors.text)),
                ]);
              }),
            ),
            const SizedBox(height: 6),
            Text(msg, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Text('O traço branco é o mínimo que o app precisa ouvir.',
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5)),
          ],
        );
      },
    );
  }
}

/// Escolha da grafia das teclas pretas: Automático (alterna ♯ e ♭ e segue a
/// tonalidade da escala), sempre ♯ ou sempre ♭.
class SpellingPicker extends StatelessWidget {
  final AppState app;
  const SpellingPicker({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final sel = app.spellingAuto ? 0 : (app.preferFlats ? 2 : 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChipGrid(
          labels: const [Text('Automático'), Text('Sustenidos'), Text('Bemóis')],
          selected: sel,
          onSelected: (i) => app.setTuning(
              spellingAuto: i == 0, preferFlats: i == 2 ? true : (i == 1 ? false : null)),
        ),
        const SizedBox(height: 8),
        Text(
          sel == 0
              ? 'Alterna entre sustenidos e bemóis e segue a tonalidade da escala que você escolher.'
              : (sel == 1
                  ? 'As teclas pretas aparecem sempre como sustenido (Lá sustenido, Sol sustenido…).'
                  : 'As teclas pretas aparecem sempre como bemol (Si bemol, Lá bemol…).'),
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ],
    );
  }
}

class LevelBar extends StatelessWidget {
  final double level;
  const LevelBar({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final v = (level * 6).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        minHeight: 4,
        value: v,
        backgroundColor: AppColors.surface2,
        color: AppColors.textDim,
      ),
    );
  }
}

/// Uma opção de [showOptionSheet] / [PickerField].
class OptionItem<T> {
  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;
  const OptionItem(this.value, this.title, {this.subtitle, this.icon});
}

/// Campo de seleção que substitui o menu suspenso padrão: mostra a opção atual
/// e, ao tocar, abre uma folha com cartões grandes e fáceis de tocar.
class PickerField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<OptionItem<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cur = options.firstWhere((o) => o.value == value, orElse: () => options.first);
    return Semantics(
      button: true,
      label: '$label: ${cur.title}. Toque para trocar.',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showOptionSheet<T>(
          context,
          title: label,
          options: options,
          selected: value,
          onPick: onChanged,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(cur.icon ?? icon ?? Icons.music_note, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                    Text(cur.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Icon(Icons.unfold_more, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Folha de seleção com cartões. Fecha ao escolher.
Future<void> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<OptionItem<T>> options,
  required T selected,
  required ValueChanged<T> onPick,
  String? hint,
  bool showIcons = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.outline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Text(title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(hint, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final o = options[i];
                  final sel = o.value == selected;
                  return Material(
                    color: sel ? AppColors.accent.withValues(alpha: 0.16) : AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        onPick(o.value);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: sel ? AppColors.accent : AppColors.outline,
                              width: sel ? 2 : 1),
                        ),
                        child: Row(
                          children: [
                            if (showIcons) ...[
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: (sel ? AppColors.accent : AppColors.textDim)
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(o.icon ?? Icons.music_note,
                                    color: sel ? AppColors.accent : AppColors.textDim),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(o.title,
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w700)),
                                  if (o.subtitle != null)
                                    Text(o.subtitle!,
                                        style: TextStyle(
                                            color: AppColors.textDim, fontSize: 12.5)),
                                ],
                              ),
                            ),
                            if (sel) Icon(Icons.check_circle, color: AppColors.accent),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opções de instrumento para [PickerField]: nome, cordas e tipo de afinação.
List<OptionItem<String>> instrumentOptions(TuningConfig cfg) {
  final plain = cfg.copyWith(transpose: 0);
  return [
    for (final i in instruments)
      OptionItem<String>(
        i.id,
        i.name,
        subtitle:
            '${i.strings.map((s) => noteName(s.midi, plain)).join(' · ')}  |  ${i.fretted ? 'com trastes, afinação igual' : 'sem trastes, quintas puras'}',
        icon: i.fretted ? Icons.music_note : Icons.graphic_eq,
      ),
  ];
}

/// Folha de ajuda com seções (título + texto). Usada nos botões "?".
Future<void> showInfoSheet(BuildContext context, String title, List<(String, String)> sections,
    {String? footer}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.lightbulb_outline, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 14),
              for (final (h, b) in sections) ...[
                Text(h, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(b, style: TextStyle(color: AppColors.textDim, height: 1.35)),
                const SizedBox(height: 14),
              ],
              if (footer != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(footer, style: const TextStyle(height: 1.35)),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendi'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Botão "?" que abre uma folha de ajuda.
class HelpButton extends StatelessWidget {
  final String title;
  final List<(String, String)> sections;
  final String? footer;
  const HelpButton({super.key, required this.title, required this.sections, this.footer});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Ajuda: $title',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
        icon: Icon(Icons.help_outline, size: 20, color: AppColors.textDim),
        onPressed: () => showInfoSheet(context, title, sections, footer: footer),
      );
}

/// Textos de ajuda (um só lugar, para as telas não se contradizerem).
class Help {
  static const modes = <(String, String)>[
    ('Cordas soltas: para AFINAR o instrumento',
        'Você escolhe o instrumento e o app mostra qual corda está soando (por exemplo Sol, Ré, Lá, Mi) e quanto falta para ela ficar certa. Toque a corda solta e gire a cravelha até a agulha ficar no verde. Cada corda tem um botão para ouvir a nota de referência.'),
    ('Cromático: para ESTUDAR',
        'Reconhece qualquer nota (Dó, Dó♯, Ré…) e mostra a afinação dela. Use ao tocar peças e escalas, ou para conferir uma nota apertada com o dedo. Aqui vale o sistema de afinação que você escolheu (igual, pitagórico ou justo).'),
  ];
  static const modesFooter =
      'Em dúvida? Para afinar antes de tocar, use Cordas soltas. Para estudar entonação, use Cromático.';

  static const system = <(String, String)>[
    ('Igual',
        'As 12 notas ficam à mesma distância umas das outras. É a afinação do piano, do violão e da guitarra (os trastes são fixos). Escolha ao tocar junto com piano, teclado ou em instrumentos de trastes.'),
    ('Pitagórico',
        'Constrói as notas com quintas puras (proporção 3:2). A terça maior e a sensível ficam mais altas que no piano, o que deixa as melodias mais brilhantes. É assim que violinistas, violistas e violoncelistas costumam tocar melodias. Escolha ao estudar melodias e escalas em instrumentos de arco.'),
    ('Justo',
        'Mede cada nota contra a tônica por proporções simples (quinta 3:2, terça maior 5:4). Com essas proporções as ondas se encaixam e some o tremor chamado batimento. A terça maior fica mais baixa que no piano e a quinta um pouco mais alta. Escolha para acordes e música em conjunto sem piano: toque a tônica como referência e afine a terça e a quinta contra ela.'),
  ];
  static const systemFooter =
      'Mudar o sistema muda o ALVO de cada nota: a mesma nota pode aparecer "baixa" no Igual e "afinada" no Justo, e isso não é erro do app. Na tabela "Entender" você vê, em Hz, o alvo de cada nota. Se não tiver certeza, use Igual. As cordas soltas não dependem desta opção.';

  static const tonic = <(String, String)>[
    ('Tônica (tom da peça)',
        'É a nota que dá nome ao tom: em Sol maior, a tônica é Sol. Só importa nos sistemas Pitagórico e Justo, porque nesses as notas são afinadas em relação à tônica.'),
    ('Manter o Lá fixo',
        'Ligado: o Lá continua exatamente na referência (por exemplo 440 Hz) e as outras notas se ajustam em torno dele. É o recomendado para instrumentos de arco, que se afinam pelo Lá. Desligado: a tônica fica na afinação igual e o Lá pode mudar um pouco.'),
  ];

  static const refA = <(String, String)>[
    ('Lá de referência',
        'É a altura do Lá que o app usa como base para todas as notas. O padrão é 440 Hz. Algumas orquestras usam 442 ou 443 Hz.'),
    ('Quando mudar',
        'Só mude se o seu grupo, professor ou piano usa outra referência. Com o Lá errado, todas as notas parecem fora do lugar, mesmo com o instrumento certo.'),
  ];
}

/// Recomendação do sistema de afinação conforme o instrumento, com aviso
/// quando a escolha atual pode dar um resultado ruim.
class SystemAdvice extends StatelessWidget {
  final AppState app;
  const SystemAdvice({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final inst = app.instrument;
    final fretted = inst.fretted;
    final sys = app.system;
    String rec;
    String? warn;
    if (fretted) {
      rec = '${inst.name} tem trastes: o recomendado é Igual.';
      if (sys != TuningSystem.equal) {
        warn = 'Com trastes, as notas já saem fixas pelo traste. No Pitagórico/Justo, notas certas vão aparecer como "fora". Prefira Igual.';
      }
    } else {
      rec = '${inst.name} é de arco: Pitagórico para melodias e escalas, Justo para acordes e conjunto.';
      if (sys == TuningSystem.equal) {
        warn = 'No Igual, algumas notas boas do arco (como terças e sensíveis) podem aparecer um pouco "fora". Para estudar melodias, experimente o Pitagórico.';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rec, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
        if (warn != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.sharp.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.sharp.withValues(alpha: 0.6)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.sharp),
                const SizedBox(width: 8),
                Expanded(child: Text(warn, style: const TextStyle(fontSize: 12.5, height: 1.3))),
              ],
            ),
          ),
      ],
    );
  }
}
