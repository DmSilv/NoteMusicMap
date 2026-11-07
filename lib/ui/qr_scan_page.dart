import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'theme.dart';

/// Abre a câmera para ler o QR de um aluno ou de um professor. Também deixa
/// digitar o código na mesma tela (se a câmera estiver sem permissão ou o QR
/// não sair). Devolve o código lido, ou null se a pessoa voltar.
///
/// [want] limita o que vale: 'aluno' (QR do aluno), 'professor' (QR do
/// professor) ou null para qualquer código.
Future<ScannedCode?> scanShareCode(BuildContext context, {required String title, String? want}) {
  return Navigator.of(context).push<ScannedCode>(
    MaterialPageRoute(builder: (_) => QrScanPage(title: title, want: want), fullscreenDialog: true),
  );
}

class QrScanPage extends StatefulWidget {
  final String title;
  final String? want;
  const QrScanPage({super.key, required this.title, this.want});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _cam = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final TextEditingController _typed = TextEditingController();
  String? _message;
  bool _done = false;

  @override
  void dispose() {
    _cam.dispose();
    _typed.dispose();
    super.dispose();
  }

  /// Confere o que veio (da câmera ou digitado) e devolve, ou avisa o que está errado.
  void _accept(String raw) {
    if (_done) return;
    final s = parseScannedCode(raw);
    if (s == null) {
      setState(() => _message = 'Este não é um código do Notemusic. Confira e tente de novo.');
      return;
    }
    if (widget.want != null && s.kind != 'codigo' && s.kind != widget.want) {
      setState(() => _message = s.kind == 'aluno'
          ? 'Este é o QR de um aluno. Aqui é preciso o QR do professor.'
          : 'Este é o QR de um professor. Aqui é preciso o QR do aluno.');
      return;
    }
    _done = true;
    Navigator.of(context).pop(s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ClipRect(
                child: MobileScanner(
                  controller: _cam,
                  onDetect: (cap) {
                    for (final b in cap.barcodes) {
                      final v = b.rawValue;
                      if (v != null) {
                        _accept(v);
                        break;
                      }
                    }
                  },
                  errorBuilder: (context, error) => _CameraProblem(error: error),
                  placeholderBuilder: (context) => const ColoredBox(
                    color: Colors.black,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  // Moldura para mirar o QR (só aparece quando a câmera está funcionando).
                  overlayBuilder: (context, constraints) => IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 230,
                        height: 230,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aponte a câmera para o QR. Se preferir, digite o código:',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _typed,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(hintText: 'K7QM-4TXD', errorText: _message, errorMaxLines: 3),
                          onChanged: (_) {
                            if (_message != null) setState(() => _message = null);
                          },
                          onSubmitted: _accept,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: () => _accept(_typed.text), child: const Text('Usar código')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Câmera indisponível ou sem permissão: explica e deixa seguir digitando.
class _CameraProblem extends StatelessWidget {
  final MobileScannerException error;
  const _CameraProblem({required this.error});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    final text = denied
        ? 'O Notemusic não tem permissão para usar a câmera. Libere nas configurações do aparelho (ou do navegador) '
            'para ler o QR, ou digite o código abaixo.'
        : unsupported
            ? 'Este aparelho ou navegador não consegue ler QR pela câmera. Digite o código abaixo.'
            : 'Não foi possível abrir a câmera agora. Digite o código abaixo.';
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 44),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}
