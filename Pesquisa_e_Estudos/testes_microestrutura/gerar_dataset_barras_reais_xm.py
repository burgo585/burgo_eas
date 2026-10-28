import os
import time
import polars as pl

CSV_PATH = r'C:\Users\Vini_Burgo\OneDrive\Documents\Robo\Marcus\GOLD_202312201206_202610260330ticksXM.csv'
OUT_DIR = r'C:\Users\Vini_Burgo\Documents\burgo_eas\Pesquisa_e_Estudos\testes_microestrutura'
M5_PARQUET = os.path.join(OUT_DIR, 'xauusd_m5_xm_real_ticks.parquet')
M15_PARQUET = os.path.join(OUT_DIR, 'xauusd_m15_xm_real_ticks.parquet')

print("=== PROTOCOLO SUNRISE: CONVERSAO CAUSAL DE 212M TICKS REAIS XM -> BARRAS M5 & M15 ===")
print(f"Origem: {CSV_PATH} ({os.path.getsize(CSV_PATH) / (1024**3):.2f} GB)")

t0 = time.time()

q_m5 = (
    pl.scan_csv(
        CSV_PATH,
        separator='\t',
        has_header=True,
        ignore_errors=True,
        schema_overrides={
            '<DATE>': pl.String,
            '<TIME>': pl.String,
            '<BID>': pl.Float64,
            '<ASK>': pl.Float64,
            '<LAST>': pl.String,
            '<VOLUME>': pl.String,
            '<FLAGS>': pl.Int64
        }
    )
    .select([
        pl.concat_str([pl.col('<DATE>').str.replace_all(r'\.', '-'), pl.lit(' '), pl.col('<TIME>')]).str.to_datetime(strict=False).dt.truncate('5m').alias('time'),
        pl.col('<BID>').forward_fill().alias('bid'),
        pl.col('<ASK>').forward_fill().alias('ask'),
    ])
    .filter(pl.col('time').is_not_null() & pl.col('bid').is_not_null() & pl.col('ask').is_not_null())
    .with_columns((pl.col('ask') - pl.col('bid')).alias('spread'))
    .group_by('time')
    .agg([
        pl.col('bid').first().alias('open'),
        pl.col('bid').max().alias('high'),
        pl.col('bid').min().alias('low'),
        pl.col('bid').last().alias('close'),
        pl.col('ask').first().alias('ask_open'),
        pl.col('ask').max().alias('ask_high'),
        pl.col('ask').min().alias('ask_low'),
        pl.col('ask').last().alias('ask_close'),
        pl.col('spread').mean().round(3).alias('spread_mean'),
        pl.col('spread').max().round(3).alias('spread_max'),
        pl.col('spread').min().round(3).alias('spread_min'),
        pl.len().alias('ticks')
    ])
    .sort('time')
)

print("Iniciando agregacao streaming de M5...")
df_m5 = q_m5.collect(engine='streaming')
t_m5 = time.time()
print(f"M5 concluido: {len(df_m5):,} barras em {t_m5 - t0:.2f}s")

# Salvar M5 Parquet
df_m5.write_parquet(M5_PARQUET, compression='zstd')
print(f"Salvo: {M5_PARQUET} ({os.path.getsize(M5_PARQUET) / (1024**2):.2f} MB)")

# Agregar M15 a partir do M5
print("Agregando M15 a partir do M5...")
df_m15 = (
    df_m5
    .with_columns(pl.col('time').dt.truncate('15m').alias('time_15m'))
    .group_by('time_15m')
    .agg([
        pl.col('open').first().alias('open'),
        pl.col('high').max().alias('high'),
        pl.col('low').min().alias('low'),
        pl.col('close').last().alias('close'),
        pl.col('ask_open').first().alias('ask_open'),
        pl.col('ask_high').max().alias('ask_high'),
        pl.col('ask_low').min().alias('ask_low'),
        pl.col('ask_close').last().alias('ask_close'),
        pl.col('spread_mean').mean().round(3).alias('spread_mean'),
        pl.col('spread_max').max().round(3).alias('spread_max'),
        pl.col('spread_min').min().round(3).alias('spread_min'),
        pl.col('ticks').sum().alias('ticks')
    ])
    .rename({'time_15m': 'time'})
    .sort('time')
)
t_m15 = time.time()
print(f"M15 concluido: {len(df_m15):,} barras em {t_m15 - t_m5:.2f}s")

# Salvar M15 Parquet
df_m15.write_parquet(M15_PARQUET, compression='zstd')
print(f"Salvo: {M15_PARQUET} ({os.path.getsize(M15_PARQUET) / (1024**2):.2f} MB)")

# Resumo Estatistico
start_dt = df_m5['time'].min()
end_dt = df_m5['time'].max()
spread_p50 = df_m5['spread_mean'].median()
spread_p95 = df_m5['spread_mean'].quantile(0.95)

print("\n=== RESUMO DO DATASET RECONSTRUIDO ===")
print(f"Periodo: {start_dt} ate {end_dt}")
print(f"Total de Barras M5:  {len(df_m5):,}")
print(f"Total de Barras M15: {len(df_m15):,}")
print(f"Spread Medio Mediano: {spread_p50:.3f} ($ {spread_p50*100:.1f} pts)")
print(f"Spread P95 (95% do tempo abaixo de): {spread_p95:.3f} ($ {spread_p95*100:.1f} pts)")
print(f"Tempo total de processamento: {time.time() - t0:.2f}s")
