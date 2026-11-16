import 'dart:async';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import 'account_email.dart';
import 'design_system.dart';
import 'devices_page.dart';
import 'settings_page.dart' show kAppName;
import 'share_sheet.dart' show shareLink;
import 'theme.dart';
import 'widgets.dart';

/// Link que, aberto no aparelho novo, já traz o código de pareamento (a câmera comum do celular abre o app).
String pairLink(String pair) => '${shareLink()}/?pair=$pair';

/// "Entrar na minha conta" no aparelho novo: o jeito mais fácil primeiro (o código que o outro aparelho mostra),
/// depois a chave de recuperação e o e-mail. Fecha sozinha quando a conta é ligada.
class JoinAccountPage extends StatefulWidget {
  final AppState app;

  /// Código já conhecido (veio de um link `?pair=`): preenche o campo.
  final String? initialPair;
  const JoinAccountPage({super.key, required this.app, this.initialPair});

  @override
  State<JoinAccountPage> createState() => _JoinAccountPageState();
}

class _JoinAccountPageState extends State<JoinAccountPage> {
  late final _pair = TextEditingController(text: widget.initialPair ?? '');
  final _key = TextEditingController();
  bool _busy = false;
  bool _useKey = false;
  String? _error;

  AppState get app => widget.app;

  @override
  void dispose() {
    _pair.dispose();
    _key.dispose();
    super.dispose();
  }

