<#
.SYNOPSIS
    Configurador e Otimizador Escolar - Win 10/11
.DESCRIPTION
    Script focado em notebooks educacionais com Azure AD/Intune e uso geral.
    Otimiza desempenho de CPU e RAM, bloqueia aplicativos/jogos/VPNs indesejados, 
    permite desativar a busca web do Bing no Menu Iniciar isoladamente, alivia desgaste em discos eMMC,
    protege atalhos da Area de Trabalho, ajusta politicas de energia e instala o NetTime.
.AUTHOR
    Julio Antunes (@JulioAntunes00)
.LINK
    https://github.com/JulioAntunes00/script_otimizacao_windows
#>

# =====================================================================
# 0. TRAVA DE SEGURANCA (Requer Administrador)
# =====================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "===================================================" -ForegroundColor Red
    Write-Host " ERRO: FALTA DE PRIVILEGIOS DE ADMINISTRADOR        " -ForegroundColor Red
    Write-Host "===================================================" -ForegroundColor Red
    Write-Host "Por favor, feche esta janela, abra o PowerShell como Administrador e execute novamente." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    return
}

$Host.UI.RawUI.WindowTitle = "Configurador e Otimizador Escolar - Win10/Win11"
$ProgressPreference = 'SilentlyContinue'

# =====================================================================
# 1. VARIAVEIS E LOGS
# =====================================================================
$LogFile = "$env:TEMP\Otimizacao_Escola.log"
$dateStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
try {
    Add-Content -Path $LogFile -Value "`n========================================" -ErrorAction SilentlyContinue
    Add-Content -Path $LogFile -Value "INICIO DA EXECUCAO: $dateStr" -ErrorAction SilentlyContinue
    Add-Content -Path $LogFile -Value "========================================" -ErrorAction SilentlyContinue
} catch {}

function Write-Step {
    param([string]$Text, [string]$Status, [string]$Color = "Green")
    $msg = "{0,-65} [{1}]" -f $Text, $Status
    if ($Status -eq "OK") { Write-Host $msg -ForegroundColor Green }
    elseif ($Status -eq "FALHA") { Write-Host $msg -ForegroundColor Red }
    elseif ($Status -eq "AVISO") { Write-Host $msg -ForegroundColor Yellow }
    else { Write-Host $msg -ForegroundColor $Color }
    
    try { Add-Content -Path $LogFile -Value "$Text -> $Status" -ErrorAction SilentlyContinue } catch {}
}

# =====================================================================
# 2. DETECCAO DE HARDWARE
# =====================================================================
function Atualizar-MetricasDisco {
    $sysPart = Get-Partition -DriveLetter ($env:SystemDrive.Trim(':')) -ErrorAction SilentlyContinue
    if ($sysPart) {
        $osDisk = Get-Disk -Number $sysPart.DiskNumber -ErrorAction SilentlyContinue
        $global:diskSizeGB = [math]::Round($osDisk.Size / 1GB, 1)
        $global:freeSpace = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
    } else {
        $global:diskSizeGB = 0
        $global:freeSpace = 0
    }
    $global:is32GB = ($global:diskSizeGB -gt 0 -and $global:diskSizeGB -le 36)
}

Atualizar-MetricasDisco
$global:espacoInicial = $global:freeSpace
$global:tamanhoInicialDisco = $global:diskSizeGB

$ram = Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory
$ramGB = [math]::Round($ram / 1GB, 1)
$osName = (Get-CimInstance Win32_OperatingSystem).Caption

# Opcoes Padrao (1 a 10)
$global:opts = @{
    1  = $false;  # Contas (alunos / anos_iniciais / LogonUI)
    2  = $false;  # Energia (desligar na tampa, sem hibernar)
    3  = $false;  # Otimizar CPU/RAM, SysMain, WSearch, Feeds e Limpeza
    4  = $false;  # OneDrive (Teams mantido)
    5  = $false;  # Windows Update (Horario Ativo 07h-18h)
    6  = $false;  # Bloqueio de Apps, Jogos (Roblox, Minecraft, GPlay) e VPNs (UltraSurf, Psiphon, etc.)
    7  = $false;  # Bloqueio da Microsoft Store
    8  = $false;  # Proteger Atalhos da Area de Trabalho
    9  = $false;  # Instalar NetTime (Sincronizador de hora para CMOS com defeito)
    10 = $false;  # Desativar Busca Web no Menu Iniciar (Bing Search isolado)
}

# =====================================================================
# 3. FUNCOES DE CONTAS E PERFIS INATIVOS
# =====================================================================

function Test-PerfilProtegido {
    param(
        [Parameter(Mandatory=$true)]
        $Perfil,
        [string[]]$AdminSIDs = @(),
        [string[]]$AdminNames = @(),
        [string[]]$SnapshotNomes = @()
    )

    # 1. Perfis especiais do Windows ou perfil atualmente carregado
    if ($Perfil.Special -or $Perfil.Loaded) { return $true }

    # 2. Caminho do perfil
    $localPath = $Perfil.LocalPath
    if ([string]::IsNullOrWhiteSpace($localPath)) { return $true }
    $userName = Split-Path -Path $localPath -Leaf

    # 3. Perfis do sistema e pastas padrao
    $pastasSistema = @("Default", "Default User", "Public", "Público", "All Users")
    if ($pastasSistema -contains $userName) { return $true }

    # 4. Contas protegidas fixas da escola
    if ($userName -ieq "alunos") { return $true }
    if ($userName -ieq "BlueLab") { return $true }
    if ($userName -ilike "ARACATUBA*") { return $true }
    if ($userName -ilike "alunos.DESKTOP*") { return $true }

    # 5. Administradores locais
    if ($AdminSIDs -contains $Perfil.SID) { return $true }
    if ($Perfil.SID -like "*-500") { return $true }
    if ($AdminNames -icontains $userName) { return $true }

    # 6. Lista do Snapshot gravada na instalacao
    if ($SnapshotNomes -icontains $userName) { return $true }

    return $false
}

