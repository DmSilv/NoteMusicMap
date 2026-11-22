import 'undo_snack.dart';
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

/// Data e hora de uma novidade, no horário do aparelho: "22/11/2026 às 14:32" (em inglês, "11/22/2026 at 14:32").
String newsStamp(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  final day = Lang.isEn ? '${two(d.month)}/${two(d.day)}/${d.year}' : '${two(d.day)}/${two(d.month)}/${d.year}';
  return tr('{0} às {1}', [day, '${two(d.hour)}:${two(d.minute)}']);
}

/// A linha de quando saiu: o relógio e a data com hora, e o "há quanto tempo" ao lado.
Widget _newsWhen(NewsItem n, {bool strong = false}) {
  if (n.publishedMs <= 0) return const SizedBox.shrink();
  return Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.schedule_rounded, size: 15, color: AppColors.textDim),
    const SizedBox(width: Ds.s4),
    Flexible(
      child: Text(
        '${newsStamp(n.publishedMs)} · ${noticeAgo(n.publishedMs)}',
        style: TextStyle(color: strong ? AppColors.text : AppColors.textDim, fontSize: strong ? 13.5 : 12.5, fontWeight: strong ? FontWeight.w600 : FontWeight.w400),
      ),
    ),
  ]);
}

/// Uma novidade inteira em TELA CHEIA: ícone, quando saiu (data e hora), título, o rótulo de feedback (se houver) e o texto por
/// completo, com o botão "Entendi" fixo embaixo. Marca como vista ao abrir. Serve para a novidade em destaque (abre sozinha) e para a
/// que a pessoa abre na central.
Future<void> showNewsDialog(BuildContext context, AppState app, NewsItem n) {
  app.markNewsSeen(n);
  return Navigator.of(context).push<void>(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (c) => Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: tr('Fechar'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(c).pop()),
        title: Text(tr('Novidade')),
      ),
      body: DsPageSafe(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s16, Ds.screenPad, Ds.s24),
              children: [
                Row(children: [
                  DsIconBadge(Icons.campaign_outlined, size: 48, color: AppColors.info),
                  const SizedBox(width: Ds.s12),
                  Expanded(child: n.publishedMs > 0 ? _newsWhen(n, strong: true) : Text(tr('Novidade'), style: Ds.support())),
                ]),
                const SizedBox(height: Ds.s20),
                Text(n.shownTitle, style: Ds.title().copyWith(fontSize: 26, height: 1.2)),
                if (n.feedback.isNotEmpty) ...[
                  const SizedBox(height: Ds.s12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Ds.s12, vertical: Ds.s8),
                    decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Text(newsFeedbackLabel(n), style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: Ds.s16),
                Divider(color: AppColors.outline, height: 1),
                const SizedBox(height: Ds.s16),
                Text(n.shownBody, style: TextStyle(height: 1.55, fontSize: 16.5, color: AppColors.text)),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s8, Ds.screenPad, Ds.s12),
              child: DsPrimaryButton(onPressed: () => Navigator.of(c).pop(), icon: Icons.check_rounded, label: tr('Entendi')),
            ),
          ),
        ]),
      ),
    ),
  ));
}

/// A central de novidades: um cartão por novidade (a mais nova primeiro), com o sinal de "não lida", a data e a hora em que saiu e
/// o começo do texto. Tocar abre a novidade inteira. Fica separada do sino, que é só de avisos que pedem ação.
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
          padding: const EdgeInsets.only(bottom: Ds.s12),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(Ds.radiusCard),
              onTap: () => showNewsDialog(context, app, n),
              child: Padding(
                padding: const EdgeInsets.all(Ds.s16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DsIconBadge(Icons.campaign_outlined, size: 44, color: app.isNewsSeen(n) ? AppColors.textDim : AppColors.info),
                  const SizedBox(width: Ds.s12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _newsWhen(n),
                      const SizedBox(height: Ds.s8),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Text(n.shownTitle, style: TextStyle(fontWeight: app.isNewsSeen(n) ? FontWeight.w600 : FontWeight.w800, fontSize: 17, height: 1.25))),
                        if (!app.isNewsSeen(n))
                          Container(
                            margin: const EdgeInsets.only(left: Ds.s8, top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
                            child: Text(tr('Nova'), style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w800, fontSize: 11.5)),
                          ),
                      ]),
                      const SizedBox(height: Ds.s8),
                      Text(n.shownBody, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.4)),
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

/// A central de novidades em TELA CHEIA (vem do ícone da barra de cima). Abrir a tela não marca nada como visto: quem marca é
/// abrir cada novidade.
Future<void> showNewsSheet(BuildContext context, AppState app) {
  // Abrir a central já apaga o laranja do sino: a pessoa viu que há novidade.
  app.markNewsPeeked();
  return Navigator.of(context).push<void>(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (c) => Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: tr('Fechar'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(c).pop()),
        title: Text(tr('Novidades')),
      ),
      body: DsPageSafe(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s16, Ds.screenPad, Ds.s32),
            children: [
              if (app.news.any((n) => !app.isNewsSeen(n)))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      final seen = app.newsSeenIds, peek = app.newsPeekMs;
                      dismissWithUndo(c,
                          message: tr('Todas as novidades marcadas como lidas.'),
                          undoLabel: tr('Desfazer'),
                          action: app.markAllNewsSeen,
                          undo: () => app.restoreNewsSeen(seen, peek));
                    },
                    icon: const Icon(Icons.done_all_rounded, size: 20),
                    label: Text(tr('Marcar todas como lidas')),
                  ),
                ),
              NewsTiles(app: app),
            ],
          ),
        ),
      ),
    ),
  ));
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
        final fresh = app.newsBellFresh;
        final still = MediaQuery.of(context).disableAnimations;
        if (fresh && !still) {
          if (!_c.isAnimating) _c.repeat();
        } else if (_c.isAnimating || _c.value != 0) {
          _c.stop();
          _c.value = 0;
        }
        final icon = Icon(Icons.campaign_outlined, size: 22, color: fresh ? AppColors.info : AppColors.text);
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
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.info, width: 2)),
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
