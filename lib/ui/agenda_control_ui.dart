import 'dart:convert';
import 'dart:typed_data';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../link/agenda_extras.dart';
import '../link/link_service.dart' show PickRequest, StudentWarn;
import '../platform/save_text.dart';
import 'agenda_actions.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tudo da agenda que dá controle ao professor e explica o fluxo para os dois lados:
/// caixa de pedidos e avisos, histórico, ajustes, guia "Qual escolher?", ajuda do aluno, aviso do aluno e calendário do celular.

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _whenOf(int ms) => fmtSlotWhen(DateTime.fromMillisecondsSinceEpoch(ms), DateTime.now());

String _warnText(String kind) => switch (kind) {
      'no' => tr('Não vou conseguir ir'),
      'rs' => tr('Queria remarcar'),
      _ => tr('Vou me atrasar'),
    };

// ---------------- Professor: pedidos e avisos ----------------

/// Cartão no topo da agenda do professor: só aparece quando há pedido ou aviso esperando.
class TeacherInboxCard extends StatelessWidget {
  final AppState app;
  const TeacherInboxCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final n = app.inboxCount;
    if (n == 0) return const SizedBox.shrink();
    final late = app.studentWarns.any((w) => w.late);
    final color = AppColors.attention;
    return Padding(
      padding: const EdgeInsets.only(top: Ds.s8, bottom: Ds.s4),
      child: InkWell(
        borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
        onTap: () => showTeacherInboxSheet(context, app),
        child: Container(
          padding: const EdgeInsets.all(Ds.s12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(Ds.radiusControl + 4),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Row(children: [
            Icon(Icons.mark_email_unread_outlined, color: color),
            const SizedBox(width: Ds.s12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n == 1 ? tr('1 pedido ou aviso de aluno') : tr('{0} pedidos e avisos de alunos', [n]), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(late ? tr('Tem aviso em cima da hora. Toque para decidir.') : tr('Nada muda na agenda até você decidir. Toque para ver.'), style: Ds.support()),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

/// A caixa com os pedidos de horário (aceitar ou recusar) e os avisos dos alunos (falta justificada, remarcar, ignorar).
Future<void> showTeacherInboxSheet(BuildContext context, AppState app) {
  return showDsSheet(context, title: tr('Pedidos e avisos dos alunos'), listenable: app, children: (c) {
    Future<void> run(Future<String?> Function() f) async {
      final err = await f();
      if (err != null) app.say(err);
    }

    Widget head(String t) => Padding(padding: const EdgeInsets.fromLTRB(0, Ds.s12, 0, Ds.s8), child: Text(t, style: Ds.section()));
    return [
      Text(tr('O aluno só avisa ou pede. A aula não muda até você decidir.'), style: Ds.support()),
      if (app.pickReqs.isNotEmpty) ...[
        head(tr('Pedidos de horário')),
        for (final q in app.pickReqs) _requestCard(app, q, run),
      ],
      if (app.studentWarns.isNotEmpty) ...[
        head(tr('Avisos sobre aulas')),
        for (final w in app.studentWarns) _warnCard(c, app, w, run),
      ],
      if (app.inboxCount == 0)
        Padding(padding: const EdgeInsets.only(top: Ds.s16), child: Text(tr('Nenhum pedido ou aviso esperando.'), style: Ds.support())),
    ];
  });
}

Widget _requestCard(AppState app, PickRequest q, Future<void> Function(Future<String?> Function()) run) {
  final name = app.studentByCode(q.student)?.name ?? tr('Um aluno');
  return Padding(
    padding: const EdgeInsets.only(bottom: Ds.s8),
    child: AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('{0} pediu o horário', [name]), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: Ds.s4),
        Text(describeSlot(q.slot), style: Ds.support()),
        const SizedBox(height: Ds.s12),
        Row(children: [
          Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.tap)), onPressed: () => run(() => app.answerRequest(q, false)), child: Text(tr('Recusar')))),
          const SizedBox(width: Ds.s8),
          Expanded(child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, Ds.tap)), onPressed: () => run(() => app.answerRequest(q, true)), child: Text(tr('Aceitar')))),
        ]),
      ]),
    ),
  );
}

