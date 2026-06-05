#!/usr/bin/env bash
#
# Gera o NotionExport.app e empacota num .dmg — feito para rodar NUM MAC.
# Instala sozinho o que faltar (Homebrew e XcodeGen). Só o Xcode você
# precisa instalar antes, pela App Store.
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
VOL_NAME="Vitamina · Notion Export"

echo "==> 1/5 Verificando o Xcode…"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "" >&2
  echo "ERRO: o Xcode completo não está pronto." >&2
  echo "  • Instale o Xcode pela App Store (busque \"Xcode\")." >&2
  echo "  • Abra o Xcode uma vez e aceite os termos." >&2
  echo "  • Se ainda falhar, rode no Terminal: sudo xcodebuild -license accept" >&2
  echo "  • E: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

echo "==> 2/5 Verificando o Homebrew…"
if ! command -v brew >/dev/null 2>&1; then
  # Carrega o brew caso já exista mas não esteja no PATH
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$p" ] && eval "$("$p" shellenv)"
  done
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "    Homebrew não encontrado; instalando (vai pedir sua senha do Mac)…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$p" ] && eval "$("$p" shellenv)"
  done
fi

echo "==> 3/5 Verificando o XcodeGen…"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "    Instalando o XcodeGen…"
  brew install xcodegen
fi

echo "==> 4/5 Gerando o projeto e compilando (Release, assinatura ad-hoc)…"
xcodegen generate
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

echo "==> 5/5 Montando o .dmg…"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/stage"
cp -R "${APP_PATH}" "${DIST_DIR}/stage/"
ln -s /Applications "${DIST_DIR}/stage/Applications"
hdiutil create -volname "${VOL_NAME}" -srcfolder "${DIST_DIR}/stage" \
  -ov -format UDZO "${DMG_PATH}"
rm -rf "${DIST_DIR}/stage"

echo ""
echo "============================================================"
echo " PRONTO! Seu instalador está em:"
echo "   $(pwd)/${DMG_PATH}"
echo ""
echo " Abra o .dmg, arraste o app para Aplicativos."
echo " No 1º uso: clique com o botão DIREITO no app -> Abrir -> Abrir"
echo " (libera o Gatekeeper, já que não há assinatura paga)."
echo "============================================================"
