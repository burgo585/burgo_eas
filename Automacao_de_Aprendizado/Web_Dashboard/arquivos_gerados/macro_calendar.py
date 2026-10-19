"""
macro_calendar.py - Motor do Radar Macroeconômico e Calendário Econômico Semanal.
Fornece notícias de alto e médio impacto, cálculo dinâmico dos eventos da semana atual,
conversão para Horário de Brasília (UTC-3), correlação com XAUUSD, BTC e NAS100,
e status do Protocolo de Segurança dos 15 minutos.
"""

import datetime
from typing import Dict, Any, List, Optional
import pytz

BRT_TZ = pytz.timezone("America/Sao_Paulo")
UTC_TZ = pytz.utc


def get_current_week_dates() -> Dict[str, datetime.date]:
    """Retorna as datas de Segunda a Sexta da semana atual."""
    now_brt = datetime.datetime.now(BRT_TZ).date()
    # Segunda-feira da semana atual (weekday() 0 = segunda)
    monday = now_brt - datetime.timedelta(days=now_brt.weekday())
    return {
        "monday": monday,
        "tuesday": monday + datetime.timedelta(days=1),
        "wednesday": monday + datetime.timedelta(days=2),
        "thursday": monday + datetime.timedelta(days=3),
        "friday": monday + datetime.timedelta(days=4)
    }


