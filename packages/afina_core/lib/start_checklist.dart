/// Os primeiros passos do professor (aluno, tarefa, tarefa entregue) e quando as ferramentas avançadas aparecem.
/// A promessa do app para ele: "ajude seu aluno a estudar entre uma aula e outra". A agenda ajuda, mas não é o começo.
/// Dart puro: o app diz o que já aconteceu e esta lógica diz o que falta e qual é o próximo passo.
library;

import 'i18n.dart';

/// Um passo da lista.
class StartItem {
  /// Professor: 'student', 'task' ou 'link'. Músico solo: 'tune', 'scale' ou 'study'.
  final String id;
  final String title;
  final String hint;
  final bool done;
  const StartItem(this.id, this.title, this.hint, this.done);
}

/// Os passos do professor, na ordem em que fazem sentido. [delivered]: algum aluno vinculado já tem uma tarefa enviada.
List<StartItem> teacherStartItems({required bool hasStudent, required bool hasTask, required bool delivered}) => [
      StartItem('student', tr('Adicione um aluno'), tr('Pelo nome, pelo QR dele ou por convite.'), hasStudent),
      StartItem('task', tr('Passe a tarefa da aula'), tr('Uma escala, uma lição ou um trecho de peça.'), hasTask),
      StartItem('link', tr('Faça a tarefa chegar nele'), tr('Ele abre o seu convite e toca em Vincular.'), delivered),
    ];

/// Professor que acabou de chegar vê só o essencial (alunos, tarefas, validar e agenda). O resto (turmas, métodos, acervo,
/// ranking e horários livres) aparece quando ele já tem aluno e tarefa, quando pede para ver tudo ([unlocked]) ou se já usa
/// alguma dessas ferramentas ([usesAdvanced]). Quem já usava o app antes entra com [unlocked] ligado.
bool teacherBasicsOnly({required bool unlocked, required bool hasStudent, required bool hasTask, required bool usesAdvanced}) =>
    !unlocked && !usesAdvanced && !(hasStudent && hasTask);

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
