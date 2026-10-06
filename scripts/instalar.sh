#!/usr/bin/env bash
# Instalador de Radar NEXO: configura Supabase y la IA en un solo paso guiado.
# Antes de correrlo necesitas (lo haces tú, en el navegador):
#   1) Cuenta y proyecto en Supabase (plan Pro) → https://supabase.com
#   2) Clave de API de Anthropic con límite de gasto → https://console.anthropic.com
# Uso:  ./scripts/instalar.sh
set -euo pipefail
. "$(dirname "$0")/_comun.sh"
cd "$RAIZ"

titulo "Radar NEXO — instalación"
verificar_requisitos

titulo "1/7  Ingreso a Supabase"
if SB projects list >/dev/null 2>&1; then ok "Ya hay una sesión de Supabase abierta."
else
  info "Se abrirá el navegador. Copia el código de verificación que muestra la página y pégalo AQUÍ rápido (caduca en pocos minutos)."
  if ! SB login; then
    warn "El ingreso con código no funcionó. Alternativa con token de acceso personal:"
    echo "     1) Abre https://supabase.com/dashboard/account/tokens"
    echo "     2) «Generate new token», nómbralo radar-nexo y cópialo (empieza por sbp_)"
    read -r -s -p "  Pega el token (no se verá en pantalla): " SUPABASE_ACCESS_TOKEN; echo
    [ -n "$SUPABASE_ACCESS_TOKEN" ] || fallo "No se completó el ingreso."
    export SUPABASE_ACCESS_TOKEN
    SB projects list >/dev/null 2>&1 || fallo "El token no fue aceptado. Revisa que lo copiaste completo."
    ok "Ingreso con token aceptado (solo vive mientras esta ventana esté abierta)."
  fi
fi

titulo "2/7  Proyecto"
pedir_ref
ok "Proyecto: $REF"

titulo "3/7  Base de datos (tablas, seguridad y funciones)"
if SB db query --project-ref "$REF" --linked -f supabase/schema.sql >/dev/null 2>&1 \
   || { SB link --project-ref "$REF" --yes >/dev/null 2>&1 </dev/null && SB db query --linked -f supabase/schema.sql >/dev/null 2>&1; }; then
  ok "Esquema aplicado."
else
  warn "No pude aplicar el esquema automáticamente."
  echo "     Hazlo a mano (30 segundos): Supabase → SQL Editor → New query → pega el contenido de"
  echo "     supabase/schema.sql → Run. Luego vuelve a ejecutar este instalador."
  read -r -p "  ¿Ya lo aplicaste a mano y quieres continuar? (s/N) " R; [ "$R" = "s" ] || [ "$R" = "S" ] || exit 1
fi

titulo "4/7  Clave de la IA (Anthropic)"
echo "  Pega tu clave de Anthropic (no se verá en pantalla ni se guardará en ningún archivo del proyecto)."
read -r -s -p "  ANTHROPIC_API_KEY: " AKEY; echo
[ -n "$AKEY" ] || fallo "No escribiste ninguna clave."
ENVF="$(mktemp)"; chmod 600 "$ENVF"
trap 'rm -f "$ENVF"' EXIT
printf 'ANTHROPIC_API_KEY=%s\nLIMITE_DIARIO=150\n' "$AKEY" > "$ENVF"
AKEY=""
SB secrets set --project-ref "$REF" --env-file "$ENVF" >/dev/null 2>&1 || fallo "No pude guardar el secreto en Supabase."
rm -f "$ENVF"
ok "Clave guardada como secreto del servidor."

titulo "5/7  Función de análisis con IA"
SB functions deploy analizar --project-ref "$REF" --use-api --no-verify-jwt || fallo "No se pudo publicar la función 'analizar'."
ok "Función publicada."

titulo "6/7  Seguridad de acceso (sin registro público + enlace de recuperación)"
echo "  Se aplicará: registro público DESACTIVADO y dirección de la app para recuperar contraseñas."
if SB config push --project-ref "$REF" --yes >/dev/null 2>&1; then ok "Configuración aplicada."
else warn "No pude aplicarla automáticamente. Hazlo a mano en Supabase → Authentication:"
     echo "     • Sign In / Providers: desactiva 'Allow new users to sign up'"
     echo "     • URL Configuration: Site URL y Redirect URL = https://scalaig.github.io/radar-nexo/app/"; fi

titulo "7/7  Conectar la aplicación y crear tu usuario administrador"
cargar_claves
python3 - "$URL" "$ANON" <<'PY'
import re, sys
url, anon = sys.argv[1], sys.argv[2]
p = "app/config.js"
s = open(p, encoding="utf-8").read()
s = re.sub(r'SUPABASE_URL:\s*"[^"]*"', 'SUPABASE_URL: "%s"' % url, s)
s = re.sub(r'SUPABASE_ANON_KEY:\s*"[^"]*"', 'SUPABASE_ANON_KEY: "%s"' % anon, s)
open(p, "w", encoding="utf-8").write(s)
PY
ok "app/config.js actualizado (solo contiene la clave pública)."
read -r -p "  Tu correo de administrador: " MAIL
read -r -p "  Tu nombre: " NOM
"$RAIZ/scripts/crear_usuario.sh" "$MAIL" "$NOM" admin

titulo "Listo. Último paso: publicar"
cat <<MSG
  Ejecuta:
      cd "$RAIZ"
      git add app supabase docs scripts .gitignore README.md
      git commit -m "Radar NEXO: version para el equipo"
      git push origin main
  Espera 1–2 minutos y entra a https://scalaig.github.io/radar-nexo/app/
  Luego haz la prueba de humo de docs/GUIA_PUESTA_EN_MARCHA.md (Paso de pruebas).
  Para agregar consultores:  ./scripts/crear_usuario.sh correo "Nombre" consultor
MSG
