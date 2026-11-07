import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'mic_pill.dart';
import 'pomodoro_card.dart';
import 'study_timers.dart';
import 'toast.dart';

/// Faixa fina logo abaixo da barra superior com os avisos que ficam ativos:
/// microfone ouvindo e timer do Pomodoro. Só aparece quando há algo ativo, e
/// os dois avisos ficam lado a lado, sem disputar espaço com o título e os
/// ícones da barra. Os alertas animados descem junto (ver [kToastExtraTop]).
class StatusStrip extends StatelessWidget {
  final AppState app;
  final VoidCallback onPomodoro;
  const StatusStrip({super.key, required this.app, required this.onPomodoro});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.micOn, app.pomoLive]),
      builder: (context, _) {
        final active = app.micOn.value || app.pomo.phase != PomoPhase.idle || app.manualClockActive;
        kToastExtraTop = active ? 40 : 0;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: active
              ? SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        MicPill(app: app),
                        PomodoroPill(app: app, onTap: onPomodoro),
                        ClockPill(app: app, onTap: onPomodoro),
                      ],
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        );
      },
    );
  }
}
