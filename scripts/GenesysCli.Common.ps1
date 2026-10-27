Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:DemoRoot = Split-Path $PSScriptRoot -Parent

function Initialize-Gc {
    param([string]$GcPath, [string]$Profile)
    if ($GcPath) {
        $cmd = Get-Command $GcPath -CommandType Application -ErrorAction Stop
    } else {
        $cmd = Get-Command gc.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { $cmd = Get-Command gc -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }
    }
    if (-not $cmd) { throw 'No se encuentra el ejecutable de Genesys. Use -GcPath C:\ruta\gc.exe. gc puede ser el alias Get-Content.' }
    $script:GcExecutable = $cmd.Source
    $script:GcProfile = $Profile
    $helpText = Invoke-GcText @('--help')
    if ($helpText -notmatch '(?i)Genesys|PureCloud') { throw 'El ejecutable no se identifica como Genesys Cloud CLI. No se ejecutaran operaciones.' }
}
function Invoke-GcText {
    param([Parameter(Mandatory=$true)][string[]]$CommandArgs)
    $allArgs = @()
    if ($script:GcProfile) { $allArgs += @('-p', $script:GcProfile) }
    $allArgs += $CommandArgs
    $errFile = [IO.Path]::GetTempFileName()
    $oldPreference = $ErrorActionPreference
    $oldEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $ErrorActionPreference = 'Continue'
        $raw = & $script:GcExecutable @allArgs 2> $errFile
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($code -ne 0) {
            # No volcar stderr: algunas configuraciones de tracing pueden contener credenciales.
            throw "Genesys CLI termino con codigo $code al ejecutar '$($CommandArgs[0])'. Revise perfil, permisos, region y --help; no publique logs con secretos."
        }
        return ($raw -join "`n")
    } finally {
        $ErrorActionPreference = $oldPreference
        [Console]::OutputEncoding = $oldEncoding
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
}
function Invoke-GcJson {
    param([Parameter(Mandatory=$true)][string[]]$CommandArgs)
    $text = Invoke-GcText $CommandArgs
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'El CLI no devolvio JSON. No se interpreta como exito.' }
    try { return ($text | ConvertFrom-Json -ErrorAction Stop) }
    catch { throw 'La salida del CLI no es JSON valido; compruebe el formato de salida del perfil. Se requiere JSON.' }
}
function Assert-GcCommand {
    param([string[]]$CommandArgs, [string[]]$RequiredFlags = @())
    $text = Invoke-GcText ($CommandArgs + @('--help'))
    foreach ($flag in $RequiredFlags) {
        if ($text -notmatch [regex]::Escape($flag)) { throw "La version instalada no anuncia $flag en '$($CommandArgs -join ' ')'. Actualice el CLI o adapte el comando con su ayuda." }
    }
}
function Get-GcPages {
    param([string[]]$CommandArgs)
    $page = 1
    do {
        $response = Invoke-GcJson ($CommandArgs + @('--pageNumber', [string]$page, '--pageSize', '100', '--autopaginate=false'))
        if (-not ($response.PSObject.Properties.Name -contains 'entities')) { throw 'Se esperaba una respuesta paginada con entities; revise el formato JSON del perfil.' }
        $entities = @($response.entities)
        foreach ($entity in $entities) { if ($null -ne $entity) { $entity } }
        if ($entities.Count -lt 100) { break }
        $page++
        if ($page -gt 10000) { throw 'Limite de paginacion alcanzado. Resultado incompleto.' }
    } while ($true)
}
function Get-UniqueNamedResource {
    param([object[]]$Entities, [string]$Name)
    $found = @($Entities | Where-Object { $_.name -ceq $Name })
    if ($found.Count -ne 1) { throw "Se esperaba exactamente un recurso '$Name'; encontrados: $($found.Count). No se elige un ID arbitrario." }
    return $found[0]
}
function Write-DemoJson {
    param([string]$Path, [object]$Value)
    $absolute = [IO.Path]::GetFullPath($Path)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($absolute)) | Out-Null
    [IO.File]::WriteAllText($absolute, ($Value | ConvertTo-Json -Depth 50), (New-Object System.Text.UTF8Encoding($false)))
}
function Assert-DemoSchema {
    param([object]$Table)
    $expected = Get-Content -LiteralPath (Join-Path $script:DemoRoot 'DT_Demo_Pedidos_Clientes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($Table.schema.required) -notcontains 'key') { throw 'La tabla no declara key como clave requerida.' }
    if ($Table.schema.properties.key.title -cne $expected.schema.properties.key.title) { throw 'La etiqueta de key no coincide con NumeroPedido del esquema preparado.' }
    $actualNames = @($Table.schema.properties.PSObject.Properties.Name | Sort-Object)
    $expectedNames = @($expected.schema.properties.PSObject.Properties.Name | Sort-Object)
    if (($actualNames -join ',') -cne ($expectedNames -join ',')) { throw 'Los campos de la Data Table no coinciden con las 37 columnas del Excel.' }
    foreach ($p in $expected.schema.properties.PSObject.Properties) {
        if ($Table.schema.properties.($p.Name).type -cne 'string') { throw "El campo $($p.Name) no es string." }
    }
}
