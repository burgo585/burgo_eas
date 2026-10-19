# 🚀 Burgo EAs — Ecossistema Quantitativo de Trading & Sistemas Algorítmicos

Repositório centralizado e governado de robôs de investimento (Expert Advisors MQL5/MQL4), indicadores técnicos proprietários, presets (.set), motores Python de backtest causal forense e inteligência quantitativa de mercado.

---

## 📊 Inventário Geral de Ativos Quantitativos

| Categoria | Quantidade | Principais Ativos / Tecnologias |
| :--- | :---: | :--- |
| **Robôs / EAs MT5** | **19 Sistemas** | `Burgo Scalpe Pro` (V40, V41, V42, V43, V50), `Robô Virada de Delta Pro`, `Robô Frasson Alta Frequência PRO`, `Valid BOS Bookmap EA`, `BoletaScalping MQL5`, `Robo POC Orderflows` |
| **Indicadores MT5 & Pine** | **5 Indicadores** | `CanalDrawer.mq5`, `MTR_Volume_AT_Price_Pro.mq5`, `Valid_BOS_Pullback.pine`, `Valid_BOS_Bookmap_Ind.mq5` |
| **Presets Calibrados (.set)** | **23 Presets** | XAUUSD (Ouro M1, M5, M15), BTCUSD (M5, VTMarkets), NAS100 / MNQ (M1, New York), MES (12R Renko, Frasson) |
| **Scripts Python & Backtest** | **104 Scripts** | Motores de backtest causal, Monte Carlo, simulação de estresse, teste de ruína (Protocolo Sunrise) e ML leakage scanner |
| **Documentação & Manuais** | **30+ Manuais** | Arquitetura MQL5, parâmetros de risco, manuais operacionais e relatórios forenses em Markdown |

---

## 📁 Estrutura Temática de Pastas de Trading

### 1. `BurgoScalpPro/`
Robô insignia de scalping com canais dinâmicos, grade inteligente e controle de exposição no Ouro (XAUUSD) e Forex.
- `Repositorio_Oficial/`: Código-fonte oficial incorporado de Documents (`Burgo Scalpe Pro V41, V42, V43 M1`), manuais de arquitetura (`docs/ARCHITECTURE.md`), parâmetros (`docs/PARAMETERS.md`) e regras de versionamento.
- `Desenvolvimento_MQL5/`: Versão base compilável no terminal MT5.
- `Backtests_XAUUSD_2Anos/`: Relatórios e dados históricos de simulação.
- `Otimizacao_XAUUSD_Lucro/`: Scripts de otimização de lucro e curvas de retorno.
- `Ajustes_MagicNumber_v50/`: Refatoração para versão 5.0 com múltiplos identificadores mágicos.
- `Correcoes_Codigo_e_Sets/`: Presets otimizados para M1, M5 e M15.

### 2. `Robo_Virada_de_Delta/`
Sistemas focados em microestrutura, absorção, fluxo institucional (Orderflows) e atratores não lineares.
- `Automacao_Virada_Delta_Pro/`: Implementação do núcleo de atrator não linear (`Nonlinear_Attractor_Core.mqh`), PVSRA (`PVSRA_Core.mqh`) e gerenciamento de risco (`Risk_Manager.mqh`).
- `Robo_Frasson_Alta_Frequencia/`: Versão profissional otimizada para MNQ, MES e XAUUSD com 20 relatórios de calibração.
- `Valid_BOS_Pullback_e_Bookmap/`: Integração híbrida PineScript + MQL5 + Java Bridge com a plataforma Bookmap.
- `Robo_POC_Orderflows/`: Estratégia de POC desenvolvida com base na metodologia Mike Valtos.

### 3. `Auditoria_Quant_Forense/`
Blindagem quantitativa, auditoria causal e Protocolo Sunrise.
- `Protocolo_Sunrise_Auditoria/`: Motores oficiais `mt5_causal_backtester.py`, scanner de vazamento temporal `ml_leakage_scanner.py` e auditoria de risco de ruína em janelas móveis.

### 4. `BoletaScalping/`
Interface gráfica (GUI) customizada para MetaTrader 5 com disparo de ordens a mercado, ordens pendentes, cálculo automático de lote e integração com canais.
- `Interface_GUI_MQL5/`: Componente visual e boleta de scalping.
- `Boleta_Com_Canais/`: Acoplamento direto entre as marcações de canal e os gatilhos da boleta.

### 5. `Indicadores_MT5/`
Ferramentas analíticas nativas em MQL5.
- `CanalDrawer/`: Traçador automático de canais e zonas de suporte/resistência.
- `MTR_Volume_AT_Price/`: Perfil de volume institucional acumulado por nível de preço.

### 6. `Plano_de_Trading/`
Plano operacional, robôs de teste e integrações.
- `Briefing_e_Guardrail/`: Configuração de regras operacionais e bot BTCUSD.
- `Auditoria_Robos_MT5/`: Verificação de dados de ticks e barras da pasta MT5.
- `Fabio_Valentim_TRAX/`: Robô baseado no sistema TRAX e técnica do Leo para Ouro.

### 7. `Automacao_de_Aprendizado/`
Ambiente web interativo com dashboard para acompanhamento de operações e parâmetros.

### 8. `Projeto_Mikael_Orderflows/`
Ferramentas de transcrição e visão computacional para análise de frames de aulas e setups de fluxo institucional.

### 9. `Relatorios_e_Analises/`
Geração automatizada de relatórios em PDF profissional (`ReportLab`) de inteligência de mercado financeiro.

### 10. `Pesquisa_e_Estudos/`
Cadernos de pesquisa em finanças quantitativas:
- `Traders_Historicos_Forex/` & `Traders_Brasileiros_Forex/`
- `Grid_e_Martingale/`: Análise estocástica de rebaixamento e quebra em grades.
- `Analise_Tecnica_Oscilacoes/`: Técnicas anti-whipsaw em consolidações.
- `Macroeconomia_BOJ/`: Modelagem de impacto de política monetária global.

---

## 🛡️ Governança e Regras de Segurança
- **Repositório Otimizado**: Mantém histórico de código, scripts, documentação e parâmetros, excluindo binários transitórios e arquivos gigantes de mídia.
- **Microestrutura Realista**: Todos os scripts de backtest incorporam custos de Swap noturno triplo, comissões ECN reais e slippage.
