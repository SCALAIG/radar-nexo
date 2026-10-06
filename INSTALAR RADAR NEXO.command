#!/bin/bash
# Doble clic para ejecutar el instalador de Radar NEXO en la Terminal.
cd "$(dirname "$0")" || exit 1
chmod +x scripts/*.sh 2>/dev/null
./scripts/instalar.sh
echo
read -n 1 -s -r -p "Presiona cualquier tecla para cerrar esta ventana…"
echo
