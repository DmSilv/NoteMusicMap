/// Regras do hub "Meu espaço": o que vai no bloco grande (destaque) e os textos dos blocos menores,
/// sempre dizendo o que fazer quando não há nada. Dart puro e testável.
library;

import 'agenda.dart';

/// A aula que importa agora (a em andamento ou a próxima).
class HubClass {
  final int startMs;
  final int endMs;

  /// Com quem: nome do aluno (professor) ou do professor (aluno).
  final String who;
  const HubClass(this.startMs, this.endMs, this.who);
}

enum HeroKind {
  /// A aula está acontecendo.
  ongoing,

  /// Começa em até 15 minutos.
  soon,

  /// Há uma aula marcada mais para frente.
  next,

  /// Nenhuma aula marcada.
  none,

  /// Aluno sem professor vinculado.
  noTeacher,
}

class HubHero {
  final HeroKind kind;

  /// Linha pequena acima do título ("Sua próxima aula", "Começa em 12 min"…).
  final String kicker;
  final String title;
  final String subtitle;
  const HubHero(this.kind, this.kicker, this.title, this.subtitle);
}

String _hm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// "em 40 min", "em 3 h", "em 2 dias".
String fmtUntil(Duration d) {
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'em ${d.inMinutes} min';
  if (d.inHours < 24) return 'em ${d.inHours} h';
  final days = d.inDays;
  return 'em $days ${days == 1 ? 'dia' : 'dias'}';
}

/// O destaque do topo. [next] é a aula em andamento ou a próxima; [todayCount] é quantas aulas o
/// professor tem hoje; [hasStudents] diz se o professor já tem aluno cadastrado.
HubHero buildHero({
  required int nowMs,
  required bool isTeacher,
  required bool hasTeacher,
  HubClass? next,
  int todayCount = 0,
  bool hasStudents = true,
}) {
  if (next != null) {
    final who = next.who.trim().isEmpty ? (isTeacher ? 'seu aluno' : 'seu professor') : next.who.trim();
    if (nowMs >= next.startMs && nowMs < next.endMs) {
      return HubHero(HeroKind.ongoing, 'Aula em andamento', 'Com $who', 'Até as ${_hm(next.endMs)}');
    }
    final until = next.startMs - nowMs;
    if (until > 0 && until <= kReminderMinutes * kMsMinute) {
      final mins = (until / kMsMinute).ceil();
      return HubHero(HeroKind.soon, 'Começa em ${mins <= 1 ? '1 min' : '$mins min'}', 'Aula com $who', 'Às ${_hm(next.startMs)}');
    }
    if (until > 0) {
      final when = fmtSlotWhen(DateTime.fromMillisecondsSinceEpoch(next.startMs), DateTime.fromMillisecondsSinceEpoch(nowMs));
      final kicker = isTeacher && todayCount > 0
          ? 'Hoje · $todayCount ${todayCount == 1 ? 'aula' : 'aulas'}'
          : (isTeacher ? 'Próxima aula' : 'Sua próxima aula');
      return HubHero(
          HeroKind.next, kicker, _cap(when), 'Com $who · ${fmtUntil(Duration(milliseconds: until))}');
    }
  }
  if (isTeacher) {
    return hasStudents
        ? const HubHero(HeroKind.none, 'Agenda', 'Sem aulas marcadas', 'Marque a primeira aula com um aluno.')
        : const HubHero(HeroKind.none, 'Agenda', 'Sem alunos ainda', 'Convide ou cadastre seu primeiro aluno.');
  }
  if (hasTeacher) {
    return const HubHero(HeroKind.none, 'Sua agenda', 'Você ainda não tem aula marcada',
        'Combine com seu professor: quando ele marcar, aparece aqui.');
  }
  return const HubHero(
      HeroKind.noTeacher, 'Estuda com um professor?', 'Vincule seu professor', 'Leia o QR dele para ver aulas e tarefas aqui.');
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Um bloco menor: título, linha principal, apoio e (opcional) progresso 0..1.
class HubTile {
  final String title;
  final String headline;
  final String caption;
  final double? progress;

  /// Pede ação (mostra em destaque amarelo).
  final bool needsAction;
  const HubTile(this.title, this.headline, this.caption, {this.progress, this.needsAction = false});
}

String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Bloco de tarefas do aluno. [open] pendentes e [total] da semana.
HubTile tasksTile({required int open, required int total}) {
  if (total == 0) {
    return const HubTile('Tarefas', 'Nenhuma tarefa', 'Quando seu professor passar, aparece aqui.');
  }
  if (open == 0) {
    return HubTile('Tarefas', 'Tudo em dia', 'Você fez as ${_n(total, 'tarefa', 'tarefas')} da semana.', progress: 1);
  }
  return HubTile('Tarefas', _n(open, 'pendente', 'pendentes'), 'de $total esta semana', progress: (total - open) / total, needsAction: true);
}

/// Bloco "para validar" do professor.
HubTile validateTile(int n) => n <= 0
    ? const HubTile('Para validar', 'Nada a validar', 'As tarefas que seus alunos marcarem aparecem aqui.')
    : HubTile('Para validar', _n(n, 'tarefa', 'tarefas'), 'marcadas pelos alunos', needsAction: true);

/// Bloco de alunos do professor.
HubTile studentsTile(int n) => n <= 0
    ? const HubTile('Alunos', 'Nenhum ainda', 'Convide ou cadastre o primeiro.')
    : HubTile('Alunos', _n(n, 'aluno', 'alunos'), 'cadastrados');

/// Bloco da agenda do aluno.
HubTile agendaTile({required String? nextText}) => nextText == null
    ? const HubTile('Minha agenda', 'Sem aulas marcadas', 'Veja aqui quando seu professor marcar.')
    : HubTile('Minha agenda', nextText, 'próxima aula');
