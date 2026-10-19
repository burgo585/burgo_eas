"""
calculators.py - Motor Quantitativo de Gestão de Risco, Fricção, ATR e Boleta.
Implementa todas as fórmulas matemáticas e regras institucionais das imagens.
"""

import math
from typing import Dict, Any, Optional
from engine.assets_db import get_asset, ASSETS


def calculate_dynamic_lot(
    capital: float,
    risk_pct: float,
    stop_pips: float,
    pip_value_per_standard_lot: float,
    min_lot: float = 0.01,
    lot_step: float = 0.01,
    max_lot: float = 50.0
) -> float:
    """
    Calcula o lote institucional dinâmico para respeitar estritamente a porcentagem de risco.
    Lote = (Capital * (Risco / 100)) / (Stop em Pips * Valor do Pip por Lote Padrão)
    """
    if capital <= 0 or stop_pips <= 0 or pip_value_per_standard_lot <= 0:
        return min_lot

    money_at_risk = capital * (risk_pct / 100.0)
    raw_lot = money_at_risk / (stop_pips * pip_value_per_standard_lot)

    # Arredonda respeitando o passo de lote (lot_step, normalmente 0.01)
    steps = round(raw_lot / lot_step)
    calculated_lot = steps * lot_step

    # Limita entre lote mínimo e máximo da corretora
    clamped_lot = max(min_lot, min(max_lot, calculated_lot))
    return round(clamped_lot, 2)


