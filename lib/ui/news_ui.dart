import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';

/// Rótulo de uma novidade que veio de feedback; só cita o apelido se a pessoa aceitou (senão, "um usuário").
String newsFeedbackLabel(NewsItem n) {
  final who = n.credit.isEmpty ? tr('um usuário') : n.credit;
  return n.feedback == 'fix' ? tr('Correção feita a partir do feedback de {0}', [who]) : tr('Sugestão de {0} que virou melhoria', [who]);
}

/// Uma novidade do boletim num aviso pequeno: título, texto curto e um botão só. Marca como vista ao abrir.
Future<void> showNewsDialog(BuildContext context, AppState app, NewsItem n) {
  app.markNewsSeen(n);
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.campaign_outlined, color: AppColors.accent, size: 32),
      title: Text(n.shownTitle, textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (n.feedback.isNotEmpty) ...[
            Text(newsFeedbackLabel(n), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: Ds.s8),
          ],
          Text(n.shownBody, style: TextStyle(height: 1.4, color: AppColors.textDim)),
        ])),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('Entendi')))],
    ),
  );
}

/// "Novidades" dentro da central de avisos: as que estão publicadas, a mais nova primeiro. Toque abre a novidade.
class NewsTiles extends StatelessWidget {
  final AppState app;
  /// [header] = o título "Novidades" acima da lista (a folha própria já tem esse título).
  final bool header;
  const NewsTiles({super.key, required this.app, this.header = true});

  @override
  Widget build(BuildContext context) {
    final list = app.news;
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (header) Padding(padding: const EdgeInsets.only(bottom: Ds.s4), child: Text(tr('Novidades'), style: Ds.section())),
      for (final n in list)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.campaign_outlined, color: app.isNewsSeen(n) ? AppColors.textDim : AppColors.accent),
          title: Text(n.shownTitle, style: TextStyle(fontWeight: app.isNewsSeen(n) ? FontWeight.w500 : FontWeight.w800, height: 1.25)),
          subtitle: Text(n.shownBody, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          trailing: app.isNewsSeen(n) ? null : Icon(Icons.circle, size: 9, color: AppColors.accent),
          onTap: () => showNewsDialog(context, app, n),
        ),
      const SizedBox(height: Ds.s12),
    ]);
  }
}

/// A lista de novidades numa folha (vem do ícone da barra de cima). Abrir a folha não marca nada como visto: quem marca é abrir cada novidade.
Future<void> showNewsSheet(BuildContext context, AppState app) {
  return showDsSheet(
    context,
    title: tr('Novidades'),
    listenable: app,
    children: (c) => [NewsTiles(app: app, header: false)],
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
