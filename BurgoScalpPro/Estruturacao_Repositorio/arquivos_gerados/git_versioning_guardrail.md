# 🛡️ Diretrizes de Guardrail e Versionamento Git Local

1. **Repositório Exclusivamente Local**:
   - O projeto utiliza controle de versão **Git 100% LOCAL**.
   - **NÃO** tente configurar, integrar ou enviar (`git push`) para repositórios remotos (GitHub, GitLab, Bitbucket, etc.). O projeto deve permanecer estritamente local.

2. **Critério para Execução de Commits**:
   - Apenas realize `git commit` após validar que as alterações fazem sentido técnico, estão organizadas, testadas e preservam a integridade do repositório local.
   - Commits devem ser acompanhados da aplicação prévia da avaliação crítica (Skill `evaluate-change-request`).

3. **Padrão Obrigatório para Novos Projetos**:
   - Em todos os novos projetos criados pelo usuário no futuro, estabeleça imediatamente um **repositório Git LOCAL** como boa prática para versionamento e proteção contra perda de dados.
