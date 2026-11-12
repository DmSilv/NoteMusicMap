import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'widgets.dart';

/// Escolha do lembrete de uma aula: com quanto tempo de antecedência o professor e o aluno são avisados.
/// Um campo só (a lista abre num modal), para não pesar o formulário. O padrão é [kReminderMinutes].
class RemindField extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const RemindField({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PickerField<int>(
      label: tr('Lembrete para os dois'),
      value: value,
      icon: value == 0 ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
      options: [
        for (final m in kRemindOptions)
          OptionItem<int>(
            m,
            remindLabel(m),
            subtitle: m == kReminderMinutes ? tr('Padrão') : null,
            icon: m == 0 ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
          ),
      ],
      onChanged: onChanged,
    );
  }
}