Widget _warnCard(BuildContext context, AppState app, StudentWarn w, Future<void> Function(Future<String?> Function()) run) {
  final st = app.studentByCode(w.student);
  final name = st?.name ?? tr('Um aluno');
  return Padding(
    padding: const EdgeInsets.only(bottom: Ds.s8),
    child: AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('$name: ${_warnText(w.kind)}', style: const TextStyle(fontWeight: FontWeight.w800))),
          if (w.late)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.attention.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
              child: Text(tr('em cima da hora'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: Ds.s4),
        Text(tr('Aula de {0}', [_whenOf(w.occ)]), style: Ds.support()),
        const SizedBox(height: Ds.s12),
        Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
          OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.tap)), onPressed: () => run(() => app.answerWarn(w, 'ig')), child: Text(tr('Ignorar'))),
          if (st != null)
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.tap)),
              onPressed: () async {
                final err = await app.answerWarn(w, 'rs');
                if (err != null) return app.say(err);
                if (!context.mounted) return;
                Navigator.of(context).pop();
                final o = _occurrenceOf(app, w);
                if (o != null && context.mounted) await moveOccurrenceFlow(context, app, o);
              },
              child: Text(tr('Remarcar')),
            ),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, Ds.tap)), onPressed: () => run(() => app.answerWarn(w, 'ok')), child: Text(tr('Falta justificada'))),
        ]),
      ]),
    ),
  );
}

SlotOccurrence? _occurrenceOf(AppState app, StudentWarn w) {
  final s = app.agenda.where((x) => x.id == w.slotId && !x.canceled).firstOrNull;
  if (s == null || !s.occurrencesBetween(w.occ, w.occ + 1).contains(w.occ)) return null;
  return SlotOccurrence(s, w.occ);
}

// ---------------- Professor: histórico e ajustes ----------------

Future<void> showAgendaHistorySheet(BuildContext context, AppState app) {
  return showDsSheet(context, title: tr('Histórico da agenda'), listenable: app, children: (c) {
    if (app.agendaLog.isEmpty) {
      return [Text(tr('Ainda não há nada aqui. O que mudar na agenda (você ou seus alunos) aparece nesta lista, só para você.'), style: Ds.support())];
    }
    return [
      Text(tr('Só você vê esta lista. Ela guarda as últimas {0} mudanças.', [kMaxAgendaLog]), style: Ds.support()),
      const SizedBox(height: Ds.s8),
      for (final e in app.agendaLog)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Ds.s8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 92,
              child: Text('${fmtDayMonth(DateTime.fromMillisecondsSinceEpoch(e.at))} ${_hm(DateTime.fromMillisecondsSinceEpoch(e.at))}', style: Ds.support()),
            ),
            Expanded(child: Text(e.text, style: const TextStyle(height: 1.3))),
          ]),
        ),
    ];
  });
}

