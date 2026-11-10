import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'app_logo.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../platform/web_install.dart' show webIsStandalone;
import 'error_ui.dart' show CriticalErrorPage, ProblemsPage;
import 'feedback_sheet.dart';
import 'install_banner.dart';
import 'profile_page.dart';
import 'qr_scan_page.dart';
import 'ref_a_dialog.dart';
import 'share_sheet.dart';
import 'theme.dart';
import 'tuning_guide.dart';
import 'widgets.dart';

const String kAppName = 'Notemusic';
const String kAppVersion = '0.1 (protótipo)';

/// E-mail de contato mostrado na política de privacidade. Defina a variável `CONTACT_EMAIL`
/// na Vercel (e faça um novo deploy); vazio, o app orienta a usar o botão Avaliar o app.
const String kContactEmail = String.fromEnvironment('CONTACT_EMAIL');

/// Configurações do app, organizadas por assunto, com a área de permissões.
class SettingsPage extends StatelessWidget {
  final AppState app;
  const SettingsPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([app, app.feedback]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
            children: [
              _header(),
              _section('Aparência', [
                _appearance(),
                const SizedBox(height: 6),
                _switch('Manter a tela acesa', 'Evita apagar enquanto você ouve, usa o metrônomo ou o timer.', app.keepAwake, app.setKeepAwake),
              ]),
              _section('Afinação', [_tuning(context)]),
              _section('Microfone', [MicSettingsContent(app: app)]),
              _section('Metrônomo', [_metronome()]),
              _section('Grade', [_grid()]),
              _section('Estudo', [_study(context)]),
              _section('Permissões e privacidade', [_permissions(context)]),
              _section('Minha conta', [_profileHub(context)]),
              _section('Sobre', [_about(context)]),
              _section('Diagnóstico', [_diagnostics(context)]),
              _section('Problemas?', [_resetAll(context)]),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
        child: Row(
          children: [
            const AppLogo(size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(kAppName,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  Text('Afine. Estude. Evolua.',
                      style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                  Text('Versão $kAppVersion',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _diagnostics(BuildContext context) => Column(children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Problemas recentes'),
          subtitle: Text(app.errorLog.items.isEmpty ? 'Nenhum problema registrado' : '${app.errorLog.items.length} registrado(s)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProblemsPage(app: app))),
        ),
        if (kDevDemo)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.science_outlined),
            title: const Text('Simular erro (teste)'),
            onTap: () => Future<void>.error(StateError('erro de teste com K7QM-4TXK e ana@exemplo.com')),
          ),
        if (kDevDemo)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.science_outlined),
            title: const Text('Ver tela de erro crítico (teste)'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (c) => CriticalErrorPage(
                error: AppError(code: 'APP-99', severity: ErrorSeverity.critical, where: 'Início do app', detail: 'StateError: teste', atMs: DateTime.now().millisecondsSinceEpoch),
                onRetry: () => Navigator.pop(c),
              ),
            )),
          ),
      ]);

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: Text(title.toUpperCase(),
                  style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700)),
            ),
            AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
          ],
        ),
      );

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
  Widget _appearance() => SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Auto')),
          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Claro')),
          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Escuro')),
        ],
        selected: {app.themeMode},
        onSelectionChanged: (s) => app.setThemeMode(s.first),
      );

  /// Cabeçalho de subgrupo dentro de um cartão.
  Widget _group(IconData icon, String title, {Widget? help}) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Row(children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          ),
          ?help,
        ]),
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

  Widget _tuning(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- 1. Básico ----
        _group(Icons.tune, 'Básico',
            help: const HelpButton(title: 'Lá de referência', sections: Help.refA)),
        _label('Lá de referência', 'A maioria usa 440 Hz. Orquestras costumam usar 442 ou 443.'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final hz in const [415.0, 432.0, 440.0, 442.0, 443.0])
            ChoiceChip(
              label: Text('${hz.round()} Hz'),
              selected: app.refA == hz,
              onSelected: (_) => app.setTuning(refA: hz),
            ),
          refAOtherChip(context, app, const [415.0, 432.0, 440.0, 442.0, 443.0]),
        ]),
        _label('Instrumento padrão'),
        PickerField<String>(
          label: 'Instrumento',
          value: app.instrumentId,
          options: instrumentOptions(app.cfg),
          onChanged: (v) => app.setTuning(instrumentId: v),
        ),

        // ---- 2. Sistema de afinação ----
        const Divider(height: 28),
        _group(Icons.straighten, 'Sistema de afinação',
            help: const HelpButton(
                title: 'Qual sistema de afinação?',
                sections: Help.system,
                footer: Help.systemFooter)),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Define como cada nota é medida no modo Cromático. As cordas soltas usam a afinação do próprio instrumento.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
        ),
        _choice('Igual', 'Piano, violão e instrumentos de trastes: as 12 notas à mesma distância.',
            app.system == TuningSystem.equal, () => app.setTuning(system: TuningSystem.equal)),
        _choice('Pitagórico', 'Melodias e escalas em instrumentos de arco: terças e sensível mais altas, quintas puras.',
            app.system == TuningSystem.pythagorean, () => app.setTuning(system: TuningSystem.pythagorean)),
        _choice('Justo', 'Acordes e conjunto: terças e quintas puras, sem tremor. A terça fica mais baixa que no piano.',
            app.system == TuningSystem.just, () => app.setTuning(system: TuningSystem.just)),
        SystemAdvice(app: app),
        TuningSystemGuide(app: app),

        // ---- 3. Som do diapasão ----
        const Divider(height: 28),
        _group(Icons.graphic_eq, 'Som de referência'),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('O som que o app toca quando você toca numa corda ou no Lá.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
        ),
        _choice('Diapasão (puro)', 'Som limpo, como um diapasão de verdade. Melhor para afinar de ouvido.',
            app.toneTimbre == ToneTimbre.fork, () => app.setToneTimbre(ToneTimbre.fork)),
        _choice('Flauta (mais cheio)', 'Soa mais forte em alto-falantes pequenos de celular.',
            app.toneTimbre == ToneTimbre.soft, () => app.setToneTimbre(ToneTimbre.soft)),
        _label('Volume do diapasão: ${(app.toneVolume * 100).round()}%',
            'Notas graves (como o Sol3) ganham reforço automático para aparecerem no alto-falante do celular.'),
        Slider(
          min: 0.2,
          max: 1.0,
          value: app.toneVolume.clamp(0.2, 1.0),
          onChanged: app.setToneVolume,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: app.testLowTone,
            icon: const Icon(Icons.volume_up),
            label: const Text('Testar com o Sol3'),
          ),
        ),

        // ---- 4. Nomes das notas ----
        const Divider(height: 28),
        _group(Icons.abc, 'Nomes das notas'),
        _label('Instrumento transpositor',
            'Mostra os nomes como estão escritos na partitura do seu instrumento.'),
        PickerField<int>(
          label: 'Transpositor',
          value: app.transpose,
          options: const [
            OptionItem(0, 'Som real (dó)', subtitle: 'Violino, viola, cello, piano, flauta, oboé'),
            OptionItem(2, 'Si♭', subtitle: 'Clarinete, trompete, sax soprano e tenor'),
            OptionItem(3, 'Lá', subtitle: 'Clarinete em Lá'),
            OptionItem(5, 'Sol', subtitle: 'Flauta alto'),
            OptionItem(7, 'Fá', subtitle: 'Trompa, corne inglês'),
            OptionItem(9, 'Mi♭', subtitle: 'Sax alto e barítono'),
            OptionItem(12, 'Oitava acima', subtitle: 'Violão, guitarra e contrabaixo (escritos uma oitava acima)'),
          ],
          onChanged: (v) => app.setTuning(transpose: v),
        ),
        const SizedBox(height: 4),
        _label('Sustenidos e bemóis', 'Como as notas pretas aparecem (Lá♭ ou Sol♯).'),
        SpellingPicker(app: app),
      ],
    );
  }

  Widget _metronome() {
    final m = app.metro;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switch('Piscar na batida', 'Acende os círculos dos tempos junto com o som.',
            app.flashEnabled, (v) => app.setTuning(flashEnabled: v)),
        _switch('Vibrar na batida', 'Vibração leve a cada tempo (só em celulares).',
            app.hapticEnabled, (v) => app.setTuning(hapticEnabled: v)),
        _label('Som do metrônomo'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in const {
            ClickSound.click: 'Clique',
            ClickSound.wood: 'Madeira',
            ClickSound.clave: 'Clave',
            ClickSound.drum: 'Tambor',
            ClickSound.beep: 'Bipe',
          }.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: m.sound == e.key,
              onSelected: (_) => app.setMetro(m.copyWith(sound: e.key)),
            ),
        ]),
        _label('Volume'),
        Slider(
          min: 0.1,
          max: 1.0,
          value: m.volume.clamp(0.1, 1.0),
          onChanged: (v) => app.setMetro(m.copyWith(volume: v)),
        ),
        _label('Ajuste de sincronia: ${app.outputLatencyMs.round()} ms',
            'Se a luz ou a vibração parecerem adiantadas em relação ao som (comum com fone Bluetooth), aumente.'),
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
        _switch('Mostrar frequência na grade', 'Mostra os Hz da nota que você toca, ao lado da dica.', app.showFreq, app.setShowFreq),
        _label('Memória da nota', 'Quanto tempo o que você tocou antes ainda pesa na cor.'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in const {
            HistoryMode.short: '1 s',
            HistoryMode.medium: '3 s',
            HistoryMode.long: '30 s',
            HistoryMode.unlimited: 'Sessão toda',
          }.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: app.history == e.key,
              onSelected: (_) => app.setTuning(history: e.key),
            ),
        ]),
        _label('Cor fica na tela por'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in {10.0: '10 s', 30.0: '30 s', 120.0: '2 min', 0.0: 'Até zerar'}.entries)
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
        _label('Meta diária: ${app.dailyGoalMinutes.round()} min'),
        Slider(
          min: 5,
          max: 120,
          divisions: 23,
          value: app.dailyGoalMinutes.clamp(5.0, 120.0),
          onChanged: (v) => app.setTuning(dailyGoalMinutes: v),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await _confirm(context, 'Apagar histórico?',
                'Remove o tempo de estudo e as escalas salvas deste aparelho. Não dá para desfazer.',
                'Apagar');
            if (ok) {
              await app.clearHistory();
              app.say('Histórico apagado');
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Apagar histórico de estudo'),
        ),
      ],
    );
  }

  /// Uma única entrada para perfil e professor. Tudo o que é de identidade e de
  /// ensino mora na tela de destino (abas), sem repetir aqui.
  Widget _profileHub(BuildContext context) {
    final p = app.profile;
    final pending = p.recoveryShownAt == null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.accent.withValues(alpha: 0.18),
        child: Icon(app.teacherMode ? Icons.school_outlined : Icons.badge_outlined, color: AppColors.accent),
      ),
      title: Text(p.name ?? 'Meu perfil', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        'Código ${p.shareCode} · Modo professor ${app.teacherMode ? 'ligado' : 'desligado'}'
        '${pending ? '\nGuarde a chave de recuperação' : ''}',
        style: TextStyle(color: pending ? AppColors.sharp : AppColors.textDim, fontSize: 12.5),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProfilePage(app: app))),
    );
  }

  /// Zera tudo: ajustes, histórico, IA e (na web) o cache da página.
  Widget _resetAll(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Se a página não atualizar ou algo estiver estranho, apague tudo e comece do zero. '
          'Remove ajustes, histórico de estudo, análises de IA e o cache do site neste aparelho.',
          style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.sharp,
            foregroundColor: readableOn(AppColors.sharp),
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () async {
            final ok = await _confirm(
                context,
                'Apagar tudo e recomeçar?',
                'Isso apaga neste aparelho todas as configurações, o histórico de estudo, '
                    'as escalas, as análises de IA e o cache da página. O app volta ao primeiro uso. '
                    'Não dá para desfazer.',
                'Apagar tudo');
            if (ok) await app.resetEverything();
          },
          icon: const Icon(Icons.restart_alt),
          label: const Text('Apagar tudo e recomeçar', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _permissions(BuildContext context) {
    final g = app.micGranted;
    final v = app.vibrationAvailable;
    final (micIcon, micColor, micStatus) = switch (g) {
      true => (Icons.check_circle, AppColors.inTune, 'Liberado'),
      false => (Icons.cancel, AppColors.sharp, 'Sem permissão'),
      null => (Icons.help_outline, AppColors.textDim, 'Ainda não verificado'),
    };
    final (vibIcon, vibColor, vibStatus) = switch (v) {
      true => (Icons.check_circle, AppColors.inTune, 'Disponível neste aparelho'),
      false => (Icons.remove_circle_outline, AppColors.textDim, 'Indisponível aqui. ${app.vibrationWhy()} O app funciona sem'),
      null => (Icons.help_outline, AppColors.textDim, 'Ainda não verificado'),
    };
    final cam = app.cameraGranted;
    final (camIcon, camColor, camStatus) = switch (cam) {
      true => (Icons.check_circle, AppColors.inTune, 'Liberada'),
      false => (Icons.cancel, AppColors.sharp, 'Sem permissão'),
      null => (Icons.help_outline, AppColors.textDim, 'Ainda não pedida'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: app.requestAllPermissions,
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Permitir tudo o que o app usa',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 4),
        Text('Pede o microfone e testa a vibração de uma vez, para você não ser interrompido depois. '
            'A câmera é pedida só quando você lê um QR (use o botão dela abaixo para liberar antes).',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
        const Divider(height: 24),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(micIcon, color: micColor, size: 30),
          title: const Text('Microfone', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$micStatus · necessário para o afinador, a grade e as escalas'),
          trailing: FilledButton.tonal(
            onPressed: app.checkMicPermission,
            child: Text(g == true ? 'Verificar' : 'Permitir'),
          ),
        ),
        if (g == false)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Para liberar depois de negar: no celular, abra Configurações › Apps › $kAppName › Permissões › Microfone. '
              'No navegador, use o cadeado ao lado do endereço.',
              style: TextStyle(color: AppColors.sharp, fontSize: 12.5),
            ),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(camIcon, color: camColor, size: 30),
          title: const Text('Câmera', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$camStatus · só para ler o QR de alunos e professores (você também pode digitar o código)'),
          trailing: FilledButton.tonal(
            onPressed: () => scanShareCode(context, title: 'Testar a câmera', onCamera: app.setCameraStatus),
            child: Text(cam == true ? 'Testar' : 'Permitir'),
          ),
        ),
        if (cam == false)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Para liberar depois de negar: no celular, abra Configurações › Apps › $kAppName › Permissões › Câmera. '
              'No navegador, use o cadeado ao lado do endereço.',
              style: TextStyle(color: AppColors.sharp, fontSize: 12.5),
            ),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(vibIcon, color: vibColor, size: 30),
          title: const Text('Vibração', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$vibStatus · batida do metrônomo, fim do Pomodoro e notas das escalas'),
          trailing: FilledButton.tonal(
            onPressed: app.testVibration,
            child: const Text('Testar'),
          ),
        ),
        _switch('Vibrar na batida e nas escalas', 'Liga ou desliga a vibração do metrônomo e dos exercícios.',
            app.hapticEnabled, (x) => app.setTuning(hapticEnabled: x)),
        const Divider(height: 20),
        _info(Icons.screen_lock_portrait, 'Tela sempre acesa',
            'Usada enquanto você estuda para a tela não apagar. Não exige permissão.'),
        _info(Icons.cloud_outlined, 'Internet (só para a análise por IA)',
            'O app funciona sem internet. Ela só é usada se você pedir a análise por IA, e mesmo assim só vão números de afinação, nunca áudio.'),
        _info(Icons.shield_outlined, 'Seu áudio fica com você',
            'O som é analisado no próprio aparelho e descartado na hora. Nada é gravado nem enviado.'),
        const Divider(height: 20),
        _switch(
            'Estatísticas anônimas de uso',
            'Ajuda a melhorar o app: avisa, sem identificar você, que o app foi aberto, em que tipo de aparelho e '
                'quais abas são mais usadas. Não envia nome, áudio, localização nem o que você toca.',
            app.statsEnabled,
            app.setStatsEnabled),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => _showPrivacy(context),
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text('Ler a política de privacidade'),
        ),
      ],
    );
  }

  Widget _info(IconData i, String title, String sub) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(i, color: AppColors.textDim),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12.5)),
      );

  Widget _about(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$kAppName reúne afinador, metrônomo, grade de entonação e registro de estudo, '
          'pensado para instrumentistas de corda, mas útil para qualquer instrumento.',
          style: TextStyle(color: AppColors.textDim),
        ),
        const SizedBox(height: 12),
        // Instalar no celular (só no navegador e enquanto não está instalado).
        if (kIsWeb && !webIsStandalone()) ...[
          FilledButton.icon(
            onPressed: () => runInstall(context, app),
            icon: const Icon(Icons.install_mobile),
            label: const Text('Instalar no celular', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Text('Coloca o Notemusic na tela inicial: abre em tela cheia, como um app, e funciona sem internet.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ),
        ],
        FilledButton.icon(
          onPressed: () async {
            final ok = await _confirm(context, 'Atualizar o app?',
                'O app busca a versão mais nova e reinicia. Seus ajustes e seu histórico são mantidos.',
                'Atualizar');
            if (ok) await app.updateApp();
          },
          icon: const Icon(Icons.system_update),
          label: Text(app.updateAvailable ? 'Atualizar agora (versão nova!)' : 'Atualizar o app',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text(
            'Instalou no celular e parece desatualizado? Toque aqui para buscar a versão mais nova. Versão atual: $kAppVersion.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => showRatingSheet(context, app),
              icon: Icon(app.feedback.rating > 0 ? Icons.star_rounded : Icons.star_outline_rounded),
              label: Text(app.feedback.rating > 0 ? 'Sua nota: ${app.feedback.rating}/5' : 'Avaliar o app'),
            ),
            if (!app.feedback.surveyAnswered)
              FilledButton.tonalIcon(
                onPressed: () => showSurveySheet(context, app),
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Pesquisa rápida'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => showShareSheet(context),
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Compartilhar o app (link e QR code)'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showLicensePage(
                  context: context,
                  applicationName: kAppName,
                  applicationVersion: kAppVersion,
                  applicationIcon: const Padding(
                      padding: EdgeInsets.all(8), child: AppLogo(size: 56))),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Licenças'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await _confirm(context, 'Restaurar padrões?',
                    'Todas as configurações voltam ao início. O histórico de estudo é mantido.',
                    'Restaurar');
                if (ok) await app.resetSettings();
              },
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('Restaurar'),
            ),
          ),
        ]),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
            const Text('Política de privacidade',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Atualizada em novembro de 2026',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            const SizedBox(height: 14),
            for (final p in [
              ('O que o app usa', 'O microfone, somente enquanto você toca em "Ouvir", para identificar a altura das notas.'),
              ('O que acontece com o som', 'É analisado em tempo real no próprio aparelho e descartado em seguida. Nenhum áudio é gravado, guardado ou enviado.'),
              ('O que fica salvo', 'Suas configurações, o tempo de estudo e as escalas que você salvar. Tudo fica apenas neste aparelho.'),
              ('Análise por IA (opcional)', 'Só se você tocar em "Analisar com IA" no Treinador, e depois de autorizar. O app envia um resumo só com números (desvios por nota e taxas de acerto) a um serviço de inteligência artificial, por um servidor intermediário que guarda as chaves e limita o uso. Nunca vão áudio, nome ou localização.'),
              ('Câmera (opcional)', 'Só quando você toca em "Ler QR", para ler o QR de um aluno ou de um professor. A imagem é lida no aparelho e nunca é gravada nem enviada. Você também pode digitar o código.'),
              ('Escrever falando (opcional)', 'Só quando você toca no microfone de um campo de texto. Quem transforma a voz em texto é o serviço de voz do seu aparelho ou do navegador (por exemplo, o do Google ou o da Apple), que pode usar a internet. O Notemusic não grava nem guarda o áudio.'),
              ('Nota e pesquisa rápida (opcional)', 'Só se você tocar em Enviar. Vão a sua resposta, a versão do app e um código do aparelho que o servidor embaralha, sem nome, e-mail nem áudio. Você pode ignorar o convite.'),
              ('Seu perfil e o vínculo online', 'O app cria no seu aparelho um código de identificação, sem cadastro. Seu histórico de exercícios fica só neste aparelho. Se você ligar o Vínculo online (ou vincular alguém lendo um QR), o servidor passa a guardar o seu código, um apelido opcional, um resumo criptográfico do seu segredo e a lista de vínculos com as datas. Se você é professor e encerra uma aula, as tarefas e as observações PASSADAS NAQUELA AULA são enviadas ao servidor para o aluno vinculado buscar (até 60 aulas por aluno). Nunca vão áudio nem o histórico de exercícios. Você pode encerrar um vínculo a qualquer momento: as aulas daquele professor deixam de valer para o aluno.'),
              ('Estatísticas anônimas de uso', 'Para saber quantas pessoas usam o app e em que tipo de aparelho, o app avisa o servidor quando é aberto e, enquanto está aberto, a cada poucos minutos. Vão apenas: um código aleatório do aparelho (que não é o seu código de perfil e não identifica você), o tipo de aparelho e de navegador, a versão do app e quais abas você abriu. Não vão nome, e-mail, localização, áudio, o que você toca e o endereço de IP não é guardado (só um resumo temporário, por até 1 hora, para barrar abusos). Você pode desligar em Configurações › Permissões e privacidade › Estatísticas anônimas de uso.'),
              ('Conta e dados pessoais', 'Não há login, cadastro nem anúncios. O app não pede nome, e-mail nem localização, e não rastreia o que você faz fora dele.'),
              (
                'Contato e seus direitos',
                kContactEmail.isEmpty
                    ? 'Para dúvidas ou pedidos sobre os seus dados (acesso, correção ou exclusão), escreva em Configurações › Sobre › Avaliar o app (campo de comentário). Os dados do perfil ficam só no seu aparelho; os do vínculo online (códigos, apelidos e aulas) saem do servidor quando você encerra o vínculo ou usa Apagar tudo.'
                    : 'Para dúvidas ou pedidos sobre os seus dados (acesso, correção ou exclusão), escreva para $kContactEmail. Os dados do perfil ficam só no seu aparelho; os do vínculo online (códigos, apelidos e aulas) saem do servidor quando você encerra o vínculo ou usa Apagar tudo.',
              ),
              ('Como apagar', 'Em Configurações › Estudo › Apagar histórico, ou desinstalando o app.'),
              ('Menores de idade', 'Como não coleta dados pessoais, o app é adequado para todas as idades.'),
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
