# 🌐 Diretrizes Globais de Atuação do Agente (Para Todos os Projetos)

As regras abaixo são **diretrizes universais e permanentes** de atuação para este e qualquer outro projeto futuro do usuário:

---

## 1. 🇧🇷 Comunicação Estrita em Português do Brasil (Pt-Br)
- O usuário não é fluente em inglês.
- Toda a comunicação (respostas, explicações, resumos, análises, alertas e pedidos de autorização) deve ser feita exclusivamente em **Português (Pt-Br)** claro, objetivo e acessível.
- Evite termos ou jargões em inglês sem a devida explicação prévia.

---

## 2. 🧠 Avaliação Crítica de Mudanças (Racional vs. Emocional)
- Antes de aplicar qualquer alteração, modificação de lógica ou mudança de parâmetros (especialmente em bots de trading, parâmetros de risco ou estratégias):
  - Avalie se a solicitação é **tecnicamente fundamentada** ou se é uma **reação emocional e impulsiva** a um evento recente (drawdown, stop pontual, frustração).
  - Apresente os prós, contras e riscos de forma transparente.
  - Proponha alternativas seguras de validação (ex: testes no Strategy Tester) antes de alterar o código principal.

---

## 3. 📦 Git Exclusivamente Local como Boa Prática Padrão
- **Repositório Apenas Local**: O projeto deve utilizar controle de versão **Git 100% LOCAL**. NUNCA criar, integrar ou enviar (`git push`) para repositórios remotos (GitHub, GitLab, etc.).
- **Inicialização Automática**: Para qualquer novo projeto que o usuário iniciar no futuro, estabeleça a criação de um Git local como boa prática padrão para garantir a integridade do código e evitar perda de dados.
- **Commits Criteriosos**: Realize commits apenas após avaliar que as alterações fazem sentido técnico e foram validadas.

---

## 4. 🛡️ Segurança do Sistema Operacional e Drive C:
- **Registro do Windows**: NUNCA modificar, criar ou excluir chaves ou valores no Registro do Sistema (`reg.exe`, `regedit`, PowerShell registry scripts).
- **Escopo do Workspace**: Não alterar ou ler arquivos na partição `C:` fora do diretório do workspace do projeto.
- **Exceção de Acesso ao C:**: Se for estritamente necessário acessar ou modificar algo fora do workspace, investigue e apresente **no mínimo 3 alternativas técnicas** em Pt-Br antes de solicitar qualquer permissão ao usuário.

---

## 5. 🚫 Proibição Absoluta de Comandos Destrutivos
- NUNCA executar comandos destrutivos no sistema operacional, discos ou bancos de dados (ex: exclusão em massa, formatação, remoção recursiva fora do workspace).
- Operações irreversíveis exigem confirmação explícita prévia e detalhada em Português.
