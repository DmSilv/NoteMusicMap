import 'dart:convert';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import 'design_system.dart';

enum _PhotoChoice { camera, gallery, remove }

/// Pergunta de onde vem a foto (câmera, galeria ou remover), reduz a imagem e devolve o texto base64 pronto.
/// Devolve: o texto da foto; '' para remover; null se a pessoa desistiu ou não deu para usar a imagem.
Future<String?> pickPersonPhoto(BuildContext context, AppState app, {required bool hasPhoto}) async {
  final choice = await showModalBottomSheet<_PhotoChoice>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard))),
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!kIsWeb)
          ListTile(
            minTileHeight: Ds.tap,
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr('Tirar uma foto')),
            onTap: () => Navigator.pop(c, _PhotoChoice.camera),
          ),
        ListTile(
          minTileHeight: Ds.tap,
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(tr('Escolher da galeria')),
          onTap: () => Navigator.pop(c, _PhotoChoice.gallery),
        ),
        if (hasPhoto)
          ListTile(
            minTileHeight: Ds.tap,
            leading: const Icon(Icons.delete_outline),
            title: Text(tr('Remover a foto')),
            onTap: () => Navigator.pop(c, _PhotoChoice.remove),
          ),
        const SizedBox(height: Ds.s8),
      ]),
    ),
  );
  if (choice == null) return null;
  if (choice == _PhotoChoice.remove) return '';
  try {
    final picker = ImagePicker();
    final source = choice == _PhotoChoice.camera ? ImageSource.camera : ImageSource.gallery;
    final f = await picker.pickImage(
        source: source, maxWidth: kPhotoSide.toDouble(), maxHeight: kPhotoSide.toDouble(), imageQuality: kPhotoQuality, requestFullMetadata: false);
    if (f == null) return null; // desistiu
    final clean = cleanPhoto(base64Encode(await f.readAsBytes()));
    if (clean != null) return clean;
  } catch (_) {
    // sem permissão, sem câmera ou imagem que o navegador não leu: cai na mensagem abaixo
  }
  app.say(tr('Não foi possível usar essa foto. Tente uma foto da câmera ou da galeria (JPEG).'));
  return null;
}
