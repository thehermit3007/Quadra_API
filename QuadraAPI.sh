#!/bin/bash

# Configuración
readonly BCV_URL="https://bcv.org.ve"
readonly ARCHIVO_SALIDA="data.json"
readonly CACHE_BCV="bcv_cache.json"
readonly LINEA_DOLAR_BCV=7
readonly LINEA_EURO_BCV=3

debe_actualizar_bcv() {
    local hora_actual=$(date -u +%H)
    [[ $hora_actual == "04" || $hora_actual == "12" ]]
}

obtener_tasas_bcv() {
    local -n rates_ref=$1
    local contenido=$(curl -s --retry 3 --connect-timeout 10 "$BCV_URL")
    local tasa_dolar=$(echo "$contenido" | grep -A $LINEA_DOLAR_BCV 'Dólar' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    local tasa_euro=$(echo "$contenido" | grep -A $LINEA_EURO_BCV 'Euro' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    
    rates_ref=("$tasa_dolar" "$tasa_euro")
    
    # Guardar en cache SOLO si se obtuvieron tasas válidas
    if [ -n "$tasa_dolar" ] && [ -n "$tasa_euro" ] && [ "$tasa_dolar" != "0" ] && [ "$tasa_euro" != "0" ]; then
        echo "{\"dolar\":\"$tasa_dolar\",\"euro\":\"$tasa_euro\",\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > $CACHE_BCV
        return 0
    fi
    return 1
}

cargar_tasas_bcv_cache() {
    local -n rates_ref=$1
    if [[ -f $CACHE_BCV ]]; then
        local dolar=$(jq -r '.dolar' $CACHE_BCV 2>/dev/null || echo "")
        local euro=$(jq -r '.euro' $CACHE_BCV 2>/dev/null || echo "")
        rates_ref=("$dolar" "$euro")
        # Verificar que los valores del cache sean válidos
        if [ -n "$dolar" ] && [ -n "$euro" ] && [ "$dolar" != "0" ] && [ "$euro" != "0" ]; then
            return 0
        fi
    fi
    return 1
}

obtener_tasa_binance() {
    local tasa=$(curl -s -X POST "https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search" \
        -H "Content-Type: application/json" \
        -H "Accept-Encoding: gzip" \
        -d '{"page":1,"rows":3,"asset":"USDT","tradeType":"BUY","fiat":"VES"}' | \
        gunzip | jq '.' | grep price | \
        awk 'NR==3 || NR==7 || NR==11 {split($0, a, "\""); sum += a[4]; count++} END {if(count>0) print sum/count; else print "0"}')
    
    # Validar que la tasa no esté vacía
    echo "${tasa:-0}"
}

cargar_json_existente() {
    local -n dolar_ref=$1 euro_ref=$2 usdt_ref=$3 timestamp_ref=$4 bcv_source_ref=$5
    
    if [[ -f $ARCHIVO_SALIDA ]]; then
        dolar_ref=$(jq -r '.rates.USD' $ARCHIVO_SALIDA 2>/dev/null || echo "0")
        euro_ref=$(jq -r '.rates.EUR' $ARCHIVO_SALIDA 2>/dev/null || echo "0")
        usdt_ref=$(jq -r '.rates.USDT' $ARCHIVO_SALIDA 2>/dev/null || echo "0")
        timestamp_ref=$(jq -r '.timestamp' $ARCHIVO_SALIDA 2>/dev/null || echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
        bcv_source_ref=$(jq -r '.cache_info.bcv_source' $ARCHIVO_SALIDA 2>/dev/null || echo "unknown")
        return 0
    fi
    return 1
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
    
    # Cargar valores existentes del JSON (si existe)
    if ! cargar_json_existente dolar euro usdt timestamp bcv_source; then
        # Si no existe el archivo, inicializar con valores por defecto
        dolar="0"
        euro="0"
        usdt="0"
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        bcv_source="unknown"
    fi
    
    # Obtener tasa Binance (SIEMPRE se actualiza)
    usdt=$(obtener_tasa_binance)
    
    # Manejar tasas BCV (solo se actualizan en horarios específicos)
    rates_bcv=("" "")
    if debe_actualizar_bcv; then
        # En horarios BCV: intentar actualizar
        echo "Actualizando tasas BCV (horario programado)..."
        if obtener_tasas_bcv rates_bcv; then
            dolar="${rates_bcv[0]}"
            euro="${rates_bcv[1]}"
            bcv_source="live"
            echo "Tasas BCV actualizadas: USD=$dolar, EUR=$euro"
        else
            # Si falla la obtención en vivo, intentar cargar del cache
            if cargar_tasas_bcv_cache rates_bcv; then
                dolar="${rates_bcv[0]}"
                euro="${rates_bcv[1]}"
                bcv_source="cache_fallback"
                echo "Usando cache BCV (fallback): USD=$dolar, EUR=$euro"
            else
                bcv_source="live_failed"
                echo "No se pudieron obtener tasas BCV, manteniendo valores anteriores"
            fi
        fi
    else
        # Fuera de horarios BCV: mantener valores existentes
        # Solo usar cache si no tenemos valores válidos
        if [[ "$dolar" == "0" || "$euro" == "0" ]]; then
            if cargar_tasas_bcv_cache rates_bcv; then
                dolar="${rates_bcv[0]}"
                euro="${rates_bcv[1]}"
                bcv_source="cache_initial"
                echo "Inicializando con cache BCV: USD=$dolar, EUR=$euro"
            else
                bcv_source="no_cache"
                echo "Fuera de horario BCV, manteniendo valores actuales: USD=$dolar, EUR=$euro"
            fi
        else
            bcv_source="existing_data"
            echo "Fuera de horario BCV, manteniendo valores existentes: USD=$dolar, EUR=$euro"
        fi
    fi
    
    # Actualizar timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Crear JSON de salida
    crear_json_salida "$dolar" "$euro" "$usdt" "$timestamp" "$bcv_source"
    
    echo "Actualización completada:"
    echo "USD: $dolar, EUR: $euro, USDT: $usdt"
    echo "Fuente: $bcv_source"
}

main "$@"
