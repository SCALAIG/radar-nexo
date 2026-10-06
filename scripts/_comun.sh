#!/usr/bin/env bash
# Funciones comunes de los scripts de Radar NEXO. No se ejecuta directamente.

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_REF="$RAIZ/scripts/.proyecto"

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
info() { printf '  \033[36m•\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
fallo(){ printf '  \033[31m✘ %s\033[0m\n' "$*"; exit 1; }
titulo(){ printf '\n\033[1m%s\033[0m\n' "$*"; }

# Supabase CLI: usa el instalado; si no existe, lo ejecuta con npx (requiere Node).
SB() {
  if command -v supabase >/dev/null 2>&1; then supabase "$@"
  elif command -v npx >/dev/null 2>&1; then npx --yes supabase "$@"
  else return 127; fi
}

# Si la máquina no tiene Node.js, descarga la versión oficial (nodejs.org) SOLO para este proyecto,
# verifica su huella SHA-256 y la deja en scripts/.node. No instala nada en el resto del Mac y no pide contraseña.
asegurar_node() {
  if command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then return 0; fi
  local dir="$RAIZ/scripts/.node"
  if [ -x "$dir/bin/node" ]; then export PATH="$dir/bin:$PATH"; return 0; fi
  local os arch base tmp linea sum file calc
  case "$(uname -s)" in Darwin) os=darwin;; Linux) os=linux;; *) fallo "Sistema no soportado por el instalador automático. Instala Node.js desde https://nodejs.org y repite.";; esac
  case "$(uname -m)" in arm64|aarch64) arch=arm64;; x86_64) arch=x64;; *) fallo "Arquitectura no soportada. Instala Node.js desde https://nodejs.org y repite.";; esac
  base="${NODE_DIST_BASE:-https://nodejs.org/dist/latest-v24.x}"
  info "No encontré Node.js. Descargando la versión oficial de nodejs.org (solo para este proyecto)…"
  tmp="$(mktemp -d)"
  curl -fsSL "$base/SHASUMS256.txt" -o "$tmp/SHASUMS256.txt" || fallo "No pude descargar la lista oficial de Node.js. Revisa tu conexión o instala Node.js desde https://nodejs.org y repite."
  linea="$(grep -E " node-v[0-9.]+-${os}-${arch}\.tar\.gz\$" "$tmp/SHASUMS256.txt" | head -1)"
  [ -n "$linea" ] || fallo "No encontré la versión de Node.js para tu equipo (${os}-${arch}). Instálalo desde https://nodejs.org y repite."
  sum="${linea%% *}"; file="${linea##* }"
  curl -fsSL "$base/$file" -o "$tmp/$file" || fallo "No pude descargar Node.js."
  if command -v shasum >/dev/null 2>&1; then calc="$(shasum -a 256 "$tmp/$file" | cut -d' ' -f1)"; else calc="$(sha256sum "$tmp/$file" | cut -d' ' -f1)"; fi
  [ "$calc" = "$sum" ] || fallo "La verificación de integridad de Node.js falló. No se instaló nada."
  mkdir -p "$dir"; tar -xzf "$tmp/$file" -C "$dir" --strip-components=1 || fallo "No pude descomprimir Node.js."
  rm -rf "$tmp"
  export PATH="$dir/bin:$PATH"
  ok "Node.js $(node -v) listo."
}

verificar_requisitos() {
  command -v python3 >/dev/null 2>&1 || fallo "Falta python3. En Terminal ejecuta: xcode-select --install"
  command -v curl    >/dev/null 2>&1 || fallo "Falta curl."
  if ! command -v supabase >/dev/null 2>&1; then asegurar_node; fi
  command -v supabase >/dev/null 2>&1 || command -v npx >/dev/null 2>&1 || fallo "No pude preparar la herramienta de Supabase."
}

# Define REF (referencia del proyecto: 20 letras minúsculas)
pedir_ref() {
  if [ -f "$ARCH_REF" ]; then REF="$(cat "$ARCH_REF")"; fi
  if [ -z "${REF:-}" ]; then
    echo
    echo "  La referencia del proyecto está en Supabase → Project Settings → General → \"Reference ID\""
    echo "  (también es la parte inicial de tu URL: https://REFERENCIA.supabase.co)"
    read -r -p "  Referencia del proyecto: " REF
  fi
  REF="$(printf '%s' "$REF" | tr -d '[:space:]')"
  printf '%s' "$REF" | grep -Eq '^[a-z]{20}$' || fallo "La referencia debe tener exactamente 20 letras minúsculas."
  printf '%s' "$REF" > "$ARCH_REF"
}

# Define URL, ANON, SERVICE leyendo las claves del proyecto (nunca se imprimen ni se guardan,
# salvo la clave pública ANON que va en app/config.js).
cargar_claves() {
  local txt
  txt="$(SB projects api-keys --project-ref "$REF" --reveal -o json 2>/dev/null)" || fallo "No pude leer las claves del proyecto. ¿Hiciste 'supabase login' y la referencia es correcta?"
  local salida
  salida="$(printf '%s' "$txt" | python3 -c '
import sys, json
raw = sys.stdin.read()
i = min([p for p in (raw.find("["), raw.find("{")) if p >= 0] or [0])
data = json.loads(raw[i:])
if isinstance(data, dict):
    for k in ("api_keys", "keys", "data"):
        if isinstance(data.get(k), list): data = data[k]; break
anon = pub = svc = sec = ""
for it in data:
    name = str(it.get("name") or it.get("id") or "").lower()
    typ  = str(it.get("type") or "").lower()
    key  = it.get("api_key") or it.get("key") or ""
    if name == "anon": anon = key
    elif "publishable" in name or typ == "publishable": pub = pub or key
    elif name == "service_role": svc = key
    elif typ == "secret" or name.startswith("secret") or name == "default": sec = sec or key
print(anon or pub); print(svc or sec)
')" || fallo "No pude interpretar las claves."
  ANON="$(printf '%s\n' "$salida" | sed -n 1p)"
  SERVICE="$(printf '%s\n' "$salida" | sed -n 2p)"
  URL="${NEXO_URL:-https://${REF}.supabase.co}"
  [ -n "$ANON" ] || fallo "No encontré la clave pública (anon/publishable) del proyecto."
}

# Encabezados HTTP para la API con la clave de servicio (JWT legado o clave secreta nueva)
curl_servicio() {
  local metodo="$1"; shift
  local ruta="$1"; shift
  if [ "${SERVICE#eyJ}" != "$SERVICE" ]; then
    curl -sS -X "$metodo" "$URL$ruta" -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" -H "Content-Type: application/json" "$@"
  else
    curl -sS -X "$metodo" "$URL$ruta" -H "apikey: $SERVICE" -H "Content-Type: application/json" "$@"
  fi
}
