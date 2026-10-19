import pandas as pd
import numpy as np

def analyze():
    df = pd.read_csv('BTCXAU_M15_202610020100_202610021845.csv', sep='\t')
    df.columns = [c.replace('<', '').replace('>', '').lower() for c in df.columns]
    df['datetime'] = pd.to_datetime(df['date'] + ' ' + df['time'])

    # Indicators
    df['ema_20'] = df['close'].ewm(span=20, adjust=False).mean()
    df['ema_50'] = df['close'].ewm(span=50, adjust=False).mean()
    
    prev_close = df['close'].shift(1)
    tr1 = df['high'] - df['low']
    tr2 = (df['high'] - prev_close).abs()
    tr3 = (df['low'] - prev_close).abs()
    df['tr'] = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    df['atr'] = df['tr'].rolling(14).mean()

    # PVSRA
    df['avg_vol'] = df['tickvol'].rolling(10).mean()
    df['candle_spread'] = (df['close'] - df['open']).abs()
    df['avg_spread'] = df['candle_spread'].rolling(10).mean()

    df['vol_ratio'] = df['tickvol'] / df['avg_vol']
    df['is_climax'] = (df['tickvol'] >= 2.0 * df['avg_vol']) | ((df['tickvol'] * df['candle_spread']) >= (2.0 * df['avg_vol'] * df['avg_spread']))
    df['is_rising'] = (df['tickvol'] >= 1.5 * df['avg_vol'])

    print("=== ANÁLISE DETALHADA DAS BARRAS DE 14:30 A 18:45 ===")
    subset = df[df['time'] >= '14:30:00'].copy()
    
    for _, r in subset.iterrows():
        body = r['close'] - r['open']
        rng = r['high'] - r['low']
        upper_wick = r['high'] - max(r['open'], r['close'])
        lower_wick = min(r['open'], r['close']) - r['low']
        
        status = "NORMAL"
        if r['is_climax']:
            status = "CLIMAX"
        elif r['is_rising']:
            status = "RISING"

        print(f"{r['time']} | O:{r['open']:.5f} H:{r['high']:.5f} L:{r['low']:.5f} C:{r['close']:.5f} | "
              f"Vol:{r['tickvol']:<4} ({r['vol_ratio']:.2f}x avg) [{status:<6}] | "
              f"Body:{body:+.5f} | Wicks(U:{upper_wick:.5f}, L:{lower_wick:.5f}) | ATR:{r['atr']:.5f}")

if __name__ == '__main__':
    analyze()
