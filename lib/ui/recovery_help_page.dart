import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'join_account_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Endereço da página pública de ajuda (a mesma que o site publica).
const String kHelpUrl = 'https://notemusicmap.vercel.app/ajuda';

Future<void> openHelpPage() => launchUrl(Uri.parse(kHelpUrl), mode: LaunchMode.externalApplication);

/// "Perdi meu acesso": os caminhos para voltar à conta, do mais fácil ao último recurso, em linguagem simples.
class RecoveryHelpPage extends StatelessWidget {
  final AppState app;
  const RecoveryHelpPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final ways = <(IconData, String, String)>[
      (Icons.devices_outlined, tr('Tenho o aparelho antigo'), tr('No antigo, toque em Minha conta › Aparelhos e adicione este. Vale 10 minutos.')),
      if (app.emailEnabled)
        (Icons.alternate_email, tr('Liguei um e-mail'), tr('Peça um código de 6 dígitos no e-mail da conta e digite aqui.')),
      (Icons.key, tr('Guardei a chave'), tr('Digite as 25 letras e números da sua chave de recuperação.')),
      (Icons.support_agent_outlined, tr('Não tenho nada disso'), tr('Aluno: peça ao professor para vincular de novo. Professor: fale com o suporte.')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Perdi meu acesso'))),
      body: DsPageSafe(
        child: ListView(
          padding: Ds.screen,
          children: [
            Text(tr('Sem senha, a conta é o seu código. Para entrar em outro aparelho, escolha um destes caminhos.'), style: Ds.support()),
            const SizedBox(height: Ds.gap),
            for (final w in ways)
              Padding(
                padding: const EdgeInsets.only(bottom: Ds.s8),
                child: AppCard(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    DsIconBadge(w.$1, size: 40),
                    const SizedBox(width: Ds.s12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(w.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: Ds.s4),
                        Text(w.$3, style: TextStyle(color: AppColors.textDim, height: 1.35)),
                      ]),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: Ds.s8),
            DsPrimaryButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => JoinAccountPage(app: app))),
              icon: Icons.login,
              label: tr('Entrar na minha conta'),
            ),
            const SizedBox(height: Ds.s8),
            OutlinedButton.icon(
              onPressed: openHelpPage,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(tr('Abrir a ajuda completa')),
            ),
            const SizedBox(height: Ds.gap),
            Text(tr('O suporte nunca pede a sua chave nem o código que chega por e-mail.'), style: Ds.support()),
          ],
        ),
      ),
    );
  }
}
