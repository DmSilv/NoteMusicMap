import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'notifications_sheet.dart' show noticeAgo;
import 'theme.dart';
import 'widgets.dart' show AppCard;

/// Rótulo de uma novidade que veio de feedback; só cita o apelido se a pessoa aceitou (senão, "um usuário").
String newsFeedbackLabel(NewsItem n) {
  final who = n.credit.isEmpty ? tr('um usuário') : n.credit;
  return n.feedback == 'fix' ? tr('Correção feita a partir do feedback de {0}', [who]) : tr('Sugestão de {0} que virou melhoria', [who]);
}

/// Uma novidade inteira numa folha que sobe de baixo (e rola se o texto for longo): ícone, quando saiu, título, o rótulo de
/// feedback (se houver) e o texto por completo. Marca como vista ao abrir. Serve para a novidade em destaque (sobe sozinha)
/// e para a que a pessoa abre na central.
Future<void> showNewsDialog(BuildContext context, AppState app, NewsItem n) {
  app.markNewsSeen(n);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s4, Ds.screenPad, Ds.s16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            DsIconBadge(Icons.campaign_outlined, size: 44, color: AppColors.accent),
            const SizedBox(width: Ds.s12),
            Expanded(
              child: Text(
                n.publishedMs > 0 ? tr('Novidade · {0}', [noticeAgo(n.publishedMs)]) : tr('Novidade'),
                style: Ds.support(),
              ),
            ),
            IconButton(tooltip: tr('Fechar'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(c).pop()),
          ]),
          const SizedBox(height: Ds.s12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.shownTitle, style: Ds.title().copyWith(fontSize: 24, height: 1.2)),
                if (n.feedback.isNotEmpty) ...[
                  const SizedBox(height: Ds.s8),
                  Text(newsFeedbackLabel(n), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13)),
                ],
                const SizedBox(height: Ds.s12),
                Text(n.shownBody, style: TextStyle(height: 1.5, fontSize: 16, color: AppColors.text)),
              ]),
            ),
          ),
          const SizedBox(height: Ds.s16),
          DsPrimaryButton(onPressed: () => Navigator.of(c).pop(), icon: Icons.check_rounded, label: tr('Entendi')),
        ]),
      ),
    ),
  );
}

/// A central de novidades: um cartão por novidade (a mais nova primeiro), com o sinal de "não lida", o quando saiu e o começo do
/// texto. Tocar abre a novidade inteira. Fica separada do sino, que é só de avisos que pedem ação.
class NewsTiles extends StatelessWidget {
  final AppState app;
  const NewsTiles({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final list = app.news;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Ds.s24),
        child: Text(tr('Nenhuma novidade por enquanto. Quando o app ganhar algo, aparece aqui.'), textAlign: TextAlign.center, style: Ds.support()),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final n in list)
        Padding(
          padding: const EdgeInsets.only(bottom: Ds.s8),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(Ds.radiusCard),
              onTap: () => showNewsDialog(context, app, n),
              child: Padding(
                padding: const EdgeInsets.all(Ds.s16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DsIconBadge(Icons.campaign_outlined, size: 40, color: app.isNewsSeen(n) ? AppColors.textDim : AppColors.accent),
                  const SizedBox(width: Ds.s12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(n.shownTitle, style: TextStyle(fontWeight: app.isNewsSeen(n) ? FontWeight.w600 : FontWeight.w800, fontSize: 16, height: 1.2))),
                        if (!app.isNewsSeen(n)) Icon(Icons.circle, size: 9, color: AppColors.accent),
                      ]),
                      const SizedBox(height: Ds.s4),
                      Text(n.shownBody, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 13.5, height: 1.35)),
                      if (n.publishedMs > 0) ...[
                        const SizedBox(height: Ds.s8),
                        Text(noticeAgo(n.publishedMs), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// A central de novidades numa folha alta (vem do ícone da barra de cima). Abrir a folha não marca nada como visto: quem marca é
/// abrir cada novidade.
Future<void> showNewsSheet(BuildContext context, AppState app) {
  return showDsSheet(
    context,
    title: tr('Novidades'),
    listenable: app,
    children: (c) => [NewsTiles(app: app)],
  );
}

/// O ícone de novidades na barra de cima, ao lado dos avisos. Só existe quando há novidade publicada. Enquanto há uma
/// que a pessoa ainda não viu, ele chama atenção: um anel que pulsa e o ícone que balança de leve (parado se o aparelho
/// pede menos movimento).
class NewsBell extends StatefulWidget {
  final AppState app;
  final Widget Function(Widget child) wrap;
  const NewsBell({super.key, required this.app, required this.wrap});

  @override
  State<NewsBell> createState() => _NewsBellState();
}

class _NewsBellState extends State<NewsBell> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (app.news.isEmpty) return const SizedBox.shrink();
        final fresh = app.news.any((n) => !app.isNewsSeen(n));
        final still = MediaQuery.of(context).disableAnimations;
        if (fresh && !still) {
          if (!_c.isAnimating) _c.repeat();
        } else if (_c.isAnimating || _c.value != 0) {
          _c.stop();
          _c.value = 0;
        }
        final icon = Icon(Icons.campaign_outlined, size: 22, color: fresh ? AppColors.accent : AppColors.text);
        return IconButton(
          tooltip: fresh ? tr('Novidade no app') : tr('Novidades'),
          onPressed: () => showNewsSheet(context, app),
          icon: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = _c.value;
              // balança no começo de cada volta e fica quieto o resto; o anel cresce e some
              final wiggle = t < 0.25 ? math.sin(t / 0.25 * math.pi * 4) * 0.22 * (1 - t / 0.25) : 0.0;
              return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                if (fresh && !still)
                  Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0) * 0.7,
                    child: Container(
                      width: 36 + 14 * t,
                      height: 36 + 14 * t,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.accent, width: 2)),
                    ),
                  ),
                widget.wrap(Transform.rotate(angle: wiggle, child: child)),
                if (fresh)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.sharp, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 1.5))),
                  ),
              ]);
            },
            child: icon,
          ),
        );
      },
    );
  }
}
