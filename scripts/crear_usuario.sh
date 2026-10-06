#!/usr/bin/env bash
# Crea un usuario del equipo (confirmado y ACTIVO) con una contraseña temporal aleatoria.
# Uso:  ./scripts/crear_usuario.sh correo@dominio.com "Nombre Apellido" [admin|consultor]
# La contraseña se muestra UNA sola vez en pantalla. Entrégala por un canal seguro.
set -euo pipefail
. "$(dirname "$0")/_comun.sh"

EMAIL="${1:-}"; NOMBRE="${2:-}"; ROL="${3:-consultor}"
[ -n "$EMAIL" ] && [ -n "$NOMBRE" ] || { echo 'Uso: ./scripts/crear_usuario.sh correo "Nombre Apellido" [admin|consultor]'; exit 1; }
case "$ROL" in admin|consultor) ;; *) fallo "El rol debe ser admin o consultor.";; esac

verificar_requisitos
pedir_ref
cargar_claves
[ -n "$SERVICE" ] || fallo "No pude leer la clave de servicio del proyecto."

PASS="$(python3 -c 'import secrets,string; a=string.ascii_letters.replace("l","").replace("I","").replace("O","")+"23456789"; print("".join(secrets.choice(a) for _ in range(12))+"-"+"".join(secrets.choice("23456789") for _ in range(2)))')"
CUERPO="$(EMAIL="$EMAIL" NOMBRE="$NOMBRE" PASS="$PASS" python3 -c 'import json,os; print(json.dumps({"email":os.environ["EMAIL"],"password":os.environ["PASS"],"email_confirm":True,"user_metadata":{"nombre":os.environ["NOMBRE"]}}))')"

RESP="$(curl_servicio POST /auth/v1/admin/users -d "$CUERPO")"
if printf '%s' "$RESP" | grep -qi 'already\|registered\|exists'; then
  warn "Ese correo ya existe. Solo actualizo su nombre, rol y activación (no cambio su contraseña)."
  PASS=""
elif ! printf '%s' "$RESP" | grep -q '"id"'; then
  fallo "No se pudo crear el usuario: $RESP"
fi

PARCHE="$(NOMBRE="$NOMBRE" ROL="$ROL" python3 -c 'import json,os; print(json.dumps({"nombre":os.environ["NOMBRE"],"rol":os.environ["ROL"],"activo":True}))')"
ENC="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$EMAIL")"
R2="$(curl_servicio PATCH "/rest/v1/perfiles?email=eq.$ENC" -H "Prefer: return=representation" -d "$PARCHE")"
printf '%s' "$R2" | grep -q "$ROL" || fallo "El usuario se creó pero no pude activarlo: $R2 (¿ejecutaste el esquema de la base de datos?)"

titulo "Usuario listo"
echo "  Correo:      $EMAIL"
echo "  Nombre:      $NOMBRE"
echo "  Rol:         $ROL (activo)"
[ -n "$PASS" ] && echo "  Contraseña:  $PASS   ← guárdala ahora; no se vuelve a mostrar. Pídele que la cambie con «Olvidé mi contraseña»."
echo "  Dirección:   https://scalaig.github.io/radar-nexo/app/"
