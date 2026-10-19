import asyncio
import json
import re
import websockets
import pandas as pd

def construct_message(msg_str):
    return f"~m~{len(msg_str)}~m~{msg_str}"

def parse_messages(raw):
    pattern = r"~m~(\d+)~m~"
    messages = []
    pos = 0
    while True:
        match = re.search(pattern, raw[pos:])
        if not match:
            break
        length = int(match.group(1))
        start = pos + match.end()
        end = start + length
        msg_payload = raw[start:end]
        messages.append(msg_payload)
        pos = end
    return messages

async def fetch_tradingview_bars(symbol="OANDA:XAUUSD", timeframe="15", num_bars=300):
    uri = "wss://data.tradingview.com/socket.io/websocket"
    headers = {
        "Origin": "https://data.tradingview.com",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    }
    async with websockets.connect(uri, additional_headers=headers) as ws:
        # Step 1: Set auth token
        await ws.send(construct_message(json.dumps({"m": "set_auth_token", "p": ["unauthorized_user_token"]})))
        
        # Step 2: Chart create session
        chart_session = "cs_testing_xau"
        await ws.send(construct_message(json.dumps({"m": "chart_create_session", "p": [chart_session, ""]})))
        
        # Step 3: Resolve symbol
        symbol_spec = json.dumps({"adjustment": "splits", "symbol": symbol})
        await ws.send(construct_message(json.dumps({"m": "resolve_symbol", "p": [chart_session, "sds_sym_1", f"={symbol_spec}"]})))
        
        # Step 4: Create series
        await ws.send(construct_message(json.dumps({"m": "create_series", "p": [chart_session, "sds_1", "s1", "sds_sym_1", timeframe, num_bars, ""]})))
        
        bars = []
        timeout = 10
        start_time = asyncio.get_event_loop().time()
        
        while asyncio.get_event_loop().time() - start_time < timeout:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=3)
            except asyncio.TimeoutError:
                break
                
            # Keep alive ping
            if "~h~" in raw:
                await ws.send(raw)
                continue
                
            msgs = parse_messages(raw)
            for m in msgs:
                if not m.startswith("{"):
                    continue
                try:
                    data = json.loads(m)
                    if data.get("m") == "timescale_update":
                        series_data = data.get("p", [])[1].get("sds_1", {}).get("s", [])
                        if series_data:
                            for item in series_data:
                                v = item.get("v", [])
                                # timestamp, open, high, low, close, volume
                                if len(v) >= 6:
                                    bars.append({
                                        "time": pd.to_datetime(v[0], unit='s'),
                                        "open": v[1],
                                        "high": v[2],
                                        "low": v[3],
                                        "close": v[4],
                                        "volume": v[5]
                                    })
                            return pd.DataFrame(bars)
                except Exception as e:
                    pass
        return pd.DataFrame(bars)

if __name__ == "__main__":
    df = asyncio.run(fetch_tradingview_bars("OANDA:XAUUSD", "15", 50))
    print("TradingView bars count:", len(df))
    if not df.empty:
        print(df.tail())
