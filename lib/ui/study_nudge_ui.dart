import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'safe_input.dart';
import 'theme.dart';
import 'widgets.dart';

/// Convite para ligar o lembrete, na hora em que ele faz sentido: quando o aluno já recebeu a primeira aula do professor.
class StudyNudgePrompt extends StatefulWidget {
  final AppState app;
  const StudyNudgePrompt({super.key, required this.app});

  @override
  State<StudyNudgePrompt> createState() => _StudyNudgePromptState();
}

class _StudyNudgePromptState extends State<StudyNudgePrompt> {
  AppState get app => widget.app;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (app.studyPromptWanted) app.refreshPush(); // só aqui sabemos se este aparelho pode receber notificação
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!app.showStudyPrompt) return const SizedBox.shrink();
        final install = app.pushStatus == PushStatus.needsInstall;
        return Padding(
          padding: const EdgeInsets.only(bottom: Ds.s12),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DsCardTitle(Icons.notifications_active_outlined, tr('Quer um lembrete da tarefa?'),
                  subtitle: tr('Avisamos antes da aula e, se você ficar uns dias sem abrir o app, um toque leve.')),
              const SizedBox(height: Ds.s8),
              Text(
                install
                    ? tr('No iPhone, primeiro adicione o app à tela inicial (Compartilhar › Adicionar à Tela de Início) e abra por lá.')
                    : tr('No máximo 2 lembretes de estudo por semana, às 18h. Dá para desligar quando quiser.'),
                style: Ds.support(),
              ),
              const SizedBox(height: Ds.s12),
              Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
                if (!install)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            final err = await app.enablePush();
                            if (err == null) app.dismissStudyPrompt();
                            app.say(err ?? tr('Lembretes ligados neste aparelho.'));
                            if (mounted) setState(() => _busy = false);
                          },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(tr('Sim, me lembre')),
                  ),
                TextButton(onPressed: app.dismissStudyPrompt, child: Text(tr('Agora não'))),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

// ---------------- Professor: quem pode precisar de um empurrãozinho ----------------

/// Lista curta, em tom amigável, de quem talvez precise de um incentivo. Só aparece quando há alguém.
class NudgeListCard extends StatelessWidget {
  final AppState app;
  const NudgeListCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final list = app.nudgeSuggestions;
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s12),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsCardTitle(Icons.waving_hand_outlined, tr('Um empurrãozinho pode ajudar'), subtitle: tr('Uma mensagem sua costuma animar mais que qualquer aviso.')),
          const SizedBox(height: Ds.s8),
          for (final n in list.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Ds.s4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.labelOf(n.student), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(n.label, style: Ds.support()),
                  ]),
                ),
                const SizedBox(width: Ds.s8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.tap)),
                  onPressed: () => showWhatsReminderSheet(context, app, n.student),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: Text(tr('Lembrar')),
                ),
              ]),
            ),
          if (list.length > 4) Text(tr('E mais {0}. Veja na lista de alunos.', [list.length - 4]), style: Ds.support()),
        ]),
      ),
    );
  }
}

/// PROFESSOR: lembrar o aluno pelo WhatsApp. O app prepara a mensagem e abre a conversa; quem envia é o professor.
Future<void> showWhatsReminderSheet(BuildContext context, AppState app, Student s) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.88),
        child: _WhatsSheet(app: app, student: s),
      ),
    ),
  );
}

class _WhatsSheet extends StatefulWidget {
  final AppState app;
  final Student student;
  const _WhatsSheet({required this.app, required this.student});

  @override
  State<_WhatsSheet> createState() => _WhatsSheetState();
}

