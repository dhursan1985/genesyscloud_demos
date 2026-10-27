# SC_Consulta_Pedido — consulta de solo lectura

Crear manualmente en Admin > Scripts, activar Screen Pop y uso con email y publicar. No se entrega un fichero importable de Script: `script-inputs.json` es el contrato documental de entradas.

El Script **solo representa información**. No tiene cajas editables, formularios, botones Guardar/Actualizar/Gestionar, Data Actions, llamadas API ni escritura sobre la Data Table. Solo hay navegación entre páginas. Los scripts PowerShell de carga administrativa son una herramienta distinta y no se ejecutan desde el Script del agente.

## Datos y comportamiento

Se muestran las 37 columnas originales de TablaVerdadHermet10. Una fila por NumeroPedido por decisión del usuario: valores distintos separados por ` | `, especialmente Instancia y orden. No tomar esos valores como una única línea original; el detalle de 90 filas se conserva en el Excel y CSV original.

Todos los campos son **texto de lectura**. Conservar `NULL` literal y las fechas registradas; no inferir estado del pedido, nombres, email o teléfono del cliente, porque no están en el Excel. `senderEmail` representa al remitente de la interacción, no un email verificado del cliente de la tabla.

Si lookupFound=false, mostrar «Pedido no localizado / datos no disponibles», el número recibido y el motivo. Ocultar el resto de campos vacíos. Si lookupFound=true, mostrar los valores recibidos. El indicador de incidencia se activa si TipologiaIncidencia no está vacía ni es NULL; es informativo, no modifica el estado.

## Páginas

### 1. Pedido y cliente

Componentes de texto enlazados mediante el selector de variables del Script:

| Etiqueta y variable | Presentación |
|---|---|
| NumeroPedido | Texto de solo lectura |
| Referencia | Texto de solo lectura |
| PedidoCliente | Texto de solo lectura |
| PedidoProveedor | Texto de solo lectura |
| WorkOrder | Texto de solo lectura |
| Expediente | Texto de solo lectura |
| CodigoCliente | Texto de solo lectura |
| IDResponsable | Texto de solo lectura |
| Instancia | Texto de solo lectura |
| orden | Texto de solo lectura |

Botones: Anterior / Siguiente, únicamente navegación de página.

### 2. Fechas

Componentes de texto enlazados mediante el selector de variables del Script:

| Etiqueta y variable | Presentación |
|---|---|
| FechaSolicitud | Texto de solo lectura |
| FechaConfirmacion | Texto de solo lectura |
| FechaPrevistaEntrega | Texto de solo lectura |
| FechaEntrega | Texto de solo lectura |
| FechaPrevistaInstalacion | Texto de solo lectura |
| FechaInstalacion | Texto de solo lectura |
| FechaSalidaTaller | Texto de solo lectura |
| FechaUltimaInteraccion | Texto de solo lectura |
| FechaPrevistaPostventa | Texto de solo lectura |

Botones: Anterior / Siguiente, únicamente navegación de página.

### 3. Transporte

Componentes de texto enlazados mediante el selector de variables del Script:

| Etiqueta y variable | Presentación |
|---|---|
| TipoEnvio | Texto de solo lectura |
| Albaran | Texto de solo lectura |
| ShippingLotCode | Texto de solo lectura |
| ShippingLotDescription | Texto de solo lectura |
| RealDeliveryDate | Texto de solo lectura |
| RealShippingDate | Texto de solo lectura |
| ShippingAreaCode | Texto de solo lectura |
| ProductionLot | Texto de solo lectura |

Botones: Anterior / Siguiente, únicamente navegación de página.

### 4. Incidencias

Componentes de texto enlazados mediante el selector de variables del Script:

| Etiqueta y variable | Presentación |
|---|---|
| PendienteRespuesta | Texto de solo lectura |
| FechaAperturaIncidencia | Texto de solo lectura |
| ID_INCIDENCIA | Texto de solo lectura |
| FECHA_APERTURA_INC | Texto de solo lectura |
| FECHA_CIERRE_INC | Texto de solo lectura |
| TipologiaIncidencia | Texto de solo lectura |
| DescripcionIncidencia | Texto de solo lectura |
| TIEMPO_PREVISTO_RESOLUCION | Texto de solo lectura |
| TIEMPO_REAL_RESOLUCION | Texto de solo lectura |
| NivelAfectacionIncidencia | Texto de solo lectura |

