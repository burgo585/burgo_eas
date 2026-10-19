# 🔒 Diretrizes de Segurança do Sistema, Idioma e Integridade de Dados

1. **Comunicação 100% em Português do Brasil (Pt-Br)**:
   - O usuário não é fluente em inglês. Todas as respostas, explicações, resumos, alertas e pedidos de confirmação devem ser elaborados **estritamente em Português do Brasil (Pt-Br)** de forma clara, direta e acessível, evitando jargões obscuros em inglês que possam gerar mal-entendidos.

2. **Proibição de Edição de Registro do Sistema**:
   - **NUNCA** modificar, criar ou deletar chaves/valores do Registro do Windows (`reg.exe`, `regedit`, `Set-ItemProperty` em `HKLM` ou `HKCU`, etc.).

3. **Isolamento de Arquivos no Drive C: (Escopo do Workspace)**:
   - Todas as operações de criação, edição e leitura de arquivos devem permanecer estritamente **restritas ao diretório do workspace** (`c:\Users\Vini_Burgo\Documents\BurgoScalpPro`).
   - **NUNCA** alterar ou deletar arquivos de sistema, pastas do Windows ou diretórios fora do workspace.
   - Caso uma tarefa necessite obrigatoriamente acessar/modificar arquivos fora do workspace na partição `C:`, avalie e apresente **no mínimo 3 alternativas técnicas** em Pt-Br antes de solicitar qualquer autorização.

4. **Prevenção Contra Comandos Destrutivos**:
   - **NUNCA** executar comandos destrutivos no sistema operacional (ex: `rmdir /s`, `Remove-Item -Recurse` em caminhos do sistema, `format`, exclusão de partições ou bancos de dados).
   - Qualquer operação irreversível ou sensível exige explicação clara e confirmação prévia e explícita do usuário em Português (Pt-Br).
