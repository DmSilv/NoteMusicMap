#!/usr/bin/env bash
# Build do Notemusic (Flutter Web) para a Vercel.
# A Vercel não tem o Flutter, então baixamos uma versão FIXA (a mesma testada
# localmente) para o build ser reproduzível e não quebrar quando sair uma versão nova.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.9}"
FLUTTER_DIR="${HOME}/flutter-${FLUTTER_VERSION}"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo ">> Baixando Flutter ${FLUTTER_VERSION}"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"
export PUB_CACHE="${HOME}/.pub-cache"
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true

flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true
flutter precache --web
flutter pub get

echo ">> Compilando para a web (release)"
flutter build web --release

echo ">> Pronto: build/web"
ls -la build/web | head -20
