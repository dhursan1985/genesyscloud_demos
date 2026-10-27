[CmdletBinding()]
param([string]$GcPath, [string]$Profile, [Parameter(Mandatory=$true)][string]$ExpectedOrganizationId, [string]$DivisionId, [switch]$Apply, [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.demo.json'))
. (Join-Path $PSScriptRoot 'GenesysCli.Common.ps1')
& (Join-Path $PSScriptRoot 'validate-config.ps1')
Initialize-Gc -GcPath $GcPath -Profile $Profile
foreach ($path in @('flows datatables list','flows datatables get','flows datatables create','flows datatables rows list','flows datatables rows create')) {
    Assert-GcCommand ($path.Split(' '))
}
Assert-GcCommand @('flows','datatables','create') @('--file')
Assert-GcCommand @('flows','datatables','rows','create') @('--file')
Assert-GcCommand @('flows','datatables','get') @('--expand')
Assert-GcCommand @('flows','datatables','list') @('--pageNumber','--pageSize','--name')
Assert-GcCommand @('flows','datatables','rows','list') @('--pageNumber','--pageSize','--showbrief')
$org = Invoke-GcJson @('organizations','me','get')
if ($org.id -cne $ExpectedOrganizationId) { throw 'La organizacion autenticada no coincide con ExpectedOrganizationId. No se escribe nada.' }
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$definition = Get-Content -LiteralPath (Join-Path $script:DemoRoot 'DT_Demo_Pedidos_Clientes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$definition.name = $config.dataTableName
$keyColumn = [string]$config.dataTableKeyColumn
if ($keyColumn -cne 'NumeroPedido') { throw 'La clave configurada debe ser NumeroPedido.' }
if ($DivisionId) { $definition | Add-Member -NotePropertyName division -NotePropertyValue @{id=$DivisionId} }
$found = @(Get-GcPages @('flows','datatables','list','--name',$config.dataTableName) | Where-Object { $_.name -ceq $config.dataTableName })
if ($found.Count -gt 1) { throw 'Nombre duplicado. Resuelva la ambiguedad antes de continuar.' }
if (-not $Apply) {
    Write-Host "PLAN: organizacion $($org.name); tabla $($config.dataTableName); coincidencias $($found.Count). Sin -Apply no se escribe nada."
    return
}
$tempDirectory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
[IO.Directory]::CreateDirectory($tempDirectory) | Out-Null
try {
    if ($found.Count -eq 0) {
        $file = Join-Path $tempDirectory 'table.json'
        Write-DemoJson -Path $file -Value $definition
        $table = Invoke-GcJson @('flows','datatables','create','--file',$file)
    } else { $table = $found[0] }
    $table = Invoke-GcJson @('flows','datatables','get',$table.id,'--expand','schema')
    Assert-DemoSchema $table
    $existing = @(Get-GcPages @('flows','datatables','rows','list',$table.id,'--showbrief=false'))
    $rows = @(Import-Csv -LiteralPath (Join-Path $script:DemoRoot 'DT_Demo_Pedidos_Clientes.csv') -Encoding UTF8)
    foreach ($row in $rows) {
        $payload = [ordered]@{key=[string]$row.$keyColumn}
        foreach ($p in $row.PSObject.Properties) { if ($p.Name -cne $keyColumn) { $payload[$p.Name]=[string]$p.Value } }
        $match = @($existing | Where-Object { $_.key -ceq $row.$keyColumn })
        if ($match.Count -gt 0) {
            foreach ($k in $payload.Keys) {
                if ([string]$match[0].$k -cne [string]$payload[$k]) { throw "La fila $($row.$keyColumn) ya existe y difiere en $k. No se sobrescribe." }
            }
            Write-Host "Fila $($row.$keyColumn) ya coincide; sin cambios."
        } else {
            $file = Join-Path $tempDirectory 'row.json'
            Write-DemoJson -Path $file -Value $payload
            $null = Invoke-GcJson @('flows','datatables','rows','create',$table.id,'--file',$file)
            Write-Host "Fila creada: $($row.$keyColumn)"
        }
    }
    Assert-GcCommand @('flows','datatables','rows','get') @('--showbrief')
    $test = Invoke-GcJson @('flows','datatables','rows','get',$table.id,[string]$config.orderNumber,'--showbrief=false')
    if ($test.key -cne $config.orderNumber) { throw 'La verificacion final de la fila no coincide.' }
    Write-Host "Pedido $($test.key) comprobado en tabla $($table.id). Ejecute otra vez para comprobar idempotencia."
} finally { Remove-Item -LiteralPath $tempDirectory -Recurse -Force }
