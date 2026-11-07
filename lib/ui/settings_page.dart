import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'app_logo.dart';
import 'theme.dart';
import 'widgets.dart';

const String kAppName = 'Tom e Tempo';
const String kAppVersion = '0.1 (protótipo)';

/// Configurações do app, organizadas por assunto, com a área de permissões.
class SettingsPage extends StatelessWidget {
  final AppState app;
  const SettingsPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
            children: [
              _header(),
              _section('Aparência', [_appearance()]),
              _section('Afinação', [_tuning(context)]),
              _section('Microfone', [MicSettingsContent(app: app)]),
              _section('Metrônomo', [_metronome()]),
              _section('Grade', [_grid()]),
              _section('Estudo', [_study(context)]),
              _section('Permissões e privacidade', [_permissions(context)]),
              _section('Sobre', [_about(context)]),
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

  Widget _label(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _tuning(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Lá de referência', 'Orquestras costumam usar 442 ou 443 Hz.'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final hz in [438.0, 440.0, 442.0, 443.0, 445.0])
            ChoiceChip(
              label: Text('${hz.round()} Hz'),
              selected: app.refA == hz,
              onSelected: (_) => app.setTuning(refA: hz),
            ),
        ]),
        _label('Instrumento padrão'),
        PickerField<String>(
          label: 'Instrumento',
          value: app.instrumentId,
          options: instrumentOptions(app.cfg),
          onChanged: (v) => app.setTuning(instrumentId: v),
        ),
        _label('Som de referência (diapasão e cordas)',
            'Puro é o som de um diapasão de verdade. Cheio ajuda a ouvir em alto-falantes pequenos.'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in const {
            ToneTimbre.fork: 'Diapasão (puro)',
            ToneTimbre.soft: 'Flauta (mais cheio)',
          }.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: app.toneTimbre == e.key,
              onSelected: (_) => app.setToneTimbre(e.key),
            ),
        ]),
        _label('Sistema de afinação (modo cromático)'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in const {
            TuningSystem.equal: 'Igual',
            TuningSystem.pythagorean: 'Pitagórico',
            TuningSystem.just: 'Justo',
          }.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: app.system == e.key,
              onSelected: (_) => app.setTuning(system: e.key),
            ),
        ]),
        _label('Instrumento transpositor',
            'Mostra os nomes das notas como estão escritos na partitura do seu instrumento.'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in const {
            0: 'Som real (dó)',
            2: 'Si♭ (clarinete, trompete)',
            9: 'Mi♭ (sax alto)',
            7: 'Fá (trompa)',
          }.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: app.transpose == e.key,
              onSelected: (_) => app.setTuning(transpose: e.key),
            ),
        ]),
        const SizedBox(height: 4),
        _switch('Usar bemóis (♭)', 'Mostra Si♭ em vez de Lá♯, por exemplo.', app.preferFlats,
            (v) => app.setTuning(preferFlats: v)),
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
        _label('Nível de exigência', 'Largura da faixa verde (afinado).'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in const {
            ZoneLevel.beginner: 'Iniciante ±10',
            ZoneLevel.intermediate: 'Intermediário ±5',
            ZoneLevel.advanced: 'Avançado ±3',
          }.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: app.zone == e.key,
              onSelected: (_) => app.setTuning(zone: e.key),
            ),
        ]),
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

  Widget _permissions(BuildContext context) {
    final g = app.micGranted;
    final (icon, color, status) = switch (g) {
      true => (Icons.check_circle, AppColors.inTune, 'Liberado'),
      false => (Icons.cancel, AppColors.sharp, 'Sem permissão'),
      null => (Icons.help_outline, AppColors.textDim, 'Ainda não verificado'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color, size: 30),
          title: const Text('Microfone', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$status · necessário para o afinador e a grade'),
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
        const Divider(height: 20),
        _info(Icons.screen_lock_portrait, 'Tela sempre acesa',
            'Usada enquanto você estuda para a tela não apagar. Não exige permissão.'),
        _info(Icons.vibration, 'Vibração', 'Usa o motor de vibração do aparelho. Não exige permissão.'),
        _info(Icons.wifi_off, 'Sem internet e sem conta',
            'O app não envia nada para fora e não tem login nem anúncios.'),
        _info(Icons.shield_outlined, 'Seu áudio fica com você',
            'O som é analisado no próprio aparelho e descartado na hora. Nada é gravado nem enviado.'),
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
            Text('Resumo para o usuário (rascunho, a revisar antes de publicar)',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            const SizedBox(height: 14),
            for (final p in const [
              ('O que o app usa', 'O microfone, somente enquanto você toca em "Ouvir", para identificar a altura das notas.'),
              ('O que acontece com o som', 'É analisado em tempo real no próprio aparelho e descartado em seguida. Nenhum áudio é gravado, guardado ou enviado.'),
              ('O que fica salvo', 'Suas configurações, o tempo de estudo e as escalas que você salvar. Tudo fica apenas neste aparelho.'),
              ('Conta e dados pessoais', 'Não há login, cadastro, anúncios nem rastreamento. O app não pede nome, e-mail nem localização.'),
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
