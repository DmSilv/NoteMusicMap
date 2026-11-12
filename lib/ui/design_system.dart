import 'package:flutter/material.dart';

import 'theme.dart';

/// Design system do Notemusic. REGRA: toda tela nova ou alterada usa estes valores e estes
/// componentes (ver docs/12_DESIGN_SYSTEM.md). Números soltos de espaçamento, raio ou altura de
/// botão não entram em tela nova.
///
/// Princípios:
/// 1. Primeira tela = só o essencial e a ação principal, visíveis sem rolar.
/// 2. Configuração e alteração ficam em modal ([showDsSheet]), abertas por [DsSettingsButton].
/// 3. Texto explicativo longo vai para o "?" (HelpButton), não para a tela.
/// 4. Avisos e sugestões vão para o sino, não ficam presos no topo.
class Ds {
  Ds._();

  // Escala de espaçamento (base 8).
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  /// Margem lateral das telas.
  static const double screenPad = 16;

  /// Espaço dentro de um cartão.
  static const double cardPad = 18;

  /// Espaço entre cartões/blocos da mesma tela.
  static const double gap = 16;

  /// Espaço entre seções diferentes.
  static const double sectionGap = 24;

  /// Alvo de toque mínimo (botões e linhas tocáveis).
  static const double tap = 48;

  /// Altura do botão de ação principal.
  static const double primaryHeight = 56;

  /// Raios.
  static const double radiusCard = 20;
  static const double radiusControl = 12;

  /// Margem padrão de uma tela rolável.
  static const EdgeInsets screen = EdgeInsets.fromLTRB(screenPad, s12, screenPad, s24);

  // Tipografia (tamanhos mínimos para o celular).
  static const double fontBody = 16;
  static const double fontSupport = 14;
  static const double fontLabel = 13;
  static const double fontTitle = 20;

  static TextStyle title() => const TextStyle(fontSize: fontTitle, fontWeight: FontWeight.w800);
  static TextStyle section() => TextStyle(fontSize: fontSupport, fontWeight: FontWeight.w700, color: AppColors.textDim);
  static TextStyle support() => TextStyle(fontSize: fontSupport, color: AppColors.textDim, height: 1.35);
}

/// Ícone dentro de um quadrado arredondado com fundo suave (mais bonito que o ícone solto).
class DsIconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  const DsIconBadge(this.icon, {super.key, this.size = 40, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, color: c, size: size * 0.55),
    );
  }
}

/// Espaço vertical padrão entre blocos.
class DsGap extends StatelessWidget {
  final double h;
  const DsGap(this.h, {super.key});
  const DsGap.section({super.key}) : h = Ds.sectionGap;
  const DsGap.small({super.key}) : h = Ds.s8;

  @override
  Widget build(BuildContext context) => SizedBox(height: h);
}

/// Botão "Ajustes" que abre o modal de configuração da tela (ícone de controles).
class DsSettingsButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  const DsSettingsButton({super.key, required this.onPressed, this.label = 'Ajustes'});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(Ds.tap, Ds.tap), padding: const EdgeInsets.symmetric(horizontal: Ds.s16)),
        onPressed: onPressed,
        icon: const Icon(Icons.tune, size: 20),
        label: Text(label),
      );
}

/// Botão de ação principal da tela: largo e alto, sempre à vista.
class DsPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  const DsPrimaryButton({super.key, required this.onPressed, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: Ds.primaryHeight,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          onPressed: onPressed,
          icon: Icon(icon, size: 24),
          label: Text(label),
        ),
      );
}

/// Linha de configuração dentro de um modal: título, valor atual e o controle à direita.
class DsSettingRow extends StatelessWidget {
  final String label;
  final Widget child;
  const DsSettingRow({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Ds.sectionGap),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Ds.section()),
          const SizedBox(height: Ds.s8),
          child,
        ]),
      );
}

/// Abre o modal de ajustes: sobe de baixo, você altera e toca em "Concluir" para voltar.
/// [listenable] reconstrói o conteúdo quando o estado muda (ex.: o próprio AppState).
Future<void> showDsSheet(
  BuildContext context, {
  required String title,
  required Listenable listenable,
  required List<Widget> Function(BuildContext) children,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.s12, Ds.s8),
          child: Row(children: [
            Expanded(child: Text(title, style: Ds.title())),
            TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Concluir')),
          ]),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListenableBuilder(
            listenable: listenable,
            builder: (c, _) => ListView(
              padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s20, Ds.screenPad, Ds.s32),
              shrinkWrap: true,
              children: children(c),
            ),
          ),
        ),
      ]),
    ),
  );
}

/// Linha de navegação de uma lista de ajustes: ícone, título, valor atual e seta. Abre um modal ou uma tela.
/// [alert] pinta um pontinho (algo pede atenção).
class DsNavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool alert;
  const DsNavRow(this.icon, this.title, this.subtitle, this.onTap, {super.key, this.alert = false});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Ds.s16, vertical: Ds.s8),
            child: Row(children: [
              DsIconBadge(icon, size: 36),
              const SizedBox(width: Ds.s12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: Ds.fontBody, fontWeight: FontWeight.w700)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: Ds.fontLabel, color: AppColors.textDim)),
                ]),
              ),
              if (alert) Container(width: 8, height: 8, margin: const EdgeInsets.only(right: Ds.s8), decoration: BoxDecoration(color: AppColors.sharp, shape: BoxShape.circle)),
              Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
            ]),
          ),
        ),
      );
}

/// Campo tocável de dia ou hora: o rótulo pequeno em cima e o valor em destaque.
class DsPickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const DsPickTile({super.key, required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      label: '$label: $value. Toque para mudar.',
      child: InkWell(
        borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Ds.primaryHeight + 4),
          padding: const EdgeInsets.symmetric(horizontal: Ds.s12, vertical: Ds.s8),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
            border: Border.all(color: AppColors.outline),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            const SizedBox(height: 2),
            Row(children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: Ds.s8),
              Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
            ]),
          ]),
        ),
      ),
    );
  }
}
