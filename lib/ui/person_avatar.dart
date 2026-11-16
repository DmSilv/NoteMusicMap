import 'dart:typed_data';

import 'package:afina_core/afina_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Fotos já decodificadas para bytes, para a lista não decodificar o texto base64 a cada quadro.
final Map<String, Uint8List> _photoCache = {};

Uint8List? _bytesOf(String? photo) {
  if (photo == null || photo.isEmpty) return null;
  final hit = _photoCache[photo];
  if (hit != null) return hit;
  final b = photoBytes(photo);
  if (b == null) return null;
  if (_photoCache.length > 60) _photoCache.remove(_photoCache.keys.first);
  return _photoCache[photo] = b;
}

/// Círculo da pessoa: a foto, se tem; senão a inicial do nome na cor [tint] (ou na de destaque).
/// Um só componente para o perfil, a ficha do aluno, as listas e a agenda.
class PersonAvatar extends StatelessWidget {
  final String name;
  final String? photo;
  final Color? tint;
  final double radius;

  /// Desenha um anel na cor de destaque (aula hoje, tarefa esperando).
  final Color? ring;
  const PersonAvatar({super.key, required this.name, this.photo, this.tint, this.radius = 16, this.ring});

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppColors.accent;
    final bytes = _bytesOf(photo);
    final n = name.trim();
    final size = radius * 2;
    final inner = bytes != null
        ? ClipOval(
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => _initial(color, n),
            ),
          )
        : _initial(color, n);
    return Semantics(
      label: n.isEmpty ? null : n,
      child: SizedBox(
        width: size,
        height: size,
        child: ring == null
            ? inner
            : DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 2)),
                child: ClipOval(child: inner),
              ),
      ),
    );
  }

  Widget _initial(Color color, String n) => Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.2)),
        child: Text(n.isEmpty ? '?' : n.characters.first.toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: radius * 0.95)),
      );
}
