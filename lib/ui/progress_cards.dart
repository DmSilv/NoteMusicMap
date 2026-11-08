import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../ai/coach_ai.dart';
import '../app_state.dart';
import 'markdown_lite.dart';
import 'scale_exercise_page.dart';
import 'theme.dart';
import 'widgets.dart';

String _pct(double a) => '${(a * 100).round()}%';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

Color _accColor(double a) =>
    a >= 0.8 ? AppColors.inTune : (a >= 0.5 ? AppColors.flat : AppColors.sharp);

/// Evolução da taxa de acerto nos exercícios de escala.
class EvolutionCard extends StatelessWidget {
  final AppState app;
  const EvolutionCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final all = app.sessionRecords; // mais recente primeiro
    if (all.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.show_chart),
              SizedBox(width: 8),
              Text('Sua evolução', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(
              'Faça um exercício guiado em Grade › Escala. A cada escala o app guarda a taxa de '
              'acerto e mostra aqui como você está melhorando.',
              style: TextStyle(color: AppColors.textDim),
            ),
          ],
        ),
      );
    }

    final chrono = all.take(20).toList().reversed.toList(); // antigo → novo
    final last = all.first;
    final best = all.map((s) => s.accuracy).reduce((a, b) => a > b ? a : b);
    final recent = all.take(5).map((s) => s.accuracy);
    final avg5 = recent.reduce((a, b) => a + b) / recent.length;
    double? delta;
    if (all.length >= 2) {
      final prev = all.skip(1).take(3).map((s) => s.accuracy);
      delta = (last.accuracy - prev.reduce((a, b) => a + b) / prev.length) * 100;
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.show_chart),
            SizedBox(width: 8),
            Text('Sua evolução', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_pct(last.accuracy),
                  style: TextStyle(
                      fontSize: 44,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: _accColor(last.accuracy))),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('na última escala\n${last.title}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ),
              ),
              if (delta != null) _DeltaChip(delta: delta),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: _ChartPainter(
                values: [for (final s in chrono) s.accuracy],
                line: AppColors.accent,
                grid: AppColors.outline,
                text: AppColors.textDim,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('Média (5 últimas)', _pct(avg5)),
              _stat('Melhor', _pct(best)),
              _stat('Escalas feitas', '${all.length}'),
            ],
          ),
          const Divider(height: 24),
          for (var i = 0; i < all.take(6).length; i++) _row(all, i),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _row(List<SessionRecord> all, int i) {
    final s = all[i];
    final prev = i + 1 < all.length ? all[i + 1] : null;
    final d = prev == null ? null : (s.accuracy - prev.accuracy) * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
              width: 46,
              child: Text(_date(s.date), style: TextStyle(color: AppColors.textDim, fontSize: 13))),
          Expanded(child: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (d != null && d.abs() >= 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('${d > 0 ? '+' : ''}${d.round()}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: d > 0 ? AppColors.inTune : AppColors.sharp)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: _accColor(s.accuracy).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_pct(s.accuracy),
                style: TextStyle(fontWeight: FontWeight.w800, color: _accColor(s.accuracy))),
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final double delta;
  const _DeltaChip({required this.delta});

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    final c = delta.abs() < 1 ? AppColors.textDim : (up ? AppColors.inTune : AppColors.sharp);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(delta.abs() < 1 ? Icons.remove : (up ? Icons.trending_up : Icons.trending_down),
            size: 16, color: c),
        const SizedBox(width: 4),
        Text('${up ? '+' : ''}${delta.round()} pts',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: c)),
      ]),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> values; // 0..1, do mais antigo ao mais novo
  final Color line;
  final Color grid;
  final Color text;
  _ChartPainter({required this.values, required this.line, required this.grid, required this.text});

  @override
  void paint(Canvas canvas, Size s) {
    const left = 30.0, bottom = 4.0, top = 6.0;
    final w = s.width - left - 6, h = s.height - bottom - top;
    double y(double v) => top + h * (1 - v);

    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [0.0, 0.5, 0.8, 1.0]) {
      canvas.drawLine(Offset(left, y(v)), Offset(s.width, y(v)), gp);
      final tp = TextPainter(
        text: TextSpan(text: '${(v * 100).round()}', style: TextStyle(color: text, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y(v) - tp.height / 2));
    }
    if (values.isEmpty) return;
    final n = values.length;
    double x(int i) => left + (n == 1 ? w / 2 : w * i / (n - 1));

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < n; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(path)
      ..lineTo(x(n - 1), y(0))
      ..lineTo(x(0), y(0))
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.12));
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    for (var i = 0; i < n; i++) {
      final last = i == n - 1;
      canvas.drawCircle(Offset(x(i), y(values[i])), last ? 5 : 3, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.values.length != values.length || o.line != line || !_same(o.values, values);

  bool _same(List<double> a, List<double> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Orientações do treinador com base nas últimas escalas.
class CoachCard extends StatelessWidget {
  final AppState app;
  const CoachCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final has = app.sessionRecords.isNotEmpty;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.psychology_alt_outlined),
            SizedBox(width: 8),
            Expanded(
              child: Text('Treinador',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'Analisa as suas últimas escalas e aponta o que ajustar. As dicas abaixo são calculadas no '
            'seu aparelho; a análise por IA é opcional.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          if (!has)
            Text('Faça um exercício guiado para receber orientações.',
                style: TextStyle(color: AppColors.textDim))
          else ...[
            for (final i in app.insights) InsightTile(insight: i),
            const Divider(height: 24),
            _AiSection(app: app),
          ],
        ],
      ),
    );
  }
}

