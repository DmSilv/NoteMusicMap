import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'dictation_button.dart';
import 'recovery_help_page.dart';
import 'safe_input.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Ajuda e suporte": o passo a passo de acesso, a página de perguntas e respostas e o relato de um problema.
Future<void> showSupportSheet(BuildContext context, AppState app) {
  return showDsSheet(
    context,
    title: tr('Ajuda e suporte'),
    listenable: app,
    children: (c) => [
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          DsNavRow(Icons.help_outline_rounded, tr('Perdi meu acesso'), tr('Passo a passo para voltar à sua conta'), () {
            Navigator.of(c).pop();
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RecoveryHelpPage(app: app)));
          }),
          Divider(height: 1, color: AppColors.outline),
          DsNavRow(Icons.quiz_outlined, tr('Perguntas e respostas'), tr('Trocar de celular, e-mail, apagar a conta'), openHelpPage),
          Divider(height: 1, color: AppColors.outline),
          DsNavRow(Icons.report_gmailerrorred_outlined, tr('Relatar um problema'), tr('Conte o que aconteceu'), () {
            Navigator.of(c).pop();
            showProblemSheet(context, app);
          }),
        ]),
      ),
      const SizedBox(height: Ds.s12),
      Text(tr('O suporte nunca pede a sua chave nem o código que chega por e-mail.'), style: Ds.support()),
    ],
  );
}

/// Relatar um problema: um texto curto. Não abre conversa: o desenvolvedor lê e decide se responde (aparece em Avisos).
Future<void> showProblemSheet(BuildContext context, AppState app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _ProblemSheet(app: app),
  );
}

class _ProblemSheet extends StatefulWidget {
  final AppState app;
  const _ProblemSheet({required this.app});

  @override
  State<_ProblemSheet> createState() => _ProblemSheetState();
}

class _ProblemSheetState extends State<_ProblemSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.app.sendProblem(_text.text);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = r.error;
      });
      return;
    }
    Navigator.pop(context);
    widget.app.say(r.replyable ? tr('Recebi o seu relato. Se eu abrir uma conversa, ela aparece em Avisos.') : tr('Relato enviado. Obrigado!'));
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final replyable = app.linkEnabled && !app.linkUnavailable;
    return Padding(
      padding: EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Relatar um problema'), style: Ds.title()),
          const SizedBox(height: Ds.s8),
          Text(
            replyable
                ? tr('Eu leio e, se precisar, abro uma conversa com você. Ela aparece em Avisos.')
                : tr('Sem o vínculo online ligado não consigo responder, mas eu leio o que você escrever.'),
            style: Ds.support(),
          ),
          const SizedBox(height: Ds.s12),
          TextField(
            controller: _text,
            inputFormatters: const [SafeText.note()],
            maxLength: 400,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('O que aconteceu?'),
              alignLabelWithHint: true,
              suffixIcon: DictationButton(app: app, controller: _text),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: Ds.s8), child: Text(_error!, style: TextStyle(color: AppColors.sharp))),
          Text(tr('Vão o seu texto, a versão do app e, com o vínculo ligado, o código do perfil. Sem e-mail nem áudio.'), style: Ds.support()),
          const SizedBox(height: Ds.s12),
          DsPrimaryButton(
            onPressed: _busy || _text.text.trim().length < 5 ? null : _send,
            icon: Icons.send_rounded,
            label: _busy ? tr('Enviando…') : tr('Enviar relato'),
          ),
        ]),
      ),
    );
  }
}