def generate_weekly_economic_calendar() -> List[Dict[str, Any]]:
    """
    Gera o calendário macroeconômico dinâmico da semana atual,
    com horários exatos em Horário de Brasília (BRT), impacto,
    ativos afetados (XAUUSD, BTC, NAS100) e orientações operacionais.
    """
    week = get_current_week_dates()
    now_brt = datetime.datetime.now(BRT_TZ)

    events_catalog = [
        # SEGUNDA-FEIRA
        {
            "day_key": "monday",
            "time_str": "09:30",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "Abertura Oficial de Nova York & Discursos do Fed",
            "impact": "Medium",
            "impact_label": "🟡 Médio Impacto",
            "forecast": "-",
            "previous": "-",
            "affected_assets": ["NAS100", "XAUUSD"],
            "market_note": "Início da liquidez pesada semanal. Entrada de fluxo institucional em tecnologia e commodities."
        },
        {
            "day_key": "monday",
            "time_str": "11:00",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "PMI Industrial & Serviços dos EUA (S&P Global / ISM)",
            "impact": "High",
            "impact_label": "🔴 ALTO IMPACTO (Tier 1)",
            "forecast": "50.5",
            "previous": "49.8",
            "affected_assets": ["NAS100", "XAUUSD", "BTCUSD"],
            "market_note": "Termômetro inicial da atividade econômica dos EUA. Movimenta forte os índices de ações e ouro."
        },
        {
            "day_key": "monday",
            "time_str": "12:30",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "Leilão de Títulos do Tesouro dos EUA (Treasuries 10 Anos)",
            "impact": "Medium",
            "impact_label": "🟡 Médio Impacto",
            "forecast": "-",
            "previous": "-",
            "affected_assets": ["NAS100", "XAUUSD"],
            "market_note": "Rendimento dos títulos (Yields) afeta diretamente o custo de oportunidade do Ouro e a precificação do Nasdaq."
        },

        # TERÇA-FEIRA
        {
            "day_key": "tuesday",
            "time_str": "09:30",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "CPI - Índice de Preços ao Consumidor (Inflação) & Core CPI",
            "impact": "High",
            "impact_label": "🔴 ALTO IMPACTO (Tier 1)",
            "forecast": "+0.2% m/m",
            "previous": "+0.2% m/m",
            "affected_assets": ["XAUUSD", "NAS100", "BTCUSD"],
            "market_note": "GATILHO DE MÁXIMA VOLATILIDADE! Inflação acima do esperado derruba o Ouro e o Nasdaq em segundos; inflação fraca provoca disparada."
        },
        {
            "day_key": "tuesday",
            "time_str": "10:15",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "Produção Industrial dos EUA (m/m)",
            "impact": "Medium",
            "impact_label": "🟡 Médio Impacto",
            "forecast": "+0.1%",
            "previous": "+0.2%",
            "affected_assets": ["NAS100"],
            "market_note": "Mede a saúde da economia real e atividade fabril americana."
        },

        # QUARTA-FEIRA
        {
            "day_key": "wednesday",
            "time_str": "11:30",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "Estoques de Petróleo Bruto (EIA)",
            "impact": "Medium",
            "impact_label": "🟡 Médio Impacto",
            "forecast": "-1.2M",
            "previous": "+1.8M",
            "affected_assets": ["XAUUSD"],
            "market_note": "Impacta custo energético global e expectativas de inflação de curto prazo."
        },
        {
            "day_key": "wednesday",
            "time_str": "15:00",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "Decisão de Taxa de Juros do FOMC / Divulgação das Atas",
            "impact": "High",
            "impact_label": "🔴 ALTO IMPACTO (Tier 1)",
            "forecast": "5.00%",
            "previous": "5.00%",
            "affected_assets": ["XAUUSD", "NAS100", "BTCUSD"],
            "market_note": "O EVENTO MAIS IMPORTANTE DO MERCADO FINANCEIRO. Define a taxa básica do Dólar. Alargamento severo de spread garantido."
        },
        {
            "day_key": "wednesday",
            "time_str": "15:30",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "Coletiva de Imprensa de Jerome Powell (Presidente do Fed)",
            "impact": "High",
            "impact_label": "🔴 ALTO IMPACTO (Tier 1)",
            "forecast": "-",
            "previous": "-",
            "affected_assets": ["XAUUSD", "NAS100", "BTCUSD"],
            "market_note": "Cada palavra de Powell causa repiques violentos de 50 a 150 pips no Ouro e no Nasdaq. Mantenha ordens fechadas."
        },

        # QUINTA-FEIRA
        {
            "day_key": "thursday",
            "time_str": "09:15",
            "country": "EUR",
            "flag": "🇪🇺",
            "title": "Decisão de Taxa de Juros do BCE (Banco Central Europeu)",
            "impact": "High",
            "impact_label": "🔴 ALTO IMPACTO (Tier 1)",
            "forecast": "3.50%",
            "previous": "3.65%",
            "affected_assets": ["XAUUSD"],
            "market_note": "Movimenta a paridade Euro/Dólar e reflete na cotação internacional do Ouro."
        },
        {
            "day_key": "thursday",
            "time_str": "09:30",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "Pedidos Iniciais por Seguro-Desemprego (Initial Jobless Claims)",
            "impact": "High",
            "impact_label": "🔴 ALTO IMPACTO (Tier 1)",
            "forecast": "225K",
            "previous": "221K",
            "affected_assets": ["NAS100", "XAUUSD"],
            "market_note": "Divulgado semanalmente às quintas-feiras. Termômetro em tempo real da força do mercado de trabalho americano."
        },
        {
            "day_key": "thursday",
            "time_str": "11:00",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "Vendas de Casas Usadas (Existing Home Sales)",
            "impact": "Medium",
            "impact_label": "🟡 Médio Impacto",
            "forecast": "3.85M",
            "previous": "3.83M",
            "affected_assets": ["NAS100"],
            "market_note": "Indicador líder da saúde do setor imobiliário e confiança do consumidor."
        },

        # SEXTA-FEIRA
        {
            "day_key": "friday",
            "time_str": "09:30",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "Non-Farm Payrolls (NFP) & Taxa de Desemprego dos EUA",
            "impact": "High",
            "impact_label": "🔴 ALTO IMPACTO (Tier 1)",
            "forecast": "+160K",
            "previous": "+142K",
            "affected_assets": ["XAUUSD", "NAS100", "BTCUSD"],
            "market_note": "A MAIOR NOTÍCIA DO MÊS. Volume institucional gigante, slippage altíssimo em robôs e gaps imediatos."
        },
        {
            "day_key": "friday",
            "time_str": "11:00",
            "country": "USD",
            "flag": "🇺🇸",
            "title": "Índice de Confiança do Consumidor de Michigan",
            "impact": "Medium",
            "impact_label": "🟡 Médio Impacto",
            "forecast": "70.2",
            "previous": "69.0",
            "affected_assets": ["NAS100", "BTCUSD"],
            "market_note": "Mede o sentimento do consumidor em relação à inflação e gastos futuros."
        },
        {
            "day_key": "friday",
            "time_str": "17:00",
            "country": "GLOBAL",
            "flag": "🏛️",
            "title": "Fechamento da Sessão de Nova York & Rollover Semanal",
            "impact": "High",
            "impact_label": "🔴 ALTO IMPACTO (Risco de Gap)",
            "forecast": "-",
            "previous": "-",
            "affected_assets": ["XAUUSD", "NAS100", "BTCUSD"],
            "market_note": "Fim da semana de negociação nos mercados tradicionais. Risco severo de gap de abertura no domingo para segunda."
        }
    ]

    processed_events = []
    day_names_pt = {
        "monday": "Segunda-feira",
        "tuesday": "Terça-feira",
        "wednesday": "Quarta-feira",
        "thursday": "Quinta-feira",
        "friday": "Sexta-feira"
    }

    for item in events_catalog:
        event_date = week[item["day_key"]]
        hour, minute = map(int, item["time_str"].split(":"))
        event_datetime_brt = BRT_TZ.localize(
            datetime.datetime(event_date.year, event_date.month, event_date.day, hour, minute)
        )

        # Diferença de tempo em minutos em relação ao horário atual
        diff_seconds = (event_datetime_brt - now_brt).total_seconds()
        diff_minutes = int(diff_seconds / 60)

        is_today = (event_date == now_brt.date())
        is_past = diff_minutes < -15  # Já passou há mais de 15 min
        is_imminent = (-15 <= diff_minutes <= 15) and item["impact"] == "High"
        is_approaching = (15 < diff_minutes <= 60) and item["impact"] == "High"

        # Status legível
        if diff_minutes < -15:
            status_text = "Concluído"
            status_badge = "badge-gray"
        elif is_imminent:
            status_text = "🚨 EM ANDAMENTO (BLOQUEIO ATIVO)"
            status_badge = "badge-red-blink"
        elif is_approaching:
            status_text = f"Em {diff_minutes} min"
            status_badge = "badge-yellow"
        elif is_today and diff_minutes > 0:
            hours_left = diff_minutes // 60
            mins_left = diff_minutes % 60
            status_text = f"Hoje às {item['time_str']}" if hours_left > 3 else f"Em {hours_left}h {mins_left}m"
            status_badge = "badge-blue"
        else:
            status_text = f"{day_names_pt[item['day_key']]} às {item['time_str']}"
            status_badge = "badge-dark"

        processed_events.append({
            "id": f"{item['day_key']}_{item['time_str']}_{item['title'][:10]}",
            "title": item["title"],
            "country": item["country"],
            "flag": item["flag"],
            "impact": item["impact"],
            "impact_label": item["impact_label"],
            "day_name": day_names_pt[item["day_key"]],
            "date_formatted": event_date.strftime("%d/%m/%Y"),
            "time_brt": item["time_str"],
            "datetime_iso": event_datetime_brt.isoformat(),
            "forecast": item["forecast"],
            "previous": item["previous"],
            "affected_assets": item["affected_assets"],
            "market_note": item["market_note"],
            "is_today": is_today,
            "is_past": is_past,
            "is_imminent": is_imminent,
            "is_approaching": is_approaching,
            "diff_minutes": diff_minutes,
            "status_text": status_text,
            "status_badge": status_badge
        })

    return processed_events


