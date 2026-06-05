#!/usr/bin/env bash
#
# Gera o NotionExport.app e empacota num .dmg.
# RODE ESTE SCRIPT NUM MAC com Xcode instalado (Linux não compila apps macOS).
#
#   cd fcpx-notion-export
#   ./build_dmg.sh
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NotionExport"
SCHEME="NotionExport"
BUILD_DIR="build"
DIST_DIR="dist"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
VOL_NAME="Notion Export"

echo "==> Verificando ferramentas…"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERRO: Xcode não encontrado. Instale o Xcode pela App Store e rode 'xcode-select --install'." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> XcodeGen não encontrado; instalando via Homebrew…"
  if ! command -v brew >/dev/null 2>&1; then
    echo "ERRO: Homebrew não encontrado. Instale em https://brew.sh e rode novamente." >&2
    exit 1
  fi
  brew install xcodegen
fi

echo "==> Gerando o projeto Xcode (project.yml -> ${APP_NAME}.xcodeproj)…"
xcodegen generate

echo "==> Compilando (Release, assinatura ad-hoc)…"
rm -rf "${BUILD_DIR}"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  clean build

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${APP_PATH}" ]; then
  echo "ERRO: app não encontrado em ${APP_PATH}" >&2
  exit 1
fi

echo "==> Montando o .dmg…"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/stage"
cp -R "${APP_PATH}" "${DIST_DIR}/stage/"
ln -s /Applications "${DIST_DIR}/stage/Applications"

hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${DIST_DIR}/stage" \
  -ov -format UDZO \
  "${DMG_PATH}"

rm -rf "${DIST_DIR}/stage"
echo ""
echo "==> Pronto! DMG gerado em: ${DMG_PATH}"
echo "    Arraste o app para Aplicativos. No 1º uso: botão direito no app -> Abrir"
echo "    (para liberar o Gatekeeper, já que não há assinatura paga)."
