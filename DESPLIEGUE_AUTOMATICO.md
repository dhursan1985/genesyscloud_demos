# Preparación administrativa automática

`scripts/deploy-genesys-demo.ps1` ejecuta comprobaciones y prepara tabla/filas, cola, biblioteca y Canned Response con CLI de Genesys autenticado. **No se ejecuta desde el Script del agente**. El Script SC_Consulta_Pedido es de solo lectura y no contiene Data Actions ni actualizaciones.

Configuración vigente: tabla con las **37 columnas Excel**, clave NumeroPedido, **15 filas consolidadas**, cola **Demo_Hermet10_EmailIN** y Script con **43 inputs**. Las 90 filas originales se conservan en datos/.

```powershell
$Gc = (Get-Command gc.exe -CommandType Application -ErrorAction Stop).Source
$OrgId = 'REEMPLAZAR_POR_ID_REAL_DE_ORGANIZACION'
.\scripts\deploy-genesys-demo.ps1 -GcPath $Gc -ExpectedOrganizationId $OrgId -Mode Plan
.\scripts\deploy-genesys-demo.ps1 -GcPath $Gc -ExpectedOrganizationId $OrgId -Mode Apply
```

Añadir -Profile 'MI_PERFIL_REAL' si se utiliza uno distinto de DEFAULT; comprobar organización con el mismo perfil. No volcar credenciales ni pasarlas en argumentos compartidos. Requiere permisos de consulta, creación de tabla/filas, cola y biblioteca/respuesta en la división elegida. Para los recursos nuevos se puede pasar -DivisionId real; no se mueven los existentes.

Orden: validar archivos → autenticar y cotejar organización → verificar ayuda CLI → inventario → tabla y 15 filas → cola si falta → biblioteca si falta → respuesta si falta → informe de pendientes. No asigna agentes, no publica flujo/Script, no configura un buzón ni envía emails.

Si existe una tabla de 16 columnas o con datos distintos, se detiene y no la sobrescribe. Resolver la migración con respaldo administrativo o usar otro nombre de tabla y actualizar config/selectores/generador. Las repeticiones reutilizan recursos y filas iguales; no borra, no hace rollback y no modifica recursos existentes. Ejecutar una sola instancia a la vez.

Informes nuevos en exports/deploy-<fecha>-<id>/deployment-report.json; incluyen IDs reales y pasos, nunca credenciales. Los informes/evidencias pueden contener datos y deben conservarse con los permisos adecuados.

| Código | Significado |
|---|---|
| 0 Plan | plan completado sin escrituras remotas |
| 2 Apply | preparación automática completada, quedan configuración y pruebas manuales |
| 0 Verify | inventario de recursos comprobado, no funcionalidad extremo a extremo |
| 1 | error; revisar failedStep/error y repetir después de corregir |

Después de configurar y publicar el Script/flujo, miembros de cola y ruta email:

```powershell
.\scripts\deploy-genesys-demo.ps1 -GcPath $Gc -ExpectedOrganizationId $OrgId -Mode Verify
```

Verify solo lee Genesys. functionalReadinessVerified permanece false: el inventario no sustituye enviar un email real, recibir respuesta y aceptar el escalado con los datos del Script. El flujo usa exclusivamente Data Table Lookup para la consulta. No hay dependencias de Data Actions de escritura en esta entrega.

Ver README_Configuracion_Genesys.md, SC_Consulta_Pedido.md y Architect_ConsultaPedido.md. La compatibilidad sintáctica con Windows no equivale a ejecución remota: las pruebas realizadas fueron PowerShell 7 en Linux con CLI simulado.