def calculate_trade(
    symbol: str = "XAUUSD",
    capital: float = 1000.0,
    risk_pct: float = 1.0,
    stop_pips: float = 20.0,
    tp_pips: float = 40.0,
    order_type: str = "BUY",
    leverage: int = 100,
    spread_pips: Optional[float] = None,
    commission_per_lot: Optional[float] = None,
    holding_days: int = 0,
    timeframe: str = "M15",
    manual_lot: Optional[float] = None,
    custom_price: Optional[float] = None,
    custom_atr_pips: Optional[float] = None
) -> Dict[str, Any]:
    """
    Executa o Raio-X completo da operação:
    - Dimensionamento do lote dinâmico
    - Perda Nominal vs. Perda Real c/ Fricção (Spread + Comissão + Swap)
    - Lucro Bruto vs. Lucro Líquido Real
    - Relação R:R e Valor Esperado (EV)
    - Margem exigida, margem livre e alavancagem operacional real
    - Avaliação estatística de ruído vs. ATR
    - Boleta de execução rápida formatada
    """
    asset = get_asset(symbol)
    price = custom_price if custom_price and custom_price > 0 else asset["default_price"]
    pip_val_std = asset["pip_value_per_standard_lot"]
    contract_size = asset["contract_size"]
    min_lot = asset["min_lot"]
    lot_step = asset["lot_step"]
    max_lot = asset["max_lot"]

    # Spread e comissão padrão se não informados
    actual_spread = spread_pips if spread_pips is not None else asset["typical_spread_pips"]
    actual_commission = commission_per_lot if commission_per_lot is not None else asset["typical_commission_per_lot"]

    # Determina o lote (manual ou dinâmico)
    if manual_lot and manual_lot > 0:
        lot = max(min_lot, min(max_lot, round(manual_lot, 2)))
    else:
        lot = calculate_dynamic_lot(
            capital=capital,
            risk_pct=risk_pct,
            stop_pips=stop_pips,
            pip_value_per_standard_lot=pip_val_std,
            min_lot=min_lot,
            lot_step=lot_step,
            max_lot=max_lot
        )

    # Valor do pip para o lote atual
    pip_value_for_lot = lot * pip_val_std

    # Resultados Nominais
    nominal_loss = lot * stop_pips * pip_val_std
    nominal_profit = lot * tp_pips * pip_val_std
    nominal_loss_pct = (nominal_loss / capital * 100.0) if capital > 0 else 0.0
    nominal_profit_pct = (nominal_profit / capital * 100.0) if capital > 0 else 0.0

    # Fricção e Custos Invisíveis
    spread_cost = lot * actual_spread * pip_val_std
    commission_cost = lot * actual_commission
    
    # Swap diário conforme direção
    swap_rate_daily = asset["typical_swap_long_daily"] if order_type.upper() == "BUY" else asset["typical_swap_short_daily"]
    # Se holding_days > 0, calcula swap acumulado
    swap_total = lot * swap_rate_daily * holding_days

    # Fricção total que onera a operação
    # Custos diretos: Spread + Comissão + (Swap se for negativo/débito)
    friction_cost = spread_cost + commission_cost
    if swap_total < 0:
        friction_cost += abs(swap_total)

    friction_pct_of_profit = (friction_cost / nominal_profit * 100.0) if nominal_profit > 0 else 0.0

    # Perda Real e Lucro Real c/ Fricção
    real_loss = nominal_loss + friction_cost
    real_loss_pct = (real_loss / capital * 100.0) if capital > 0 else 0.0

    real_profit = nominal_profit - friction_cost + (swap_total if swap_total > 0 else 0.0)
    real_profit_pct = (real_profit / capital * 100.0) if capital > 0 else 0.0

    # Relação Risco:Retorno (R:R)
    rr_ratio = (tp_pips / stop_pips) if stop_pips > 0 else 0.0

    # Conta & Margem
    # Margem Exigida = (Lote * Tamanho do Contrato * Preço Atual) / Alavancagem
    margin_required = (lot * contract_size * price) / max(1, leverage)
    margin_free = max(0.0, capital - margin_required)
    margin_level_pct = (capital / margin_required * 100.0) if margin_required > 0 else 0.0
    
    # Alavancagem Operacional Real (Exposição no mercado / Saldo)
    exposure_usd = lot * contract_size * price
    real_leverage_ratio = (exposure_usd / capital) if capital > 0 else 0.0

    # Volatilidade & Análise ATR
    atr_table = asset.get("typical_atr", {})
    selected_atr = custom_atr_pips if custom_atr_pips and custom_atr_pips > 0 else atr_table.get(timeframe, 20.0)
    stop_to_atr_ratio = (stop_pips / selected_atr) if selected_atr > 0 else 1.0

    if stop_to_atr_ratio < 1.0:
        atr_status = "CRITICO"
        atr_badge = "🚨 Limiar Crítico"
        atr_message = f"Stop ({stop_pips:.1f}p) é menor que o ATR de 1 vela ({selected_atr:.1f}p). Risco severo de violinar no ruído normal de mercado!"
    elif stop_to_atr_ratio < 1.2:
        atr_status = "VULNERAVEL"
        atr_badge = "⚠️ Limiar Vulnerável"
        atr_message = f"Distância do Stop é {stop_to_atr_ratio:.2f}x ATR ({timeframe}). Exige >= 1.20x ATR para amortecer oscilações brownianas e falsos rompimentos."
    else:
        atr_status = "SEGURO"
        atr_badge = "✅ Parâmetro Seguro"
        atr_message = f"Stop institucional saudável ({stop_to_atr_ratio:.2f}x ATR). Distância suficiente acima do ruído da vela."

    # Probabilidade Teórica e Expectativa Matemática (EV)
    # Modelo estatístico clássico com fricção de spread:
    denom = stop_pips + tp_pips + (2.0 * actual_spread)
    prob_tp = (stop_pips / denom * 100.0) if denom > 0 else 50.0
    prob_sl = 100.0 - prob_tp

    # EV em termos de R-múltiplo: EV = (P(TP) * R_ganho) - (P(SL) * R_perda)
    r_ganho = (real_profit / nominal_loss) if nominal_loss > 0 else rr_ratio
    r_perda = (real_loss / nominal_loss) if nominal_loss > 0 else 1.0
    ev_r = ((prob_tp / 100.0) * r_ganho) - ((prob_sl / 100.0) * r_perda)

    # Parecer Geral de Governança
    governance_alerts = []
    if real_loss_pct > 2.0:
        governance_alerts.append(f"Perda real ({real_loss_pct:.1f}%) excede o limite profissional de 2.0% por trade.")
    if real_leverage_ratio > 20.0:
        governance_alerts.append(f"Alavancagem real de {real_leverage_ratio:.1f}x é alta para a sua conta.")
    if friction_pct_of_profit > 15.0:
        governance_alerts.append(f"Fricção da corretora consome {friction_pct_of_profit:.1f}% do lucro alvo! Cuidado com scalps curtos demais.")
    if atr_status != "SEGURO":
        governance_alerts.append(atr_message)

    if not governance_alerts:
        governance_verdict = "Parâmetros Seguros: Risco, margem e volatilidade 100% sob controle institucional."
        governance_level = "SEGURO"
    else:
        governance_verdict = "Atenção a Filtros de Risco: Verifique os avisos de fricção e volatilidade antes da ordem."
        governance_level = "ALERTA" if atr_status == "VULNERAVEL" and real_loss_pct <= 2.0 else "PERIGO"

    # Boletas de Execução Rápida
    boleta_compact = f"[ {lot:.2f} LOTES ]  SL: {stop_pips:.0f}p  |  TP: {tp_pips:.0f}p  ({order_type.upper()})"
    boleta_mt5 = f"{symbol} | {order_type.upper()} | {lot:.2f} Lotes | SL: {stop_pips:.0f}p | TP: {tp_pips:.0f}p"

    return {
        "asset": asset,
        "symbol": symbol,
        "price": price,
        "capital": capital,
        "risk_pct": risk_pct,
        "order_type": order_type.upper(),
        "lot": lot,
        "stop_pips": stop_pips,
        "tp_pips": tp_pips,
        "leverage": leverage,
        "timeframe": timeframe,
        "nominal": {
            "loss_usd": round(nominal_loss, 2),
            "loss_pct": round(nominal_loss_pct, 2),
            "profit_usd": round(nominal_profit, 2),
            "profit_pct": round(nominal_profit_pct, 2),
            "rr_ratio": round(rr_ratio, 2)
        },
        "real": {
            "loss_usd": round(real_loss, 2),
            "loss_pct": round(real_loss_pct, 2),
            "profit_usd": round(real_profit, 2),
            "profit_pct": round(real_profit_pct, 2),
            "friction_usd": round(friction_cost, 2),
            "friction_pct_profit": round(friction_pct_of_profit, 1)
        },
        "costs": {
            "spread_pips": actual_spread,
            "spread_usd": round(spread_cost, 2),
            "commission_usd": round(commission_cost, 2),
            "swap_daily_usd": round(lot * swap_rate_daily, 2),
            "swap_total_usd": round(swap_total, 2),
            "holding_days": holding_days
        },
        "margin": {
            "required_usd": round(margin_required, 2),
            "free_usd": round(margin_free, 2),
            "level_pct": round(margin_level_pct, 1),
            "real_leverage": round(real_leverage_ratio, 1)
        },
        "volatility": {
            "atr_pips": round(selected_atr, 1),
            "stop_atr_ratio": round(stop_to_atr_ratio, 2),
            "status": atr_status,
            "badge": atr_badge,
            "message": atr_message,
            "prob_tp_pct": round(prob_tp, 1),
            "ev_r": round(ev_r, 2)
        },
        "governance": {
            "level": governance_level,
            "verdict": governance_verdict,
            "alerts": governance_alerts
        },
        "boleta": {
            "compact": boleta_compact,
            "mt5": boleta_mt5
        }
    }


