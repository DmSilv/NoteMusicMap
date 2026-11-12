/// Regras do hub "Meu espaço": o que vai no bloco grande (destaque) e os textos dos blocos menores,
/// sempre dizendo o que fazer quando não há nada. Dart puro e testável.
library;

import 'agenda.dart';
import 'i18n.dart';

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
  if (d.inMinutes < 1) return tr('agora');
  if (d.inMinutes < 60) return tr('em {0} min', [d.inMinutes]);
  if (d.inHours < 24) return tr('em {0} h', [d.inHours]);
  final days = d.inDays;
  return tr('em {0} {1}', [days, days == 1 ? tr('dia') : tr('dias')]);
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
    final who = next.who.trim().isEmpty ? (isTeacher ? tr('seu aluno') : tr('seu professor')) : next.who.trim();
    if (nowMs >= next.startMs && nowMs < next.endMs) {
      return HubHero(HeroKind.ongoing, tr('Aula em andamento'), tr('Com {0}', [who]), tr('Até as {0}', [_hm(next.endMs)]));
    }
    final until = next.startMs - nowMs;
    if (until > 0 && until <= kReminderMinutes * kMsMinute) {
      final mins = (until / kMsMinute).ceil();
      return HubHero(HeroKind.soon, tr('Começa em {0}', [mins <= 1 ? tr('1 min') : '$mins min']), tr('Aula com {0}', [who]), tr('Às {0}', [_hm(next.startMs)]));
    }
    if (until > 0) {
      final when = fmtSlotWhen(DateTime.fromMillisecondsSinceEpoch(next.startMs), DateTime.fromMillisecondsSinceEpoch(nowMs));
      final kicker = isTeacher && todayCount > 0
          ? tr('Hoje · {0} {1}', [todayCount, todayCount == 1 ? tr('aula') : tr('aulas')])
          : (isTeacher ? tr('Próxima aula') : tr('Sua próxima aula'));
      return HubHero(
          HeroKind.next, kicker, _cap(when), tr('Com {0} · {1}', [who, fmtUntil(Duration(milliseconds: until))]));
    }
  }
  if (isTeacher) {
    return hasStudents
        ? HubHero(HeroKind.none, tr('Agenda'), tr('Sem aulas marcadas'), tr('Marque a primeira aula com um aluno.'))
        : HubHero(HeroKind.none, tr('Agenda'), tr('Sem alunos ainda'), tr('Convide ou cadastre seu primeiro aluno.'));
  }
  if (hasTeacher) {
    return HubHero(HeroKind.none, tr('Sua agenda'), tr('Você ainda não tem aula marcada'),
        tr('Combine com seu professor: quando ele marcar, aparece aqui.'));
  }
  return HubHero(
      HeroKind.noTeacher, tr('Estuda com um professor?'), tr('Vincule seu professor'), tr('Leia o QR dele para ver aulas e tarefas aqui.'));
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
    return HubTile(tr('Tarefas'), tr('Nenhuma tarefa'), tr('Quando seu professor passar, aparece aqui.'));
  }
  if (open == 0) {
    return HubTile(tr('Tarefas'), tr('Tudo em dia'), tr('Você fez as {0} da semana.', [_n(total, tr('tarefa'), tr('tarefas'))]), progress: 1);
  }
  return HubTile(tr('Tarefas'), _n(open, tr('pendente'), tr('pendentes')), tr('de {0} esta semana', [total]), progress: (total - open) / total, needsAction: true);
}

/// Bloco "para validar" do professor.
HubTile validateTile(int n) => n <= 0
    ? HubTile(tr('Para validar'), tr('Nada a validar'), tr('As tarefas que seus alunos marcarem aparecem aqui.'))
    : HubTile(tr('Para validar'), _n(n, tr('tarefa'), tr('tarefas')), tr('marcadas pelos alunos'), needsAction: true);

/// Bloco de alunos do professor.
HubTile studentsTile(int n) => n <= 0
    ? HubTile(tr('Alunos'), tr('Nenhum ainda'), tr('Convide ou cadastre o primeiro.'))
    : HubTile(tr('Alunos'), _n(n, tr('aluno'), tr('alunos')), tr('cadastrados'));

/// Bloco da agenda do aluno.
HubTile agendaTile({required String? nextText}) => nextText == null
    ? HubTile(tr('Agenda do aluno'), tr('Sem aulas marcadas'), tr('Veja aqui quando seu professor marcar.'))
    : HubTile(tr('Agenda do aluno'), nextText, tr('próxima aula'));
