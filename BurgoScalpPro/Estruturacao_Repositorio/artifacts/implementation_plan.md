# Plano de Organização e Documentação do Repositório - BurgoScalpPro

Este plano define a reestruturação e a padronização do repositório **BurgoScalpPro** (Expert Advisor de Scalping & Grid para MetaTrader 5 em MQL5), garantindo a organização do código-fonte por versão, a criação de documentações técnicas completas e o estabelecimento de boas práticas para manter a integridade das versões futuras.

---

## Estrutura Atual vs. Estrutura Proposta

### Estado Atual
Atualmente, o repositório contém os arquivos soltos na raiz:
- `Burgo Scalpe Pro V41.mq5`
- `Burgo Scalpe Pro V42.mq5`
- `Burgo Scalpe Pro V43 XAUUSD M1.mq5`
- Ausência de `.gitignore`, `README.md`, guia de parâmetros, arquitetura ou histórico formal de alterações (`CHANGELOG.md`).

### Estrutura Alvo Proposta
```
BurgoScalpPro/
├── .gitignore                      # Filtro para ignorar binários (.ex5), logs e arquivos temporários do MT5
├── README.md                       # Documentação principal com visão geral, instalação e instrução de uso
├── CHANGELOG.md                    # Histórico detalhado da evolução (V41 -> V42 -> V43)
├── CONTRIBUTING.md                 # Guia para desenvolvimento, compilação no MetaEditor e padrão de git
├── docs/
│   ├── ARCHITECTURE.md             # Arquitetura técnica (motores de grid, filtros, painel GUI, proteção de equity)
│   └── PARAMETERS.md               # Guia explicativo de todos os parâmetros input e faixas recomendadas
├── presets/
│   └── README.md                   # Orientações sobre arquivos .set de configuração por ativo (ex: XAUUSD M1)
└── src/
    ├── Burgo Scalpe Pro V43 XAUUSD M1.mq5  # Versão mais recente e otimizada (XAUUSD M1)
    ├── Burgo Scalpe Pro V42.mq5            # Versão 42 (Filtro CHOP + Hard Equity Stop)
    └── Burgo Scalpe Pro V41.mq5            # Versão 41 (Anti-Oscilação ADX + Cooldown)
```

---

## Mudanças Propostas

### 1. Governança e Arquivos de Raiz
- `[NEW]` [`.gitignore`](file:///c:/Users/Vini_Burgo/Documents/BurgoScalpPro/.gitignore): Ignorar `.ex5`, logs do MetaTrader 5 (`*.log`), pastas `.logs`, arquivos temporários do Strategy Tester e arquivos de ambiente do IDE.
- `[NEW]` [`README.md`](file:///c:/Users/Vini_Burgo/Documents/BurgoScalpPro/README.md): Documento principal em Português cobrindo:
  - Visão geral do bot **Burgo Scalpe Pro**.
  - Destaque para a versão ativa / produção (`V43 XAUUSD M1`).
  - Funcionalidades principais (Grid Progressivo, Hard Equity Stop, Filtro CHOP, EMA200, ATR, ADX).
  - Guia rápido de instalação no MetaTrader 5 (compilação no MetaEditor).
  - Aviso de risco financeiro (*Risk Disclaimer*).
- `[NEW]` [`CHANGELOG.md`](file:///c:/Users/Vini_Burgo/Documents/BurgoScalpPro/CHANGELOG.md): Histórico estruturado detalhando melhorias da V41 à V43.
- `[NEW]` [`CONTRIBUTING.md`](file:///c:/Users/Vini_Burgo/Documents/BurgoScalpPro/CONTRIBUTING.md): Diretrizes para manutenção do código, controle de versão e boas práticas no MQL5.

---

### 2. Pasta de Documentação Técnica (`docs/`)
- `[NEW]` [`docs/ARCHITECTURE.md`](file:///c:/Users/Vini_Burgo/Documents/BurgoScalpPro/docs/ARCHITECTURE.md):
  - Fluxo de execução (`OnInit`, `OnTick`, `OnDeinit`, `OnChartEvent`).
  - Módulos de filtragem de entrada (ADX, ATR, CHOP, EMA200, RSI).
  - Motor de Grid Progressivo e cálculo dinâmico de lotes.
  - Mecanismos de Gestão de Risco (Hard Equity Stop %, Max Drawdown %, Trailing Stop em USD).
  - Sistema de painel interativo direto no gráfico.
- `[NEW]` [`docs/PARAMETERS.md`](file:///c:/Users/Vini_Burgo/Documents/BurgoScalpPro/docs/PARAMETERS.md):
  - Tabela explicativa de cada grupo de entrada (`input group`).
  - Parâmetros específicos da V43 para XAUUSD no timeframe M1.
  - Recomendações de gerenciamento de risco de acordo com a banca.

---

### 3. Organização dos Códigos Fontes (`src/`) e Presets (`presets/`)
- `[NEW]` Mover códigos fontes da raiz para `src/`:
  - `src/Burgo Scalpe Pro V43 XAUUSD M1.mq5`
  - `src/Burgo Scalpe Pro V42.mq5`
  - `src/Burgo Scalpe Pro V41.mq5`
- `[DELETE]` Remover arquivos `.mq5` da raiz para evitar duplicação.
- `[NEW]` [`presets/README.md`](file:///c:/Users/Vini_Burgo/Documents/BurgoScalpPro/presets/README.md): Instruções para salvar e carregar presets `.set` no MetaTrader 5.

---

### 4. Controle de Versão (Git)
- Executar commit organizado com mensagem clara e padronizada utilizando a nova estrutura.

---

## Plano de Verificação

### Validação da Organização
1. Verificar integridade dos arquivos movidos para `src/` garantindo que nenhuma linha de código MQL5 foi corrompida.
2. Garantir que os caminhos e referências nos documentos apontam corretamente para os arquivos na pasta `src/`.
3. Testar a sintaxe dos arquivos markdown gerados.
