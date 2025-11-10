#!/bin/bash
URL="https://bcv.org.ve" 

ARCHIVO_SALIDA="/data.json"

LINEA_DOLAR=7 
LINEA_EURO=3  

readarray -t RATES < <(
    curl -ksL "$URL" | \
    grep '<strong>.*</strong>' | \
    sed 's/.*<strong>//; s/<\/strong>.*//' | \
    sed 's/,/./g' | \
    awk 'NR=='"$LINEA_EURO"' || NR=='"$LINEA_DOLAR"''
)

if [ ${#RATES[@]} -lt 2 ]; then
    echo "Error $(date -u) - La extracción de valores falló o no se encontraron 2 líneas." >> /var/log/cron_error.log
    exit 1
fi

EURO="$(echo "${RATES[0]}" | xargs)"
DOLAR="$(echo "${RATES[1]}" | xargs)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")


cat <<EOF > "$ARCHIVO_SALIDA"
{
  "status": "success",
  "timestamp": "$TIMESTAMP",
  "base_currency": "USD/EUR",
  "target_currency": "BS / VES",
  "rates": {
    "USD": "$DOLAR",
    "EUR": "$EURO"
  }
}
EOF

exit 0
