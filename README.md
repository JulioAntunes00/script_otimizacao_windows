# Script de Configuração para Escolas (`Configurar-Escola.ps1`)

Este script foi desenvolvido especificamente para padronizar, otimizar e proteger os computadores e notebooks do ambiente escolar.

---

## 📋 Como Funciona a Navegação

Ao abrir o script, você verá o **Menu Principal**:
* **[1] Instalação Padrão:** Executa o pacote completo de melhorias recomendadas (opções de 1 a 10) de uma só vez (com verificação automática de perfis inativos).
* **[2] Personalizar Configuração:** Permite selecionar individualmente quais das 10 opções aplicar (inicia com todas as caixas desmarcadas `[ ]` para maior controle).
* **[3] Liberar Partição de Recuperação:** Exclusivo para notebooks com eMMC de 32GB (exclui a partição OEM de fábrica e expande o disco C: em 8 a 14 GB).
* **[4] Diagnóstico de Hardware:** Analisa a saúde da bateria, vida útil do armazenamento (SSD/eMMC), temperatura e tempo ligado (uptime).
* **[5] Limpar Perfis de Alunos Inativos:** Verifica perfis de alunos com login institucional inativos há mais de 2 meses (60 dias) e abre tela interativa com caixas `[X]` para exclusão seletiva, liberando gigabytes de cache sem tocar em contas de administradores ou do sistema.
* **[6] Desfazer / Reverter Alterações:** Reabilita os serviços e remove os bloqueios aplicados caso precise voltar atrás.
* **[7] Reportar Problema ou Sugerir Melhoria:** Permite enviar feedbacks, relatos de erros e sugestões diretamente do terminal para a equipe de suporte e desenvolvimento.
* **[H] Ajuda:** Explicação resumida de cada item na própria tela.
* **[0] Sair:** Fecha o script e encerra a janela.

---

## ⚙️ O que cada uma das 10 Otimizações faz:

### [1] Configurar Contas de Usuário
- Cria a conta padrão de uso diário chamada **`alunos`** (sem senha, com privilégios de usuário padrão).
- **Fixação Instantânea na Tela de Login:** Injeta as diretivas `EnumerateLocalUsers = 1`, `dontdisplaylastusername = 0`, além de vincular diretamente o SID e dados do usuário `alunos` no `LogonUI` e `Winlogon`. Isso garante que o avatar da conta `alunos` apareça **de primeira na tela de login após reiniciar** (inclusive em notebooks com Azure AD / Domínio), sem necessidade de digitar `.\alunos` manualmente.
- Oculta as contas de Administrador da tela de boas-vindas do Windows (exibindo com destaque o usuário `alunos`).
- Remove contas antigas em desuso (ex: `anos_iniciais`) e limpa perfis órfãos.
- **Snapshot de Blindagem & Manutenção Semanal:**
  - Cria um snapshot permanente (`C:\ProgramData\EscolaConfig\perfis_protegidos.txt`) registrando todas as contas existentes e protegendo `alunos`, `BlueLab`, `ARACATUBA*`, `alunos.DESKTOP*`, Administradores e perfis de sistema.
  - Registra uma Tarefa Agendada no Windows (`LimpezaPerfisAlunos`) que roda semanalmente em segundo plano para limpar silenciosamente perfis de alunos novos inativos há mais de 7 dias (1 semana), mantendo o SSD/eMMC livre de gargalos.

### [2] Ajustar Políticas de Energia
- Configura o notebook para **desligar automaticamente ao fechar a tampa** (tanto na tomada quanto na bateria).
- Define o desligamento do monitor após 10 minutos de inatividade.
- Desativa a hibernação para liberar espaço no disco (elimina o arquivo `hiberfil.sys`).

### [3] Otimizar Desempenho e Limpar Disco
- **Execução Modular e Resiliente:** Processamento dividido em 8 etapas com tratamento de exceções independente (`try/catch`). Se qualquer etapa falhar ou encontrar restrições no sistema, o script exibe aviso específico do componente e continua executando todos os demais otimizadores sem interromper a rotina.
- **Feedback Visual Passo a Passo:** Cada um dos 8 sub-módulos exibe seu status em tempo real na tela (`[3.1]` até `[3.8]` com `[OK]` ou `[AVISO]`), permitindo ao operador acompanhar individualmente cada otimização aplicada.
- **Redução de Uso de CPU/RAM:** Desativa a Telemetria da Microsoft, o serviço SysMain (Superfetch) e o GameDVR.
- **Widgets e Notícias:** Desativa a barra de Notícias e Interesses (Win 10) e Widgets (Win 11) via registro e encerra o processo `Feeds` que consumia CPU em segundo plano.
- **Navegador Edge:** Desativa inicialização em segundo plano, startup boost e desabilita na aba Inicializar do Gerenciador de Tarefas (`StartupApproved`).
- **Sem Dicas e Sugestões:** Desativa tarefas em segundo plano do `ContentDeliveryManager` (dicas de boas-vindas e sugestões da Microsoft).
- **Serviços Extras Desativados:** Desativa serviços desnecessários para a escola (`MapsBroker`, `Fax`, serviços residuais do Xbox).
- **Catálogo Local de Aplicativos (`WSearch`):** Mantém o serviço `WSearch` ativo para que a pesquisa localize instantaneamente programas locais (Calculadora, navegadores, Word) sem exibir mensagens de erro de indexação.
- **Limpeza Segura de Arquivos Temporários (HD):** 
  - Limpa caches temporários do Windows (`%temp%`, `C:\Windows\Temp`, `Prefetch`), instaladores do Windows Update (`SoftwareDistribution\Download`), relatórios de erro do sistema (`WER`), esvazia a lixeira e limpa a fila de impressão (`Spool\Printers`).
  - **Proteção Total de Contas e Perfis:** Opera estritamente no nível de sistema e lixeira sem tocar em diretórios de outros usuários (`C:\Users\*`), preservando 100% íntegras as contas de domínio/Active Directory, o papel de parede oficial do governo e os dados pessoais.
