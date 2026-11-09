import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'note_widgets.dart';
import 'theme.dart';

String _hz(double v, {int d = 1}) => v.toStringAsFixed(d).replaceAll('.', ',');

String _signed(double v) {
  final r = (v * 10).round() / 10;
  if (r == 0) return '0,0';
  return '${r > 0 ? '+' : '−'}${_hz(r.abs())}';
}

/// Explicação didática do sistema de afinação escolhido, com a tabela de alvos da tônica
/// (em Hz, contra a afinação igual) e botões para OUVIR cada nota. Aparece no Afinador
/// (modo Cromático) e nas Configurações.
class TuningSystemGuide extends StatefulWidget {
  final AppState app;
  const TuningSystemGuide({super.key, required this.app});

  @override
  State<TuningSystemGuide> createState() => _TuningSystemGuideState();
}

class _TuningSystemGuideState extends State<TuningSystemGuide> {
  bool _all = false;
  int? _playing; // passo (0..11) que está soando

  AppState get app => widget.app;

  @override
  void dispose() {
    if (_playing != null) app.tone.stop();
    super.dispose();
  }

  Future<void> _toggle(SystemRow r) async {
    if (_playing == r.step) {
      await app.tone.stop();
      if (mounted) setState(() => _playing = null);
      return;
    }
    setState(() => _playing = r.step);
    if (app.tone.running) {
      app.tone.setFrequency(r.target);
    } else {
      await app.tone.play(r.target);
    }
  }

  static const _titles = {
    TuningSystem.equal: 'Afinação igual',
    TuningSystem.pythagorean: 'Afinação pitagórica',
    TuningSystem.just: 'Afinação justa',
  };

  static const _summary = {
    TuningSystem.equal:
        'As 12 notas ficam à mesma distância umas das outras. É a afinação do piano, do violão e de '
            'qualquer instrumento de trastes: todos os tons soam iguais, mas nenhum intervalo é 100% puro.',
    TuningSystem.pythagorean:
        'As notas são construídas empilhando quintas puras (proporção 3:2) a partir da tônica. '
            'Os violinistas costumam tocar assim as melodias: a terça maior sobe e a sensível (7ª maior) '
            'chega mais perto da tônica, o que soa mais brilhante e expressivo.',
    TuningSystem.just:
        'Cada nota é medida contra a tônica por proporções simples entre as frequências: quinta 3:2, '
            'terça maior 5:4, quarta 4:3. Quando duas notas têm essa proporção, as ondas se encaixam e o som '
            'fica "parado", sem o tremor chamado batimento. É por isso que acordes soam tão limpos.',
  };

  static const _change = {
    TuningSystem.equal:
        'Nenhuma nota é "puxada": o alvo de cada nota é o do piano. A tônica não faz diferença neste sistema.',
    TuningSystem.pythagorean:
        'A mesma nota tem outro alvo: a terça maior (e a sensível) ficam mais altas que no piano e a quinta é pura. '
            'A coluna Diferença da tabela mostra quantos Hz cada nota sobe ou desce.',
    TuningSystem.just:
        'A mesma nota tem outro alvo: a terça maior fica mais baixa que no piano e a quinta um pouco mais alta. '
            'A coluna Diferença mostra o quanto o alvo se afasta da afinação igual (negativo = mais baixo). '
            'Por isso uma nota certa no Justo pode aparecer "baixa" se você olhar pelo Igual: não é erro do app.',
  };

  static const _steps = {
    TuningSystem.equal: [
      'Use ao tocar junto com piano, teclado ou violão: eles não mudam de nota.',
      'Instrumentos de trastes (violão, guitarra, ukulele) devem ficar sempre no Igual.',
      'Na dúvida, escolha este.',
    ],
    TuningSystem.pythagorean: [
      'Escolha a tônica: a nota que dá nome ao tom da peça (em Sol maior, Sol).',
      'Toque a escala ou a melodia. O app mostra o alvo pitagórico de cada nota.',
      'Confira as terças e as sensíveis: no Pitagórico elas precisam estar um pouco mais altas que no piano.',
      'Mudou de tom? Troque a tônica.',
    ],
    TuningSystem.just: [
      'Escolha a tônica: a nota que dá nome ao tom da peça ou do acorde (em Sol maior, Sol).',
      'Toque na linha "Tônica" da tabela para ouvi-la como referência (ou toque-a no instrumento).',
      'Toque a terça ou a quinta e afine contra a tônica. A cor verde no app significa que o intervalo está puro.',
      'Em acorde ou dueto: deixe a tônica soando e ajuste a terça e a quinta até o tremor (batimento) sumir.',
      'Mudou de tom ou de acorde? Troque a tônica.',
    ],
  };

  static const _caution = {
    TuningSystem.just:
        'Use o Justo para acordes e música em conjunto sem piano. Ao tocar junto com piano ou violão, volte ao Igual: '
            'eles não podem mudar de nota.',
    TuningSystem.pythagorean:
        'O Pitagórico é para tocar melodias sozinho ou com outros instrumentos de arco. Para acordes, prefira o Justo.',
  };

