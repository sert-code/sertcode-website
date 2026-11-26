#!/usr/bin/env bash
# Exporta as capas dos destaques em 1080x1920, tamanho de story.
set -e

CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
AQUI="$(cd "$(dirname "$0")" && pwd)"
JANELA() { echo "$1" | sed 's|^/\([a-z]\)/|\1:/|'; }
FONTE="file:///$(JANELA "$AQUI")/destaques.html"
SAIDA="$AQUI/destaques"

mkdir -p "$SAIDA"

for d in quem-somos servicos sistemas processo projetos duvidas bastidores contato; do
  "$CHROME" \
    --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 \
    --window-size=1080,1920 \
    --virtual-time-budget=8000 \
    --screenshot="$(JANELA "$SAIDA")/$d.png" \
    "$FONTE?d=$d" 2>/dev/null
  echo "$d.png"
done

echo "Pronto em: $SAIDA"
