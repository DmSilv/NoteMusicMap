import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'app_logo.dart';
import 'design_system.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../platform/web_install.dart' show webIsStandalone;
import 'error_ui.dart' show CriticalErrorPage, ProblemsPage;
import 'feedback_sheet.dart';
import 'install_banner.dart';
import 'qr_scan_page.dart';
import 'ref_a_dialog.dart';
import 'share_sheet.dart';
import 'theme.dart';
import 'tuning_pick.dart';
import 'widgets.dart';

final String kAppName = 'Notemusic';
final String kAppVersion = tr('0.1 (protótipo)');

/// E-mail de contato mostrado na política de privacidade. Defina a variável `CONTACT_EMAIL`
/// na Vercel (e faça um novo deploy); vazio, o app orienta a usar o botão Avaliar o app.
const String kContactEmail = String.fromEnvironment('CONTACT_EMAIL');

/// Configurações do app, organizadas por assunto, com a área de permissões.
class SettingsPage extends StatelessWidget {
  final AppState app;
  const SettingsPage({super.key, required this.app});

  /// Abre o modal de um assunto: mexe, toca em "Concluir" e volta à lista.
  void _open(BuildContext context, String title, List<Widget> Function(BuildContext) children) =>
      showDsSheet(context, title: title, listenable: Listenable.merge([app, app.feedback]), children: children);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ajustes'))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([app, app.feedback]),
          builder: (context, _) {
            final themeName = switch (app.themeMode) { ThemeMode.light => tr('Claro'), ThemeMode.dark => tr('Escuro'), _ => tr('Automático') };
            final soundName = {ClickSound.click: tr('Clique'), ClickSound.wood: tr('Madeira'), ClickSound.clave: tr('Clave'), ClickSound.drum: tr('Tambor'), ClickSound.beep: tr('Bipe')}[app.metro.sound] ?? tr('Clique');
            final micName = switch (app.micGranted) { true => tr('Liberado'), false => tr('Sem permissão'), null => tr('Ainda não verificado') };
            return ListView(
              padding: Ds.screen,
              children: [
                _header(),
                const DsGap(Ds.gap),
                _navCard([
                  DsNavRow(Icons.palette_rounded, tr('Aparência e tela'), '$themeName${app.keepAwake ? tr(' · tela acesa') : ''}', () => _open(context, tr('Aparência e tela'), (c) => _appearanceList())),
                  DsNavRow(Icons.straighten, tr('Afinação'), tuningSummary(app), () => _open(context, tr('Afinação'), (c) => [_tuningBasic(c)])),
                  DsNavRow(Icons.graphic_eq_rounded, tr('Som de referência'), app.toneTimbre == ToneTimbre.fork ? tr('Diapasão') : tr('Flauta'), () => _open(context, tr('Som de referência'), (c) => [_tone()])),
                  DsNavRow(Icons.abc_rounded, tr('Nomes das notas'), app.transpose == 0 ? tr('Som real') : tr('Transpositor'), () => _open(context, tr('Nomes das notas'), (c) => [_names()])),
                  DsNavRow(Icons.mic_none_rounded, tr('Microfone'), micName, () => _open(context, tr('Microfone'), (c) => [MicSettingsContent(app: app)])),
                  DsNavRow(Icons.timer_outlined, tr('Metrônomo'), soundName, () => _open(context, tr('Metrônomo'), (c) => [_metronome()])),
                  DsNavRow(Icons.grid_view_rounded, tr('Grade'), tr('Memória {0}', [{HistoryMode.short: tr('1 s'), HistoryMode.medium: tr('3 s'), HistoryMode.long: tr('30 s'), HistoryMode.unlimited: tr('da sessão')}[app.history]]), () => _open(context, tr('Grade'), (c) => [_grid()])),
                  DsNavRow(Icons.auto_stories_rounded, tr('Estudo'), tr('Meta {0} min', [app.dailyGoalMinutes.round()]), () => _open(context, tr('Estudo'), (c) => [_study(c)])),
                ]),
                const DsGap(Ds.gap),
                _navCard([
                  DsNavRow(Icons.verified_user_outlined, tr('Permissões e privacidade'), micName, () => _open(context, tr('Permissões e privacidade'), (c) => [_permissions(c)])),
                  DsNavRow(Icons.info_outline_rounded, tr('Sobre o app'), app.updateAvailable ? tr('Versão nova disponível') : tr('Versão {0}', [kAppVersion]), () => _open(context, tr('Sobre o app'), (c) => [_about(c)]),
                      alert: app.updateAvailable),
                  DsNavRow(Icons.bug_report_outlined, tr('Problemas e diagnóstico'), app.errorLog.items.isEmpty ? tr('Nenhum problema') : tr('{0} registrado(s)', [app.errorLog.items.length]), () => _open(context, tr('Problemas e diagnóstico'), (c) => [_diagnostics(c)])),
                  DsNavRow(Icons.restart_alt_rounded, tr('Restaurar e apagar'), tr('Voltar ao início'), () => _open(context, tr('Restaurar e apagar'), (c) => [_resetAll(c)])),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Cartão com linhas de navegação separadas por filete.
  Widget _navCard(List<Widget> rows) => AppCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Ds.radiusCard),
          child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 64, color: AppColors.outline.withValues(alpha: 0.5)),
            rows[i],
          ],
        ]),
        ),
      );

  Widget _header() => Row(
        children: [
          const AppLogo(size: 48),
          const SizedBox(width: Ds.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kAppName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(tr('Afine. Estude. Evolua.'), style: Ds.support()),
              ],
            ),
          ),
        ],
      );

  List<Widget> _appearanceList() => [
        DsSettingRow(label: tr('Tema'), child: SizedBox(width: double.infinity, child: _appearance())),
        DsSettingRow(label: tr('Idioma / Language'), child: SizedBox(width: double.infinity, child: _language())),
        _switch(tr('Manter a tela acesa'), tr('Enquanto você ouve ou estuda.'), app.keepAwake, app.setKeepAwake),
      ];

  Widget _diagnostics(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(tr('Problemas recentes')),
          subtitle: Text(app.errorLog.items.isEmpty ? tr('Nenhum problema registrado') : tr('{0} registrado(s)', [app.errorLog.items.length])),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProblemsPage(app: app))),
        ),
        const Divider(height: Ds.sectionGap),
        Row(children: [
          Expanded(child: Text(tr('Enviar relatório de erro'), style: TextStyle(fontWeight: FontWeight.w700))),
          HelpButton(title: tr('Relatório de erro'), sections: [(tr('O que vai'), tr('Só dados técnicos: nada de nome, código de perfil, áudio ou o que você toca.'))]),
        ]),
        const SizedBox(height: Ds.s8),
        Wrap(spacing: 8, children: [
          for (final m in ReportMode.values)
            ChoiceChip(
              label: Text(reportModeLabel(m)),
              selected: app.reportMode == m,
              onSelected: (_) => app.setReportMode(m),
            ),
        ]),
        if (kDevDemo)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.science_outlined),
            title: Text(tr('Simular erro (teste)')),
            onTap: () => Future<void>.error(StateError('erro de teste com K7QM-4TXK e ana@exemplo.com')),
          ),
        if (kDevDemo)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.science_outlined),
            title: Text(tr('Ver tela de erro crítico (teste)')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (c) => CriticalErrorPage(
                error: AppError(code: 'APP-99', severity: ErrorSeverity.critical, where: tr('Início do app'), detail: 'StateError: teste', atMs: DateTime.now().millisecondsSinceEpoch),
                onRetry: () => Navigator.pop(c),
              ),
            )),
          ),
      ]);

  Widget _label(String t, [String? sub, Widget? help]) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700))),
              ?help,
            ]),
            if (sub != null)
              Text(sub, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ],
        ),
      );

  Widget _switch(String title, String sub, bool v, ValueChanged<bool> on) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12.5)),
        value: v,
        onChanged: on,
      );

  // ------------------------------------------------------------------
  /// Idioma: 'auto' segue o aparelho. Os nomes dos idiomas ficam sempre na própria língua.
  Widget _language() => SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: 'auto', icon: const Icon(Icons.language), label: Text(tr('Auto'))),
          ButtonSegment(value: 'pt', label: Text('Português')),
          ButtonSegment(value: 'en', label: Text('English')),
        ],
        selected: {app.langPref},
        onSelectionChanged: (s) => app.setLangPref(s.first),
      );

  Widget _appearance() => SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text(tr('Auto'))),
          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text(tr('Claro'))),
          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text(tr('Escuro'))),
        ],
        selected: {app.themeMode},
        onSelectionChanged: (s) => app.setThemeMode(s.first),
      );

  /// Opção em cartão: título, explicação curta e marca de selecionada.
  Widget _choice(String title, String sub, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected ? AppColors.accent.withValues(alpha: 0.12) : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected ? AppColors.accent : Colors.transparent, width: 1.5),
              ),
              child: Row(children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 22, color: selected ? AppColors.accent : AppColors.textDim),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.25)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _tuningBasic(BuildContext context) {
    const refs = [415.0, 432.0, 440.0, 442.0, 443.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(tr('Lá de referência'), null, HelpButton(title: tr('Lá de referência'), sections: Help.refA)),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final hz in refs)
            ChoiceChip(label: Text('${hz.round()} Hz'), selected: app.refA == hz, onSelected: (_) => app.setTuning(refA: hz)),
          refAOtherChip(context, app, refs),
        ]),
        _label(tr('Instrumento padrão')),
        PickerField<String>(
          label: tr('Instrumento'),
          value: app.instrumentId,
          options: instrumentOptions(app.cfg),
          onChanged: (v) => app.setTuning(instrumentId: v),
        ),
        _label(tr('Sistema de afinação'), null, HelpButton(title: tr('Qual sistema de afinação?'), sections: Help.system, footer: Help.systemFooter)),
        _choice(tr('Igual'), tr('Piano, violão e trastes.'), app.system == TuningSystem.equal, () => app.setTuning(system: TuningSystem.equal)),
        _choice(tr('Pitagórico'), tr('Arco e melodias.'), app.system == TuningSystem.pythagorean, () => app.setTuning(system: TuningSystem.pythagorean)),
        _choice(tr('Justo'), tr('Acordes e conjunto.'), app.system == TuningSystem.just, () => app.setTuning(system: TuningSystem.just)),
      ],
    );
  }

  Widget _tone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _choice(tr('Diapasão'), tr('Som puro, para afinar de ouvido.'), app.toneTimbre == ToneTimbre.fork, () => app.setToneTimbre(ToneTimbre.fork)),
        _choice(tr('Flauta'), tr('Mais cheio no celular.'), app.toneTimbre == ToneTimbre.soft, () => app.setToneTimbre(ToneTimbre.soft)),
        _label(tr('Volume: {0}%', [(app.toneVolume * 100).round()])),
        Slider(min: 0.2, max: 1.0, value: app.toneVolume.clamp(0.2, 1.0), onChanged: app.setToneVolume),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: app.testLowTone, icon: const Icon(Icons.volume_up, size: 20), label: Text(tr('Testar com o Sol3'))),
        ),
      ],
    );
  }

  Widget _names() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(tr('Instrumento transpositor')),
        PickerField<int>(
          label: tr('Transpositor'),
          value: app.transpose,
          options: [
            OptionItem(0, tr('Som real (dó)'), subtitle: tr('Violino, viola, cello, piano, flauta, oboé')),
            OptionItem(2, tr('Si♭'), subtitle: tr('Clarinete, trompete, sax soprano e tenor')),
            OptionItem(3, tr('Lá'), subtitle: tr('Clarinete em Lá')),
            OptionItem(5, tr('Sol'), subtitle: tr('Flauta alto')),
            OptionItem(7, tr('Fá'), subtitle: tr('Trompa, corne inglês')),
            OptionItem(9, tr('Mi♭'), subtitle: tr('Sax alto e barítono')),
            OptionItem(12, tr('Oitava acima'), subtitle: tr('Violão, guitarra e contrabaixo')),
          ],
          onChanged: (v) => app.setTuning(transpose: v),
        ),
        _label(tr('Sustenidos e bemóis')),
        SpellingPicker(app: app),
      ],
    );
  }

  Widget _metronome() {
    final m = app.metro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switch(tr('Piscar a tela na batida'), tr('Um clarão a cada tempo.'),
            app.flashEnabled, (v) => app.setTuning(flashEnabled: v)),
        _switch(tr('Vibrar na batida'), tr('Só no celular Android.'),
            app.hapticEnabled, (v) => app.setTuning(hapticEnabled: v)),
        _label(tr('Som do metrônomo')),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in {
            ClickSound.click: tr('Clique'),
            ClickSound.wood: tr('Madeira'),
            ClickSound.clave: tr('Clave'),
            ClickSound.drum: tr('Tambor'),
            ClickSound.beep: tr('Bipe'),
          }.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: m.sound == e.key,
              onSelected: (_) => app.setMetro(m.copyWith(sound: e.key)),
            ),
        ]),
        _label(tr('Volume')),
        Slider(
          min: 0.1,
          max: 1.0,
          value: m.volume.clamp(0.1, 1.0),
          onChanged: (v) => app.setMetro(m.copyWith(volume: v)),
        ),
        _label(tr('Sincronia: {0} ms', [app.outputLatencyMs.round()]), tr('Aumente se a luz vier antes do som (fone Bluetooth).')),
        Slider(
          min: 0,
          max: 250,
          divisions: 50,
          value: app.outputLatencyMs.clamp(0.0, 250.0),
          onChanged: app.setLatency,
        ),
      ],
    );
  }

  Widget _grid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switch(tr('Mostrar frequência'), tr('Os Hz da nota que você toca.'), app.showFreq, app.setShowFreq),
        _label(tr('Memória da nota')),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in {
            HistoryMode.short: tr('1 s'),
            HistoryMode.medium: tr('3 s'),
            HistoryMode.long: tr('30 s'),
            HistoryMode.unlimited: tr('Sessão toda'),
          }.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: app.history == e.key,
              onSelected: (_) => app.setTuning(history: e.key),
            ),
        ]),
        _label(tr('Cor fica na tela por')),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in {10.0: tr('10 s'), 30.0: tr('30 s'), 120.0: tr('2 min'), 0.0: tr('Até zerar')}.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: app.holdSeconds == e.key,
              onSelected: (_) => app.setTuning(holdSeconds: e.key),
            ),
        ]),
      ],
    );
  }

  Widget _study(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(tr('Meta diária: {0} min', [app.dailyGoalMinutes.round()])),
        Slider(
          min: 5,
          max: 120,
          divisions: 23,
          value: app.dailyGoalMinutes.clamp(5.0, 120.0),
          onChanged: (v) => app.setTuning(dailyGoalMinutes: v),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await _confirm(context, tr('Apagar histórico?'),
                tr('Remove o tempo de estudo e as escalas salvas deste aparelho. Não dá para desfazer.'),
                tr('Apagar'));
            if (ok) {
              await app.clearHistory();
              app.say(tr('Histórico apagado'));
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Apagar histórico')),
        ),
      ],
    );
  }

  /// Restaurar e apagar (do mais leve ao mais pesado).
  Widget _resetAll(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await _confirm(context, tr('Restaurar padrões?'), tr('Os ajustes voltam ao início. O histórico de estudo é mantido.'), tr('Restaurar'));
            if (ok) await app.resetSettings();
          },
          icon: const Icon(Icons.settings_backup_restore),
          label: Text(tr('Restaurar ajustes')),
        ),
        const DsGap(Ds.s12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.sharp, foregroundColor: readableOn(AppColors.sharp)),
          onPressed: () async {
            final ok = await _confirm(
                context,
                tr('Apagar tudo e recomeçar?'),
                tr('Apaga neste aparelho os ajustes, o histórico, as análises de IA e o cache. O app volta ao primeiro uso. Não dá para desfazer.'),
                tr('Apagar tudo'));
            if (ok) await app.resetEverything();
          },
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(tr('Apagar tudo e recomeçar'), style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const DsGap(Ds.s8),
        Text(tr('Use se algo estiver estranho.'), style: Ds.support()),
      ],
    );
  }

  Widget _permissions(BuildContext context) {
    final g = app.micGranted;
    final v = app.vibrationAvailable;
    final cam = app.cameraGranted;
    (IconData, Color, String) st(bool? ok, String yes, String no, String unknown) => switch (ok) {
          true => (Icons.check_circle, AppColors.inTune, yes),
          false => (Icons.cancel, AppColors.sharp, no),
          null => (Icons.help_outline, AppColors.textDim, unknown),
        };
    final (micIcon, micColor, micStatus) = st(g, tr('Liberado'), tr('Sem permissão'), tr('Não verificado'));
    final (camIcon, camColor, camStatus) = st(cam, tr('Liberada'), tr('Sem permissão'), tr('Ainda não pedida'));
    final (vibIcon, vibColor, vibStatus) = v == false
        ? (Icons.remove_circle_outline, AppColors.textDim, tr('Indisponível aqui'))
        : st(v, tr('Disponível'), '', tr('Não verificado'));
    Widget row(IconData i, Color c, String title, String status, String action, VoidCallback on) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(i, color: c, size: 28),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(status),
          trailing: FilledButton.tonal(onPressed: on, child: Text(action)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DsPrimaryButton(onPressed: app.requestAllPermissions, icon: Icons.verified_user_outlined, label: tr('Permitir tudo')),
        const DsGap(Ds.s12),
        row(micIcon, micColor, tr('Microfone'), micStatus, g == true ? tr('Verificar') : tr('Permitir'), app.checkMicPermission),
        row(camIcon, camColor, tr('Câmera'), camStatus, cam == true ? tr('Testar') : tr('Permitir'),
            () => scanShareCode(context, title: tr('Testar a câmera'), onCamera: app.setCameraStatus)),
        row(vibIcon, vibColor, tr('Vibração'), vibStatus, tr('Testar'), app.testVibration),
        if (g == false || cam == false)
          Padding(
            padding: const EdgeInsets.only(top: Ds.s8),
            child: Text(tr('Negou antes? Libere no cadeado do navegador ou em Configurações › Apps › {0}.', [kAppName]), style: TextStyle(color: AppColors.sharp, fontSize: Ds.fontLabel)),
          ),
        const Divider(height: Ds.sectionGap),
        _switch(tr('Vibrar na batida e nas escalas'), tr('Metrônomo e exercícios.'), app.hapticEnabled, (x) => app.setTuning(hapticEnabled: x)),
        _switch(tr('Batida leve ao dar certo'), tr('Ao pegar horário, marcar aula e enviar tarefa.'), app.successHaptic, app.setSuccessHaptic),
        Row(children: [
          Expanded(
            child: _switch(tr('Estatísticas anônimas'), tr('Sem identificar você.'), app.statsEnabled, app.setStatsEnabled),
          ),
          HelpButton(title: tr('Estatísticas anônimas'), sections: [
            (tr('O que vai'), tr('Que o app foi aberto, o tipo de aparelho (sistema, tela, idioma, região aproximada) e as abas mais usadas, só como categorias.')),
            (tr('O que não vai'), tr('Nome, áudio, localização nem o que você toca.')),
          ]),
        ]),
        _info(Icons.shield_outlined, tr('Seu áudio fica com você'), tr('Analisado no aparelho e descartado na hora.')),
        TextButton.icon(
          onPressed: () => _showPrivacy(context),
          icon: const Icon(Icons.privacy_tip_outlined),
          label: Text(tr('Política de privacidade')),
        ),
      ],
    );
  }

  Widget _info(IconData i, String title, String sub) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(i, color: AppColors.textDim),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(fontSize: Ds.fontLabel)),
      );

  Widget _about(BuildContext context) {
    Widget tile(IconData i, String title, VoidCallback on, {String? sub}) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(i),
          title: Text(title),
          subtitle: sub == null ? null : Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: on,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DsPrimaryButton(
          onPressed: () async {
            final ok = await _confirm(context, tr('Atualizar o app?'), tr('Busca a versão mais nova e reinicia. Seus ajustes e histórico ficam.'), tr('Atualizar'));
            if (ok) await app.updateApp();
          },
          icon: Icons.system_update,
          label: app.updateAvailable ? tr('Atualizar (versão nova!)') : tr('Atualizar o app'),
        ),
        const DsGap(Ds.s8),
        Text(tr('Versão {0}', [kAppVersion]), style: Ds.support()),
        const DsGap(Ds.s8),
        if (kIsWeb && !webIsStandalone()) tile(Icons.install_mobile, tr('Instalar no celular'), () => runInstall(context, app), sub: tr('Abre em tela cheia e funciona sem internet.')),
        tile(Icons.school_outlined, tr('Rever tutoriais'), () {
          app.resetTutorials();
          app.say(tr('Pronto: o "Comece por aqui" volta ao Meu espaço e os tutoriais podem ser vistos de novo.'));
        }, sub: tr('Mostra de novo os guias de como usar.')),
        tile(app.feedback.rating > 0 ? Icons.star_rounded : Icons.star_outline_rounded, app.feedback.rating > 0 ? tr('Sua nota: {0}/5', [app.feedback.rating]) : tr('Avaliar o app'), () => showRatingSheet(context, app)),
        if (!app.feedback.surveyAnswered) tile(Icons.poll_outlined, tr('Pesquisa rápida'), () => showSurveySheet(context, app)),
        tile(Icons.qr_code_2, tr('Compartilhar o app'), () => showShareSheet(context), sub: tr('Link e QR code.')),
        tile(
            Icons.description_outlined,
            tr('Licenças'),
            () => showLicensePage(
                context: context,
                applicationName: kAppName,
                applicationVersion: kAppVersion,
                applicationIcon: const Padding(padding: EdgeInsets.all(8), child: AppLogo(size: 56)))),
      ],
    );
  }

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return r == true;
  }

  void _showPrivacy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Text(tr('Política de privacidade'),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('Atualizada em novembro de 2026'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            const SizedBox(height: 14),
            for (final p in [
              (tr('O que o app usa'), tr('O microfone, somente enquanto você toca em "Ouvir", para identificar a altura das notas.')),
              (tr('O que acontece com o som'), tr('É analisado em tempo real no próprio aparelho e descartado em seguida. Nenhum áudio é gravado, guardado ou enviado.')),
              (tr('O que fica salvo'), tr('Suas configurações, o tempo de estudo e as escalas que você salvar. Tudo fica apenas neste aparelho.')),
              (tr('Análise por IA (opcional)'), tr('Só se você tocar em "Analisar com IA" no Treinador, e depois de autorizar. O app envia um resumo só com números (desvios por nota e taxas de acerto) a um serviço de inteligência artificial, por um servidor intermediário que guarda as chaves e limita o uso. Nunca vão áudio, nome ou localização.')),
              (tr('Câmera (opcional)'), tr('Só quando você toca em "Ler QR", para ler o QR de um aluno ou de um professor. A imagem é lida no aparelho e nunca é gravada nem enviada. Você também pode digitar o código.')),
              (tr('Escrever falando (opcional)'), tr('Só quando você toca no microfone de um campo de texto. Quem transforma a voz em texto é o serviço de voz do seu aparelho ou do navegador (por exemplo, o do Google ou o da Apple), que pode usar a internet. O Notemusic não grava nem guarda o áudio.')),
              (tr('Nota e pesquisa rápida (opcional)'), tr('Só se você tocar em Enviar. Vão a sua resposta, a versão do app e um código do aparelho que o servidor embaralha, sem nome, e-mail nem áudio. Você pode ignorar o convite.')),
              (tr('Seu perfil e o vínculo online'), tr('O app cria no seu aparelho um código de identificação, sem cadastro. Seu histórico de exercícios fica só neste aparelho. Se você ligar o Vínculo online (ou vincular alguém lendo um QR), o servidor passa a guardar o seu código, um apelido opcional, um resumo criptográfico do seu segredo e a lista de vínculos com as datas. Se você é professor e encerra uma aula, as tarefas e as observações PASSADAS NAQUELA AULA são enviadas ao servidor para o aluno vinculado buscar (até 60 aulas por aluno). Nunca vão áudio nem o histórico de exercícios. Você pode encerrar um vínculo a qualquer momento: as aulas daquele professor deixam de valer para o aluno. Perfis sem vínculo e sem uso há 60 dias são apagados do servidor automaticamente.')),
              (tr('Estatísticas anônimas de uso'), tr('Para saber quantas pessoas usam o app e em que tipo de aparelho, o app avisa o servidor quando é aberto e, enquanto está aberto, a cada poucos minutos. Vão apenas: um código aleatório do aparelho (que não é o seu código de perfil e não identifica você), o tipo de aparelho e de navegador, o sistema, a faixa de tamanho da tela, o idioma, se o tema é claro ou escuro, se a tela é de toque, se o microfone e as notificações estão liberados, o fuso horário, a memória e o número de núcleos do aparelho, a qualidade da conexão, a densidade da tela, a região aproximada (país e estado, que o servidor deduz da conexão, sem guardar o endereço de IP), a versão do app e quais abas você abriu (tudo em categorias curtas). Não vão nome, e-mail, localização, áudio, o que você toca e o endereço de IP não é guardado (só um resumo temporário, por até 1 hora, para barrar abusos). Você pode desligar em Configurações › Permissões e privacidade › Estatísticas anônimas de uso.')),
              (tr('Acervo do professor (só testes)'), tr('Se o seu professor liberar, ele pode cadastrar títulos e links de materiais (Google Drive, IMSLP, YouTube…). O servidor guarda só o título, o autor, o link e para quem é; nenhum arquivo. Ao tocar em Abrir, você sai do Notemusic para o site do link. Quem publica é responsável pelo conteúdo; dá para denunciar um item.')),
              (tr('Presença no vínculo online'), tr('Com o vínculo online ligado e o app aberto, o servidor guarda o seu código, o horário do último sinal (no máximo a cada 10 minutos), o tempo de uso estimado dos últimos 14 dias (só minutos, nunca o que você toca), o tempo de estudo (minutos por dia, nunca o que você toca) e a ficha do aparelho: modelo, tipo de aparelho e navegador, sistema, tela, idioma, região aproximada (país, estado e cidade) e versão do app. O administrador usa isso para ver quem está online e dar suporte. Quem desliga as estatísticas anônimas não envia a ficha do aparelho. Para parar, desligue o vínculo online em Minha conta.')),
              (tr('Conta e dados pessoais'), tr('Não há login, cadastro nem anúncios. O app não pede nome, e-mail nem localização, e não rastreia o que você faz fora dele.')),
              (
                tr('Contato e seus direitos'),
                kContactEmail.isEmpty
                    ? tr('Para dúvidas ou pedidos sobre os seus dados (acesso, correção ou exclusão), escreva em Configurações › Sobre › Avaliar o app (campo de comentário). Os dados do perfil ficam só no seu aparelho; os do vínculo online (códigos, apelidos e aulas) saem do servidor quando você encerra o vínculo ou usa Apagar tudo.')
                    : tr('Para dúvidas ou pedidos sobre os seus dados (acesso, correção ou exclusão), escreva para {0}. Os dados do perfil ficam só no seu aparelho; os do vínculo online (códigos, apelidos e aulas) saem do servidor quando você encerra o vínculo ou usa Apagar tudo.', [kContactEmail]),
              ),
              (tr('Como apagar'), tr('Em Configurações › Estudo › Apagar histórico, ou desinstalando o app.')),
              (tr('Menores de idade'), tr('Como não coleta dados pessoais, o app é adequado para todas as idades.')),
            ]) ...[
              Text(p.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(p.$2, style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
