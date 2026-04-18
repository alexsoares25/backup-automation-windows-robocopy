# backup-automation-windows-robocopy
Automated Windows backup system using PowerShell, Robocopy and Task Scheduler, with daily execution, mirroring and scalable structure for logs and data protection.
📦 Backup Automation System (Windows + Robocopy)

Sistema de backup automatizado baseado em PowerShell + Robocopy + Task Scheduler, projetado para ambientes locais com foco em confiabilidade, simplicidade operacional e baixo custo.

📌 Objetivo

Garantir cópia automática e contínua dos dados do disco principal (E:) para um disco secundário (D:), com execução agendada e mínima intervenção manual.

⚙️ Funcionamento
Origem: E:\ (dados principais)
Destino: D:\BACKUP_DADOS\espelho
Execução automática diária
Script PowerShell acionado via Task Scheduler
Espelhamento completo utilizando Robocopy
🧠 Arquitetura do Sistema
E:\                      # Fonte de dados
│
└── (Robocopy /MIR)
     ↓
D:\BACKUP_DADOS\
   ├── espelho\          # Backup principal (espelhado)
   ├── logs\             # Logs de execução
   └── quarentena\       # (estrutura futura)
🚀 Execução Automatizada

O sistema utiliza o Agendador de Tarefas do Windows:

Frequência: Diária
Horário: 20:00
Execução com privilégios elevados
Script chamado:
C:\Backup\backup.ps1
📜 Script de Backup

Exemplo base utilizado:

robocopy E:\ D:\BACKUP_DADOS\espelho /MIR /R:3 /W:5 /LOG:D:\BACKUP_DADOS\logs\backup.log
Parâmetros:
Parâmetro	Função
/MIR	Espelhamento completo
/R:3	3 tentativas em caso de erro
/W:5	Espera de 5 segundos entre tentativas
/LOG	Registro de execução
⚠️ Risco Estrutural Atual

O uso de /MIR implica comportamento destrutivo:

❗ Se um arquivo for apagado na origem (E:), ele também será apagado no backup.

🛡️ Melhorias Recomendadas
1. Sistema de Quarentena

Antes de exclusões, mover arquivos para:

D:\BACKUP_DADOS\quarentena\
2. Versionamento

Manter histórico de alterações:

backup_2026-04-18\
backup_2026-04-19\
3. Backup Incremental

Evitar cópia total sempre:

Reduz tempo
Reduz desgaste do HD
Melhora performance
4. Monitoramento
Logs estruturados
Alertas em falhas
Integração futura com dashboard (SGDT)
🧩 Stack Tecnológica
PowerShell
Robocopy (nativo Windows)
Task Scheduler
