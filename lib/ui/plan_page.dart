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

/// Tela "Plano": mostra se o professor está no Pro e até quando, explica o que o Pro libera e como funciona, deixa assinar por Pix
/// (mensal ou anual), mostra o prazo do Pix, comemora quando o pagamento entra, lista os pagamentos e deixa pedir o reembolso
/// integral em até 7 dias. Quem já assinou vê só o plano que paga (os outros ficam atrás de "Ver outros planos").
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
  String _pixPeriod = '';
  DateTime _started = DateTime.now();
  DateTime _now = DateTime.now();

  PayReply? _paid; // resposta do pagamento aprovado (mostra a tela de parabéns)
  double _paidAmount = 0;
  String _paidPeriod = '';

  bool _busy = false;
  bool _showOthers = false;
  String _msg = '';
  Timer? _poll;
  Timer? _tick;
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
    _tick?.cancel();
    _svc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await _svc.plan(_code, _secret);
    final h = p.ok ? await _svc.hist(_code, _secret) : const PayReply();
    if (!mounted) return;
    if (p.ok) widget.app.setProUntil(p.pro ? p.until : 0);
    setState(() {
      _plan = p;
      _items = h.items;
      _refundDays = h.refundDays;
    });
  }

  /// O plano que a pessoa paga hoje ('m', 'y') ou null (grátis, ou Pro de cortesia).
  String? get _currentPlan {
    if (_plan == null || !_plan!.pro) return null;
    for (final it in _items) {
      if (it.status != 'refunded' && it.paid > 0 && (it.plan == 'm' || it.plan == 'y')) return it.plan;
    }
    return null;
  }

  Future<void> _pay(String period) async {
    setState(() {
      _busy = true;
      _msg = '';
      _pix = null;
    });
    final r = await _svc.payNew(_code, _secret, period);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok && r.id.isNotEmpty) {
        _pix = r;
        _pixPeriod = period;
        _started = DateTime.now();
        _now = _started;
        _tries = 0;
      } else if (r.httpStatus == 403) {
        _msg = tr('O pagamento ainda não está disponível para o seu perfil.');
      } else {
        _msg = r.off ? tr('O pagamento ainda não está disponível.') : (r.offline ? tr('Sem conexão. Tente de novo.') : tr('Não consegui gerar o Pix. Tente de novo em instantes.'));
      }
    });
    if (_pix != null) {
      _poll?.cancel();
      _tick?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check());
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  Duration get _left => _started.add(Duration(seconds: _pix?.ttl ?? 1800)).difference(_now);

  Future<void> _check() async {
    final p = _pix;
    if (p == null) return;
    _tries++;
    final r = await _svc.payCheck(_code, _secret, p.id);
    if (!mounted) return;
    if (r.ok && r.status == 'approved') {
      _poll?.cancel();
      _tick?.cancel();
      widget.app.setProUntil(r.pro ? r.until : 0);
      setState(() {
        _paid = r;
        _paidAmount = p.amount;
        _paidPeriod = _pixPeriod;
        _pix = null;
      });
      await _load();
      return;
    }
    if (_left.isNegative && _tries > 6) {
      _poll?.cancel();
      _tick?.cancel(); // venceu: a tela oferece gerar outro
    }
  }

  void _cancelPix() {
    _poll?.cancel();
    _tick?.cancel();
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

  String _mmss(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  // ---------- peças ----------

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
      if (widget.app.studentLimitOn) ...[
        const SizedBox(height: Ds.s8),
        Text(tr('Você tem {0} de {1} alunos.', [widget.app.students.length, p.free]), style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ]);
  }

  Widget _planOption({required String id, required String title, required String price, required String note, bool best = false, String? button}) {
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
            label: Text(button ?? tr('Pagar com Pix')),
          ),
        ),
      ]),
    );
  }

  Widget _monthly({String? button}) => _planOption(id: 'm', title: tr('Mensal'), price: 'R\$ 14,90', note: tr('30 dias de Pro. Sem renovação automática.'), button: button);
  Widget _yearly({String? button}) => _planOption(id: 'y', title: tr('Anual'), price: 'R\$ 149,00', note: tr('365 dias de Pro (R\$ 12,42 por mês).'), best: true, button: button);

  /// Quem já assina vê só o plano que paga; o outro fica atrás de "Ver outros planos".
  List<Widget> _planChoices(PayReply p) {
    final cur = _currentPlan;
    final label = p.pro ? tr('Renovar') : tr('Assinar o Pro');
    final widgets = <Widget>[Padding(padding: const EdgeInsets.only(left: Ds.s4, bottom: Ds.s8), child: Text(label, style: Ds.section()))];
    if (cur == null || _showOthers) {
      widgets.addAll([_monthly(), const SizedBox(height: Ds.gap), _yearly()]);
    } else {
      widgets.add(cur == 'y' ? _yearly(button: tr('Renovar com Pix')) : _monthly(button: tr('Renovar com Pix')));
      widgets.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: () => setState(() => _showOthers = true), child: Text(cur == 'y' ? tr('Ver o plano mensal') : tr('Ver o plano anual'))),
      ));
    }
    if (p.test) {
      widgets.addAll([const SizedBox(height: Ds.gap), OutlinedButton(onPressed: _busy ? null : () => _pay('t'), child: const Text('Teste: R\$ 1,00 por 1 dia'))]);
    }
    return widgets;
  }

  Widget _pixCard() {
    final p = _pix!;
    Uint8List? img;
    try {
      img = base64Decode(p.qrBase64);
    } catch (_) {}
    final total = Duration(seconds: p.ttl);
    final left = _left;
    final expired = left.isNegative || left.inSeconds == 0;
    final waited = _now.difference(_started);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Pague {0} pelo app do seu banco', [_money(p.amount)]), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: Ds.s12),
        // Prazo do Pix: quanto falta e uma barra que esvazia.
        Row(children: [
          Icon(Icons.timer_outlined, size: 20, color: expired || left.inMinutes < 5 ? AppColors.sharp : AppColors.textDim),
          const SizedBox(width: Ds.s8),
          Expanded(
            child: Text(expired ? tr('Este Pix venceu.') : tr('Vence em {0}', [_mmss(left)]), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: expired || left.inMinutes < 5 ? AppColors.sharp : AppColors.text)),
          ),
          Text(tr('Aguardando há {0}', [_mmss(waited)]), style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport)),
        ]),
        const SizedBox(height: Ds.s8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: expired ? 0 : (left.inSeconds / total.inSeconds).clamp(0.0, 1.0),
            backgroundColor: AppColors.surface2,
            color: left.inMinutes < 5 ? AppColors.sharp : AppColors.accent,
          ),
        ),
        const SizedBox(height: Ds.s16),
        if (expired) ...[
          Text(tr('Se você já pagou, aguarde alguns segundos: o Pro libera sozinho. Se não, gere outro Pix.'), style: TextStyle(color: AppColors.textDim, height: 1.4)),
          const SizedBox(height: Ds.s12),
          FilledButton(onPressed: _busy ? null : () => _pay(_pixPeriod), child: Text(tr('Gerar outro Pix'))),
        ] else ...[
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
          Text(tr('No app do banco, escolha Pix, depois "copia e cola" ou ler o QR, e confirme. O Pro libera sozinho em poucos segundos.'), style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport, height: 1.4)),
        ],
        const SizedBox(height: Ds.s8),
        TextButton(onPressed: _cancelPix, child: Text(tr('Cancelar'))),
      ]),
    );
  }

  /// Tela de parabéns quando o Pix cai: o que foi pago, até quando vale e um botão para continuar.
  Widget _success() {
    final r = _paid!;
    final name = _paidPeriod == 'y' ? tr('Anual') : (_paidPeriod == 't' ? tr('Teste') : tr('Mensal'));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      children: [
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 60, color: AppColors.accent),
          ),
        ),
        const SizedBox(height: Ds.s24),
        Text(tr('Parabéns! O Pix foi pago.'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: Ds.s8),
        Text(tr('O seu plano Pro está ativo.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: AppColors.textDim)),
        const SizedBox(height: Ds.s24),
        AppCard(
          child: Column(children: [
            _kv(tr('Plano'), 'Pro · $name'),
            const Divider(height: 24),
            _kv(tr('Valor'), _money(_paidAmount)),
            const Divider(height: 24),
            _kv(tr('Ativo até'), _when(r.until)),
          ]),
        ),
        const SizedBox(height: Ds.s16),
        _benefits(compact: true),
        const SizedBox(height: Ds.s24),
        DsPrimaryButton(onPressed: () => setState(() => _paid = null), icon: Icons.arrow_forward_rounded, label: tr('Continuar')),
      ],
    );
  }

  Widget _kv(String k, String v) => Row(children: [
        Expanded(child: Text(k, style: TextStyle(color: AppColors.textDim))),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ]);

  Widget _benefitRow(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: Ds.s12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.accent, size: 22),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(body, style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport, height: 1.4)),
            ]),
          ),
        ]),
      );

  /// O que o Pro libera, em frases curtas (só o que existe de verdade).
  Widget _benefits({bool compact = false}) {
    final free = _plan?.free ?? 3;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('O que o Pro libera'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: Ds.s12),
        _benefitRow(Icons.groups_rounded, tr('Alunos sem limite'), tr('No plano grátis o limite é de {0} alunos. Com o Pro você cadastra quantos quiser.', [free])),
        _benefitRow(Icons.favorite_border_rounded, tr('Aluno sempre grátis'), tr('Seus alunos nunca pagam para usar o app.')),
        if (!compact) ...[
          _benefitRow(Icons.pix_rounded, tr('Pague só quando quiser'), tr('Pix avulso: sem cartão e sem renovação automática.')),
          _benefitRow(Icons.undo_rounded, tr('Reembolso fácil'), tr('Integral em até {0} dias depois do pagamento.', [_refundDays])),
        ],
      ]),
    );
  }

  Widget _howItWorks() {
    Widget step(String n, String t) => Padding(
          padding: const EdgeInsets.only(bottom: Ds.s8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.textDim)),
              child: Text(n, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(width: Ds.s12),
            Expanded(child: Text(t, style: const TextStyle(height: 1.4))),
          ]),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Como funciona'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: Ds.s12),
        step('1', tr('Escolha o plano mensal ou o anual.')),
        step('2', tr('Pague o Pix no app do seu banco. Ele vale por 30 minutos.')),
        step('3', tr('O Pro libera sozinho em poucos segundos.')),
        const SizedBox(height: Ds.s4),
        Text(tr('Quando o Pro vence, o app volta ao plano grátis. Seus alunos e dados continuam com você.'), style: TextStyle(color: AppColors.textDim, fontSize: Ds.fontSupport, height: 1.4)),
      ]),
    );
  }

  Widget _history() {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: Ds.s4, bottom: Ds.s8, top: Ds.s16), child: Text(tr('Pagamentos'), style: Ds.section())),
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
        child: _paid != null
            ? _success()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  AppCard(child: _statusCard()),
                  const SizedBox(height: Ds.gap),
                  if (_pix != null)
                    _pixCard()
                  else if (can) ...[
                    ..._planChoices(p),
                    if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Ds.gap), child: Text(_msg, style: TextStyle(color: AppColors.sharp, height: 1.4))),
                  ] else if (p != null && p.ok && !p.pro)
                    Text(tr('O pagamento do plano Pro ainda não está disponível.'), style: TextStyle(color: AppColors.textDim)),
                  if (_pix == null) ...[
                    const SizedBox(height: Ds.gap),
                    _benefits(),
                    const SizedBox(height: Ds.gap),
                    _howItWorks(),
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
          if (!app.proActive) return const SizedBox.shrink();
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
