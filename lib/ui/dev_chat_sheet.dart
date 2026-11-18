import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../link/link_service.dart';
import 'design_system.dart';
import 'notifications_sheet.dart' show noticeAgo;
import 'theme.dart';

/// Conversa particular com o desenvolvedor: só esta pessoa vê. Mensagens do administrador, resposta curta,
/// e (quando ele pergunta) escolher se o apelido pode ser citado no boletim. O texto vem do servidor ao abrir.
Future<void> showDevChatSheet(BuildContext context, AppState app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => _DevChat(app: app),
  );
}

class _DevChat extends StatefulWidget {
  final AppState app;
  const _DevChat({required this.app});

  @override
  State<_DevChat> createState() => _DevChatState();
}

class _DevChatState extends State<_DevChat> {
  final _ctl = TextEditingController();
  List<DevMsg>? _msgs;
  bool _askOpen = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run(widget.app.devChat());
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<({List<DevMsg>? msgs, bool askOpen, String? error})> f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await f;
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.msgs != null) {
        _msgs = r.msgs;
        _askOpen = r.askOpen;
      } else {
        _error = r.error;
      }
    });
  }

  Future<void> _send() async {
    final t = cleanText(_ctl.text, max: kMaxDevReply);
    if (t.isEmpty || _busy) return;
    await _run(widget.app.devChat(reply: t));
    if (mounted && _error == null) _ctl.clear();
  }

  Widget _bubble(DevMsg m) {
    final mine = !m.admin;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Ds.s8),
        padding: const EdgeInsets.all(Ds.s12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: mine ? AppColors.accent.withValues(alpha: 0.16) : AppColors.surface,
          border: Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.circular(Ds.radiusCard),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (m.ref.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Ds.s4),
              child: Text(tr('Sobre: "{0}"', [m.ref]), style: Ds.support()),
            ),
          Text(m.text, style: const TextStyle(height: 1.35)),
          const SizedBox(height: Ds.s4),
          Text(m.admin ? '${tr('Desenvolvedor')} · ${noticeAgo(m.atMs)}' : noticeAgo(m.atMs), style: Ds.support()),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _msgs;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.s12, Ds.s8),
            child: Row(children: [
              Expanded(child: Text(tr('Conversa com o desenvolvedor'), style: Ds.title())),
              IconButton(onPressed: () => Navigator.of(context).pop(), tooltip: tr('Fechar'), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.all(Ds.screenPad),
              shrinkWrap: true,
              reverse: false,
              children: [
                Text(tr('Só você e o desenvolvedor veem esta conversa.'), style: Ds.support()),
                const SizedBox(height: Ds.s12),
                if (msgs == null && _busy) const Center(child: Padding(padding: EdgeInsets.all(Ds.s24), child: CircularProgressIndicator())),
                if (msgs == null && !_busy) Text(_error ?? tr('Sem conexão agora.'), style: Ds.support()),
                if (msgs != null) for (final m in msgs) _bubble(m),
                if (_askOpen)
                  Padding(
                    padding: const EdgeInsets.only(top: Ds.s4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(tr('Posso citar o seu apelido quando a sua ideia virar novidade no app?'), style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
                      const SizedBox(height: Ds.s8),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: _busy ? null : () => _run(widget.app.devChat(credit: true)),
                        child: Text(tr('Pode citar meu apelido')),
                      ),
                      const SizedBox(height: Ds.s8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: _busy ? null : () => _run(widget.app.devChat(credit: false)),
                        child: Text(tr('Prefiro ficar anônimo')),
                      ),
                    ]),
                  ),
                if (_error != null && msgs != null) Padding(padding: const EdgeInsets.only(top: Ds.s8), child: Text(_error!, style: TextStyle(color: AppColors.sharp))),
              ],
            ),
          ),
          if (msgs != null && msgs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Ds.screenPad, Ds.s4, Ds.s8, Ds.s12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: TextField(
                    controller: _ctl,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: kMaxDevReply,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(hintText: tr('Sua resposta'), counterText: ''),
                  ),
                ),
                IconButton.filled(
                  onPressed: _busy ? null : _send,
                  tooltip: tr('Enviar'),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.send_rounded),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
