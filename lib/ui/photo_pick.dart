import 'package:afina_core/afina_core.dart';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'photo_editor.dart';
import 'theme.dart';

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
  Uint8List? bytes;
  try {
    final source = choice == _PhotoChoice.camera ? ImageSource.camera : ImageSource.gallery;
    // Pede a imagem num tamanho de trabalho (no iPhone isso já converte HEIC para JPEG); o recorte e a redução final são do editor.
    final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 92, requestFullMetadata: false);
    if (f == null) return null; // desistiu
    bytes = await f.readAsBytes();
  } catch (_) {
    if (!context.mounted) return null;
    await _explain(context, tr('Não consegui abrir a câmera ou a galeria. Confira se o Notemusic tem permissão para fotos nas configurações do aparelho.'));
    return null;
  }
  if (!context.mounted) return null;
  // ignore: use_build_context_synchronously
  final r = await editPersonPhoto(context, bytes);
  if (r == null) return null; // cancelou no editor
  if (r.photo != null) return r.photo;
  if (context.mounted) await _explain(context, r.problem ?? tr('Não deu para preparar esta foto. Tente outra ou chegue mais perto do rosto.'));
  return null;
}

/// Explica o que houve com a foto, por inteiro e com o que fazer (um aviso rápido cortava o texto).
Future<void> _explain(BuildContext context, String text) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(Icons.photo_camera_back_outlined, color: AppColors.sharp, size: 32),
      title: Text(tr('Não deu para usar a foto')),
      content: Text(text),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('Entendi')))],
    ),
  );
}
