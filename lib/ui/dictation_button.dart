import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../voice/dictation.dart';
import 'theme.dart';
import 'package:afina_core/afina_core.dart';

/// Botão de microfone para ditar num campo de texto. Use como `suffixIcon` do `InputDecoration`.
/// Parado: microfone. Preparando: roda um indicador. Ouvindo: círculo vermelho que pulsa com o ícone de parar (tocar de novo
/// para). O aviso completo (ouvindo, volume, tempo, por que parou) é a faixa [DictationPill], igual em todos os campos.
class DictationButton extends StatelessWidget {
  final AppState app;
  final TextEditingController controller;
  const DictationButton({super.key, required this.app, required this.controller});

  Future<void> _tap(BuildContext context) async {
    final d = app.dictation;
    if (!d.consented && !d.isListening(controller)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.mic),
          title: Text(tr('Escrever falando')),
          content: Text(
              tr('Toque no microfone de um campo e fale: o texto aparece escrito. Quem transforma a voz em texto é o serviço de voz do seu aparelho ou do navegador (por exemplo, o do Google ou o da Apple), que pode usar a internet. O Notemusic não grava nem guarda o áudio.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Agora não'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Entendi, usar'))),
          ],
        ),
      );
      if (ok != true) return;
      await d.setConsent(true);
    }
    await d.toggle(controller);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.dictation,
      builder: (context, _) {
        final d = app.dictation;
        final busy = d.isBusy(controller);
        final starting = busy && d.phase == DictationPhase.starting;
        return IconButton(
          tooltip: busy ? tr('Parar de ouvir') : tr('Escrever falando'),
          icon: starting
              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.sharp))
              : (busy ? const _ListeningDot() : Icon(Icons.mic_none, color: AppColors.textDim)),
          onPressed: () => _tap(context),
        );
      },
    );
  }
}

/// O botão enquanto ouve: círculo vermelho com o ícone de parar e um anel que pulsa.
class _ListeningDot extends StatefulWidget {
  const _ListeningDot();

  @override
  State<_ListeningDot> createState() => _ListeningDotState();
}

class _ListeningDotState extends State<_ListeningDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: 34,
      height: 34,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = still ? 0.0 : _c.value;
          return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            if (!still)
              Opacity(
                opacity: (1 - t) * 0.6,
                child: Container(width: 26 + 12 * t, height: 26 + 12 * t, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.sharp, width: 2))),
              ),
            Container(width: 26, height: 26, decoration: BoxDecoration(color: AppColors.sharp, shape: BoxShape.circle), child: Icon(Icons.stop_rounded, size: 17, color: readableOn(AppColors.sharp))),
          ]);
        },
      ),
    );
  }
}

String _mmss(int ms) {
  final s = (ms / 1000).ceil().clamp(0, 5999);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// A faixa de voz: aparece acima do teclado, igual em qualquer tela e campo, sempre que o ditado está ativo. Diz o que está
/// acontecendo (preparando, ouvindo, parando) e, ao fim, por que parou. É montada uma vez só, no alto do app (ver main.dart).
class DictationPill extends StatelessWidget {
  final AppState app;
  const DictationPill({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final d = app.dictation;
    return ListenableBuilder(
      listenable: Listenable.merge([d, d.elapsedMs, d.quietMs, d.level]),
      builder: (context, _) {
        if (d.phase == DictationPhase.idle) return const SizedBox.shrink();
        final mq = MediaQuery.of(context);
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, mq.viewInsets.bottom + (mq.viewInsets.bottom > 0 ? 8 : mq.padding.bottom + 76)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Material(
                color: AppColors.surface2,
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: AppColors.outline)),
                child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 8, 10), child: _content(context, d)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, Dictation d) {
    final small = TextStyle(color: AppColors.textDim, fontSize: 12.5);
    const title = TextStyle(fontWeight: FontWeight.w800, fontSize: 15);
    switch (d.phase) {
      case DictationPhase.starting:
        return Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent)),
          const SizedBox(width: 12),
          Expanded(child: Text(tr('Preparando o microfone…'), style: title)),
          TextButton(onPressed: d.stop, child: Text(tr('Cancelar'))),
        ]);
      case DictationPhase.listening:
        final total = Dictation.listenFor.inMilliseconds;
        final left = (total - d.elapsedMs.value).clamp(0, total);
        final silenceLeft = (Dictation.pauseFor.inMilliseconds - d.quietMs.value).clamp(0, Dictation.pauseFor.inMilliseconds);
        final ending = left <= 10000;
        final quietSoon = d.quietMs.value >= 2000 && silenceLeft > 0;
        final head = ending ? tr('Parando em {0}', [_mmss(left)]) : tr('Ouvindo');
        final hint = quietSoon
            ? tr('Silêncio: para em {0} s', [(silenceLeft / 1000).ceil()])
            : tr('Fale agora. Para sozinho após {0} s de silêncio ou em {1}.', [Dictation.pauseFor.inSeconds, _mmss(total)]);
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.sharp, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Text(head, style: title),
            const SizedBox(width: 12),
            _Bars(level: d.level.value, tick: d.elapsedMs.value),
            const Spacer(),
            Text(_mmss(d.elapsedMs.value), style: small.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: d.stop,
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
              child: Text(tr('Parar')),
            ),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: (d.elapsedMs.value / total).clamp(0.0, 1.0), minHeight: 3, backgroundColor: AppColors.surface, color: ending ? AppColors.flat : AppColors.sharp),
          ),
          const SizedBox(height: 6),
          Text(hint, style: small),
        ]);
      case DictationPhase.ended:
        final nothing = d.endedBy == DictationEnd.nothing;
        final why = switch (d.endedBy) {
          DictationEnd.manual => tr('você parou'),
          DictationEnd.silence => tr('parou por silêncio'),
          DictationEnd.maxTime => tr('tempo máximo atingido'),
          _ => tr('fale mais perto e tente de novo'),
        };
        return Row(children: [
          Icon(nothing ? Icons.mic_off_outlined : Icons.check_circle_rounded, size: 20, color: nothing ? AppColors.flat : AppColors.inTune),
          const SizedBox(width: 10),
          Text(nothing ? tr('Não ouvi nada') : tr('Texto inserido'), style: title),
          const SizedBox(width: 10),
          Expanded(child: Text(why, style: small, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]);
      case DictationPhase.idle:
        return const SizedBox.shrink();
    }
  }
}

/// Barrinhas que acompanham o volume da fala; se o aparelho não informa o volume, ficam num balanço suave (só mostram que está ativo).
class _Bars extends StatelessWidget {
  final double level;
  final int tick;
  const _Bars({required this.level, required this.tick});

  @override
  Widget build(BuildContext context) {
    final t = tick / 180.0;
    final amp = level > 0.02 ? level : 0.25;
    return SizedBox(
      height: 20,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        for (var i = 0; i < 6; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 3,
            height: 4 + 15 * amp * (0.45 + 0.55 * math.sin(t + i * 1.3).abs()),
            decoration: BoxDecoration(color: AppColors.sharp, borderRadius: BorderRadius.circular(2)),
          ),
        ],
      ]),
    );
  }
}
