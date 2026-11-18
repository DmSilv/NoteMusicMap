import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../link/account_service.dart' show AccountDevice;
import 'design_system.dart';
import 'join_account_page.dart' show showAddDeviceSheet;
import 'theme.dart';
import 'widgets.dart';

/// Nome do sistema como a pessoa reconhece ("Android", "iPhone ou iPad"...).
String _osName(String os) => switch (os) {
      'android' => 'Android',
      'ios' => tr('iPhone ou iPad'),
      'windows' => 'Windows',
      'mac' => 'Mac',
      'linux' => 'Linux',
      _ => '',
    };

/// "chrome130" -> "Chrome".
String _browserName(String br) {
  final name = br.replaceAll(RegExp(r'\d+$'), '');
  return switch (name) {
    'chrome' => 'Chrome',
    'edge' => 'Edge',
    'firefox' => 'Firefox',
    'safari' => 'Safari',
    'samsung' => 'Samsung Internet',
    _ => '',
  };
}

/// Título do aparelho: o apelido que a pessoa deu, senão o modelo, senão o sistema.
String deviceTitle(AccountDevice d) {
  if (d.nick.isNotEmpty) return d.nick;
  if (d.model.isNotEmpty) return d.model;
  final os = _osName(d.os);
  return os.isNotEmpty ? os : tr('Aparelho');
}

/// Segunda linha: navegador e sistema, quando se sabe.
String deviceDetail(AccountDevice d) {
  final parts = [_browserName(d.browser), _osName(d.os)].where((s) => s.isNotEmpty).toList();
  if (d.created != null) parts.add(tr('entrou em {0}', [fmtDayMonth(d.created!)]));
  return parts.join(' · ');
}

IconData _deviceIcon(AccountDevice d) => switch (d.os) {
      'android' || 'ios' => Icons.smartphone,
      'windows' || 'mac' || 'linux' => Icons.computer,
      _ => Icons.devices_other,
    };

/// A conta está cheia: a pessoa escolhe qual aparelho sai para dar lugar a este. Devolve o id escolhido, ou null se desistiu.
Future<String?> pickDeviceToDrop(BuildContext context, AppState app) {
  final list = app.deviceChoices;
  return showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(tr('Sua conta já está em {0} aparelhos', [list.length])),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, Ds.s12),
          child: Text(tr('Escolha um para sair e dar lugar a este.'), style: Ds.support()),
        ),
        for (final d in list)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, d.id),
            child: Row(children: [
              Icon(_deviceIcon(d), color: AppColors.textDim),
              const SizedBox(width: Ds.s12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(deviceTitle(d), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: Ds.fontBody)),
                  if (deviceDetail(d).isNotEmpty) Text(deviceDetail(d), style: Ds.support()),
                ]),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s4, Ds.s16, 0),
          child: Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancelar')))),
        ),
      ],
    ),
  );
}

/// "Aparelhos": onde a conta está aberta (até 5). A pessoa vê todos, dá nome a este e tira os que não usa mais.
class DevicesBody extends StatefulWidget {
  final AppState app;
  const DevicesBody({super.key, required this.app});

  @override
  State<DevicesBody> createState() => _DevicesBodyState();
}

class _DevicesBodyState extends State<DevicesBody> {
  bool _loading = true;
  String? _busyId;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await app.refreshDevices();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _remove(AccountDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Tirar {0} da conta?', [deviceTitle(d)])),
        content: Text(tr('Ele perde o acesso na hora. Para voltar, precisa entrar de novo.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Tirar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyId = d.id);
    final problem = await app.removeDevice(d.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    app.say(problem ?? tr('Aparelho tirado da conta.'));
  }

  Future<void> _rename(AccountDevice d) async {
    final ctl = TextEditingController(text: d.nick);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Nome deste aparelho')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(hintText: tr('Ex.: Celular da Ana'), counterText: ''),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(tr('Salvar'))),
        ],
      ),
    );
    ctl.dispose();
    if (name == null || !mounted) return;
    final problem = await app.nameThisDevice(name);
    if (problem != null) app.say(problem);
  }

  Widget _row(AccountDevice d, DateTime now) {
    final detail = deviceDetail(d);
    final when = d.current ? tr('Em uso agora') : (d.lastSeen == null ? '' : tr('Visto {0}', [fmtAgo(now.difference(d.lastSeen!))]));
    final sub = [detail, when].where((s) => s.isNotEmpty).join('\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s8),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(Ds.s16, Ds.s8, Ds.s8, Ds.s8),
          leading: DsIconBadge(_deviceIcon(d), size: 40, color: d.current ? AppColors.accent : AppColors.textDim),
          title: Text(deviceTitle(d), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: Ds.fontBody)),
          subtitle: sub.isEmpty ? null : Text(sub, style: Ds.support()),
          isThreeLine: sub.contains('\n'),
          trailing: d.current
              ? IconButton(tooltip: tr('Dar um nome'), icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(d))
              : (_busyId == d.id
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: () => _remove(d), child: Text(tr('Tirar')))),
        ),
      ),
    );
  }

  /// O limite à vista: uma bolinha por vaga (cheia = aparelho na conta) e uma frase dizendo quantas faltam ou o que fazer quando lota.
  /// Todos os aparelhos da conta são iguais: qualquer um pode adicionar ou tirar outro.
  Widget _slots(int used) {
    final max = app.maxDevices;
    final free = (max - used).clamp(0, max);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('No máximo {0} aparelhos ao mesmo tempo', [max]), style: const TextStyle(fontSize: Ds.fontBody, fontWeight: FontWeight.w800)),
        const SizedBox(height: Ds.s12),
        Row(children: [
          for (var i = 0; i < max; i++)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: Ds.s8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < used ? AppColors.accent : Colors.transparent,
                border: Border.all(color: i < used ? AppColors.accent : AppColors.outline, width: 2),
              ),
              child: i < used ? Icon(Icons.smartphone, size: 16, color: AppColors.bg) : null,
            ),
        ]),
        const SizedBox(height: Ds.s12),
        Text(
          free == 0
              ? tr('Limite atingido. Para adicionar outro, tire um aparelho da lista abaixo.')
              : (free == 1 ? tr('Dá para adicionar mais 1 aparelho.') : tr('Dá para adicionar mais {0} aparelhos.', [free])),
          style: Ds.support(),
        ),
        const SizedBox(height: Ds.s4),
        Text(tr('Todos os aparelhos são iguais: qualquer um pode adicionar ou tirar outro.'), style: Ds.support()),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = [...app.deviceList]..sort((a, b) {
            if (a.current != b.current) return a.current ? -1 : 1;
            return (b.lastSeen ?? DateTime(2000)).compareTo(a.lastSeen ?? DateTime(2000));
          });
        final now = DateTime.now();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _slots(list.length),
          const SizedBox(height: Ds.s16),
          if (list.length < app.maxDevices) ...[
            SizedBox(
              height: Ds.primaryHeight,
              child: FilledButton.icon(
                onPressed: () => showAddDeviceSheet(context, app),
                icon: const Icon(Icons.add_to_queue),
                label: Text(tr('Adicionar um aparelho'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: Ds.s16),
          ],
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Ds.s24),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : Text(tr('Não foi possível ver os aparelhos agora. Tente de novo mais tarde.'), textAlign: TextAlign.center, style: Ds.support()),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: Ds.s8),
              child: Text(tr('{0} de {1} aparelhos', [list.length, app.maxDevices]), style: Ds.section()),
            ),
            for (final d in list) _row(d, now),
          ],
        ]);
      },
    );
  }
}
