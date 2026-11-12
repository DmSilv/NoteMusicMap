import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import 'theme.dart';
import 'widgets.dart';

IconData errorIcon(ErrorSeverity s) => switch (s) {
      ErrorSeverity.critical => Icons.error_outline,
      ErrorSeverity.action => Icons.warning_amber_rounded,
      ErrorSeverity.info => Icons.cloud_off_outlined,
    };

Color errorTint(ErrorSeverity s) => switch (s) {
      ErrorSeverity.critical => AppColors.sharp,
      ErrorSeverity.action => AppColors.flat,
      ErrorSeverity.info => AppColors.textDim,
    };

/// "há 5 min" / "ontem" para a hora de um problema.
String errorAgo(int atMs, {DateTime? now}) {
  final m = (now ?? DateTime.now()).difference(DateTime.fromMillisecondsSinceEpoch(atMs)).inMinutes;
  if (m < 1) return tr('agora');
  if (m < 60) return tr('há {0} min', [m]);
  if (m < 60 * 24) return tr('há {0} h', [m ~/ 60]);
  final d = m ~/ (60 * 24);
  return d == 1 ? tr('ontem') : tr('há {0} d', [d]);
}

/// Tela cheia para quando o app não consegue seguir (ex.: falha ao abrir).
/// Mostra o que houve, o código para citar e o que fazer.
class CriticalErrorPage extends StatelessWidget {
  final AppError error;
  final VoidCallback onRetry;
  const CriticalErrorPage({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final log = ErrorLog()..add(error);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Icon(errorIcon(error.severity), size: 64, color: errorTint(error.severity)),
                const SizedBox(height: 16),
                Text(error.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(error.message, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, height: 1.4)),
                const SizedBox(height: 14),
                Center(child: _CodeChip(error.shortId)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(error.action),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: log.report()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Detalhes copiados.'))));
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(tr('Copiar detalhes')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String id;
  const _CodeChip(this.id);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.textDim.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.outline),
        ),
        child: Text(tr('Código {0}', [id]), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textDim)),
      );
}

/// Entra no lugar de um bloco que quebrou ao desenhar (em vez da tela cinza/vermelha):
/// o resto da tela segue funcionando.
class FriendlyErrorWidget extends StatelessWidget {
  final String id;
  const FriendlyErrorWidget({super.key, required this.id});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.flat.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.flat),
          const SizedBox(width: 10),
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Este bloco não carregou'), style: TextStyle(fontWeight: FontWeight.w800)),
              Text(tr('Código {0}', [id]), style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            ]),
          ),
        ]),
      );
}

/// Ajustes › Diagnóstico › Problemas recentes.
class ProblemsPage extends StatefulWidget {
  final AppState app;
  const ProblemsPage({super.key, required this.app});

  @override
  State<ProblemsPage> createState() => _ProblemsPageState();
}

class _ProblemsPageState extends State<ProblemsPage> {
  AppState get app => widget.app;

  void _detail(AppError e) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [
          Icon(errorIcon(e.severity), color: errorTint(e.severity)),
          const SizedBox(width: 8),
          Expanded(child: Text(e.title)),
        ]),
        content: SingleChildScrollView(
          child: SelectionArea(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.message, style: const TextStyle(height: 1.35)),
              const SizedBox(height: 10),
              Text(tr('Código {0} · {1}', [e.shortId, e.code]), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              if (e.where.isNotEmpty) Text(tr('Onde: {0}', [e.where]), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              if (e.detail.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(e.detail, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: AppColors.textDim)),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final ok = await app.sendReport(e);
              app.say(ok ? tr('Relatório enviado. Obrigado!') : tr('Não foi possível enviar agora. Tente de novo mais tarde.'));
            },
            icon: const Icon(Icons.send, size: 18),
            label: Text(tr('Enviar relatório')),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Fechar'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = app.errorLog.items;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Problemas recentes'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (items.isEmpty)
            AppCard(
              child: Row(children: [
                Icon(Icons.check_circle_outline, color: AppColors.inTune),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('Nenhum problema registrado. Está tudo certo por aqui.'))),
              ]),
            )
          else ...[
            for (final e in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(errorIcon(e.severity), color: errorTint(e.severity)),
                    title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${e.shortId} · ${errorAgo(e.atMs)}${app.errorLog.repeatsOf(e) > 1 ? tr(' · {0}x', [app.errorLog.repeatsOf(e)]) : ''}'
                      '${e.where.isEmpty ? '' : '\n${e.where}'}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.3),
                    ),
                    isThreeLine: e.where.isNotEmpty,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _detail(e),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: app.errorLog.report()));
                    app.say(tr('Relatório copiado.'));
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(tr('Copiar relatório')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(app.clearErrors),
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: Text(tr('Limpar')),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