/// Análise por IA (opcional): consentimento, fila e limites.
class _AiSection extends StatelessWidget {
  final AppState app;
  const _AiSection({required this.app});

  Future<void> _ask(BuildContext context) async {
    final ai = app.ai;
    if (!ai.consent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Análise por IA'),
          content: const Text(
              'Para gerar a análise, o app envia à IA um resumo só com números: '
              'desvios de afinação por nota, escalas e taxas de acerto.\n\n'
              'Nunca vão áudio, nome ou qualquer dado pessoal. Dá para usar até 5 vezes por dia.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Autorizar e analisar')),
          ],
        ),
      );
      if (ok != true) return;
      await ai.setConsent(true);
    }
    await ai.ask(app.aiSummary());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.ai,
      builder: (context, _) {
        final ai = app.ai;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Análise por IA: pede à IA orientações em linguagem natural sobre os seus últimos exercícios. '
              'Só números são enviados, nunca áudio. Opcional e precisa de internet.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            if (ai.phase == AiPhase.sending)
              const Row(children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Expanded(child: Text('Analisando seus exercícios…')),
              ])
            else if (ai.phase == AiPhase.queued)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ai.queuePosition != null
                    ? 'Muita gente usando agora. Você é o ${ai.queuePosition}º da fila: sua vez em ${ai.queuedSeconds}s.'
                    : 'Muita gente usando agora. Você está na fila: nova tentativa em ${ai.queuedSeconds}s '
                        '(tentativa ${ai.attempt}/${CoachAi.maxAttempts}).'),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: ai.cancel, child: const Text('Cancelar')),
              ])
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () => _ask(context),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(ai.text == null ? 'Analisar com IA' : 'Analisar de novo'),
                ),
                OutlinedButton.icon(
                  onPressed: () => copyAiSummary(app),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar resumo'),
                ),
              ]),
            if (ai.phase == AiPhase.failed && ai.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(ai.message!, style: TextStyle(color: AppColors.sharp, fontSize: 13)),
              ),
            if (ai.text != null && !ai.busy) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: MarkdownLite(ai.text!),
              ),
              const SizedBox(height: 6),
              Text('Gerado por IA: pode errar. Use como sugestão, junto com o seu professor.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 11.5)),
            ],
          ],
        );
      },
    );
  }
}
