#!/bin/bash

# Configuración
readonly BCV_URL="https://bcv.org.ve"
readonly ARCHIVO_SALIDA="data.json"
readonly CACHE_BCV="bcv_cache.json"
readonly LINEA_DOLAR_BCV=7
readonly LINEA_EURO_BCV=3

# Variables globales para controlar qué actualizar
ACTUALIZAR_BCV=false
ACTUALIZAR_BINANCE=false

debe_actualizar_bcv() {
    local hora_actual=$(date -u +%H)
    
    # Horarios específicos para BCV (4AM y 12PM Venezuela = 8AM y 4PM UTC)
    if [[ $hora_actual == "08" || $hora_actual == "16" ]]; then
        echo "✓ Horario BCV detectado (UTC $hora_actual:00)"
        return 0
    fi
    
    # Verificar si la última consulta BCV es del día actual
    if [[ -f $CACHE_BCV ]]; then
        local ultima_actualizacion=$(jq -r '.timestamp' $CACHE_BCV 2>/dev/null)
        if [[ -n "$ultima_actualizacion" && "$ultima_actualizacion" != "null" ]]; then
            local fecha_cache=$(echo "$ultima_actualizacion" | cut -d'T' -f1)
            local fecha_actual=$(date -u +"%Y-%m-%d")
            
            if [[ "$fecha_cache" != "$fecha_actual" ]]; then
                echo "✓ Última consulta BCV es de día diferente ($fecha_cache vs $fecha_actual)"
                return 0
            else
                echo "✗ Última consulta BCV es del día actual ($fecha_actual)"
            fi
        else
            echo "✓ No hay timestamp válido en cache BCV"
            return 0
        fi
    else
        echo "✓ No existe cache BCV"
        return 0
    fi
    
    return 1
}

debe_actualizar_binance() {
    local hora_actual=$(date -u +%H)
    [[ $hora_actual == "04" || $hora_actual == "08" || $hora_actual == "12" || $hora_actual == "16" || $hora_actual == "20" || $hora_actual == "00" ]]
}

obtener_tasas_bcv() {
    local -n rates_ref=$1
    echo "Obteniendo tasas BCV desde $BCV_URL..."
    local contenido=$(curl -s --retry 3 --connect-timeout 10 "$BCV_URL")
    local tasa_dolar=$(echo "$contenido" | grep -A $LINEA_DOLAR_BCV 'Dólar' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    local tasa_euro=$(echo "$contenido" | grep -A $LINEA_EURO_BCV 'Euro' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    
    rates_ref=("$tasa_dolar" "$tasa_euro")
    
    # Guardar en cache SOLO si se obtuvieron tasas válidas
    if [ -n "$tasa_dolar" ] && [ -n "$tasa_euro" ] && [ "$tasa_dolar" != "0" ] && [ "$tasa_euro" != "0" ]; then
        echo "{\"dolar\":\"$tasa_dolar\",\"euro\":\"$tasa_euro\",\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > $CACHE_BCV
        echo "✓ Cache BCV actualizado: Dólar=$tasa_dolar, Euro=$tasa_euro"
        return 0
    else
        echo "✗ No se pudieron obtener tasas BCV válidas"
        return 1
    fi
}

cargar_tasas_bcv_cache() {
    local -n rates_ref=$1
    if [[ -f $CACHE_BCV ]]; then
        local dolar=$(jq -r '.dolar' $CACHE_BCV 2>/dev/null || echo "")
        local euro=$(jq -r '.euro' $CACHE_BCV 2>/dev/null || echo "")
        rates_ref=("$dolar" "$euro")
        # Verificar que los valores del cache sean válidos
        if [ -n "$dolar" ] && [ -n "$euro" ] && [ "$dolar" != "0" ] && [ "$euro" != "0" ]; then
            echo "✓ Cache BCV cargado: Dólar=$dolar, Euro=$euro"
            return 0
        fi
    fi
    echo "✗ No hay cache BCV disponible o es inválido"
    return 1
}

# FUNCIÓN BINANCE ORIGINAL (SIN MODIFICACIONES)
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
    local -n json_ref=$1
    
    if [[ -f $ARCHIVO_SALIDA ]]; then
        json_ref=$(cat $ARCHIVO_SALIDA)
        echo "✓ JSON existente cargado"
        return 0
    else
        # Crear JSON inicial si no existe
        json_ref='{
  "status": "success",
  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
  "base_currency": "USD/EUR/USDT",
  "target_currency": "BS / VES",
  "rates": {
    "USD": "0",
    "EUR": "0",
    "USDT": "0"
  },
  "cache_info": {
    "bcv_source": "initial"
  }
}'
        echo "$json_ref" > $ARCHIVO_SALIDA
        echo "✓ JSON inicial creado"
        return 1
    fi
}

