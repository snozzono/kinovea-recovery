[CmdletBinding()]
param(
    [string]$Filtro = '*',
    [string]$Destino = (Join-Path ([Environment]::GetFolderPath('Desktop')) ('Recuperado_Kinovea_' + (Get-Date -Format 'yyyyMMdd_HHmmss')))
)

# Solo lectura sobre las fuentes. Copia lo encontrado al Destino.
$ErrorActionPreference = 'SilentlyContinue'
$extensiones = @('.kva', '.mp4', '.avi', '.mov', '.mkv', '.wmv', '.flv', '.mpg', '.mpeg', '.m4v', '.webm', '.3gp')
$patron = if ($Filtro -match '\*') { $Filtro } else { "*$Filtro*" }
$resultados = New-Object System.Collections.Generic.List[object]

function Coincide($nombre) {
    $ext = [IO.Path]::GetExtension($nombre).ToLower()
    return ($extensiones -contains $ext) -and ($nombre -like $patron)
}

function Agregar($origen, $ruta, $nombreOriginal) {
    if (-not (Coincide $nombreOriginal)) { return }
    $item = Get-Item -LiteralPath $ruta -Force
    if (-not $item -or $item.PSIsContainer) { return }
    $resultados.Add([pscustomobject]@{
        Origen = $origen
        Ruta   = $item.FullName
        Nombre = $nombreOriginal
        Tamano = $item.Length
        Fecha  = $item.LastWriteTime
    })
}

function Leer-NombreI([byte[]]$bytes) {
    $ver = [BitConverter]::ToInt64($bytes, 0)
    if ($ver -eq 2) {
        $n = [BitConverter]::ToInt32($bytes, 24)
        return [Text.Encoding]::Unicode.GetString($bytes, 28, ($n - 1) * 2)
    }
    return [Text.Encoding]::Unicode.GetString($bytes, 24, 520).TrimEnd([char]0)
}

# 1. Carpetas de usuario y las que aparecen en la configuracion de Kinovea
$raices = New-Object System.Collections.Generic.List[string]
$candidatas = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('MyDocuments'),
    [Environment]::GetFolderPath('MyVideos'),
    (Join-Path $env:USERPROFILE 'Downloads'),
    $env:OneDrive
)
foreach ($c in $candidatas) {
    if ($c -and (Test-Path -LiteralPath $c -PathType Container)) { $raices.Add($c) }
}
$cfg = Join-Path $env:APPDATA 'Kinovea'
if (Test-Path -LiteralPath $cfg) {
    foreach ($f in Get-ChildItem -LiteralPath $cfg -Recurse -File -Force) {
        $texto = Get-Content -LiteralPath $f.FullName -Raw
        foreach ($m in [regex]::Matches($texto, '[A-Za-z]:\\[^<>"|?*\r\n]+')) {
            $p = $m.Value.Trim()
            if (Test-Path -LiteralPath $p -PathType Container) { $raices.Add($p) }
            elseif (Test-Path -LiteralPath $p -PathType Leaf) { $raices.Add((Split-Path -Parent $p)) }
        }
    }
}
$raices = @($raices | Select-Object -Unique)
Write-Host "Carpetas a revisar: $($raices.Count)"
$raices | ForEach-Object { Write-Host "  $_" }

# 2. Archivos actuales (pueden estar corruptos o en 0 KB)
foreach ($r in $raices) {
    foreach ($f in Get-ChildItem -LiteralPath $r -Recurse -File -Force) {
        Agregar 'Actual' $f.FullName $f.Name
    }
}