class _WhatsSheetState extends State<_WhatsSheet> {
  AppState get app => widget.app;
  Student get s => widget.student;
  final _number = TextEditingController();
  bool _editing = false;
  int _variant = 0;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _saveNumber() {
    final n = cleanWhatsNumber(_number.text);
    if (n == null) {
      setState(() => _error = tr('Digite o DDD e o número. De outro país, comece com +.'));
      return;
    }
    app.setStudentWhats(s, n);
    setState(() {
      _editing = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final first = s.name.split(' ').first;
    final messages = reminderMessages(first, [for (final t in s.tasks) if (!t.done && t.claimedAt == null) t.title]);
    final text = messages[_variant % messages.length];
    final days = [tr('seg@@dia'), tr('ter@@dia'), tr('qua@@dia'), tr('qui@@dia'), tr('sex@@dia'), tr('sáb@@dia'), tr('dom@@dia')];
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final has = s.whats != null;
        return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s24), children: [
          Text(tr('Lembrar {0}', [first]), style: Ds.title()),
          const SizedBox(height: Ds.s12),
          if (has && !_editing)
            Row(children: [
              Icon(Icons.phone_iphone_rounded, size: 18, color: AppColors.textDim),
              const SizedBox(width: Ds.s8),
              Expanded(child: Text(whatsLabel(s.whats!), style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton(
                onPressed: () => setState(() {
                  _number.text = '+${s.whats}';
                  _editing = true;
                }),
                child: Text(tr('Trocar')),
              ),
              IconButton(tooltip: tr('Apagar o número'), onPressed: () => app.setStudentWhats(s, null), icon: const Icon(Icons.delete_outline)),
            ])
          else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  controller: _number,
                  keyboardType: TextInputType.phone,
                  inputFormatters: const [SafeText.line()],
                  maxLength: 20,
                  onSubmitted: (_) => _saveNumber(),
                  decoration: InputDecoration(labelText: tr('WhatsApp do aluno (opcional)'), hintText: '11 91234-5678', errorText: _error, counterText: ''),
                ),
              ),
              const SizedBox(width: Ds.s8),
              Padding(padding: const EdgeInsets.only(top: Ds.s4), child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ds.tap)), onPressed: _saveNumber, child: Text(tr('Guardar')))),
            ]),
            const SizedBox(height: Ds.s4),
            Text(tr('Fica só no seu aparelho. {0} recebe um aviso no app de que você o guardou.', [first]), style: Ds.support()),
          ],
          const SizedBox(height: Ds.s12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Ds.s12),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(Ds.radiusControl), border: Border.all(color: AppColors.outline)),
            child: Text(text, style: const TextStyle(height: 1.4)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: () => setState(() => _variant++), icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Outra mensagem'))),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
            onPressed: () async {
              var ok = false;
              try {
                ok = await launchUrl(whatsUri(s.whats, text), mode: LaunchMode.externalApplication);
              } catch (_) {
                ok = false;
              }
              if (ok) {
                app.markReminded(s);
              } else {
                app.say(tr('Não foi possível abrir o WhatsApp. Copie a mensagem.'));
              }
            },
            icon: const Icon(Icons.send_rounded),
            label: Text(tr('Abrir o WhatsApp')),
          ),
          const SizedBox(height: Ds.s8),
          Text(has ? tr('A conversa abre com o texto pronto. Você confere e envia.') : tr('Sem número guardado, o WhatsApp pergunta para quem enviar.'), style: Ds.support()),
          const SizedBox(height: Ds.s8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              app.say(tr('Mensagem copiada.'));
            },
            icon: const Icon(Icons.copy_rounded),
            label: Text(tr('Copiar a mensagem')),
          ),
          const SizedBox(height: Ds.s16),
          Text(tr('Programar'), style: Ds.section()),
          const SizedBox(height: Ds.s4),
          Text(tr('Nos dias marcados, {0} aparece na sua lista para você enviar.', [first]), style: Ds.support()),
          const SizedBox(height: Ds.s8),
          Wrap(spacing: Ds.s8, runSpacing: Ds.s8, children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(label: Text(days[d - 1]), selected: s.remindDays.contains(d), onSelected: (_) => app.toggleRemindDay(s, d)),
          ]),
        ]);
      },
    );
  }
}
