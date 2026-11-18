// Escolher foto no NAVEGADOR lendo o arquivo na hora, sem passar por endereço "blob:".
//
// O seletor padrão (image_picker) devolve um endereço blob: do arquivo e só depois o app o baixa. No celular esse endereço
// pode já ter expirado quando o app vai ler (o navegador solta o arquivo quando a página volta da câmera ou da galeria),
// e a foto "abria" mas não entrava no app. Aqui o conteúdo é lido pelo FileReader assim que a pessoa escolhe.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Abre o seletor de arquivos de imagem (ou a câmera, com [camera]) e devolve os bytes; null se a pessoa desistiu.
/// Lança se o navegador não conseguir ler o arquivo.
Future<Uint8List?> pickImageBytesWeb({required bool camera}) {
  final done = Completer<Uint8List?>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = 'image/*';
  if (camera) input.setAttribute('capture', 'user'); // câmera da frente: é a foto do perfil
  input.style.display = 'none';
  web.document.body!.append(input);

  void finish({Uint8List? bytes, Object? error}) {
    if (!done.isCompleted) {
      if (error != null) {
        done.completeError(error);
      } else {
        done.complete(bytes);
      }
    }
    input.remove();
  }

  input.addEventListener(
      'change',
      ((web.Event _) {
        final files = input.files;
        if (files == null || files.length == 0) {
          finish();
          return;
        }
        final reader = web.FileReader();
        reader.addEventListener(
            'load',
            ((web.Event _) {
              try {
                final result = reader.result;
                if (result == null) {
                  finish(error: StateError('arquivo vazio'));
                  return;
                }
                finish(bytes: (result as JSArrayBuffer).toDart.asUint8List());
              } catch (e) {
                finish(error: e);
              }
            }).toJS);
        reader.addEventListener('error', ((web.Event _) => finish(error: StateError('não deu para ler o arquivo'))).toJS);
        reader.readAsArrayBuffer(files.item(0)!);
      }).toJS);
  // Fechou o seletor sem escolher (navegadores novos avisam com "cancel").
  input.addEventListener('cancel', ((web.Event _) => finish()).toJS);
  input.click();
  return done.future;
}
