import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../link/pay_service.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart' show AppCard;

/// Tela ESCONDIDA de teste do Pix (toque longo no título de "Minha conta"). Serve para provar um pagamento real de R$ 1
/// de ponta a ponta antes de existir a tela "Plano". Só funciona para o perfil liberado no servidor (`PAY_TEST_CODES`).
/// Texto em português fixo de propósito: não é parte do app para o público; a tela "Plano" definitiva será traduzida.
class PayTestPage extends StatefulWidget {
  final AppState app;
  const PayTestPage({super.key, required this.app});

  @override
  State<PayTestPage> createState() => _PayTestPageState();
}

class _PayTestPageState extends State<PayTestPage> {
  final PayService _svc = PayService();
  PayReply? _plan;
  PayReply? _pix;
  PayReply? _last; // última conferência
  bool _busy = false;
  String _msg = '';
  Timer? _poll;
  int _tries = 0;

  String get _code => widget.app.profile.shareCode;
  String get _secret => widget.app.profile.secret;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _svc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _svc.plan(_code, _secret);
    if (mounted) setState(() => _plan = r);
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _msg = '';
      _pix = null;
      _last = null;
    });
    final r = await _svc.payNew(_code, _secret, 't');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok && r.id.isNotEmpty) {
        _pix = r;
        _tries = 0;
      } else {
        _msg = r.off ? 'Pix desligado no servidor.' : (r.offline ? 'Sem conexão. Tente de novo.' : 'Não consegui gerar o Pix (${r.error.isEmpty ? 'erro' : r.error}).');
      }
    });
    if (_pix != null) {
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check());
    }
  }

  Future<void> _check() async {
    final p = _pix;
    if (p == null) return;
    _tries++;
    final r = await _svc.payCheck(_code, _secret, p.id);
    if (!mounted) return;
    setState(() => _last = r);
    if ((r.ok && r.status == 'approved') || _tries > 150) _poll?.cancel(); // ~12 minutos
  }

  String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _status() {
    final p = _plan;
    if (p == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (!p.ok) return Text(p.offline ? 'Sem conexão com o servidor.' : 'Erro ao consultar o plano (${p.error}).');
    final pro = (_last != null && _last!.ok) ? _last!.pro : p.pro;
    final until = (_last != null && _last!.ok) ? _last!.until : p.until;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(pro ? 'Pro ativo até ${_when(until)}' : 'Plano grátis (sem Pro)', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text('Pix no servidor: ${p.enabled ? 'ligado' : 'desligado'}  ·  este perfil pode testar: ${p.test ? 'sim' : 'não'}', style: TextStyle(color: AppColors.textDim)),
    ]);
  }

  Widget _pixCard() {
    final p = _pix!;
    final approved = _last != null && _last!.ok && _last!.status == 'approved';
    Uint8List? img;
    try {
      img = base64Decode(p.qrBase64);
    } catch (_) {}
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (approved)
        AppCard(
          child: Row(children: [
            Icon(Icons.check_circle_rounded, color: AppColors.inTune, size: 32),
            const SizedBox(width: 12),
            const Expanded(child: Text('Pagamento aprovado! O Pro foi liberado.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
        )
      else ...[
        Text('Pague R\$ ${p.amount.toStringAsFixed(2).replaceAll('.', ',')} pelo app do seu banco (Pix copia e cola ou QR).', style: const TextStyle(fontSize: 15, height: 1.4)),
        const SizedBox(height: 12),
        if (img != null)
          Center(child: Container(color: Colors.white, padding: const EdgeInsets.all(10), child: Image.memory(img, width: 220, height: 220, filterQuality: FilterQuality.none))),
        const SizedBox(height: 12),
        SelectableText(p.qr, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: p.qr));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pix copiado.')));
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copiar Pix'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(child: Text('Aguardando o pagamento (status: ${_last?.status.isNotEmpty == true ? _last!.status : p.status.isNotEmpty ? p.status : 'pending'})', style: TextStyle(color: AppColors.textDim))),
        ]),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final can = _plan != null && _plan!.ok && _plan!.enabled && _plan!.test;
    return Scaffold(
      appBar: AppBar(title: const Text('Plano Pro · teste do Pix')),
      body: DsPageSafe(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            AppCard(child: _status()),
            const SizedBox(height: 16),
            if (_plan != null && _plan!.ok && !can)
              Text(_plan!.enabled ? 'Este perfil não está liberado para o teste (PAY_TEST_CODES).' : 'O Pix está desligado no servidor (PAY_ENABLED).', style: TextStyle(color: AppColors.textDim))
            else if (can) ...[
              if (_pix == null) ...[
                const Text('Teste de pagamento real: R\$ 1,00 por 1 dia de Pro, só para este perfil.', style: TextStyle(fontSize: 15, height: 1.4)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _busy ? null : _generate, child: Text(_busy ? 'Gerando...' : 'Gerar Pix de teste (R\$ 1,00)')),
              ] else
                _pixCard(),
              if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg, style: TextStyle(color: AppColors.sharp))),
            ],
          ],
        ),
      ),
    );
  }
}
