---
description: Sempre incluir no final de cada resolução um leitor de áudio interativo avançado para o usuário ouvir o resumo do que foi feito.
trigger: always_on
---

# Regra Global: Leitor de Áudio em Todas as Resoluções

O usuário configurou como regra obrigatória que, ao finalizar qualquer resolução, tarefa, entrega ou explicação em qualquer projeto no Antigravity, você DEVE SEMPRE fornecer no final um leitor interativo de voz com controle completo para que ele escute o que foi feito.

## Requisitos do Widget de Áudio:
1. **Motor de Reprodução em Sentenças (Chunking)**:
   - Divida o texto do resumo em frases/trechos (`splitSentences`). Isso garante que:
     - A alteração de **velocidade** (0.75x a 2.0x) funcione **instantaneamente** e em tempo real.
     - O usuário tenha botões de **Avançar trecho (⏭️)** e **Voltar trecho (⏮️)**.
     - A função **Pausar (⏸️)** e **Continuar (▶️)** funcione sem travar o motor de áudio.
2. **Controles Obrigatórios no Player**:
   - Botão principal: `▶️ Ouvir Resposta` / `⏸️ Pausar` / `▶️ Continuar`
   - Botão `Avançar ⏭️` (pula para o próximo trecho)
   - Botão `⏮️ Voltar` (retorna ao trecho anterior)
   - Botão `⏹️` (para a reprodução e reseta ao início)
   - Seletor de Velocidade com alteração imediata (0.75x, 1.0x, 1.25x, 1.5x, 1.75x, 2.0x)
   - Barra de progresso visual e exibição do trecho falado no momento.
3. **Localização do Arquivo e Embed**:
   - Salve o arquivo em `<appDataDir>/brain/<conversation-id>/audio_reader.html`.
   - Adicione no fim exato da resposta a tag:
     `<agent-embed src="file:///<artifact_path>/audio_reader.html"></agent-embed>`
