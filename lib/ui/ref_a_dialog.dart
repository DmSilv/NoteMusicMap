import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'theme.dart';

/// Atalhos comuns para o Lá de referência (Hz).
const List<(double, String)> kRefAPresets = [
  (392, 'Barroco francês'),
  (415, 'Barroco'),
  (430, 'Clássico'),
  (432, '432'),
  (440, 'Padrão'),
  (442, 'Orquestras'),
  (443, 'Orquestras'),
  (445, 'Brilhante'),
];

/// Janela para digitar o Lá de referência ou escolher um atalho.
Future<void> showRefADialog(BuildContext context, AppState app) async {
  final ctl = TextEditingController(text: _fmt(app.refA));
  final v = await showDialog<double>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) {
        final typed = double.tryParse(ctl.text.replaceAll(',', '.'));
        final ok = typed != null && typed >= 380 && typed <= 480;
        return AlertDialog(
          title: const Text('Lá de referência'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Frequência do Lá4 (Hz)',
                    suffixText: 'Hz',
                    helperText: 'Entre 380 e 480 Hz',
                    errorText: ok ? null : 'Digite um valor entre 380 e 480',
                  ),
                  onChanged: (_) => setS(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final p in kRefAPresets)
                    ActionChip(
                      label: Text('${_fmt(p.$1)} · ${p.$2}'),
                      onPressed: () => setS(() => ctl.text = _fmt(p.$1)),
                    ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
            FilledButton.icon(
              onPressed: ok ? () => Navigator.pop(c, typed) : null,
              icon: const Icon(Icons.check, size: 18), label: const Text('Aplicar'),
            ),
          ],
        );
      },
    ),
  );
  ctl.dispose();
  if (v != null) app.setTuning(refA: v);
}

String _fmt(double hz) => hz == hz.roundToDouble() ? hz.round().toString() : hz.toStringAsFixed(1);

/// Chip "Outro…" que mostra o valor quando não é um dos atalhos fixos.
Widget refAOtherChip(BuildContext context, AppState app, List<double> fixed) {
  final custom = !fixed.contains(app.refA);
  return ChoiceChip(
    avatar: Icon(Icons.edit, size: 16, color: AppColors.text),
    label: Text(custom ? '${_fmt(app.refA)} Hz' : 'Outro…'),
    selected: custom,
    onSelected: (_) => showRefADialog(context, app),
  );
}
