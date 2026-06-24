# Entregable 4 - Kavak Seguros Churn Temprano

Prototipo funcional para operacionalizar el modelo de churn temprano de Kavak Seguros.

## Que incluye

- API local ejecutable en PowerShell.
- Dashboard HTML que consume la API.
- Version web estatica para GitHub Pages, con datos demo anonimos.
- Ranking de polizas activas ordenadas por score de churn.
- Solapa de insights con graficos de riesgo por aseguradora, metodo de pago, region y drivers.
- Prediccion individual para simular una poliza nueva.

## Link web inmediato

El dashboard se puede abrir directo desde el repo con este link:

https://raw.githack.com/lisomedici/entregable_4/545c5255d6272574df218a11976211c701cd4c6a/dashboard/index.html

La version web funciona sin instalar nada. Usa datos demo anonimos para no publicar informacion personal de clientes.

Si se habilita GitHub Pages en Settings, tambien puede publicarse como:

https://lisomedici.github.io/entregable_4/

## Como correrlo

Desde esta carpeta:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_dashboard.ps1
```

Luego abrir:

- Dashboard: http://localhost:8787/
- Healthcheck API: http://localhost:8787/api/health

Si el CSV esta en otra ruta:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_dashboard.ps1 -CsvPath "C:\ruta\archivo.csv"
```

## Endpoints principales

- `GET /api/summary`: metricas generales del prototipo.
- `GET /api/policies?limit=80&reveal=0`: polizas activas priorizadas.
- `POST /api/predict`: prediccion individual.
- `POST /api/batch`: prediccion por lote enviando un array JSON.
- `GET /api/schema`: entradas esperadas y salidas.

## Como leer el dashboard

- **Filtros de priorizacion**: sirven para decidir que parte del ranking mirar. No recalculan el modelo.
- **Nivel de riesgo**: filtra las polizas por score: Alto `> 0,40`, Medio `0,20 a 0,40`, Bajo `< 0,20`.
- **Maximo a mostrar**: limita cuantas filas se ven en la tabla despues de aplicar busqueda y filtro. Por ejemplo, si hay 1.118 polizas de riesgo medio y el maximo es 80, muestra las 80 de mayor score dentro de Medio.
- **Buscar poliza, patente o cliente**: busca dentro de la lista evaluada.
- **Insights**: resume donde se concentra el alto riesgo y sugiere focos de accion para campanas de retencion.
- **Simulador de poliza nueva**: es opcional. Sirve para demostrar que el sistema tambien puede recibir datos de una poliza que todavia no esta en cartera/ranking y devolver un score. Para el trabajo diario de retencion, la vista principal es la lista de polizas a contactar.

## Nota metodologica

El Entregable 3 selecciono XGBoost como modelo ganador, con Precision@Top20% de 49,1% y ROC-AUC de 0,731 en validacion out-of-time.

Como en esta computadora no esta disponible Python ni el `.joblib` entrenado, el prototipo usa un scorecard local reproducible con las mismas variables seguras definidas en los notebooks: aseguradora, cluster, metodo de pago, region, genero, rango de comision, edad, antiguedad del vehiculo, cuota, comision, renovacion y GNC.

La arquitectura deja el scoring encapsulado en `api/server.ps1`. En una version productiva, esa funcion se reemplaza por la carga del modelo persistido (`mejor_modelo_churn.joblib`) y los encoders generados desde Colab, manteniendo iguales los endpoints y el dashboard.

Para que la demo abra rapido en una computadora sin Python, el ranking inicial scorea una muestra operativa de hasta 1.200 polizas activas del CSV. El endpoint y la interfaz quedan listos para ampliar ese limite si se ejecuta en un entorno mas comodo.

En GitHub Pages no se ejecuta la API PowerShell. Por eso `dashboard/app.js` intenta consumir `/api/*` y, si no existe, cambia automaticamente a modo demo web con `dashboard/demo-data.js`.

## Guion de demo sugerido

1. Problema: detectar churn temprano para contactar antes de la baja.
2. Recordatorio del modelo: XGBoost gano y supera KPI de Precision@Top20%.
3. Mostrar la API local en ejecucion.
4. Abrir el dashboard y explicar la lista priorizada.
5. Filtrar por alto riesgo y mostrar drivers.
6. Ejecutar una prediccion individual.
7. Cerrar con proximos pasos: persistir `.joblib`, registrar contactos y reentrenar trimestralmente.



