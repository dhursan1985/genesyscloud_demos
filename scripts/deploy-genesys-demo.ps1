[CmdletBinding()]
param(
    [string]$GcPath,
    [string]$Profile,
    [Parameter(Mandatory=$true)][string]$ExpectedOrganizationId,
    [ValidateSet('Plan','Apply','Verify')][string]$Mode = 'Plan',
    [string]$DivisionId,
    [string]$LibraryName = 'BIB_Demo_Pedidos',
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config.demo.json'),
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'exports')
)
. (Join-Path $PSScriptRoot 'GenesysCli.Common.ps1')
$runDirectory = Join-Path $OutputDirectory ('deploy-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$reportPath = Join-Path $runDirectory 'deployment-report.json'
$report = [ordered]@{
    mode=$Mode; status='running'; organizationId=$null; steps=@(); resources=@{};
    functionalReadinessVerified=$false;
    pendingManualSteps=@(
        'Configurar miembros/capacidad email de la cola y comprobar agentes disponibles.',
        'Crear y publicar SC_Consulta_Pedido con sus inputs y Screen Pop; ver SC_Consulta_Pedido.md.',
        'Construir, validar y publicar el flujo con Data Table Lookup; ver Architect_ConsultaPedido.md. No importar el adjunto incompleto.',
        'Configurar dominio/buzon real y asociar ruta al flujo publicado.',
        'Probar autorrespuesta, no encontrado, error, transferencia y recepcion del Script por un agente.',
        'La Canned Response conserva marcadores manuales: el agente debe rellenarlos antes de enviar.'
    )
}
$step = 'Validacion local'
function Record-Step {
    param([string]$Name)
    $report.steps += $Name
    Write-DemoJson -Path $reportPath -Value $report
    Write-Host "OK: $Name"
}
function Find-OneOrNone {
    param([object[]]$Entities,[string]$Name)
    $matches = @($Entities | Where-Object { $_.name -ceq $Name })
    if ($matches.Count -gt 1) { throw "Nombre ambiguo: $Name. No se selecciona un ID arbitrario." }
    if ($matches.Count -eq 1) { return $matches[0] }
    return $null
}
function New-DemoResource {
    param([string[]]$CommandArgs,[object]$Body,[string]$FileName)
    $file = Join-Path $runDirectory $FileName
    Write-DemoJson -Path $file -Value $Body
    $created = Invoke-GcJson ($CommandArgs + @('--file',$file))
    if (-not ($created.PSObject.Properties.Name -contains 'id') -or -not $created.id) { throw 'La API no devolvio ID; compruebe el recurso antes de repetir.' }
    return $created
}
try {
    & (Join-Path $PSScriptRoot 'validate-config.ps1')
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($field in @('dataTableName','queueName','flowName','scriptName','cannedResponseName','orderNumber')) {
        if ([string]::IsNullOrWhiteSpace([string]$config.$field)) { throw "Falta el campo $field en config." }
    }
    if ([string]::IsNullOrWhiteSpace($LibraryName)) { throw 'LibraryName no puede estar vacio.' }
    Initialize-Gc -GcPath $GcPath -Profile $Profile
    $step = 'Autenticacion y organizacion'
    $org = Invoke-GcJson @('organizations','me','get')
    if ($org.id -cne $ExpectedOrganizationId) { throw 'Organizacion distinta de la esperada; no se escribe en Genesys.' }
    $report.organizationId = $org.id
    Record-Step $step
    $step = 'Compatibilidad CLI'
    & (Join-Path $PSScriptRoot 'check-genesys-cli.ps1') -GcPath $script:GcExecutable -Profile $Profile
    foreach ($path in @('routing queues list','responsemanagement libraries list','responsemanagement responses list')) {
        Assert-GcCommand ($path.Split(' ')) @('--pageNumber','--pageSize','--autopaginate')
    }
    Assert-GcCommand @('responsemanagement','responses','list') @('--libraryId')
    if ($Mode -eq 'Apply') {
        foreach ($path in @('routing queues create','responsemanagement libraries create','responsemanagement responses create')) {
            Assert-GcCommand ($path.Split(' ')) @('--file')
        }
    }
    Record-Step $step
    $step = 'Inventario previo de recursos'
    $queue = Find-OneOrNone @(Get-GcPages @('routing','queues','list','--name',$config.queueName)) $config.queueName
    $library = Find-OneOrNone @(Get-GcPages @('responsemanagement','libraries','list')) $LibraryName
    $response = $null
    if ($null -ne $library) {
        $response = Find-OneOrNone @(Get-GcPages @('responsemanagement','responses','list','--libraryId',$library.id)) $config.cannedResponseName
    }
    Record-Step $step
    $seedArgs = @{GcPath=$script:GcExecutable; Profile=$Profile; ExpectedOrganizationId=$ExpectedOrganizationId; ConfigPath=$ConfigPath}
    if ($DivisionId) { $seedArgs.DivisionId=$DivisionId }
    if ($Mode -eq 'Plan') {
        $step = 'Plan de Data Table'
        & (Join-Path $PSScriptRoot 'seed-datatable.ps1') @seedArgs
        $report.resources.queue = $(if ($null -eq $queue) { 'would-create' } else { 'reuse-existing' })
        $report.resources.library = $(if ($null -eq $library) { 'would-create' } else { 'reuse-existing' })
        $report.resources.cannedResponse = $(if ($null -eq $response) { 'would-create' } else { 'reuse-existing-without-overwrite' })
        $report.status='plan-only-no-remote-writes'
        Record-Step $step
        Write-Host "Plan guardado: $reportPath. Para ejecutar, use -Mode Apply."
        exit 0
    }
    if ($Mode -eq 'Apply') {
        $step = 'Crear/verificar Data Table y pedidos'
        & (Join-Path $PSScriptRoot 'seed-datatable.ps1') @seedArgs -Apply
        Record-Step $step
        $step = 'Crear/verificar cola'
        if ($null -eq $queue) {
            $body = @{name=$config.queueName;description='Demo de consulta de pedidos por email'}
            if ($DivisionId) { $body.division=@{id=$DivisionId} }
            $queue = New-DemoResource @('routing','queues','create') $body 'queue-request.json'
        }
        $report.resources.queue=@{id=$queue.id;name=$queue.name;membersConfiguredByThisScript=$false}
        Record-Step $step
        $step = 'Crear/verificar biblioteca'
        if ($null -eq $library) {
            $body=@{name=$LibraryName}
            if ($DivisionId) { $body.division=@{id=$DivisionId} }
            $library = New-DemoResource @('responsemanagement','libraries','create') $body 'library-request.json'
        }
        $report.resources.library=@{id=$library.id;name=$library.name}
        Record-Step $step
        $step = 'Crear/verificar Canned Response'
        if ($null -eq $response) {
            # Volver a consultar antes de crear: no duplicar respuestas de otra ejecucion completada.
            $response = Find-OneOrNone @(Get-GcPages @('responsemanagement','responses','list','--libraryId',$library.id)) $config.cannedResponseName
        }
        if ($null -eq $response) {
            $body = Get-Content -LiteralPath (Join-Path $script:DemoRoot 'CannedResponse_ConsultaPedido.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $body.name=$config.cannedResponseName
            $body.libraries=@(@{id=$library.id})
            $response = New-DemoResource @('responsemanagement','responses','create') $body 'canned-response-request.json'
            $responseStatus='created-from-template'
        } else { $responseStatus='reused-content-not-overwritten-or-verified' }
        $report.resources.cannedResponse=@{id=$response.id;name=$response.name;status=$responseStatus}
        Record-Step $step
        $report.status='automatic-preparation-complete-manual-steps-pending'
        Write-DemoJson -Path $reportPath -Value $report
        Write-Host "Preparacion automatica completada. Informe: $reportPath"
        foreach ($pending in $report.pendingManualSteps) { Write-Host "PENDIENTE: $pending" }
        # No declarar despliegue funcional completo por crear solo los recursos API.
        exit 2
    }
    $step = 'Verificar recursos remotos'
    if ($null -eq $queue -or $null -eq $library -or $null -eq $response) { throw 'Faltan cola, biblioteca o Canned Response. Ejecute primero Plan/Apply.' }
    & (Join-Path $PSScriptRoot 'check-resources.ps1') -GcPath $script:GcExecutable -Profile $Profile -ConfigPath $ConfigPath -ExportDirectory $runDirectory
    Record-Step $step
    $report.status='resource-inventory-verified-functional-tests-still-required'
    Write-DemoJson -Path $reportPath -Value $report
    Write-Host "Inventario verificado: $reportPath. Aun debe probar email, flujo y Script de extremo a extremo."
    exit 0
} catch {
    $report.status='failed'
    $report.failedStep=$step
    $report.error=$_.Exception.Message
    Write-DemoJson -Path $reportPath -Value $report
    Write-Warning "Fallo en '$step': $($_.Exception.Message). Informe: $reportPath"
    Write-Warning 'No se hace rollback ni se borran recursos. Corrija el fallo y repita; los recursos existentes se descubren de nuevo.'
    exit 1
}