def get_drawdown_recovery_table() -> list:
    """
    Retorna a tabela de esforço de recuperação por nível de perda (Drawdown)
    com base nas imagens enviadas pelo usuário.
    """
    levels = [10.0, 20.0, 30.0, 50.0, 80.0, 90.0]
    result = []
    for loss in levels:
        req = (loss / (100.0 - loss)) * 100.0
        note = ""
        if loss == 50.0:
            note = "Exige dobrar a conta (+100%) só para empatar!"
        elif loss == 80.0:
            note = "Exige multiplicar a conta por 5 (+400%)!"
        elif loss >= 90.0:
            note = "Quase matematicamente irrecuperável (+900%)!"

        result.append({
            "loss_pct": loss,
            "required_gain_pct": round(req, 1),
            "note": note
        })
    return result


def calculate_stops_survival() -> list:
    """
    Retorna a resistência a sequências de perdas consecutivas por nível de risco.
    """
    risks = [0.5, 1.0, 2.0, 5.0]
    result = []
    for r in risks:
        # Número aproximado de stops para perder 100% (aritmético ou com decaimento geométrico)
        stops_nominal = int(100.0 / r)
        # Sequência para perder 50% da conta com dimensionamento composto
        stops_to_50pct = int(math.log(0.5) / math.log(1.0 - (r / 100.0)))
        status = "Seguro (Institucional)" if r <= 1.0 else ("Atenção (Agressivo)" if r <= 2.0 else "Zona de Ruína!")
        result.append({
            "risk_pct": r,
            "stops_nominal": stops_nominal,
            "stops_to_50pct": stops_to_50pct,
            "status": status,
            "is_danger": r >= 5.0
        })
    return result
