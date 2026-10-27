[CmdletBinding()]
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$required=@('DT_Demo_Pedidos_Clientes.csv','DT_Demo_Pedidos_Clientes.json','data-table-fields.json','datos/TablaVerdadHermet10.xlsx','datos/TablaVerdadHermet10_original.csv','datos/source-manifest.json','datos/consolidation-report.json','SC_Consulta_Pedido.md','script-inputs.json','README_Configuracion_Genesys.md','config.demo.json')
foreach($file in $required){if(-not(Test-Path -LiteralPath (Join-Path $Root $file))){throw "Falta $file"}}
$utf8=New-Object System.Text.UTF8Encoding($false,$true)
$jsonFiles=@(Get-ChildItem -LiteralPath $Root -Filter '*.json' -File -Recurse | Where-Object {$_.FullName -notmatch '[\\/](exports|\.local|\.git|node_modules)[\\/]'})
foreach($file in $jsonFiles){
    $text=$utf8.GetString([IO.File]::ReadAllBytes($file.FullName)).TrimStart([char]0xFEFF)
    if($PSVersionTable.PSVersion.Major -ge 6){$null=$text | ConvertFrom-Json -AsHashtable -ErrorAction Stop}
    else{Add-Type -AssemblyName System.Web.Extensions; $serializer=New-Object System.Web.Script.Serialization.JavaScriptSerializer; $serializer.MaxJsonLength=16777216; $null=$serializer.DeserializeObject($text)}
}
$fields=@(Get-Content -LiteralPath (Join-Path $Root 'data-table-fields.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
$definition=Get-Content -LiteralPath (Join-Path $Root 'DT_Demo_Pedidos_Clientes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($fields.Count -ne 37 -or $fields[0] -cne 'NumeroPedido'){throw 'Se esperan las 37 columnas del Excel empezando por NumeroPedido.'}
if(@($definition.schema.required) -notcontains 'key' -or $definition.schema.properties.key.title -cne 'NumeroPedido'){throw 'key debe ser obligatoria y mostrarse como NumeroPedido.'}
$displayColumns=@($definition.schema.properties.PSObject.Properties | ForEach-Object {$_.Value.title})
if(($displayColumns -join ',') -cne ($fields -join ',')){throw 'Las columnas del esquema no coinciden exactamente con el Excel.'}
foreach($p in $definition.schema.properties.PSObject.Properties){if($p.Value.type -cne 'string'){throw "$($p.Name) debe ser String"}}
$rows=@(Import-Csv -LiteralPath (Join-Path $Root 'DT_Demo_Pedidos_Clientes.csv') -Encoding UTF8)
$original=@(Import-Csv -LiteralPath (Join-Path $Root 'datos/TablaVerdadHermet10_original.csv') -Encoding UTF8)
if($rows.Count -ne 15 -or $original.Count -ne 90){throw 'Se esperan 15 filas consolidadas y 90 originales.'}
foreach($list in @(@{Rows=$rows},@{Rows=$original})){
    if(($list.Rows[0].PSObject.Properties.Name -join ',') -cne ($fields -join ',')){throw 'La cabecera debe conservar las 37 columnas y su orden.'}
}
if(@($rows | Group-Object NumeroPedido | Where-Object Count -gt 1).Count){throw 'NumeroPedido no es unico en el CSV consolidado.'}
foreach($row in $rows){
    $source=@($original | Where-Object {$_.NumeroPedido -ceq $row.NumeroPedido})
    if($source.Count -eq 0){throw 'Pedido consolidado inexistente en el original.'}
    foreach($field in $fields){
        $values=New-Object 'System.Collections.Generic.List[string]'
        foreach($item in $source){if(-not $values.Contains([string]$item.$field)){$values.Add([string]$item.$field)}}
        if([string]$row.$field -cne ($values -join ' | ')){throw "Consolidacion incorrecta: $($row.NumeroPedido), $field"}
    }
}
$main=@($rows | Where-Object NumeroPedido -CEQ '2540721')
if($main.Count -ne 1 -or $main[0].orden -cne '1 | 2' -or $main[0].DescripcionIncidencia -cne 'falta tapa interior de 155 la viuda'){throw 'Fila principal alterada.'}
$manifest=Get-Content -LiteralPath (Join-Path $Root 'datos/source-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if((Get-FileHash -LiteralPath (Join-Path $Root 'datos/TablaVerdadHermet10.xlsx') -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest.sha256){throw 'El Excel original fue alterado.'}
$map=@(Get-Content -LiteralPath (Join-Path $Root 'script-inputs.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
if($map.Count -ne 43){throw 'Se esperan 37 campos Excel y 6 entradas auxiliares.'}
foreach($f in $fields){if(@($map | Where-Object {$_.name -ceq $f -and $_.architect -ceq "Flow.$f"}).Count -ne 1){throw "Falta mapeo $f"}}
foreach($m in $map){if($m.input -ne $true -or $m.output -ne $false -or $m.readOnly -ne $true){throw 'Todos los inputs del Script deben ser solo lectura, sin outputs.'}}
if(@(Get-ChildItem -LiteralPath $Root -Filter 'DA_Update*.json' -File).Count){throw 'No debe haber Data Actions de escritura en la entrega activa.'}
$config=Get-Content -LiteralPath (Join-Path $Root 'config.demo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($config.queueName -cne 'Demo_Hermet10_EmailIN' -or $config.readOnlyAgentScript -ne $true){throw 'Cola o modo de Script incorrecto.'}
$flow=Get-Content -LiteralPath (Join-Path $Root 'flow-spec.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($flow.lookup.action -cne 'Data Table Lookup' -or $flow.lookup.usesDataAction -ne $false -or $flow.agentScript.dataActions.Count -ne 0){throw 'Solo se admite lookup nativo y Script sin Data Actions.'}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Filter '*.ps1'){
    $tokens=$null;$errors=$null;$null=[System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "Error sintactico en $($file.Name): $errors"}
}
Write-Host "VALIDACION LOCAL OK: $($jsonFiles.Count) JSON, 37 columnas, 90 filas originales, 15 pedidos consolidados y 43 inputs de solo lectura."
Write-Host 'No verifica recursos remotos, generacion/importacion de flujo ni envio real de email.'