  /// Roda o pedido de entrada; com a conta cheia a pessoa escolhe qual aparelho sai e o pedido se repete.
  Future<void> _run(Future<String?> Function({String? drop}) job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    var problem = await job();
    if (problem == AppState.deviceLimitProblem && mounted) {
      final drop = await pickDeviceToDrop(context, app);
      problem = drop == null ? tr('Nada mudou. Para entrar, escolha um aparelho para sair.') : await job(drop: drop);
      if (problem == AppState.deviceLimitProblem) problem = tr('Não foi possível concluir. Tente de novo.');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = problem;
    });
    if (problem == null) {
      app.say(tr('Conta recuperada neste aparelho.'));
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairOk = normalizePairCode(_pair.text) != null;
    final keyOk = normalizeShortKey(_key.text) != null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Entrar na minha conta'))),
      body: DsPageSafe(
        child: ListView(
          padding: Ds.screen,
          children: [
            Text(tr('Já usa o {0} em outro aparelho? Ligue este à mesma conta e traga alunos, aulas e tarefas.', [kAppName]), style: Ds.support()),
            const SizedBox(height: Ds.gap),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DsCardTitle(Icons.devices_outlined, tr('Código do outro aparelho'), subtitle: tr('No outro: Minha conta › Aparelhos › Adicionar um aparelho.')),
                const SizedBox(height: Ds.s16),
                TextField(
                  controller: _pair,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  maxLength: 20,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ?&=:/._#]'))],
                  decoration: InputDecoration(labelText: tr('Código (XXXX-XXXX)'), counterText: ''),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: Ds.s12),
                SizedBox(
                  height: Ds.primaryHeight,
                  child: FilledButton.icon(
                    onPressed: _busy || !pairOk ? null : () => _run(({String? drop}) => app.pairJoin(_pair.text, drop: drop)),
                    icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                    label: Text(tr('Entrar com este código'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: Ds.s12), child: Text(_error!, style: TextStyle(color: AppColors.sharp, fontSize: Ds.fontSupport))),
              ]),
            ),
            const SizedBox(height: Ds.s8),
            AppCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                minTileHeight: Ds.tap + 8,
                leading: const Icon(Icons.key),
                title: Text(tr('Tenho a chave de recuperação'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('A chave de 25 caracteres que você guardou.'), style: Ds.support()),
                trailing: Icon(_useKey ? Icons.expand_less : Icons.expand_more),
                onTap: () => setState(() => _useKey = !_useKey),
              ),
            ),
            if (_useKey)
              Padding(
                padding: const EdgeInsets.only(top: Ds.s8),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: _key,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      maxLength: 40,
                      decoration: InputDecoration(labelText: tr('XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'), counterText: ''),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    const SizedBox(height: Ds.s12),
                    SizedBox(
                      height: Ds.tap,
                      child: FilledButton(
                        onPressed: _busy || !keyOk ? null : () => _run(({String? drop}) => app.recoveryKeyLogin(_key.text, drop: drop)),
                        child: Text(tr('Entrar com a chave')),
                      ),
                    ),
                  ]),
                ),
              ),
            if (app.emailEnabled) ...[
              const SizedBox(height: Ds.s8),
              AppCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  minTileHeight: Ds.tap + 8,
                  leading: const Icon(Icons.alternate_email),
                  title: Text(tr('Receber um código por e-mail'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tr('Use o e-mail que você ligou à conta.'), style: Ds.support()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (c) => Scaffold(
                      appBar: AppBar(title: Text(tr('Entrar com e-mail'))),
                      body: DsPageSafe(
                        child: ListView(padding: Ds.screen, children: [
                          AccountEmailBody(
                            app: app,
                            startInLogin: true,
                            onSignedIn: () {
                              Navigator.of(c).pop();
                              if (mounted) Navigator.of(context).pop(true);
                            },
                          ),
                        ]),
                      ),
                    ),
                  )),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chamado ao abrir o app por um link `?pair=` (o QR do outro aparelho): confirma e entra na conta.
/// O aviso é claro porque este aparelho deixa de usar o código atual: um link recebido de um desconhecido
/// poderia levar a pessoa para a conta dele.
Future<void> handleIncomingPairCode(BuildContext context, AppState app) async {
  final pair = app.incomingPairCode;
  if (pair == null) return;
  app.incomingPairCode = null;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Entrar numa conta?')),
      content: Text(tr('Este aparelho passa a usar uma conta que já existe e deixa o código {0}. Só continue se o link foi seu.', [app.profile.shareCode])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Agora não'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Entrar'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  var problem = await app.pairJoin(pair);
  if (problem == AppState.deviceLimitProblem && context.mounted) {
    final drop = await pickDeviceToDrop(context, app);
    problem = drop == null ? tr('Nada mudou. Para entrar, escolha um aparelho para sair.') : await app.pairJoin(pair, drop: drop);
  }
  app.say(problem == null ? tr('Conta recuperada neste aparelho.') : (problem == AppState.deviceLimitProblem ? tr('Não foi possível concluir. Tente de novo.') : problem));
}

/// "Adicionar um aparelho": mostra um QR e um código de 10 minutos para o aparelho novo. Fecha sozinha quando o outro entra.
Future<void> showAddDeviceSheet(BuildContext context, AppState app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => _AddDeviceBody(app: app),
  );
}

class _AddDeviceBody extends StatefulWidget {
  final AppState app;
  const _AddDeviceBody({required this.app});

  @override
  State<_AddDeviceBody> createState() => _AddDeviceBodyState();
}

class _AddDeviceBodyState extends State<_AddDeviceBody> {
  String? _pair;
  String? _problem;
  DateTime? _until;
  int _before = 0;
  Timer? _tick;
  Timer? _poll;
  bool _busy = true;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    _before = app.deviceList.length;
    _new();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _new() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    final r = await app.pairNew();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pair = r.pair;
      _problem = r.problem;
      _until = r.pair == null ? null : DateTime.now().add(Duration(seconds: r.ttl));
    });
    _tick?.cancel();
    _poll?.cancel();
    if (r.pair == null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Enquanto o código está na tela, olha de tempos em tempos se o aparelho novo já entrou.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_until == null || DateTime.now().isAfter(_until!)) return;
      await app.refreshDevices();
      if (!mounted) return;
      if (app.deviceList.length > _before) {
        app.say(tr('Aparelho adicionado à sua conta.'));
        Navigator.of(context).pop();
      }
    });
  }

  String _left() {
    final s = _until == null ? 0 : _until!.difference(DateTime.now()).inSeconds;
    if (s <= 0) return '';
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _share() async {
    final text = tr('Para entrar na minha conta do {0} neste aparelho, abra: {1}', [kAppName, pairLink(_pair!)]);
    try {
      await SharePlus.instance.share(ShareParams(text: text, title: kAppName));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      app.say(tr('Link copiado. Cole numa conversa para enviar.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = _left();
    final expired = _pair != null && left.isEmpty;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Ds.screenPad, 0, Ds.screenPad, Ds.s24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Adicionar um aparelho'), style: Ds.title()),
          const SizedBox(height: Ds.s8),
          Text(tr('No aparelho novo, abra o {0} e escolha "Já tenho conta". Aponte a câmera para o QR ou digite o código.', [kAppName]), style: Ds.support()),
          const SizedBox(height: Ds.s16),
          if (_busy)
            const Padding(padding: EdgeInsets.all(Ds.s32), child: Center(child: CircularProgressIndicator()))
          else if (_problem != null) ...[
            Text(_problem!, style: TextStyle(color: AppColors.sharp)),
            const SizedBox(height: Ds.s12),
            FilledButton(onPressed: _new, child: Text(tr('Tentar de novo'))),
          ] else ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Ds.radiusControl)),
                child: Opacity(opacity: expired ? 0.25 : 1, child: QrImageView(data: pairLink(_pair!), size: 180, padding: EdgeInsets.zero)),
              ),
            ),
            const SizedBox(height: Ds.s16),
            InkWell(
              borderRadius: BorderRadius.circular(Ds.radiusControl),
              onTap: expired
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: _pair!));
                      app.say(tr('Código copiado.'));
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Ds.s8),
                child: Text(_pair!, textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 4, color: expired ? AppColors.textDim : AppColors.accent)),
              ),
            ),
            Text(expired ? tr('O código venceu.') : tr('Vale por mais {0}', [left]), textAlign: TextAlign.center, style: Ds.support()),
            const SizedBox(height: Ds.s16),
            if (expired)
              FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)), onPressed: _new, icon: const Icon(Icons.refresh), label: Text(tr('Gerar outro código')))
            else
              OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)), onPressed: _share, icon: const Icon(Icons.ios_share), label: Text(tr('Enviar o link'))),
          ],
        ]),
      ),
    );
  }
}
