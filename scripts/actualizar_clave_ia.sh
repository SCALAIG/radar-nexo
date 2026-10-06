#!/usr/bin/env bash
# Cambia (o corrige) la clave de Anthropic que usa la función de análisis con IA.
# Antes de guardarla, la prueba directamente con Anthropic: si no es válida, no la guarda.
# Uso:  ./scripts/actualizar_clave_ia.sh
set -euo pipefail
. "$(dirname "$0")/_comun.sh"
cd "$RAIZ"

titulo "Actualizar la clave de la IA (Anthropic)"
verificar_requisitos
pedir_ref

echo "  1) En la página de Anthropic, selecciona la clave y cópiala con Cmd+C."
echo "  2) Vuelve aquí y presiona Enter. El script la leerá de lo que copiaste (no hace falta pegar)."
read -r -p "  Presiona Enter cuando ya la hayas copiado... " _
if command -v pbpaste >/dev/null 2>&1; then AKEY="$(pbpaste)"; else read -r -s -p "  ANTHROPIC_API_KEY: " AKEY; echo; fi
# quita espacios, saltos de línea y comillas que se cuelan al copiar
AKEY="$(printf '%s' "$AKEY" | tr -d '[:space:]"'"'"'')"
[ -n "$AKEY" ] || fallo "No escribiste ninguna clave."
info "Se leyó una clave de ${#AKEY} caracteres que empieza por ${AKEY:0:10}... y termina en ...${AKEY: -4}"
case "$AKEY" in sk-ant-*) ;; *) fallo "La clave no empieza por sk-ant-. Revisa que copiaste la clave completa.";; esac

info "Probando la clave con Anthropic..."
CODIGO="$(curl -s -o /dev/null -w '%{http_code}' https://api.anthropic.com/v1/models \
  -H "x-api-key: $AKEY" -H "anthropic-version: 2023-06-01" || true)"
case "$CODIGO" in
  200) ok "Anthropic aceptó la clave." ;;
  401) fallo "Anthropic rechazó la clave (401). Crea una nueva en console.anthropic.com → API keys y vuelve a correr este comando." ;;
  *)   fallo "No pude validar la clave (respuesta $CODIGO). Revisa tu conexión e intenta de nuevo." ;;
esac

ENVF="$(mktemp)"; chmod 600 "$ENVF"
trap 'rm -f "$ENVF"' EXIT
printf 'ANTHROPIC_API_KEY=%s\n' "$AKEY" > "$ENVF"
AKEY=""
SB secrets set --project-ref "$REF" --env-file "$ENVF" >/dev/null 2>&1 || fallo "No pude guardar el secreto en Supabase."
rm -f "$ENVF"
ok "Clave guardada en Supabase. Ya puedes usar \"Generar análisis\" en la aplicación."

info "Publicando la función con la clave nueva..."
SB functions deploy analizar --project-ref "$REF" --use-api --no-verify-jwt >/dev/null 2>&1 || fallo "No pude publicar la función 'analizar'."
ok "Función publicada. Ya puedes usar \"Generar análisis\" en la aplicación."