actualizar_campo_json() {
    local campo="$1"
    local valor="$2"
    local temp_file=$(mktemp)
    
    jq --arg campo "$campo" --arg valor "$valor" '.rates[$campo] = $valor' $ARCHIVO_SALIDA > "$temp_file" && mv "$temp_file" $ARCHIVO_SALIDA
}

actualizar_timestamp() {
    local temp_file=$(mktemp)
    jq --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '.timestamp = $timestamp' $ARCHIVO_SALIDA > "$temp_file" && mv "$temp_file" $ARCHIVO_SALIDA
}

actualizar_fuente_bcv() {
    local fuente="$1"
    local temp_file=$(mktemp)
    jq --arg fuente "$fuente" '.cache_info.bcv_source = $fuente' $ARCHIVO_SALIDA > "$temp_file" && mv "$temp_file" $ARCHIVO_SALIDA
}

procesar_bcv() {
    echo "--- PROCESANDO BCV ---"
    local rates_bcv=("" "")
    local fuente_bcv="existing_data"
    
    if obtener_tasas_bcv rates_bcv; then
        actualizar_campo_json "USD" "${rates_bcv[0]}"
        actualizar_campo_json "EUR" "${rates_bcv[1]}"
        fuente_bcv="live"
        echo "✓ BCV actualizado desde fuente en vivo"
    elif cargar_tasas_bcv_cache rates_bcv; then
        actualizar_campo_json "USD" "${rates_bcv[0]}"
        actualizar_campo_json "EUR" "${rates_bcv[1]}"
        fuente_bcv="cache_fallback"
        echo "✓ BCV actualizado desde cache"
    else
        fuente_bcv="failed"
        echo "✗ No se pudo actualizar BCV"
    fi
    
    actualizar_fuente_bcv "$fuente_bcv"
}

procesar_binance() {
    echo "--- PROCESANDO BINANCE ---"
    local tasa_binance=$(obtener_tasa_binance)
    
    if [[ "$tasa_binance" != "0" ]]; then
        actualizar_campo_json "USDT" "$tasa_binance"
        echo "✓ Binance actualizado: $tasa_binance"
    else
        echo "✗ No se pudo actualizar Binance, manteniendo valor anterior"
    fi
}

main() {
    echo "=== INICIANDO ACTUALIZACIÓN DE TASAS ==="
    echo "Hora actual UTC: $(date -u +"%H:%M")"
    echo "Fecha actual UTC: $(date -u +"%Y-%m-%d")"
    
    # Mostrar información del cache BCV si existe
    if [[ -f $CACHE_BCV ]]; then
        local cache_timestamp=$(jq -r '.timestamp' $CACHE_BCV 2>/dev/null || echo "N/A")
        echo "Última actualización BCV cache: $cache_timestamp"
    fi
    
    # Determinar qué actualizar basado en la hora
    if debe_actualizar_bcv; then
        ACTUALIZAR_BCV=true
    else
        echo "--- BCV: Fuera de horario o ya actualizado hoy ---"
    fi
    
    if debe_actualizar_binance; then
        ACTUALIZAR_BINANCE=true
        echo "✓ Horario Binance detectado"
    else
        echo "--- BINANCE: Fuera de horario, no se actualiza ---"
    fi
    
    # Cargar JSON existente o crear uno nuevo
    local json_content
    cargar_json_existente json_content
    
    # Actualizar timestamp siempre
    actualizar_timestamp
    
    # Procesar actualizaciones según corresponda
    if [ "$ACTUALIZAR_BCV" = true ]; then
        procesar_bcv
    fi
    
    if [ "$ACTUALIZAR_BINANCE" = true ]; then
        procesar_binance
    fi
    
    echo "=== ACTUALIZACIÓN COMPLETADA ==="
    echo "Contenido final:"
    cat $ARCHIVO_SALIDA
}

main "$@"