# 3. Papelera de reciclaje
foreach ($d in Get-PSDrive -PSProvider FileSystem) {
    $rb = Join-Path $d.Root '$Recycle.Bin'
    if (-not (Test-Path -LiteralPath $rb)) { continue }
    foreach ($sid in Get-ChildItem -LiteralPath $rb -Directory -Force) {
        foreach ($i in Get-ChildItem -LiteralPath $sid.FullName -Filter '$I*' -File -Force) {
            try {
                $bytes = [IO.File]::ReadAllBytes($i.FullName)
                $orig = Split-Path -Leaf (Leer-NombreI $bytes)
                $r = Join-Path $i.DirectoryName ('$R' + $i.Name.Substring(2))
                Agregar 'Papelera' $r $orig
            } catch { }
        }
    }
}

# 4. Copias de sombra (Versiones anteriores). Requiere ejecutar como administrador.
$volumenes = Get-CimInstance Win32_Volume | Where-Object { $_.DriveLetter }
$sombras = Get-CimInstance Win32_ShadowCopy
if (-not $sombras) { Write-Host 'Sin copias de sombra (o falta ejecutar como administrador).' }
foreach ($s in $sombras) {
    $letra = ($volumenes | Where-Object { $_.DeviceID -eq $s.VolumeName } | Select-Object -First 1).DriveLetter
    if (-not $letra) { continue }
    foreach ($r in $raices | Where-Object { $_.StartsWith($letra, 'OrdinalIgnoreCase') }) {
        $base = $s.DeviceObject + $r.Substring(2)
        if (-not (Test-Path -LiteralPath $base)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $base -Recurse -File -Force) {
            Agregar 'Copia_sombra' $f.FullName $f.Name
        }
    }
}

# 5. Historial de archivos (quita la marca de fecha del nombre)
foreach ($d in Get-PSDrive -PSProvider FileSystem) {
    $fh = Join-Path $d.Root 'FileHistory'
    if (-not (Test-Path -LiteralPath $fh)) { continue }
    foreach ($f in Get-ChildItem -LiteralPath $fh -Recurse -File -Force) {
        if ($f.FullName -notmatch '\\Data\\') { continue }
        $orig = $f.Name -replace ' \(\d{4}_\d{2}_\d{2} \d{2}_\d{2}_\d{2} UTC\)(?=\.[^.]+$)', ''
        Agregar 'Historial' $f.FullName $orig
    }
}

# 6. Copiar lo que no es "Actual" al Destino (las fuentes no se tocan)
New-Item -ItemType Directory -Path $Destino -Force | Out-Null
$manifiesto = @()
$i = 0
foreach ($r in $resultados | Sort-Object Nombre, Origen) {
    if ($r.Origen -eq 'Actual') {
        $manifiesto += [pscustomobject]@{ Origen = 'Actual'; Nombre = $r.Nombre; Tamano = $r.Tamano; Fecha = $r.Fecha; Copia = $r.Ruta; Estado = 'Solo lectura (no copiado)'; SHA256 = '' }
        continue
    }
    $i++
    $carpeta = Join-Path $Destino ($r.Origen)
    New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    $dest = Join-Path $carpeta ('{0:000}_{1}' -f $i, $r.Nombre)
    try {
        Copy-Item -LiteralPath $r.Ruta -Destination $dest -ErrorAction Stop
        $estado = 'OK'
        $hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
    } catch {
        $estado = 'ERROR: ' + $_.Exception.Message
        $hash = ''
    }
    $manifiesto += [pscustomobject]@{ Origen = $r.Origen; Nombre = $r.Nombre; Tamano = $r.Tamano; Fecha = $r.Fecha; Copia = $dest; Estado = $estado; SHA256 = $hash }
}

$manifiesto | Export-Csv -LiteralPath (Join-Path $Destino 'manifiesto.csv') -NoTypeInformation -Encoding UTF8
Write-Host ''
$manifiesto | Format-Table Origen, Nombre, Tamano, Estado -AutoSize
Write-Host "Destino: $Destino"
Write-Host 'Revisa manifiesto.csv. Los archivos de tamano 0 o con Estado ERROR suelen estar vacios o danados.'
if (Test-Path -LiteralPath $Destino) { Start-Process explorer.exe $Destino }
