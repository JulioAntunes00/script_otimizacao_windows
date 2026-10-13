# 📋 Plano de Melhorias: Script de Configuração Escolar (Windows 10/11)

> **Autor:** Julio Antunes ([@JulioAntunes00](https://github.com/JulioAntunes00))  
> **Cenário de Execução:** Notebooks de escolas públicas (governo / Azure AD / Intune), executado via Web (`irm ... | iex`) ou pendrive. Utilizado tanto em formatações do zero quanto em manutenção de máquinas que já estão em uso.
> **Hardware Típico:** eMMC 32GB, eMMC 64GB e SSD M.2 SATA 128GB+ (Windows 10 e Windows 11).

---

## 🧭 1. Resumo das Decisões & Alinhamento Atualizado

| Área | Decisão | Status |
| :--- | :--- | :---: |
| **Instalação Padrão** | Executa o pacote completo de uma vez: contas (`alunos`), energia, bloatware, otimizações de RAM/SysMain/Edge, corte de inicialização do OneDrive, horário ativo do Windows Update, bloqueio de apps/jogos/VPNs, proteção de atalhos, bloqueio de Store, **NetTime inteligente** e **desativação da busca web (Bing)**. | ✅ Aprovado (10 Otimizações) |
| **Instalação Personalizada** | Apresenta as **10 opções** com caixas de seleção interativas `[ ]`, iniciando **todas desmarcadas** para seleção manual cirúrgica (com atalhos `[T]` marcar todas e `[N]` desmarcar). | ✅ Aprovado (10 Opções) |
| **Resiliência do Desempenho (Opção 3)** | Dividido em **8 sub-blocos isolados** com `try/catch` independentes e feedback visual `[OK]` em tempo real para cada um. Se alguma otimização falhar, o script exibe aviso específico sem interromper os demais módulos. | ✅ Resiliente em 8 Etapas |
| **Limpeza Segura de Armazenamento (HD)** | Esvazia caches temporários do sistema (`C:\Windows\Temp`, `%temp%`, `Prefetch`), cache de download do Windows Update, relatórios WER e lixeira. **Não invade pastas pessoais (`C:\Users\*`)**, garantindo 100% de integridade em contas de domínio/AD e papéis de parede governamentais. | ✅ Modo Seguro de Sistema |
| **NetTime Inteligente** | Sincronizador de hora para CMOS com defeito. **Detecção Automática:** se o NetTime já estiver instalado na máquina, apenas garante o serviço ativo e pula download/instalador. | ✅ Integrado e Otimizado |
| **Busca Web no Iniciar (Opção 10)** | Injeta bloqueio em `HKLM`, `HKCU`, perfil modelo `C:\Users\Default\NTUSER.DAT` e `C:\Users\alunos\NTUSER.DAT`. Garante que novas contas e alunos pesquisem **apenas aplicativos e arquivos locais**, sem puxar Bing ou internet. | ✅ Multi-Perfil Ativo |
| **Indexador Local (`WSearch`)** | Mantido ativo em modo automático para catalogar programas locais e eliminar a mensagem *"A indexação de pesquisa foi desativada"*. | ✅ Aprovado |
| **Microsoft Edge** | Desativado em segundo plano, desativado Boost de inicialização e **desativado na aba Inicializar do Gerenciador de Tarefas** (via `StartupApproved\Run`). | ✅ Aprovado |
| **Diagnóstico Técnico** | Exibe bateria (saúde/desgaste), **saúde e vida útil do SSD/eMMC (desgaste %)**, **temperatura da placa-mãe/processador** e **tempo de atividade (Uptime)**. | ✅ Aprovado |
| **Eixo de Desempenho** | Desativar GameDVR, limpar `SoftwareDistribution` e `Prefetch`, cortar telemetria/SysMain, desativar transparência e **ocultar Widgets/Feeds**. | ✅ Aprovado |
| **Bloqueios de Jogos, VPNs e Apps** | Bloquear **Minecraft**, **Roblox**, **Google Play Games**, **UltraSurf**, **Psiphon**, **todas as principais VPNs**, restrição de conexões VPN no Windows e navegadores paralelos (**Opera, Brave**). *(Netflix e Clipchamp mantidos)*. | ✅ Aprovado |
| **Partição de Recuperação (32GB)** | Isolada **apenas no Menu Principal (Opção 3)** com confirmação `[S/N]` e trava de segurança para eMMC de 32GB, evitando cliques acidentais no menu personalizado. | ✅ Aprovado |
| **Limpeza e Gestão de Perfis de Alunos** | Identifica contas de alunos com login institucional inativas há mais de **1 mês (30 dias)** com alerta interativo e seleção por caixas `[X]` (iniciando todas marcadas para exclusão, com opção de desmarcar). Blindagem total de **Administradores, BlueLab, alunos, ARACATUBA\* e alunos.DESKTOP\***. Snapshot inicial de contas no dia da configuração e **tarefa agendada semanal** para remover perfis novos inativos há mais de **7 dias**. | ✅ Implementado & Blindado |
| **Navegação Contínua & Armazenamento Dinâmico** | Ao concluir tarefas, o script retorna ao Menu Principal sem fechar e **recalcula o disco em tempo real**, exibindo o ganho em verde (ex: `+6.6 GB liberados`). | ✅ Implementado Dinâmico |
| **Reporte de Problemas & Sugestões** | Envia relatos do técnico diretamente do terminal para uma planilha do **Google Sheets (via Google Forms POST silencioso)** com identificação opcional e diagnóstico automático de hardware. | ✅ Implementado |
| **Opção de Reverter / Desfazer** | Restaura o computador ao estado original (para notebooks pessoais rodados por engano). | ✅ Aprovado |

---

## 🖥️ 2. Visualização das Telas e Menus Interativos

### 2.1. Tela Inicial Principal

```text
=====================================================================
          CONFIGURADOR E OTIMIZADOR ESCOLAR - WIN 10/11              
      v2.1.0 | Desenvolvido por Julio | GitHub: @JulioAntunes00      
=====================================================================
 Sistema: Windows 11 Pro Education (64-bit) | RAM: 4 GB
 Disco do Sistema (C:): eMMC 32 GB (Livre: 12.8 GB | +6.6 GB liberados)
 >> AVISO: Disco de 32GB detectado! Recomendado liberar particao (Opcao 3)
=====================================================================

 Use as SETAS (Cima/Baixo) para navegar e ENTER para confirmar:

 -> [1] Instalacao Padrao (Recomendado - Completo: 10 Otimizacoes)
    [2] Instalacao Personalizada (Selecao por caixas [X])
    [3] Liberar Particao de Recuperacao (eMMC 32GB)
    [4] Diagnostico de Hardware (Bateria, Disco, CPU, Uptime)
    [5] Limpar Perfis de Alunos Inativos (> 1 mes)
    [6] Desfazer / Reverter Alteracoes
    [7] Reportar Problema ou Sugerir Melhoria
    [H] Ajuda (Detalhes de cada opcao)
    [0] Sair

 Ou pressione o numero/letra correspondente no teclado.
```

---

### 2.2. Tela de Instalação Personalizada [2]

Todas as 10 opções iniciam **desmarcadas (`[ ]`)** para escolha livre do técnico:

```text
=====================================================================
                    PERSONALIZAR CONFIGURACAO                        
=====================================================================
 Armazenamento detectado: 64 GB (Espaco suficiente para o sistema).
=====================================================================

 Use as SETAS (Cima/Baixo) para navegar.
 Aperte ESPACO ou ENTER para marcar/desmarcar a opcao [X]:

 -> [1] [ ] Configurar Contas (Criar 'alunos', remover 'anos_iniciais')
    [2] [ ] Ajustar Energia (Desligar na tampa, sem hibernar)
    [3] [ ] Otimizar Desempenho (CPU/RAM, SysMain, WSearch, Feeds, Limpeza)
    [4] [ ] Desativar Inicializacao do OneDrive (Teams mantido)
    [5] [ ] Definir Horario Ativo do Windows Update (07:00 as 18:00)
    [6] [ ] Bloquear Apps, Jogos e VPNs (Roblox, Minecraft, GPlay, Opera/Brave, VPNs)
    [7] [ ] Bloquear Microsoft Store
    [8] [ ] Proteger Atalhos da Area de Trabalho contra exclusao
    [9] [ ] Instalar NetTime (Verifica se ja existe; se sim, apenas ativa)
    [10] [ ] Desativar Busca Web no Menu Iniciar (Pesquisa apenas programas locais)

 Comandos Rapidos (Pressione a tecla a qualquer momento):
  [T] Marcar Todas    [N] Desmarcar Todas
  [E] EXECUTAR OPCOES MARCADAS
  [V] VOLTAR AO MENU PRINCIPAL
```

---

### 2.3. Tela de Ajuda [H]

```text
=====================================================================
                   AJUDA - DETALHES DAS OPCOES                       
=====================================================================
[1] Configurar Contas:
    Cria a conta 'alunos' (padrao sem senha), remove 'anos_iniciais' e
    oculta contas de administradores locais da tela de login.

[2] Ajustar Energia:
    Desliga o notebook ao fechar a tampa (evita esquentar na mochila),
    apaga a tela em 10 min e desativa a hibernacao (economiza disco).

[3] Otimizar Desempenho (CPU/RAM, WSearch, Limpeza):
    Desativa SysMain, GameDVR, indexacao pesada, Feeds de noticias,
    servicos ociosos, Edge inicial e limpa caches/Prefetch.

[4] Desativar OneDrive:
    Impede que o OneDrive inicialize sozinho (economiza RAM), mantendo o Teams.

[5] Definir Horario Ativo:
    Windows Update nao reinicia nem baixa atualizacoes entre 07:00 e 18:00.

[6] Bloquear Apps, Jogos e VPNs:
    Trava a execucao/instalacao do Roblox, Minecraft, Google Play Games,
    navegadores paralelos (Opera/Brave) e VPNs (UltraSurf, Psiphon, etc.).

[7] Bloquear Microsoft Store:
    Desativa o app da Loja do Windows para evitar instalacao de jogos.

[8] Proteger Atalhos da Area de Trabalho:
    Impede que os alunos excluam atalhos importantes do sistema escolar.

[9] Instalar NetTime:
    Sincroniza data e hora automaticamente. Se ja estiver instalado, apenas valida o servico.

[10] Desativar Busca Web no Menu Iniciar (Bing Search):
    Faz a barra de pesquisa buscar APENAS programas e arquivos locais do Windows.
    Elimina buscas e sugestoes da internet no Iniciar, deixando a pesquisa instantanea e leve.
=====================================================================
```

---

## ⚙️ 3. Funcionamento Interno e Detalhes Técnicos

1. **Detecção Inteligente de NetTime Instalado:**
   - O script verifica previamente se o serviço `NetTime` ou o binário `NetTime.exe` já existem em disco.
   - Em caso positivo, cancela etapas de download e instalador, apenas garantindo o serviço ativo em inicialização automática e o `w32time` desativado.

2. **Bloqueio Completo da Busca Web (Multi-Perfil):**
   - Aplica em nível de máquina (`HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions = 1` e políticas do Windows Search).
   - Injeta em tempo de execução em todas as hives ativas (`HKEY_USERS\S-1-5-21-*`).
   - Carrega temporariamente `C:\Users\Default\NTUSER.DAT` e `C:\Users\alunos\NTUSER.DAT` via `reg load` para gravar as diretivas `BingSearchEnabled = 0`, `CortanaConsent = 0` e `IsBingSearchEnabled = 0`.
   - Reinicia `SearchHost` / `StartMenuExperienceHost` para efeito instantâneo sem necessidade de reinicialização.

3. **Manutenção do `WSearch` Ativo:**
   - O serviço Windows Search permanece configurado em modo automático e ativo, evitando que a barra de pesquisa perca o catálogo de programas locais e impedindo o surgimento da mensagem *"A indexação de pesquisa foi desativada"*.

4. **Gerenciamento de Navegação Contínua no Terminal:**
   - As rotinas de execução finalizam com `"Pressione Enter para voltar ao menu principal..."`, mantendo o loop ativo para que o técnico possa executar manutenções adicionais (diagnóstico, partição ou ajuda) sem reiniciar o PowerShell.

5. **Resiliência e Tratamento de Erros Granular na Otimização (Opção 3):**
   - O bloco de desempenho opera em **8 sub-blocos independentes com `try/catch` individual**:
     - **3.1:** Desativação do GameDVR via Registro (`HKCU` e `HKLM`).
     - **3.2:** Desativação de serviços pesados (`DiagTrack`, `SysMain`) e ociosos (`MapsBroker`, `Fax`, Xbox), garantindo o `WSearch` ativo.
     - **3.3:** Desativação de telemetria via diretiva GPO (`DataCollection\AllowTelemetry`).
     - **3.4:** Desativação de Feeds, Notícias e Interesses e Widgets (`Dsh` e `Feeds`).
     - **3.5:** Desativação do Microsoft Edge em segundo plano, Startup Boost e trava na inicialização (`StartupApproved\Run`).
     - **3.6:** Bloqueio de apps patrocinados (`CloudContent\DisableWindowsConsumerFeatures`), desativação de sugestões no `ContentDeliveryManager` e remoção blindada de bloatwares Appx (Solitaire, Spotify, TikTok, etc., ignorando pacotes protegidos do sistema como XboxGamingOverlay para evitar erros de Acesso Negado).
     - **3.7:** Desativação de efeitos visuais pesados e transparência gráfica.
     - **3.8:** Limpeza segura de caches e temporários do sistema.
   - Se ocorrer qualquer exceção em alguma etapa, o script incrementa `$errosOtimizacao`, registra `[AVISO]` especificando a etapa com falha e **continua executando normalmente as etapas seguintes sem abortar o processo**.
   - **Feedback Visual Individual em Tempo Real:** Cada um dos 8 sub-módulos aciona `Write-Step` individualmente com prefixo `[3.1]` até `[3.8]`, exibindo `[OK]` em verde na tela à medida que roda, seguido de uma confirmação geral de conclusão.

6. **Proteção Rigorosa de Contas de Domínio (AD/Azure AD) e Papéis de Parede Governamentais:**
   - **Isolamento de Sessões:** O script **não encerra nem desloga forçadamente outros usuários** via `quser`/`logoff`, evitando quebrar conexões ativas ou sincronizações de contas de rede corporativa/escolar.
   - **Limpeza Restrita ao Nível de Sistema:** A limpeza de disco é executada estritamente em pastas globais do Windows (`%temp%`, `C:\Windows\Temp`, `Prefetch`, `SoftwareDistribution\Download`, `WER` e lixeira).
   - **Preservação de `C:\Users\*`:** O script **nunca invade diretórios de outros usuários**. Isso previne a corrupção de perfis do Active Directory (que gerava a falha *"Não foi possível entrar na sua conta"* / carregamento de perfil temporário) e preserva integralmente os papéis de parede oficiais do governo e políticas do ambiente escolar.

7. **Fixação Automática da Conta `alunos` no LogonUI e Winlogon:**
   - Injeta a política oficial `EnumerateLocalUsers = 1` (além de `EnumerateLocalUsersOnDomainJoinedComputers`) em `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` para que computadores com Azure AD, Intune ou Domínio exibam as contas locais na tela de boas-vindas.
   - Desativa a política `dontdisplaylastusername = 0` em `HKLM:\...\Policies\System`, impedindo que o Windows force as duas caixas em branco de "Outro Usuário".
   - Captura dinamicamente o SID do usuário `alunos` (`$aluno.SID.Value`) e preenche `SelectedUserSID`, `LastLoggedOnUserSID`, `LastLoggedOnDisplayName`, `LastLoggedOnUser` e `LastLoggedOnProvider` na chave `HKLM:\...\Authentication\LogonUI`.
   - Registra `DefaultUserName = "alunos"` em `HKLM:\...\Winlogon`.
   - Garante que ao reiniciar o computador, o avatar do usuário `alunos` já apareça **selecionado e pronto para entrar de primeira**, sem obrigar o técnico ou aluno a digitar `.\alunos`.

8. **Desbloqueio da Calculadora e Utilitários Nativos (Opção 7 - Microsoft Store):**
   - **Diagnóstico da Restrição:** No Windows 10 e Windows 11, a Calculadora (`Microsoft.WindowsCalculator`), Bloco de Notas (Win 11), Fotos, Ferramenta de Captura e Paint são empacotados como UWP/MSIX. A política de registro `DisableStoreApps = 1` bloqueava a execução de **todos os aplicativos empacotados**, fazendo o Windows exibir a mensagem *"Este aplicativo foi bloqueado pelo administrador do sistema"*.
   - **Solução Aplicada:** O script mantém `RemoveWindowsStore = 1` (desativa apenas o aplicativo da loja, impedindo que alunos abram a Store ou baixem jogos), e remove explicitamente a chave `DisableStoreApps`. Com isso, a Calculadora, Bloco de Notas, Fotos, Câmera e Ferramenta de Captura funcionam normalmente, sem abrir brecha para a Loja.

9. **Supressão da Barra de Progresso Congelada do PowerShell (`$ProgressPreference`):**
   - **Diagnóstico:** Ao executar comandos de desinstalação de pacotes AppX (`Remove-AppxPackage`, como no `Microsoft.XboxApp`) ou downloads via Web, o PowerShell desenha nativamente uma barra de progresso no topo da tela (*"Progresso da operação de implantação: Microsoft.xboxapp_48..."*). Em consoles do Windows, essa barra frequentemente trava na tela e nunca mais sai do buffer visual, além de prejudicar a performance.
   - **Solução:** Configurado `$ProgressPreference = 'SilentlyContinue'` no início do script e no bloco 3.6. Isso silencia totalmente essa barra gráfica interna do PowerShell, mantendo o terminal limpo e acelerando substancialmente a execução dos comandos AppX.

10. **Blindagem e Gestão Inteligente de Perfis de Alunos:**
    - **Varredura de Inatividade (> 1 mês / 30 dias):** Executada na inicialização da instalação ou diretamente pela Opção [5] do Menu Principal. Exibe confirmação visual `[OK]` mesmo quando nenhum perfil inativo for detectado, e abre menu interativo com caixas `[X]` pré-selecionadas caso encontre perfis aptos a remoção.
    - **Lista Branca Rígida (Intocáveis):** Nenhuma conta de Administrador (membro de Administradores ou SID `-500`), sessões ativas (`Loaded`), perfis especiais (`Special`), contas padrão (`alunos`, `BlueLab`), contas de escolas (`ARACATUBA*`), clones locais (`alunos.DESKTOP*`) ou contas registradas no snapshot inicial pode ser tocada.
    - **Snapshot Inicial & Manutenção Semanal Automatizada:** No momento da primeira configuração, o script salva a "foto" dos usuários existentes em `C:\ProgramData\EscolaConfig\perfis_protegidos.txt` e cria uma Tarefa Agendada no Windows (`LimpezaPerfisAlunos`) que roda semanalmente para expurgar silenciosamente novos perfis de alunos que ficarem mais de 7 dias sem login, poupando espaço de discos eMMC e SSDs.

11. **Canal de Feedback e Relato de Problemas (Google Forms via HTTP POST):**
    - **Envio Direto sem Navegador:** O técnico pode reportar bugs ou enviar ideias de melhoria pelo terminal (Opção [7] / atalho `R`), informando Tipo, Mensagem e identificação opcional (Nome/Cidade).
    - **Diagnóstico Automático:** O script anexa automaticamente a versão do Windows, memória RAM, capacidade/espaço livre do disco e nome do computador.
    - **Privacidade e Sigilo:** As respostas são enviadas silenciosamente para o endpoint `/formResponse` do Google Forms e gravadas em tempo real na planilha do desenvolvedor. A interface no terminal oculta completamente qualquer menção ao Google Forms ou Google Sheets, exibindo apenas mensagens neutras de status.

12. **Métricas Dinâmicas de Armazenamento ("Antes e Depois"):**
    - **Recálculo em Tempo Real:** A função `Atualizar-MetricasDisco` é chamada a cada renderização do Menu Principal, recalculando o espaço livre de `C:` e a capacidade total.
    - **Destaque Visual:** Compara com o espaço inicial medido na abertura do script e exibe em verde no cabeçalho o ganho obtido (ex: `+7.4 GB liberados`), além de refletir a expansão da partição após a liberação da partição de recuperação.

13. **Versionamento e Repositório Oficial no GitHub:**
    - **Repositório:** [https://github.com/JulioAntunes00/script_otimizacao_windows](https://github.com/JulioAntunes00/script_otimizacao_windows)
    - **Regras de Exclusão (`.gitignore`):** Backups legados manuais (`*.bak`, `*_backup*.ps1`) e logs temporários são ignorados. Todo o versionamento histórico é gerenciado com commits atômicos no Git, dispensando arquivos duplicados no computador.
    - **Controle Automático de Versão (`$SCRIPT_VERSAO`):** Centralizado na variável global `$SCRIPT_VERSAO` (iniciando em `2.1.0`), exibida no topo do menu. O assistente é responsável por incrementar a versão automaticamente a cada entrega de novas funções ou correções (seguindo versionamento semântico `MAJOR.MINOR.PATCH`), sem exigir preocupação manual do usuário.

14. **Levantamento e Inventário Silencioso de Equipamentos (Araçatuba):**
    - **Execução Oculta em Background:** A função `Registrar-InventarioSilencioso` roda de forma assíncrona (`[Task]::Run`) no início da execução, sem bloquear o menu e sem emitir nenhuma saída no terminal.
    - **Filtro de Localidade:** Dispara apenas se o usuário atual, contas locais ou pastas de perfis começarem com `ARACATUBA*`.
    - **Métricas Registradas:** Envia silenciosamente via HTTP POST ao Google Forms os campos: Escola/Usuário, Hostname, Número de Série (S/N da BIOS), Marca, Modelo, Tamanho do Disco e Data/Hora da Última Formatação (instalação do Windows).
