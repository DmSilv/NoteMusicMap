import 'dart:async';
import 'dart:convert';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../link/pay_service.dart';
import 'design_system.dart';
import 'theme.dart';
import 'widgets.dart' show AppCard;

/// Tela "Plano": mostra se o professor está no Pro e até quando, deixa assinar por Pix (mensal ou anual), lista os pagamentos e
/// deixa pedir o reembolso integral em até 7 dias. Hoje abre por toque longo no título de "Minha conta" (o acesso público vem depois).
class PlanPage extends StatefulWidget {
  final AppState app;
  const PlanPage({super.key, required this.app});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  final PayService _svc = PayService();
  PayReply? _plan;
  List<PayItem> _items = const [];
  int _refundDays = 7;
  PayReply? _pix; // Pix aberto para pagar agora
  PayReply? _last;
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
    final p = await _svc.plan(_code, _secret);
    final h = p.ok && p.enabled ? await _svc.hist(_code, _secret) : const PayReply();
    if (!mounted) return;
    if (p.ok) widget.app.setProUntil(p.pro ? p.until : 0);
    setState(() {
      _plan = p;
      _items = h.items;
      _refundDays = h.refundDays;
    });
  }

  Future<void> _pay(String period) async {
    setState(() {
      _busy = true;
      _msg = '';
      _pix = null;
      _last = null;
    });
    final r = await _svc.payNew(_code, _secret, period);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok && r.id.isNotEmpty) {
        _pix = r;
        _tries = 0;
      } else {
        _msg = r.off ? tr('O pagamento ainda não está disponível.') : (r.offline ? tr('Sem conexão. Tente de novo.') : tr('Não consegui gerar o Pix. Tente de novo em instantes.'));
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
    if (r.ok && r.status == 'approved') {
      _poll?.cancel();
      widget.app.setProUntil(r.pro ? r.until : 0);
      setState(() {
        _last = r;
        _pix = null;
      });
      await _load();
      return;
    }
    if (_tries > 150) {
      _poll?.cancel(); // ~12 minutos
      setState(() {
        _pix = null;
        _msg = tr('O Pix venceu. Gere outro para pagar.');
      });
    }
  }

  void _cancelPix() {
    _poll?.cancel();
    setState(() => _pix = null);
  }

  Future<void> _refund(PayItem it) async {
    final ok = await showDsConfirm(
      context,
      title: tr('Pedir reembolso?'),
      body: tr('O Pix de {0} volta inteiro para você e o Pro deste pagamento é retirado da sua conta.', [_money(it.amount)]),
      confirmLabel: tr('Pedir reembolso'),
      icon: Icons.undo_rounded,
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await _svc.refund(_code, _secret, it.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = r.ok
          ? tr('Reembolso pedido. O Pix volta para a sua conta em instantes.')
          : (r.error == 'too_late' ? tr('O prazo de {0} dias já passou.', [_refundDays]) : tr('Não consegui reembolsar agora. Tente de novo ou fale com o suporte.'));
    });
    if (r.ok) {
      setState(() => _last = null); // o aviso verde de "Pro liberado" já não vale depois do reembolso
      widget.app.setProUntil(r.pro ? r.until : 0);
      await _load();
    }
  }

  static String _money(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Widget _statusCard() {
    final p = _plan;
    if (p == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (!p.ok) return Text(p.offline ? tr('Sem conexão com o servidor.') : tr('Não consegui consultar o plano agora.'));
    if (p.pro) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _ProBadge(),
          const SizedBox(width: Ds.s12),
          Expanded(child: Text(tr('Você está no Pro'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: Ds.s12),
        Text(tr('Ativo até {0}', [_when(p.until)]), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(p.daysLeft == 1 ? tr('Falta 1 dia.') : tr('Faltam {0} dias.', [p.daysLeft]), style: TextStyle(color: p.daysLeft <= 5 ? AppColors.sharp : AppColors.textDim, fontSize: Ds.fontSupport)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Plano grátis'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(tr('Até {0} alunos. O Pro tira o limite de alunos.', [p.free]), style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport, height: 1.4)),
    ]);
  }

  Widget _planOption({required String id, required String title, required String price, required String note, bool best = false}) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (best)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.accent)),
              child: Text(tr('2 meses grátis'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accent)),
            ),
        ]),
        const SizedBox(height: 4),
        Text(price, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        Text(note, style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport)),
        const SizedBox(height: Ds.s12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _pay(id),
            icon: const Icon(Icons.pix_rounded, size: 20),
            label: Text(tr('Pagar com Pix')),
          ),
        ),
      ]),
    );
  }

  Widget _pixCard() {
    final p = _pix!;
    Uint8List? img;
    try {
      img = base64Decode(p.qrBase64);
    } catch (_) {}
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Pague {0} pelo app do seu banco', [_money(p.amount)]), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: Ds.s12),
        if (img != null) Center(child: Container(color: Colors.white, padding: const EdgeInsets.all(10), child: Image.memory(img, width: 210, height: 210, filterQuality: FilterQuality.none))),
        const SizedBox(height: Ds.s12),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: p.qr));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Pix copiado.'))));
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(tr('Copiar Pix (copia e cola)')),
        ),
        const SizedBox(height: Ds.s12),
        Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(child: Text(tr('Aguardando o pagamento. O Pro libera sozinho.'), style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport))),
        ]),
        const SizedBox(height: Ds.s8),
        TextButton(onPressed: _cancelPix, child: Text(tr('Cancelar'))),
      ]),
    );
  }

  Widget _history() {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: Ds.s4, bottom: Ds.s8, top: Ds.s8), child: Text(tr('Pagamentos'), style: Ds.section())),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.outline),
            Padding(
              padding: const EdgeInsets.all(Ds.s16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_items[i].name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('${_money(_items[i].amount)} · ${_items[i].paid > 0 ? _when(_items[i].paid) : ''}', style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport)),
                  ]),
                ),
                if (_items[i].status == 'refunded')
                  Text(tr('Reembolsado'), style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w700))
                else if (_items[i].refundable)
                  OutlinedButton(onPressed: _busy ? null : () => _refund(_items[i]), child: Text(tr('Pedir reembolso')))
                else
                  Text(tr('Pago'), style: TextStyle(color: AppColors.inTune, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(left: Ds.s4, top: Ds.s8),
        child: Text(tr('Reembolso integral em até {0} dias depois do pagamento.', [_refundDays]), style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = _plan;
    final can = p != null && p.ok && p.enabled;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Plano'))),
      body: DsPageSafe(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            AppCard(child: _statusCard()),
            if (_last != null && _last!.ok && _last!.status == 'approved')
              Padding(
                padding: const EdgeInsets.only(top: Ds.gap),
                child: AppCard(
                  child: Row(children: [
                    Icon(Icons.check_circle_rounded, color: AppColors.inTune, size: 28),
                    const SizedBox(width: Ds.s12),
                    Expanded(child: Text(tr('Pagamento aprovado! O Pro foi liberado.'), style: const TextStyle(fontWeight: FontWeight.w800))),
                  ]),
                ),
              ),
            const SizedBox(height: Ds.gap),
            if (p != null && p.ok && !can)
              Text(tr('O pagamento do plano Pro ainda não está disponível.'), style: TextStyle(color: AppColors.textDim))
            else if (can) ...[
              if (_pix != null)
                _pixCard()
              else ...[
                Padding(padding: const EdgeInsets.only(left: Ds.s4, bottom: Ds.s8), child: Text(p.pro ? tr('Renovar') : tr('Assinar o Pro'), style: Ds.section())),
                _planOption(id: 'm', title: tr('Mensal'), price: 'R\$ 14,90', note: tr('30 dias de Pro. Sem renovação automática.')),
                const SizedBox(height: Ds.gap),
                _planOption(id: 'y', title: tr('Anual'), price: 'R\$ 149,00', note: tr('365 dias de Pro (R\$ 12,42 por mês).'), best: true),
                if (p.test) ...[
                  const SizedBox(height: Ds.gap),
                  OutlinedButton(onPressed: _busy ? null : () => _pay('t'), child: const Text('Teste: R\$ 1,00 por 1 dia')),
                ],
              ],
              if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Ds.gap), child: Text(_msg, style: TextStyle(color: AppColors.sharp, height: 1.4))),
              _history(),
            ],
          ],
        ),
      ),
    );
  }
}

/// O selo "Pro": verde, com a borda do app; aparece na tela Plano e na barra de cima enquanto o Pro está ativo.
class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
        child: Text('PRO', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1, color: AppColors.onAccent)),
      );
}

/// O selo "Pro" para a barra de cima: aparece só enquanto o Pro está ativo (a data vem do último contato com o servidor).
class ProPill extends StatelessWidget {
  final AppState app;
  final VoidCallback onTap;
  const ProPill({super.key, required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (app.proUntil <= DateTime.now().millisecondsSinceEpoch) return const SizedBox.shrink();
          return Tooltip(
            message: tr('Plano Pro ativo'),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                child: Text('PRO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1, color: AppColors.onAccent)),
              ),
            ),
          );
        },
      );
}