Botones: Anterior / Siguiente, únicamente navegación de página.

## Entradas y mapeo de Architect

Crear **43 inputs**: 37 campos Excel String y 6 metadatos. Todos Input=true, Output=false. No usar el prefijo Flow en el nombre del input del Script; Flow.* solo identifica el valor que envía Architect en Set Screen Pop.

| Input | Tipo | Valor Architect |
|---|---|---|
| NumeroPedido | String | Flow.NumeroPedido |
| Referencia | String | Flow.Referencia |
| PedidoCliente | String | Flow.PedidoCliente |
| PedidoProveedor | String | Flow.PedidoProveedor |
| WorkOrder | String | Flow.WorkOrder |
| Expediente | String | Flow.Expediente |
| CodigoCliente | String | Flow.CodigoCliente |
| IDResponsable | String | Flow.IDResponsable |
| FechaSolicitud | String | Flow.FechaSolicitud |
| FechaConfirmacion | String | Flow.FechaConfirmacion |
| FechaPrevistaEntrega | String | Flow.FechaPrevistaEntrega |
| FechaEntrega | String | Flow.FechaEntrega |
| FechaPrevistaInstalacion | String | Flow.FechaPrevistaInstalacion |
| FechaInstalacion | String | Flow.FechaInstalacion |
| FechaSalidaTaller | String | Flow.FechaSalidaTaller |
| TipoEnvio | String | Flow.TipoEnvio |
| PendienteRespuesta | String | Flow.PendienteRespuesta |
| FechaUltimaInteraccion | String | Flow.FechaUltimaInteraccion |
| FechaPrevistaPostventa | String | Flow.FechaPrevistaPostventa |
| FechaAperturaIncidencia | String | Flow.FechaAperturaIncidencia |
| Albaran | String | Flow.Albaran |
| ShippingLotCode | String | Flow.ShippingLotCode |
| ShippingLotDescription | String | Flow.ShippingLotDescription |
| RealDeliveryDate | String | Flow.RealDeliveryDate |
| RealShippingDate | String | Flow.RealShippingDate |
| ShippingAreaCode | String | Flow.ShippingAreaCode |
| ProductionLot | String | Flow.ProductionLot |
| Instancia | String | Flow.Instancia |
| orden | String | Flow.orden |
| ID_INCIDENCIA | String | Flow.ID_INCIDENCIA |
| FECHA_APERTURA_INC | String | Flow.FECHA_APERTURA_INC |
| FECHA_CIERRE_INC | String | Flow.FECHA_CIERRE_INC |
| TipologiaIncidencia | String | Flow.TipologiaIncidencia |
| DescripcionIncidencia | String | Flow.DescripcionIncidencia |
| TIEMPO_PREVISTO_RESOLUCION | String | Flow.TIEMPO_PREVISTO_RESOLUCION |
| TIEMPO_REAL_RESOLUCION | String | Flow.TIEMPO_REAL_RESOLUCION |
| NivelAfectacionIncidencia | String | Flow.NivelAfectacionIncidencia |
| orderNumber | String | Flow.orderNumber |
| lookupFound | Boolean | Flow.lookupFound |
| senderEmail | String | Flow.senderEmail |
| contactReason | String | Flow.contactReason |
| escalationReason | String | Flow.escalationReason |
| incidentIndicator | Boolean | Flow.incidentIndicator |

En Architect, Data Table Lookup asigna las 36 columnas no clave a Flow.<nombre exacto>. La clave NumeroPedido se asigna desde Flow.orderNumber en la rama Found; no se presupone que el lookup la devuelva como columna de salida. Después Set Screen Pop selecciona SC_Consulta_Pedido publicado y enlaza los 43 inputs.

Las acciones Update Data de Architect solo asignan variables Flow.*; no actualizan la Data Table.

La cola destino es **Demo_Hermet10_EmailIN**. La transferencia se realiza en el flujo con Transfer to ACD. No hay un botón del Script que modifique la tabla ni que simule una transferencia cambiando variables.

## Prueba manual

Asignar un email a un agente: comprobar que abre el Script, muestra NumeroPedido=2540721, CodigoCliente=10065, Referencia=80822416, orden=`1 | 2`, la incidencia y las dos fechas de entrega distintas. Verificar que no hay controles editables ni acciones de modificación y que navegar no cambia los datos. Publicar cambios del Script y refrescar su selección en Architect si se modifican inputs.
