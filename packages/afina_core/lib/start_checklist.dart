/// "Comece por aqui": o que o professor novo precisa fazer para o app render (vincular, marcar aula, passar tarefa).
/// Dart puro: o app diz o que já aconteceu e esta lógica diz o que falta e qual é o próximo passo.
library;

import 'i18n.dart';

/// Um passo da lista.
class StartItem {
  /// 'link', 'class' ou 'task'.
  final String id;
  final String title;
  final String hint;
  final bool done;
  const StartItem(this.id, this.title, this.hint, this.done);
}

/// Os passos do professor, na ordem em que fazem sentido.
List<StartItem> teacherStartItems({required bool hasLinkedStudent, required bool hasClass, required bool hasTask}) => [
      StartItem('link', tr('Vincule um aluno'), tr('Ele lê o seu QR ou digita o seu código.'), hasLinkedStudent),
      StartItem('class', tr('Marque uma aula'), tr('Uma vez, ou toda semana.'), hasClass),
      StartItem('task', tr('Passe uma tarefa'), tr('Escala, lição ou repertório; o aluno recebe na hora.'), hasTask),
    ];

/// Segundos de estudo que contam como "estudar um pouco" no passo 3 do músico novo (5 minutos).
const int kFirstStudySeconds = 300;

/// "Seu primeiro passo": o que o músico que chega sozinho faz nos primeiros minutos (afinar, tocar uma escala, estudar 5 min).
/// Ids: 'tune', 'scale' e 'study'.
List<StartItem> soloStartItems({required bool tuned, required bool playedScale, required double studySeconds}) => [
      StartItem('tune', tr('Afinar uma corda'), tr('Toque uma corda solta e deixe o ponteiro no centro.'), tuned),
      StartItem('scale', tr('Tocar a primeira escala'), tr('Escolha uma escala e toque nota por nota.'), playedScale),
      StartItem('study', tr('Estudar 5 minutos'), tr('Ligue o metrônomo e toque junto.'), studySeconds >= kFirstStudySeconds),
    ];

/// O primeiro passo que ainda falta (null se tudo foi feito).
StartItem? nextStartItem(List<StartItem> items) {
  for (final i in items) {
    if (!i.done) return i;
  }
  return null;
}

bool allStartDone(List<StartItem> items) => items.every((i) => i.done);

/// Quantos passos já foram feitos.
int startDoneCount(List<StartItem> items) => items.where((i) => i.done).length;
