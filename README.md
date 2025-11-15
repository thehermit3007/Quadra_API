# Quadra API - Tasas de Cambio Multi-Fuente

API gratuita que proporciona tasas de cambio actualizadas del BCV (Bolívar Venezolano) y Binance P2P en formato JSON.

## Características

- **Tasas del BCV**: USD y EUR oficiales del Banco Central de Venezuela
- **Tasa Binance P2P**: Promedio de las 3 mejores tasas de compra de USDT
- **Actualización automática**: Datos frescos cada 4 horas
- **Formato JSON**: Fácil de consumir desde cualquier aplicación
- **Totalmente gratuito**: Sin límites de uso para proyectos personales

## Endpoint

```
GET https://thehermit007.github.io/Quadra_API/data.json
```

## Estructura de la Respuesta

```json
{
  "status": "success",
  "timestamp": "2024-01-15T04:00:00Z",
  "base_currency": "USD/EUR/USDT",
  "target_currency": "BS / VES",
  "rates": {
    "USD": "35.5000",
    "EUR": "38.2000",
    "USDT": "36.8000"
  },
  "cache_info": {
    "bcv_source": "live"
  }
}
```

## Fuentes de Datos

| Moneda | Fuente | Frecuencia | Descripción |
|--------|--------|-------------|-------------|
| USD | BCV | 2 veces/día | Tasa oficial del Banco Central de Venezuela |
| EUR | BCV | 2 veces/día | Tasa oficial del Euro del BCV |
| USDT | Binance P2P | 6 veces/día | Promedio de las 3 mejores tasas de compra |

## Frecuencia de Actualización

### Binance P2P (USDT)
- **Horarios**: 04:00, 08:00, 12:00, 16:00, 20:00, 00:00 UTC
- **Método**: Promedio de las 3 mejores ofertas de compra (BUY)
- **Actualización**: Cada 4 horas

### BCV (USD/EUR)
- **Horarios**: 04:00 y 12:00 UTC
- **Método**: Web scraping directo del sitio oficial
- **Actualización**: 2 veces al día (con cache inteligente)

## Ejemplos de Uso

### JavaScript
```javascript
async function getExchangeRates() {
  try {
    const response = await fetch('https://thehermit007.github.io/Quadra_API/data.json');
    const data = await response.json();
    
    if (data.status === 'success') {
      console.log('USD:', data.rates.USD);
      console.log('EUR:', data.rates.EUR);
      console.log('USDT:', data.rates.USDT);
      console.log('Actualizado:', data.timestamp);
    }
  } catch (error) {
    console.error('Error obteniendo tasas:', error);
  }
}
```

### Python
```python
import requests

def get_rates():
    url = "https://thehermit007.github.io/Quadra_API/data.json"
    response = requests.get(url)
    data = response.json()
    
    if data['status'] == 'success':
        return {
            'usd': float(data['rates']['USD']),
            'eur': float(data['rates']['EUR']),
            'usdt': float(data['rates']['USDT']),
            'timestamp': data['timestamp']
        }
```

### cURL
```bash
curl -s "https://thehermit007.github.io/Quadra_API/data.json" | jq .
```

## Instalación y Desarrollo

### Requisitos
- Bash
- curl
- jq
- Git

### Ejecución Local
```bash
# Clonar repositorio
git clone https://github.com/thehermit007/Quadra_API.git
cd Quadra_API

# Ejecutar script manualmente
chmod +x QuadraAPI.sh
./QuadraAPI.sh
```

## Configuración

El proyecto usa GitHub Actions para actualizaciones automáticas:

```yaml
# .github/workflows/update-rates.yml
schedule:
  - cron: '0 4,8,12,16,20,0 * * *'  # Binance cada 4 horas
  - cron: '0 4,12 * * *'             # BCV 2 veces al día
```

## Método de Cálculo Binance

La tasa USDT se calcula como:

```
USDT = (precio1 + precio2 + precio3) / 3
```

Donde:
- `precio1`, `precio2`, `precio3` = Las 3 mejores ofertas de **compra** de USDT/VES
- Fuente: API oficial de Binance P2P
- Parámetros: `asset=USDT`, `tradeType=BUY`, `fiat=VES`

## Limitaciones y Consideraciones

- **Cache**: GitHub Pages puede cachear respuestas hasta 10 minutos
- **Rate Limiting**: Máximo ~100 requests/hora por IP
- **Disponibilidad**: Servicio "best-effort" sin garantías
- **Precisión**: Tasas BCV dependen de la actualización oficial

## Solución de Problemas

### Error de parsing
```javascript
// Siempre verificar el status
if (data.status === 'success') {
  // Usar datos
} else {
  // Manejar error
}
```

### Datos desactualizados
```javascript
// Verificar timestamp
const lastUpdate = new Date(data.timestamp);
const now = new Date();
const diffHours = (now - lastUpdate) / (1000 * 60 * 60);

if (diffHours > 4) {
  console.log('Los datos pueden estar desactualizados');
}
```

## Licencia

Este proyecto es de código abierto y está disponible bajo la licencia MIT.

---
