"""
MT5 MCP Unified Client & Bridge
Conecta o Antigravity / Claude / Codex aos servidores MCP do MetaTrader 5:
- MetaEditor MCP (porta 22345): Compilação, validação de sintaxe, formatação e gestão de arquivos MQL5.
- Terminal MT5 MCP (porta 22346): Execução, dados de conta e operações.
- MarketData MCP (metatrader.com): Cotações públicas, histórico OHLCV e ativos globais.
"""

import urllib.request
import urllib.error
import json
import sys

DEFAULT_CONFIG = {
    "metaeditor": {
        "url": "http://127.0.0.1:22345/mcp",
        "token": "tqR1jKRLYvBaOgyeUewC5azre29Vr1IrPi23WTPqep",
        "version": "2025-06-18"
    },
    "terminal": {
        "url": "http://127.0.0.1:22346/mcp",
        "token": "tqR1jKRLYvBaOgyeUewC5azre29Vr1IrPi23WTPqep",
        "version": "2025-06-18"
    },
    "marketdata": {
        "url": "https://www.metatrader.com/mcp",
        "token": "mq-ebe8e9298e1d120007e9246bfd0d300f",
        "version": "2024-11-05"
    }
}

class MT5MCPClient:
    def __init__(self, service="metaeditor", token=None, url=None):
        cfg = DEFAULT_CONFIG.get(service, {})
        self.service = service
        self.url = url or cfg.get("url")
        self.token = token or cfg.get("token")
        self.protocol_version = cfg.get("version", "2025-06-18")
        self.session_id = None
        self.headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream"
        }
        self._init_session()

    def _parse_response(self, raw_text):
        data_lines = []
        for line in raw_text.splitlines():
            if line.startswith("data:"):
                data_lines.append(line[5:])
        if data_lines:
            return json.loads("\n".join(data_lines))
        return json.loads(raw_text)

    def _init_session(self):
        payload = json.dumps({
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": self.protocol_version,
                "capabilities": {},
                "clientInfo": {"name": "antigravity-mt5-client", "version": "1.0"}
            }
        }).encode("utf-8")
        
        req = urllib.request.Request(self.url, data=payload, headers=self.headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                self.session_id = resp.headers.get("Mcp-Session-Id")
                cookie = resp.headers.get("Set-Cookie")
                if self.session_id:
                    self.headers["Mcp-Session-Id"] = self.session_id
                    self.headers["MCP-Protocol-Version"] = self.protocol_version
                if cookie:
                    self.headers["Cookie"] = cookie
                self.init_data = self._parse_response(resp.read().decode("utf-8"))
                
                # Send initialized notification
                notif_payload = json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}).encode("utf-8")
                n_req = urllib.request.Request(self.url, data=notif_payload, headers=self.headers, method="POST")
                try:
                    with urllib.request.urlopen(n_req, timeout=3): pass
                except: pass
        except urllib.error.HTTPError as e:
            raise ConnectionError(f"Erro HTTP {e.code} ao conectar em {self.url} ({self.service})")
        except Exception as e:
            raise ConnectionError(f"Falha de conexão com {self.url}: {e}")

    def list_tools(self):
        payload = json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}).encode("utf-8")
        req = urllib.request.Request(self.url, data=payload, headers=self.headers, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = self._parse_response(resp.read().decode("utf-8"))
            return data.get("result", {}).get("tools", [])

    def call_tool(self, tool_name, arguments={}):
        payload = json.dumps({
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": {"name": tool_name, "arguments": arguments}
        }).encode("utf-8")
        req = urllib.request.Request(self.url, data=payload, headers=self.headers, method="POST")
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = self._parse_response(resp.read().decode("utf-8"))
            return data.get("result", {})

if __name__ == "__main__":
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')

    print("=== Testando Clientes MCP do MetaTrader ===")
    
    # 1. MetaEditor
    try:
        me = MT5MCPClient("metaeditor")
        tools = me.list_tools()
        print(f"✅ MetaEditor MCP Conectado ({len(tools)} ferramentas disponíveis)")
        ws = me.call_tool("get_workspace_info")
        print("   Workspace MQL5:", ws.get("structuredContent", {}).get("workspace", {}).get("mql5_folder"))
    except Exception as e:
        print("❌ MetaEditor MCP:", e)

    # 2. MarketData
    try:
        md = MT5MCPClient("marketdata")
        md_tools = md.list_tools()
        print(f"✅ MarketData MCP Conectado ({len(md_tools)} ferramentas disponíveis)")
    except Exception as e:
        print("❌ MarketData MCP:", e)

    # 3. Terminal
    try:
        tm = MT5MCPClient("terminal")
        tm_tools = tm.list_tools()
        print(f"✅ Terminal MCP Conectado ({len(tm_tools)} ferramentas)")
    except Exception as e:
        print("⚠️ Terminal MCP (Porta 22346):", e)
        print("   -> Para autenticar o Terminal MT5, acesse no MT5: Ferramentas > Opções > Assistente IA / Servidor MCP e copie o Token gerado especificamente para o Terminal.")
