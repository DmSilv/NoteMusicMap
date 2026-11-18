import 'package:afina_core/afina_core.dart';

import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import 'design_system.dart';
import 'photo_editor.dart';
import 'web_file_pick_stub.dart'
    if (dart.library.js_interop) 'web_file_pick_web.dart';
import 'theme.dart';

enum _PhotoChoice { camera, gallery, remove }

/// Pergunta de onde vem a foto (câmera, galeria ou remover), reduz a imagem e devolve o texto base64 pronto.
/// Devolve: o texto da foto; '' para remover; null se a pessoa desistiu ou não deu para usar a imagem.
Future<String?> pickPersonPhoto(
  BuildContext context,
  AppState app, {
  required bool hasPhoto,
}) async {
  final choice = await showModalBottomSheet<_PhotoChoice>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusCard)),
    ),
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!kIsWeb ||
              defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
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
        ],
      ),
    ),
  );
  if (choice == null) return null;
  if (choice == _PhotoChoice.remove) return '';
  // Primeira vez com a câmera ou com as fotos: explica o que o app faz antes de o sistema pedir a permissão.
  final kind = choice == _PhotoChoice.camera ? 'camera' : 'gallery';
  // No navegador não: lá o pedido é do próprio navegador e o seletor de arquivos só abre logo depois do toque (uma janela no meio o bloquearia).
  if (!kIsWeb && !app.photoRationaleSeen(kind)) {
    if (!context.mounted) return null;
    final go = await _rationale(context, camera: choice == _PhotoChoice.camera);
    if (go != true) return null;
    app.markPhotoRationale(kind);
  }
  Uint8List? bytes;
  try {
    final source = choice == _PhotoChoice.camera
        ? ImageSource.camera
        : ImageSource.gallery;
    if (kIsWeb) {
      // No navegador o arquivo é lido na hora (sem endereço blob:, que no celular chegava a expirar antes de o app ler).
      bytes = await pickImageBytesWeb(camera: choice == _PhotoChoice.camera);
      if (bytes == null) return null; // desistiu
    } else {
      final picker = ImagePicker();
      XFile? f;
      try {
        // No aparelho, pede a imagem num tamanho de trabalho (no iPhone isso já converte HEIC para JPEG). No navegador NÃO: o
        // redimensionamento de lá falha com várias fotos de celular e dava "não consegui abrir"; o recorte e a redução são do editor.
        f = kIsWeb
            ? await picker.pickImage(source: source)
            : await picker.pickImage(
                source: source,
                maxWidth: 1600,
                maxHeight: 1600,
                imageQuality: 92,
                requestFullMetadata: false,
              );
      } on PlatformException catch (e) {
        // Permissão negada e afins seguem para a explicação abaixo; qualquer outro erro do seletor ganha uma segunda tentativa, sem ajustes.
        if (e.code.contains('denied') || e.code.contains('restricted') || e.code == 'already_active') {
          rethrow;
        }
        f = await picker.pickImage(source: source);
      }
      if (f == null) return null; // desistiu
      bytes = await f.readAsBytes();
    }
  } catch (e, st) {
    app.reportError(e, st, where: 'foto de perfil');
    if (!context.mounted) return null;
    // Permissão negada: diz qual (câmera ou fotos) e onde ligar. Outro erro: o aviso geral.
    final code = e is PlatformException ? e.code : '';
    final cameraDenied =
        code == 'camera_access_denied' || code == 'camera_access_restricted';
    final photosDenied =
        code == 'photo_access_denied' || code == 'photo_access_restricted';
    await _explain(
      context,
      cameraDenied
          ? tr(
              'O Notemusic não tem permissão para usar a câmera. Ative em Configurações do aparelho, em Notemusic, e tente de novo. Ou escolha uma foto da galeria.',
            )
          : photosDenied
          ? tr(
              'O Notemusic não tem permissão para ver as fotos. Ative em Configurações do aparelho, em Notemusic, e tente de novo.',
            )
          : tr(
              'Não consegui abrir a câmera ou a galeria. Confira se o Notemusic tem permissão para fotos nas configurações do aparelho.',
            ),
      detail: _short(e),
    );
    return null;
  }
  if (!context.mounted) return null;
  // ignore: use_build_context_synchronously
  final r = await editPersonPhoto(context, bytes);
  if (r == null) return null; // cancelou no editor
  if (r.photo != null) return r.photo;
  if (context.mounted) {
    await _explain(
      context,
      r.problem ??
          tr(
            'Não deu para preparar esta foto. Tente outra ou chegue mais perto do rosto.',
          ),
    );
  }
  return null;
}

/// Explica o que houve com a foto, por inteiro e com o que fazer (um aviso rápido cortava o texto).
Future<void> _explain(BuildContext context, String text, {String? detail}) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(
        Icons.photo_camera_back_outlined,
        color: AppColors.sharp,
        size: 32,
      ),
      title: Text(tr('Não deu para usar a foto')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          // A causa técnica, curta, para a pessoa poder dizer qual foi (e para o registro de problemas).
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: Ds.s12),
            Text(tr('Detalhe: {0}', [detail]), style: Ds.support()),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(c),
          child: Text(tr('Entendi')),
        ),
      ],
    ),
  );
}

/// Antes do pedido do sistema: para que o app usa a câmera ou as fotos (e o que NÃO faz).
Future<bool?> _rationale(BuildContext context, {required bool camera}) {
  return showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(
        camera ? Icons.photo_camera_outlined : Icons.photo_library_outlined,
        color: AppColors.accent,
        size: 32,
      ),
      title: Text(camera ? tr('Usar a câmera?') : tr('Usar as suas fotos?')),
      content: Text(
        camera
            ? tr(
                'O Notemusic usa a câmera só para tirar a foto do seu perfil. Nada é gravado nem enviado sem você escolher mostrar a foto.',
              )
            : tr(
                'O Notemusic só vê a foto que você escolher para o seu perfil. Nada é enviado sem você escolher mostrar a foto.',
              ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(tr('Agora não')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(tr('Continuar')),
        ),
      ],
    ),
  );
}

/// A causa do erro em poucas palavras (código do sistema ou o começo da mensagem).
String _short(Object e) {
  final s = e is PlatformException
      ? '${e.code}: ${e.message ?? ''}'
      : e.toString();
  final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return one.length > 120 ? one.substring(0, 120) : one;
}
