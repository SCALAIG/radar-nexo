#!/usr/bin/env bash
# Descarga una copia completa de empresas, historial y usuarios a ./respaldos/AAAA-MM-DD_HHMM/
# Úsalo al final de cada jornada. (El plan Pro también hace respaldos diarios automáticos.)
set -euo pipefail
. "$(dirname "$0")/_comun.sh"
verificar_requisitos
pedir_ref
cargar_claves
[ -n "$SERVICE" ] || fallo "No pude leer la clave de servicio del proyecto."

DEST="$RAIZ/respaldos/$(date +%Y-%m-%d_%H%M)"
mkdir -p "$DEST"; chmod 700 "$RAIZ/respaldos" "$DEST"
for T in empresas empresas_historial perfiles uso_ia; do
  curl_servicio GET "/rest/v1/$T?select=*" > "$DEST/$T.json"
  N="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d) if isinstance(d,list) else "ERROR")' "$DEST/$T.json")"
  [ "$N" = "ERROR" ] && fallo "No se pudo respaldar $T: $(head -c 200 "$DEST/$T.json")"
  ok "$T: $N registros"
done
chmod 600 "$DEST"/*.json
echo; echo "  Copia guardada en: $DEST"
echo "  (Esta carpeta contiene datos personales: no la subas a GitHub; ya está excluida por .gitignore.)"
