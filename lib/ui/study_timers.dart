import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'safe_input.dart';
import 'pomodoro_card.dart';
import 'theme.dart';
import 'widgets.dart';

/// Bloco "Como você quer estudar?": submenu com Pomodoro, Cronômetro e Meu
/// tempo, cada um com uma explicação curta de quando usar.
class StudyTimerSection extends StatelessWidget {
  final AppState app;
  const StudyTimerSection({super.key, required this.app});

  static final _info = {
    StudyMode.pomodoro: (
      Icons.local_fire_department_outlined,
      tr('Pomodoro: foco e descanso em ciclos'),
      tr('Estude 25 minutos concentrado, descanse 5 e repita; a cada 4 ciclos há uma pausa maior. Bom para manter a concentração e não esquecer de descansar.')
    ),
    StudyMode.stopwatch: (
      Icons.av_timer,
      tr('Cronômetro: só contar o seu tempo'),
      tr('Mede quanto tempo você estudou, sem alarme e sem ciclos. Toque em Iniciar ao começar e em Pausar ao terminar. Bom para quem prefere estudar livremente.')
    ),
    StudyMode.custom: (
      Icons.hourglass_bottom,
      tr('Meu tempo: sessão com duração escolhida'),
      tr('Você define a duração (por exemplo, 40 minutos) e o app avisa no fim. Sem ciclos de descanso. Bom para ensaios e para estudos com hora marcada.')
    ),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final m = app.studyMode;
        return Column(
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(tr('Como você quer estudar?'),
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    HelpButton(
                      title: tr('Pomodoro, Cronômetro ou Meu tempo?'),
                      sections: [for (final e in _info.values) (e.$2, e.$3)],
                    ),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<StudyMode>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        minimumSize: WidgetStatePropertyAll(Size(0, 48)),
                        textStyle: WidgetStatePropertyAll(
                            TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
                      ),
                      segments: [
                        ButtonSegment(value: StudyMode.pomodoro, label: Text(tr('Pomodoro'))),
                        ButtonSegment(value: StudyMode.stopwatch, label: Text(tr('Cronômetro'))),
                        ButtonSegment(value: StudyMode.custom, label: Text(tr('Meu tempo'))),
                      ],
                      selected: {m},
                      onSelectionChanged: (s) => app.setStudyMode(s.first),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            switch (m) {
              StudyMode.pomodoro => PomodoroCard(app: app),
              StudyMode.stopwatch => _StopwatchCard(app: app),
              StudyMode.custom => _CustomCard(app: app),
            },
          ],
        );
      },
    );
  }
}

class _StopwatchCard extends StatelessWidget {
  final AppState app;
  const _StopwatchCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final c = app.stopwatch;
    return AppCard(
      child: ListenableBuilder(
        listenable: app.pomoLive,
        builder: (context, _) {
          final ms = c.elapsedMs(DateTime.now().millisecondsSinceEpoch);
          return Column(
            children: [
              Text(c.running ? tr('Contando seu estudo…') : (ms > 0 ? tr('Pausado') : tr('Pronto para começar')),
                  style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 6),
              Text(formatClock(ms),
                  style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 12),
              _clockButtons(app, c, startLabel: ms > 0 ? tr('Continuar') : tr('Iniciar')),
              const SizedBox(height: 6),
              Text(tr('O tempo vai para o seu total de hoje enquanto o cronômetro roda.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ],
          );
        },
      ),
    );
  }
}

class _CustomCard extends StatelessWidget {
  final AppState app;
  const _CustomCard({required this.app});

  Future<void> _other(BuildContext context) async {
    final ctl = TextEditingController(text: '${app.customMinutes}');
    final v = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Quantos minutos?')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: digitsFormatters(4),
          decoration: InputDecoration(suffixText: 'min', helperText: tr('De 1 a 600 minutos')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancelar'))),
          FilledButton.icon(
              onPressed: () => Navigator.pop(c, int.tryParse(ctl.text)), icon: const Icon(Icons.check, size: 18), label: Text(tr('Aplicar'))),
        ],
      ),
    );
    ctl.dispose();
    if (v != null && v > 0) app.setCustomMinutes(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = app.customClock;
    const presets = [15, 30, 45, 60, 90];
    return AppCard(
      child: ListenableBuilder(
        listenable: app.pomoLive,
        builder: (context, _) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final left = c.remainingMs(now);
          final done = c.finished(now);
          return Column(
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  for (final m in presets)
                    ChoiceChip(
                      label: Text('$m min'),
                      selected: app.customMinutes == m,
                      onSelected: c.running ? null : (_) => app.setCustomMinutes(m),
                    ),
                  ChoiceChip(
                    avatar: const Icon(Icons.edit, size: 15),
                    label: Text(presets.contains(app.customMinutes) ? tr('Outro…') : '${app.customMinutes} min'),
                    selected: !presets.contains(app.customMinutes),
                    onSelected: c.running ? null : (_) => _other(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                  done
                      ? tr('Sessão concluída! Bom trabalho.')
                      : (c.running ? tr('Estudando…') : (c.elapsedMs(now) > 0 ? tr('Pausado') : tr('Pronto para começar'))),
                  style: TextStyle(color: done ? AppColors.inTune : AppColors.textDim)),
              const SizedBox(height: 6),
              Text(formatClock(left),
                  style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: c.progress(now),
                  backgroundColor: AppColors.surface2,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 12),
              _clockButtons(app, c,
                  startLabel: c.elapsedMs(now) > 0 && !done ? tr('Continuar') : tr('Iniciar'), done: done),
            ],
          );
        },
      ),
    );
  }
}

/// Iniciar/Pausar + Reiniciar.
Widget _clockButtons(AppState app, StudyClock c, {required String startLabel, bool done = false}) {
  return Row(
    children: [
      Expanded(
        flex: 3,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: done
              ? () => app.clockReset(c)
              : (c.running ? () => app.clockPause(c) : () => app.clockStart(c)),
          icon: Icon(done ? Icons.replay : (c.running ? Icons.pause : Icons.play_arrow)),
          label: Text(done ? tr('Nova sessão') : (c.running ? tr('Pausar') : startLabel),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => app.clockReset(c),
          icon: const Icon(Icons.restart_alt),
          label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Reiniciar'))),
        ),
      ),
    ],
  );
}

/// Aviso na faixa de status quando o cronômetro ou o tempo personalizado rodam.
class ClockPill extends StatelessWidget {
  final AppState app;
  final VoidCallback onTap;
  const ClockPill({super.key, required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sw = app.stopwatch.running;
    final cu = app.customClock.running;
    if (!sw && !cu) return const SizedBox.shrink();
    final text = cu ? formatClock(app.customClock.remainingMs(now)) : formatClock(app.stopwatch.elapsedMs(now));
    final color = AppColors.accent;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.7)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(cu ? Icons.hourglass_bottom : Icons.av_timer, size: 16, color: color),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        ),
      ),
    );
  }
}
