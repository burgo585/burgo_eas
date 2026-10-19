---
name: quant-forensic-auditor
description: >-
  Audits and executes strictly causal, microstructure-accurate quantitative backtests
  for MQL4/MQL5 Expert Advisors (EAs), Python trading scripts, Backtrader, PineScript,
  and financial Machine Learning pipelines. Activate this skill whenever the user asks
  to create, test, simulate, optimize, debug, or audit any trading robot, strategy,
  `.mq5`/`.set` file, or financial ML model. Enforces zero lookahead bias, real broker
  swap/commission/slippage extraction from MetaTrader 5, causal intrabar execution
  (no wick-teleportation), and rolling-window Risk of Ruin (Stop-Out) calculation.
---

# Quantitative Forensic Auditor & Causal Backtesting Skill (Sunrise Protocol)

This skill enforces strict scientific skepticism, zero sycophancy, and institutional-grade microstructure accuracy across all algorithmic trading and financial ML tasks.

## Mandatory Workflow

Whenever a user requests a backtest, simulation, parameter optimization, or strategy review:

### Step 1: Pre-Flight Audit for Data Leakage & Microstructure Bugs
1. **If evaluating Python / Machine Learning scripts**, run the static AST/pattern scanner:
   ```powershell
   python "C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\scripts\ml_leakage_scanner.py" "<path_to_script.py>"
   ```
2. **Consult the Forensic Checklist**: See [forensic_checklist.md](./references/forensic_checklist.md) to verify that none of the 5 classic backtest illusions are present:
   - **Illusion #1 (Wick-Top/Bottom Take-Profit Teleportation)**: Never credit floating profit calculated at the bar's `High` or `Low` (`balance += floating_profit`) when a fixed target (`TargetUSD`) is crossed. Cap realized profit strictly at `TargetUSD`.
   - **Illusion #2 (Wick-Bottom Grid Fill & Single-Order Cap)**: Never use a single `if` evaluated at `Low`/`High` to open grid orders at the extreme wick price. Use a `while` loop that triggers all breached grid levels sequentially at their exact trigger prices (`last_price +/- distance +/- slippage`), and evaluate Margin/Stop-Out at the bar's worst excursion with **all** triggered orders open.
   - **Illusion #3 (Intrabar Time Travel)**: In bearish bars (`Close < Open`), price moves `Open -> High -> Low -> Close`. Buy grid orders opened during the drop to `Low` must **never** be evaluated against the bar's `High` (which occurred in the past); they can only be evaluated at `Close`. In conservative mode, prohibit opening at `Low` and closing at `High` within the same M15 candle, and prohibit multiple re-entries inside a single OHLC leg.
   - **Illusion #4 (Intrabar Indicator Lookahead)**: Every bar-based indicator (`EMA`, `ATR`, `RSI`, `Bollinger`) used during bar `t` MUST be shifted by 1 closed bar (`.shift(1)` in pandas; `CopyBuffer(..., shift=1)` in MQL5).
   - **Illusion #5 (Zero-Cost Fiction)**: Never run a simulation with `swap = 0` or `commission = 0`. Extract real specifications from the local MetaTrader 5 terminal.

### Step 2: Execute the Official Causal Backtester & Rolling Risk-of-Ruin Engine
Run the standardized causal backtester script:
- Script path: [mt5_causal_backtester.py](./scripts/mt5_causal_backtester.py)
- You can invoke it via CLI or import `CausalGridBacktester` / `extract_mt5_specs` in Python:
  ```powershell
  python "C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\scripts\mt5_causal_backtester.py" --symbol "XAUUSD-ECN" --balance 100 --leverage 500 --mode "BUY_ONLY" --dist 300 --lot 0.01 --mult 1.2 --max-orders 4 --target-side 3.0 --target-global 15.0
  ```
- The engine automatically:
  1. Connects to `C:\MetaTrader\terminal64.exe` and extracts real `swap_long`, `swap_short`, `swap_rollover3days`, `spread`, `trade_contract_size`, and account `leverage`.
  2. Runs the **Strictly Causal Simulation** over the full historical dataset with real Swap, ECN Commission, and Slippage.
  3. Runs the **30+ Monthly Rolling Start-Date Falsification Test** (starting a fresh account on the 1st of every month) to compute the true **Probability of Ruin (`Stop-Out %`)**.
  4. Calculates the **Minimum Realistic Capital Required** to survive the worst historical shock without Stop-Out.
  5. Can optionally generate a verified `.ini` configuration file (`Model=4`, Every tick based on real ticks) for native MetaTrader 5 Strategy Tester execution.

### Step 3: Mandatory Reporting Format for the User
Always present the **Painel de Realidade e Risco de Ruína** at the very top of your response, in plain, accessible Portuguese free of hype adjectives:

| Métrica de Realidade Forense | Valor Auditado | Significado Prático para o seu Bolso |
| :--- | :---: | :--- |
| **Veredito Forense** | `[APROVADO COM RESSALVAS]` ou `[ALTO RISCO DE QUEBRA / REPROVADO]` | Diagnóstico direto sem elogios falsos |
| **Taxa de Falência em Meses Aleatórios (*Risk of Ruin*)** | `X / Y meses (Z%)` | Em quantos meses do histórico a banca quebra se ligada no dia 1º |
| **Pior Rebaixamento Flutuante Real (`MaxDD_USD`)** | `-US$ X.XXX,XX (Y%)` | Maior prejuízo aberto simultâneo que a conta precisou aguentar |
| **Custos Ocultos Pagos (Swap + Comissão ECN)** | `-US$ X.XXX,XX` | Dinheiro comido pelas taxas noturnas e corretagem |
| **Banca Mínima Realista Recomendada** | `US$ X.XXX,XX` | Capital mínimo real para não tomar Stop-Out no pior choque do ativo |
