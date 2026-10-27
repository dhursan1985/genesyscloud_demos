# Validación vigente — 2026-10-27

Configuración solicitada: campos del Excel, una fila por pedido tras confirmación del usuario, Script de agente de solo lectura y cola **Demo_Hermet10_EmailIN**. No se ha accedido a una organización Genesys ni se han cambiado recursos remotos.

## Evidencia ejecutada

- **9 pruebas Python correctas** de datos/entrega: mismos 37 encabezados y valores del workbook normalizado, 90 filas originales conservadas, 15 consolidadas, clave NumeroPedido única, campos exactos, inputs de solo lectura, cola y respuestas. Usa openpyxl 3.1.5. No se infieren campos ausentes.
- Excel guardado byte a byte, SHA-256 real: `4c765dbb98ccd18e5f6329c5aa09a00888c76127b8c7f687375b10eecb550f1f`. El manifiesto y las pruebas comprueban su igualdad con la fuente recibida.
- **11 pruebas Node correctas** del generador: API pública del SDK 0.70.1 disponible y grafo simulado, extracción, encontrado/no encontrado, 43 inputs, asistencia, fallos y bloqueos de credenciales/configuración. No equivalen al motor Architect real.
- **15 pruebas PowerShell/CLI simulado correctas**, ejecutadas con PowerShell 7.5.5 en Linux: carga de las 15 filas, repetición idempotente, protección de esquemas/filas distintos, perfil, autenticación, organización, paginación, Plan/Apply/Verify y reanudación parcial. No ejecutadas en Windows ni contra API real.
- `validate-config.ps1` pasó: 14 JSON válidos, 37 columnas, 90 filas originales, 15 pedidos consolidados, integridad de workbook, 43 inputs Input=true/Output=false/readOnly=true y sintaxis de todos los scripts PowerShell.
- Definición API de Data Table y Canned Response contrastadas sin errores con DataTable/Response del Swagger oficial ya consultado, revisión `840a1776a400c3a44faa3754b4d3a26e8d8f4727`.

## Datos confirmados

No hay una columna única en las 90 filas originales. Se eligió explícitamente consolidar por NumeroPedido. La clave API `key` muestra el título NumeroPedido: sustituye esa columna en el esquema, no agrega un campo visible. Son 37 columnas en total.

Se conservan nombres, orden, NULL literal, espacios y fechas. Las celdas datetime de Excel se representan como texto ISO con espacio. Solo Instancia/orden tienen valores distintos dentro de los pedidos; se unen con ` | `, sin eliminar valores distintos. Las líneas y multiplicidades originales permanecen en XLSX/CSV original. Para 2540721: orden=`1 | 2`, FechaEntrega=2025-10-03 00:00:00.000 y RealDeliveryDate=2025-10-06 07:05:13.197, sin confundir fechas.

No se generan customerName/customerEmail/customerPhone/status. El Script tiene cuatro páginas de texto y navegación, ninguna entrada editable ni acción de escritura. Se retiraron los tres JSON de DA_Update* y sus fixtures de la entrega activa; la copia anterior está preservada fuera del checkout.

## Pendiente real

Comprobar CLI/perfil de Windows, permisos/divisiones, creación o migración administrativa de tabla, publicación del Script con 43 inputs, generación/validación/importación del flujo mediante SDK o editor, cola con agentes y ruta/buzón real. Probar envío, respuesta y aceptación del escalado. La limitación del asunto personalizado de Send Auto Reply permanece.

No se ha entregado ni generado aquí un nuevo `.i3InboundEmailFlow` que se afirme validado. La lectura de archivos y pruebas locales no certifica existencia de recursos en Genesys ni funcionamiento de extremo a extremo.

El tratamiento de JSON en Windows PowerShell 5.1 usa JavaScriptSerializer para admitir la clave vacía del package-lock; esa rama no se ha ejecutado en Windows. Node_modules y exportaciones locales quedan excluidos de la validación de archivos de entrega.
