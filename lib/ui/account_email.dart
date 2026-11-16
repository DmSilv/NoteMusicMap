import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'devices_page.dart' show pickDeviceToDrop;
import 'theme.dart';
import 'widgets.dart';

/// "E-mail da conta" (Minha conta): liga um e-mail ao perfil para recuperá-lo em outro aparelho, SEM senha.
/// O app pede um código, o servidor manda 6 dígitos para o e-mail e a pessoa digita aqui. Mesma tela para
/// "Entrar com e-mail" num aparelho novo (o aparelho novo entra na conta, que pode ficar em até 5 aparelhos).
class AccountEmailBody extends StatefulWidget {
  final AppState app;

  /// Chamado quando entrar com e-mail deu certo (a subtela se fecha).
  final VoidCallback? onSignedIn;
  const AccountEmailBody({super.key, required this.app, this.onSignedIn});

  @override
  State<AccountEmailBody> createState() => _AccountEmailBodyState();
}

class _AccountEmailBodyState extends State<AccountEmailBody> {
  final _email = TextEditingController();
  final _otp = TextEditingController();
  bool _login = false; // false = ligar o e-mail a esta conta; true = entrar numa conta que já tem e-mail
  bool _changing = false; // trocar o e-mail que já está ligado
  bool _codeStep = false;
  bool _busy = false;
  String? _error;

  AppState get app => widget.app;

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() job, {required void Function() onOk}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final problem = await job();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = problem;
    });
    if (problem == null) onOk();
  }

  Future<void> _sendCode() => _run(
        () => _login ? app.emailLoginSend(_email.text) : app.emailSendCode(_email.text),
        onOk: () {
          _otp.clear();
          setState(() => _codeStep = true);
          app.say(tr('Código enviado. Confira também o spam.'));
        },
      );

  /// Entra na conta; se ela já está em 5 aparelhos, a pessoa escolhe qual sai e o mesmo código vale de novo.
  Future<String?> _loginConfirm() async {
    var problem = await app.emailLoginConfirm(_email.text, _otp.text);
    if (problem == AppState.deviceLimitProblem && mounted) {
      final drop = await pickDeviceToDrop(context, app);
      if (drop == null) return tr('Nada mudou. Para entrar, escolha um aparelho para sair.');
      problem = await app.emailLoginConfirm(_email.text, _otp.text, drop: drop);
      if (problem == AppState.deviceLimitProblem) problem = tr('Não foi possível concluir. Tente de novo.');
    }
    return problem;
  }

  Future<void> _confirm() => _run(
        () => _login ? _loginConfirm() : app.emailConfirm(_email.text, _otp.text),
        onOk: () {
          if (_login) {
            app.say(tr('Conta recuperada neste aparelho.'));
            widget.onSignedIn?.call();
          } else {
            app.say(tr('E-mail ligado.'));
            setState(() {
              _changing = false;
              _codeStep = false;
              _email.clear();
              _otp.clear();
            });
          }
        },
      );

  Future<void> _unlink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Remover o e-mail?')),
        content: Text(tr('Sem ele, só a chave de recuperação leva a conta a outro aparelho.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Remover'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(app.emailUnlink, onOk: () => app.say(tr('E-mail removido.')));
  }

  void _back() => setState(() {
        _codeStep = false;
        _error = null;
        _otp.clear();
      });

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: Ds.s8),
        child: Text(t, style: const TextStyle(fontSize: Ds.fontTitle, fontWeight: FontWeight.w800)),
      );

  Widget _errorLine() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: Ds.s12),
          child: Text(_error!, style: TextStyle(color: AppColors.sharp, fontWeight: FontWeight.w700, fontSize: Ds.fontLabel + 0.5)),
        );

  Widget _primary(String label, VoidCallback? onPressed) => SizedBox(
        width: double.infinity,
        height: Ds.primaryHeight,
        child: FilledButton(
          onPressed: _busy ? null : onPressed,
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final linked = app.emailHint.isNotEmpty;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (linked && !_changing && !_login)
          ..._linkedView()
        else if (_codeStep)
          ..._codeView()
        else
          ..._emailView(),
      ]),
    );
  }

  List<Widget> _linkedView() => [
        _title(tr('E-mail ligado')),
        Text(app.emailHint, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: Ds.s8),
        Text(tr('Com ele você recupera a conta em outro aparelho, sem senha. Guardamos só uma versão embaralhada do e-mail.'), style: Ds.support()),
        _errorLine(),
        const SizedBox(height: Ds.s16),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
              onPressed: _busy ? null : () => setState(() => _changing = true),
              child: Text(tr('Trocar e-mail')),
            ),
          ),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
              onPressed: _busy ? null : _unlink,
              child: Text(tr('Remover e-mail')),
            ),
          ),
        ]),
      ];

  List<Widget> _emailView() => [
        _title(_login ? tr('Entrar com e-mail') : tr('Ligar um e-mail à conta')),
        Text(
          _login
              ? tr('Use o e-mail que você ligou à sua conta. Este aparelho entra nela (até 5 aparelhos). O que ficou guardado só no outro aparelho (anotações, histórico) não vem junto.')
              : tr('Mandamos um código para o seu e-mail e você digita aqui: não tem senha para lembrar. Com ele dá para recuperar a conta se você perder o celular.'),
          style: Ds.support(),
        ),
        const SizedBox(height: Ds.s16),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          textInputAction: TextInputAction.done,
          maxLength: 120,
          decoration: InputDecoration(labelText: tr('Seu e-mail'), counterText: ''),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) {
            if (looksLikeEmail(_email.text) && !_busy) _sendCode();
          },
        ),
        _errorLine(),
        const SizedBox(height: Ds.s16),
        _primary(tr('Enviar código'), looksLikeEmail(_email.text) ? _sendCode : null),
        const SizedBox(height: Ds.s8),
        if (!_login && !_changing)
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
            onPressed: _busy ? null : () => setState(() {
                  _login = true;
                  _error = null;
                }),
            child: Text(tr('Já tenho conta em outro aparelho')),
          )
        else
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
            onPressed: _busy ? null : () => setState(() {
                  _login = false;
                  _changing = false;
                  _error = null;
                }),
            child: Text(tr('Voltar')),
          ),
      ];

  List<Widget> _codeView() => [
        _title(tr('Digite o código')),
        Text(tr('Enviamos 6 dígitos para {0}. Eles valem por 10 minutos.', [_email.text.trim().toLowerCase()]), style: Ds.support()),
        const SizedBox(height: Ds.s16),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 8),
          decoration: InputDecoration(hintText: '······', counterText: '', labelText: tr('Código')),
          onChanged: (v) {
            setState(() => _error = null);
            if (v.length == 6 && !_busy) _confirm();
          },
        ),
        _errorLine(),
        const SizedBox(height: Ds.s16),
        _primary(tr('Confirmar'), _otp.text.length == 6 ? _confirm : null),
        const SizedBox(height: Ds.s8),
        Row(children: [
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
              onPressed: _busy ? null : _sendCode,
              child: Text(tr('Reenviar código')),
            ),
          ),
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(Ds.tap)),
              onPressed: _busy ? null : _back,
              child: Text(tr('Mudar e-mail')),
            ),
          ),
        ]),
      ];
}
