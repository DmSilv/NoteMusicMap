import 'package:flutter/material.dart';

import 'design_system.dart';
import 'theme.dart';

/// Pergunta antes de fechar o app (botão voltar na tela principal). Devolve true só se a pessoa tocar em "Sair do app":
/// tocar fora, arrastar para baixo ou apertar voltar de novo significa FICAR. O botão grande e destacado é o de ficar;
/// sair é um texto discreto (um toque por engano no voltar nunca fecha o app).
Future<bool> confirmExitApp(BuildContext context) async {
  final leave = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true, // sem o teto de altura padrão: em tela baixa (celular deitado) a folha rola em vez de estourar
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s4, Ds.screenPad, Ds.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DsIconBadge(Icons.waving_hand_rounded, size: 56, color: AppColors.sharp),
          const SizedBox(height: Ds.s16),
          Text('Já vai embora?', textAlign: TextAlign.center, style: Ds.title().copyWith(fontSize: 22)),
          const SizedBox(height: Ds.s8),
          Text(
            'Se estiver tocando ou estudando, o app para de ouvir.',
            textAlign: TextAlign.center,
            style: Ds.support().copyWith(fontSize: 15),
          ),
          const SizedBox(height: Ds.s24),
          DsPrimaryButton(onPressed: () => Navigator.of(c).pop(false), icon: Icons.check_rounded, label: 'Continuar no app'),
          const SizedBox(height: Ds.s8),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(Ds.tap),
              foregroundColor: AppColors.textDim,
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Sair do app'),
          ),
        ],
      ),
    ),
  );
  return leave == true;
}
