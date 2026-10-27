# Hermet10_Demo_ConsultaPedido — email y datos del Excel

Estado: guía/especificación y generador preparados; no hay un flujo nativo nuevo validado en la organización. El generador SDK de `generador-flujo/` crea uno en memoria, valida, exporta y reimporta antes de entregar un archivo. No utiliza el adjunto de flujo anterior.

## 1. Recursos

- Data Table DT_Demo_Pedidos_Clientes: 37 columnas del Excel, 15 filas consolidadas por elección del usuario. Clave API `key`, etiqueta **NumeroPedido**, String. No añadir orderNumber/customerName/customerEmail/status a la tabla.
- Cola **Demo_Hermet10_EmailIN**: crear/asignar miembros capaces de atender email.
- Script **SC_Consulta_Pedido** publicado, Screen Pop, 43 inputs de solo lectura. Sin Data Actions ni componentes de edición.
- Ruta/buzón real autorizado; la dirección del ejemplo no se ha aprovisionado.

Si existe la tabla anterior de 16 columnas, los scripts rechazan el esquema incompatible y no lo cambian ni borran. Configurar otro nombre para una tabla nueva o resolver la migración con copia de seguridad y autorización administrativa; actualizar selectores/configuración en consecuencia.

## 2. Variables

Crear 37 String **Flow.<nombre exacto de columna Excel>**, según `data-table-fields.json`. NumeroPedido se mantiene separado de **Flow.orderNumber**, String auxiliar que contiene el número extraído del email.

Añadir Flow.lookupFound, Flow.needsAgent, Flow.incidentIndicator, Flow.ambiguous (Boolean); Flow.position, Flow.keywordIndex, Flow.digitIndex (Integer); y Flow.rawBody, Flow.bodyLower, Flow.remaining, Flow.afterKeyword, Flow.candidate, Flow.firstOrder, Flow.currentChar, Flow.senderEmail, Flow.contactReason, Flow.escalationReason, Flow.responseBody (String). Inicializar Strings a vacío, Boolean a false y contadores a cero.

La tabla no contiene nombre/email/teléfono del cliente ni estado del pedido: no crearlos ni inferir ENTREGADO. SenderEmail es el remitente de la interacción, no una dirección contrastada con la tabla. Todos los datos de la tabla llegan al Script como texto de lectura.

## 3. Leer cuerpo

En Update Data seleccionar el cuerpo String del email con el editor de expresiones, previsto como Email.Message.body. Para el remitente se propone ToString(Email.Message.from), sujeto a validación de tipo del motor. Las expresiones son configurables en el generador si la versión expone otra propiedad. No usar el asunto o adjuntos como cuerpo.

Texto plano, hasta 16000 caracteres. Si el cuerpo solo está disponible como HTML arbitrario, no afirmar que Replace lo convierte en texto de forma general: limitar la demo a texto plano o transferir a un agente. Normalizar en asignaciones sucesivas: Lower, sustituir retornos/saltos/tabuladores por espacios y ú por u, guardar en Flow.remaining. Conservar el cuerpo original en Flow.rawBody.

## 4. Extracción nativa, sin servicio externo

Architect no debe tratarse como un intérprete de regex de JavaScript/.NET. Este algoritmo usa búsqueda de texto y caracteres; no necesita Data Action. Alcance deliberado: **pedidos de siete cifras ASCII**, hasta diez menciones de `pedido`, cuerpo plano de hasta 16000 caracteres. Ajustar longitud y pruebas si tus pedidos tienen otro formato. La fecha de 2025 de la fila original es histórica e intencionada.

Crear una tarea `ExtraerPedido` con Loop de **10** iteraciones, índice Task.keywordIndex. El siguiente pseudocódigo describe acciones Loop/Decision/Update Data/Exit Loop reales; **no se pega como una expresión única**:

```text
firstOrder=""; ambiguous=false
repetir como máximo 10 veces:
  position = FindString(remaining, "pedido")
  si position < 0: Exit Loop
  si position > 0:
    prev = Substring(remaining, position-1, 1)
    si prev es letra o cifra: consumir hasta position+6 y continuar siguiente iteración
  afterKeyword = Trim(Substring(remaining, position+6, Length(remaining)-position-6))
  remaining = afterKeyword   # garantiza progreso incluso si la mención es inválida
  si afterKeyword empieza por ":": quitar exactamente ese carácter y Trim
  si afterKeyword empieza por "numero ": quitar 7 caracteres y Trim
  si después empieza por ":": quitar exactamente ese carácter y Trim
  candidate=""
  Loop 8, índice Task.digitIndex:
    si digitIndex >= Length(afterKeyword): Exit Loop
    currentChar=Substring(afterKeyword, digitIndex, 1)
    si FindString("0123456789", currentChar) < 0: Exit Loop
    candidate = candidate + currentChar
  si Length(candidate) != 7: siguiente iteración exterior
  si hay carácter tras esas 7 cifras y es letra o cifra: siguiente iteración exterior
  si firstOrder == "": firstOrder=candidate
  si firstOrder != candidate: ambiguous=true
al salir:
  si FindString(remaining,"pedido") >= 0 tras agotar las 10 iteraciones: ambiguous=true
  orderNumber=firstOrder
```

Detalles para conectar acciones sin inventar instrucciones de control:

- Dentro de Loop, usar Decision para cada condición. Para «siguiente iteración» dejar que esa rama llegue al final de la iteración exterior; no añadir un Exit Loop que abandone toda la búsqueda.
- Buscar `pedido` con `FindString(Flow.remaining, "pedido")`. Se usa el resultado cero como coincidencia válida; solo un resultado negativo significa ausencia.
- Para «empieza por» primero comprobar `Length(...)` suficiente en una Decision y después comparar `Substring(...,0,n)`. No evaluar un Substring fuera de rango ni confiar en cortocircuito booleano.
- La prueba de letra usa `FindString("abcdefghijklmnopqrstuvwxyzáéíóúüñ", carácter) >= 0`; la de cifra usa `FindString("0123456789", carácter) >= 0`. Comprobar límites antes de leer el carácter anterior o posterior.
- Para consumir hasta la palabra encontrada usar la asignación `Flow.remaining = Trim(Substring(Flow.remaining, Flow.position + 6, Length(Flow.remaining) - Flow.position - 6))`; para el prefijo `numero ` usar `Trim(Substring(Flow.afterKeyword,7,Length(Flow.afterKeyword)-7))`, después de comprobar longitud y prefijo.
- `pedido:` y `pedido ` son válidos. `despedido`, `pedidos`, `pedido 25407210`, `pedido 2540721abc` y `pedido ABC2540721` no se aceptan. Se admiten `pedido número 2540721` y las cuatro variantes solicitadas. Duplicar la misma referencia no crea ambigüedad; dos distintas sí.
- Si no hay más menciones, conectar una salida de la tarea que evite marcar «límite agotado». Si termina la iteración 10 por límite y quedan menciones, marcar ambiguo. Se pueden usar dos salidas separadas de tarea o un Boolean auxiliar `Flow.limitReached`.
- Tras extraer, si ambiguo: `Flow.escalationReason="Varios pedidos o limite de extraccion"` y Escalar. Si vacío: Send Auto Reply con SinNumero y Disconnect en éxito; en Failure, Escalar.

Solicitar agente explícitamente cuando el cuerpo normalizado contenga `agente`, `asistencia` o `hablar con una persona` usando FindString. Guardar `Flow.needsAgent=true`. Es un detector conservador de palabras, no un clasificador de intención. Si el pedido es válido, hacer el lookup para llenar los datos y después escalar; si falta el número pero se solicita un agente, escalar directamente en vez de terminar con SinNumero.

## 5. Data Table Lookup