/// Ajustes de quem manda na agenda: avisos dos alunos (todos) e o que cada aluno pode, com o guia de decisões.
Future<void> showAgendaControlSheet(BuildContext context, AppState app) {
  return showDsSheet(context, title: tr('Controle da agenda'), listenable: app, children: (c) {
    return [
      Text(tr('Você decide o que o aluno pode fazer. A agenda é sua: o aluno só vê, avisa e, nos horários que você liberar, pede ou pega.'), style: Ds.support()),
      const SizedBox(height: Ds.s12),
      AppCard(
        padding: EdgeInsets.zero,
        child: SwitchListTile(
          secondary: Icon(Icons.mark_email_unread_outlined, color: AppColors.textDim),
          title: Text(tr('Receber avisos dos alunos'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            app.warnsMuted
                ? tr('Desligado: o aluno vê "este professor não recebe avisos por aqui" e fala com você direto.')
                : tr('Ligado: o aluno pode avisar "não vou" ou "queria remarcar". Nada muda na agenda sem você.'),
            style: Ds.support(),
          ),
          value: !app.warnsMuted,
          onChanged: (v) async {
            final err = await app.setWarnsAllowed(v);
            if (err != null) app.say(err);
          },
        ),
      ),
      const SizedBox(height: Ds.s8),
      Text(tr('Para um aluno só (liga ou desliga "pegar horário" e os avisos dele), abra a ficha do aluno › Controle do aluno.'), style: Ds.support()),
      const SizedBox(height: Ds.s12),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          DsNavRow(Icons.help_outline_rounded, tr('Qual escolher?'), tr('Cancelar, remarcar, pausar, desativar ou encerrar'), () => showChoiceGuide(context)),
          const Divider(height: 1),
          DsNavRow(Icons.history_rounded, tr('Histórico da agenda'), tr('O que mudou e quem mudou'), () => showAgendaHistorySheet(context, app)),
          const Divider(height: 1),
          DsNavRow(Icons.calendar_month_outlined, tr('Adicionar ao calendário do celular'), tr('Baixa um arquivo com as suas aulas'), () => exportAgendaCalendar(context, app, forTeacher: true)),
        ]),
      ),
    ];
  });
}

/// "Qual escolher?": a diferença entre as formas de parar ou mudar uma aula, sem jargão.
Future<void> showChoiceGuide(BuildContext context) {
  Widget item(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: Ds.s16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsIconBadge(icon, size: 40),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              const SizedBox(height: Ds.s4),
              Text(body, style: Ds.support()),
            ]),
          ),
        ]),
      );
  return showDsSheet(context, title: tr('Qual escolher?'), listenable: ValueNotifier(0), children: (c) => [
        Text(tr('Todas avisam o aluno. A diferença é por quanto tempo e o que fica guardado.'), style: Ds.support()),
        const SizedBox(height: Ds.s16),
        item(Icons.event_busy_rounded, tr('Cancelar uma aula'), tr('Só aquela data. Uma aula que se repete toda semana continua nas outras semanas.')),
        item(Icons.event_repeat_rounded, tr('Remarcar'), tr('Muda uma data para outro dia ou hora. O resto da regra semanal não muda.')),
        item(Icons.swap_horiz_rounded, tr('Trocar'), tr('Dois alunos trocam de horário entre si, só nessa data.')),
        item(Icons.pause_circle_outline_rounded, tr('Pausar (férias, viagem)'), tr('Cancela as aulas de todos num período. Elas voltam sozinhas depois.')),
        item(Icons.person_off_outlined, tr('Desativar o aluno'), tr('Ele sai do seu dia a dia, mas o histórico fica. Não conta no limite do plano grátis e você reativa quando quiser.')),
        item(Icons.link_off, tr('Encerrar o vínculo'), tr('Fim da relação: as aulas e tarefas dele no servidor são apagadas. Para voltar, o aluno lê o seu QR de novo.')),
      ]);
}

// ---------------- Aluno ----------------

