// A barra de baixo: Meu espaço no centro e é a aba que abre primeiro.
import 'package:afina/ui/home_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o Meu espaço abre primeiro e fica no centro da barra', () {
    expect(kHomeTab, kTabStudy);
    expect(kTabOrder.length, 5);
    expect(kTabOrder[kTabOrder.length ~/ 2], kTabStudy, reason: 'o do meio é o Meu espaço');
  });

  test('a barra mostra cada aba uma vez só, com os ids de sempre', () {
    expect(kTabOrder.toSet(), {kTabTuner, kTabMetronome, kTabGrid, kTabScales, kTabStudy});
    expect(kTabOrder.indexOf(kHomeTab), 2);
    expect(kTabTuner, 0);
    expect(kTabStudy, 4, reason: 'o hub e o Pomodoro ainda usam estes números');
  });
}
