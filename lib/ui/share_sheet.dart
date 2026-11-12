import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'settings_page.dart' show kAppName;
import 'theme.dart';
import 'toast.dart';
import 'package:afina_core/afina_core.dart';

/// Endereço público do app (usado no celular; na web vale o endereço aberto).
const String kShareUrl = String.fromEnvironment(
  'SHARE_URL',
  defaultValue: 'https://notemusicmap.vercel.app',
);

String shareLink() {
  if (kIsWeb) {
    final b = Uri.base;
    final isLocal = b.host == 'localhost' || b.host == '127.0.0.1';
    if (!isLocal && b.host.isNotEmpty) return '${b.scheme}://${b.authority}';
  }
  return kShareUrl;
}

/// Janela de compartilhar: QR code que abre o app + link para copiar/enviar.
Future<void> showShareSheet(BuildContext context) {
  final link = shareLink();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Compartilhar {0}', [kAppName]),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('Aponte a câmera do celular para o código ou envie o link.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white, // QR precisa de fundo claro para ser lido
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: link,
                size: 200,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                semanticsLabel: tr('QR code com o endereço do app'),
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(link,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    var ok = true;
                    try {
                      await Clipboard.setData(ClipboardData(text: link))
                          .timeout(const Duration(seconds: 2));
                    } catch (_) {
                      ok = false; // navegador negou a área de transferência
                    }
                    if (c.mounted) {
                      showToast(c, ok ? tr('Link copiado') : tr('Não deu para copiar: selecione o link acima'),
                          icon: ok ? Icons.check_circle : Icons.info_outline);
                    }
                  },
                  icon: const Icon(Icons.link),
                  label: Text(tr('Copiar link')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    try {
                      await SharePlus.instance.share(ShareParams(
                        text: tr('Conheça o {0}: afinador, metrônomo e estudo para instrumentos. {1}', [kAppName, link]),
                        title: kAppName,
                      ));
                    } catch (_) {
                      await Clipboard.setData(ClipboardData(text: link));
                    }
                  },
                  icon: const Icon(Icons.ios_share),
                  label: Text(tr('Enviar')),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
}
