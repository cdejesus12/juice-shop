#!/usr/bin/env bash
# chaos_test.sh - Simula una caida de un contenedor Docker con Pumba,
# mide el downtime (MTTR) y opcionalmente lo reinicia si no tiene
# politica de --restart=always.
#
# Uso:
#   ./chaos_test.sh <contenedor> <puerto> [--auto-restart]
#
# Ejemplos:
#   ./chaos_test.sh test1 8091
#   ./chaos_test.sh juice-shop 3000 --auto-restart

set -uo pipefail

CONTAINER="${1:-}"
PORT="${2:-}"
AUTO_RESTART="${3:-}"

if [[ -z "$CONTAINER" || -z "$PORT" ]]; then
  echo "Uso: $0 <contenedor> <puerto> [--auto-restart]"
  exit 1
fi

URL="http://localhost:${PORT}"
LOGFILE="chaos_results.csv"

if [[ ! -f "$LOGFILE" ]]; then
  echo "timestamp,container,downtime_seconds,recovery_method" > "$LOGFILE"
fi

echo "=================================================="
echo " Chaos Test - $(date '+%Y-%m-%d %H:%M:%S')"
echo " Contenedor objetivo : $CONTAINER"
echo " URL monitoreada     : $URL"
echo "=================================================="

STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$URL" || echo "000")
if [[ "$STATUS" != "200" ]]; then
  echo "[ABORTADO] El servicio no responde 200 antes de empezar (status=$STATUS)."
  exit 1
fi
echo "[OK] Servicio sano antes del experimento (HTTP $STATUS)"

echo "[ATAQUE] Matando contenedor '$CONTAINER' con pumba..."
START_MS=$(date +%s%3N)
pumba kill "$CONTAINER" >/dev/null 2>&1

echo "[MEDICION] Esperando recuperacion..."
RECOVERY_METHOD="timeout - no recuperado"
MAX_WAIT_MS=120000
WAIT_BEFORE_RESTART_MS=5000
RESTARTED=false

while true; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 "$URL" || echo "000")
  NOW_MS=$(date +%s%3N)
  ELAPSED_MS=$((NOW_MS - START_MS))

  if [[ "$STATUS" == "200" ]]; then
    if [[ "$RESTARTED" == "true" ]]; then
      RECOVERY_METHOD="manual (docker start)"
    else
      RECOVERY_METHOD="automatica (restart policy)"
    fi
    break
  fi

  if [[ "$AUTO_RESTART" == "--auto-restart" && "$RESTARTED" == "false" && $ELAPSED_MS -ge $WAIT_BEFORE_RESTART_MS ]]; then
    echo "[RECUPERACION] Reiniciando contenedor manualmente tras $((WAIT_BEFORE_RESTART_MS/1000))s caido..."
    docker start "$CONTAINER" >/dev/null 2>&1
    RESTARTED=true
  fi

  if [[ $ELAPSED_MS -ge $MAX_WAIT_MS ]]; then
    echo "[TIMEOUT] No se recupero en $((MAX_WAIT_MS/1000))s. Abortando medicion."
    break
  fi

  sleep 0.5
done

END_MS=$(date +%s%3N)
DOWNTIME_MS=$((END_MS - START_MS))
DOWNTIME_S=$(awk "BEGIN{printf \"%.2f\", $DOWNTIME_MS/1000}")

echo "=================================================="
echo " Downtime total       : ${DOWNTIME_S}s"
echo " Metodo de recuperacion: $RECOVERY_METHOD"
echo "=================================================="

echo "$(date '+%Y-%m-%d %H:%M:%S'),$CONTAINER,$DOWNTIME_S,$RECOVERY_METHOD" >> "$LOGFILE"
echo "Resultado agregado a $LOGFILE"
