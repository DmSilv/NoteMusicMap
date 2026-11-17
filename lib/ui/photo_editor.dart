import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'design_system.dart';
import 'theme.dart';

/// Resultado do editor: o texto da foto pronta (base64 de um JPEG pequeno) ou o motivo de não ter dado certo.
class PhotoResult {
  final String? photo;
  final String? problem;
  const PhotoResult.ok(String this.photo) : problem = null;
  const PhotoResult.fail(String this.problem) : photo = null;
}

/// Lê qualquer imagem que a plataforma saiba abrir (JPEG, PNG, WebP, GIF, HEIC no iPhone…) já em tamanho de trabalho,
/// deixa a pessoa ARRASTAR e APROXIMAR dentro de um círculo e devolve a foto recortada, reduzida e em JPEG pequeno.
/// Devolve null se a pessoa cancelou.
Future<PhotoResult?> editPersonPhoto(BuildContext context, Uint8List bytes) async {
  ui.Image decoded;
  try {
    // Decodifica já reduzindo (a foto de câmera pode ter 12 megapixels): o que a plataforma abrir, o editor aceita.
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1000);
    decoded = (await codec.getNextFrame()).image;
  } catch (_) {
    return PhotoResult.fail(tr('Este arquivo não parece uma imagem que o aparelho consiga abrir. Tente outra foto.'));
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<PhotoResult>(MaterialPageRoute<PhotoResult>(fullscreenDialog: true, builder: (_) => _PhotoEditor(image: decoded)));
}

class _PhotoEditor extends StatefulWidget {
  final ui.Image image;
  const _PhotoEditor({required this.image});

  @override
  State<_PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<_PhotoEditor> {
  static const double _box = 300; // lado da janela de recorte (px lógicos)
  final _ctl = TransformationController();
  double _zoom = 1;
  bool _busy = false;

  ui.Image get im => widget.image;

  /// A imagem aparece com o MENOR lado ocupando a janela inteira.
  double get _childW => im.width >= im.height ? _box * im.width / im.height : _box;
  double get _childH => im.width >= im.height ? _box : _box * im.height / im.width;

  @override
  void initState() {
    super.initState();
    _ctl.value = Matrix4.identity()..translateByDouble(-(_childW - _box) / 2, -(_childH - _box) / 2, 0, 1);
    _ctl.addListener(() {
      final s = _ctl.value.getMaxScaleOnAxis();
      if ((s - _zoom).abs() > 0.001 && mounted) setState(() => _zoom = s);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Muda o zoom pelo controle deslizante, mantendo o centro da janela no mesmo ponto da imagem.
  void _setZoom(double z) {
    final m = _ctl.value;
    final s = m.getMaxScaleOnAxis();
    final tx = m.storage[12], ty = m.storage[13];
    final cx = (_box / 2 - tx) / s, cy = (_box / 2 - ty) / s; // ponto da imagem no centro da janela
    var ntx = _box / 2 - cx * z, nty = _box / 2 - cy * z;
    ntx = ntx.clamp(_box - _childW * z, 0.0);
    nty = nty.clamp(_box - _childH * z, 0.0);
    _ctl.value = Matrix4.identity()
      ..translateByDouble(ntx, nty, 0, 1)
      ..scaleByDouble(z, z, 1, 1);
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    try {
      final m = _ctl.value;
      final s = m.getMaxScaleOnAxis();
      final k = (im.width >= im.height ? im.height : im.width) / _box; // px da imagem por px da janela
      var x = (-m.storage[12] / s) * k, y = (-m.storage[13] / s) * k;
      final side = (_box / s) * k;
      x = x.clamp(0.0, im.width - side);
      y = y.clamp(0.0, im.height - side);
      final out = kPhotoSide;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawImageRect(im, Rect.fromLTWH(x, y, side, side), Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble()), Paint()..filterQuality = FilterQuality.high);
      final cropped = await rec.endRecording().toImage(out, out);
      final data = await cropped.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('sem pixels');
      final frame = img.Image.fromBytes(width: out, height: out, bytes: data.buffer, numChannels: 4);
      // JPEG pequeno: começa na qualidade padrão e baixa até caber no limite.
      for (final q in [kPhotoQuality + 12, kPhotoQuality, 48, 36]) {
        final jpg = Uint8List.fromList(img.encodeJpg(frame, quality: q));
        final clean = cleanPhoto(base64Encode(jpg));
        if (clean != null) {
          if (mounted) Navigator.of(context).pop(PhotoResult.ok(clean));
          return;
        }
      }
      throw StateError('grande demais');
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pop(PhotoResult.fail(tr('Não deu para preparar esta foto. Tente outra ou chegue mais perto do rosto.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ajustar foto'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Ds.screenPad),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Arraste para enquadrar e aproxime com os dedos ou com o controle.'), textAlign: TextAlign.center, style: Ds.support()),
              const SizedBox(height: Ds.s16),
              SizedBox(
                width: _box,
                height: _box,
                child: Stack(children: [
                  ClipRect(
                    child: InteractiveViewer(
                      transformationController: _ctl,
                      constrained: false,
                      minScale: 1,
                      maxScale: 5,
                      boundaryMargin: EdgeInsets.zero,
                      child: SizedBox(width: _childW, height: _childH, child: RawImage(image: im, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
                    ),
                  ),
                  // Escurece fora do círculo: o que fica dentro é o que vira foto.
                  IgnorePointer(child: CustomPaint(size: const Size(_box, _box), painter: _CirclePainter())),
                ]),
              ),
              const SizedBox(height: Ds.s16),
              Row(children: [
                const Icon(Icons.zoom_out, size: 20),
                Expanded(
                  child: Slider(
                    value: _zoom.clamp(1.0, 5.0),
                    min: 1,
                    max: 5,
                    onChanged: _setZoom,
                  ),
                ),
                const Icon(Icons.zoom_in, size: 20),
              ]),
              const SizedBox(height: Ds.s8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Ds.primaryHeight)),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(tr('Cancelar')),
                  ),
                ),
                const SizedBox(width: Ds.s12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Ds.primaryHeight)),
                    onPressed: _busy ? null : _done,
                    icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                    label: Text(tr('Usar esta foto'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 4))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = AppColors.bg.withValues(alpha: 0.72));
    canvas.drawCircle(size.center(Offset.zero), size.width / 2 - 4, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
