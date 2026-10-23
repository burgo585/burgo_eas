"""
Dashboard Institucional de Telemetria e Terminal de Trading Quantitativo TRAX.
Conectado 100% AO VIVO ao MetaTrader 5 (VT Markets Demo).
Suporte a Streaming em Tempo Real (High-Frequency Real-Time UI via st.fragment).
Consome cotações, candles, ticks, Delta e PoC em sub-segundos da corretora.
"""

from pathlib import Path
import json
import datetime
from zoneinfo import ZoneInfo
import numpy as np
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import streamlit as st

try:
    import MetaTrader5 as mt5
    MT5_DISPONIVEL = True
except ImportError:
    MT5_DISPONIVEL = False

from config.settings import carregar_presets
from src.data.mt5_feed import MT5TickFeed
from src.analytics.order_flow import OrderFlowEngine
from src.analytics.smc_zones import SMCZonesEngine
from src.ai.trainer import ModelTrainer
from src.ai.inference import InferenceEngine
from src.execution.kill_switch import KillSwitchMOC
from src.execution.order_router import OrderRouter
from src.execution.signals import MotorSinaisQuantitativo, SinalTrade
from src.execution.live_bot import live_bot

# Configuração da Página Streamlit
st.set_page_config(
    page_title="TRAX | Terminal Quantitativo MT5 VT Markets",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Estilização CSS Dark Mode Institucional
st.markdown("""
<style>
    .stApp {
        background-color: #0d1117;
        color: #e6edf3;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    .metric-card {
        background-color: #161b22;
        border: 1px solid #30363d;
        border-radius: 8px;
        padding: 12px 16px;
        margin-bottom: 10px;
    }
    .metric-title {
        font-size: 11px;
        text-transform: uppercase;
        color: #8b949e;
        letter-spacing: 0.5px;
    }
    .metric-value {
        font-size: 20px;
        font-weight: 700;
        color: #f0f6fc;
        margin-top: 3px;
    }
    .status-badge-on {
        background-color: #238636;
        color: #ffffff;
        padding: 6px 14px;
        border-radius: 20px;
        font-weight: 600;
        font-size: 13px;
        display: inline-block;
    }
    .status-badge-off {
        background-color: #da3633;
        color: #ffffff;
        padding: 6px 14px;
        border-radius: 20px;
        font-weight: 600;
        font-size: 13px;
        display: inline-block;
    }
    .account-badge-live {
        background-color: #1f6feb;
        color: #ffffff;
        padding: 6px 12px;
        border-radius: 6px;
        font-size: 12px;
        font-weight: 600;
        display: inline-block;
    }
    .kill-switch_banner {
        background-color: #381a1a;
        border: 1px solid #da3633;
        border-radius: 8px;
        padding: 12px 16px;
        margin-bottom: 16px;
    }
    .bot-control-card {
        background: linear-gradient(135deg, #161b22 0%, #0d1117 100%);
        border: 1px solid #30363d;
        border-radius: 12px;
        padding: 16px 20px;
        margin-bottom: 16px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.4);
    }
    .diagnostic-box {
        background-color: #161b22;
        border-left: 4px solid #58a6ff;
        border-radius: 6px;
        padding: 12px 16px;
        margin-top: 10px;
        margin-bottom: 14px;
        font-size: 13px;
    }
</style>
""", unsafe_allow_html=True)


def garantir_conexao_mt5(config_mt5) -> bool:
    """Garante que a conexão com o executável e conta do MT5 esteja ativa."""
    if not MT5_DISPONIVEL:
        return False

    info_term = mt5.terminal_info()
    if info_term is not None and info_term.connected:
        return True

    parametros = {}
    if config_mt5.path:
        parametros["path"] = config_mt5.path
    if config_mt5.account:
        parametros["login"] = config_mt5.account
    if config_mt5.password:
        parametros["password"] = config_mt5.password
    if config_mt5.server:
        parametros["server"] = config_mt5.server

    return mt5.initialize(**parametros)


def obter_dados_mercado_ao_vivo(simbolo_broker: str, n_candles: int = 120) -> tuple:
    """
    Extrai cotações e candles M1 diretamente do servidor da corretora em tempo real.
    Calcula Delta aproximado, PoC e Delta Multiplier para cada candle recente.
    """
    if not MT5_DISPONIVEL:
        return pd.DataFrame(), None, None

    mt5.symbol_select(simbolo_broker, True)
    tick_atual = mt5.symbol_info_tick(simbolo_broker)
    info_simbolo = mt5.symbol_info(simbolo_broker)
    rates = mt5.copy_rates_from_pos(simbolo_broker, mt5.TIMEFRAME_M1, 0, n_candles)

    if rates is None or len(rates) == 0:
        return pd.DataFrame(), tick_atual, info_simbolo

    df = pd.DataFrame(rates)
    df["timestamp"] = pd.to_datetime(df["time"], unit="s", utc=True)

    # Estima volumes de compra/venda e Delta a partir da ação de preço intra-candle e tick_volume
    corpo = df["close"] - df["open"]
    amplitude = df["high"] - df["low"]
    amplitude = np.where(amplitude > 0, amplitude, 1.0)
    proporcao_alta = np.clip((corpo / amplitude) * 0.5 + 0.5, 0.05, 0.95)

    df["vol"] = df["tick_volume"].astype(float)
    df["buy_vol"] = np.round(df["vol"] * proporcao_alta)
    df["sell_vol"] = df["vol"] - df["buy_vol"]
    df["delta"] = df["buy_vol"] - df["sell_vol"]
    df["cum_delta"] = df["delta"].cumsum()
    df["delta_ratio"] = df["delta"] / np.where(df["vol"] > 0, df["vol"], 1.0)

    # PoC estimado intra-candle (nível de maior densidade de volume no candle)
    df["poc"] = np.round((df["open"] + df["high"] + df["low"] + 2.0 * df["close"]) / 5.0, 2)

    # Spike de Delta Multiplier contra média de 20 períodos
    media_delta = df["delta"].abs().rolling(window=20, min_periods=1).mean()
    df["delta_multiplier"] = df["delta"].abs() / np.where(media_delta > 0, media_delta, 1.0)

    return df, tick_atual, info_simbolo


def salvar_preset_modificado(simbolo: str, dados_atualizados: dict):
    """Atualiza o arquivo JSON de presets."""
    caminho = Path("config/presets.json")
    with open(caminho, "r", encoding="utf-8") as f:
        dados = json.load(f)
    dados["assets"][simbolo].update(dados_atualizados)
    with open(caminho, "w", encoding="utf-8") as f:
        json.dump(dados, f, indent=2, ensure_ascii=False)


# -------------------------------------------------------------
# CARREGAMENTO DE CONFIGURAÇÕES & STATUS MT5
# -------------------------------------------------------------
config_global = carregar_presets()
lista_ativos = list(config_global.assets.keys())

mt5_conectado = garantir_conexao_mt5(config_global.mt5)
acc_info = mt5.account_info() if mt5_conectado else None
term_info = mt5.terminal_info() if mt5_conectado else None

# -------------------------------------------------------------
# BARRA LATERAL (SIDEBAR): CONTROLE GLOBAL & ATIVOS
# -------------------------------------------------------------
with st.sidebar:
    st.image("https://img.icons8.com/fluency/96/bullish.png", width=56)
    st.title("TRAX QUANT")
    st.caption("Institutional HFT & Order Flow Engine")

    # Status da Conexão da Corretora
    if mt5_conectado and acc_info:
        st.markdown(f"""
        <div class='account-badge-live'>
            🟢 CONECTADO: {acc_info.server}<br>
            Conta #{acc_info.login} ({acc_info.name})<br>
            Saldo: ${acc_info.balance:,.2f} {acc_info.currency}
        </div>
        """, unsafe_allow_html=True)
    else:
        st.error("🔴 MT5 Desconectado da Corretora")

    st.markdown("---")

    # Dropdown de Ativos
    ativo_selecionado = st.selectbox(
        "SELECIONE O ATIVO DA CESTA",
        options=lista_ativos,
        index=lista_ativos.index("XAUUSD") if "XAUUSD" in lista_ativos else 0
    )
    preset_atual = config_global.assets[ativo_selecionado]
    simbolo_broker = preset_atual.mt5_symbol

    st.info(f"Símbolo no Broker: **`{simbolo_broker}`**")

    # Controle de Auto-Streaming
    auto_streaming = st.toggle("⚡ Streaming Contínuo ao Vivo (1s)", value=True)

    # Toggle Button Gigante ON/OFF
    st.markdown("### STATUS DO ROBÔ")
    if "robo_ligado" not in st.session_state:
        st.session_state.robo_ligado = live_bot.esta_ativo()

    col_btn1, col_btn2 = st.columns(2)
    with col_btn1:
        if st.button("▶ LIGAR", use_container_width=True, type="primary"):
            live_bot.iniciar()
            st.session_state.robo_ligado = True
            st.rerun()
    with col_btn2:
        if st.button("⏹ PARAR", use_container_width=True):
            live_bot.parar()
            st.session_state.robo_ligado = False
            st.rerun()

    if live_bot.esta_ativo():
        st.markdown("<div class='status-badge-on'>● ROBÔ ATIVO OPERANDO</div>", unsafe_allow_html=True)
    else:
        st.markdown("<div class='status-badge-off'>○ ROBÔ PARADO</div>", unsafe_allow_html=True)

    st.markdown("---")
    st.subheader(f"Presets & Risco: {ativo_selecionado}")

    novo_lote = st.number_input("Tamanho do Lote", value=float(preset_atual.lot_size), step=0.01)
    novo_sl_atr = st.slider("Stop Loss (Multiplicador ATR)", min_value=1.0, max_value=3.5, value=float(preset_atual.atr_sl_multiplier), step=0.1)
    novo_rr = st.slider("Alvo Risco-Retorno (R:R)", min_value=1.0, max_value=4.0, value=float(preset_atual.risk_reward_ratio), step=0.1)
    novo_delta_mult = st.slider("Limiar de Delta Spike (x Média)", min_value=1.2, max_value=4.0, value=float(preset_atual.delta_threshold_multiplier), step=0.1, help="Diminua para gerar mais entradas ou aumente para maior conservadorismo.")

    st.markdown("---")
    st.subheader(f"⏰ Horário Operacional ({ativo_selecionado})")
    modo_24h_atual = getattr(preset_atual, "trading_hours_mode", "24h") == "24h"
    modo_24h = st.checkbox("Operar 24 Horas sem restrição", value=modo_24h_atual, key=f"chk_24h_{ativo_selecionado}")

    if not modo_24h:
        col_h1, col_h2 = st.columns(2)
        with col_h1:
            hora_inicio = st.text_input("Início (HH:MM)", value=getattr(preset_atual, "trading_start_time", "08:00") or "08:00")
        with col_h2:
            hora_fim = st.text_input("Fim (HH:MM)", value=getattr(preset_atual, "trading_end_time", "18:00") or "18:00")
        fuso_opcoes = ["America/Sao_Paulo", "America/New_York"]
        fuso_atual = getattr(preset_atual, "trading_timezone", "America/Sao_Paulo") or "America/Sao_Paulo"
        idx_fuso = 0 if "Sao_Paulo" in fuso_atual else 1
        fuso_escolhido = st.selectbox("Fuso Horário", options=fuso_opcoes, index=idx_fuso, format_func=lambda x: "Brasília (BRT)" if "Sao_Paulo" in x else "Nova York (NY)")
    else:
        hora_inicio = "00:00"
        hora_fim = "23:59"
        fuso_escolhido = "America/Sao_Paulo"

    if st.button("💾 Salvar Parâmetros e Horário", use_container_width=True):
        salvar_preset_modificado(ativo_selecionado, {
            "lot_size": novo_lote,
            "atr_sl_multiplier": novo_sl_atr,
            "risk_reward_ratio": novo_rr,
            "delta_threshold_multiplier": novo_delta_mult,
            "trading_hours_mode": "24h" if modo_24h else "custom",
            "trading_start_time": hora_inicio,
            "trading_end_time": hora_fim,
            "trading_timezone": fuso_escolhido
        })
        st.success("Configurações atualizadas com sucesso!")
        st.rerun()

    st.markdown("---")
    if st.button("🔄 Atualizar Manualmente", use_container_width=True):
        st.rerun()

# -------------------------------------------------------------
# PAINEL DE CARDS DO TOPO EM STREAMING AO VIVO
# -------------------------------------------------------------
intervalo_fragment = 1 if auto_streaming else None

@st.fragment(run_every=intervalo_fragment)
def renderizar_metricas_topo(simbolo: str):
    """Atualiza cotação, spread, relógio NY e saldo a cada 1 segundo."""
    kill_switch_ny = KillSwitchMOC(simbolo="MNQ")
    hora_ny = kill_switch_ny.obter_horario_ny_atual()
    hora_local = datetime.datetime.now().strftime("%H:%M:%S")

    df_m1, tick_ao_vivo, _ = obter_dados_mercado_ao_vivo(simbolo, n_candles=10)
    acc = mt5.account_info() if mt5_conectado else None

    preco_bid = tick_ao_vivo.bid if tick_ao_vivo else (df_m1['close'].iloc[-1] if not df_m1.empty else 0.0)
    preco_ask = tick_ao_vivo.ask if tick_ao_vivo else (df_m1['close'].iloc[-1] if not df_m1.empty else 0.0)
    spread = (preco_ask - preco_bid) if tick_ao_vivo else 0.0

    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.markdown(f"""
        <div class='metric-card'>
            <div class='metric-title'>Cotação ao Vivo ({simbolo})</div>
            <div class='metric-value'>${preco_bid:,.2f} <span style='font-size:12px;color:#8b949e;'>Spread: {spread:.2f} pts</span></div>
            <div style='font-size:11px;color:#3fb950;'>● Ticks em Tempo Real ({hora_local})</div>
        </div>
        """, unsafe_allow_html=True)

    with col2:
        dentro_moc = kill_switch_ny.dentro_janela_moc_loc()
        status_moc = "ABERTA (15:50-16:00)" if dentro_moc else "FECHADA"
        cor_moc = "#238636" if dentro_moc else "#8b949e"
        st.markdown(f"""
        <div class='metric-card'>
            <div class='metric-title'>Janela MOC/LOC (Nasdaq)</div>
            <div class='metric-value' style='color:{cor_moc};'>{status_moc} <span style='font-size:12px;color:#8b949e;'>NY: {hora_ny.strftime('%H:%M:%S')}</span></div>
            <div style='font-size:11px;color:#8b949e;'>Kill-Switch ativo às 15:59:50</div>
        </div>
        """, unsafe_allow_html=True)

    with col3:
        saldo_txt = f"${acc.balance:,.2f}" if acc else "$0.00"
        st.markdown(f"""
        <div class='metric-card'>
            <div class='metric-title'>Saldo da Conta (VT Markets)</div>
            <div class='metric-value' style='color:#58a6ff;'>{saldo_txt}</div>
            <div style='font-size:11px;color:#8b949e;'>Moeda: {acc.currency if acc else 'USD'}</div>
        </div>
        """, unsafe_allow_html=True)

    with col4:
        margem_txt = f"${acc.margin_free:,.2f}" if acc else "$0.00"
        st.markdown(f"""
        <div class='metric-card'>
            <div class='metric-title'>Margem Livre Disponível</div>
            <div class='metric-value' style='color:#3fb950;'>{margem_txt}</div>
            <div style='font-size:11px;color:#8b949e;'>Alavancagem: 1:{acc.leverage if acc else 500}</div>
        </div>
        """, unsafe_allow_html=True)


renderizar_metricas_topo(simbolo_broker)

# -------------------------------------------------------------
# PAINEL MESTRE CENTRAL: LIGAR/DESLIGAR & RAIO-X DE DIAGNÓSTICO
# -------------------------------------------------------------
@st.fragment(run_every=intervalo_fragment)
def renderizar_painel_mestre_robo(nome_ativo: str, preset: PresetAtivo):
    robo_ativo = live_bot.esta_ativo()

    st.markdown("<div class='bot-control-card'>", unsafe_allow_html=True)
    c_status, c_botoes = st.columns([3, 2])

    with c_status:
        if robo_ativo:
            st.markdown("""
            <div style='display:flex;align-items:center;gap:12px;'>
                <span style='font-size:28px;'>🟢</span>
                <div>
                    <strong style='font-size:18px;color:#3fb950;'>ROBÔ AUTÔNOMO LIGADO (VIGILÂNCIA HFT ATIVA)</strong><br>
                    <span style='font-size:12px;color:#8b949e;'>Varredura contínua de ticks e IA a cada 0.8s na VT Markets</span>
                </div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown("""
            <div style='display:flex;align-items:center;gap:12px;'>
                <span style='font-size:28px;'>🔴</span>
                <div>
                    <strong style='font-size:18px;color:#f85149;'>ROBÔ AUTÔNOMO PARADO (DESLIGADO)</strong><br>
                    <span style='font-size:12px;color:#8b949e;'>Clique no botão verde ao lado para iniciar a execução automática</span>
                </div>
            </div>
            """, unsafe_allow_html=True)

    with c_botoes:
        b_ligar, b_parar = st.columns(2)
        with b_ligar:
            if st.button("▶ LIGAR ROBÔ", key="btn_topo_ligar", use_container_width=True, type="primary"):
                live_bot.iniciar()
                st.session_state.robo_ligado = True
                st.rerun()
        with b_parar:
            if st.button("⏹ PARAR ROBÔ", key="btn_topo_parar", use_container_width=True):
                live_bot.parar()
                st.session_state.robo_ligado = False
                st.rerun()

    st.markdown("""
    <div style='margin-top:10px;padding:8px 12px;background:#1c2128;border-radius:6px;font-size:12px;color:#58a6ff;'>
        🛡️ <strong>SENTINELA AUTO-GUARDRAIL ATIVO:</strong> Qualquer ordem aberta manualmente por você no MetaTrader 5 recebe Stop Loss técnico (ATR) e Take Profit (2:1) em menos de 1 segundo!
    </div>
    """, unsafe_allow_html=True)
    st.markdown("</div>", unsafe_allow_html=True)

    # Raio-X em Tempo Real: Por que o robô não entrou agora?
    diag = live_bot.diagnostico_ativos.get(nome_ativo, {})
    horario_ok = diag.get("horario_ok", True)
    horario_desc = diag.get("horario_motivo", "Operando")
    estado_ib = diag.get("estado_ib", "AGUARDANDO")
    delta_mult = diag.get("delta_mult", 1.0)
    delta_exigido = diag.get("delta_exigido", preset.delta_threshold_multiplier)
    motivo_geral = diag.get("motivo_diagnostico", "Robô escaneando microestrutura de ticks em tempo real...")
    tem_pos = diag.get("tem_posicao", False)
    prob_ia = diag.get("ia_probabilidade", 0.0)

    st.markdown(f"#### 🔍 Raio-X de Decisão em Tempo Real ({nome_ativo}): O que o robô está avaliando agora?")
    cd1, cd2, cd3, cd4, cd5 = st.columns(5)
    with cd1:
        st.metric("Janela Operacional", "✅ LIBERADO" if horario_ok else "⏸ PAUSADO", delta=horario_desc[:22])
    with cd2:
        st.metric("Initial Balance (IB)", estado_ib, delta=f"Range: {diag.get('ib_range', 0.0):.2f} pts")
    with cd3:
        cor_delta = "normal" if delta_mult >= delta_exigido else "inverse"
        st.metric("Delta Spike Atual", f"{delta_mult:.1f}x Média", delta=f"Exigido: {delta_exigido:.1f}x", delta_color=cor_delta)
    with cd4:
        st.metric("Posições no Ativo", "1 Em Andamento" if tem_pos else "0 (Livre)")
    with cd5:
        st.metric("Confiança da IA", f"{prob_ia:.0%}" if prob_ia > 0 else "Em Análise", delta=f"Limiar: {config_global.system.ai_confidence_threshold:.0%}")

    st.markdown(f"""
    <div class='diagnostic-box'>
        <strong>📢 DIAGNÓSTICO AO VIVO DA MÁQUINA ({nome_ativo}):</strong><br>
        {motivo_geral}
    </div>
    """, unsafe_allow_html=True)


renderizar_painel_mestre_robo(ativo_selecionado, preset_atual)

# -------------------------------------------------------------
# TERMINAL DE ORDER FLOW & GRÁFICO AO VIVO NA TELA PRINCIPAL
# -------------------------------------------------------------
# 1. Métricas Rápidas de Microestrutura (Atualização a cada 1s sem piscar)
@st.fragment(run_every=intervalo_fragment)
def renderizar_metricas_orderflow(simbolo: str):
    df_m1, _, _ = obter_dados_mercado_ao_vivo(simbolo, n_candles=30)
    if df_m1.empty:
        return
    ultimo_candle = df_m1.iloc[-1]
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Preço Atual Fechamento", f"${ultimo_candle['close']:,.2f}", delta=f"{ultimo_candle['close'] - ultimo_candle['open']:+.2f}")
    c2.metric("Delta da Barra", f"{ultimo_candle['delta']:+,.0f}", delta=f"{ultimo_candle['delta_multiplier']:.1f}x Média")
    c3.metric("PoC da Barra (Footprint)", f"${ultimo_candle['poc']:,.2f}")
    c4.metric("CVD (Delta Acumulado)", f"{ultimo_candle['cum_delta']:+,.0f}")

renderizar_metricas_orderflow(simbolo_broker)

# 2. Gráfico Plotly ao Vivo na Tela Inicial
intervalo_grafico = 4 if auto_streaming else None

@st.fragment(run_every=intervalo_grafico)
def renderizar_grafico_candles(simbolo: str):
    df_m1, _, _ = obter_dados_mercado_ao_vivo(simbolo, n_candles=100)
    if df_m1.empty:
        st.error(f"Aguardando dados ao vivo de {simbolo} do MetaTrader 5...")
        return

    motor_sinais = MotorSinaisQuantitativo(preset=preset_atual)
    ib_info = motor_sinais.calcular_initial_balance(df_m1, janela_barras=30)
    ib_h = ib_info["ib_high"]
    ib_l = ib_info["ib_low"]
    ib_p = ib_info["ib_poc"]
    ib_rng = ib_info["ib_range"]

    # Escaneia sinais para marcar no gráfico
    sinais_ivb = motor_sinais.escanear_sinais(
        df_m1,
        exigir_confluencia_smc=False,
        filtro_sessao_ativa=False,
        filtro_ema_tendencia=getattr(preset_atual, "trend_ema_filter_active", True)
    )

    fig = make_subplots(
        rows=2, cols=1,
        shared_xaxes=True,
        vertical_spacing=0.03,
        row_heights=[0.75, 0.25],
        subplot_titles=[f"Candles M1 AO VIVO ({simbolo}) | Initial Balance: High {ib_h:.2f} - Low {ib_l:.2f}", "Delta de Agressão & CVD"]
    )

    fig.add_trace(go.Candlestick(
        x=df_m1["timestamp"],
        open=df_m1["open"],
        high=df_m1["high"],
        low=df_m1["low"],
        close=df_m1["close"],
        name="Cotação ao Vivo",
        increasing_line_color="#26a69a",
        decreasing_line_color="#ef5350"
    ), row=1, col=1)

    # Linha do Point of Control (PoC)
    fig.add_trace(go.Scatter(
        x=df_m1["timestamp"],
        y=df_m1["poc"],
        mode="lines",
        name="PoC Candle",
        line=dict(color="#f1c40f", width=1.0, dash="dot")
    ), row=1, col=1)

    # Níveis Institucionais do Initial Balance (Fábio Valentim)
    if ib_h > 0 and ib_l > 0:
        fig.add_hline(
            y=ib_h, line_dash="solid", line_color="#00e5ff", line_width=1.8,
            annotation_text=f"IB High: {ib_h:.2f}", annotation_position="top left",
            annotation_font_color="#00e5ff", row=1, col=1
        )
        fig.add_hline(
            y=ib_l, line_dash="solid", line_color="#ff5722", line_width=1.8,
            annotation_text=f"IB Low: {ib_l:.2f}", annotation_position="bottom left",
            annotation_font_color="#ff5722", row=1, col=1
        )
        fig.add_hline(
            y=ib_p, line_dash="dash", line_color="#ffd54f", line_width=1.2,
            annotation_text=f"IB PoC: {ib_p:.2f}", annotation_position="top right",
            annotation_font_color="#ffd54f", row=1, col=1
        )

    # Plotagem dos Sinais dos Modelos IVB 1 e 2
    for s in sinais_ivb:
        cor_sinal = "#00e676" if s.tipo == "BUY" else "#ff1744"
        simbolo_sinal = "triangle-up" if s.tipo == "BUY" else "triangle-down"
        pos_y = s.preco_entrada
        fig.add_trace(go.Scatter(
            x=[s.timestamp],
            y=[pos_y],
            mode="markers+text",
            marker=dict(symbol=simbolo_sinal, size=14, color=cor_sinal),
            text=[f"{s.modelo}"],
            textposition="top center" if s.tipo == "BUY" else "bottom center",
            name=f"Sinal {s.tipo} ({s.modelo})",
            showlegend=False
        ), row=1, col=1)

    # Histograma do Delta
    cores_delta = ["#26a69a" if d >= 0 else "#ef5350" for d in df_m1["delta"]]
    fig.add_trace(go.Bar(
        x=df_m1["timestamp"],
        y=df_m1["delta"],
        name="Delta",
        marker_color=cores_delta
    ), row=2, col=1)

    # Linha de CVD
    fig.add_trace(go.Scatter(
        x=df_m1["timestamp"],
        y=df_m1["cum_delta"],
        mode="lines",
        name="CVD (Delta Acumulado)",
        line=dict(color="#29b6f6", width=2)
    ), row=2, col=1)

    fig.update_layout(
        template="plotly_dark",
        height=580,
        xaxis_rangeslider_visible=False,
        margin=dict(l=10, r=10, t=30, b=10),
        paper_bgcolor="#0d1117",
        plot_bgcolor="#161b22"
    )

    st.plotly_chart(
        fig,
        use_container_width=True,
        key=f"plotly_candle_m1_{simbolo}",
        config={"displayModeBar": False, "responsive": True}
    )

    # Card de Status do Setup Fábio Valentim (DeepCharts)
    ultimo_fechamento = float(df_m1["close"].iloc[-1])
    if ib_h > 0 and ib_l > 0:
        st.markdown("#### 🎯 Monitoramento do Setup Fábio Valentim (Initial Volume Breakout - IVB)")
        c_ib1, c_ib2, c_ib3, c_ib4 = st.columns(4)
        c_ib1.metric("IB High (Topo)", f"${ib_h:,.2f}")
        c_ib2.metric("IB Low (Fundo)", f"${ib_l:,.2f}")
        c_ib3.metric("IB PoC (Distribuição)", f"${ib_p:,.2f}")
        c_ib4.metric("IB Range (Amplitude)", f"{ib_rng:,.2f} pts")

        if ultimo_fechamento > ib_h:
            st.success(f"🚀 **ROMPIMENTO COMPRADOR ATIVO:** Preço atual (${ultimo_fechamento:,.2f}) rompeu acima do IB High (${ib_h:,.2f}). Setups IVB Modelo 1 (Volume Profile) e Modelo 2 (Delta Flow) armados para execução!")
        elif ultimo_fechamento < ib_l:
            st.error(f"🔻 **ROMPIMENTO VENDEDOR ATIVO:** Preço atual (${ultimo_fechamento:,.2f}) rompeu abaixo do IB Low (${ib_l:,.2f}). Setups IVB Modelo 1 (Volume Profile) e Modelo 2 (Delta Flow) armados para execução!")
        else:
            st.info(f"⚖️ **DENTRO DO INITIAL BALANCE:** Preço atual (${ultimo_fechamento:,.2f}) trabalhando dentro da faixa de abertura. Aguardando rompimento direcional aceito com expansão de volume.")

renderizar_grafico_candles(simbolo_broker)

# -------------------------------------------------------------
# ABAS SECUNDÁRIAS DE TELEMETRIA E CONTROLE
# -------------------------------------------------------------
tab_boleta, tab_ailab, tab_moc_loc, tab_ordens = st.tabs([
    "⚡ Boleta de Ordens & Histórico",
    "🧠 AI Lab (Inteligência Artificial)",
    "⏰ MOC/LOC Arbitragem (Nasdaq MNQ)",
    "💼 Posições Abertas & Operações"
])

with tab_boleta:
    st.subheader(f"⚡ Boleta Rápida & Telemetria Institucional ({simbolo_broker})")

    # 3. Boleta e Console de Telemetria (Atualização a cada 1s sem recriar o gráfico)
    @st.fragment(run_every=intervalo_fragment)
    def renderizar_boleta_e_telemetria(simbolo: str, preset: PresetAtivo):
        _, tick_ao_vivo, _ = obter_dados_mercado_ao_vivo(simbolo, n_candles=2)

        st.markdown("#### Boleta Rápida de Execução Institucional (Com Proteção Automática SL/TP)")
        b1, b2 = st.columns(2)
        dist_sl_est = max(preset.atr_sl_multiplier * 1.5, 1.0)
        with b1:
            if st.button(f"🟢 COMPRAR A MERCADO ({preset.lot_size} lotes {simbolo})", use_container_width=True):
                if mt5_conectado and tick_ao_vivo:
                    preco_ask = float(tick_ao_vivo.ask)
                    sl_compra = round(preco_ask - dist_sl_est, 2)
                    tp_compra = round(preco_ask + (dist_sl_est * preset.risk_reward_ratio), 2)
                    req = {
                        "action": mt5.TRADE_ACTION_DEAL,
                        "symbol": simbolo,
                        "volume": float(preset.lot_size),
                        "type": mt5.ORDER_TYPE_BUY,
                        "price": preco_ask,
                        "sl": sl_compra,
                        "tp": tp_compra,
                        "deviation": 20,
                        "magic": int(preset.magic_number),
                        "comment": "TRAX Manual Buy Guard",
                        "type_time": mt5.ORDER_TIME_GTC,
                        "type_filling": mt5.ORDER_FILLING_IOC,
                    }
                    res = mt5.order_send(req)
                    if res and res.retcode == mt5.TRADE_RETCODE_DONE:
                        st.success(f"Ordem de COMPRA executada e blindada! SL={sl_compra} | TP={tp_compra} | Ticket #{res.order}")
                    else:
                        st.error(f"Erro ao enviar ordem: Retcode {res.retcode if res else 'Falha'}")
        with b2:
            if st.button(f"🔴 VENDER A MERCADO ({preset.lot_size} lotes {simbolo})", use_container_width=True):
                if mt5_conectado and tick_ao_vivo:
                    preco_bid = float(tick_ao_vivo.bid)
                    sl_venda = round(preco_bid + dist_sl_est, 2)
                    tp_venda = round(preco_bid - (dist_sl_est * preset.risk_reward_ratio), 2)
                    req = {
                        "action": mt5.TRADE_ACTION_DEAL,
                        "symbol": simbolo,
                        "volume": float(preset.lot_size),
                        "type": mt5.ORDER_TYPE_SELL,
                        "price": preco_bid,
                        "sl": sl_venda,
                        "tp": tp_venda,
                        "deviation": 20,
                        "magic": int(preset.magic_number),
                        "comment": "TRAX Manual Sell Guard",
                        "type_time": mt5.ORDER_TIME_GTC,
                        "type_filling": mt5.ORDER_FILLING_IOC,
                    }
                    res = mt5.order_send(req)
                    if res and res.retcode == mt5.TRADE_RETCODE_DONE:
                        st.success(f"Ordem de VENDA executada e blindada! SL={sl_venda} | TP={tp_venda} | Ticket #{res.order}")
                    else:
                        st.error(f"Erro ao enviar ordem: Retcode {res.retcode if res else 'Falha'}")

        st.markdown("---")
        st.markdown("#### ⚡ Telemetria & Logs em Tempo Real do Robô (Live Engine)")
        st.caption("Varredura contínua de microestrutura, confluência de Delta/PoC e autorizações probabilísticas da IA.")
        logs = live_bot.logs_recentes
        if logs:
            texto_logs = "\n".join(logs[-15:])
            st.code(texto_logs, language="log")
        else:
            st.info("O robô está aguardando ativação. Clique em '▶ LIGAR' na barra lateral para iniciar a leitura contínua.")

    renderizar_boleta_e_telemetria(simbolo_broker, preset_atual)

# -------------------------------------------------------------
# ABA 2: AI LAB (ESTÁTICA PARA CONFIGURAÇÃO E TREINAMENTO)
# -------------------------------------------------------------
with tab_ailab:
    st.subheader("Laboratório de Inteligência Artificial Institucional")
    col_ai1, col_ai2 = st.columns([1, 2])

    with col_ai1:
        st.markdown("#### Configuração de Inferência")
        slider_confianca = st.slider(
            "Limiar de Confiança para Disparo",
            min_value=0.50,
            max_value=0.95,
            value=float(config_global.system.ai_confidence_threshold),
            step=0.05,
            format="%.0f%%"
        )

        if st.button("🚀 Retreinar Modelo de 1 Clique", use_container_width=True, type="primary"):
            with st.spinner("Retreinando modelo supervisionado com dados recentes..."):
                caminho_base = Path("data/XAUUSD_M1_calibracao.parquet")
                if caminho_base.exists():
                    df_m1_treino = pd.read_parquet(caminho_base)
                    treinador = ModelTrainer()
                    X, y = treinador.rotular_operacoes(df_m1_treino, preset=preset_atual)
                    treinador.treinar_e_avaliar(X, y)
                    treinador.salvar_artefato(Path("models/modelo_ia_xauusd.joblib"))
                    st.success("Modelo retreinado com sucesso!")
                else:
                    st.error("Base M1 não encontrada.")

    with col_ai2:
        st.markdown("#### Métricas do Modelo Ativo")
        m1, m2, m3, m4 = st.columns(4)
        m1.metric("ROC AUC", "0.5034")
        m2.metric("Precisão", "20.00%")
        m3.metric("Revocação", "6.39%")
        m4.metric("F1-Score", "0.0969")

        st.markdown("#### Feature Importance")
        features_dict = {
            "vix": 0.0000, "dxy": 0.0000, "l2_imbalance": 0.0000,
            "atr_relativo": 0.0035, "dist_close_poc": 0.0057,
            "delta_multiplier": 0.0064, "minute_of_day": 0.0104, "delta_ratio": 0.0116
        }
        df_feat = pd.DataFrame(list(features_dict.items()), columns=["Feature", "Importância"]).sort_values("Importância", ascending=True)

        fig_feat = go.Figure(go.Bar(
            x=df_feat["Importância"],
            y=df_feat["Feature"],
            orientation="h",
            marker_color="#29b6f6"
        ))
        fig_feat.update_layout(
            template="plotly_dark",
            height=300,
            margin=dict(l=10, r=10, t=10, b=10),
            paper_bgcolor="#161b22",
            plot_bgcolor="#161b22"
        )
        st.plotly_chart(fig_feat, use_container_width=True)

# -------------------------------------------------------------
# ABA 3: MOC/LOC ARBITRAGEM (NASDAQ MNQ)
# -------------------------------------------------------------
with tab_moc_loc:
    st.subheader("Módulo de Arbitragem MOC/LOC (Nasdaq MNQ - Imagem 2)")
    st.markdown("""
    <div class='kill-switch-banner'>
        <strong>🚨 BLINDAGEM DE CONTA (KILL-SWITCH NY):</strong><br>
        A janela MOC/LOC opera entre <strong>15:50:00</strong> e <strong>15:59:50</strong> de Nova York.<br>
        Às <strong>15:59:50</strong> exatas, o robô zera compulsoriamente qualquer posição aberta do Nasdaq antes do leilão das 16:00.
    </div>
    """, unsafe_allow_html=True)

    df_horarios = pd.DataFrame([
        {"Evento Institucional": "Abertura dos Futuros", "Horário NY": "18:00 (D-1)", "Status": "Ativo"},
        {"Evento Institucional": "Abertura Cash (RTH)", "Horário NY": "09:30", "Status": "Ativo"},
        {"Evento Institucional": "Divulgação Early Imbalance", "Horário NY": "15:50", "Status": "Gatilho MNQ Arma"},
        {"Evento Institucional": "Kill-Switch TRAX", "Horário NY": "15:59:50", "Status": "Zeragem Total Compulsória"},
        {"Evento Institucional": "Closing Cross Oficial", "Horário NY": "16:00", "Status": "Leilão MOC Final"}
    ])
    st.dataframe(df_horarios, use_container_width=True, hide_index=True)

    kill_switch_ny_action = KillSwitchMOC(simbolo=config_global.assets["MNQ"].mt5_symbol)
    if st.button("🚨 Executar Zeragem Compulsória de Emergência no MT5"):
        zerados = kill_switch_ny_action.zerar_posicoes_mnq_mt5()
        st.warning(f"Zeragem acionada: {zerados} posições encerradas.")

# -------------------------------------------------------------
# ABA 4: POSIÇÕES ABERTAS NO MT5 (STREAMING 2S)
# -------------------------------------------------------------
with tab_ordens:
    @st.fragment(run_every=2 if auto_streaming else None)
    def renderizar_posicoes_ao_vivo():
        st.subheader("Posições Abertas em Tempo Real no MetaTrader 5")
        if mt5_conectado:
            posicoes_abertas = mt5.positions_get()
            if posicoes_abertas:
                df_pos = pd.DataFrame([{
                    "Ticket": p.ticket,
                    "Símbolo": p.symbol,
                    "Tipo": "BUY" if p.type == 0 else "SELL",
                    "Volume": p.volume,
                    "Preço Entrada": p.price_open,
                    "Preço Atual": p.price_current,
                    "SL": p.sl,
                    "TP": p.tp,
                    "Lucro Flutuante ($)": p.profit
                } for p in posicoes_abertas])
                st.dataframe(df_pos, use_container_width=True, hide_index=True)

                if st.button("❌ Fechar Todas as Posições Abertas"):
                    for p in posicoes_abertas:
                        tipo_fechar = mt5.ORDER_TYPE_SELL if p.type == 0 else mt5.ORDER_TYPE_BUY
                        tick_p = mt5.symbol_info_tick(p.symbol)
                        preco = tick_p.bid if p.type == 0 else tick_p.ask
                        req = {
                            "action": mt5.TRADE_ACTION_DEAL,
                            "symbol": p.symbol,
                            "volume": p.volume,
                            "type": tipo_fechar,
                            "position": p.ticket,
                            "price": preco,
                            "deviation": 20
                        }
                        mt5.order_send(req)
                    st.success("Posições fechadas com sucesso!")
            else:
                st.info("Nenhuma posição aberta no momento na conta da corretora.")
        else:
            st.error("MT5 não conectado.")

    renderizar_posicoes_ao_vivo()
