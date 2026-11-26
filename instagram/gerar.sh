#!/usr/bin/env bash
# Exporta os slides do carrossel em 1080x1350, resolução de publicação.
#
# Usa o Chrome em modo headless: renderiza o mesmo HTML que o navegador
# mostra, com as fontes do Google e os assets do site, e salva o PNG.
# --virtual-time-budget dá tempo de as fontes e as imagens carregarem
# antes da captura; sem ele o texto sai na fonte de sistema.
set -e

CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
AQUI="$(cd "$(dirname "$0")" && pwd)"
FONTE="file:///$(echo "$AQUI" | sed 's|^/\([a-z]\)/|\1:/|')/quem-somos.html"
SAIDA="$AQUI/slides"

mkdir -p "$SAIDA"

for n in 1 2 3 4 5 6 7 8; do
  "$CHROME" \
    --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 \
    --window-size=1080,1350 \
    --virtual-time-budget=8000 \
    --screenshot="$(echo "$SAIDA" | sed 's|^/\([a-z]\)/|\1:/|')/slide-$n.png" \
    "$FONTE?s=$n" 2>/dev/null
  echo "slide-$n.png"
done

echo "Pronto em: $SAIDA"