/// "Como funciona" da agenda do aluno: o que ele pode e o que não pode, e onde decide o professor.
Future<void> showStudentAgendaHelp(BuildContext context) {
  Widget item(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: Ds.s16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsIconBadge(icon, size: 40),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              const SizedBox(height: Ds.s4),
              Text(body, style: Ds.support()),
            ]),
          ),
        ]),
      );
  return showDsSheet(context, title: tr('Como funciona a sua agenda'), listenable: ValueNotifier(0), children: (c) => [
        Text(tr('A agenda é do seu professor: é ele quem marca, muda e cancela as aulas. Você acompanha tudo por aqui.'), style: Ds.support()),
        const SizedBox(height: Ds.s16),
        item(Icons.event_available_outlined, tr('Ver as aulas'), tr('Os dias com pontinhos têm aula. Toque no dia para ver horário, link da sala e observações.')),
        item(Icons.notifications_active_outlined, tr('Avisos'), tr('Se o professor marcar, mudar ou cancelar uma aula, você recebe um aviso no sino e, se ativar, no celular.')),
        item(Icons.mark_email_unread_outlined, tr('Não vai poder ir?'), tr('Toque em "Avisar o professor" na aula. Isso só avisa: a aula continua marcada até ele decidir.')),
        item(Icons.add_task_rounded, tr('Pegar horário'), tr('Quando o professor deixa horários livres, você pega um. Se ele pedir confirmação, a aula só entra depois que ele aceitar. Pegou sem querer? Dá para desfazer nos primeiros 10 minutos.')),
        item(Icons.videocam_outlined, tr('Aula online'), tr('O botão "Entrar" aparece quando o professor coloca o link da sala.')),
        item(Icons.calendar_month_outlined, tr('Calendário do celular'), tr('Use o botão de calendário no alto para levar as aulas para o calendário do seu celular.')),
      ]);
}

/// ALUNO: avisa o professor sobre uma aula (não muda a aula).
Future<void> showWarnSheet(BuildContext context, AppState app, SlotOccurrence o) async {
  final s = o.slot;
  final who = s.teacherName.isNotEmpty ? s.teacherName : tr('o professor');
  final kind = await showDsSheetResult<String>(context, title: tr('Avisar {0}', [who]), children: (c) => [
        Text(tr('Isso só manda um aviso. A aula de {0} continua marcada até o professor decidir.', [_whenOf(o.startMs)]), style: Ds.support()),
        const SizedBox(height: Ds.s16),
        for (final k in const ['no', 'rs', 'late'])
          Padding(
            padding: const EdgeInsets.only(bottom: Ds.s8),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap), alignment: Alignment.centerLeft),
              onPressed: () => Navigator.pop(c, k),
              child: Text(_warnText(k)),
            ),
          ),
      ]);
  if (kind == null || !context.mounted) return;
  final err = await app.sendWarn(s, o.startMs, kind);
  app.say(err ?? tr('Aviso enviado. {0} decide e você vê a resposta aqui.', [who]));
}

/// Folha de baixo simples que devolve uma escolha (o [showDsSheet] só mostra).
Future<T?> showDsSheetResult<T>(BuildContext context, {required String title, required List<Widget> Function(BuildContext) children}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Ds.title()),
        const SizedBox(height: Ds.s8),
        ...children(c),
      ]),
    ),
  );
}

/// Texto curto do que aconteceu com o aviso que o aluno mandou para esta aula (null = não mandou).
String? warnStatusText(SentWarn? w) {
  if (w == null) return null;
  return switch (w.state) {
    'ok' => tr('Professor registrou o seu aviso'),
    'rs' => tr('Professor vai remarcar'),
    'ig' => tr('Professor viu o aviso'),
    _ => tr('Aviso enviado: esperando o professor'),
  };
}

// ---------------- Calendário do celular ----------------

/// Gera o arquivo .ics com as aulas: baixa na web e abre o compartilhar do celular nos apps.
Future<void> exportAgendaCalendar(BuildContext context, AppState app, {required bool forTeacher}) async {
  final text = app.agendaIcsText(forTeacher: forTeacher);
  if (!text.contains('BEGIN:VEVENT')) {
    app.say(tr('Não há aulas marcadas para levar ao calendário.'));
    return;
  }
  const name = 'aulas-notemusic.ics';
  if (saveTextSupported()) {
    app.say(saveTextFile(name, 'text/calendar', text) ? tr('Arquivo baixado. Abra-o para adicionar as aulas ao seu calendário.') : tr('Não foi possível baixar o arquivo.'));
    return;
  }
  try {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(Uint8List.fromList(utf8.encode(text)), mimeType: 'text/calendar', name: name)],
      fileNameOverrides: [name],
      title: tr('Aulas'),
    ));
  } catch (_) {
    app.say(tr('Não foi possível compartilhar o arquivo.'));
  }
}
