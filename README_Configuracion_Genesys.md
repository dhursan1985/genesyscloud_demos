# Configuración vigente — Excel y consulta de solo lectura

La entrega activa usa **TablaVerdadHermet10.xlsx** como fuente. Por elección del usuario se consolida a **una fila por NumeroPedido**: 15 pedidos, conservando las **37 columnas originales**, sus nombres, mayúsculas y orden. La cola se llama **Demo_Hermet10_EmailIN**. El Script de agente solo muestra datos y no utiliza Data Actions ni permite edición.

## Archivos de datos

- `datos/TablaVerdadHermet10.xlsx`: copia byte a byte del adjunto recibido.
- `datos/TablaVerdadHermet10_original.csv`: 90 filas originales, incluidas repeticiones.
- `DT_Demo_Pedidos_Clientes.csv`: 15 filas consolidadas para carga en la tabla.
- `DT_Demo_Pedidos_Clientes.json`: body API de creación; clave técnica `key` etiquetada **NumeroPedido**, y 36 propiedades adicionales. Son 37 columnas visibles, no una columna nueva añadida al Excel.
- `data-table-fields.json`: lista canónica de las 37 columnas, con el orden original.
- `datos/source-manifest.json` y `datos/consolidation-report.json`: hashes, recuentos y valores consolidados.

Todos los campos se almacenan como String para conservar NULL literal, valores multivalor, fechas y espacios. Las celdas datetime reales de Excel se representan con texto ISO y espacio; las fechas que ya eran texto, incluidos sus milisegundos, se mantienen. No se recortan espacios como el de ShippingAreaCode="ARAG ".

Regla de consolidación autorizada: valores distintos por columna, en orden de aparición, unidos con ` | `. Solo varían **Instancia** y **orden** dentro de los pedidos de este Excel. Para 2540721, `orden` pasa a `1 | 2`; el resto coincide. La tabla consolidada no conserva la multiplicidad de líneas ni las asociaciones entre filas: para ese detalle se conserva la fuente completa. No se selecciona arbitrariamente una fila.

No existen en el Excel customerName, customerEmail, customerPhone ni status. Se retiraron los datos ficticios de cliente y estado anteriores. FechaEntrega y RealDeliveryDate siguen siendo campos separados. No se infiere ENTREGADO.

## Preparar VS Code / Windows

Abrir esta carpeta en PowerShell; `gc` puede ser un alias de Get-Content, por eso se usa gc.exe:

```powershell
$Gc = (Get-Command gc.exe -CommandType Application -ErrorAction Stop).Source
.\scripts\validate-config.ps1
.\scripts\check-genesys-cli.ps1 -GcPath $Gc -CheckAuth
```

El CLI debe estar autenticado en la región/organización correctas y tener permisos de lectura y de creación administrativa para los recursos que se vayan a cargar. Reutilizar el perfil existente con `-Profile 'MI_PERFIL_REAL'`; no compartir secretos, volcar .gc/config.toml ni copiar credenciales a archivos del repositorio.

## Cargar la tabla

```powershell
$OrgId = 'REEMPLAZAR_POR_ID_REAL_DE_ORGANIZACION'
.\scripts\seed-datatable.ps1 -GcPath $Gc -ExpectedOrganizationId $OrgId
.\scripts\seed-datatable.ps1 -GcPath $Gc -ExpectedOrganizationId $OrgId -Apply
```

El primer comando es Plan. Apply crea tabla y filas si faltan; no cambia ni borra una tabla existente con otro esquema y no sobrescribe filas distintas. Es **carga administrativa**, no una acción del Script del agente. Para división concreta usar -DivisionId con un ID real. No hay IDs de organización ni de recursos inventados en la configuración.

**Si ya creaste la tabla anterior de 16 columnas**, no sirve para este esquema: los scripts se detienen. Resolver la migración administrativamente después de una copia de seguridad o cambiar dataTableName para crear una tabla nueva y sincronizar ese nombre en los selectores y el generador. No se borrará la tabla anterior automáticamente.

Para importación manual, crear el esquema con clave String etiquetada NumeroPedido y sus 36 columnas; descargar una plantilla CSV del importador y confirmar si usa la etiqueta NumeroPedido o el nombre técnico key para su cabecera. El CSV entregado usa NumeroPedido. El script de carga hace esa traducción automáticamente para API.

## Script, flujo y cola

- [SC_Consulta_Pedido.md](SC_Consulta_Pedido.md): cuatro páginas simples, todos los controles de datos son texto de solo lectura. Solo hay botones de navegación, sin guardar, modificar, cerrar incidencias ni ejecutar Data Actions.
- `script-inputs.json`: 37 columnas Excel + 6 metadatos, **43 inputs**, todos Input=true, Output=false, readOnly=true. Es documentación de mapeo, no un Script importable.
- [Architect_ConsultaPedido.md](Architect_ConsultaPedido.md): consulta exclusivamente con **Data Table Lookup**, ramas Found/Not Found/Failure, autorrespuesta y transferencia con Screen Pop.
- [generador-flujo/README.md](generador-flujo/README.md): genera un flujo nuevo con el SDK oficial, previa autenticación y existencia de tabla/cola/Script. No se ha generado ni validado un `.i3InboundEmailFlow` real aquí.
- Cola: **Demo_Hermet10_EmailIN**, configurar miembros y capacidad email; no basta con crear el recurso.

Sin email de cliente en la tabla no se puede validar su identidad por comparación con el remitente. SenderEmail es solo un metadato de la interacción. Limitar esta demo a buzones controlados. Las respuestas solo usan los campos existentes y no inventan nombres, contacto ni estado.

Send Auto Reply no expone el asunto personalizado en la superficie oficial consultada; esa limitación se conserva documentada. Configurar la ruta de email y un buzón real; los emails ilustrativos no se aprovisionan al cargar archivos.

## Respuestas y automatización

`respuestas/` incluye encontrado/no encontrado/sin número, TXT/HTML y expresiones. CannedResponse_ConsultaPedido.* es la respuesta reutilizable del agente, distinta de la autorrespuesta. TXT/HTML se copian al editor; su JSON es un body API con marcador de biblioteca real pendiente. Los marcadores [NombreColumna] se rellenan manualmente antes de enviar.

[DESPLIEGUE_AUTOMATICO.md](DESPLIEGUE_AUTOMATICO.md) y `scripts/deploy-genesys-demo.ps1` preparan recursos administrativos con Plan/Apply/Verify: tabla y 15 filas, cola, biblioteca y respuesta. No habilitan escrituras en el Script de agente ni crean/publican automáticamente el flujo o Script.

Las Data Actions de modificación y sus fixtures anteriores se han retirado de la entrega activa. La copia anterior se conserva fuera del checkout en `genesyscloud_demo_antes_excel_20261027.zip` para recuperación; no es la entrega vigente.

## Validación

```powershell
.\scripts\validate-config.ps1
.\scripts\check-resources.ps1 -GcPath $Gc
```

La validación local comprueba columnas, consolidación, clave, integridad del Excel y mapeos. La remota comprueba recursos API y el pedido 2540721, pero no el grafo ni recepción real de email/Script. Ver VALIDACION.md para la evidencia exacta y sus límites.

Si se desea regenerar los CSV con Python y openpyxl: `python scripts/consolidate-excel.py datos/TablaVerdadHermet10.xlsx RUTA_NUEVA_DE_SALIDA`. No se sobrescriben archivos existentes.
