import 'dart:math' as math;

import 'package:afina_core/afina_core.dart';
import 'safe_input.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';
import 'widgets.dart';

String fmtClock(int ms) {
  final s = (ms / 1000).ceil();
  final m = s ~/ 60;
  final r = s % 60;
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

String phaseLabel(PomodoroTimer p) {
  final base = switch (p.phase) {
    PomoPhase.idle => tr('Pronto para começar'),
    PomoPhase.focus => tr('Foco'),
    PomoPhase.shortBreak => tr('Pausa curta'),
    PomoPhase.longBreak => tr('Pausa longa'),
  };
  return p.isPaused ? tr('{0} · pausado', [base]) : base;
}

Color phaseColor(PomoPhase p) =>
    p == PomoPhase.shortBreak || p == PomoPhase.longBreak ? AppColors.flat : AppColors.accent;

/// Timer de estudo (Pomodoro) com alarme sutil.
class PomodoroCard extends StatelessWidget {
  final AppState app;
  const PomodoroCard({super.key, required this.app});

  // Só o cartão reage ao tique de 500 ms; o resto da aba não é reconstruído.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app.pomoLive,
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    final p = app.pomo;
    final rem = app.pomoRemainingMs;
    final color = phaseColor(p.phase);
    final n = p.config.cyclesBeforeLong;

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Foco (Pomodoro)'),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: tr('Ajustes do timer'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.tune),
                onPressed: () => showPomodoroSettings(context, app),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 210,
            height: 210,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(210, 210),
                  painter: _RingPainter(
                    progress: p.phase == PomoPhase.idle ? 0 : app.pomoProgress,
                    color: color,
                    track: AppColors.surface2,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fmtClock(rem),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(phaseLabel(p),
                        style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // pontinhos: focos concluídos até a pausa longa
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < n; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < p.cycle ? AppColors.accent : Colors.transparent,
                    border: Border.all(
                        color: i < p.cycle ? AppColors.accent : AppColors.textDim, width: 1.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            app.pomoToday == 0
                ? tr('Nenhum foco concluído hoje')
                : tr('{0} foco{1} concluído{2} hoje', [app.pomoToday, app.pomoToday > 1 ? 's' : '', app.pomoToday > 1 ? 's' : '']),
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton.outlined(
                tooltip: tr('Reiniciar'),
                iconSize: 26,
                onPressed: p.phase == PomoPhase.idle ? null : app.pomoReset,
                icon: const Icon(Icons.restart_alt),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: p.running ? app.pomoPause : app.pomoStart,
                  icon: Icon(p.running ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    p.running ? tr('Pausar') : (p.isPaused ? tr('Continuar') : tr('Iniciar foco')),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: tr('Pular para a próxima fase'),
                iconSize: 26,
                onPressed: p.phase == PomoPhase.idle ? null : app.pomoSkip,
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            app.pomoChime
                ? tr('Um sininho suave avisa o fim de cada fase. Mantenha o app aberto.')
                : tr('Alarme sonoro desligado (ligue nos ajustes do timer).'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  _RingPainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2 - 10;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, base..color = track);
    if (progress > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
          2 * math.pi * progress, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.color != color || o.track != track;
}

/// Mini cronômetro da barra do topo: aparece em qualquer aba enquanto o timer existe.
class PomodoroPill extends StatelessWidget {
  final AppState app;
  final VoidCallback onTap;
  const PomodoroPill({super.key, required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.pomoLive,
      builder: (context, _) {
        final p = app.pomo;
        if (p.phase == PomoPhase.idle) return const SizedBox.shrink();
        final color = phaseColor(p.phase);
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(p.running ? Icons.timer : Icons.pause_circle_outline, size: 16, color: color),
                  const SizedBox(width: 4),
                  Text(fmtClock(app.pomoRemainingMs),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Modal com os ajustes do timer.
void showPomodoroSettings(BuildContext context, AppState app) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final c = app.pomo.config;
          Widget stepper(String label, int value, int min, int max, int step, String unit,
              ValueChanged<int> on) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: value > min ? () => on(value - step) : null,
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _askNumber(context, label, value, min, max, unit, on),
                    child: Container(
                      width: 84,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$value $unit'.trim(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: value < max ? () => on(value + step) : null,
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Ajustes do timer'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(tr('Toque no número para digitar o tempo (a partir de 1 minuto). Vale a partir da próxima fase e fica salvo neste aparelho.'),
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                const SizedBox(height: 12),
                Text(tr('Atalhos'), style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final (f, sh, lo, name) in [
                    (25, 5, 15, tr('Clássico 25/5')),
                    (50, 10, 20, tr('Longo 50/10')),
                    (15, 3, 10, tr('Curto 15/3')),
                    (1, 1, 2, tr('Teste 1/1')),
                  ])
                    ActionChip(
                      label: Text(name),
                      onPressed: () => app.setPomo(
                          config: c.copyWith(focusMin: f, shortMin: sh, longMin: lo)),
                    ),
                ]),
                const SizedBox(height: 8),
                stepper(tr('Foco'), c.focusMin, 1, 180, 1, 'min',
                    (v) => app.setPomo(config: c.copyWith(focusMin: v))),
                stepper(tr('Pausa curta'), c.shortMin, 1, 60, 1, 'min',
                    (v) => app.setPomo(config: c.copyWith(shortMin: v))),
                stepper(tr('Pausa longa'), c.longMin, 1, 120, 1, 'min',
                    (v) => app.setPomo(config: c.copyWith(longMin: v))),
                stepper(tr('Focos até a pausa longa'), c.cyclesBeforeLong, 2, 8, 1, '',
                    (v) => app.setPomo(config: c.copyWith(cyclesBeforeLong: v))),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Começar a próxima fase sozinho')),
                  subtitle: Text(tr('Desligado: espera você tocar em Continuar.')),
                  value: c.autoStart,
                  onChanged: (v) => app.setPomo(config: c.copyWith(autoStart: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Alarme sonoro suave')),
                  subtitle: Text(tr('Sininho de duas notas, baixinho.')),
                  value: app.pomoChime,
                  onChanged: (v) => app.setPomo(chime: v),
                ),
                if (app.pomoChime)
                  Row(
                    children: [
                      const Icon(Icons.volume_down, size: 20),
                      Expanded(
                        child: Slider(
                          min: 0.1,
                          max: 1.0,
                          value: app.pomoVolume.clamp(0.1, 1.0),
                          onChanged: (v) => app.setPomo(volume: v),
                        ),
                      ),
                      TextButton(onPressed: app.pomoTestChime, child: Text(tr('Ouvir'))),
                    ],
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Vibrar ao terminar')),
                  subtitle: Text(tr('Só em celulares.')),
                  value: app.pomoVibrate,
                  onChanged: (v) => app.setPomo(vibrate: v),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// Pergunta um número (minutos) num diálogo simples.
Future<void> _askNumber(BuildContext context, String label, int value, int min, int max,
    String unit, ValueChanged<int> on) async {
  final ctl = TextEditingController(text: '$value');
  final v = await showDialog<int>(
    context: context,
    builder: (ctx) {
      String? err;
      return StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(label),
          content: TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: digitsFormatters(4),
            decoration: InputDecoration(
              suffixText: unit,
              helperText: tr('De {0} a {1}', [min, max]),
              errorText: err,
            ),
            onSubmitted: (_) {
              final n = int.tryParse(ctl.text);
              if (n != null && n >= min && n <= max) Navigator.pop(ctx, n);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(ctl.text);
                if (n == null || n < min || n > max) {
                  set(() => err = tr('Use um valor entre {0} e {1}', [min, max]));
                } else {
                  Navigator.pop(ctx, n);
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    },
  );
  if (v != null) on(v);
}
