/// "Comece por aqui": o que o professor novo precisa fazer para o app render (vincular, marcar aula, passar tarefa).
/// Dart puro: o app diz o que já aconteceu e esta lógica diz o que falta e qual é o próximo passo.
library;

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
      StartItem('link', 'Vincule um aluno', 'Ele lê o seu QR ou digita o seu código.', hasLinkedStudent),
      StartItem('class', 'Marque uma aula', 'Uma vez, ou toda semana.', hasClass),
      StartItem('task', 'Passe uma tarefa', 'Escala, lição ou repertório; o aluno recebe na hora.', hasTask),
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
