import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart';

String _pct(double a) => '${(a * 100).round()}%';

String _date(DateTime d) => fmtDayMonth(d);

/// Verde: 80% ou mais; azul: 50 a 79%; laranja: abaixo de 50%.
Color _accColor(double a) => a >= 0.8 ? AppColors.inTune : (a >= 0.5 ? AppColors.flat : AppColors.sharp);

/// Acerto nas escalas: quantas notas ficaram afinadas em cada exercício, e como isso mudou.
class EvolutionCard extends StatelessWidget {
  final AppState app;
  const EvolutionCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final all = app.sessionRecords; // mais recente primeiro
    final title = DsCardTitle(Icons.show_chart, tr('Acerto nas escalas'), subtitle: tr('Quantas notas ficaram afinadas em cada exercício.'));
    if (all.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: Ds.s8),
            Text(tr('Faça uma escala guiada em Escalas: a taxa de acerto aparece aqui.'), style: Ds.support()),
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
          title,
          const SizedBox(height: Ds.s16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_pct(last.accuracy), style: TextStyle(fontSize: 44, height: 1.0, fontWeight: FontWeight.w800, color: _accColor(last.accuracy))),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(tr('no último exercício\n{0}', [last.title]), style: Ds.support()),
                ),
              ),
            ],
          ),
          if (delta != null) ...[
            const SizedBox(height: Ds.s8),
            Row(children: [
              _DeltaChip(delta: delta),
              const SizedBox(width: Ds.s8),
              Expanded(child: Text(tr('em relação aos 3 anteriores'), style: Ds.support())),
            ]),
          ],
          const SizedBox(height: Ds.s16),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _ChartPainter(
                values: [for (final s in chrono) s.accuracy],
                line: AppColors.accent,
                grid: AppColors.outline,
                text: AppColors.textDim,
                bandLabel: tr('Ótimo'),
                firstDate: _date(chrono.first.date),
                lastDate: _date(chrono.last.date),
              ),
            ),
          ),
          const SizedBox(height: Ds.s12),
          Row(
            children: [
              _stat(tr('Média (5 últimas)'), _pct(avg5)),
              _stat(tr('Melhor'), _pct(best)),
              _stat(tr('Escalas feitas'), '${all.length}'),
            ],
          ),
          const Divider(height: 28),
          Text(tr('Últimos exercícios'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: Ds.s4),
          Wrap(spacing: Ds.s12, runSpacing: 2, children: [
            _legend(AppColors.inTune, tr('80% ou mais')),
            _legend(AppColors.flat, tr('50 a 79%')),
            _legend(AppColors.sharp, tr('menos de 50%')),
          ]),
          const SizedBox(height: Ds.s4),
          for (var i = 0; i < all.take(6).length; i++) _row(all, i),
        ],
      ),
    );
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(t, style: Ds.support()),
      ]);

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
          SizedBox(width: 46, child: Text(_date(s.date), style: TextStyle(color: AppColors.textDim, fontSize: 13))),
          Expanded(child: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (d != null && d.abs() >= 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('${d > 0 ? '▲' : '▼'} ${d.abs().round()}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: d > 0 ? AppColors.inTune : AppColors.sharp)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: _accColor(s.accuracy).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
            child: Text(_pct(s.accuracy), style: TextStyle(fontWeight: FontWeight.w800, color: _accColor(s.accuracy))),
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
    final same = delta.abs() < 1;
    final c = same ? AppColors.textDim : (up ? AppColors.inTune : AppColors.sharp);
    final label = same ? tr('igual') : (up ? tr('{0} pontos a mais', [delta.round()]) : tr('{0} pontos a menos', [-delta.round()]));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(same ? Icons.remove : (up ? Icons.trending_up : Icons.trending_down), size: 16, color: c),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: c)),
      ]),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> values; // 0..1, do mais antigo ao mais novo
  final Color line;
  final Color grid;
  final Color text;
  final String bandLabel;
  final String firstDate;
  final String lastDate;
  _ChartPainter({required this.values, required this.line, required this.grid, required this.text, required this.bandLabel, required this.firstDate, required this.lastDate});

  TextPainter _tp(String t, {double size = 10, Color? color, FontWeight? weight}) =>
      TextPainter(text: TextSpan(text: t, style: TextStyle(color: color ?? text, fontSize: size, fontWeight: weight)), textDirection: TextDirection.ltr)..layout();

  @override
  void paint(Canvas canvas, Size s) {
    const left = 34.0, bottom = 20.0, top = 14.0, right = 10.0;
    final w = s.width - left - right, h = s.height - bottom - top;
    double y(double v) => top + h * (1 - v);

    // Faixa "ótimo" (80% a 100%).
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(left, y(1), s.width - right, y(0.8)), const Radius.circular(6)),
      Paint()..color = AppColors.inTune.withValues(alpha: 0.10),
    );
    final bl = _tp(bandLabel, size: 10.5, color: AppColors.inTune, weight: FontWeight.w700);
    bl.paint(canvas, Offset(s.width - right - bl.width - 6, y(1) + 3));

    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [0.0, 0.5, 0.8, 1.0]) {
      canvas.drawLine(Offset(left, y(v)), Offset(s.width - right, y(v)), gp);
      final tp = _tp('${(v * 100).round()}%');
      tp.paint(canvas, Offset(left - tp.width - 6, y(v) - tp.height / 2));
    }
    if (values.isEmpty) return;
    final n = values.length;
    double x(int i) => left + (n == 1 ? w / 2 : w * i / (n - 1));

    // Datas do primeiro e do último exercício.
    final a = _tp(firstDate);
    final b = _tp(lastDate);
    a.paint(canvas, Offset(n == 1 ? x(0) - a.width / 2 : left, s.height - a.height));
    if (n > 1) b.paint(canvas, Offset(s.width - right - b.width, s.height - b.height));

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < n; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    for (var i = 0; i < n; i++) {
      final isLast = i == n - 1;
      canvas.drawCircle(Offset(x(i), y(values[i])), isLast ? 6 : 3, Paint()..color = isLast ? _color(values[i]) : line);
    }
    // O valor do último ponto, escrito junto dele.
    final lv = _tp('${(values.last * 100).round()}%', size: 12, color: _color(values.last), weight: FontWeight.w800);
    final lx = (x(n - 1) - lv.width / 2).clamp(left, s.width - right - lv.width);
    final ly = y(values.last) - lv.height - 8;
    lv.paint(canvas, Offset(lx, ly < 0 ? y(values.last) + 8 : ly));
  }

  Color _color(double a) => a >= 0.8 ? AppColors.inTune : (a >= 0.5 ? AppColors.flat : AppColors.sharp);

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.values.length != values.length || o.line != line || o.bandLabel != bandLabel || o.firstDate != firstDate || o.lastDate != lastDate || !_same(o.values, values);

  bool _same(List<double> a, List<double> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
