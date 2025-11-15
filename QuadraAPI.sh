#!/bin/bash

# Configuración
readonly BCV_URL="https://bcv.org.ve"
readonly BINANCE_API_URL="https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search"
readonly ARCHIVO_SALIDA="data.json"
readonly CACHE_BCV="bcv_cache.json"
readonly LINEA_DOLAR_BCV=7
readonly LINEA_EURO_BCV=3
readonly BINANCE_REQUEST_DATA='{"page":1,"rows":3,"asset":"USDT","tradeType":"BUY","fiat":"VES"}'

debe_actualizar_bcv() {
    local hora_actual=$(date -u +%H)
    [[ $hora_actual == "04" || $hora_actual == "12" ]]
}

obtener_tasas_bcv() {
    local -n rates_ref=$1
    local contenido=$(curl -s --retry 3 "$BCV_URL")
    local tasa_dolar=$(echo "$contenido" | grep -A $LINEA_DOLAR_BCV 'Dólar' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    local tasa_euro=$(echo "$contenido" | grep -A $LINEA_EURO_BCV 'Euro' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    
    rates_ref=("$tasa_dolar" "$tasa_euro")
    
    # Guardar en cache
    echo "{\"dolar\":\"$tasa_dolar\",\"euro\":\"$tasa_euro\",\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > $CACHE_BCV
}

cargar_tasas_bcv_cache() {
    local -n rates_ref=$1
    if [[ -f $CACHE_BCV ]]; then
        local dolar=$(jq -r '.dolar' $CACHE_BCV)
        local euro=$(jq -r '.euro' $CACHE_BCV)
        rates_ref=("$dolar" "$euro")
        return 0
    fi
    return 1
}

obtener_tasa_binance() {
    local response=$(curl -s -X POST $BINANCE_API_URL \
        -H "Content-Type: application/json" \
        -d "$BINANCE_REQUEST_DATA")
    
    local precio1=$(echo "$response" | jq -r '.data[0].adv.price')
    local precio2=$(echo "$response" | jq -r '.data[1].adv.price')
    local precio3=$(echo "$response" | jq -r '.data[2].adv.price')
    
    # Calcular promedio
    local promedio=$(echo "scale=4; ($precio1 + $precio2 + $precio3) / 3" | bc)
    echo "$promedio"
}

crear_json_salida() {
    local dolar=$1 euro=$2 usdt=$3 timestamp=$4 bcv_source=$5
    
    cat > $ARCHIVO_SALIDA << EOF
{
  "status": "success",
  "timestamp": "$timestamp",
  "base_currency": "USD/EUR/USDT",
  "target_currency": "BS / VES",
  "rates": {
    "USD": "$dolar",
    "EUR": "$euro",
    "USDT": "$usdt"
  },
  "cache_info": {
    "bcv_source": "$bcv_source"
  }
}
EOF
}

main() {
    local rates_bcv euro dolar usdt timestamp bcv_source
    
    # Inicializar arrays
    rates_bcv=()
    
    # Obtener tasas BCV (desde cache o live)
    if debe_actualizar_bcv; then
        obtener_tasas_bcv rates_bcv
        bcv_source="live"
    else
        if ! cargar_tasas_bcv_cache rates_bcv; then
            # Si no hay cache, usar valores por defecto
            rates_bcv=("0" "0")
            bcv_source="default"
        else
            bcv_source="cache"
        fi
    fi
    
    # Obtener tasa Binance
    usdt=$(obtener_tasa_binance)
    
    # Asignar valores
    dolar="${rates_bcv[0]}"
    euro="${rates_bcv[1]}"
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Crear JSON de salida
    crear_json_salida "$dolar" "$euro" "$usdt" "$timestamp" "$bcv_source"
}

main "$@"
