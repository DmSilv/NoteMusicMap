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
          Wrap(spacing: 6, children: [
            for (final s in MicSensitivity.values)
              ChoiceChip(
                label: Text(s.label),
                selected: app.sensitivity == s,
                onSelected: (_) => app.setMic(sensitivity: s),
              ),
          ]),
          const SizedBox(height: 4),
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

/// Diagnóstico ao vivo da captação: mostra o nível do sinal contra o mínimo que
/// o detector exige, a clareza do som, o pico (distorção) e por que uma nota foi
/// aceita ou recusada. Serve para ajustar o ganho e a sensibilidade com o
/// instrumento na mão.
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
        final minClar = app.sensitivity.minClarity;
        final on = app.listening && d != null;
        final clipping = app.diagPeakHold >= 0.98;
        final nf = app.noiseFloor;

        String status;
        Color statusColor;
        if (!app.listening) {
          status = 'Microfone desligado';
          statusColor = AppColors.textDim;
        } else if (d == null) {
          status = 'Aguardando som…';
          statusColor = AppColors.textDim;
        } else if (d.reject == PitchReject.none) {
          status = 'Nota reconhecida';
          statusColor = AppColors.inTune;
        } else {
          status = 'Recusado: ${d.reject.label}';
          statusColor = AppColors.sharp;
        }

        String tip = '';
        if (on && d.reject == PitchReject.quiet) {
          tip = 'O som está abaixo do mínimo. Aumente o ganho ou chegue mais perto.';
        } else if (on && d.reject == PitchReject.unclear) {
          tip = 'Há som, mas pouco limpo. Reduza o ruído do ambiente ou escolha "Livre".';
        } else if (on && d.reject == PitchReject.noPeak) {
          tip = 'Som sem altura definida (ruído ou ataque do arco). Sustente a nota.';
        }
        if (clipping) tip = 'O sinal está estourando (distorção). Reduza o ganho.';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.monitor_heart_outlined, size: 18, color: AppColors.textDim),
              const SizedBox(width: 6),
              const Text('Diagnóstico ao vivo', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (!app.listening)
                TextButton.icon(
                  onPressed: app.startListening,
                  icon: const Icon(Icons.mic, size: 18),
                  label: const Text('Ligar'),
                ),
            ]),
            const SizedBox(height: 6),
            Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
            if (on && d.freq > 0)
              Text(
                'Altura achada: ${d.freq.toStringAsFixed(1).replaceAll('.', ',')} Hz · '
                'clareza ${(d.clarity * 100).round()}%',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
            const SizedBox(height: 10),
            _meter(
              label: 'Nível',
              value: on ? _pos(d.rms) : 0,
              mark: _pos(minRms),
              mark2: nf == null ? null : _pos(nf),
              ok: on && d.rms >= minRms,
              right: on ? '${_db(d.rms).round()} dB' : '—',
              note: 'mínimo ${_db(minRms).round()} dB'
                  '${nf == null ? '' : ' · ruído ${_db(nf).round()} dB'}',
            ),
            const SizedBox(height: 8),
            _meter(
              label: 'Clareza',
              value: on ? d.clarity : 0,
              mark: minClar,
              ok: on && d.clarity >= minClar,
              right: on ? '${(d.clarity * 100).round()}%' : '—',
              note: 'mínimo ${(minClar * 100).round()}%',
            ),
            const SizedBox(height: 8),
            _meter(
              label: 'Pico',
              value: app.diagPeakHold.clamp(0.0, 1.0),
              mark: 0.98,
              ok: !clipping,
              right: clipping ? 'estourando' : 'ok',
              note: 'não passe do traço (distorce)',
            ),
            const SizedBox(height: 8),
            Text(
              'Notas reconhecidas nos últimos instantes: ${(app.diagRate * 100).round()}%',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
            if (app.recentRuns.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Últimas notas ouvidas',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in app.recentRuns)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: r.kept ? AppColors.surface2 : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: r.kept ? AppColors.inTune.withValues(alpha: 0.6) : AppColors.outline),
                    ),
                    child: Text(
                      '${noteName(r.midi, app.cfg, withOctave: true)} '
                      '${(r.seconds * 1000).round()} ms · ${(r.clarity * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: r.kept ? AppColors.text : AppColors.textDim,
                        decoration: r.kept ? null : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(
                'Riscadas = curtas demais (menos de ${(app.minNoteSeconds * 1000).round()} ms): '
                'não entram na grade nem no placar.',
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
              ),
            ],
            if (tip.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(tip, style: TextStyle(color: AppColors.sharp, fontSize: 12.5)),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: app.listening && !app.probingNoise ? app.startNoiseProbe : null,
              icon: const Icon(Icons.graphic_eq, size: 18),
              label: Text(app.probingNoise
                  ? 'Medindo o ruído… fique em silêncio'
                  : (nf == null ? 'Medir o ruído do ambiente (2 s)' : 'Medir o ruído de novo')),
            ),
            if (nf != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  minRms < nf * 1.5
                      ? 'O nível mínimo está colado no ruído do ambiente: o app pode tratar ruído como nota.'
                      : 'Folga entre o ruído e o mínimo: ${(_db(minRms) - _db(nf)).round()} dB.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _meter({
    required String label,
    required double value,
    required double mark,
    double? mark2,
    required bool ok,
    required String right,
    required String note,
  }) {
    final color = ok ? AppColors.inTune : AppColors.textDim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          Text(right, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: 14,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            return Stack(children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: w * value.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
              if (mark2 != null)
                Positioned(
                    left: w * mark2 - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: AppColors.flat)),
              Positioned(
                  left: w * mark - 1,
                  top: -1,
                  bottom: -1,
                  child: Container(width: 2.5, color: AppColors.text)),
            ]);
          }),
        ),
        const SizedBox(height: 2),
        Text(note, style: TextStyle(color: AppColors.textDim, fontSize: 11.5)),
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
        'As 12 notas são equidistantes. É a afinação do piano, do violão e da guitarra (os trastes são fixos). Escolha ao tocar junto com piano/teclado ou em instrumentos de trastes.'),
    ('Pitagórico',
        'Baseado em quintas puras. As notas de melodia ficam um pouco mais "brilhantes" (a terça maior sobe cerca de 8 cents e a sensível chega mais perto da tônica). É assim que violinistas, violistas e violoncelistas costumam tocar melodias. Escolha ao estudar melodias e escalas em instrumentos de arco.'),
    ('Justo',
        'Intervalos puros, pensados para acordes (a terça maior fica cerca de 14 cents mais baixa que na afinação igual). Soa mais "limpo" em acordes e em duos ou quartetos de cordas sem piano.'),
  ];
  static const systemFooter =
      'Mudar o sistema muda o ALVO de cada nota: a mesma nota pode aparecer "baixa" no igual e "afinada" no justo. Não é erro do app. Se não tiver certeza, use Igual. As cordas soltas não dependem desta opção.';

  static const tonic = <(String, String)>[
    ('Tônica (tom da peça)',
        'É a nota que dá nome ao tom: em Sol maior, a tônica é Sol. Só importa nos sistemas Pitagórico e Justo, porque nesses as notas são afinadas em relação à tônica.'),
    ('Manter o Lá fixo',
        'Ligado: o Lá continua exatamente na referência (por exemplo 440 Hz) e as outras notas se ajustam em torno dele. É o recomendado para instrumentos de arco, que se afinam pelo Lá. Desligado: a tônica fica na afinação igual e o Lá pode mudar alguns cents.'),
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
        warn = 'No Igual, algumas notas boas do arco (como terças e sensíveis) podem aparecer alguns cents "fora". Para estudar melodias, experimente o Pitagórico.';
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
