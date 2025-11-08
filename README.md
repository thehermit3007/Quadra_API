# QuadraAPI
## Solucion para Consulta del Dólar en Venezuela

Los venezolanos enfrentan diariamente la dificultad de conocer el precio actualizado del dólar para calcular precios de productos y servicios. Las fuentes oficiales no siempre están accesibles o actualizadas, generando frustración en las transacciones cotidianas.

Este proyeco se implementó como un scrapper automático que provee el valor del dólar actualizado tres veces al día (8:00 AM, 12:00 PM y 4:00 PM, hora Venezuela) mediante un archivo JSON público y accesible.

## Cómo Funciona

**Backend Automático:**
- Un script se ejecuta automáticamente en los horarios establecidos
- Consulta fuentes confiables del valor del dólar
- Guarda los datos en un archivo JSON actualizado
- Todo funciona sin intervención humana

**Acceso para Desarrolladores:**
- El archivo JSON está disponible públicamente en GitHub Pages
- Las aplicaciones y PWAs pueden consultarlo directamente
- Formato simple y estándar para fácil integración

## Beneficios para la Comunidad

**Para Usuarios Finales:**
- Acceso rápido al valor actual del dólar
- Información actualizada en horarios clave del día
- Sin necesidad de buscar en múltiples fuentes

**Para Desarrolladores:**
- API gratuita y sin límites de uso
- Fácil integración en cualquier aplicación
- No requiere servidores propios ni mantenimiento

## Características Técnicas
- Actualización automática tres veces al día
- Formato JSON estándar
- Accesible desde cualquier aplicación web o móvil
- Funciona incluso si la fuente principal falla (usa valores de respaldo)

Esta solución busca reducir la fricción diaria que enfrentan los venezolanos al necesitar información confiable y actualizada sobre el tipo de cambio para sus actividades económicas cotidianas.

## Licencia

Este proyecto está bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para detalles.
