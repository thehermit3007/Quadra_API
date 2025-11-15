#!/bin/bash

readonly BCV_URL="https://bcv.org.ve"
readonly BINANCE_API_URL="https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search"
readonly ARCHIVO_SALIDA="data.json"
readonly CACHE_BCV="bcv_cache.json"
readonly LINEA_DOLAR_BCV=7
readonly LINEA_EURO_BCV=3
readonly BINANCE_REQUEST_DATA='{"page":1,"rows":3,"asset":"USDT","tradeType":"BUY","fiat":"VES"}'

debe_actualizar_bcv() {
    local hora_actual=$(date -u +%H)
    [[ "$hora_actual" == "04" ]] || [[ "$hora_actual" == "12" ]]
}

obtener_tasas_bcv() {
    local -n rates_ref=$1
    local bcv_data
    
    bcv_data=$(curl -ksL --max-time 10 "$BCV_URL" 2>/dev/null)
    [[ -z "$bcv_data" ]] && return 1
    
    readarray -t rates_ref < <(
        echo "$bcv_data" | \
        grep '<strong>.*</strong>' | \
        sed 's/.*<strong>//; s/<\/strong>.*//' | \
        sed 's/,/./g' | \
        awk "NR==$LINEA_EURO_BCV || NR==$LINEA_DOLAR_BCV"
    )
    
    [[ ${#rates_ref[@]} -lt 2 ]] && return 1
    
    cat <<EOF > "$CACHE_BCV"
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "rates": {
    "USD": "${rates_ref[1]}",
    "EUR": "${rates_ref[0]}"
  }
}
EOF
    
    return 0
}

cargar_tasas_bcv_cache() {
    local -n rates_ref=$1
    
    if [[ -f "$CACHE_BCV" ]]; then
        rates_ref[0]=$(jq -r '.rates.EUR' "$CACHE_BCV")
        rates_ref[1]=$(jq -r '.rates.USD' "$CACHE_BCV")
        return 0
    fi
    return 1
}

obtener_tasa_binance() {
    local binance_response
    
    binance_response=$(curl -s --max-time 15 --compressed \
        -X POST "$BINANCE_API_URL" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$BINANCE_REQUEST_DATA")
    
    [[ -z "$binance_response" ]] && echo "null" && return 1
    
    echo "$binance_response" | jq -r '
        [.data[0:3] | .[] | .adv.price | tonumber] | 
        if length > 0 then add / length else "null" end' 2>/dev/null || echo "null"
}

generar_json() {
    cat <<EOF
{
  "status": "success",
  "timestamp": "$1",
  "base_currency": "USD/EUR/USDT",
  "target_currency": "BS / VES",
  "rates": {
    "USD": "$2",
    "EUR": "$3",
    "USDT": "$4"
  },
  "cache_info": {
    "bcv_source": "$5"
  }
}
EOF
}

main() {
    local rates_bcv=() euro dolar usdt timestamp bcv_source
    
    if debe_actualizar_bcv; then
        if obtener_tasas_bcv rates_bcv; then
            bcv_source="live"
        else
            cargar_tasas_bcv_cache rates_bcv || exit 1
            bcv_source="cache"
        fi
    else
        cargar_tasas_bcv_cache rates_bcv || exit 1
        bcv_source="cache"
    fi
    
    euro=$(echo "${rates_bcv[0]}" | xargs)
    dolar=$(echo "${rates_bcv[1]}" | xargs)
    usdt=$(obtener_tasa_binance)
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    generar_json "$timestamp" "$dolar" "$euro" "$usdt" "$bcv_source" > "$ARCHIVO_SALIDA"
}

main "$@"
