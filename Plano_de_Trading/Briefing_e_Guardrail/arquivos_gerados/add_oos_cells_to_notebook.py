import json

def add_oos_section():
    nb_path = 'btcusd_guardrail_backtest_v3.ipynb'
    with open(nb_path, 'r', encoding='utf-8') as f:
        nb = json.load(f)

    md_cell = {
        "cell_type": "markdown",
        "metadata": {},
        "source": [
            "## 🔬 7. Prova de Robustez: In-Sample (2024–2025) vs. Out-of-Sample (2026)\n",
            "\n",
            "Para eliminar qualquer suspeita de **sobreajuste (overfitting / curva ajustada ao passado)**, o histórico é dividido estritamente em dois blocos temporais independentes:\n",
            "\n",
            "1. **In-Sample (Treino / Calibração):** `20/02/2024 até 31/12/2025` (~63.196 barras, 71% dos dados).\n",
            "2. **Out-of-Sample (Teste Cego / Dados Nunca Vistos):** `01/01/2026 até 30/09/2026` (~25.580 barras, 29% dos dados).\n",
            "\n",
            "> **Critério Institucional de Aprovação:** Uma estratégia possui borda matemática (*edge*) real quando o desempenho no Out-of-Sample se mantém positivo e não colapsa."
        ]
    }

    code_cell = {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": [
            "# Execução da Validação In-Sample vs. Out-of-Sample\n",
            "split_date = pd.to_datetime('2026-01-01 00:00:00+00:00')\n",
            "\n",
            "df_is = df[df['datetime'] < split_date].copy().reset_index(drop=True)\n",
            "df_oos = df[df['datetime'] >= split_date].copy().reset_index(drop=True)\n",
            "\n",
            "# 1. Simulação In-Sample\n",
            "trades_is, eq_is, costs_is, _ = run_institutional_backtest_with_costs(\n",
            "    df_is, rr_ratio=2.0, initial_capital=1000.0, use_session_filter=True\n",
            ")\n",
            "\n",
            "# 2. Simulação Out-of-Sample\n",
            "trades_oos, eq_oos, costs_oos, _ = run_institutional_backtest_with_costs(\n",
            "    df_oos, rr_ratio=2.0, initial_capital=1000.0, use_session_filter=True\n",
            ")\n",
            "\n",
            "def get_summary(label, tdf, eq_df, costs, initial=1000.0):\n",
            "    wins = tdf[tdf['net_pnl'] > 0]\n",
            "    losses = tdf[tdf['net_pnl'] <= 0]\n",
            "    wr = (len(wins) / len(tdf)) * 100\n",
            "    final = eq_df['equity'].iloc[-1]\n",
            "    ret = ((final - initial) / initial) * 100\n",
            "    pf = wins['net_pnl'].sum() / abs(losses['net_pnl'].sum())\n",
            "    eq_df['peak'] = eq_df['equity'].cummax()\n",
            "    mdd = abs(((eq_df['equity'] - eq_df['peak']) / eq_df['peak'] * 100).min())\n",
            "    rets = eq_df['equity'].pct_change().dropna()\n",
            "    sharpe = (rets.mean() / rets.std()) * np.sqrt(252 * 24 * 4) if rets.std() > 0 else 0\n",
            "    return {\n",
            "        'Conjunto': label,\n",
            "        'Trades': len(tdf),\n",
            "        'Win Rate (%)': f\"{wr:.2f}%\",\n",
            "        'Profit Factor': f\"{pf:.2f}\",\n",
            "        'Retorno Líquido (%)': f\"{ret:+.2f}%\",\n",
            "        'Saldo Final': f\"${final:,.2f}\",\n",
            "        'Max Drawdown (%)': f\"{mdd:.2f}%\",\n",
            "        'Sharpe Ratio': f\"{sharpe:.2f}\",\n",
            "        'Custos Pagos ($)': f\"${costs['spread'] + costs['swap']:,.2f}\"\n",
            "    }\n",
            "\n",
            "s_is = get_summary('In-Sample (2024–2025)', trades_is, eq_is, costs_is)\n",
            "s_oos = get_summary('Out-of-Sample (2026 Cego)', trades_oos, eq_oos, costs_oos)\n",
            "\n",
            "df_comparison = pd.DataFrame([s_is, s_oos])\n",
            "print(\"=\"*75)\n",
            "print(f\"{'COMPARATIVO CIENTÍFICO: IN-SAMPLE vs. OUT-OF-SAMPLE':^75}\")\n",
            "print(\"=\"*75)\n",
            "display(df_comparison)\n",
            "\n",
            "# Gráfico Comparativo de Trajetória\n",
            "fig_oos = make_subplots(rows=1, cols=2, subplot_titles=('In-Sample: 2024–2025', 'Out-of-Sample: 2026 (Cego)'))\n",
            "fig_oos.add_trace(go.Scatter(x=eq_is['datetime'], y=eq_is['equity'], line=dict(color='#29B6F6', width=2), name='In-Sample ($1k)'), row=1, col=1)\n",
            "fig_oos.add_trace(go.Scatter(x=eq_oos['datetime'], y=eq_oos['equity'], line=dict(color='#00E676', width=2), name='Out-of-Sample ($1k)'), row=1, col=2)\n",
            "fig_oos.update_layout(height=450, title='Trajetória de Patrimônio: Calibração vs. Teste Cego', template='plotly_dark')\n",
            "fig_oos.show()"
        ]
    }

    nb['cells'].append(md_cell)
    nb['cells'].append(code_cell)

    with open(nb_path, 'w', encoding='utf-8') as f:
        json.dump(nb, f, indent=1)

    print("[SUCESSO] Seção In-Sample vs. Out-of-Sample adicionada ao notebook!")

if __name__ == '__main__':
    add_oos_section()