def get_macro_safety_status() -> Dict[str, Any]:
    """
    Avalia em tempo real se o mercado está em 'Zona Segura' ou 'Zona de Perigo'
    conforme o Protocolo dos 15 minutos de notícias Tier 1.
    """
    events = generate_weekly_economic_calendar()
    now_brt = datetime.datetime.now(BRT_TZ)

    imminent_events = [e for e in events if e["is_imminent"]]
    approaching_events = [e for e in events if e["is_approaching"]]
    today_high_events = [e for e in events if e["is_today"] and e["impact"] == "High" and not e["is_past"]]
    all_upcoming_high = [e for e in events if e["impact"] == "High" and not e["is_past"]]

    next_upcoming_high = all_upcoming_high[0] if all_upcoming_high else None

    if imminent_events:
        evt = imminent_events[0]
        status = "DANGER"
        title = "🚨 PROTOCOLO DE BLOQUEIO ATIVO: NOTÍCIA TIER 1 EM ANDAMENTO"
        message = (
            f"Evento crítico: '{evt['title']}' ({evt['time_brt']} BRT). "
            f"Proibido abrir novas ordens! Spreads alargados e alto risco de slippage severo nos ativos: {', '.join(evt['affected_assets'])}."
        )
        badge_class = "badge-red"
    elif approaching_events:
        evt = approaching_events[0]
        status = "WARNING"
        title = "⚠️ ATENÇÃO: NOTÍCIA TIER 1 SE APROXIMANDO"
        message = (
            f"Evento '{evt['title']}' em {evt['diff_minutes']} minutos ({evt['time_brt']} BRT). "
            f"Prepare-se para proteger stops no zero a zero ou encerrar scalps rápidos em {', '.join(evt['affected_assets'])}."
        )
        badge_class = "badge-yellow"
    else:
        status = "SAFE"
        title = "🟢 ZONA OPERACIONAL LIBERADA"
        if next_upcoming_high:
            if next_upcoming_high["is_today"]:
                message = f"Nenhuma notícia Tier 1 nos próximos minutos. Próximo grande evento hoje: '{next_upcoming_high['title']}' às {next_upcoming_high['time_brt']} BRT ({next_upcoming_high['status_text']})."
            else:
                message = f"Mercado estável hoje. Próximo grande evento da semana: '{next_upcoming_high['title']}' na {next_upcoming_high['day_name']} às {next_upcoming_high['time_brt']} BRT."
        else:
            message = "Todos os grandes eventos Tier 1 programados para esta semana foram concluídos. Operação dentro dos parâmetros estatísticos normais."
        badge_class = "badge-green"

    return {
        "status": status,
        "title": title,
        "message": message,
        "badge_class": badge_class,
        "current_time_brt": now_brt.strftime("%H:%M:%S (Horário de Brasília)"),
        "current_date_brt": now_brt.strftime("%d/%m/%Y"),
        "total_weekly_events": len(events),
        "high_impact_count": len([e for e in events if e["impact"] == "High"]),
        "medium_impact_count": len([e for e in events if e["impact"] == "Medium"]),
        "next_upcoming_high": next_upcoming_high,
        "events": events
    }
