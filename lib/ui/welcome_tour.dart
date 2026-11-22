import 'dart:async';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'app_logo.dart';
import 'theme.dart';

/// Para onde a pessoa quer ir depois da apresentação.
enum TourChoice { study, hasTeacher, teacher, look, hasAccount }

/// Apresentação do primeiro acesso: 4 telas curtas com telas reais do app e, no fim,
/// três portas (estudar, tenho professor, sou professor). Não pede nada: nem cadastro
/// nem permissão. Devolve a porta escolhida (ou [TourChoice.look] se a pessoa pulou).
Future<TourChoice> showWelcomeTour(BuildContext context) async {
  final r = await Navigator.of(context).push<TourChoice>(
    PageRouteBuilder<TourChoice>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => const WelcomeTour(),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
  return r ?? TourChoice.look;
}

/// Um recorte de tela real do app (assets/tour), já cortado em pontos naturais.
class _Shot {
  final String asset;
  final double aspect; // largura / altura do recorte
  const _Shot(this.asset, this.aspect);
}

// Larguras e alturas em pixels do recorte original (780 de largura).
const _tunerFlat = _Shot('assets/tour/tuner_flat.png', 780 / 1065);
const _tunerOk = _Shot('assets/tour/tuner_ok.png', 780 / 1065);
const _tools = [
  _Shot('assets/tour/tab_tuner.png', 780 / 1190),
  _Shot('assets/tour/tab_scales.png', 780 / 1250),
  _Shot('assets/tour/tab_metro.png', 780 / 1150),
  _Shot('assets/tour/tab_grid.png', 780 / 1150),
];
const _hubs = [
  _Shot('assets/tour/hub_student.png', 780 / 1215),
  _Shot('assets/tour/hub_teacher.png', 780 / 1250),
];

class WelcomeTour extends StatefulWidget {
  const WelcomeTour({super.key});

  @override
  State<WelcomeTour> createState() => _WelcomeTourState();
}

class _WelcomeTourState extends State<WelcomeTour> {
  final _pc = PageController();
  int _page = 0;

  // tela 1: a mesma corda desafinada e afinada
  bool _inTune = false;
  // tela 2: abas das ferramentas (trocam sozinhas até a pessoa tocar)
  int _tool = 0;
  bool _toolTouched = false;
  // tela 3: o lado que a pessoa quer ver
  bool _teacherSide = false;
  Timer? _t1, _t2;

  @override
  void initState() {
    super.initState();
    _t1 = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (mounted && _page == 0) setState(() => _inTune = !_inTune);
    });
    _t2 = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (mounted && _page == 1 && !_toolTouched) {
        setState(() => _tool = (_tool + 1) % 4);
      }
    });
  }

  @override
  void dispose() {
    _t1?.cancel();
    _t2?.cancel();
    _pc.dispose();
    super.dispose();
  }

  void _go(int p) => _pc.animateToPage(
    p,
    duration: const Duration(milliseconds: 320),
    curve: Curves.easeOutCubic,
  );

  void _finish(TourChoice c) => Navigator.of(context).pop(c);

  @override
  Widget build(BuildContext context) {
    final last = _page == 3;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_page > 0) {
          _go(_page - 1);
        } else {
          _finish(TourChoice.look);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  _topBar(last),
                  Expanded(
                    child: PageView(
                      controller: _pc,
                      onPageChanged: (p) => setState(() => _page = p),
                      children: [_page1(), _page2(), _page3(), _page4()],
                    ),
                  ),
                  if (!last)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onPressed: () => _go(_page + 1),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(tr('Continuar')),
                              const SizedBox(width: 10),
                              const Icon(Icons.arrow_forward_rounded, size: 22),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(bool last) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
    child: Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              const AppLogo(size: 32),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'Notemusic',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              if (!last)
                TextButton(
                  onPressed: () => _go(3),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    foregroundColor: AppColors.textDim,
                  ),
                  child: Text(
                    tr('Pular'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 6),
          child: Semantics(
            label: tr('Passo {0} de 4', [_page + 1]),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 4,
                      margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                      decoration: BoxDecoration(
                        color: i <= _page
                            ? AppColors.accent
                            : AppColors.outline,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  // ---------- peças ----------

  Widget _title(List<(String, bool)> parts, {double? size}) => LayoutBuilder(
    builder: (context, c) {
      final h = MediaQuery.sizeOf(context).height;
      final s =
          size ??
          (h < 640
              ? 24.0
              : (MediaQuery.sizeOf(context).width * 0.082).clamp(26.0, 34.0));
      return Text.rich(
        TextSpan(
          children: [
            for (final p in parts)
              TextSpan(
                text: p.$1,
                style: TextStyle(
                  color: p.$2 ? AppColors.accent : AppColors.text,
                ),
              ),
          ],
        ),
        style: TextStyle(
          fontSize: s,
          fontWeight: FontWeight.w800,
          height: 1.06,
          letterSpacing: -s * 0.03,
        ),
      );
    },
  );

  /// Celular bem baixo (ex.: 320 × 568): some o que é só apoio, para o recorte do app ficar legível.
  bool get _compact => MediaQuery.sizeOf(context).height < 640;

  Widget _sub(String t) {
    if (_compact) return const SizedBox.shrink();
    final small = MediaQuery.sizeOf(context).height < 700;
    return Padding(
      padding: EdgeInsets.only(top: small ? 6 : 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Text(
          t,
          style: TextStyle(
            color: AppColors.textDim,
            fontSize: small ? 14.5 : 16,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  /// Moldura de celular com as telas reais; a tela ativa aparece por cima das outras.
  Widget _phone(List<_Shot> shots, int index, {double maxH = 400}) {
    final aspect = shots.first.aspect;
    return LayoutBuilder(
      builder: (context, c) {
        final h = [
          c.maxHeight,
          maxH,
          c.maxWidth / aspect,
        ].reduce((a, b) => a < b ? a : b);
        return Center(
          child: SizedBox(
            height: h,
            width: h * aspect,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0F1419),
                borderRadius: BorderRadius.circular(h < 280 ? 20 : 26),
                border: Border.all(
                  color: const Color(0xFF2A3541),
                  width: h < 280 ? 4 : 5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .35),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(h < 280 ? 16 : 21),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var i = 0; i < shots.length; i++)
                      AnimatedOpacity(
                        opacity: i == index ? 1 : 0,
                        duration: const Duration(milliseconds: 350),
                        child: Image.asset(
                          shots[i].asset,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          excludeFromSemantics: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pill(String text, {Color? dot}) => Container(
    constraints: const BoxConstraints(minHeight: 36),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.outline),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot != null) ...[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _layout({required Widget art, required Widget copy}) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: art),
        const SizedBox(height: 8),
        copy,
        const SizedBox(height: 6),
      ],
    ),
  );

  // ---------- telas ----------

  Widget _page1() => _layout(
    art: Column(
      children: [
        if (!_compact)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: Text(
                tr('Será que essa nota está afinada?'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (!_compact) const SizedBox(height: 10),
        Expanded(child: _phone([_tunerFlat, _tunerOk], _inTune ? 1 : 0)),
        const SizedBox(height: 10),
        _pill(
          _inTune ? tr('Afinado') : tr('Agudo: desça a afinação'),
          dot: _inTune ? AppColors.inTune : AppColors.sharp,
        ),
      ],
    ),
    copy: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title([
          ("${tr('Tocou a nota e ficou')} ", false),
          (tr('na dúvida?'), true),
        ]),
        _sub(
          tr(
            'O Notemusic escuta e diz na hora se está afinada, baixa ou alta. Sem cadastro, sem pegadinha.',
          ),
        ),
      ],
    ),
  );

  Widget _page2() {
    final names = [tr('Afinador'), tr('Escalas'), tr('Metrônomo'), tr('Grade')];
    final caps = [
      tr('Corda a corda, com a agulha mostrando o caminho.'),
      tr('Escalas e arpejos na partitura, com exercício guiado.'),
      tr('O chefe do tempo, sem reclamar de hora extra.'),
      tr('Toque qualquer nota e veja se está afinada.'),
    ];
    return _layout(
      art: Column(
        children: [
          Expanded(child: _phone(_tools, _tool)),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            runSpacing: 5,
            children: [
              for (var i = 0; i < 4; i++)
                Semantics(
                  button: true,
                  selected: _tool == i,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _toolTouched = true;
                      _tool = i;
                    }),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _tool == i
                            ? AppColors.accent
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _tool == i
                              ? AppColors.accent
                              : AppColors.outline,
                        ),
                      ),
                      child: Text(
                        names[i],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _tool == i
                              ? AppColors.onAccent
                              : AppColors.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            caps[_tool],
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: AppColors.textDim),
          ),
        ],
      ),
      copy: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title([
            ("${tr('Uma caixa de ferramentas,')} ", false),
            (tr('zero bagunça'), true),
          ]),
          _sub(
            tr(
              'Abra o que precisa, quando precisar. O resto fica quieto esperando.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _page3() {
    Widget seg(String label, bool on, VoidCallback tap) => Expanded(
      child: GestureDetector(
        onTap: tap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: on ? AppColors.onAccent : AppColors.textDim,
            ),
          ),
        ),
      ),
    );
    return _layout(
      art: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                seg(
                  tr('Tenho professor'),
                  !_teacherSide,
                  () => setState(() => _teacherSide = false),
                ),
                seg(
                  tr('Sou professor'),
                  _teacherSide,
                  () => setState(() => _teacherSide = true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _phone(_hubs, _teacherSide ? 1 : 0)),
          const SizedBox(height: 6),
          // As telas são capturas fixas (datas e nomes de exemplo): avisa que é uma ilustração.
          Center(child: Text(tr('Exemplo ilustrativo'), style: TextStyle(fontSize: 12, color: AppColors.textDim))),
        ],
      ),
      copy: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        layoutBuilder: (cur, prev) =>
            Stack(alignment: Alignment.topLeft, children: [...prev, ?cur]),
        child: Column(
          key: ValueKey(_teacherSide),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _teacherSide
              ? [
                  _title([
                    ("${tr('Agenda e alunos,')} ", false),
                    (tr('sem planilha'), true),
                  ]),
                  _sub(
                    tr(
                      'Marque aulas, abra horários livres e abra a ficha de cada aluno com um toque.',
                    ),
                  ),
                ]
              : [
                  _title([
                    ("${tr('A aula e as tarefas')} ", false),
                    (tr('num lugar só'), true),
                  ]),
                  _sub(
                    tr(
                      'Seu professor marca a aula, você vê na hora e pega um horário livre.',
                    ),
                  ),
                ],
        ),
      ),
    );
  }

  /// Porta escolhida na última tela: só abre o card com a explicação; quem confirma é o botão "Seguir".
  TourChoice? _door;

  (String, String)? _doorInfo(TourChoice? c) => switch (c) {
        TourChoice.study => (
            tr('Afinador, escalas guiadas e metrônomo para estudar do seu jeito. Funciona sem conta e seus dados ficam neste aparelho.'),
            tr('Começar a estudar')
          ),
        TourChoice.hasTeacher => (
            tr('Seu professor mostra um QR no app dele. Você lê o QR, ou digita o código, e passa a ver as aulas, as tarefas e os horários dele.'),
            tr('Ler o QR do professor')
          ),
        TourChoice.teacher => (
            tr('Cadastre alunos, marque aulas e envie tarefas. Você informa seu nome e instrumentos, e o vínculo online liga para trocar tarefas e avisos com os alunos.'),
            tr('Criar meu perfil de professor')
          ),
        _ => null,
      };

  /// Uma porta: seletor (marcador à direita) em vez de seta, para deixar claro que escolher não sai da tela.
  Widget _pick(IconData icon, String title, String sub, TourChoice c) {
    final on = _door == c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: on,
        child: Material(
          color: on ? AppColors.accent.withValues(alpha: .16) : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _door = c),
            child: Container(
              constraints: const BoxConstraints(minHeight: 68),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: on ? AppColors.accent : AppColors.outline, width: on ? 2 : 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: AppColors.accent, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(sub, style: TextStyle(fontSize: 13, color: AppColors.textDim, height: 1.25)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      color: on ? AppColors.accent : AppColors.textDim, size: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Card que aparece embaixo das portas: explica a ideia em duas linhas e traz o botão para seguir.
  Widget _doorCard() {
    final info = _doorInfo(_door);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: info == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 2, bottom: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.accent.withValues(alpha: .6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.$1, style: const TextStyle(fontSize: 14.5, height: 1.35)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      onPressed: () => _finish(_door!),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      iconAlignment: IconAlignment.end,
                      label: Text(info.$2, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Botão secundário de largura total, com ícone e borda: dá para ver que é para tocar.
  Widget _secondary(IconData icon, String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: BorderSide(color: AppColors.outline, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
  );

  Widget _page4() => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.maxHeight - 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title([
              ("${tr('Gostou?')} ", false),
              ("${tr('Escolha')} ", true),
              (tr('por onde começar'), false),
            ]),
            _sub(tr('Nada de formulário. Seus dados ficam neste aparelho e a conta só entra em cena se você quiser ligar com um professor.')),
            const SizedBox(height: 16),
            _pick(Icons.graphic_eq_rounded, tr('Quero estudar'), tr('Afinador, escalas e metrônomo'), TourChoice.study),
            _pick(Icons.qr_code_scanner_rounded, tr('Tenho professor'), tr('Leia o QR ou digite o código dele'), TourChoice.hasTeacher),
            _pick(Icons.person_add_alt_1_rounded, tr('Sou professor'), tr('Alunos, agenda e tarefas online num só lugar'), TourChoice.teacher),
            _doorCard(),
            const SizedBox(height: 10),
            Divider(color: AppColors.outline, height: 1),
            const SizedBox(height: 12),
            _secondary(Icons.login_rounded, tr('Já tenho conta em outro aparelho'), () => _finish(TourChoice.hasAccount)),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '${tr('Sem cadastro')} · ${tr('Dados no aparelho')}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textDim),
              ),
            ),
          ],
        ),
      ),
    ),
  );

}