  @override
  Widget build(BuildContext context) {
    final sys = app.system;
    final cfg = app.cfg;
    final rows = systemRows(cfg.copyWith(transpose: 0));
    final shown = _all ? rows : [for (final r in rows) if (kMajorScaleSteps.contains(r.step)) r];
    final tonicName = rows.first.name;
    final shift = a4ShiftHz(cfg);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // A chave muda com o sistema: ao escolher Pitagórico ou Justo o guia abre sozinho.
        key: ValueKey(sys),
        initiallyExpanded: sys != TuningSystem.equal,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: Icon(Icons.school_outlined, color: AppColors.accent),
        title: Text('Entender: ${_titles[sys]}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('O que é, o que muda e como usar', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        children: [
          _block('O que é', _summary[sys]!),
          _block('O que muda nas notas', _change[sys]!),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Como usar na prática', style: _head),
          ),
          for (var i = 0; i < _steps[sys]!.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.22), shape: BoxShape.circle),
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_steps[sys]![i], style: const TextStyle(fontSize: 13, height: 1.3))),
              ]),
            ),
          if (_caution[sys] != null) _note(_caution[sys]!),
          if (sys != TuningSystem.equal) ...[
            const SizedBox(height: 12),
            Text('Alvo de cada nota (tônica: $tonicName)', style: _head),
            const SizedBox(height: 2),
            Text(
              'Toque numa linha para ouvir a nota. "Diferença" é o alvo menos a afinação igual, em Hz.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 6),
            _tableHeader(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a),
                  child: c,
                ),
              ),
              layoutBuilder: (cur, prev) => Stack(
                alignment: Alignment.topCenter,
                children: [...prev, ?cur],
              ),
              child: Column(
                key: ValueKey('$sys|${app.tonicPc}|${app.refA}|${app.anchor.name}|$_all|${cfg.preferFlats}|${cfg.autoSpelling}'),
                children: [for (final r in shown) _row(r, sys)],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.centerLeft),
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? 'Mostrar só as notas da escala maior' : 'Mostrar as 12 notas'),
              ),
            ),
            if (app.anchor == Anchor.a4)
              _note(
                shift.abs() < 0.005
                    ? 'Lá fixo ligado: o Lá continua em ${_hz(app.refA)} Hz.'
                    : 'Lá fixo ligado: o Lá continua em ${_hz(app.refA)} Hz e a tônica se ajusta em volta dele '
                        '(por isso a tônica aparece ${_signed(rows.first.diffHz)} Hz diferente do Igual). '
                        'Desligue para deixar a tônica na afinação igual.',
              )
            else
              _note('Lá fixo desligado: a tônica fica na afinação igual e o Lá passa a ${_hz(targetFreq(69, cfg))} Hz.'),
          ],
        ],
      ),
    );
  }

  TextStyle get _head => const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5);

  Widget _block(String title, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _head),
            const SizedBox(height: 2),
            Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
        ),
      );

  Widget _note(String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 17, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.3))),
        ]),
      );

  Widget _tableHeader() {
    final s = TextStyle(color: AppColors.textDim, fontSize: 11.5, fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Expanded(flex: 5, child: Text('Nota', style: s)),
        Expanded(flex: 3, child: Text('Alvo (Hz)', style: s, textAlign: TextAlign.right)),
        Expanded(flex: 3, child: Text('Igual (Hz)', style: s, textAlign: TextAlign.right)),
        Expanded(flex: 3, child: Text('Diferença', style: s, textAlign: TextAlign.right)),
      ]),
    );
  }

  Widget _row(SystemRow r, TuningSystem sys) {
    final playing = _playing == r.step;
    final Color dc = !r.differs ? AppColors.textDim : (r.diffHz < 0 ? AppColors.flat : AppColors.sharp);
    final num = TextStyle(fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      button: true,
      label: '${r.name}, ${r.role}, alvo ${_hz(r.target)} hertz, diferença ${_signed(r.diffHz)} hertz. Toque para ouvir.',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _toggle(r),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: playing ? AppColors.accent.withValues(alpha: 0.2) : (r.step == 0 ? AppColors.surface2 : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: playing ? AppColors.accent : Colors.transparent),
          ),
          child: Row(children: [
            Expanded(
              flex: 5,
              child: Row(children: [
                Icon(playing ? Icons.volume_up : Icons.volume_mute, size: 15, color: playing ? AppColors.accent : AppColors.textDim),
                const SizedBox(width: 6),
                SizedBox(
                  width: 34,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: NoteLabel(name: r.name, size: 14, color: AppColors.text),
                  ),
                ),
                Flexible(
                  child: Text(
                    '${r.role}${sys == TuningSystem.just && kJustRatioText[r.step] != null ? ' ${kJustRatioText[r.step]}' : ''}',
                    maxLines: 2,
                    style: TextStyle(color: AppColors.textDim, fontSize: 11),
                  ),
                ),
              ]),
            ),
            Expanded(flex: 3, child: Text(_hz(r.target, d: 2), style: num, textAlign: TextAlign.right)),
            Expanded(
                flex: 3,
                child: Text(_hz(r.equal, d: 2), style: num.copyWith(color: AppColors.textDim), textAlign: TextAlign.right)),
            Expanded(
              flex: 3,
              child: Text(r.differs ? _signed(r.diffHz) : '—',
                  style: num.copyWith(color: dc, fontWeight: FontWeight.w800), textAlign: TextAlign.right),
            ),
          ]),
        ),
      ),
    );
  }
}