1. Añadir **Data Table Lookup** y seleccionar DT_Demo_Pedidos_Clientes. No añadir Call Data Action.
2. Lookup Value: **Flow.orderNumber**, no un literal con ese texto. Busca la clave etiquetada NumeroPedido.
3. Found: asignar las 36 columnas no clave a Flow.<nombre exacto>. Asignar explícitamente **Flow.NumeroPedido=Flow.orderNumber** y Flow.lookupFound=true. La clave no se presupone como una salida de columna.
4. El indicador de incidencia es true si TipologiaIncidencia no está vacía ni es el literal NULL. Los NULL del Excel se conservan; no sustituyen ni inventan datos.
5. Si el cliente solicita agente: motivo correspondiente y Escalar; si no, Send Auto Reply con la respuesta Encontrado y terminar en éxito.
6. Not Found: lookupFound=false, motivo Pedido no encontrado, respuesta NoEncontrado y Escalar tanto en éxito como en fallo de envío.
7. Failure: lookupFound=false, motivo técnico y Escalar. No afirmar que no existe el pedido ante un fallo de consulta.

Una fila por pedido resuelve la clave única. Los campos Instancia y orden pueden ser multivalor con ` | `. No son filas que se puedan consultar por separado en esta tabla. En los datos recibidos solo esos dos campos difieren dentro de cada pedido; el informe `datos/consolidation-report.json` recoge los casos.

## 6. Respuestas

Para Inbound Email usar **Send Auto Reply** y enlazar Flow.responseBody. Las plantillas están en respuestas/, con expresiones `.architect-expression.txt` que sí enlazan variables; los marcadores {{Flow.*}} de TXT/HTML no se sustituyen por sí solos. El generador configura la respuesta como String; comprobar formato/saltos en una prueba real.

La respuesta usa columnas reales: CodigoCliente, Referencia, PedidoCliente, PedidoProveedor, FechaPrevistaEntrega, FechaEntrega, RealDeliveryDate, TipoEnvio, ShippingLotDescription, Albaran, ShippingAreaCode e incidencia. No incluye nombre/email/teléfono o estado inexistentes.

**FechaEntrega y RealDeliveryDate son columnas distintas**: para 2540721 son 2025-10-03 y 2025-10-06 respectivamente. No elegir una como si fuera la otra.

El SDK consultado no expone asunto personalizado en Send Auto Reply; se conserva la semántica nativa de respuesta. El asunto deseado se entrega como plantilla, no como propiedad inventada. Solo responder al remitente, no Reply All; probar protección de autorrespondedores/bucles con la configuración disponible del canal.

Sin email de cliente en la tabla no hay comparación de identidad posible. Esta es una demo para buzones/remitentes controlados; no se presenta el número de pedido como autenticación de cliente ni se fabrican datos de contacto.

## 7. Escalar

Antes de cada transferencia, conservar datos y rellenar motivo/remitente. **Set Screen Pop** selecciona el Script publicado SC_Consulta_Pedido y mapea los 43 inputs de script-inputs.json. Después **Transfer to ACD** selecciona **Demo_Hermet10_EmailIN**. En éxito la interacción sale del flujo; no desconectar antes.

Failure de transferencia: un único reintento a la cola de respaldo real configurada (por defecto la misma). Tras dos fallos el generador termina: requiere supervisión/configuración operativa, no garantiza un agente durante una indisponibilidad. No hacer un bucle infinito.

El Script aparece cuando un agente acepta el email. Solo muestra información y permite cambiar de página; no invoca Data Actions ni modifica registros.

## 8. Validar y publicar

Validate sin errores, revisar warnings, guardar/publicar y asociar la ruta de email real. Probar 2540721, desconocido, sin número, petición de agente y fallos. Revisar llegada de los 43 inputs y ausencia de controles editables. El generador oficial no publica: importar su resultado en un Inbound Email Flow de prueba y validar de nuevo. CLI/JSON locales no prueban la entrega de email ni la asignación real a un agente.
