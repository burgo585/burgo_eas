import pandas as pd
from test_nas100_sunrise import prepare_nas100_indicators, run_nas100_simulation, compute_forensic_metrics

def main():
    df = prepare_nas100_indicators(pd.read_parquet('data/NAS100_M15.parquet'))
    split_date = pd.to_datetime('2026-01-01 00:00:00+00:00')
    df_oos = df[df['datetime'] >= split_date].copy().reset_index(drop=True)

    print("=== OTIMIZAÇÃO DE PARÂMETROS NAS100 (SESSÃO NY 13:30-20:00 UTC) ===")
    print(f"{'SL_ATR':<6} | {'RR_RATIO':<8} | {'Total Ret':<10} | {'Total PF':<8} | {'OOS Ret':<10} | {'OOS PF':<8} | {'MaxDD%':<6}")
    print("-" * 70)

    for sl_mult in [1.0, 1.2, 1.5, 2.0]:
        for rr in [1.2, 1.5, 1.8, 2.0, 2.5]:
            tr, eq = run_nas100_simulation(df, session_mode='ny_core', sl_atr_mult=sl_mult, rr_ratio=rr)
            m = compute_forensic_metrics(tr, eq)
            tr_oos, eq_oos = run_nas100_simulation(df_oos, session_mode='ny_core', sl_atr_mult=sl_mult, rr_ratio=rr)
            m_oos = compute_forensic_metrics(tr_oos, eq_oos)
            print(f"{sl_mult:<6.1f} | {rr:<8.1f} | {m['total_return']:>+9.1f}% | {m['profit_factor']:>8.2f} | {m_oos['total_return']:>+9.1f}% | {m_oos['profit_factor']:>8.2f} | {m['max_dd_pct']:>5.1f}%")

if __name__ == '__main__':
    main()
