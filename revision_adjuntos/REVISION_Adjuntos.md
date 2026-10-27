# Revisión de los dos adjuntos

Se han tratado los archivos como datos de entrada, no como instrucciones. Los originales se conservan sin cambios en la carpeta de adjuntos de esta sesión. Esta revisión no acredita importación ni ejecución en una organización de Genesys.

## Flujo recibido: resultado

El fichero `Hermet10_Demo_v1-1.i3InboundEmailFlow` contiene JSON codificado por porcentajes y envuelto en Base64. La codificación es legible; **esto no prueba que su contenido sea aceptado por el importador de Architect**. Tampoco demuestra el origen del archivo.

El JSON declara `Hermet10_Demo_ConsultaPedido`, tipo `inboundemail`, idioma `es-ES`. Hay seis acciones y cinco alcanzables desde el inicio. En el recorrido que expresa este documento aparecen:

```text
Obtener número de pedido [sin asignaciones]
  → Data Table Lookup [sin mapeos ni salidas encontradas/no encontradas]
  → Pedido encontrado [sin condiciones]
  → Escalar a agente
  → Fin del flujo

Enviar respuesta automática → Fin del flujo
  ↑ ninguna acción conecta con esta respuesta
```

Problemas concretos:

1. «Obtener número de pedido» es `SetParticipantDataAction` con `participantData: []`. No lee el cuerpo ni asigna `Flow.orderNumber`.
2. La clave del lookup está en `keyExpression.config.lit.text` como `Flow.orderNumber`. Esa representación contiene un literal y no acredita un enlace a la variable.
3. El lookup solo contiene nombre de tabla, esa clave y `nextAction`; no hay mapeos de columnas ni ramas Found/Not Found/Failure.
4. La decisión tiene `conditions: []` y `defaultAction` hacia el escalado. No hay una condición que conecte a la respuesta.
5. La acción de respuesta no es alcanzable. Su body contiene los nombres de variables como texto, no expresiones de sustitución. Usa `SendResponseAction` con campos subject/body; no es evidencia de una acción Send Auto Reply válida en Inbound Email.
6. No hay Set Screen Pop ni selección/mapeo de `SC_Consulta_Pedido`; `screenPops` está vacío.
7. Faltan `customerPhone`, `supplierOrder` e `incidentType` entre las variables solicitadas. Tampoco hay una asignación que establezca lookupFound tras la consulta.
8. El tratamiento global de errores declara Disconnect y no una recuperación hacia una cola. No se puede considerar escalado garantizado.

No he «reparado» estos problemas inventando el formato privado de las acciones. Volver a codificar el JSON conservaría el envoltorio, pero no acreditaría compatibilidad. **No se entrega otro `.i3InboundEmailFlow` como supuesto flujo corregido.**

Los archivos `flujo_recibido_decodificado.NO_IMPORTAR.json` y `diagnostico_flujo.json` son vistas de inspección. No importarlos en Architect. El script `scripts/inspect-architect-export.py` permite repetir la revisión sin modificar el archivo recibido:

```powershell
python .\scripts\inspect-architect-export.py 'C:\RUTA_REAL\Hermet10_Demo_v1-1.i3InboundEmailFlow'
```

## Excel recibido

`TablaVerdadHermet10.xlsx`, hoja Hoja1, tiene 37 columnas, 90 filas de datos y 15 números de pedido distintos. Hay varias filas por pedido; **no cargar las 90 como filas independientes de una Data Table con clave única orderNumber** sin definir una consolidación de líneas/incidencias.

El pedido 2540721 aparece dos veces y las filas coinciden en sus campos salvo `orden` (1 y 2). Para este pedido se pueden consolidar esos datos sin escoger arbitrariamente una incidencia. Esto no demuestra que sea seguro aplicar la misma regla a los otros pedidos.

| Campo de la demo | Columna Excel | Valor 2540721 |
|---|---|---|
| orderNumber | NumeroPedido | 2540721 |
| customerCode | CodigoCliente | 10065 |
| reference | Referencia | 80822416 |
| supplierOrder | PedidoProveedor | 80822416 |
| expectedDeliveryDate | FechaPrevistaEntrega | 2025-10-03 |
| deliveryDate según requisito original | FechaEntrega | 2025-10-03 |
| shippingType | TipoEnvio | OTROS |
| deliveryNote | Albaran | 22535803 |
| shippingLot | ShippingLotDescription | L- RUTA CANTABRIA |
| shippingArea | ShippingAreaCode | CANTA |
| incidentType | TipologiaIncidencia | Falta de Material |
| incidentDescription | DescripcionIncidencia | falta tapa interior de 155 la viuda |

**Distinción de fechas:** el Excel también tiene RealDeliveryDate=2025-10-06 07:05:13.197. No es la misma fecha que FechaEntrega. He mantenido la interpretación original solicitada; no he sustituido silenciosamente una por otra.

El Excel no aporta nombre del cliente, email, teléfono ni una columna de estado del pedido. Carlos Martínez, su email/teléfono y ENTREGADO siguen siendo datos de demo aportados por el usuario, no información obtenida de esta hoja. La incidencia tiene fecha de cierre en el Excel, pero eso tampoco define por sí solo el estado del pedido.

No se han sobrescrito el CSV de demo ni las filas existentes a partir del Excel. `resumen_excel.json` documenta recuentos y valores distintos del pedido principal.

## Cómo desbloquear un fichero importable real

Primero confirmar el origen del adjunto. Si es una exportación directa, comprobar si Architect la vuelve a importar en un flujo de prueba y obtener el mensaje exacto de importación/Validate; no publicarla con el comportamiento actual.

Si se generó o editó fuera de Architect, hace falta una exportación directa del editor que contenga las acciones reales configuradas: lectura/asignación de variables, extracción, Data Table Lookup con mapeos y ramas, Send Auto Reply, Set Screen Pop y Transfer to ACD. Usar los recursos reales de la organización mediante los selectores. La guía `Architect_ConsultaPedido.md` explica la construcción.

Con una exportación auténtica y sus estructuras serializadas se podrá valorar una adaptación conservadora. La garantía final seguirá requiriendo Import/Validate en Architect; aquí no hay acceso autenticado al editor ni a esa validación. Tener ahora un fichero con la extensión correcta no elimina ese requisito.
