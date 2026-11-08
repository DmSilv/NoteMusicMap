import 'dart:async';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'safe_input.dart';
import 'theme.dart';

/// Abre a câmera para ler o QR de um aluno ou de um professor. Também deixa
/// digitar o código na mesma tela (se a câmera estiver sem permissão ou o QR
/// não sair). Devolve o código lido, ou null se a pessoa voltar.
///
/// [want] limita o que vale: 'aluno' (QR do aluno), 'professor' (QR do
/// professor) ou null para qualquer código.
///
/// [check] confere o código lido com as regras do app (ex.: não ser o próprio
/// código): devolve o problema a mostrar, ou null se está certo. [onCamera]
/// avisa se a câmera abriu (true) ou foi negada (false), para a tela de permissões.
Future<ScannedCode?> scanShareCode(
  BuildContext context, {
  required String title,
  String? want,
  String? Function(String code)? check,
  void Function(bool granted)? onCamera,
}) {
  return Navigator.of(context).push<ScannedCode>(
    MaterialPageRoute(
        builder: (_) => QrScanPage(title: title, want: want, check: check, onCamera: onCamera),
        fullscreenDialog: true),
  );
}

class QrScanPage extends StatefulWidget {
  final String title;
  final String? want;
  final String? Function(String code)? check;
  final void Function(bool granted)? onCamera;
  const QrScanPage({super.key, required this.title, this.want, this.check, this.onCamera});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _cam = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    // Normal (com intervalo): um QR inválido que continua na frente da câmera é
    // lido de novo e o aviso reaparece, em vez de a tela ficar parada e muda.
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 900,
  );
  final TextEditingController _typed = TextEditingController();
  String? _message; // erro do campo digitado
  String? _bannerTitle; // aviso sobre a câmera (QR lido)
  String? _bannerText;
  Timer? _bannerTimer;
  bool _done = false;
  bool? _reported;

  @override
  void initState() {
    super.initState();
    _cam.addListener(_onCamera);
  }

  /// Conta à tela de permissões se a câmera abriu ou foi negada.
  void _onCamera() {
    final s = _cam.value;
    final bool? now = s.error?.errorCode == MobileScannerErrorCode.permissionDenied
        ? false
        : (s.isRunning ? true : null);
    if (now != null && now != _reported) {
      _reported = now;
      widget.onCamera?.call(now);
    }
  }

  @override
  void dispose() {
    _cam.removeListener(_onCamera);
    _bannerTimer?.cancel();
    _cam.dispose();
    _typed.dispose();
    super.dispose();
  }

  /// Mostra um aviso vermelho sobre a câmera (some sozinho).
  void _banner(String title, String text) {
    _bannerTimer?.cancel();
    setState(() {
      _bannerTitle = title;
      _bannerText = text;
    });
    _bannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _bannerTitle = null);
    });
  }

  /// Confere o que veio e devolve, ou avisa o que está errado. Do QR (câmera) o
  /// aviso é "QR Code inválido" (o problema é o QR, não o app); do campo digitado
  /// é "código incorreto". O conteúdo lido nunca é mostrado nem aberto.
  void _accept(String raw, {required bool fromCamera}) {
    if (_done) return;
    final s = parseScannedCode(raw, extraHosts: {if (kIsWeb) Uri.base.host});
    if (s == null) {
      if (fromCamera) {
        _banner('QR Code inválido',
            'Este QR não é do Notemusic, então não há nada para fazer com ele. '
            'Aponte para o QR de um aluno ou professor do app.');
      } else {
        setState(() => _message = 'Código incorreto. Confira as letras e os números (ex.: K7QM-4TXD).');
      }
      return;
    }
    if (widget.want != null && s.kind != 'codigo' && s.kind != widget.want) {
      final msg = s.kind == 'aluno'
          ? 'Este é o QR de um aluno. Aqui é preciso o QR do professor.'
          : 'Este é o QR de um professor. Aqui é preciso o QR do aluno.';
      if (fromCamera) {
        _banner('QR do tipo errado', msg);
      } else {
        setState(() => _message = msg);
      }
      return;
    }
    final problem = widget.check?.call(s.code);
    if (problem != null) {
      if (fromCamera) {
        _banner('Não dá para usar este QR', problem);
      } else {
        setState(() => _message = problem);
      }
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
              child: Stack(children: [
                Positioned.fill(
                  child: ClipRect(
                child: MobileScanner(
                  controller: _cam,
                  onDetect: (cap) {
                    for (final b in cap.barcodes) {
                      final v = b.rawValue;
                      if (v != null) {
                        _accept(v, fromCamera: true);
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
                if (_bannerTitle != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: _InvalidBanner(title: _bannerTitle!, text: _bannerText ?? ''),
                  ),
              ]),
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
                          enableSuggestions: false,
                          inputFormatters: codeFormatters,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(hintText: 'K7QM-4TXD', errorText: _message, errorMaxLines: 3),
                          onChanged: (_) {
                            if (_message != null) setState(() => _message = null);
                          },
                          onSubmitted: (v) => _accept(v, fromCamera: false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: () => _accept(_typed.text, fromCamera: false), child: const Text('Usar código')),
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

/// Aviso vermelho sobre a câmera: o QR lido não serve.
class _InvalidBanner extends StatelessWidget {
  final String title;
  final String text;
  const _InvalidBanner({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Material(
        color: const Color(0xFFB3261E),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.qr_code_2, color: Colors.white, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(text,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
