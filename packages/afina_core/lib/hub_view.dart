/// Visões do "Meu espaço": quem é professor também pode ser aluno de outra pessoa, então o hub
/// tem duas visões separadas (Aluno e Professor) e cada destino aparece UMA vez por visão.
/// Dart puro e testável: a tela só desenha o que sai daqui.
library;

import 'hub.dart';

/// Qual papel o Meu espaço mostra.
enum HubView { student, teacher }

/// Cada lugar para onde o hub leva. Um destino nunca aparece duas vezes na mesma visão.
enum HubDest {
  // lado do aluno
  agendaStudent, // Agenda do aluno
  myTasks, // Minhas tarefas / aulas recebidas
  pickSlot, // Pegar horário
  scanTeacher, // Ler QR do professor
  // lado do professor
  agendaTeacher, // Agenda do professor
  openSlots, // Horários livres
  students, // Alunos
  validate, // Tarefas para validar
  studentFile, // Ficha do aluno da próxima aula
  markClass, // Marcar aula
  inviteStudent, // Convidar aluno
  // comuns
  metronome,
  scales,
}

/// Destinos que só fazem sentido para um papel.
const Set<HubDest> kStudentOnly = {HubDest.agendaStudent, HubDest.myTasks, HubDest.pickSlot, HubDest.scanTeacher};
const Set<HubDest> kTeacherOnly = {
  HubDest.agendaTeacher,
  HubDest.openSlots,
  HubDest.students,
  HubDest.validate,
  HubDest.studentFile,
  HubDest.markClass,
  HubDest.inviteStudent,
};

/// O alternador Aluno | Professor só aparece para quem tem os dois papéis.
bool canSwitchHubView({required bool teacherMode, required bool hasTeacherSide}) => teacherMode && hasTeacherSide;

/// Visão em uso: só aluno → aluno; só professor → professor; os dois → a escolha da pessoa
/// ([preferred]), ou professor se ela nunca escolheu.
HubView resolveHubView({required bool teacherMode, required bool hasTeacherSide, HubView? preferred}) {
  if (!teacherMode) return HubView.student;
  if (!hasTeacherSide) return HubView.teacher;
  return preferred ?? HubView.teacher;
}

/// Organização do que aparece abaixo do destaque.
class HubLayout {
  /// Os blocos grandes (no máximo 2), do que pede ação.
  final List<HubDest> tiles;

  /// A faixa de ferramentas.
  final List<HubDest> tools;
  const HubLayout({required this.tiles, required this.tools});
}

/// Blocos e ferramentas da visão [v]. [hasTeacherSide] = tem professor, aula ou agenda como aluno.
/// Os atalhos do destaque ficam de fora daqui (ver [heroActions]); cada destino aparece uma vez só.
HubLayout hubLayout(HubView v, {required bool hasTeacherSide}) {
  if (v == HubView.teacher) {
    return const HubLayout(
      tiles: [HubDest.validate, HubDest.students],
      tools: [HubDest.agendaTeacher, HubDest.openSlots, HubDest.metronome, HubDest.scales],
    );
  }
  return HubLayout(
    tiles: hasTeacherSide ? const [HubDest.myTasks, HubDest.agendaStudent] : const [],
    tools: [if (hasTeacherSide) HubDest.pickSlot, HubDest.metronome, HubDest.scales],
  );
}

/// Botões do destaque. Nunca repetem o que os blocos e as ferramentas já oferecem:
/// o destaque age sobre a PRÓXIMA AULA (ficha), ou ajuda a começar quando não há nada.
List<HubDest> heroActions(HubView v, HeroKind kind, {required bool hasStudents, required bool hasClassStudent}) {
  if (v == HubView.teacher) {
    return switch (kind) {
      HeroKind.ongoing || HeroKind.soon || HeroKind.next => [if (hasClassStudent) HubDest.studentFile],
      HeroKind.none || HeroKind.noTeacher => [hasStudents ? HubDest.markClass : HubDest.inviteStudent],
    };
  }
  return switch (kind) {
    HeroKind.noTeacher => const [HubDest.scanTeacher],
    _ => const [],
  };
}

/// Avisos que pertencem a cada visão (o sino mostra todos; o hub mostra os da visão atual).
const Map<HubView, Set<String>> kNoticeKindsByView = {
  HubView.student: {'teacher', 'lesson', 'task'},
  HubView.teacher: {'done', 'pick'},
};