function Configurar-ManutencaoAgendadaPerfis {
    try {
        $escolaDir = "C:\ProgramData\EscolaConfig"
        if (-not (Test-Path $escolaDir)) { New-Item -Path $escolaDir -ItemType Directory -Force | Out-Null }

        $snapshotFile = "$escolaDir\perfis_protegidos.txt"
        if (-not (Test-Path $snapshotFile)) {
            $perfisAtuais = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue
            $nomesProtegidos = [System.Collections.Generic.List[string]]::new()
            
            # Adiciona contas existentes no momento da configuracao
            foreach ($p in $perfisAtuais) {
                if ($p.LocalPath) {
                    $uName = Split-Path -Path $p.LocalPath -Leaf
                    if (-not $nomesProtegidos.Contains($uName)) { $nomesProtegidos.Add($uName) }
                }
            }
            # Garante regras fixas no snapshot
            $regrasFixas = @("alunos", "BlueLab", "Público", "Public", "Default", "Default User", "All Users")
            foreach ($rf in $regrasFixas) {
                if (-not $nomesProtegidos.Contains($rf)) { $nomesProtegidos.Add($rf) }
            }

            $nomesProtegidos | Set-Content -Path $snapshotFile -Force -ErrorAction SilentlyContinue
            
            $dataInstalacao = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Set-Content -Path "$escolaDir\data_configuracao.txt" -Value $dataInstalacao -Force -ErrorAction SilentlyContinue
        }

        # Cria script de manutencao que roda em segundo plano
        $scriptManutencao = @'
# Manutencao Automatica de Perfis de Alunos - Escola
$ErrorActionPreference = 'SilentlyContinue'
$snapshotFile = "C:\ProgramData\EscolaConfig\perfis_protegidos.txt"
$logFile = "C:\ProgramData\EscolaConfig\manutencao_perfis.log"

if (-not (Test-Path $snapshotFile)) { exit }
$protegidos = Get-Content $snapshotFile -ErrorAction SilentlyContinue

$adminGroup = Get-LocalGroup | Where-Object { $_.SID -eq 'S-1-5-32-544' }
$adminMembers = if ($adminGroup) { Get-LocalGroupMember -Group $adminGroup.Name -ErrorAction SilentlyContinue } else { @() }
$adminSIDs = @($adminMembers.SID.Value)
$adminNames = @($adminMembers.Name | ForEach-Object { $_.Split('\')[-1] })

$hoje = Get-Date
$perfis = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue

foreach ($p in $perfis) {
    if ($p.Special -or $p.Loaded) { continue }
    if ([string]::IsNullOrWhiteSpace($p.LocalPath)) { continue }
    $user = Split-Path -Path $p.LocalPath -Leaf

    if ($user -in @("Default", "Public", "Público", "All Users", "Default User")) { continue }
    if ($user -ieq "alunos" -or $user -ieq "BlueLab") { continue }
    if ($user -ilike "ARACATUBA*" -or $user -ilike "alunos.DESKTOP*") { continue }
    if ($adminSIDs -contains $p.SID -or $p.SID -like "*-500" -or $adminNames -icontains $user) { continue }
    if ($protegidos -icontains $user) { continue }

    $dataUso = $p.LastUseTime
    if (-not $dataUso) {
        try { $dataUso = (Get-Item -Path $p.LocalPath -ErrorAction SilentlyContinue).LastWriteTime } catch {}
    }

    if ($dataUso) {
        $dias = [math]::Floor(($hoje - $dataUso).TotalDays)
        # Remove contas criadas apos o snapshot e sem uso ha mais de 7 dias
        if ($dias -ge 7) {
            try {
                $p | Remove-CimInstance -ErrorAction Stop
                Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Perfil '$user' removido (Inativo ha $dias dias)" -ErrorAction SilentlyContinue
            } catch {
                Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Erro ao remover '$user': $($_.Exception.Message)" -ErrorAction SilentlyContinue
            }
        }
    }
}
'@
        Set-Content -Path "$escolaDir\Limpar-PerfisInativos.ps1" -Value $scriptManutencao -Encoding UTF8 -Force -ErrorAction SilentlyContinue

        # Cria Tarefa Agendada no Windows (executa semanalmente toda segunda-feira as 12:00)
        $actionCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$escolaDir\Limpar-PerfisInativos.ps1"""
        schtasks /create /tn "LimpezaPerfisAlunos" /tr $actionCmd /sc WEEKLY /d MON /st 12:00 /ru "SYSTEM" /f 2>$null | Out-Null

        Write-Step -Text "Regra de manutencao automatica de perfis ativada (semanal / 7 dias)" -Status "OK"
    } catch {
        Write-Step -Text "Falha ao agendar manutencao de perfis ($($_.Exception.Message))" -Status "AVISO"
    }
}

function Gerenciar-PerfisInativos {
    param([switch]$SilenciosoSeVazio)

    Write-Host "`n>> Analisando perfis de usuarios no computador..." -ForegroundColor Cyan

    $adminGroup = Get-LocalGroup | Where-Object { $_.SID -eq 'S-1-5-32-544' }
    $adminMembers = if ($adminGroup) { Get-LocalGroupMember -Group $adminGroup.Name -ErrorAction SilentlyContinue } else { @() }
    $adminSIDs = @($adminMembers.SID.Value)
    $adminNames = @($adminMembers.Name | ForEach-Object { $_.Split('\')[-1] })

    $snapshotFile = "C:\ProgramData\EscolaConfig\perfis_protegidos.txt"
    $snapshotNomes = if (Test-Path $snapshotFile) { Get-Content $snapshotFile -ErrorAction SilentlyContinue } else { @() }

    $perfis = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue
    $candidatos = [System.Collections.Generic.List[PSCustomObject]]::new()
    $hoje = Get-Date

    foreach ($p in $perfis) {
        if (Test-PerfilProtegido -Perfil $p -AdminSIDs $adminSIDs -AdminNames $adminNames -SnapshotNomes $snapshotNomes) {
            continue
        }

        $dataUso = $p.LastUseTime
        if (-not $dataUso) {
            try { $dataUso = (Get-Item -Path $p.LocalPath -ErrorAction SilentlyContinue).LastWriteTime } catch {}
        }

        if ($dataUso) {
            $dias = [math]::Floor(($hoje - $dataUso).TotalDays)
            if ($dias -ge 60) {
                $uName = Split-Path -Path $p.LocalPath -Leaf
                
                # Tamanho aproximado
                $tamStr = "calculando..."
                try {
                    $bytes = (Get-ChildItem -Path $p.LocalPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($bytes -ge 1GB) { $tamStr = "$([math]::Round($bytes / 1GB, 1)) GB" }
                    elseif ($bytes -ge 1MB) { $tamStr = "$([math]::Round($bytes / 1MB, 0)) MB" }
                    else { $tamStr = "< 1 MB" }
                } catch { $tamStr = "N/D" }

                $candidatos.Add([PSCustomObject]@{
                    Perfil      = $p
                    UserName    = $uName
                    Dias        = $dias
                    Tamanho     = $tamStr
                    Selecionado = $true
                })
            }
        }
    }

    if ($candidatos.Count -eq 0) {
        if (-not $SilenciosoSeVazio) {
            Write-Host " -> Nenhum perfil de aluno inativo (> 2 meses) encontrado." -ForegroundColor Green
            Write-Host "`nPressione Enter para voltar ao menu principal..."
            Read-Host
        } else {
            Write-Step -Text "Verificacao de perfis inativos (> 2 meses): Nenhum encontrado" -Status "OK"
        }
        return
    }

    # Alerta na tela
    Clear-Host
    Write-Host "=====================================================================" -ForegroundColor Yellow
    Write-Host "            AVISO: PERFIS DE USUARIOS INATIVOS ENCONTRADOS           " -ForegroundColor Yellow
    Write-Host "=====================================================================" -ForegroundColor Yellow
    Write-Host " Foram detectados $($candidatos.Count) perfil(is) de aluno inativo(s) ha mais de 2 meses (60 dias)." -ForegroundColor Yellow
    Write-Host " Administradores, BlueLab, alunos e contas da escola estao 100% protegidos." -ForegroundColor Green
    Write-Host "=====================================================================`n" -ForegroundColor Yellow
    Write-Host " [D] Deletar perfis inativos (Abre lista para selecionar com caixas [X])" -ForegroundColor Cyan
    Write-Host " [P] Prosseguir sem deletar (Manter todos os perfis intactos)`n" -ForegroundColor White

    $escolha = Read-Host " Escolha uma opcao [D/P]"
    if ($escolha -notmatch "^[dD]") {
        Write-Host "`n Prosseguindo sem alterar usuarios..." -ForegroundColor Gray
        Start-Sleep -Seconds 1
        return
    }

    # Tela Interativa de Selecao com [X]
    $loop = $true
    $selectedIndex = 0
    while ($loop) {
        Clear-Host
        Write-Host "=====================================================================" -ForegroundColor Cyan
        Write-Host "                SELECAO DE PERFIS INATIVOS PARA EXCLUSAO             " -ForegroundColor Cyan
        Write-Host "=====================================================================" -ForegroundColor Cyan
        Write-Host " Use as SETAS (Cima/Baixo) para navegar." -ForegroundColor Yellow
        Write-Host " Aperte ESPACO ou ENTER para marcar/desmarcar a opcao [X]:`n" -ForegroundColor Yellow

        for ($i = 0; $i -lt $candidatos.Count; $i++) {
            $prefix = if ($i -eq $selectedIndex) { " -> " } else { "    " }
            $check = if ($candidatos[$i].Selecionado) { "[X]" } else { "[ ]" }
            $uName = $candidatos[$i].UserName
            $dias = $candidatos[$i].Dias
            $tam = $candidatos[$i].Tamanho
            $texto = "[$($i + 1)] $check $uName (Inativo ha $dias dias | Espaco: $tam)"

            if ($i -eq $selectedIndex) {
                Write-Host "${prefix}${texto}" -ForegroundColor Green
            } else {
                if ($candidatos[$i].Selecionado) {
                    Write-Host "${prefix}${texto}" -ForegroundColor White
                } else {
                    Write-Host "${prefix}${texto}" -ForegroundColor DarkGray
                }
            }
        }

        Write-Host "`n Comandos Rapidos:" -ForegroundColor Cyan
        Write-Host "  [T] Marcar Todos    [N] Desmarcar Todos"
        Write-Host "  [E] EXECUTAR EXCLUSAO DOS MARCADOS" -ForegroundColor Red
        Write-Host "  [C] CANCELAR E VOLTAR (Nao excluir nada)`n" -ForegroundColor Gray

        $key = [Console]::ReadKey($true)
        $char = ""
        if ([int]$key.KeyChar -ne 0) { $char = $key.KeyChar.ToString().ToUpper() }

        switch ($key.Key) {
            'UpArrow' {
                $selectedIndex--
                if ($selectedIndex -lt 0) { $selectedIndex = $candidatos.Count - 1 }
            }
            'DownArrow' {
                $selectedIndex++
                if ($selectedIndex -ge $candidatos.Count) { $selectedIndex = 0 }
            }
            'Spacebar' {
                $candidatos[$selectedIndex].Selecionado = -not $candidatos[$selectedIndex].Selecionado
            }
            'Enter' {
                $candidatos[$selectedIndex].Selecionado = -not $candidatos[$selectedIndex].Selecionado
            }
        }

        switch ($char) {
            'T' { foreach ($c in $candidatos) { $c.Selecionado = $true } }
            'N' { foreach ($c in $candidatos) { $c.Selecionado = $false } }
            'C' {
                Write-Host "`n Operacao cancelada pelo usuario." -ForegroundColor Gray
                Start-Sleep -Seconds 1
                return
            }
            'E' {
                $paraExcluir = $candidatos | Where-Object { $_.Selecionado }
                if ($paraExcluir.Count -eq 0) {
                    Write-Host "`n Nenhum perfil selecionado para exclusao. Cancelando..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                    return
                }

                Write-Host "`n ATENCAO: Voce esta prestes a excluir $($paraExcluir.Count) perfil(is) permanentemente." -ForegroundColor Yellow
                $confirma = Read-Host " Confirma a exclusao definitiva? [S] Sim | [N] Nao"
                if ($confirma -match "^[sS]") {
                    Write-Host "`n Excluindo perfis selecionados..." -ForegroundColor Cyan
                    foreach ($item in $paraExcluir) {
                        try {
                            $item.Perfil | Remove-CimInstance -ErrorAction Stop
                            Write-Step -Text "Perfil '$($item.UserName)' removido com sucesso" -Status "OK"
                        } catch {
                            Write-Step -Text "Falha ao remover perfil '$($item.UserName)' ($($_.Exception.Message))" -Status "AVISO"
                        }
                    }
                    Write-Host "`n Exclusao concluida! Pressione Enter para prosseguir..." -ForegroundColor Green
                    Read-Host
                } else {
                    Write-Host "`n Exclusao cancelada pelo operador." -ForegroundColor Gray
                    Start-Sleep -Seconds 1
                }
                return
            }
        }
    }
}

# =====================================================================
# 4. FUNCOES DE EXECUCAO
# =====================================================================

function Executar-Tarefas {
    Clear-Host
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "                 INICIANDO APLICACAO DE MELHORIAS                    " -ForegroundColor Cyan
    Write-Host "=====================================================================" -ForegroundColor Cyan

    # Verificar perfis inativos ha mais de 2 meses (60 dias) com confirmacao/selecao
    Gerenciar-PerfisInativos -SilenciosoSeVazio

    # Ativar regra de manutencao automatica de perfis e registrar snapshot seguro
    Configurar-ManutencaoAgendadaPerfis

    # [01] Contas
    if ($global:opts[1]) {
        Write-Host "`n>> [01] Configurando Contas de Usuario..." -ForegroundColor Cyan
        try {
            $aluno = Get-LocalUser -Name "alunos" -ErrorAction SilentlyContinue
            if (-not $aluno) { New-LocalUser -Name "alunos" -NoPassword -UserMayNotChangePassword | Out-Null }
            Set-LocalUser -Name "alunos" -PasswordNeverExpires $true
            
            $userGroup = (Get-LocalGroup | Where-Object SID -eq 'S-1-5-32-545').Name
            if ($userGroup) { Add-LocalGroupMember -Group $userGroup -Member "alunos" -ErrorAction SilentlyContinue }

            # Obter o objeto e o SID da conta 'alunos'
            $alunoObj = Get-LocalUser -Name "alunos" -ErrorAction SilentlyContinue
            $alunoSID = if ($alunoObj) { $alunoObj.SID.Value } else { "" }

            Get-LocalUser -Name "anos_iniciais" -ErrorAction SilentlyContinue | Remove-LocalUser -ErrorAction SilentlyContinue
            Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -match "anos_iniciais" } | Remove-CimInstance -ErrorAction SilentlyContinue

            # 1. Forcar a exibicao de contas locais na tela de logon (mesmo em maquinas ingressadas em Dominio / Azure AD)
            $sysRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
            if (-not (Test-Path $sysRegPath)) { New-Item -Path $sysRegPath -Force | Out-Null }
            Set-ItemProperty -Path $sysRegPath -Name "EnumerateLocalUsers" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $sysRegPath -Name "EnumerateLocalUsersOnDomainJoinedComputers" -Value 1 -Type DWord -Force

            # 2. Desativar a politica que oculta o ultimo usuario logado (dontdisplaylastusername)
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name "dontdisplaylastusername" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $regPath -Name "HideFastUserSwitching" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            # 3. Ocultar administradores locais da tela de login, garantindo 'alunos' visivel
            $hideUsersPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList"
            if (-not (Test-Path $hideUsersPath)) { New-Item -Path $hideUsersPath -Force -ErrorAction SilentlyContinue | Out-Null }
            $usuariosOcultos = Get-LocalUser | Where-Object { $_.Name -ne "alunos" }
            foreach ($user in $usuariosOcultos) { Set-ItemProperty -Path $hideUsersPath -Name $user.Name -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue }
            Set-ItemProperty -Path $hideUsersPath -Name "alunos" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

            # 4. Apontar o LogonUI diretamente para o SID e nome de 'alunos'
            $logonUI = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
            if (Test-Path $logonUI) {
                Set-ItemProperty -Path $logonUI -Name "LastLoggedOnUser" -Value ".\alunos" -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $logonUI -Name "LastLoggedOnSAMUser" -Value "$env:COMPUTERNAME\alunos" -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $logonUI -Name "LastLoggedOnDisplayName" -Value "alunos" -Force -ErrorAction SilentlyContinue
                if ($alunoSID) {
                    Set-ItemProperty -Path $logonUI -Name "SelectedUserSID" -Value $alunoSID -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $logonUI -Name "LastLoggedOnUserSID" -Value $alunoSID -Force -ErrorAction SilentlyContinue
                }
                Set-ItemProperty -Path $logonUI -Name "LastLoggedOnProvider" -Value "{60B78E88-EAD8-445C-9CFD-0B87F74EA6CD}" -Force -ErrorAction SilentlyContinue
            }

            # 5. Fixar usuario padrao no Winlogon
            $winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
            if (Test-Path $winlogonPath) {
                Set-ItemProperty -Path $winlogonPath -Name "DefaultUserName" -Value "alunos" -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $winlogonPath -Name "DefaultDomainName" -Value "." -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $winlogonPath -Name "AltDefaultUserName" -Value "alunos" -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $winlogonPath -Name "AltDefaultDomainName" -Value "." -Force -ErrorAction SilentlyContinue
            }

            Write-Step -Text "Conta 'alunos' configurada e fixada no LogonUI com sucesso" -Status "OK"

            # 6. Registrar Snapshot de contas seguras e agendar manutencao semanal de perfis de alunos
            Configurar-ManutencaoAgendadaPerfis
        } catch { Write-Step -Text "Erro ao configurar contas ($($_.Exception.Message))" -Status "FALHA" }
    }

    # [02] Energia
    if ($global:opts[2]) {
        Write-Host "`n>> [02] Ajustando Politicas de Energia..." -ForegroundColor Cyan
        try {
            # Limpa tarefa legada de desligamento se existir
            schtasks /delete /tn "DesligamentoInativo30m" /f 2>$null | Out-Null

            powercfg /change monitor-timeout-ac 10 | Out-Null
            powercfg /change monitor-timeout-dc 10 | Out-Null
            powercfg /change standby-timeout-ac 20 | Out-Null
            powercfg /change standby-timeout-dc 20 | Out-Null
            powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 3 | Out-Null
            powercfg /setdcvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 3 | Out-Null
            powercfg /setactive SCHEME_CURRENT | Out-Null
            powercfg /hibernate off | Out-Null
            Write-Step -Text "Acao de tampa (Desligar) definida e Hibernacao desativada" -Status "OK"
        } catch { Write-Step -Text "Erro na configuracao de energia" -Status "FALHA" }
    }

    # [03] Desempenho e Recursos do Sistema (CPU/RAM, WSearch, Feeds, Limpeza)
    if ($global:opts[3]) {
        Write-Host "`n>> [03] Otimizando Desempenho de CPU/RAM, Disco e Limpeza..." -ForegroundColor Cyan
        
        $errosOtimizacao = 0

        # 3.1 - GameDVR
        try {
            $gameDVR = "HKCU:\System\GameConfigStore"
            if (Test-Path $gameDVR) { Set-ItemProperty -Path $gameDVR -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue }
            $gameBar = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
            if (-not (Test-Path $gameBar)) { New-Item -Path $gameBar -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $gameBar -Name "AllowGameDVR" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Step -Text "  [3.1] Desativar GameDVR e gravacoes em segundo plano" -Status "OK"
        } catch { $errosOtimizacao++; Write-Step -Text "  [3.1] Falha ao desativar GameDVR" -Status "AVISO" }

        # 3.2 - Servicos pesados em background (Telemetria, SysMain/Superfetch e WSearch)
        try {
            Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue

            # Garante que o servico de busca (WSearch) esteja ativo para indexar aplicativos locais do Windows
            Set-Service -Name "WSearch" -StartupType Automatic -ErrorAction SilentlyContinue
            if ((Get-Service -Name "WSearch" -ErrorAction SilentlyContinue).Status -ne 'Running') {
                Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
            }

            # Servicos ociosos desnecessarios para ambiente escolar
            $idleServices = @("MapsBroker", "Fax", "XblAuthManager", "XblGameSave", "XboxNetApiSvc")
            foreach ($srv in $idleServices) {
                Stop-Service -Name $srv -Force -ErrorAction SilentlyContinue
                Set-Service -Name $srv -StartupType Disabled -ErrorAction SilentlyContinue
            }
            Write-Step -Text "  [3.2] Desativar servicos pesados (SysMain, Telemetria)" -Status "OK"
        } catch { $errosOtimizacao++; Write-Step -Text "  [3.2] Falha ao configurar servicos de background" -Status "AVISO" }

        # 3.3 - Telemetria GPO
        try {
            $telemetryReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
            if (-not (Test-Path $telemetryReg)) { New-Item -Path $telemetryReg -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $telemetryReg -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Step -Text "  [3.3] Desativar telemetria do Windows via Registro" -Status "OK"
        } catch { $errosOtimizacao++; Write-Step -Text "  [3.3] Falha ao desativar telemetria" -Status "AVISO" }

        # 3.4 - Desativar Feeds / Noticias e Interesses
        try {
            $widgetReg = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
            if (-not (Test-Path $widgetReg)) { New-Item -Path $widgetReg -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $widgetReg -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            $feedsUser = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
            if (-not (Test-Path $feedsUser)) { New-Item -Path $feedsUser -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $feedsUser -Name "ShellFeedsTaskbarViewMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Step -Text "  [3.4] Desativar Feeds de noticias e Widgets" -Status "OK"
        } catch { $errosOtimizacao++; Write-Step -Text "  [3.4] Falha ao desativar Feeds e Widgets" -Status "AVISO" }

        # 3.5 - Desativar Edge em segundo plano e Startup Boost
        try {
            $edgeReg = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
            if (-not (Test-Path $edgeReg)) { New-Item -Path $edgeReg -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $edgeReg -Name "BackgroundModeEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $edgeReg -Name "StartupBoostEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            # Desativar Edge na aba Inicializar do Gerenciador de Tarefas
            $saBytes = [byte[]]@(0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
            $saPaths = @(
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
            )
            foreach ($sa in $saPaths) {
                if (-not (Test-Path $sa)) { New-Item -Path $sa -Force -ErrorAction SilentlyContinue | Out-Null }
                if (Test-Path $sa) {
                    Set-ItemProperty -Path $sa -Name "MicrosoftEdgeAutoLaunch" -Value $saBytes -Type Binary -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $sa -Name "Microsoft Edge" -Value $saBytes -Type Binary -Force -ErrorAction SilentlyContinue
                }
            }
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "MicrosoftEdgeAutoLaunch" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "MicrosoftEdgeAutoLaunch" -ErrorAction SilentlyContinue
            Write-Step -Text "  [3.5] Cortar Edge em 2 plano e inicializacao automatica" -Status "OK"
        } catch { $errosOtimizacao++; Write-Step -Text "  [3.5] Falha ao desativar Edge em segundo plano" -Status "AVISO" }

        # 3.6 - Bloquear download de apps patrocinados e Remover bloatwares
        try {
            # 1. Bloquear download e reinstalacao automatica de apps de consumo
            $cloudReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
            if (-not (Test-Path $cloudReg)) { New-Item -Path $cloudReg -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $cloudReg -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

            # 2. Desativar sugestoes e instalacao silenciosa no ContentDeliveryManager
            $contentDelivery = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            if (-not (Test-Path $contentDelivery)) { New-Item -Path $contentDelivery -Force -ErrorAction SilentlyContinue | Out-Null }
            if (Test-Path $contentDelivery) {
                Set-ItemProperty -Path $contentDelivery -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $contentDelivery -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $contentDelivery -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            }

            # 3. Remover bloatwares instalados (apenas pacotes removiveis, ignorando componentes de sistema)
            $ProgressPreference = 'SilentlyContinue'
            $bloatList = @(
                "Microsoft.MicrosoftSolitaireCollection",
                "Microsoft.XboxApp",
                "Microsoft.GamingApp",
                "*Spotify*",
                "*TikTok*",
                "*Instagram*",
                "*Facebook*",
                "*Disney*"
            )

            foreach ($appName in $bloatList) {
                try {
                    $pkgs = Get-AppxPackage -Name $appName -ErrorAction SilentlyContinue | Where-Object { -not $_.NonRemovable }
                    if ($pkgs) {
                        foreach ($p in $pkgs) {
                            try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction SilentlyContinue } catch {}
                        }
                    }
                } catch {}
            }

            # 4. Remover pacotes provisionados (para novos usuarios nao receberem bloatware)
            try {
                $provList = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                if ($provList) {
                    foreach ($appName in $bloatList) {
                        $matched = $provList | Where-Object { $_.DisplayName -like $appName }
                        foreach ($m in $matched) {
                            try { Remove-AppxProvisionedPackage -Online -PackageName $m.PackageName -ErrorAction SilentlyContinue | Out-Null } catch {}
                        }
                    }
                }
            } catch {}

            Write-Step -Text "  [3.6] Remover bloatwares e sugestoes do Windows" -Status "OK"
        } catch { $errosOtimizacao++; Write-Step -Text "  [3.6] Falha ao remover bloatwares e apps patrocinados" -Status "AVISO" }

        # 3.7 - Transparencia e Efeitos Visuais
        try {
            $themeReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            if (Test-Path $themeReg) { Set-ItemProperty -Path $themeReg -Name "EnableTransparency" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue }
            $themeRegLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            if (Test-Path $themeRegLM) { Set-ItemProperty -Path $themeRegLM -Name "EnableTransparency" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue }

            $visualReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
            if (Test-Path $visualReg) { Set-ItemProperty -Path $visualReg -Name "VisualFXSetting" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue }
            Write-Step -Text "  [3.7] Desativar transparencia e efeitos graficos pesados" -Status "OK"
        } catch { $errosOtimizacao++; Write-Step -Text "  [3.7] Falha ao desativar transparencia grafica" -Status "AVISO" }

        # 3.8 - Limpeza segura de arquivos temporarios e caches do sistema
        try {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            
            # Limpeza segura do Windows (sem tocar em pastas de usuarios nem perfis AD)
            $sysPaths = @(
                "$env:TEMP\*",
                "C:\Windows\Temp\*",
                "C:\Windows\Prefetch\*",
                "C:\Windows\SoftwareDistribution\Download\*",
                "C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*",
                "C:\ProgramData\Microsoft\Windows\WER\ReportQueue\*",
                "C:\Windows\System32\Spool\Printers\*"
            )
            foreach ($path in $sysPaths) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
            Write-Step -Text "  [3.8] Limpeza segura de caches e temporarios do sistema" -Status "OK"
        } catch { $errosOtimizacao++; Write-Step -Text "  [3.8] Falha na limpeza de temporarios do sistema" -Status "AVISO" }

        if ($errosOtimizacao -eq 0) {
            Write-Step -Text "Todos os 8 modulos de desempenho foram concluidos com sucesso" -Status "OK"
        } else {
            Write-Step -Text "Otimizacao concluida com $errosOtimizacao aviso(s) apontados acima" -Status "AVISO"
        }
    }

    # [04] OneDrive
    if ($global:opts[4]) {
        Write-Host "`n>> [04] Cortando inicializacao do OneDrive (Mantendo Teams)..." -ForegroundColor Cyan
        try {
            $odReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
            if (-not (Test-Path $odReg)) { New-Item -Path $odReg -Force | Out-Null }
            Set-ItemProperty -Path $odReg -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
            Write-Step -Text "OneDrive desativado com sucesso" -Status "OK"
        } catch { Write-Step -Text "Erro ao desativar OneDrive" -Status "FALHA" }
    }

    # [05] Windows Update
    if ($global:opts[5]) {
        Write-Host "`n>> [05] Definindo Horario Ativo (07h as 18h)..." -ForegroundColor Cyan
        try {
            $wuReg = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            if (-not (Test-Path $wuReg)) { New-Item -Path $wuReg -Force | Out-Null }
            Set-ItemProperty -Path $wuReg -Name "ActiveHoursStart" -Value 7 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $wuReg -Name "ActiveHoursEnd" -Value 18 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $wuReg -Name "SmartActiveHoursState" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Step -Text "Horario de Update definido para fora das aulas" -Status "OK"
        } catch { Write-Step -Text "Erro ao definir horario de Update" -Status "FALHA" }
    }

    # [06] Bloquear Apps, Jogos e VPNs
    if ($global:opts[6]) {
        Write-Host "`n>> [06] Aplicando Travas contra Jogos, Navegadores Paralelos e VPNs..." -ForegroundColor Cyan
        try {
            $appsBloquear = @(
                # Emuladores e Jogos (Roblox, Minecraft, Google Play Games)
                "GooglePlayGamesSetup.exe", "Bootstrapper.exe", "currentuserbootstrapper.exe", "GooglePlayGames.exe", "crosvm.exe", "ServiceAgent.exe",
                "Minecraft.Windows.exe", "MinecraftEducation.exe", "MinecraftEducationInstaller.exe",
                "RobloxPlayerBeta.exe", "RobloxPlayerInstaller.exe", "RobloxPlayerLauncher.exe", "RobloxStudioLauncherBeta.exe",
                # Navegadores nao homologados
                "OperaSetup.exe", "OperaGXSetup.exe", "BraveBrowserSetup.exe",
                # VPNs e Proxies populares (UltraSurf, Psiphon, Proton, etc.)
                "u.exe", "ultrasurf.exe",
                "ProtonVPN_Setup.exe", "ProtonVPN.exe", "Windscribe_windows.exe", "Windscribe.exe",
                "TunnelBear-Installer.exe", "TunnelBear.exe", "HotspotShield-install.exe", "HotspotShield.exe",
                "Psiphon3.exe", "UrbanVPN.exe", "TouchVPN.exe", "NordVPN.exe", "NordVPN-Setup.exe",
                "ExpressVPN.exe", "expressvpn_setup.exe", "OpenVPN.exe", "openvpn-install.exe",
                "WireGuard.exe", "wireguard-installer.exe", "CloudflareWARP.exe", "warp.exe",
                "HideMe.exe", "Speedify.exe"
            )
            foreach ($app in $appsBloquear) {
                $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$app"
                if (-not (Test-Path $ifeoPath)) { New-Item -Path $ifeoPath -Force | Out-Null }
                Set-ItemProperty -Path $ifeoPath -Name "Debugger" -Value "rundll32.exe" -Force -ErrorAction SilentlyContinue
            }

            # Bloqueio de criacao e configuracao de VPN nativa no Windows via Politicas de Rede
            $netPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections"
            if (-not (Test-Path $netPol)) { New-Item -Path $netPol -Force | Out-Null }
            Set-ItemProperty -Path $netPol -Name "NC_NewConnectionWizard" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $netPol -Name "NC_RasUserConfig" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $netPol -Name "NC_RasAllUserConfig" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $netPol -Name "NC_RasConnect" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            # Ocultar pagina de configuracao de VPN nas Configuracoes do Windows
            $explorerPol = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
            if (-not (Test-Path $explorerPol)) { New-Item -Path $explorerPol -Force | Out-Null }
            Set-ItemProperty -Path $explorerPol -Name "SettingsPageVisibility" -Value "hide:network-vpn" -Type String -Force -ErrorAction SilentlyContinue

            # Desativar servico de conexao de acesso remoto e VPN nativa (RasMan)
            Stop-Service -Name "RasMan" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "RasMan" -StartupType Disabled -ErrorAction SilentlyContinue

            Write-Step -Text "Apps bloqueados (Roblox, Minecraft, GPlay) e uso de VPNs travado" -Status "OK"
        } catch { Write-Step -Text "Erro ao aplicar travas de aplicativos e VPNs" -Status "FALHA" }
    }

    # [07] Store
    if ($global:opts[7]) {
        Write-Host "`n>> [07] Bloqueando Microsoft Store..." -ForegroundColor Cyan
        try {
            $storeReg = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
            if (-not (Test-Path $storeReg)) { New-Item -Path $storeReg -Force | Out-Null }
            # Bloqueia apenas o aplicativo da Loja (impede abrir a loja e baixar apps novos)
            Set-ItemProperty -Path $storeReg -Name "RemoveWindowsStore" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            
            # Remove a trava que bloqueava a Calculadora, Bloco de Notas, Fotos e utilitarios essenciais do Windows
            Remove-ItemProperty -Path $storeReg -Name "DisableStoreApps" -ErrorAction SilentlyContinue
            
            Write-Step -Text "Loja do Windows bloqueada (Calculadora e apps do sistema liberados)" -Status "OK"
        } catch { Write-Step -Text "Erro ao bloquear Store" -Status "FALHA" }
    }

    # [08] Atalhos
    if ($global:opts[8]) {
        Write-Host "`n>> [08] Protegendo Atalhos da Area de Trabalho..." -ForegroundColor Cyan
        try {
            $publicDesktop = "C:\Users\Public\Desktop"
            if (Test-Path $publicDesktop) {
                icacls $publicDesktop /grant "BUILTIN\Users:(OI)(CI)(W,RC)" /C /Q | Out-Null
                icacls "$publicDesktop\*" /deny "BUILTIN\Users:(DE)" /C /Q | Out-Null
                Write-Step -Text "Exclusao de atalhos bloqueada (Criacao permitida)" -Status "OK"
            } else { Write-Step -Text "Pasta Public\Desktop nao encontrada" -Status "AVISO" }
        } catch { Write-Step -Text "Erro ao configurar NTFS nos atalhos" -Status "FALHA" }
    }

    # [09] NetTime
    if ($global:opts[9]) {
        Write-Host "`n>> [09] Sincronizacao de Data e Hora (NetTime)..." -ForegroundColor Cyan
        try {
            # 1. Verifica se o NetTime ja esta instalado na maquina
            $servicoExistente = Get-Service -Name "NetTime" -ErrorAction SilentlyContinue
            $exeExistente = (Test-Path "${env:ProgramFiles(x86)}\NetTime\NetTime.exe") -or (Test-Path "$env:ProgramFiles\NetTime\NetTime.exe")

            if ($servicoExistente -or $exeExistente) {
                Write-Host " -> NetTime ja esta instalado nesta maquina. Pulando download/instalador..." -ForegroundColor Yellow
                
                # Desativa o w32time nativo para evitar conflito de horario
                Stop-Service -Name "w32time" -Force -ErrorAction SilentlyContinue
                Set-Service -Name "w32time" -StartupType Disabled -ErrorAction SilentlyContinue

                # Garante que o servico NetTime esteja ativo e em inicializacao automatica
                if ($servicoExistente) {
                    Set-Service -Name "NetTime" -StartupType Automatic -ErrorAction SilentlyContinue
                    if ($servicoExistente.Status -ne 'Running') {
                        Start-Service -Name "NetTime" -ErrorAction SilentlyContinue
                    }
                    Write-Step -Text "NetTime ja instalado e ativo como servico (w32time desativado)" -Status "OK"
                } else {
                    Write-Step -Text "NetTime ja instalado na maquina" -Status "OK"
                }
            } else {
                # 2. Se nao estiver instalado, prossegue com instalacao local ou via Web
                $instaladorFinal = ""
                $tempInstaller = "$env:TEMP\NetTimeSetup-314.exe"

                # Verifica se o instalador existe localmente (pendrive ou pasta do script)
                $localInstaller = if ($PSScriptRoot) { Join-Path $PSScriptRoot "NetTimeSetup-314.exe" } else { "" }
                if ($localInstaller -and (Test-Path $localInstaller)) {
                    Write-Host " -> Instalador local detectado (pendrive/pasta)." -ForegroundColor Green
                    $instaladorFinal = $localInstaller
                } else {
                    Write-Host " -> Baixando NetTime da internet..." -NoNewline
                    $url = "http://www.timesynctool.com/NetTimeSetup-314.exe"
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
                    try {
                        Invoke-WebRequest -Uri $url -OutFile $tempInstaller -UseBasicParsing -ErrorAction Stop
                    } catch {
                        (New-Object Net.WebClient).DownloadFile($url, $tempInstaller)
                    }
                    Write-Host " [Download OK]" -ForegroundColor Green
                    $instaladorFinal = $tempInstaller
                }

                if ($instaladorFinal -and (Test-Path $instaladorFinal)) {
                    # Finaliza processos anteriores e desativa o servico legado w32time
                    Stop-Service -Name "NetTime" -Force -ErrorAction SilentlyContinue
                    Stop-Process -Name "NetTime*" -Force -ErrorAction SilentlyContinue
                    Stop-Service -Name "w32time" -Force -ErrorAction SilentlyContinue
                    Set-Service -Name "w32time" -StartupType Disabled -ErrorAction SilentlyContinue

                    # Execucao silenciosa com Inno Setup
                    $argumentos = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"
                    $processo = Start-Process -FilePath $instaladorFinal -ArgumentList $argumentos -PassThru
                    
                    $limite = 20
                    while (-not $processo.HasExited -and $limite -gt 0) {
                        Start-Sleep -Seconds 1
                        $limite--
                    }
                    if (-not $processo.HasExited) {
                        Stop-Process -Id $processo.Id -Force -ErrorAction SilentlyContinue
                    }

                    Start-Sleep -Seconds 2
                    $servico = Get-Service -Name "NetTime" -ErrorAction SilentlyContinue
                    if ($servico) {
                        Set-Service -Name "NetTime" -StartupType Automatic -ErrorAction SilentlyContinue
                        if ($servico.Status -ne 'Running') {
                            Start-Service -Name "NetTime" -ErrorAction SilentlyContinue
                        }
                        Write-Step -Text "NetTime instalado e ativo como servico (w32time desativado)" -Status "OK"
                    } else {
                        Write-Step -Text "NetTime instalado, mas servico nao iniciou automaticamente" -Status "AVISO"
                    }

                    if (Test-Path $tempInstaller) { Remove-Item -Path $tempInstaller -Force -ErrorAction SilentlyContinue }
                } else {
                    Write-Step -Text "Instalador do NetTime nao encontrado" -Status "FALHA"
                }
            }
        } catch { Write-Step -Text "Falha na sincronizacao do NetTime ($($_.Exception.Message))" -Status "FALHA" }
    }

    # [10] Desativar Busca Web no Menu Iniciar (Bing / Cortana)
    if ($global:opts[10]) {
        Write-Host "`n>> [10] Desativando Busca Web (Bing) para TODOS os Perfis (alunos, adm e novos)..." -ForegroundColor Cyan
        try {
            # 1. Politicas Globais de Maquina (HKLM) - Valem para qualquer usuario que logar
            $searchPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
            if (-not (Test-Path $searchPolicy)) { New-Item -Path $searchPolicy -Force | Out-Null }
            Set-ItemProperty -Path $searchPolicy -Name "DisableWebSearch" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $searchPolicy -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $searchPolicy -Name "ConnectedSearchUseWebOverMeteredConnections" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $searchPolicy -Name "AllowCortana" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            $explorerPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
            if (-not (Test-Path $explorerPolicy)) { New-Item -Path $explorerPolicy -Force | Out-Null }
            Set-ItemProperty -Path $explorerPolicy -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

            $searchSettingsLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings"
            if (-not (Test-Path $searchSettingsLM)) { New-Item -Path $searchSettingsLM -Force | Out-Null }
            Set-ItemProperty -Path $searchSettingsLM -Name "IsBingSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            # Funcao interna para aplicar as chaves do usuario em qualquer hive carregada
            $aplicarHive = {
                param([string]$basePath)
                try {
                    $k1 = "$basePath\Software\Microsoft\Windows\CurrentVersion\Search"
                    if (-not (Test-Path $k1)) { New-Item -Path $k1 -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -Path $k1 -Name "BingSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $k1 -Name "CortanaConsent" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

                    $k2 = "$basePath\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
                    if (-not (Test-Path $k2)) { New-Item -Path $k2 -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -Path $k2 -Name "IsBingSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

                    $k3 = "$basePath\Software\Policies\Microsoft\Windows\Explorer"
                    if (-not (Test-Path $k3)) { New-Item -Path $k3 -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -Path $k3 -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                } catch {}
            }

            # 2. Aplica no usuario atual logado (HKCU)
            & $aplicarHive "HKCU:"

            # 3. Aplica em todos os perfis de usuario atualmente carregados no Windows (HKU)
            Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match "^S-1-5-21-" -and $_.PSChildName -notmatch "_Classes" } | ForEach-Object {
                & $aplicarHive "Registry::HKEY_USERS\$($_.PSChildName)"
            }

            # 4. Injeta no perfil modelo C:\Users\Default e no C:\Users\alunos (se existirem no disco)
            $hivesOffline = @("C:\Users\Default\NTUSER.DAT")
            $alunosDat = "C:\Users\alunos\NTUSER.DAT"
            if (Test-Path $alunosDat) { $hivesOffline += $alunosDat }

            foreach ($dat in $hivesOffline) {
                if (Test-Path $dat) {
                    $hiveName = "TempHiveSearch_" + (Get-Random)
                    reg load "HKU\$hiveName" "$dat" 2>$null | Out-Null
                    if (Test-Path "Registry::HKEY_USERS\$hiveName") {
                        & $aplicarHive "Registry::HKEY_USERS\$hiveName"
                        [GC]::Collect()
                        [GC]::WaitForPendingFinalizers()
                        reg unload "HKU\$hiveName" 2>$null | Out-Null
                    }
                }
            }

            # 5. Reinicia os processos visuais de busca para aplicar instantaneamente
            Stop-Process -Name "SearchApp", "SearchHost", "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue

            Write-Step -Text "Busca Web/Bing bloqueada para perfil alunos, novos e sistema" -Status "OK"
        } catch { Write-Step -Text "Erro ao configurar busca do Windows ($($_.Exception.Message))" -Status "FALHA" }
    }



    Write-Host "`n=====================================================================" -ForegroundColor Green
    Write-Host "                    CONCLUIDO COM SUCESSO!                           " -ForegroundColor Green
    Write-Host "=====================================================================" -ForegroundColor Green
    Write-Host "Log salvo em: $LogFile" -ForegroundColor DarkGray
    Write-Host "Pressione Enter para voltar ao menu principal..."
    Read-Host
}

# =====================================================================
# 4. FUNCOES AUXILIARES E MENUS
# =====================================================================

function Liberar-ParticaoRecovery {
    Clear-Host
    Write-Host "=====================================================================" -ForegroundColor Yellow
    Write-Host "               LIBERAR ESPACO DA PARTICAO DE RECUPERACAO             " -ForegroundColor Yellow
    Write-Host "=====================================================================" -ForegroundColor Yellow
    if ($is32GB) {
        Write-Host " Armazenamento detectado: $diskSizeGB GB (Espaco critico de 32GB)." -ForegroundColor Red
    } else {
        Write-Host " Armazenamento detectado: $diskSizeGB GB (Livre: $freeSpace GB)." -ForegroundColor Green
    }
    Write-Host "`n ATENCAO: Esta operacao ira excluir a particao de recuperacao OEM de fabrica" -ForegroundColor Yellow
    Write-Host " e estender o disco C: para liberar mais espaco de armazenamento livre.`n" -ForegroundColor Yellow
    
    $confirm = Read-Host " Deseja realmente prosseguir? [S] Sim | [N] Cancelar"
    if ($confirm -match "^[sS]") {
        Write-Host "`n -> Localizando e removendo particao de recuperacao..." -ForegroundColor Cyan
        try {
            $sysPart = Get-Partition -DriveLetter ($env:SystemDrive.Trim(':'))
            $recoveryParts = Get-Partition -DiskNumber $sysPart.DiskNumber | Where-Object { $_.Type -match "Recovery" -or $_.GptType -match "Recovery" }
            $removed = $false
            foreach ($rp in $recoveryParts) {
                if ($rp.Offset -gt $sysPart.Offset) {
                    Remove-Partition -DiskNumber $rp.DiskNumber -PartitionNumber $rp.PartitionNumber -Confirm:$false -ErrorAction Stop
                    $removed = $true
                }
            }
            if ($removed) {
                $maxSize = (Get-PartitionSupportedSize -DriveLetter ($env:SystemDrive.Trim(':'))).SizeMax
                Resize-Partition -DriveLetter ($env:SystemDrive.Trim(':')) -Size $maxSize -ErrorAction Stop
                Write-Step -Text "Particao de recuperacao excluida e disco C: estendido com sucesso" -Status "OK"
            } else {
                Write-Step -Text "Nenhuma particao de recuperacao apta a exclusao encontrada" -Status "AVISO"
            }
        } catch {
            Write-Step -Text "Falha ao manipular particoes do disco ($($_.Exception.Message))" -Status "FALHA"
        }
    } else {
        Write-Host "`n Operacao cancelada pelo usuario." -ForegroundColor Gray
    }
    Write-Host "`nPressione Enter para voltar ao menu principal..."
    Read-Host
}

function Mostrar-Diagnostico {
    Clear-Host
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "                 DIAGNOSTICO DE HARDWARE E SISTEMA                   " -ForegroundColor Cyan
    Write-Host "=====================================================================" -ForegroundColor Cyan
    
    Write-Host "Sistema Operacional: " -NoNewline; Write-Host $osName -ForegroundColor Yellow
    Write-Host "Processador:         " -NoNewline
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name
    Write-Host $cpu -ForegroundColor Yellow
    Write-Host "Memoria RAM:         " -NoNewline; Write-Host "$ramGB GB" -ForegroundColor Yellow
    
    # Tempo de Atividade (Uptime)
    Write-Host "`nTempo de Atividade (Uptime):"
    try {
        $lastBoot = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
        if ($lastBoot) {
            $uptime = (Get-Date) - $lastBoot
            $uptimeStr = "{0} dias, {1} horas e {2} minutos" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
            Write-Host " -> Ligado ha:            $uptimeStr" -ForegroundColor Yellow
            Write-Host " -> Ultima Inicializacao: $(Get-Date $lastBoot -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor DarkGray
        } else {
            Write-Host " -> Informacoes de Uptime indisponiveis." -ForegroundColor DarkGray
        }
    } catch {
        Write-Host " -> Nao foi possivel obter o Uptime." -ForegroundColor DarkGray
    }

    # Temperatura da CPU / Notebook
    Write-Host "`nTemperatura do Processador / Notebook:"
    $celsius = $null
    $tempObj = Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
    if ($tempObj) {
        $curK = ($tempObj | Select-Object -First 1).CurrentTemperature
        if ($curK -gt 2732) {
            $celsius = [math]::Round(($curK - 2732) / 10, 1)
        }
    }
    if (-not $celsius) {
        $perfTemp = Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($perfTemp -and $perfTemp.Temperature -gt 273) {
            $celsius = [math]::Round($perfTemp.Temperature - 273.15, 1)
        }
    }
    if ($celsius) {
        $tempColor = if ($celsius -gt 80) { "Red" } elseif ($celsius -gt 65) { "Yellow" } else { "Green" }
        Write-Host " -> Temperatura Atual da CPU: $celsius °C" -ForegroundColor $tempColor
    } else {
        Write-Host " -> Sensor ACPI termico:      Nao exposto diretamente pela BIOS/Fabricante" -ForegroundColor DarkGray
    }

    # Armazenamento e Saude do SSD / M.2 / eMMC
    Write-Host "`nArmazenamento e Saude dos Discos (SSD / M.2 / eMMC):"
    $pDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($pDisks) {
        foreach ($pd in $pDisks) {
            $media = if ($pd.MediaType) { $pd.MediaType } else { "Armazenamento" }
            $health = $pd.HealthStatus
            $status = $pd.OperationalStatus
            $healthColor = if ($health -eq "Healthy") { "Green" } else { "Red" }
            $sizeGB = [math]::Round($pd.Size / 1GB, 1)
            Write-Host " -> $($pd.FriendlyName) [$media - $sizeGB GB]: Saude = $health ($status)" -ForegroundColor $healthColor

            $counters = $pd | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            if ($counters) {
                if ($null -ne $counters.Wear -and $counters.Wear -ge 0) {
                    $wearColor = if ($counters.Wear -gt 80) { "Red" } elseif ($counters.Wear -gt 50) { "Yellow" } else { "Green" }
                    Write-Host "    Vida Util Consumida (Desgaste): $($counters.Wear)%" -ForegroundColor $wearColor
                }
                if ($null -ne $counters.Temperature -and $counters.Temperature -gt 0) {
                    Write-Host "    Temperatura do SSD/M.2:        $($counters.Temperature) °C" -ForegroundColor Cyan
                }
                if ($null -ne $counters.ReadErrorsTotal -and ($counters.ReadErrorsTotal -gt 0 -or $counters.WriteErrorsTotal -gt 0)) {
                    Write-Host "    Erros de Leitura / Gravacao:    $($counters.ReadErrorsTotal) / $($counters.WriteErrorsTotal)" -ForegroundColor Red
                }
            }
        }
    } else {
        $disks = Get-Disk
        foreach ($d in $disks) {
            $size = [math]::Round($d.Size / 1GB, 1)
            Write-Host " -> Disco $($d.Number): $($d.FriendlyName) ($size GB) - Status: $($d.HealthStatus)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`nStatus da Bateria:"
    $battery = Get-WmiObject -Class BatteryStatus -Namespace root\wmi -ErrorAction SilentlyContinue
    $battInfo = Get-WmiObject -Class BatteryFullCapacity -Namespace root\wmi -ErrorAction SilentlyContinue
    $battStatic = Get-WmiObject -Class BatteryStaticData -Namespace root\wmi -ErrorAction SilentlyContinue
    
    if ($battInfo -and $battStatic) {
        $full = $battInfo.FullChargeCapacity
        $design = $battStatic.DesignedCapacity
        if ($design -gt 0) {
            $wear = 100 - [math]::Round(($full / $design) * 100, 1)
            Write-Host " -> Capacidade de Fabrica: $design mWh"
            Write-Host " -> Carga Maxima Atual:    $full mWh"
            if ($wear -gt 30) {
                Write-Host " -> Desgaste da Bateria:   $wear% (BATERIA VICIADA/FRACA)" -ForegroundColor Red
            } else {
                Write-Host " -> Desgaste da Bateria:   $wear% (Saudavel)" -ForegroundColor Green
            }
        }
    } else {
        Write-Host " -> Bateria nao detectada ou sem suporte ao WMI neste modelo." -ForegroundColor DarkGray
    }
    
    Write-Host "`n=====================================================================" -ForegroundColor Cyan
    Write-Host "Pressione Enter para voltar ao menu principal..."
    Read-Host
}

function Desfazer-Alteracoes {
    Clear-Host
    Write-Host "=====================================================================" -ForegroundColor Yellow
    Write-Host "                  DESFAZENDO ALTERACOES (REVERTER)                   " -ForegroundColor Yellow
    Write-Host "=====================================================================" -ForegroundColor Yellow
    Write-Host "Restaurando PC ao padrao original..." -ForegroundColor Cyan
    
    # Energia
    powercfg /change monitor-timeout-ac 15 | Out-Null
    powercfg /change monitor-timeout-dc 15 | Out-Null
    powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 1 | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 1 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    powercfg /hibernate on | Out-Null
    
    # Desempenho e Servicos (DiagTrack, SysMain, WSearch)
    $gameBar = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (Test-Path $gameBar) { Remove-ItemProperty -Path $gameBar -Name "AllowGameDVR" -ErrorAction SilentlyContinue }
    Set-Service -Name "DiagTrack" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "DiagTrack" -ErrorAction SilentlyContinue
    Set-Service -Name "SysMain" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "SysMain" -ErrorAction SilentlyContinue
    Set-Service -Name "WSearch" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
    
    $idleServices = @("MapsBroker", "Fax", "XblAuthManager", "XblGameSave", "XboxNetApiSvc")
    foreach ($srv in $idleServices) {
        Set-Service -Name "srv" -StartupType Manual -ErrorAction SilentlyContinue
    }

    $telemetryReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (Test-Path $telemetryReg) { Remove-ItemProperty -Path $telemetryReg -Name "AllowTelemetry" -ErrorAction SilentlyContinue }
    
    # Feeds e Edge
    $widgetReg = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (Test-Path $widgetReg) { Remove-ItemProperty -Path $widgetReg -Name "AllowNewsAndInterests" -ErrorAction SilentlyContinue }
    $feedsUser = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
    if (Test-Path $feedsUser) { Remove-ItemProperty -Path $feedsUser -Name "ShellFeedsTaskbarViewMode" -ErrorAction SilentlyContinue }
    $edgeReg = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (Test-Path $edgeReg) {
        Remove-ItemProperty -Path $edgeReg -Name "BackgroundModeEnabled" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $edgeReg -Name "StartupBoostEnabled" -ErrorAction SilentlyContinue
    }
    foreach ($sa in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run")) {
        if (Test-Path $sa) {
            Remove-ItemProperty -Path $sa -Name "MicrosoftEdgeAutoLaunch" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $sa -Name "Microsoft Edge" -ErrorAction SilentlyContinue
        }
    }
    
    # Busca Web / Bing
    $searchPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (Test-Path $searchPolicy) {
        Remove-ItemProperty -Path $searchPolicy -Name "DisableWebSearch" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $searchPolicy -Name "ConnectedSearchUseWeb" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $searchPolicy -Name "AllowCortana" -ErrorAction SilentlyContinue
    }
    $userSearch = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    if (Test-Path $userSearch) {
        Remove-ItemProperty -Path $userSearch -Name "BingSearchEnabled" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $userSearch -Name "CortanaConsent" -ErrorAction SilentlyContinue
    }
    $userSearchPol = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    if (Test-Path $userSearchPol) {
        Remove-ItemProperty -Path $userSearchPol -Name "DisableSearchBoxSuggestions" -ErrorAction SilentlyContinue
    }
    if (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings") {
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsBingSearchEnabled" -ErrorAction SilentlyContinue
    }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings") {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsBingSearchEnabled" -ErrorAction SilentlyContinue
    }

    # Transparencia
    $themeReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (Test-Path $themeReg) { Set-ItemProperty -Path $themeReg -Name "EnableTransparency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue }
    $themeRegLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (Test-Path $themeRegLM) { Set-ItemProperty -Path $themeRegLM -Name "EnableTransparency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue }

    # OneDrive e Update
    $odReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (Test-Path $odReg) { Remove-ItemProperty -Path $odReg -Name "DisableFileSyncNGSC" -ErrorAction SilentlyContinue }
    $wuReg = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
    if (Test-Path $wuReg) {
        Remove-ItemProperty -Path $wuReg -Name "ActiveHoursStart" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $wuReg -Name "ActiveHoursEnd" -ErrorAction SilentlyContinue
    }
    
    # IFEO, Store, Logon e VPNs
    $appsBloquear = @(
        "GooglePlayGamesSetup.exe", "Bootstrapper.exe", "currentuserbootstrapper.exe", "GooglePlayGames.exe", "crosvm.exe", "ServiceAgent.exe",
        "Minecraft.Windows.exe", "MinecraftEducation.exe", "MinecraftEducationInstaller.exe",
        "RobloxPlayerBeta.exe", "RobloxPlayerInstaller.exe", "RobloxPlayerLauncher.exe", "RobloxStudioLauncherBeta.exe",
        "OperaSetup.exe", "OperaGXSetup.exe", "BraveBrowserSetup.exe",
        "u.exe", "ultrasurf.exe",
        "ProtonVPN_Setup.exe", "ProtonVPN.exe", "Windscribe_windows.exe", "Windscribe.exe",
        "TunnelBear-Installer.exe", "TunnelBear.exe", "HotspotShield-install.exe", "HotspotShield.exe",
        "Psiphon3.exe", "UrbanVPN.exe", "TouchVPN.exe", "NordVPN.exe", "NordVPN-Setup.exe",
        "ExpressVPN.exe", "expressvpn_setup.exe", "OpenVPN.exe", "openvpn-install.exe",
        "WireGuard.exe", "wireguard-installer.exe", "CloudflareWARP.exe", "warp.exe",
        "HideMe.exe", "Speedify.exe"
    )
    foreach ($app in $appsBloquear) {
        $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$app"
        if (Test-Path $ifeoPath) { Remove-Item -Path $ifeoPath -Force -Recurse -ErrorAction SilentlyContinue }
    }
    
    # Reverter politicas de conexao e VPN
    $netPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections"
    if (Test-Path $netPol) {
        Remove-ItemProperty -Path $netPol -Name "NC_NewConnectionWizard" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $netPol -Name "NC_RasUserConfig" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $netPol -Name "NC_RasAllUserConfig" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $netPol -Name "NC_RasConnect" -ErrorAction SilentlyContinue
    }
    $explorerPol = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    if (Test-Path $explorerPol) { Remove-ItemProperty -Path $explorerPol -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue }
    Set-Service -Name "RasMan" -StartupType Manual -ErrorAction SilentlyContinue
    
    $storeReg = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
    if (Test-Path $storeReg) { 
        Remove-ItemProperty -Path $storeReg -Name "RemoveWindowsStore" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $storeReg -Name "DisableStoreApps" -ErrorAction SilentlyContinue
    }
    
    $hideUsersPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList"
    if (Test-Path $hideUsersPath) { Remove-Item -Path $hideUsersPath -Force -Recurse -ErrorAction SilentlyContinue }
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnumerateLocalUsers" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnumerateLocalUsersOnDomainJoinedComputers" -ErrorAction SilentlyContinue
    
    $publicDesktop = "C:\Users\Public\Desktop"
    if (Test-Path $publicDesktop) { icacls "$publicDesktop\*" /remove:d "BUILTIN\Users" /C /Q | Out-Null }

    # Desativar Tarefa de Manutencao de Perfis de Alunos
    schtasks /delete /tn "LimpezaPerfisAlunos" /f 2>$null | Out-Null
    Remove-Item "C:\ProgramData\EscolaConfig\Limpar-PerfisInativos.ps1" -Force -ErrorAction SilentlyContinue

    Write-Step -Text "Todas as alteracoes (bloqueios e otimizacoes) revertidas" -Status "OK"
    Write-Host "`nPressione Enter para voltar ao menu principal..."
    Read-Host
}

function Mostrar-Ajuda {
    Clear-Host
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "                   AJUDA - DETALHES DAS OPCOES                       " -ForegroundColor Cyan
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "[1] Configurar Contas:" -ForegroundColor Yellow
    Write-Host "    Cria a conta 'alunos' (padrao sem senha), remove 'anos_iniciais' e"
    Write-Host "    oculta contas de administradores locais da tela de login."
    Write-Host ""
    Write-Host "[2] Ajustar Energia:" -ForegroundColor Yellow
    Write-Host "    Desliga o notebook ao fechar a tampa (evita esquentar na mochila),"
    Write-Host "    apaga a tela em 10 min e desativa a hibernacao (economiza disco)."
    Write-Host ""
    Write-Host "[3] Otimizar Desempenho (CPU/RAM, WSearch, Limpeza):" -ForegroundColor Yellow
    Write-Host "    Desativa SysMain, GameDVR, indexacao pesada (WSearch), Feeds de noticias,"
    Write-Host "    servicos ociosos, Edge inicial e limpa caches/Prefetch."
    Write-Host ""
    Write-Host "[4] Desativar OneDrive:" -ForegroundColor Yellow
    Write-Host "    Impede que o OneDrive inicialize sozinho (economiza RAM), mantendo o Teams."
    Write-Host ""
    Write-Host "[5] Definir Horario Ativo:" -ForegroundColor Yellow
    Write-Host "    Windows Update nao reinicia nem baixa atualizacoes entre 07:00 e 18:00."
    Write-Host ""
    Write-Host "[6] Bloquear Apps, Jogos e VPNs:" -ForegroundColor Yellow
    Write-Host "    Trava a execucao/instalacao do Roblox, Minecraft, Google Play Games,"
    Write-Host "    navegadores paralelos (Opera/Brave) e VPNs (UltraSurf, Psiphon, etc.)."
    Write-Host ""
    Write-Host "[7] Bloquear Microsoft Store:" -ForegroundColor Yellow
    Write-Host "    Desativa o app da Loja do Windows para evitar instalacao de jogos."
    Write-Host ""
    Write-Host "[8] Proteger Atalhos da Area de Trabalho:" -ForegroundColor Yellow
    Write-Host "    Impede que os alunos excluam atalhos importantes do sistema escolar."
    Write-Host ""
    Write-Host "[9] Instalar NetTime:" -ForegroundColor Yellow
    Write-Host "    Sincroniza data e hora automaticamente. Se ja estiver instalado, apenas valida o servico."
    Write-Host ""
    Write-Host "[10] Desativar Busca Web no Menu Iniciar (Bing Search):" -ForegroundColor Yellow
    Write-Host "    Faz a barra de pesquisa buscar APENAS programas e arquivos locais do Windows."
    Write-Host "    Elimina buscas e sugestoes da internet no Iniciar, deixando a pesquisa instantanea e leve."
    Write-Host ""
    Write-Host "[*] Manutencao e Limpeza de Perfis de Alunos:" -ForegroundColor Yellow
    Write-Host "    Identifica contas de alunos com login institucional inativas ha mais de 2 meses."
    Write-Host "    Permite selecao individual por caixas [X] para remocao definitiva de perfis pesados."
    Write-Host "    Contas de Administrador, BlueLab, 'alunos' e escolas sao 100% blindadas e protegidas."
    Write-Host "    Ao configurar contas, ativa tarefa agendada semanal para manter o PC sempre limpo."
    Write-Host ""
    Write-Host "[7] Reportar Problema ou Sugerir Melhoria:" -ForegroundColor Yellow
    Write-Host "    Permite ao operador digitar um relato de erro ou ideia de melhoria diretamente no terminal."
    Write-Host "    Os dados sao transmitidos de forma segura para a equipe de desenvolvimento."
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "Pressione Enter para voltar ao menu principal..."
    Read-Host
}

function Menu-Personalizado {
    # Inicia com todas as opcoes desmarcadas para selecao manual
    for ($i = 1; $i -le 10; $i++) { $global:opts[$i] = $false }
    $loop = $true
    $selectedIndex = 0
    
    $opcoesTexto = @(
        "Configurar Contas (Criar 'alunos', remover 'anos_iniciais')",
        "Ajustar Energia (Desligar na tampa, sem hibernar)",
        "Otimizar Desempenho (CPU/RAM, SysMain, WSearch, Feeds, Limpeza)",
        "Desativar Inicializacao do OneDrive (Teams mantido)",
        "Definir Horario Ativo do Windows Update (07:00 as 18:00)",
        "Bloquear Apps, Jogos e VPNs (Roblox, Minecraft, GPlay, Opera/Brave, VPNs)",
        "Bloquear Microsoft Store",
        "Proteger Atalhos da Area de Trabalho contra exclusao",
        "Instalar NetTime (Verifica se ja existe; se sim, apenas ativa)",
        "Desativar Busca Web no Menu Iniciar (Pesquisa apenas programas locais)"
    )

    while ($loop) {
        Clear-Host
        Write-Host "=====================================================================" -ForegroundColor Cyan
        Write-Host "                    PERSONALIZAR CONFIGURACAO                        " -ForegroundColor Cyan
        Write-Host "=====================================================================" -ForegroundColor Cyan
        if ($is32GB) {
            Write-Host " Armazenamento detectado: $diskSizeGB GB (Espaco critico de 32GB)." -ForegroundColor Red
        } else {
            Write-Host " Armazenamento detectado: $diskSizeGB GB (Espaco suficiente para o sistema)." -ForegroundColor Green
        }
        Write-Host "=====================================================================" -ForegroundColor Cyan
        Write-Host "`n Use as SETAS (Cima/Baixo) para navegar." -ForegroundColor Yellow
        Write-Host " Aperte ESPACO ou ENTER para marcar/desmarcar a opcao [X]:`n" -ForegroundColor Yellow

        for ($i = 0; $i -lt 10; $i++) {
            $optNum = $i + 1
            $prefix = if ($i -eq $selectedIndex) { " -> " } else { "    " }
            $check = if ($global:opts[$optNum]) { "[X]" } else { "[ ]" }
            $text = "[$optNum] $check $($opcoesTexto[$i])"

            if ($i -eq $selectedIndex) {
                Write-Host "${prefix}${text}" -ForegroundColor Green
            } else {
                Write-Host "${prefix}${text}" -ForegroundColor White
            }
        }

        Write-Host "`n Comandos Rapidos (Pressione a tecla a qualquer momento):" -ForegroundColor Cyan
        Write-Host "  [T] Marcar Todas    [N] Desmarcar Todas"
        Write-Host "  [E] EXECUTAR OPCOES MARCADAS" -ForegroundColor Green
        Write-Host "  [V] VOLTAR AO MENU PRINCIPAL`n"
        
        $key = [Console]::ReadKey($true)
        $char = ""
        if ([int]$key.KeyChar -ne 0) { $char = $key.KeyChar.ToString().ToUpper() }

        switch ($key.Key) {
            'UpArrow' { 
                $selectedIndex--
                if ($selectedIndex -lt 0) { $selectedIndex = 9 }
            }
            'DownArrow' { 
                $selectedIndex++
                if ($selectedIndex -gt 9) { $selectedIndex = 0 }
            }
            'Spacebar' {
                $optNum = $selectedIndex + 1
                $global:opts[$optNum] = -not $global:opts[$optNum]
            }
            'Enter' {
                $optNum = $selectedIndex + 1
                $global:opts[$optNum] = -not $global:opts[$optNum]
            }
        }

        switch ($char) {
            'T' { for ($i = 1; $i -le 10; $i++) { $global:opts[$i] = $true } }
            'N' { for ($i = 1; $i -le 10; $i++) { $global:opts[$i] = $false } }
            'E' { 
                $loop = $false
                Executar-Tarefas 
            }
            'V' { $loop = $false }
            '1' { $global:opts[1] = -not $global:opts[1] }
            '2' { $global:opts[2] = -not $global:opts[2] }
            '3' { $global:opts[3] = -not $global:opts[3] }
            '4' { $global:opts[4] = -not $global:opts[4] }
            '5' { $global:opts[5] = -not $global:opts[5] }
            '6' { $global:opts[6] = -not $global:opts[6] }
            '7' { $global:opts[7] = -not $global:opts[7] }
            '8' { $global:opts[8] = -not $global:opts[8] }
            '9' { $global:opts[9] = -not $global:opts[9] }
            '0' { $global:opts[10] = -not $global:opts[10] }
        }
    }
}

# =====================================================================
# CONFIGURACAO DO GOOGLE FORMS (FEEDBACK / MELHORIAS)
# =====================================================================
$global:GoogleFormUrl            = "https://docs.google.com/forms/d/e/1FAIpQLSfe9rJRS-ZUiQAZHbHVifYe8d32QucHPURN2iidtDXoDaD-hA/formResponse"
$global:GoogleFormEntryTipo      = "entry.1741125581" # Qual e o tipo?
$global:GoogleFormEntryMensagem  = "entry.528682894"  # Qual e a mensagem?
$global:GoogleFormEntryTecnico   = "entry.1792191175" # Qual e o seu nome e cidade?
$global:GoogleFormEntrySistema   = "entry.272576545"  # Qual e o diagnostico do sistema?

function Enviar-Feedback {
    Clear-Host
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "             REPORTAR UM PROBLEMA OU SUGERIR MELHORIA                " -ForegroundColor Cyan
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host " Envie seu relato diretamente para a equipe de desenvolvimento.`n" -ForegroundColor DarkGray

    Write-Host " O que voce gostaria de enviar?" -ForegroundColor Yellow
    Write-Host " [1] Reportar um Problema / Erro no script"
    Write-Host " [2] Sugerir uma Nova Melhoria ou Ideia"
    Write-Host " [0] Cancelar e Voltar`n"

    $tipoOpcao = Read-Host " Escolha uma opcao [1/2/0]"
    $tipoTexto = ""
    switch ($tipoOpcao) {
        "1" { $tipoTexto = "Problema / Erro" }
        "2" { $tipoTexto = "Sugestao de Melhoria" }
        default { return }
    }

    Write-Host "`n>> Descreva o problema ou sugestao em detalhes:" -ForegroundColor Cyan
    $mensagem = Read-Host " Mensagem"
    if ([string]::IsNullOrWhiteSpace($mensagem)) {
        Write-Host "`n Nenhuma mensagem digitada. Operacao cancelada." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }

    Write-Host "`n>> Identificacao do Tecnico (Opcional):" -ForegroundColor Cyan
    Write-Host " Informe seu Nome e Cidade (ex: Joao - Aracatuba), ou pressione Enter para enviar anonimo:" -ForegroundColor DarkGray
    $tecnico = Read-Host " Nome e Cidade"
    if ([string]::IsNullOrWhiteSpace($tecnico)) { $tecnico = "Anonimo / Nao informado" }

    # Diagnostico automatico do equipamento
    $infoSistema = "OS: $osName | RAM: $ramGB GB | Disco: $global:diskSizeGB GB (Livre: $global:freeSpace GB) | PC: $env:COMPUTERNAME"

    Write-Host "`n Enviando dados..." -ForegroundColor Yellow

    try {
        $body = @{
            $global:GoogleFormEntryTipo     = $tipoTexto
            $global:GoogleFormEntryMensagem = $mensagem
            $global:GoogleFormEntryTecnico  = $tecnico
            $global:GoogleFormEntrySistema  = $infoSistema
        }

        $null = Invoke-RestMethod -Uri $global:GoogleFormUrl -Method Post -Body $body -TimeoutSec 10 -ErrorAction Stop
        Write-Host "`n [OK] Relatorio enviado com sucesso! Muito obrigado pela colaboracao." -ForegroundColor Green
    } catch {
        Write-Host "`n [AVISO] Nao foi possivel enviar os dados no momento (sem conexao com a internet)." -ForegroundColor Yellow
        Write-Host " Seu relato foi salvo localmente em: $env:TEMP\Feedback_Pendente.txt" -ForegroundColor DarkGray
        $backupFeedback = @"
Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Tipo: $tipoTexto
Mensagem: $mensagem
Tecnico / Cidade: $tecnico
Sistema: $infoSistema
"@
        Set-Content -Path "$env:TEMP\Feedback_Pendente.txt" -Value $backupFeedback -Encoding UTF8 -Force -ErrorAction SilentlyContinue
    }

    Write-Host "`nPressione Enter para voltar ao menu principal..."
    Read-Host
}

function Menu-Principal {
    $loop = $true
    $selectedIndex = 0

    $menuItems = @(
        "[1] Instalacao Padrao (Recomendado - Completo: 10 Otimizacoes)",
        "[2] Instalacao Personalizada (Selecao por caixas [X])",
        "[3] Liberar Particao de Recuperacao (eMMC 32GB)",
        "[4] Diagnostico de Hardware (Bateria, Disco, CPU, Uptime)",
        "[5] Limpar Perfis de Alunos Inativos (> 2 meses)",
        "[6] Desfazer / Reverter Alteracoes",
        "[7] Reportar Problema ou Sugerir Melhoria",
        "[H] Ajuda (Detalhes de cada opcao)",
        "[0] Sair"
    )

    while ($loop) {
        Atualizar-MetricasDisco
        $liberado = [math]::Round($global:freeSpace - $global:espacoInicial, 1)

        Clear-Host
        Write-Host "=====================================================================" -ForegroundColor Cyan
        Write-Host "          CONFIGURADOR E OTIMIZADOR ESCOLAR - WIN 10/11              " -ForegroundColor Cyan
        Write-Host "         Ambiente: Governo / Azure AD / Laptops Educacionais         " -ForegroundColor Cyan
        Write-Host "=====================================================================" -ForegroundColor Cyan
        Write-Host " Sistema: " -NoNewline; Write-Host "$osName | RAM: $ramGB GB" -ForegroundColor Yellow
        Write-Host " Disco do Sistema (C:): " -NoNewline
        if ($liberado -gt 0.05) {
            Write-Host "eMMC/SSD de $global:diskSizeGB GB (Livre: $global:freeSpace GB | " -NoNewline -ForegroundColor Yellow
            Write-Host "+$liberado GB liberados" -ForegroundColor Green -NoNewline
            Write-Host ")" -ForegroundColor Yellow
        } else {
            Write-Host "eMMC/SSD de $global:diskSizeGB GB (Livre: $global:freeSpace GB)" -ForegroundColor Yellow
        }
        
        if ($global:is32GB) {
            Write-Host "`n >> AVISO: Disco de 32GB detectado! Recomendado liberar particao (Opcao 3)" -ForegroundColor Red
        }
        Write-Host "=====================================================================`n" -ForegroundColor Cyan
        
        Write-Host " Use as SETAS (Cima/Baixo) para navegar e ENTER para confirmar:`n" -ForegroundColor Yellow

        for ($i = 0; $i -lt $menuItems.Count; $i++) {
            $prefix = if ($i -eq $selectedIndex) { " -> " } else { "    " }
            $text = $menuItems[$i]

            if ($i -eq 2 -and -not $global:is32GB) {
                $text = "[3] Liberar Particao de Recuperacao (Opcional)"
                if ($i -eq $selectedIndex) { Write-Host "${prefix}${text}" -ForegroundColor Green }
                else { Write-Host "${prefix}${text}" -ForegroundColor DarkGray }
            } else {
                if ($i -eq $selectedIndex) { Write-Host "${prefix}${text}" -ForegroundColor Green }
                else { Write-Host "${prefix}${text}" -ForegroundColor White }
            }
        }
        
        Write-Host "`n Ou pressione o numero/letra correspondente no teclado." -ForegroundColor DarkGray
        Write-Host "=====================================================================" -ForegroundColor Cyan
        Write-Host " [i] Desenvolvido por: Julio Antunes | github.com/JulioAntunes00" -ForegroundColor DarkCyan
        Write-Host "=====================================================================" -ForegroundColor Cyan

        $key = [Console]::ReadKey($true)
        $char = ""
        if ([int]$key.KeyChar -ne 0) { $char = $key.KeyChar.ToString().ToUpper() }

        switch ($key.Key) {
            'UpArrow' { 
                $selectedIndex--
                if ($selectedIndex -lt 0) { $selectedIndex = $menuItems.Count - 1 }
            }
            'DownArrow' { 
                $selectedIndex++
                if ($selectedIndex -ge $menuItems.Count) { $selectedIndex = 0 }
            }
            'Enter' {
                switch ($selectedIndex) {
                    0 { 
                        # [1] Instalacao Padrao: Forca todas as 10 opcoes ativas
                        for ($i = 1; $i -le 10; $i++) { $global:opts[$i] = $true }
                        Executar-Tarefas
                    }
                    1 { Menu-Personalizado }
                    2 { Liberar-ParticaoRecovery }
                    3 { Mostrar-Diagnostico }
                    4 { Gerenciar-PerfisInativos }
                    5 { Desfazer-Alteracoes }
                    6 { Enviar-Feedback }
                    7 { Mostrar-Ajuda }
                    8 { $loop = $false; Write-Host "Saindo..." }
                }
            }
        }

        switch ($char) {
            "1" { 
                # [1] Instalacao Padrao: Forca todas as 10 opcoes ativas
                for ($i = 1; $i -le 10; $i++) { $global:opts[$i] = $true }
                Executar-Tarefas
            }
            "2" { Menu-Personalizado }
            "3" { Liberar-ParticaoRecovery }
            "4" { Mostrar-Diagnostico }
            "5" { Gerenciar-PerfisInativos }
            "6" { Desfazer-Alteracoes }
            "7" { Enviar-Feedback }
            "R" { Enviar-Feedback }
            "H" { Mostrar-Ajuda }
            "0" { $loop = $false; Write-Host "Saindo..." }
        }
    }
}

# =====================================================================
# INICIO DO SCRIPT
# =====================================================================
Menu-Principal