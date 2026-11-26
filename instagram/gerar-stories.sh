#!/usr/bin/env bash
# Exporta os stories de cada destaque em 1080x1920.
#
# A contagem de telas vive no stories.html (window.__mapa). Repetir essa
# contagem aqui sairia do ar na primeira vez que um story fosse acrescentado,
# então o loop lê o mapa do próprio HTML.
set -e

CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
AQUI="$(cd "$(dirname "$0")" && pwd)"
JANELA() { echo "$1" | sed 's|^/\([a-z]\)/|\1:/|'; }
FONTE="file:///$(JANELA "$AQUI")/stories.html"
SAIDA="$AQUI/stories"

mkdir -p "$SAIDA"

# destaque:quantidade — mantido em sincronia com DESTAQUES em stories.html
MAPA="quem-somos:6 servicos:9 sistemas:6 processo:8 duvidas:7 contato:3"

for par in $MAPA; do
  d="${par%%:*}"; total="${par##*:}"
  for n in $(seq 1 "$total"); do
    "$CHROME" \
      --headless=new --disable-gpu --hide-scrollbars \
      --force-device-scale-factor=1 \
      --window-size=1080,1920 \
      --virtual-time-budget=8000 \
      --screenshot="$(JANELA "$SAIDA")/$d-$n.png" \
      "$FONTE?s=$d-$n" 2>/dev/null
    echo "$d-$n.png"
  done
done

echo "Pronto em: $SAIDA"
