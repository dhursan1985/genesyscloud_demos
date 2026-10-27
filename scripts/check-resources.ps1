[CmdletBinding()]
param([string]$GcPath, [string]$Profile, [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.demo.json'), [string]$ExportDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'exports'))
. (Join-Path $PSScriptRoot 'GenesysCli.Common.ps1')
Initialize-Gc -GcPath $GcPath -Profile $Profile
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$org = Invoke-GcJson @('organizations','me','get')
Write-Host "Organizacion consultada: $($org.name) [$($org.id)]"
Write-DemoJson -Path (Join-Path $ExportDirectory 'organization.json') -Value $org
$errors = New-Object 'System.Collections.Generic.List[string]'
foreach ($kind in @('table','queue','flow','script')) {
    try {
        switch ($kind) {
            'table' { $path=@('flows','datatables','list'); $name=$config.dataTableName }
            'queue' { $path=@('routing','queues','list'); $name=$config.queueName }
            'flow' { $path=@('flows','list'); $name=$config.flowName }
            'script' { $path=@('scripts','published','list'); $name=$config.scriptName }
        }
        Assert-GcCommand -CommandArgs $path -RequiredFlags @('--name','--pageNumber','--pageSize')
        $entities = @(Get-GcPages ($path + @('--name', $name)))
        Write-DemoJson -Path (Join-Path $ExportDirectory "$kind-search.json") -Value $entities
        $entity = Get-UniqueNamedResource -Entities $entities -Name $name
        Write-Host "$kind encontrado: $($entity.name) [$($entity.id)]"
        if ($kind -eq 'table') {
            Assert-GcCommand @('flows','datatables','get') @('--expand')
            Assert-GcCommand @('flows','datatables','rows','get') @('--showbrief')
            $table = Invoke-GcJson @('flows','datatables','get', $entity.id, '--expand','schema')
            Assert-DemoSchema $table
            Write-DemoJson -Path (Join-Path $ExportDirectory 'datatable-schema.json') -Value $table
            $row = Invoke-GcJson @('flows','datatables','rows','get', $entity.id, [string]$config.orderNumber, '--showbrief=false')
            if ([string]$row.key -cne [string]$config.orderNumber) { throw 'La fila devuelta no tiene la clave esperada.' }
            Write-DemoJson -Path (Join-Path $ExportDirectory 'order.json') -Value $row
            Write-Host "Clave NumeroPedido y pedido $($config.orderNumber) verificados en la API."
        }
        if ($kind -eq 'flow') {
            Assert-GcCommand @('flows','get')
            $details = Invoke-GcJson @('flows','get',$entity.id)
            Write-DemoJson -Path (Join-Path $ExportDirectory 'flow-metadata.json') -Value $details
            if ($details.type -cne 'inboundemail') { throw 'El flujo existe pero no es inboundemail.' }
        }
    } catch {
        $errors.Add("${kind}: $($_.Exception.Message)")
        Write-Warning $errors[$errors.Count-1]
    }
}
if ($errors.Count -gt 0) { throw "Validacion remota incompleta: $($errors -join '; ')" }
Write-Host 'Recursos encontrados. Esto NO verifica el grafo de Architect, su publicacion, el buzon ni un envio real. Complete la matriz de pruebas del README.'
