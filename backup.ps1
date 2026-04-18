# ============================================================================
# BACKUP.PS1 - Backup E:\ -> D:\BACKUP_DADOS  com QUARENTENA de 30 dias
# Versao com suporte a LONG PATH (>260 caracteres)
# ============================================================================

$Origem     = 'E:\'
$Destino    = 'D:\BACKUP_DADOS'
$Quarentena = 'D:\BACKUP_QUARENTENA'
$LogDir     = 'D:\BACKUP_LOGS'
$Log        = Join-Path $LogDir 'backup.log'
$RetencaoQuarentenaDias = 30

if (-not (Test-Path $Destino))    { New-Item -ItemType Directory -Path $Destino    -Force | Out-Null }
if (-not (Test-Path $Quarentena)) { New-Item -ItemType Directory -Path $Quarentena -Force | Out-Null }
if (-not (Test-Path $LogDir))     { New-Item -ItemType Directory -Path $LogDir     -Force | Out-Null }

function LogLine($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $Log -Value "[$ts] $msg"
}

function To-LongPath([string]$p) {
    if ($p.StartsWith('\\?\')) { return $p }
    if ($p.StartsWith('\\'))   { return '\\?\UNC\' + $p.Substring(2) }
    return '\\?\' + $p
}
function Exists-LP([string]$p)    { [System.IO.File]::Exists((To-LongPath $p)) -or [System.IO.Directory]::Exists((To-LongPath $p)) }
function CreateDir-LP([string]$p) { [System.IO.Directory]::CreateDirectory((To-LongPath $p)) | Out-Null }
function Move-LP([string]$src,[string]$dst) { [System.IO.File]::Move((To-LongPath $src), (To-LongPath $dst)) }

if (-not (Test-Path 'E:\')) {
    LogLine 'ERRO: HD externo E: nao encontrado - backup cancelado'
    exit 1
}

LogLine '======================================='
LogLine 'BACKUP + QUARENTENA - INICIO'
LogLine '======================================='

$dataHoje = Get-Date -Format 'yyyy-MM-dd'
$destinoQ = Join-Path $Quarentena $dataHoje
$destNorm = $Destino.TrimEnd('\') + '\'
$origNorm = $Origem.TrimEnd('\')  + '\'

$movidos = 0
$falhas  = 0
$verificados = 0

$arquivos = Get-ChildItem -LiteralPath $Destino -Recurse -File -ErrorAction SilentlyContinue

foreach ($arquivo in $arquivos) {
    $verificados++
    if ($arquivo.FullName -like '*\logs\*')    { continue }
    if ($arquivo.Name     -ieq  'backup.log')  { continue }
    if ($arquivo.Name     -ieq  'Thumbs.db')   { continue }
    if ($arquivo.Name     -ieq  'desktop.ini') { continue }

    try {
        $rel  = $arquivo.FullName.Substring($destNorm.Length)
        $orig = $origNorm + $rel

        if (-not (Exists-LP $orig)) {
            $dest  = Join-Path $destinoQ $rel
            $pasta = Split-Path $dest -Parent
            if (-not (Exists-LP $pasta)) { CreateDir-LP $pasta }
            Move-LP $arquivo.FullName $dest
            $movidos++
        }
    } catch {
        $falhas++
        LogLine "AVISO: falha ao mover '$($arquivo.FullName)' -> $($_.Exception.Message)"
    }
}
LogLine "Quarentena: $verificados verificados / $movidos movidos / $falhas falhas"

$limite = (Get-Date).AddDays(-$RetencaoQuarentenaDias)
$apagadas = 0
Get-ChildItem -LiteralPath $Quarentena -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $limite } |
    ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
            $apagadas++
        } catch {
            LogLine "AVISO: nao apagou quarentena antiga '$($_.FullName)'"
        }
    }
LogLine "Limpeza: $apagadas pasta(s) com mais de $RetencaoQuarentenaDias dias apagada(s)"

$robocopyLog = Join-Path $LogDir 'robocopy.log'
robocopy 'E:\' 'D:\BACKUP_DADOS' /MIR /Z /R:1 /W:3 /XJ /NFL /NDL /XD "D:\BACKUP_DADOS\logs" /XF "D:\BACKUP_DADOS\backup.log" /LOG+:$robocopyLog

attrib -H -S 'D:\BACKUP_DADOS'
attrib -H -S 'D:\BACKUP_DADOS\*' /S /D

LogLine 'BACKUP + QUARENTENA - FIM'
LogLine '======================================='
