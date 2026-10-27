[CmdletBinding()]
param([string]$GcPath, [string]$Profile, [switch]$CheckAuth)
. (Join-Path $PSScriptRoot 'GenesysCli.Common.ps1')
Initialize-Gc -GcPath $GcPath -Profile $Profile
Write-Host "Ejecutable: $script:GcExecutable"
foreach ($name in @('GENESYSCLOUD_REGION','GENESYSCLOUD_OAUTHCLIENT_ID','GENESYSCLOUD_OAUTHCLIENT_SECRET','GENESYSCLOUD_ACCESS_TOKEN')) {
    $present = -not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))
    Write-Host "$name presente: $present"
}
Write-Host (Invoke-GcText @('version'))
$commands = @(
    @{ Path=@('organizations','me','get'); Flags=@() },
    @{ Path=@('flows','datatables','list'); Flags=@('--name','--pageNumber','--pageSize') },
    @{ Path=@('flows','datatables','get'); Flags=@('--expand') },
    @{ Path=@('flows','datatables','create'); Flags=@('--file') },
    @{ Path=@('flows','datatables','rows','get'); Flags=@('--showbrief') },
    @{ Path=@('flows','datatables','rows','list'); Flags=@('--showbrief','--pageNumber','--pageSize') },
    @{ Path=@('flows','datatables','rows','create'); Flags=@('--file') },
    @{ Path=@('routing','queues','list'); Flags=@('--name','--pageNumber','--pageSize') },
    @{ Path=@('flows','list'); Flags=@('--name','--pageNumber','--pageSize') },
    @{ Path=@('flows','get'); Flags=@() },
    @{ Path=@('scripts','published','list'); Flags=@('--name','--pageNumber','--pageSize') }
)
foreach ($c in $commands) {
    Assert-GcCommand -CommandArgs $c.Path -RequiredFlags $c.Flags
    Write-Host "Ayuda compatible: $($c.Path -join ' ')"
}
# La ayuda es local. Solo esta llamada verifica autenticacion real y organizacion.
if ($CheckAuth) {
    $org = Invoke-GcJson @('organizations','me','get')
    Write-Host "Autenticacion verificada. Organizacion: $($org.name); ID devuelto por API: $($org.id)"
} else { Write-Host 'Autenticacion NO comprobada. Ejecute de nuevo con -CheckAuth.' }
