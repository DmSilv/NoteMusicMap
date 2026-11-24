import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';
import 'package:afina_core/afina_core.dart';

/// "Como funciona a sua conta": explica, em quatro blocos curtos, que a pessoa já tem uma conta mesmo sem cadastro,
/// o que fica no celular, o que a chave faz e como entrar em outro aparelho.
Future<void> showAccountExplainer(BuildContext context, AppState app, {required VoidCallback onKey, required VoidCallback onJoin}) {
  Widget block(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: Ds.s16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsIconBadge(icon, size: 40),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              const SizedBox(height: Ds.s4),
              Text(body, style: Ds.support()),
            ]),
          ),
        ]),
      );
  return showDsSheet(context, title: tr('Como funciona a sua conta'), listenable: app, children: (c) {
    final pending = app.keyPending;
    final hasEmail = app.emailHint.isNotEmpty;
    return [
      Text(tr('Você não precisa de e-mail nem senha. O app já criou a sua conta neste aparelho.'), style: Ds.support()),
      const SizedBox(height: Ds.s16),
      block(Icons.badge_outlined, tr('O seu código é você'), tr('O código {0} identifica a sua conta. É com ele (ou o QR) que professor e aluno se vinculam. Ele não é uma senha: sozinho, não dá acesso a nada.', [app.profile.shareCode])),
      block(
        Icons.phone_iphone_rounded,
        tr('O que fica no celular'),
        app.teacherMode
            ? tr('O histórico de estudo, as fichas e as anotações dos seus alunos ficam só neste aparelho. O servidor guarda o código, o apelido, os vínculos e o que você envia ao aluno (aulas, tarefas e agenda).')
            : tr('O seu histórico de estudo e as suas anotações ficam só neste aparelho. O servidor guarda o código, o apelido, os vínculos e o que o professor envia a você (aulas, tarefas e agenda).'),
      ),
      block(
        Icons.key_rounded,
        tr('A chave traz a conta de volta'),
        hasEmail
            ? tr('Se perder o celular, entre em outro aparelho com o seu e-mail ou com a chave de recuperação. Volta o seu código e os vínculos, mas não o que ficou só no celular.')
            : tr('Se perder o celular, a chave de recuperação traz de volta o seu código e os vínculos em outro aparelho. O que ficou só no celular não volta. Sem a chave, só o suporte consegue ajudar.'),
      ),
      block(Icons.devices_outlined, tr('Mais de um aparelho'), tr('Você pode usar a mesma conta em até {0} aparelhos. No outro aparelho, escolha "Já tenho conta" e use a chave.', [app.maxDevices])),
      Container(
        padding: const EdgeInsets.all(Ds.s12),
        decoration: BoxDecoration(
          color: (pending ? AppColors.attention : AppColors.accent).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
          border: Border.all(color: (pending ? AppColors.attention : AppColors.accent).withValues(alpha: 0.55)),
        ),
        child: Row(children: [
          Icon(pending ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: pending ? AppColors.attention : AppColors.accent),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: Text(
              pending ? tr('Você ainda não guardou a sua chave.') : (hasEmail ? tr('Sua conta está protegida pelo e-mail.') : tr('Sua chave está guardada.')),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
      const SizedBox(height: Ds.s12),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
        onPressed: () {
          Navigator.of(c).pop();
          onKey();
        },
        icon: const Icon(Icons.key_rounded),
        label: Text(pending ? tr('Guardar a minha chave') : tr('Ver a minha chave')),
      ),
      const SizedBox(height: Ds.s8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
        onPressed: () {
          Navigator.of(c).pop();
          onJoin();
        },
        icon: const Icon(Icons.login),
        label: Text(tr('Já tenho conta em outro aparelho')),
      ),
    ];
  });
}
