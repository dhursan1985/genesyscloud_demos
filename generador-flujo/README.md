# Flujo nuevo con datos del Excel y Script de solo lectura

El generador crea un Inbound Email Flow **nuevo**, sin utilizar el archivo anterior. Usa el SDK oficial de Architect 0.70.1 para construirlo en memoria, validar, exportar a `.i3InboundEmailFlow`, reimportar en memoria y volver a validar. No necesita Archy ni guarda/publica un flujo remoto.

**Estado:** código probado localmente con un grafo simulado y métodos del paquete oficial. No hay autenticación Genesys en cloud: no se ha ejecutado la validación real ni se ha generado un archivo nativo como validado.

## Configuración vigente

- Tabla: **DT_Demo_Pedidos_Clientes**, las 37 columnas originales del Excel, con String para todos los campos.
- Clave API: `key`, etiqueta **NumeroPedido**. Hay **15 filas**, una por pedido; valores distintos de Instancia/orden consolidados con ` | ` según la elección del usuario. Las 90 filas se conservan aparte.
- Cola y reintento por defecto: **Demo_Hermet10_EmailIN**.
- Script publicado: **SC_Consulta_Pedido**, cuatro páginas de solo lectura, **43 inputs** (37 campos Excel y 6 metadatos). Ninguna Data Action ni control editable.
- El lookup usa Flow.orderNumber, variable de extracción. En Found se asigna explícitamente Flow.NumeroPedido=Flow.orderNumber; el resto se mapea desde las 36 columnas de salida.
- No hay customerName/customerEmail/customerPhone/status en la tabla. No se inventa nombre ni estado; tampoco se compara el remitente con un email de cliente inexistente.

## Requisitos

Node.js 20+ y npm; autenticación y permisos de Architect Scripting (incluido architect:ui:view), vista/búsqueda de tabla, cola y Script en sus divisiones. Los recursos deben existir antes de generar. Publicar el Script con Screen Pop y sus 43 inputs. Si falta un campo o input, el generador se detiene.

El código y las respuestas usan `../data-table-fields.json`, `../respuestas/` y los datos de prueba de `../tests/email_cuerpo.txt`. Extraer el paquete completo, no descargar solo builder.cjs.

## Ejecutar en PowerShell / VS Code

Desde la raíz del proyecto:

```powershell
Set-Location .\generador-flujo
npm ci --ignore-scripts
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron instalar las dependencias' }
Copy-Item .\config.example.json .\config.local.json
```

Si config.local.json ya existe, conservarlo y actualizar sus nombres/columnas de acuerdo con la configuración actual. No se edita package-lock.json ni se desactiva TLS/integridad.

En config.local.json sustituir **location** por la región SDK real (ejemplos: Irlanda prod_eu_west_1, Frankfurt prod_eu_central_1, Londres prod_eu_west_2) y **expectedOrganizationId** por el ID de la organización destino conocido. No inferir región por idioma. Los nombres de tabla/cola/Script deben ser exactos; si creas una tabla nueva por incompatibilidad con la anterior, sincronizar aquí su nombre.

Autenticación mediante bindings de proceso: GENESYSCLOUD_ACCESS_TOKEN, o GENESYSCLOUD_OAUTHCLIENT_ID + GENESYSCLOUD_OAUTHCLIENT_SECRET. No poner valores en JSON, Git o el chat. Un perfil de gc no inyecta automáticamente estas variables en Node; usar el mecanismo seguro de tu equipo. Si se usa token de usuario, tokenIsClientCredentials=false; para client credentials mantener true. Si coexisten ambos mecanismos se utiliza el token.

Las expresiones de cuerpo/remitente previstas son Email.Message.body y ToString(Email.Message.from). El motor real debe validar sus tipos; si tu versión expone otra propiedad, configurar la String correcta en bodyExpression/senderExpression. No se ignoran errores para exportar.

```powershell
npm run generate
if ($LASTEXITCODE -ne 0) { throw 'La generacion no ha terminado correctamente' }
```

## Resultado e importación

Solo después de las dos validaciones sin errores:

```text
exports/flujo-nuevo/Hermet10_Demo_ConsultaPedido.i3InboundEmailFlow
exports/flujo-nuevo/validation.txt
exports/flujo-nuevo/roundtrip-validation.txt
```

El archivo lo produce el serializador oficial, no una codificación manual. Si ya existe, se conserva y se debe elegir otro outputDirectory para generar una versión nueva. Importar manualmente en un **Inbound Email Flow de prueba**, ejecutar Validate en Architect, revisar dependencias y solo entonces guardar/publicar/asociar ruta y probar recepción real. La exportación contiene referencias resueltas para la organización autenticada: para otra organización recrear dependencias y volver a generar.

## Recorrido

Cuerpo plano, siete cifras, hasta diez menciones y 16000 caracteres. Admite los patrones solicitados y pedido número 2540721. Repetir la misma referencia no crea ambigüedad; referencias distintas o límites escalan. No procesa adjuntos, imágenes ni HTML arbitrario.

- Found → mapeo de campos Excel; si se pide agente, Screen Pop y transferencia; si no, autorrespuesta y fin.
- Not Found → aviso y escalado; Failure de lookup/envío → motivo técnico y escalado.
- Sin número → solicitar dato, salvo petición explícita de agente, que escala.
- Set Screen Pop pasa los 43 inputs de lectura. Transfer to ACD usa Demo_Hermet10_EmailIN; un único reintento ante Failure a la cola de respaldo real (por defecto la misma). Dos fallos terminan y requieren revisión operativa: no se garantiza un agente durante una indisponibilidad.

El Script no contiene escrituras ni Data Actions. Los campos se presentan tal cual; NULL literal y fechas distintas no se reinterpretan como estado. Limitar la demo a buzones controlados: no hay datos de email del cliente para verificar identidad en la tabla.

Las respuestas se configuran como String; comprobar formato/saltos en tu canal. Send Auto Reply no expone asunto personalizado en la API consultada; el asunto exacto pedido sigue siendo una limitación, no se inventa una propiedad Subject. Las plantillas HTML son una alternativa para revisar/configurar en un modo compatible, no una promesa de multipart MIME.

## Pruebas

`npm test`: 11 pruebas locales del grafo, patrones, 43 inputs, ausencia de campos ficticios, fallos y bloqueos de configuración/autenticación. No equivalen a ejecutar expresiones en Genesys. La validación autenticada, importación, publicación y recepción real siguen pendientes.

Fuentes: [SDK oficial](https://github.com/MyPureCloud/purecloud-flow-scripting-api-sdk-javascript), [ArchFactoryFlows](https://mypurecloud.github.io/purecloud-flow-scripting-api-sdk-javascript/ArchFactoryFlows.html), [exportación oficial](https://mypurecloud.github.io/purecloud-flow-scripting-api-sdk-javascript/ArchFlowInboundEmail.html#exportToDirAsync).
