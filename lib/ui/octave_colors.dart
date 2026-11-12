import 'package:flutter/material.dart';
import 'package:afina_core/afina_core.dart';

/// Uma cor para cada oitava do exercício (escalas e arpejos), diferente das cores de afinação
/// (azul, verde, laranja): violeta, rosa, dourado e prata.
const _octaveColors = [Color(0xFF9C7BFF), Color(0xFFFF7BAC), Color(0xFFF2C94C), Color(0xFFCFD8DC)];

Color octaveColor(int i) => _octaveColors[i.clamp(0, _octaveColors.length - 1)];

/// Em qual oitava do exercício (0 = a primeira) está [midi], contando a partir da nota mais grave [lo].
/// A nota final (a tônica uma oitava acima) fica na última oitava, não numa nova.
int octaveIndex(int midi, int lo, int octaves) => ((midi - lo) ~/ 12).clamp(0, octaves - 1);

String octaveName(int i) => tr('{0}ª oitava', [i + 1]);

/// Legenda das oitavas: "● 1ª oitava  ● 2ª oitava".
class OctaveLegend extends StatelessWidget {
  final int octaves;
  const OctaveLegend({super.key, required this.octaves});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 14, runSpacing: 4, children: [
        for (var i = 0; i < octaves; i++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: octaveColor(i), borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 6),
            Text(octaveName(i), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
      ]);
}
