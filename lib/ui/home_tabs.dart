/// Abas da tela principal. Os ids são fixos (o hub e os atalhos usam estes números); só a ORDEM na barra de baixo muda.
const int kTabTuner = 0, kTabMetronome = 1, kTabGrid = 2, kTabScales = 3, kTabStudy = 4;

/// A aba que abre primeiro e para onde o botão voltar leva: o Meu espaço.
const int kHomeTab = kTabStudy;

/// Ordem na barra de baixo: o Meu espaço fica no centro.
const List<int> kTabOrder = [kTabTuner, kTabMetronome, kTabStudy, kTabGrid, kTabScales];
