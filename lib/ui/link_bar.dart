import 'package:flutter/material.dart';

import '../app_state.dart';
import 'theme.dart';
import 'package:afina_core/afina_core.dart';

/// Aviso do alto da tela quando o vínculo online está DESLIGADO mas há quem dependa dele
/// (modo professor, professor ou aluno vinculado): sem ele, nada chega ao aparelho.
class LinkOffBar extends StatelessWidget {
  final AppState app;
  const LinkOffBar({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!app.linkNeedsAttention) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Material(
            color: AppColors.sharp.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.sharp.withValues(alpha: 0.7)),
              ),
              child: Row(children: [
                Icon(Icons.cloud_off_outlined, color: AppColors.sharp),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('Você está offline'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(tr('Vínculo desligado: sem avisos de alunos, aulas nem tarefas.'),
                        style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ]),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
                  onPressed: () {
                    app.setLinkEnabled(true);
                    app.say(tr('Vínculo online ligado.'));
                  },
                  child: Text(tr('Ligar')),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

Widget _connectDialog(BuildContext c, String title, String text, {String? note}) => AlertDialog(
      icon: Icon(Icons.cloud_outlined, color: AppColors.textDim),
      title: Text(title),
      content: note == null
          ? Text(text)
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(text),
              const SizedBox(height: 10),
              Text(note, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Agora não'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Conectar'))),
      ],
    );

/// Ao ligar o modo professor com o vínculo desligado: pergunta se quer conectar. **Ser professor não depende disso.**
/// true = conectar; false = "Agora não" (entra como professor sem conectar); null = fechou sem escolher (não liga nada).
/// Sem pergunta (true) se já está conectado.
Future<bool?> askTeacherLink(BuildContext context, AppState app) async {
  if (app.linkEnabled) return true;
  return showDialog<bool>(
    context: context,
    builder: (c) => _connectDialog(c, tr('Conectar com os alunos?'),
        tr('Conectado, as tarefas chegam a eles (vão código, apelido, tarefas e aulas). Pode ficar para depois.')),
  );
}

/// Antes de uma ação que só funciona conectado (convidar, vincular, enviar). [why] diz para que serve agora.
/// Devolve true se está conectado (já estava ou a pessoa aceitou); "Agora não" não conecta nada.
Future<bool> ensureTeacherLink(BuildContext context, AppState app, String why) async {
  if (app.linkEnabled) return true;
  if (!await _askConnectNow(context, why)) return false;
  app.setLinkEnabled(true);
  return true;
}

Future<bool> _askConnectNow(BuildContext context, String why) async =>
    await showDialog<bool>(
        context: context,
        builder: (c) => _connectDialog(c, tr('Conectar agora?'), why, note: tr('Ao conectar vão: código, apelido, tarefas e aulas.'))) ==
    true;

/// Quem está sem conexão e guarda alunos com código (mesmo com o modo professor desligado) vai se vincular como ALUNO: o vínculo
/// é um só, então esses alunos também vão. Só pergunta: quem conecta é o próprio addMyTeacher, que sincroniza em seguida.
Future<bool> confirmStudentLink(BuildContext context, AppState app) async {
  if (app.linkEnabled || !app.students.any((s) => s.code != null)) return true;
  return _askConnectNow(context, tr('Isso conecta o app todo: seus alunos com código, tarefas e aulas guardados também vão.'));
}

/// Antes de desligar o modo professor: diz o que some da tela e que nada é apagado. Devolve true se a pessoa confirmou.
Future<bool> confirmTurnOffTeacher(BuildContext context, AppState app) async {
  final n = app.students.length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.groups_outlined, color: AppColors.textDim),
      title: Text(tr('Desligar o modo professor?')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('A área de professor some: você deixa de ver alunos, agenda e tarefas e não envia nada a eles.')),
        const SizedBox(height: 10),
        Text(n == 0
            ? tr('Nada é apagado. Ao ligar de novo, tudo volta.')
            : (n == 1 ? tr('Nada é apagado: o aluno e o histórico ficam guardados e voltam quando você ligar de novo.') : tr('Nada é apagado: os {0} alunos e o histórico ficam guardados e voltam quando você ligar de novo.', [n]))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Manter ligado'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Desligar'))),
      ],
    ),
  );
  return ok == true;
}

/// Depois de desligar o modo professor: se não há professor, aula, agenda nem aluno com código, o vínculo online não serve mais
/// a nada; pergunta se quer desligá-lo também. Se algo depende dele, não faz nada (ninguém perde avisos sem querer).
Future<void> offerLinkOffAfterTeacher(BuildContext context, AppState app) async {
  final needed = app.hasTeacherSide || app.students.any((s) => s.code != null);
  if (!app.linkEnabled || needed) return;
  final off = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.cloud_off_outlined, color: AppColors.textDim),
      title: Text(tr('Desligar também o vínculo online?')),
      content: Text(tr('Sem professor nem aluno vinculado, ele não é mais necessário. Dá para ligar de novo em Minha conta.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Manter ligado'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Desligar'))),
      ],
    ),
  );
  if (off == true) app.setLinkEnabled(false);
}

/// Aviso antes de desligar o vínculo: diz claramente o que deixa de funcionar.
Future<bool> confirmDisableLink(BuildContext context, AppState app) async {
  final q = app.linkQueueSize;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.cloud_off_outlined, color: AppColors.sharp),
      title: Text(tr('Desligar o vínculo online?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Você ficará offline:'), style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(tr('• não recebe avisos de alunos nem do professor\n• novos vínculos com você não chegam\n• aulas, tarefas e horários não são enviados nem recebidos\n• os lembretes de aula param')),
          const SizedBox(height: 8),
          Text(
            tr('Seus dados continuam neste aparelho{0}. Você pode ligar de novo quando quiser.', [q > 0 ? tr(', e os {0} itens da fila ficam guardados até você ligar de novo', [q]) : '']),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Continuar online'))),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.sharp),
          onPressed: () => Navigator.pop(c, true),
          child: Text(tr('Desligar mesmo assim')),
        ),
      ],
    ),
  );
  return ok == true;
}

/// "Há uma versão nova": faixa fixa com botão para atualizar, no lugar de depender
/// de a pessoa abrir as configurações.
class UpdateBar extends StatelessWidget {
  final AppState app;
  const UpdateBar({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!app.showUpdatePrompt) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Material(
            color: AppColors.info.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.6)),
              ),
              child: Row(children: [
                Icon(Icons.system_update, color: AppColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('Versão nova disponível'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(tr('Atualize para receber as correções.'),
                        style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ]),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
                  onPressed: () => app.updateApp(),
                  child: Text(tr('Atualizar')),
                ),
                IconButton(
                  tooltip: tr('Depois'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => app.hideUpdatePrompt(hours: 6),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
