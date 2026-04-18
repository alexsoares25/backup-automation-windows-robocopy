# ============================================================================
# BACKUP.PS1
# Sistema de Backup Espelhado com Quarentena Inteligente
# ----------------------------------------------------------------------------
# OBJETIVO:
# - Espelhar dados do HD externo (E:\) para HD local (D:\BACKUP_DADOS)
# - Evitar perda de arquivos deletados acidentalmente
# - Mover arquivos removidos para quarentena antes da exclusão definitiva
# - Manter histórico de 30 dias antes de apagar permanentemente
# - Suporte a caminhos longos (> 260 caracteres)
#
# ESTRATÉGIA:
# 1. Varre o destino (backup atual)
# 2. Verifica se arquivos ainda existem na origem
# 3. Se NÃO existir → move para quarentena
# 4. Executa robocopy /MIR (espelhamento real)
# 5. Remove quarentena antiga (> 30 dias)
# 6. Registra tudo em log
# ============================================================================


# =========================
# CONFIGURAÇÕES PRINCIPAIS
# =========================

$Origem     = 'E:\'                     # HD externo (fonte principal)
$Destino    = 'D:\BACKUP_DADOS'         # Pasta de backup espelhado
$Quarentena = 'D:\BACKUP_QUARENTENA'    # Área de proteção contra deleções
$LogDir     = 'D:\BACKUP_LOGS'          # Pasta de logs
$Log        = Join-Path $LogDir 'backup.log'

# Tempo de retenção da quarentena (dias)
$RetencaoQuarentenaDias = 30


# =========================
# CRIAÇÃO DE ESTRUTURA BASE
# =========================

# Garante que todas as pastas existam antes da execução
if (-not (Test-Path $Destino))    { New-Item -ItemType Directory -Path $Destino    -Force | Out-Null }
if (-not (Test-Path $Quarentena)) { New-Item -ItemType Directory -Path $Quarentena -Force | Out-Null }
if (-not (Test-Path $LogDir))     { New-Item -ItemType Directory -Path $LogDir     -Force | Out-Null }


# =========================
# FUNÇÃO DE LOG
# =========================

# Registra mensagens com timestamp no arquivo de log
function LogLine($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $Log -Value "[$ts] $msg"
}


# =========================
# SUPORTE A LONG PATH
# =========================

# Converte caminhos para formato compatível com >260 caracteres
function To-LongPath([string]$p) {
    if ($p.StartsWith('\\?\')) { return $p }

    # Caminho de rede (UNC)
    if ($p.StartsWith('\\'))   { return '\\?\UNC\' + $p.Substring(2) }

    # Caminho local padrão
    return '\\?\' + $p
}

# Verifica existência de arquivo/pasta com suporte a long path
function Exists-LP([string]$p) {
    return [System.IO.File]::Exists((To-LongPath $p)) -or `
           [System.IO.Directory]::Exists((To-LongPath $p))
}

# Cria diretórios com suporte a long path
function CreateDir-LP([string]$p) {
    [System.IO.Directory]::CreateDirectory((To-LongPath $p)) | Out-Null
}

# Move arquivos com suporte a long path
function Move-LP([string]$src,[string]$dst) {
    [System.IO.File]::Move((To-LongPath $src), (To-LongPath $dst))
}


# =========================
# VALIDAÇÃO DE ORIGEM
# =========================

# Se o HD externo não estiver conectado → aborta
if (-not (Test-Path 'E:\')) {
    LogLine 'ERRO: HD externo E: nao encontrado - backup cancelado'
    exit 1
}


# =========================
# INÍCIO DO PROCESSO
# =========================

LogLine '======================================='
LogLine 'BACKUP + QUARENTENA - INICIO'
LogLine '======================================='


# =========================
# PREPARAÇÃO DE VARIÁVEIS
# =========================

$dataHoje = Get-Date -Format 'yyyy-MM-dd'       # Nome da pasta da quarentena (por data)
$destinoQ = Join-Path $Quarentena $dataHoje     # Caminho final da quarentena do dia

# Normalização de paths (evita erro de substring)
$destNorm = $Destino.TrimEnd('\') + '\'
$origNorm = $Origem.TrimEnd('\')  + '\'

# Contadores de controle
$movidos = 0
$falhas  = 0
$verificados = 0


# =========================
# FASE 1 — DETECÇÃO DE DELEÇÕES
# =========================
# Objetivo:
# Identificar arquivos que EXISTEM no backup mas NÃO existem mais na origem

$arquivos = Get-ChildItem -LiteralPath $Destino -Recurse -File -ErrorAction SilentlyContinue

foreach ($arquivo in $arquivos) {

    $verificados++

    # Ignora arquivos de sistema e logs
    if ($arquivo.FullName -like '*\logs\*')    { continue }
    if ($arquivo.Name     -ieq  'backup.log')  { continue }
    if ($arquivo.Name     -ieq  'Thumbs.db')   { continue }
    if ($arquivo.Name     -ieq  'desktop.ini') { continue }

    try {
        # Caminho relativo do arquivo
        $rel  = $arquivo.FullName.Substring($destNorm.Length)

        # Caminho correspondente na origem
        $orig = $origNorm + $rel

        # Se NÃO existe mais na origem → mover para quarentena
        if (-not (Exists-LP $orig)) {

            $dest  = Join-Path $destinoQ $rel
            $pasta = Split-Path $dest -Parent

            # Cria estrutura de pasta na quarentena
            if (-not (Exists-LP $pasta)) {
                CreateDir-LP $pasta
            }

            # Move arquivo
            Move-LP $arquivo.FullName $dest
            $movidos++
        }

    } catch {
        $falhas++
        LogLine "AVISO: falha ao mover '$($arquivo.FullName)' -> $($_.Exception.Message)"
    }
}

LogLine "Quarentena: $verificados verificados / $movidos movidos / $falhas falhas"


# =========================
# FASE 2 — LIMPEZA DA QUARENTENA
# =========================
# Remove pastas antigas com mais de 30 dias

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


# =========================
# FASE 3 — BACKUP (ESPELHO)
# =========================
# Executa sincronização completa com robocopy

$robocopyLog = Join-Path $LogDir 'robocopy.log'

robocopy 'E:\' 'D:\BACKUP_DADOS' `
    /MIR `        # Espelhamento (copia + remove)
    /Z `          # Modo reiniciável (resiliência)
    /R:1 `        # 1 tentativa em erro
    /W:3 `        # Espera 3 segundos
    /XJ `         # Ignora junctions (evita loops)
    /NFL /NDL `   # Não loga arquivos/pastas individuais (log limpo)
    /XD "D:\BACKUP_DADOS\logs" `     # Ignora pasta de logs
    /XF "D:\BACKUP_DADOS\backup.log" ` # Ignora log principal
    /LOG+:$robocopyLog               # Log incremental


# =========================
# FASE 4 — NORMALIZAÇÃO
# =========================
# Remove atributos oculto/sistema para evitar "pasta invisível"

attrib -H -S 'D:\BACKUP_DADOS'
attrib -H -S 'D:\BACKUP_DADOS\*' /S /D


# =========================
# FINALIZAÇÃO
# =========================

LogLine 'BACKUP + QUARENTENA - FIM'
LogLine '======================================='
