"""
server.py - Servidor Web Local em FastAPI para o Dashboard de Automação de Aprendizado.
Fornece API REST para cálculos em tempo real, presets e base de conhecimento didática.
"""

import os
import sys
import webbrowser
from typing import Optional
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field
import uvicorn

from engine.assets_db import ASSETS, get_asset
from engine.presets import PRESETS, list_presets, get_preset
from engine.calculators import calculate_trade, get_drawdown_recovery_table, calculate_stops_survival
from engine.macro_calendar import get_macro_safety_status
from content.knowledge_base import get_discord_categories, get_channel_by_id

app = FastAPI(
    title="Central de Gestão de Risco & Educação Financeira",
    description="Dashboard local para cálculo de risco, ATR, fricção e aprendizado para XAUUSD, BTC e NAS100",
    version="1.0.0"
)

# Adiciona CORS para garantir que chamadas locais nunca sejam bloqueadas
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Diretório de arquivos estáticos da interface web
WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")


class TradeRequest(BaseModel):
    symbol: str = Field(default="XAUUSD", description="XAUUSD, BTCUSD ou NAS100")
    capital: float = Field(default=1000.0, description="Capital da conta em USD")
    risk_pct: float = Field(default=1.0, description="Risco percentual por operação (ex: 1.0%)")
    stop_pips: float = Field(default=20.0, description="Distância do stop em pips/pontos")
    tp_pips: float = Field(default=40.0, description="Distância do take profit em pips/pontos")
    order_type: str = Field(default="BUY", description="BUY ou SELL")
    leverage: int = Field(default=100, description="Alavancagem da conta (ex: 100, 500)")
    spread_pips: Optional[float] = Field(default=None, description="Spread em pips")
    commission_per_lot: Optional[float] = Field(default=None, description="Comissão por lote")
    holding_days: int = Field(default=0, description="Dias mantendo a posição (para cálculo de swap)")
    timeframe: str = Field(default="M15", description="M1, M5, M15, H1, H4, D1")
    manual_lot: Optional[float] = Field(default=None, description="Lote manual customizado se desejar")
    custom_price: Optional[float] = Field(default=None, description="Preço de cotação customizado")
    custom_atr_pips: Optional[float] = Field(default=None, description="ATR customizado em pips")


@app.get("/api/assets")
def api_get_assets():
    """Retorna a lista e configurações dos ativos suportados (XAUUSD, BTCUSD, NAS100)."""
    return JSONResponse(content={"assets": ASSETS})


@app.get("/api/presets")
def api_get_presets():
    """Retorna os presets rápidos (Scalp Ouro, Cripto, Day Trade Nasdaq, Mesa Proprietária, etc.)."""
    return JSONResponse(content={"presets": list_presets()})


@app.get("/api/presets/{preset_id}")
def api_get_preset_by_id(preset_id: str):
    return JSONResponse(content=get_preset(preset_id))


@app.post("/api/calculate")
def api_calculate_trade(req: TradeRequest):
    """Executa o cálculo de risco institucional, fricção, ATR e gera a boleta."""
    try:
        result = calculate_trade(
            symbol=req.symbol,
            capital=req.capital,
            risk_pct=req.risk_pct,
            stop_pips=req.stop_pips,
            tp_pips=req.tp_pips,
            order_type=req.order_type,
            leverage=req.leverage,
            spread_pips=req.spread_pips,
            commission_per_lot=req.commission_per_lot,
            holding_days=req.holding_days,
            timeframe=req.timeframe,
            manual_lot=req.manual_lot,
            custom_price=req.custom_price,
            custom_atr_pips=req.custom_atr_pips
        )
        return JSONResponse(content=result)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/api/drawdown-matrix")
def api_drawdown_matrix():
    """Retorna dados de assimetria de drawdown e resistência a sequências de perdas."""
    return JSONResponse(content={
        "drawdown_recovery": get_drawdown_recovery_table(),
        "survival_stops": calculate_stops_survival()
    })


@app.get("/api/education/categories")
def api_get_categories():
    """Retorna a árvore completa de categorias e canais do Discord."""
    return JSONResponse(content={"categories": get_discord_categories()})


@app.get("/api/education/channel/{channel_id}")
def api_get_channel(channel_id: str):
    """Retorna o conteúdo completo de um canal/aula específico."""
    return JSONResponse(content=get_channel_by_id(channel_id))


@app.get("/api/macro-calendar")
def api_get_macro_calendar():
    """Retorna o status em tempo real do mercado e os eventos da semana com filtro de impacto."""
    return JSONResponse(content=get_macro_safety_status())


# Servir arquivos estáticos do frontend
if os.path.exists(WEB_DIR):
    app.mount("/static", StaticFiles(directory=WEB_DIR), name="static")

@app.get("/")
def serve_index():
    index_file = os.path.join(WEB_DIR, "index.html")
    if os.path.exists(index_file):
        return FileResponse(index_file)
    return {"message": "Interface Web em construção."}


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8")
            sys.stderr.reconfigure(encoding="utf-8")
        except Exception:
            pass

    port = 8000
    host = "127.0.0.1"
    url = f"http://{host}:{port}"
    print("\n=======================================================")
    print("[*] Central de Gestao & Aprendizado iniciada com sucesso!")
    print(f"[*] Acesse no seu navegador: {url}")
    print("=======================================================\n")
    try:
        webbrowser.open(url)
    except Exception:
        pass
    uvicorn.run("server:app", host=host, port=port, reload=False)