- **Animações Leves:** Desativa animações lentas de janelas, mantendo a suavização de fontes ativa para ótima legibilidade.

### [4] Desativar Inicialização do OneDrive
- Remove o OneDrive da inicialização automática do Windows para economizar memória RAM e agilizar o boot (mantém o Microsoft Teams intacto).

### [5] Definir Horário Ativo do Windows Update
- Trava o horário de atividade do sistema entre **07:00 e 18:00**.
- Garante que o Windows Update nunca reinicie o computador sozinho no meio de uma aula.

### [6] Bloquear Aplicativos, Jogos e VPNs
- Bloqueia a execução por **IFEO (Image File Execution Options)** e regras de Firewall de:
  - **Jogos:** Roblox (instaladores e jogo), instaladores do Minecraft e Google Play Games.
  - **Navegadores Indesejados:** Instaladores do Opera GX e Brave.
  - **VPNs (para impedir evasão de rede):** UltraSurf, Psiphon, ProtonVPN, NordVPN, Cloudflare WARP, Hotspot Shield, UrbanVPN, TunnelBear, Windscribe, OpenVPN e WireGuard.

### [7] Bloquear Microsoft Store
- Impede o acesso dos alunos à Loja do Windows para evitar o download de aplicativos paralelos (`RemoveWindowsStore = 1`).
- **Preservação de Aplicativos Essenciais:** Não bloqueia os utilitários nativos empacotados do Windows. Aplicativos essenciais como **Calculadora**, **Bloco de Notas** (Win 11), **Fotos**, **Ferramenta de Captura**, **Paint** (Win 11) e **Câmera** continuam funcionando perfeitamente (a diretiva restritiva `DisableStoreApps` foi removida para evitar que o Windows exiba o aviso de "bloqueado pelo administrador").

### [8] Proteger Atalhos da Área de Trabalho
- Aplica permissão somente-leitura aos atalhos na Área de Trabalho Pública (`C:\Users\Public\Desktop`), impedindo que alunos excluam ou modifiquem os ícones dos programas da escola.

### [9] Instalar e Configurar NetTime
- Sincronização forçada de data e hora via internet para notebooks com CMOS descarregada.
- **Verificação Inteligente:** Se o NetTime já estiver instalado no computador, o script apenas valida e garante que o serviço está rodando em inicialização automática, sem baixar nem reinstalar nada.

### [10] Desativar Busca Web no Menu Iniciar (Bing Search)
- Faz com que ao digitar no Iniciar/Barra de tarefas a pesquisa procure **exclusivamente por aplicativos e arquivos locais do Windows**.
- Remove completamente resultados da web, prévias do Bing e buscas online na internet, tornando a pesquisa instantânea, leve e sem consumir banda de rede.

---

## 🛠️ Recursos Adicionais do Menu

### [5] Limpar Perfis de Alunos Inativos (> 2 meses)
- **Varredura Segura:** Identifica perfis institucionais de alunos inativos há mais de 60 dias.
- **Seleção Interativa:** Apresenta lista com caixas `[X]` pré-marcadas, permitindo desmarcar qualquer aluno que desejar poupar antes da exclusão.
- **Blindagem:** Administradores, perfis de sistema, contas `alunos`, `BlueLab` e escolas (`ARACATUBA*`) são 100% imunes.

### [7] Reportar Problema ou Sugerir Melhoria
- Permite ao técnico relatar erros de execução ou enviar ideias de melhoria diretamente do terminal.
- Coleta opcionalmente Nome e Cidade/Escola e anexa diagnóstico de hardware (Windows, RAM, espaço em disco) de forma segura e transparente.

---

## 🚀 Como Executar
1. Clique com o botão direito no arquivo `Configurar-Escola.ps1` e selecione **Executar com o PowerShell**.
2. O script exige privilégios de **Administrador**. Se executado sem permissão, ele solicita automaticamente a elevação de privilégios pelo UAC.

---

## 📦 Repositório Oficial e Versionamento
Código-fonte, controle de versão e melhorias disponíveis no GitHub:
🔗 [https://github.com/JulioAntunes00/script_otimizacao_windows](https://github.com/JulioAntunes00/script_otimizacao_windows)

---

## 👨‍💻 Autor
Desenvolvido por **Julio Antunes**
* GitHub: [@JulioAntunes00](https://github.com/JulioAntunes00)
* Repositório: [script_otimizacao_windows](https://github.com/JulioAntunes00/script_otimizacao_windows)
