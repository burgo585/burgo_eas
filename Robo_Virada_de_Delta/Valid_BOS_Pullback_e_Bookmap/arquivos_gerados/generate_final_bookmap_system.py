# -*- coding: utf-8 -*-
"""
generate_final_bookmap_system.py
Gera e compila Valid_BOS_Bookmap_EA.mq5 e Valid_BOS_Bookmap_Ind.mq5
com 100% de precisão, conexão Bookmap ultraleve, rastreamento de basis,
e novo gatilho institucional de absorção na VWAP no pavio com delta.
"""

import os
import shutil
import subprocess

PROJECT_DIR = r"c:\Robo Virada de Delta\Valid_BOS_Pullback"
MT5_TERM_DIR = r"C:\Users\Vini_Burgo\AppData\Roaming\MetaQuotes\Terminal\9AF8328437A6A393B2016FC9156E6753\MQL5"
METAEDITOR = r"C:\Program Files\MetaTrader 5\metaeditor64.exe"

# 1. Bloco de Dimensões para ambos
DIMENSIONS_BLOCK = """int GetLineRelY(int lineIndex)
{
   int extraGap = 0;
   if(lineIndex >= 2) extraGap += 3;
   if(lineIndex >= 5) extraGap += 4;
   if(lineIndex >= 8) extraGap += 4;
   if(lineIndex >= 11) extraGap += 4;
   if(lineIndex >= 14) extraGap += 4;
   return g_lineYStart + (lineIndex * g_lineH) + extraGap;
}

void CalculateDashboardDimensions()
{
   g_fontSize = MathMax(7, MathMin(14, InpFontSize));
   double scale = (double)g_fontSize / 8.0;

   g_headerH    = (int)MathRound(34.0 * scale);
   g_lineH      = (int)MathRound(19.0 * scale);
   g_lineYStart = g_headerH + 6;

   int totalLines = 15;
   g_panelHeightFull = g_lineYStart + (totalLines * g_lineH) + 24;
   g_panelHeightMin  = g_headerH + 4;
   g_panelWidth      = (int)MathRound(560.0 * scale);
}
"""

def build_ea():
    with open(os.path.join(PROJECT_DIR, "Valid_BOS_Pullback_EA.mq5"), "r", encoding="utf-8") as f:
        code = f.read()

    # 1. Header info
    code = code.replace("Valid_BOS_Pullback_EA.mq5", "Valid_BOS_Bookmap_EA.mq5")
    code = code.replace("Robô Quantitativo Institucional Pro Max", "Robô Quantitativo Bookmap Pro Max (COMEX GC + VT Markets)")
    code = code.replace('#define G_PREFIX "VBPEA_"', '#define G_PREFIX "VBPEA_BM_"')

    # 2. Add Bookmap Inputs before Group 9 (Painel)
    bm_inputs = """
//+------------------------------------------------------------------+
//| PARÂMETROS INSTITUCIONAIS BOOKMAP & EXECUÇÃO DUAL-TRANCHE        |
//+------------------------------------------------------------------+
input group "=== 10. INTEGRAÇÃO INSTITUCIONAL BOOKMAP (COMEX GC) ==="
input bool                    InpUseBookmap            = true;                 // Ativar Conexão com Bookmap (COMEX Fluxo Real)?
input string                  InpBookmapHost           = "127.0.0.1";          // Host do Servidor Bookmap
input int                     InpBookmapPort           = 5555;                 // Porta do Servidor Bookmap
input bool                    InpAutoBasisTracking     = true;                 // Rastreamento Automático do Desconto (Basis)?
input double                  InpManualBasisOffset     = 20.0;                 // Desconto Manual (se Auto-Rastreamento = false)
input bool                    InpPlotBookmapLevels     = true;                 // Plotar Linhas de Liquidez do Bookmap no Gráfico?
input bool                    InpFilterTradesByDelta   = true;                 // Filtrar Entradas por Delta Institucional do Bookmap?
input bool                    InpUseVwapWickSignal     = true;                 // Ativar Sinal Institucional de Absorção na VWAP?
input bool                    InpTradeVwapSignals      = true;                 // Executar Ordens Automaticamente na Absorção de VWAP?
input int                     InpMinAggressionDelta    = 50;                   // Delta Mínimo de Agressão do Bookmap (+/-)
input double                  InpMinWickPct            = 20.0;                 // Tamanho Mínimo do Pavio (% do Candle)
input int                     InpMinWallVolume         = 200;                  // Volume Mínimo para Parede de Liquidez (Lotes)
input color                   InpColorBookmapVWAP      = clrMagenta;           // Cor da VWAP Total do Bookmap
input color                   InpColorBookmapPOC       = clrGold;              // Cor do POC da COMEX
input color                   InpColorBookmapVAH       = C'255,140,80';        // Cor do VAH (Value Area High 70%)
input color                   InpColorBookmapVAL       = C'100,180,255';       // Cor do VAL (Value Area Low 70%)
input color                   InpColorBookmapHVN       = clrDeepSkyBlue;       // Cor do Nó de Volume (HVN)
input color                   InpColorBidWall          = clrLimeGreen;         // Cor da Parede de Compra (Bid Wall)
input color                   InpColorAskWall          = clrRed;               // Cor da Parede de Venda (Ask Wall)

input group "=== 11. EXECUÇÃO DUAL-TRANCHE (SCALP + RUNNER INSTITUCIONAL) ==="
input bool                    InpUseDualTranche        = true;                 // Dividir Operação (50% Scalp Curto + 50% Runner)?
input int                     InpScalpSplitPercent     = 50;                   // % do Lote para a Perna de Scalp
input int                     InpScalpTakeProfitPts    = 250;                  // Take Profit da Perna de Scalp em Pontos (ex: 250 pts = $2.50)
input bool                    InpAutoBreakEvenOnScalpTP= true;                 // Mover Perna Runner para 0x0 ao Atingir TP1?
input int                     InpRunnerTrailingPts     = 300;                  // Trailing Stop da Perna Runner (Pontos)
input bool                    InpTargetRunnerToWall    = true;                 // Mirar Take do Runner na Parede de Liquidez Bookmap?
"""
    code = code.replace('input group "=== 9. PAINEL ARRASTÁVEL E MINIMIZÁVEL (HUD DASHBOARD) ==="', bm_inputs + '\ninput group "=== 9. PAINEL ARRASTÁVEL E MINIMIZÁVEL (HUD DASHBOARD) ==="')

    # 3. Globais
    bm_globals = """
//+------------------------------------------------------------------+
//| ESTRUTURA DE DADOS DO BOOKMAP EM TEMPO REAL                      |
//+------------------------------------------------------------------+
struct SBookmapData
{
   string   symbol;
   double   lastPrice;
   double   vwap;
   double   poc;
   double   vah;
   double   val;
   double   hvn;
   double   profileHigh;
   double   profileLow;
   double   bidWallPrice;
   int      bidWallVol;
   double   askWallPrice;
   int      askWallVol;
   long     delta;
   long     cvd;
   long     totalVol;
   datetime lastUpdateTime;
   bool     isConnected;
};

SBookmapData g_bmData;
double       g_smoothedBasis       = 0.0;
int          g_socketHandle        = INVALID_HANDLE;
datetime     g_lastSocketTry       = 0;
ulong        g_lastFileRead        = 0;
bool         g_botActive           = true;       // Controle Manual do Robô
bool         g_bookmapActive       = true;       // Controle Manual do Bookmap
int          g_lastSignalDirection = 0;          // 1 = Compra, -1 = Venda, 0 = Neutro
double       g_lastSignalEntry     = 0.0;
double       g_lastSignalSL        = 0.0;
double       g_lastSignalTP1       = 0.0;
double       g_lastSignalTP2       = 0.0;

// OTIMIZAÇÃO DE PERFORMANCE (ULTRA-LEVE)
ulong        g_lastRedrawTick      = 0;
int          g_lastSecRem          = -1;
double       g_lastBidPrice        = 0.0;
long         g_lastDelta           = 0;
double       g_lastRenderedVwap    = 0.0;
double       g_lastRenderedPoc     = 0.0;
double       g_lastRenderedVah     = 0.0;
double       g_lastRenderedVal     = 0.0;
double       g_lastRenderedHvn     = 0.0;
double       g_lastRenderedBidWall = 0.0;
double       g_lastRenderedAskWall = 0.0;
datetime     g_lastRenderTime      = 0;
"""
    code = code.replace("SActiveTradeMonitor g_activeTrade;", "SActiveTradeMonitor g_activeTrade;\n" + bm_globals)

    # 4. Substituir GetLineRelY e CalculateDashboardDimensions
    dim_start = code.find("int GetLineRelY(int lineIndex)")
    dim_end = code.find("bool IsTrendAligned(", dim_start)
    code = code[:dim_start] + DIMENSIONS_BLOCK + "\n" + code[dim_end:]

    # 5. Bookmap Helper Functions & Parser & Render & Absorção VWAP
    bm_funcs = """
//+------------------------------------------------------------------+
//| MÓDULO DE INTEGRAÇÃO COM BOOKMAP (COMEX FLUXO REAL)              |
//+------------------------------------------------------------------+
string ExtractJsonString(string json, string key)
{
   int pos = StringFind(json, key);
   if(pos < 0) return "";
   pos += StringLen(key);
   if(StringGetCharacter(json, pos) == 34) pos++;
   int endPos = StringFind(json, CharToString(34), pos);
   if(endPos < 0) return "";
   return StringSubstr(json, pos, endPos - pos);
}

double ExtractJsonDouble(string json, string key)
{
   int pos = StringFind(json, key);
   if(pos < 0) return 0.0;
   pos += StringLen(key);
   string sub = StringSubstr(json, pos);
   return StringToDouble(sub);
}

void ParseBookmapJson(string json)
{
   if(StringLen(json) < 10) return;

   double lp = ExtractJsonDouble(json, "\\"lp\\":");
   if(lp <= 0.0) return;

   g_bmData.lastPrice    = lp;
   g_bmData.vwap         = ExtractJsonDouble(json, "\\"vwap\\":");
   g_bmData.poc          = ExtractJsonDouble(json, "\\"poc\\":");
   g_bmData.vah          = ExtractJsonDouble(json, "\\"vah\\":");
   g_bmData.val          = ExtractJsonDouble(json, "\\"val\\":");
   g_bmData.hvn          = ExtractJsonDouble(json, "\\"hvn\\":");
   g_bmData.profileHigh  = ExtractJsonDouble(json, "\\"prh\\":");
   g_bmData.profileLow   = ExtractJsonDouble(json, "\\"prl\\":");
   g_bmData.bidWallPrice = ExtractJsonDouble(json, "\\"bwp\\":");
   g_bmData.bidWallVol   = (int)ExtractJsonDouble(json, "\\"bwv\\":");
   g_bmData.askWallPrice = ExtractJsonDouble(json, "\\"awp\\":");
   g_bmData.askWallVol   = (int)ExtractJsonDouble(json, "\\"awv\\":");
   g_bmData.delta        = (long)ExtractJsonDouble(json, "\\"del\\":");
   g_bmData.cvd          = (long)ExtractJsonDouble(json, "\\"cvd\\":");
   g_bmData.totalVol     = (long)ExtractJsonDouble(json, "\\"vol\\":");

   double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(curBid <= 0.0) curBid = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Normalização Multi-Ativo Inteligente (Ouro GC, Bitcoin BTC, etc.)
   if(curBid > 0.0 && g_bmData.lastPrice > curBid * 5.0)
   {
      double ratio = MathRound(g_bmData.lastPrice / curBid);
      if(ratio >= 8.0 && ratio <= 12.0)
      {
         g_bmData.lastPrice    /= 10.0;
         if(g_bmData.vwap > 0.0) g_bmData.vwap /= 10.0;
         g_bmData.poc          /= 10.0;
         if(g_bmData.vah > 0.0)  g_bmData.vah  /= 10.0;
         if(g_bmData.val > 0.0)  g_bmData.val  /= 10.0;
         g_bmData.hvn          /= 10.0;
         if(g_bmData.profileHigh > 0.0) g_bmData.profileHigh /= 10.0;
         if(g_bmData.profileLow > 0.0)  g_bmData.profileLow  /= 10.0;
         if(g_bmData.bidWallPrice > 0.0) g_bmData.bidWallPrice /= 10.0;
         if(g_bmData.askWallPrice > 0.0) g_bmData.askWallPrice /= 10.0;
      }
      else if(ratio >= 80.0 && ratio <= 120.0)
      {
         g_bmData.lastPrice    /= 100.0;
         if(g_bmData.vwap > 0.0) g_bmData.vwap /= 100.0;
         g_bmData.poc          /= 100.0;
         if(g_bmData.vah > 0.0)  g_bmData.vah  /= 100.0;
         if(g_bmData.val > 0.0)  g_bmData.val  /= 100.0;
         g_bmData.hvn          /= 100.0;
         if(g_bmData.profileHigh > 0.0) g_bmData.profileHigh /= 100.0;
         if(g_bmData.profileLow > 0.0)  g_bmData.profileLow  /= 100.0;
         if(g_bmData.bidWallPrice > 0.0) g_bmData.bidWallPrice /= 100.0;
         if(g_bmData.askWallPrice > 0.0) g_bmData.askWallPrice /= 100.0;
      }
   }
   else if(g_bmData.lastPrice > 10000.0 && curBid < 10000.0)
   {
      g_bmData.lastPrice /= 10.0;
      if(g_bmData.vwap > 10000.0) g_bmData.vwap /= 10.0;
      g_bmData.poc /= 10.0;
      if(g_bmData.vah > 10000.0) g_bmData.vah /= 10.0;
      if(g_bmData.val > 10000.0) g_bmData.val /= 10.0;
      g_bmData.hvn /= 10.0;
      if(g_bmData.profileHigh > 10000.0) g_bmData.profileHigh /= 10.0;
      if(g_bmData.profileLow > 10000.0)  g_bmData.profileLow  /= 10.0;
      if(g_bmData.bidWallPrice > 10000.0) g_bmData.bidWallPrice /= 10.0;
      if(g_bmData.askWallPrice > 10000.0) g_bmData.askWallPrice /= 10.0;
   }

   double areaOffset = (curBid > 10000.0) ? (curBid * 0.003) : 3.0;
   if(g_bmData.vah <= 0.0 && g_bmData.poc > 0.0) g_bmData.vah = g_bmData.poc + areaOffset;
   if(g_bmData.val <= 0.0 && g_bmData.poc > 0.0) g_bmData.val = g_bmData.poc - areaOffset;
   if(g_bmData.profileHigh <= 0.0) g_bmData.profileHigh = (g_bmData.vah > 0.0) ? (g_bmData.vah + areaOffset * 1.5) : (g_bmData.lastPrice + areaOffset * 3.0);
   if(g_bmData.profileLow <= 0.0)  g_bmData.profileLow  = (g_bmData.val > 0.0) ? (g_bmData.val - areaOffset * 1.5) : (g_bmData.lastPrice - areaOffset * 3.0);

   if(g_bmData.lastPrice > 0.0)
   {
      if(!g_bmData.isConnected)
      {
         PrintFormat("⚡ [BOOKMAP CONECTADO] COMEX: %.2f USD | Delta: %d | Poc: %.2f | VAH: %.2f | VAL: %.2f | VWAP: %.2f", g_bmData.lastPrice, g_bmData.delta, g_bmData.poc, g_bmData.vah, g_bmData.val, g_bmData.vwap);
      }
      g_bmData.lastUpdateTime = TimeCurrent();
      g_bmData.isConnected = true;

      if(curBid > 0.0)
      {
         double rawBasis = g_bmData.lastPrice - curBid;
         if(InpAutoBasisTracking)
         {
            double basisThreshold = (curBid > 10000.0) ? 1000.0 : 50.0;
            if(g_smoothedBasis == 0.0 || MathAbs(g_smoothedBasis - rawBasis) > basisThreshold)
               g_smoothedBasis = rawBasis;
            else
               g_smoothedBasis = (g_smoothedBasis * 0.95) + (rawBasis * 0.05);
         }
         else
         {
            g_smoothedBasis = InpManualBasisOffset;
         }
      }
   }
}

void UpdateBookmapData()
{
   if(!InpUseBookmap) return;

   datetime now = TimeCurrent();
   string payload = "";

   // 1. Tentar ler do Socket TCP se disponível
   if(g_socketHandle == INVALID_HANDLE && (now - g_lastSocketTry >= 3))
   {
      g_lastSocketTry = now;
      g_socketHandle = SocketCreate();
      if(g_socketHandle != INVALID_HANDLE)
      {
         if(!SocketConnect(g_socketHandle, InpBookmapHost, InpBookmapPort, 50))
         {
            SocketClose(g_socketHandle);
            g_socketHandle = INVALID_HANDLE;
         }
      }
   }

   if(g_socketHandle != INVALID_HANDLE)
   {
      if(!SocketIsConnected(g_socketHandle))
      {
         SocketClose(g_socketHandle);
         g_socketHandle = INVALID_HANDLE;
      }
      else
      {
         uint readable = SocketIsReadable(g_socketHandle);
         if(readable > 0)
         {
            uchar buffer[];
            ArrayResize(buffer, (int)readable + 1);
            int bytesRead = SocketRead(g_socketHandle, buffer, readable, 20);
            if(bytesRead > 0)
            {
               buffer[bytesRead] = 0;
               payload = CharArrayToString(buffer, 0, bytesRead, CP_UTF8);
            }
         }
      }
   }

   // 2. Fallback de Arquivo com Throttling (no máximo a cada 250ms)
   if(payload == "" && (GetTickCount64() - g_lastFileRead >= 250))
   {
      g_lastFileRead = GetTickCount64();
      int fileHandle = FileOpen("bookmap_stream.json", FILE_READ|FILE_BIN|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(fileHandle == INVALID_HANDLE)
         fileHandle = FileOpen("bookmap_stream.json", FILE_READ|FILE_BIN|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_COMMON);

      if(fileHandle != INVALID_HANDLE)
      {
         ulong sz = FileSize(fileHandle);
         if(sz > 0 && sz < 4096)
         {
            uchar buf[];
            ArrayResize(buf, (int)sz + 1);
            uint bytesRead = FileReadArray(fileHandle, buf, 0, (int)sz);
            if(bytesRead > 0)
            {
               buf[bytesRead] = 0;
               payload = CharArrayToString(buf, 0, (int)bytesRead, CP_UTF8);
            }
         }
         FileClose(fileHandle);
      }
   }

   if(payload != "")
   {
      ParseBookmapJson(payload);
   }
   else if(g_bmData.lastUpdateTime > 0 && (now - g_bmData.lastUpdateTime > 10))
   {
      g_bmData.isConnected = false;
   }
}

void DrawRayLevel(string name, datetime t1, double p1, datetime t2, double p2, color c, ENUM_LINE_STYLE st, int w, string tooltip)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);

   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}

void RenderBookmapLevels()
{
   if(!InpPlotBookmapLevels || !g_bookmapActive || !g_bmData.isConnected || g_smoothedBasis == 0.0)
   {
      ObjectDelete(0, G_PREFIX + "BM_VWAP");
      ObjectDelete(0, G_PREFIX + "BM_POC");
      ObjectDelete(0, G_PREFIX + "BM_VAH");
      ObjectDelete(0, G_PREFIX + "BM_VAL");
      ObjectDelete(0, G_PREFIX + "BM_HVN");
      ObjectDelete(0, G_PREFIX + "BM_BidWall");
      ObjectDelete(0, G_PREFIX + "BM_AskWall");
      g_lastRenderedVwap    = 0.0;
      g_lastRenderedPoc     = 0.0;
      g_lastRenderedVah     = 0.0;
      g_lastRenderedVal     = 0.0;
      g_lastRenderedHvn     = 0.0;
      g_lastRenderedBidWall = 0.0;
      g_lastRenderedAskWall = 0.0;
      return;
   }

   double mt5_vwap    = (g_bmData.vwap > 0.0) ? (g_bmData.vwap - g_smoothedBasis) : 0.0;
   double mt5_poc     = (g_bmData.poc > 0.0) ? (g_bmData.poc - g_smoothedBasis) : 0.0;
   double mt5_vah     = (g_bmData.vah > 0.0) ? (g_bmData.vah - g_smoothedBasis) : 0.0;
   double mt5_val     = (g_bmData.val > 0.0) ? (g_bmData.val - g_smoothedBasis) : 0.0;
   double mt5_hvn     = (g_bmData.hvn > 0.0) ? (g_bmData.hvn - g_smoothedBasis) : 0.0;
   double mt5_bidWall = (g_bmData.bidWallPrice > 0.0) ? (g_bmData.bidWallPrice - g_smoothedBasis) : 0.0;
   double mt5_askWall = (g_bmData.askWallPrice > 0.0) ? (g_bmData.askWallPrice - g_smoothedBasis) : 0.0;

   datetime now = TimeCurrent();
   bool levelsChanged = (MathAbs(mt5_vwap - g_lastRenderedVwap) > 0.01 ||
                         MathAbs(mt5_poc - g_lastRenderedPoc) > 0.01 ||
                         MathAbs(mt5_vah - g_lastRenderedVah) > 0.01 ||
                         MathAbs(mt5_val - g_lastRenderedVal) > 0.01 ||
                         MathAbs(mt5_hvn - g_lastRenderedHvn) > 0.01 ||
                         MathAbs(mt5_bidWall - g_lastRenderedBidWall) > 0.01 ||
                         MathAbs(mt5_askWall - g_lastRenderedAskWall) > 0.01);

   if(!levelsChanged && (now - g_lastRenderTime < 30)) return;

   g_lastRenderedVwap    = mt5_vwap;
   g_lastRenderedPoc     = mt5_poc;
   g_lastRenderedVah     = mt5_vah;
   g_lastRenderedVal     = mt5_val;
   g_lastRenderedHvn     = mt5_hvn;
   g_lastRenderedBidWall = mt5_bidWall;
   g_lastRenderedAskWall = mt5_askWall;
   g_lastRenderTime      = now;

   datetime t1 = iTime(_Symbol, _Period, MathMin(30, iBars(_Symbol, _Period) - 1));
   datetime t2 = now + PeriodSeconds(_Period) * 15;

   if(mt5_vwap > 0.0)
   {
      string vwapDesc = StringFormat("🟣 VWAP TOTAL BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.vwap, g_smoothedBasis, mt5_vwap);
      DrawRayLevel(G_PREFIX + "BM_VWAP", t1, mt5_vwap, t2, mt5_vwap, InpColorBookmapVWAP, STYLE_DASHDOT, 2, vwapDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_VWAP");

   string pocDesc = StringFormat("★ POC BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.poc, g_smoothedBasis, mt5_poc);
   DrawRayLevel(G_PREFIX + "BM_POC", t1, mt5_poc, t2, mt5_poc, InpColorBookmapPOC, STYLE_SOLID, 2, pocDesc);

   if(mt5_vah > 0.0)
   {
      string vahDesc = StringFormat("🔺 VAH 70%% BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.vah, g_smoothedBasis, mt5_vah);
      DrawRayLevel(G_PREFIX + "BM_VAH", t1, mt5_vah, t2, mt5_vah, InpColorBookmapVAH, STYLE_DASH, 1, vahDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_VAH");

   if(mt5_val > 0.0)
   {
      string valDesc = StringFormat("🔻 VAL 70%% BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.val, g_smoothedBasis, mt5_val);
      DrawRayLevel(G_PREFIX + "BM_VAL", t1, mt5_val, t2, mt5_val, InpColorBookmapVAL, STYLE_DASH, 1, valDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_VAL");

   string hvnDesc = StringFormat("✦ HVN BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.hvn, g_smoothedBasis, mt5_hvn);
   DrawRayLevel(G_PREFIX + "BM_HVN", t1, mt5_hvn, t2, mt5_hvn, InpColorBookmapHVN, STYLE_DASH, 1, hvnDesc);

   if(g_bmData.bidWallVol >= InpMinWallVolume && mt5_bidWall > 0.0)
   {
      string bwDesc = StringFormat("🛡️ PAREDE COMPRA BOOKMAP [MT5 %.2f | %d Lotes]", mt5_bidWall, g_bmData.bidWallVol);
      DrawRayLevel(G_PREFIX + "BM_BidWall", t1, mt5_bidWall, t2, mt5_bidWall, InpColorBidWall, STYLE_SOLID, 2, bwDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_BidWall");

   if(g_bmData.askWallVol >= InpMinWallVolume && mt5_askWall > 0.0)
   {
      string awDesc = StringFormat("🏰 PAREDE VENDA BOOKMAP [MT5 %.2f | %d Lotes]", mt5_askWall, g_bmData.askWallVol);
      DrawRayLevel(G_PREFIX + "BM_AskWall", t1, mt5_askWall, t2, mt5_askWall, InpColorAskWall, STYLE_SOLID, 2, awDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_AskWall");
}

void ManageDualTranchePositions()
{
   if(!InpUseDualTranche || !InpAutoBreakEvenOnScalpTP) return;

   int total = PositionsTotal();
   bool hasScalp = false;
   ulong runnerTicket = 0;
   double runnerOpenPrice = 0.0;
   double runnerSL = 0.0;
   int runnerType = -1;

   for(int i = 0; i < total; i++)
   {
      if(m_pos.SelectByIndex(i))
      {
         if(m_pos.Symbol() == _Symbol)
         {
            if(m_pos.Magic() == InpMagicNumber) hasScalp = true;
            if(m_pos.Magic() == InpMagicNumber + 1)
            {
               runnerTicket = m_pos.Ticket();
               runnerOpenPrice = m_pos.PriceOpen();
               runnerSL = m_pos.StopLoss();
               runnerType = (int)m_pos.PositionType();
            }
         }
      }
   }

   if(!hasScalp && runnerTicket > 0)
   {
      double point = _Point > 0.0 ? _Point : 0.0001;
      double bePrice = 0.0;
      bool needBE = false;

      if(runnerType == POSITION_TYPE_BUY)
      {
         bePrice = runnerOpenPrice + (InpBreakEvenExtraPoints * point);
         if(runnerSL < runnerOpenPrice) needBE = true;
      }
      else if(runnerType == POSITION_TYPE_SELL)
      {
         bePrice = runnerOpenPrice - (InpBreakEvenExtraPoints * point);
         if(runnerSL > runnerOpenPrice || runnerSL == 0.0) needBE = true;
      }

      if(needBE)
      {
         m_trade.PositionModify(runnerTicket, bePrice, m_pos.TakeProfit());
         Print("🛡️ [DUAL-TRANCHE BREAK-EVEN] Perna Scalp atingiu TP! Stop da Perna Runner movido para o 0x0 @ ", bePrice);
      }
   }
}

//+------------------------------------------------------------------+
//| NOVO GATILHO: ABSORÇÃO DE VWAP NO PAVIO COM DELTA                |
//+------------------------------------------------------------------+
void CheckVwapWickAbsorption(const MqlRates &bar, bool isLive, bool executeTrade)
{
   if(!InpUseBookmap || !g_bmData.isConnected || g_smoothedBasis == 0.0 || g_bmData.vwap <= 0.0 || !InpUseVwapWickSignal) return;
   if(!g_bookmapActive) return;

   double mt5_vwap = g_bmData.vwap - g_smoothedBasis;
   double range = bar.high - bar.low;
   if(range <= 0.0) return;

   double bodyTop    = MathMax(bar.open, bar.close);
   double bodyBottom = MathMin(bar.open, bar.close);
   double lowerWick  = bodyBottom - bar.low;
   double upperWick  = bar.high - bodyTop;
   double pt         = _Point > 0.0 ? _Point : 0.0001;
   double tol        = 10.0 * pt;

   // 1. COMPRA: VWAP Total fechando no pavio inferior + Forte Agressão Compradora
   if(lowerWick >= range * (InpMinWickPct / 100.0))
   {
      if(mt5_vwap >= (bar.low - tol) && mt5_vwap <= (bodyBottom + tol))
      {
         if(g_bmData.delta >= InpMinAggressionDelta)
         {
            string sigId = StringFormat("%sVwapAbs_Buy_%d", G_PREFIX, (int)bar.time);
            if(ObjectFind(0, sigId) < 0)
            {
               ObjectCreate(0, sigId, OBJ_ARROW_BUY, 0, bar.time, bar.low - (15 * pt));
               ObjectSetInteger(0, sigId, OBJPROP_COLOR, clrLimeGreen);
               ObjectSetInteger(0, sigId, OBJPROP_WIDTH, 3);
               ObjectSetString(0, sigId, OBJPROP_TOOLTIP, StringFormat("⚡ ABSORÇÃO COMPRADORA: VWAP no Pavio Inferior @ %.2f | Delta: %+d", mt5_vwap, g_bmData.delta));
            }

            g_lastSignalDirection = 1;
            g_lastSignalText      = StringFormat("⚡ COMPRA: Absorção VWAP no Pavio Inferior (Delta %+d)", g_bmData.delta);
            g_lastSignalColor     = clrLimeGreen;

            SetupNewTradePlan(1, bar.close, bar.time, bar.low, false);

            if(isLive)
            {
               DispatchNotification(StringFormat("⚡ [BOOKMAP ABSORÇÃO] COMPRA CONFIRMADA: VWAP @ %.2f no Pavio Inferior + Forte Delta Comprador (%+d) no %s @ %.2f!",
                                    mt5_vwap, g_bmData.delta, _Symbol, bar.close), InpSoundBOS, true);
            }

            if(executeTrade && isLive && InpTradeVwapSignals)
            {
               ExecuteRealOrder(ORDER_TYPE_BUY, bar.close, bar.low, false);
            }
            return;
         }
      }
   }

   // 2. VENDA: VWAP Total fechando no pavio superior + Forte Agressão Vendedora
   if(upperWick >= range * (InpMinWickPct / 100.0))
   {
      if(mt5_vwap >= (bodyTop - tol) && mt5_vwap <= (bar.high + tol))
      {
         if(g_bmData.delta <= -InpMinAggressionDelta)
         {
            string sigId = StringFormat("%sVwapAbs_Sell_%d", G_PREFIX, (int)bar.time);
            if(ObjectFind(0, sigId) < 0)
            {
               ObjectCreate(0, sigId, OBJ_ARROW_SELL, 0, bar.time, bar.high + (15 * pt));
               ObjectSetInteger(0, sigId, OBJPROP_COLOR, clrRed);
               ObjectSetInteger(0, sigId, OBJPROP_WIDTH, 3);
               ObjectSetString(0, sigId, OBJPROP_TOOLTIP, StringFormat("⚡ ABSORÇÃO VENDEDORA: VWAP no Pavio Superior @ %.2f | Delta: %+d", mt5_vwap, g_bmData.delta));
            }

            g_lastSignalDirection = -1;
            g_lastSignalText      = StringFormat("⚡ VENDA: Absorção VWAP no Pavio Superior (Delta %+d)", g_bmData.delta);
            g_lastSignalColor     = clrRed;

            SetupNewTradePlan(-1, bar.close, bar.time, bar.high, false);

            if(isLive)
            {
               DispatchNotification(StringFormat("⚡ [BOOKMAP ABSORÇÃO] VENDA CONFIRMADA: VWAP @ %.2f no Pavio Superior + Forte Delta Vendedor (%+d) no %s @ %.2f!",
                                    mt5_vwap, g_bmData.delta, _Symbol, bar.close), InpSoundBOS, true);
            }

            if(executeTrade && isLive && InpTradeVwapSignals)
            {
               ExecuteRealOrder(ORDER_TYPE_SELL, bar.close, bar.high, false);
            }
            return;
         }
      }
   }
}
"""
    code = code.replace("void ExecuteRealOrder(", bm_funcs + "\nvoid ExecuteRealOrder(")

    # 6. ExecuteRealOrder: Bloqueio g_botActive, filtro Delta, e envio Dual-Tranche
    exec_find = """   if(orderType == ORDER_TYPE_BUY)
   {
      m_trade.Buy(lot, _Symbol, ask, slPrice, tpPrice, isScalp ? "VBP_Scalp" : "VBP_Swing");
   }
   else
   {
      m_trade.Sell(lot, _Symbol, bid, slPrice, tpPrice, isScalp ? "VBP_Scalp" : "VBP_Swing");
   }"""

    exec_replace = """   if(!g_botActive)
   {
      Print("⛔ [ROBÔ PAUSADO] Ordem bloqueada pelo botão [BOT: OFF] no painel.");
      return;
   }

   // FILTRO INSTITUCIONAL BOOKMAP: Verifica se o Delta do COMEX apoia a entrada
   if(InpUseBookmap && g_bmData.isConnected && InpFilterTradesByDelta)
   {
      if(orderType == ORDER_TYPE_BUY  && g_bmData.delta < -150)
      {
         Print("⛔ [BOOKMAP] Compra bloqueada: Delta Vendedor Agressivo massivo no COMEX (", g_bmData.delta, ")");
         return;
      }
      if(orderType == ORDER_TYPE_SELL && g_bmData.delta > 150)
      {
         Print("⛔ [BOOKMAP] Venda bloqueada: Delta Comprador Agressivo massivo no COMEX (", g_bmData.delta, ")");
         return;
      }
   }

   // EXECUÇÃO DUAL-TRANCHE: Divide em Scalp (50%) + Runner para Surfar (50%)
   if(InpUseDualTranche && !isScalp)
   {
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double lotScalp  = MathMax(minLot, MathFloor((lot * (InpScalpSplitPercent / 100.0)) / step) * step);
      double lotRunner = MathMax(minLot, MathFloor((lot - lotScalp) / step) * step);

      // TP do Scalp
      double tpScalp = (orderType == ORDER_TYPE_BUY) ? (ask + InpScalpTakeProfitPts * point) : (bid - InpScalpTakeProfitPts * point);

      // TP do Runner (mirando na parede de liquidez ou 1:3 RR)
      double tpRunner = 0.0;
      if(InpTargetRunnerToWall && g_bmData.isConnected && g_smoothedBasis != 0.0)
      {
         if(orderType == ORDER_TYPE_BUY && g_bmData.askWallVol >= InpMinWallVolume)
         {
            double wallPrice = g_bmData.askWallPrice - g_smoothedBasis;
            if(wallPrice > ask + (InpScalpTakeProfitPts * 2 * point))
               tpRunner = wallPrice - (10 * point);
         }
         else if(orderType == ORDER_TYPE_SELL && g_bmData.bidWallVol >= InpMinWallVolume)
         {
            double wallPrice = g_bmData.bidWallPrice - g_smoothedBasis;
            if(wallPrice < bid - (InpScalpTakeProfitPts * 2 * point))
               tpRunner = wallPrice + (10 * point);
         }
      }
      if(tpRunner == 0.0)
      {
         double riskDist = MathAbs(ask - slPrice);
         tpRunner = (orderType == ORDER_TYPE_BUY) ? (ask + riskDist * 3.0) : (bid - riskDist * 3.0);
      }

      // Disparo da Perna 1 (Scalp)
      m_trade.SetExpertMagicNumber(InpMagicNumber);
      if(orderType == ORDER_TYPE_BUY)
         m_trade.Buy(lotScalp, _Symbol, ask, slPrice, tpScalp, "VBP_Scalp_Tranche");
      else
         m_trade.Sell(lotScalp, _Symbol, bid, slPrice, tpScalp, "VBP_Scalp_Tranche");

      // Disparo da Perna 2 (Runner)
      m_trade.SetExpertMagicNumber(InpMagicNumber + 1);
      if(orderType == ORDER_TYPE_BUY)
         m_trade.Buy(lotRunner, _Symbol, ask, slPrice, tpRunner, "VBP_Runner_Tranche");
      else
         m_trade.Sell(lotRunner, _Symbol, bid, slPrice, tpRunner, "VBP_Runner_Tranche");

      m_trade.SetExpertMagicNumber(InpMagicNumber);
      Print("🚀 [DUAL-TRANCHE EXECUTADO] Scalp: ", lotScalp, " lotes (TP: ", tpScalp, ") | Runner: ", lotRunner, " lotes (TP: ", tpRunner, ")");
      return;
   }

   if(orderType == ORDER_TYPE_BUY)
   {
      m_trade.Buy(lot, _Symbol, ask, slPrice, tpPrice, isScalp ? "VBP_Scalp" : "VBP_Swing");
   }
   else
   {
      m_trade.Sell(lot, _Symbol, bid, slPrice, tpPrice, isScalp ? "VBP_Scalp" : "VBP_Swing");
   }"""
    code = code.replace(exec_find, exec_replace)

    # 7. Atualizar SetupNewTradePlan para registrar sinal
    plan_record = """   g_lastSignalDirection = dir;
   g_lastSignalEntry     = entryP;
   g_lastSignalSL        = slPrice;
   g_lastSignalTP1       = (dir == 1) ? (entryP + InpScalpTakeProfitPts * point) : (entryP - InpScalpTakeProfitPts * point);
   g_lastSignalTP2       = tpPrice;

   datetime tEnd = entryT + PeriodSeconds(_Period) * 30;"""
    code = code.replace("datetime tEnd = entryT + PeriodSeconds(_Period) * 30;", plan_record)

    # 8. Inserir chamada de CheckVwapWickAbsorption no loop de ExecuteBarCalculations
    calc_loop_find = """      // 4. Scalpers
      if(InpEnableScalpers)
      {
         DetectIntermediateScalpsAndTrade(i, rates, emaArr, adxArr, barIsLive, drawObjects);
      }
   }"""
    calc_loop_replace = """      // 4. Scalpers
      if(InpEnableScalpers)
      {
         DetectIntermediateScalpsAndTrade(i, rates, emaArr, adxArr, barIsLive, drawObjects);
      }

      // 5. GATILHO INSTITUCIONAL BOOKMAP: Absorção na VWAP com Agressão
      if(InpUseBookmap && InpUseVwapWickSignal)
      {
         CheckVwapWickAbsorption(rates[i], barIsLive, true);
      }
   }"""
    code = code.replace(calc_loop_find, calc_loop_replace)

    # 9. Inserir verificação da VWAP em tempo real no DiagnoseLiveCandleAction
    diag_find = """   if(pctLower >= 45.0)
   {
      g_candleActionText  = "🔥 ABSORÇÃO COMPRADORA (Pavio " + DoubleToString(pctLower, 0) + "%)";
      g_candleActionColor = clrLimeGreen;
   }"""
    diag_replace = """   if(InpUseBookmap && g_bmData.isConnected && g_bmData.vwap > 0.0 && g_smoothedBasis != 0.0)
   {
      double mt5_vwap = g_bmData.vwap - g_smoothedBasis;
      double bTop = MathMax(cOpen, cClose);
      double bBot = MathMin(cOpen, cClose);
      double tol  = 10.0 * _Point;

      if(mt5_vwap >= (cLow - tol) && mt5_vwap <= (bBot + tol) && pctLower >= InpMinWickPct)
      {
         g_candleActionText  = StringFormat("⚡ ABSORÇÃO VWAP NO PAVIO INFERIOR (Pavio %.0f%% | Delta %+d)", pctLower, g_bmData.delta);
         g_candleActionColor = (g_bmData.delta >= InpMinAggressionDelta) ? clrLimeGreen : clrGold;
      }
      else if(mt5_vwap >= (bTop - tol) && mt5_vwap <= (cHigh + tol) && pctUpper >= InpMinWickPct)
      {
         g_candleActionText  = StringFormat("⚡ ABSORÇÃO VWAP NO PAVIO SUPERIOR (Pavio %.0f%% | Delta %+d)", pctUpper, g_bmData.delta);
         g_candleActionColor = (g_bmData.delta <= -InpMinAggressionDelta) ? clrCrimson : clrGold;
      }
      else if(pctLower >= 45.0)
      {
         g_candleActionText  = "🔥 ABSORÇÃO COMPRADORA (Pavio " + DoubleToString(pctLower, 0) + "%)";
         g_candleActionColor = clrLimeGreen;
      }
      else if(pctUpper >= 45.0)
      {
         g_candleActionText  = "🔻 ABSORÇÃO VENDEDORA (Pavio " + DoubleToString(pctUpper, 0) + "%)";
         g_candleActionColor = clrCrimson;
      }
      else if(pctBody >= 68.0 && cClose > cOpen)
      {
         g_candleActionText  = "🚀 IMPULSO COMPRADOR (Corpo " + DoubleToString(pctBody, 0) + "%)";
         g_candleActionColor = clrLime;
      }
      else if(pctBody >= 68.0 && cClose < cOpen)
      {
         g_candleActionText  = "💥 IMPULSO VENDEDOR (Corpo " + DoubleToString(pctBody, 0) + "%)";
         g_candleActionColor = clrRed;
      }
      else
      {
         g_candleActionText  = "⚖ EQUILÍBRIO / MICRO-LATERAL (Corpo " + DoubleToString(pctBody, 0) + "%)";
         g_candleActionColor = clrSilver;
      }
   }
   else if(pctLower >= 45.0)
   {
      g_candleActionText  = "🔥 ABSORÇÃO COMPRADORA (Pavio " + DoubleToString(pctLower, 0) + "%)";
      g_candleActionColor = clrLimeGreen;
   }"""
    code = code.replace(diag_find, diag_replace)

    # 10. Atualizar OnInit e OnDeinit com Timer ultraleve (500ms)
    code = code.replace("ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);\n   return(INIT_SUCCEEDED);", 
                        "ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);\n   EventSetMillisecondTimer(500);\n   UpdateBookmapData();\n   RenderBookmapLevels();\n   return(INIT_SUCCEEDED);")

    code = code.replace("void OnDeinit(const int reason)\n{\n   CleanObjects(G_PREFIX);\n   ChartRedraw(0);\n}",
                        "void OnDeinit(const int reason)\n{\n   EventKillTimer();\n   if(g_socketHandle != INVALID_HANDLE) { SocketClose(g_socketHandle); g_socketHandle = INVALID_HANDLE; }\n   CleanObjects(G_PREFIX);\n   ChartRedraw(0);\n}")

    # 11. Adicionar OnTimer ultraleve com Dirty-Check
    ontimer_block = """
//+------------------------------------------------------------------+
//| EVENTO DE TIMER (ATUALIZAÇÃO INSTANTÂNEA BOOKMAP & DASHBOARD)    |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateBookmapData();
   RenderBookmapLevels();
   ManageDualTranchePositions();

   if(InpShowDashboard)
   {
      double curPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(curPrice > 0.0)
      {
         UpdateDashboardContent(curPrice);

         // Redraw Inteligente (Dirty Check): Só redesenha se houver alteração real
         datetime barTime = iTime(_Symbol, _Period, 0);
         int secRem = (int)((barTime + PeriodSeconds(_Period)) - TimeCurrent());
         ulong nowTick = GetTickCount64();

         bool priceChanged = MathAbs(curPrice - g_lastBidPrice) > (0.5 * _Point);
         bool secChanged   = (secRem != g_lastSecRem);
         bool deltaChanged = (g_bmData.delta != g_lastDelta);

         if(priceChanged || secChanged || deltaChanged || (nowTick - g_lastRedrawTick >= 1000))
         {
            g_lastBidPrice   = curPrice;
            g_lastSecRem     = secRem;
            g_lastDelta      = g_bmData.delta;
            g_lastRedrawTick = nowTick;
            ChartRedraw(0);
         }
      }
   }
}
"""
    code = code.replace("void OnTick()", ontimer_block + "\nvoid OnTick()")

    # 12. Substituir OnChartEvent por versão robusta e fluida
    oce_start = code.find("void OnChartEvent(const int id,")
    oce_end   = code.find("//| GERENCIAMENTO DE SWINGS E ESTRUTURAS", oce_start)

    oce_new = """void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(!InpShowDashboard) return;

   // 1. Cliques nos Botões do Cabeçalho
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == G_PREFIX + "Btn_Min")
      {
         g_panelMinimized = !g_panelMinimized;
         ObjectSetString(0, G_PREFIX + "Btn_Min", OBJPROP_TEXT, g_panelMinimized ? "+" : "—");
         ObjectSetInteger(0, G_PREFIX + "Dash_BG", OBJPROP_YSIZE, g_panelMinimized ? g_panelHeightMin : g_panelHeightFull);
         UpdateDashboardVisibility();
         ChartRedraw(0);
         return;
      }

      if(sparam == G_PREFIX + "Btn_Reset")
      {
         g_totalTradesWon      = 0;
         g_totalTradesLost     = 0;
         g_totalValidPullbacks = 0;
         g_totalValidBOS       = 0;
         g_totalScalps         = 0;
         g_lastSignalDirection = 0;
         g_lastSignalText      = "Estatísticas Resetadas";
         g_lastSignalColor     = clrSilver;
         g_activeTrade.Reset();
         CleanObjects(G_PREFIX + "Trade_");
         CleanObjects(G_PREFIX + "Outcome_");
         CleanObjects(G_PREFIX + "Bull_Zone_");
         CleanObjects(G_PREFIX + "Bear_Zone_");
         UpdateDashboardContent(SymbolInfoDouble(_Symbol, SYMBOL_BID));
         ChartRedraw(0);
         return;
      }

      if(sparam == G_PREFIX + "Btn_ToggleBot")
      {
         g_botActive = !g_botActive;
         ObjectSetString(0, G_PREFIX + "Btn_ToggleBot", OBJPROP_TEXT, g_botActive ? "🟢 BOT: ON" : "🔴 BOT: OFF");
         ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBot", OBJPROP_BGCOLOR, g_botActive ? C'20,60,35' : C'70,25,25');
         UpdateDashboardContent(SymbolInfoDouble(_Symbol, SYMBOL_BID));
         ChartRedraw(0);
         return;
      }

      if(sparam == G_PREFIX + "Btn_ToggleBM")
      {
         g_bookmapActive = !g_bookmapActive;
         ObjectSetString(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_TEXT, g_bookmapActive ? "⚡ BM: ON" : "⚡ BM: OFF");
         ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_BGCOLOR, g_bookmapActive ? C'25,50,75' : C'50,50,50');
         ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_COLOR, g_bookmapActive ? clrAqua : clrSilver);
         if(!g_bookmapActive)
         {
            ObjectDelete(0, G_PREFIX + "BM_VWAP");
            ObjectDelete(0, G_PREFIX + "BM_POC");
            ObjectDelete(0, G_PREFIX + "BM_VAH");
            ObjectDelete(0, G_PREFIX + "BM_VAL");
            ObjectDelete(0, G_PREFIX + "BM_HVN");
            ObjectDelete(0, G_PREFIX + "BM_BidWall");
            ObjectDelete(0, G_PREFIX + "BM_AskWall");
         }
         else
         {
            RenderBookmapLevels();
         }
         ChartRedraw(0);
         return;
      }
   }

   // 2. Arrastar livremente com clique e arrasto no cabeçalho
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      uint mouseState = (uint)sparam;
      bool leftDown = ((mouseState & 1) == 1);

      if(leftDown)
      {
         if(!g_isDragging)
         {
            if(mouseX >= g_panelX && mouseX <= (g_panelX + g_panelWidth) &&
               mouseY >= g_panelY && mouseY <= (g_panelY + g_headerH))
            {
               g_isDragging  = true;
               g_dragOffsetX = mouseX - g_panelX;
               g_dragOffsetY = mouseY - g_panelY;
            }
         }
         else
         {
            g_panelX = mouseX - g_dragOffsetX;
            g_panelY = mouseY - g_dragOffsetY;

            int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
            int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

            if(g_panelX < 0) g_panelX = 0;
            if(g_panelY < 0) g_panelY = 0;
            if(g_panelX + g_panelWidth > chartW) g_panelX = MathMax(0, chartW - g_panelWidth);
            if(g_panelY + g_headerH > chartH)    g_panelY = MathMax(0, chartH - g_headerH);

            RepositionDashboard();
            ChartRedraw(0);
         }
      }
      else
      {
         g_isDragging = false;
      }
   }
}
"""
    code = code[:oce_start] + oce_new + "\n//+------------------------------------------------------------------+\n" + code[oce_end:]

    # 13. Substituir CreateInteractiveDashboard até o fim de UpdateDashboardContent
    dash_start = code.find("void CreateInteractiveDashboard()")
    dash_end   = code.find("void CreateDashLabel(", dash_start)

    dash_new = """void CreateInteractiveDashboard()
{
   CalculateDashboardDimensions();

   string bgName = G_PREFIX + "Dash_BG";
   ObjectDelete(0, bgName);
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, g_panelY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, g_panelWidth);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, g_panelMinimized ? g_panelHeightMin : g_panelHeightFull);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, InpPanelBgColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, InpPanelBorderColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);

   string hdName = G_PREFIX + "Dash_Header";
   ObjectDelete(0, hdName);
   ObjectCreate(0, hdName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, hdName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, hdName, OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, hdName, OBJPROP_YDISTANCE, g_panelY);
   ObjectSetInteger(0, hdName, OBJPROP_XSIZE, g_panelWidth);
   ObjectSetInteger(0, hdName, OBJPROP_YSIZE, g_headerH);
   ObjectSetInteger(0, hdName, OBJPROP_BGCOLOR, InpPanelHeaderColor);
   ObjectSetInteger(0, hdName, OBJPROP_BORDER_COLOR, InpPanelBorderColor);
   ObjectSetInteger(0, hdName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, hdName, OBJPROP_SELECTABLE, false);

   CreateDashLabel(G_PREFIX + "Lbl_Title", "★ VALID BOS EXPERT PRO | @viniciusburgo", 12, (g_headerH - g_fontSize - 4) / 2, clrGold, g_fontSize, true);

   int btnH = (int)MathRound(20.0 * ((double)g_fontSize / 8.0));
   int btnY = (g_headerH - btnH) / 2;

   int wBot = 92;
   int wBM  = 80;
   int wMin = 22;
   int wRes = 22;

   int curX = g_panelWidth - 6;

   curX -= wRes;
   CreateDashButton(G_PREFIX + "Btn_Reset", "R", curX, btnY, wRes, btnH, C'50,30,40', clrLightCoral, g_fontSize);

   curX -= (wMin + 4);
   CreateDashButton(G_PREFIX + "Btn_Min", g_panelMinimized ? "+" : "—", curX, btnY, wMin, btnH, C'35,48,72', clrWhite, g_fontSize);

   curX -= (wBM + 4);
   CreateDashButton(G_PREFIX + "Btn_ToggleBM", g_bookmapActive ? "⚡ BM: ON" : "⚡ BM: OFF", curX, btnY, wBM, btnH, g_bookmapActive ? C'25,50,75' : C'50,50,50', g_bookmapActive ? clrAqua : clrSilver, g_fontSize - 1);

   curX -= (wBot + 4);
   CreateDashButton(G_PREFIX + "Btn_ToggleBot", g_botActive ? "🟢 BOT: ON" : "🔴 BOT: OFF", curX, btnY, wBot, btnH, g_botActive ? C'20,60,35' : C'70,25,25', clrWhite, g_fontSize - 1);

   CreateDashLabel(G_PREFIX + "Txt_Timer",       "⏱ Candle: --:-- | Spread: -- pts | Corretora VT Markets", 12, GetLineRelY(0), clrAqua, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_Action",      "🎯 AÇÃO IMEDIATA: [ ⚪ MONITORANDO FLUXO ]", 12, GetLineRelY(1), clrGold, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_EntrySL",     "📍 ENTRADA EXATA: --- | 🛑 STOP LOSS: ---", 12, GetLineRelY(2), clrWhite, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_TPTargets",   "🎯 ALVOS: TP1 (Scalp 50%) --- | 🚀 TP2 (Runner 50%) ---", 12, GetLineRelY(3), clrDeepSkyBlue, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_RiskRule",    "🛡️ GESTÃO: Ao atingir TP1 ➔ Stop do Runner vai pro Zero a Zero (0x0)!", 12, GetLineRelY(4), clrYellowGreen, g_fontSize - 1, false);
   CreateDashLabel(G_PREFIX + "Txt_ResSup",      "Resistência Topo: --- | Suporte Fundo: ---", 12, GetLineRelY(5), clrOrange, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BMComp",      "⚡ BOOKMAP COMEX GC: --- | 🏦 VT MARKETS SPOT: ---", 12, GetLineRelY(6), clrAqua, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMBasis",     "⚖ DIFERENÇA (BASIS): --- ➔ Níveis projetados nas velas MT5", 12, GetLineRelY(7), clrGold, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMDelta",     "📊 DELTA COMEX: --- | CVD: ---", 12, GetLineRelY(8), clrSilver, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMNodes",     "🟣 VWAP: --- | ★ POC: --- | 🔺 VAH: --- | 🔻 VAL: ---", 12, GetLineRelY(9), clrGold, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BMVPVR",      "📊 VPVR: Range [--- ⟷ ---] | Status: Aguardando...", 12, GetLineRelY(10), clrAqua, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMWalls",     "🏰 PAREDE VENDA: --- | 🛡️ PAREDE COMPRA: ---", 12, GetLineRelY(11), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_LiveCandle",  "Vela [0]: Monitorando microestrutura...", 12, GetLineRelY(12), clrWhite, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_Diag",        "Contexto Técnico: Analisando EMA / ADX...", 12, GetLineRelY(13), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BotStatus",   "STATUS OPERACIONAL: 🟢 ROBÔ LIGADO (EXECUÇÃO AUTOMÁTICA)", 12, GetLineRelY(14), clrLimeGreen, g_fontSize, true);

   UpdateDashboardVisibility();
}

void RepositionDashboard()
{
   ObjectSetInteger(0, G_PREFIX + "Dash_BG", OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, G_PREFIX + "Dash_BG", OBJPROP_YDISTANCE, g_panelY);
   ObjectSetInteger(0, G_PREFIX + "Dash_Header", OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, G_PREFIX + "Dash_Header", OBJPROP_YDISTANCE, g_panelY);

   int btnH = (int)MathRound(20.0 * ((double)g_fontSize / 8.0));
   int btnY = (g_headerH - btnH) / 2;

   int wBot = 92;
   int wBM  = 80;
   int wMin = 22;
   int wRes = 22;

   ObjectSetInteger(0, G_PREFIX + "Lbl_Title", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Lbl_Title", OBJPROP_YDISTANCE, g_panelY + (g_headerH - g_fontSize - 4) / 2);

   int curX = g_panelWidth - 6;

   curX -= wRes;
   ObjectSetInteger(0, G_PREFIX + "Btn_Reset", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_Reset", OBJPROP_YDISTANCE, g_panelY + btnY);

   curX -= (wMin + 4);
   ObjectSetInteger(0, G_PREFIX + "Btn_Min", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_Min", OBJPROP_YDISTANCE, g_panelY + btnY);

   curX -= (wBM + 4);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_YDISTANCE, g_panelY + btnY);

   curX -= (wBot + 4);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBot", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBot", OBJPROP_YDISTANCE, g_panelY + btnY);

   ObjectSetInteger(0, G_PREFIX + "Txt_Timer", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Timer", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(0));

   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(1));

   ObjectSetInteger(0, G_PREFIX + "Txt_EntrySL", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_EntrySL", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(2));

   ObjectSetInteger(0, G_PREFIX + "Txt_TPTargets", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_TPTargets", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(3));

   ObjectSetInteger(0, G_PREFIX + "Txt_RiskRule", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_RiskRule", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(4));

   ObjectSetInteger(0, G_PREFIX + "Txt_ResSup", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_ResSup", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(5));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMComp", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMComp", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(6));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMBasis", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMBasis", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(7));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(8));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMNodes", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMNodes", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(9));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(10));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(11));

   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(12));

   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(13));

   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(14));
}

void UpdateDashboardVisibility()
{
   long hiddenFlag = g_panelMinimized ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;

   ObjectSetInteger(0, G_PREFIX + "Txt_Timer", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_EntrySL", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_TPTargets", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_RiskRule", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_ResSup", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMComp", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_TIMEFRAMES, hiddenFlag);
}

void UpdateDashboardContent(double curPrice)
{
   if(g_panelMinimized) return;

   double pt = _Point > 0.0 ? _Point : 0.0001;

   datetime barTime = iTime(_Symbol, _Period, 0);
   int secRem = (int)((barTime + PeriodSeconds(_Period)) - TimeCurrent());
   if(secRem < 0) secRem = 0;
   int mins = secRem / 60;
   int secs = secRem % 60;
   string timerStr = StringFormat("⏱ Candle: %02d:%02d | Spread: %d pts | Corretora: VT Markets", mins, secs, (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   ObjectSetString(0, G_PREFIX + "Txt_Timer", OBJPROP_TEXT, timerStr);

   bool hasPos = false;
   string posDir = "";
   double posOpenPrice = 0.0;
   double posSL = 0.0;
   double posTP = 0.0;
   double posProfit = 0.0;
   double posVol = 0.0;

   int totalPos = PositionsTotal();
   for(int i = 0; i < totalPos; i++)
   {
      if(m_pos.SelectByIndex(i))
      {
         if(m_pos.Symbol() == _Symbol && (m_pos.Magic() == InpMagicNumber || m_pos.Magic() == InpMagicNumber + 1))
         {
            hasPos = true;
            posDir = (m_pos.PositionType() == POSITION_TYPE_BUY) ? "COMPRADO" : "VENDIDO";
            posOpenPrice = m_pos.PriceOpen();
            posSL = m_pos.StopLoss();
            posTP = m_pos.TakeProfit();
            posProfit += m_pos.Profit();
            posVol += m_pos.Volume();
         }
      }
   }

   string actionTxt = "";
   color actionClr = clrGold;
   string entrySLTxt = "";
   string tpTargetsTxt = "";

   if(hasPos)
   {
      actionTxt = StringFormat("🎯 POSIÇÃO ATIVA: [ %s %.2f lotes @ %.2f ] | Lucro: $%.2f", posDir, posVol, posOpenPrice, posProfit);
      actionClr = (posProfit >= 0.0) ? clrLimeGreen : clrCrimson;

      double slDistPts = MathAbs(curPrice - posSL) / pt;
      entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts] (Protegendo Capital)", posOpenPrice, posSL, slDistPts);

      double tpDistPts = MathAbs(posTP - curPrice) / pt;
      tpTargetsTxt = StringFormat("🎯 TAKE PROFIT ATIVO: %.2f [%.0f pts restantes para o Alvo]", posTP, tpDistPts);
   }
   else
   {
      if(g_lastSignalDirection == 1)
      {
         actionTxt = "🎯 SINAL RECOMENDADO: [ 🟢 FORTE COMPRA NO PULLBACK / VWAP ]";
         actionClr = clrLimeGreen;
         double estSL = (g_lastSignalSL > 0.0) ? g_lastSignalSL : (g_currentSwingLow > 0.0 ? (g_currentSwingLow - InpSLBufferPoints * pt) : (curPrice - InpMinSLPoints * pt));
         double slPts = MathAbs(curPrice - estSL) / pt;
         entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts]", curPrice, estSL, slPts);
         double tp1 = curPrice + (InpScalpTakeProfitPts * pt);
         double tp2 = curPrice + (slPts * InpRiskRewardRatio * pt);
         tpTargetsTxt = StringFormat("🎯 TP1 (Scalp 50%%): %.2f [+%d pts] | 🚀 TP2 (Runner 50%%): %.2f", tp1, InpScalpTakeProfitPts, tp2);
      }
      else if(g_lastSignalDirection == -1)
      {
         actionTxt = "🎯 SINAL RECOMENDADO: [ 🔴 FORTE VENDA NO PULLBACK / VWAP ]";
         actionClr = clrRed;
         double estSL = (g_lastSignalSL > 0.0) ? g_lastSignalSL : (g_currentSwingHigh > 0.0 ? (g_currentSwingHigh + InpSLBufferPoints * pt) : (curPrice + InpMinSLPoints * pt));
         double slPts = MathAbs(estSL - curPrice) / pt;
         entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts]", curPrice, estSL, slPts);
         double tp1 = curPrice - (InpScalpTakeProfitPts * pt);
         double tp2 = curPrice - (slPts * InpRiskRewardRatio * pt);
         tpTargetsTxt = StringFormat("🎯 TP1 (Scalp 50%%): %.2f [-%d pts] | 🚀 TP2 (Runner 50%%): %.2f", tp1, InpScalpTakeProfitPts, tp2);
      }
      else
      {
         actionTxt = "🎯 AÇÃO IMEDIATA: [ ⚪ MONITORANDO FLUXO & ABSORÇÃO NA VWAP ]";
         actionClr = clrGold;
         entrySLTxt = StringFormat("📍 PRÓX. COMPRA: Acima de %.2f (Topo) | PRÓX. VENDA: Abaixo de %.2f (Fundo)", g_currentSwingHigh, g_currentSwingLow);
         tpTargetsTxt = StringFormat("🎯 ALVOS PADRÃO: TP1 Scalp %d pts | TP2 Runner Parede de Liquidez Bookmap", InpScalpTakeProfitPts);
      }
   }

   ObjectSetString(0, G_PREFIX + "Txt_Action", OBJPROP_TEXT, actionTxt);
   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_COLOR, actionClr);

   ObjectSetString(0, G_PREFIX + "Txt_EntrySL", OBJPROP_TEXT, entrySLTxt);
   ObjectSetString(0, G_PREFIX + "Txt_TPTargets", OBJPROP_TEXT, tpTargetsTxt);

   ObjectSetString(0, G_PREFIX + "Txt_RiskRule", OBJPROP_TEXT, "🛡️ GESTÃO DE CAPITAL: Ao atingir TP1 ➔ SL da Perna Runner é puxado para o 0x0 (Break-Even)!");

   string resStr = "Resistência (Topo MT5): " + (g_currentSwingHigh > 0.0 ? DoubleToString(g_currentSwingHigh, _Digits) : "---");
   if(g_currentSwingHigh > 0.0) resStr += StringFormat(" [%.0f pts]", (g_currentSwingHigh - curPrice) / pt);
   string supStr = "Suporte (Fundo MT5): " + (g_currentSwingLow > 0.0 ? DoubleToString(g_currentSwingLow, _Digits) : "---");
   if(g_currentSwingLow > 0.0) supStr += StringFormat(" [%.0f pts]", (curPrice - g_currentSwingLow) / pt);
   ObjectSetString(0, G_PREFIX + "Txt_ResSup", OBJPROP_TEXT, resStr + " | " + supStr);

   if(g_bmData.isConnected && g_bmData.lastPrice > 0.0)
   {
      string bmSym = (g_bmData.symbol != "" ? g_bmData.symbol : (curPrice > 10000.0 ? "BTC" : "COMEX GC"));
      string compStr = StringFormat("⚡ BOOKMAP %s: %.2f USD | 🏦 %s SPOT: %.2f USD", bmSym, g_bmData.lastPrice, _Symbol, curPrice);
      ObjectSetString(0, G_PREFIX + "Txt_BMComp", OBJPROP_TEXT, compStr);

      string basisStr = StringFormat("⚖ DIFERENÇA (BASIS): %+.2f USD ➔ Níveis Bookmap sincronizados nas velas MT5", g_smoothedBasis);
      ObjectSetString(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TEXT, basisStr);

      string deltaDiag = (g_bmData.delta > 50) ? "[COMPRADORES ATIVOS]" : ((g_bmData.delta < -50) ? "[VENDEDORES ATIVOS]" : "[FLUXO EQUILIBRADO]");
      color deltaClr = (g_bmData.delta > 0) ? clrLimeGreen : ((g_bmData.delta < 0) ? clrCrimson : clrSilver);
      string deltaStr = StringFormat("📊 DELTA BOOKMAP: %+d %s | CVD: %+d | Vol Total: %d", g_bmData.delta, deltaDiag, g_bmData.cvd, g_bmData.totalVol);
      ObjectSetString(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TEXT, deltaStr);
      ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_COLOR, deltaClr);

      double mt5_vwap = (g_bmData.vwap > 0.0) ? (g_bmData.vwap - g_smoothedBasis) : 0.0;
      double mt5_poc  = (g_bmData.poc > 0.0) ? (g_bmData.poc - g_smoothedBasis) : 0.0;
      double mt5_vah  = (g_bmData.vah > 0.0) ? (g_bmData.vah - g_smoothedBasis) : 0.0;
      double mt5_val  = (g_bmData.val > 0.0) ? (g_bmData.val - g_smoothedBasis) : 0.0;
      string nodesStr = StringFormat("🟣 VWAP: %.2f | ★ POC: %.2f | 🔺 VAH: %.2f | 🔻 VAL: %.2f", mt5_vwap, mt5_poc, mt5_vah, mt5_val);
      ObjectSetString(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TEXT, nodesStr);

      double mt5_prh = (g_bmData.profileHigh > 0.0) ? (g_bmData.profileHigh - g_smoothedBasis) : (mt5_vah > 0.0 ? mt5_vah + 5.0 : curPrice + 10.0);
      double mt5_prl = (g_bmData.profileLow > 0.0) ? (g_bmData.profileLow - g_smoothedBasis) : (mt5_val > 0.0 ? mt5_val - 5.0 : curPrice - 10.0);
      string vpvrStatus = "";
      color  vpvrClr    = clrSilver;

      if(mt5_vah > 0.0 && mt5_val > 0.0)
      {
         if(curPrice > mt5_vah)
         {
            double diffPts = (curPrice - mt5_vah) / pt;
            vpvrStatus = StringFormat("🚀 ACIMA DO VAH (+%.0f pts) | EXPANSÃO COMPRADORA", diffPts);
            vpvrClr = clrLimeGreen;
         }
         else if(curPrice < mt5_val)
         {
            double diffPts = (mt5_val - curPrice) / pt;
            vpvrStatus = StringFormat("💥 ABAIXO DO VAL (-%.0f pts) | EXPANSÃO VENDEDORA", diffPts);
            vpvrClr = clrCrimson;
         }
         else
         {
            double distPoc = (curPrice - mt5_poc) / pt;
            vpvrStatus = StringFormat("⚖ NA VALUE AREA 70%% (Afast. POC %+.0f pts)", distPoc);
            vpvrClr = clrGold;
         }
      }
      else
      {
         vpvrStatus = "Calculando distribuição VPVR...";
         vpvrClr = clrSilver;
      }

      string vpvrStr = StringFormat("📊 VPVR: Range [%.2f ⟷ %.2f] | %s", mt5_prl, mt5_prh, vpvrStatus);
      ObjectSetString(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_TEXT, vpvrStr);
      ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_COLOR, vpvrClr);

      double mt5_bidWall = (g_bmData.bidWallPrice > 0.0) ? (g_bmData.bidWallPrice - g_smoothedBasis) : 0.0;
      double mt5_askWall = (g_bmData.askWallPrice > 0.0) ? (g_bmData.askWallPrice - g_smoothedBasis) : 0.0;
      string wallsStr = "";
      if(g_bmData.askWallVol >= InpMinWallVolume && mt5_askWall > 0.0)
         wallsStr += StringFormat("🏰 VENDA: %.2f (%d lotes) ", mt5_askWall, g_bmData.askWallVol);
      else
         wallsStr += "🏰 VENDA: Sem parede massiva ";

      if(g_bmData.bidWallVol >= InpMinWallVolume && mt5_bidWall > 0.0)
         wallsStr += StringFormat("| 🛡️ COMPRA: %.2f (%d lotes)", mt5_bidWall, g_bmData.bidWallVol);
      else
         wallsStr += "| 🛡️ COMPRA: Sem parede massiva";
      ObjectSetString(0, G_PREFIX + "Txt_BMWalls", OBJPROP_TEXT, wallsStr);
   }
   else
   {
      ObjectSetString(0, G_PREFIX + "Txt_BMComp", OBJPROP_TEXT, "⚡ BOOKMAP: Conectando na porta 5555 / arquivo stream...");
      ObjectSetString(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TEXT, "⚖ DIFERENÇA (BASIS): Aguardando primeiro tick do COMEX...");
      ObjectSetString(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TEXT, "📊 DELTA BOOKMAP: Aguardando fluxo...");
      ObjectSetString(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TEXT, "🟣 VWAP & PROFILE (POC/VAH/VAL): Aguardando Bookmap...");
      ObjectSetString(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_TEXT, "📊 VPVR: Aguardando distribuição de volume Bookmap...");
      ObjectSetString(0, G_PREFIX + "Txt_BMWalls", OBJPROP_TEXT, "🏰 PAREDES DE LIQUIDEZ: Aguardando profundidade DOM...");
   }

   ObjectSetString(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_TEXT, "Vela [0]: " + g_candleActionText);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_COLOR, g_candleActionColor);

   string filterStr = "";
   if(InpUseEMATrendFilter && g_handleEMA != INVALID_HANDLE)
   {
      double emaBuf[1];
      if(CopyBuffer(g_handleEMA, 0, 0, 1, emaBuf) > 0)
      {
         if(curPrice > emaBuf[0]) filterStr += "[EMA200: ALTA] ";
         else filterStr += "[EMA200: BAIXA] ";
      }
   }
   if(InpUseADXFilter && g_handleADX != INVALID_HANDLE)
   {
      double adxBuf[1];
      if(CopyBuffer(g_handleADX, 0, 0, 1, adxBuf) > 0)
      {
         if(adxBuf[0] >= InpMinADXLevel) filterStr += "[ADX: " + DoubleToString(adxBuf[0], 1) + " OK] ";
         else filterStr += "[ADX: " + DoubleToString(adxBuf[0], 1) + " LATERAL] ";
      }
   }
   ObjectSetString(0, G_PREFIX + "Txt_Diag", OBJPROP_TEXT, "Contexto: " + filterStr + g_candleContextDiag);

   string botStatusStr = g_botActive ? "STATUS: 🟢 ROBÔ LIGADO (EXECUÇÃO AUTOMÁTICA ATIVA)" : "STATUS: 🔴 ROBÔ PAUSADO PELO USUÁRIO (ORDENS BLOQUEADAS)";
   ObjectSetString(0, G_PREFIX + "Txt_BotStatus", OBJPROP_TEXT, botStatusStr);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_COLOR, g_botActive ? clrLimeGreen : clrRed);
}
"""
    code = code[:dash_start] + dash_new + "\n//+------------------------------------------------------------------+\n" + code[dash_end:]

    ea_out = os.path.join(PROJECT_DIR, "Valid_BOS_Bookmap_EA.mq5")
    with open(ea_out, "w", encoding="utf-8") as f:
        f.write(code)
    print(f"Salvo EA: {ea_out} ({len(code)} bytes)")


def build_ind():
    with open(os.path.join(PROJECT_DIR, "Valid_BOS_Pullback_Ind.mq5"), "r", encoding="utf-8") as f:
        code = f.read()

    code = code.replace("Valid_BOS_Pullback_Ind.mq5", "Valid_BOS_Bookmap_Ind.mq5")
    code = code.replace("Indicador Institucional Pro Max", "Indicador Institucional Bookmap Pro Max (COMEX GC + VT Markets)")
    code = code.replace('#define G_PREFIX "VBP_"', '#define G_PREFIX "VBP_BM_"')

    # Add Bookmap Inputs before Group 7 (Painel)
    bm_inputs = """
//+------------------------------------------------------------------+
//| PARÂMETROS INSTITUCIONAIS BOOKMAP (COMEX GC)                     |
//+------------------------------------------------------------------+
input group "=== 8. INTEGRAÇÃO INSTITUCIONAL BOOKMAP (COMEX GC) ==="
input bool                    InpUseBookmap            = true;                 // Ativar Conexão com Bookmap (COMEX Fluxo Real)?
input string                  InpBookmapHost           = "127.0.0.1";          // Host do Servidor Bookmap
input int                     InpBookmapPort           = 5555;                 // Porta do Servidor Bookmap
input bool                    InpAutoBasisTracking     = true;                 // Rastreamento Automático do Desconto (Basis)?
input double                  InpManualBasisOffset     = 20.0;                 // Desconto Manual (se Auto-Rastreamento = false)
input bool                    InpPlotBookmapLevels     = true;                 // Plotar Linhas de Liquidez do Bookmap no Gráfico?
input bool                    InpUseVwapWickSignal     = true;                 // Ativar Sinal Institucional de Absorção na VWAP?
input int                     InpMinAggressionDelta    = 50;                   // Delta Mínimo de Agressão do Bookmap (+/-)
input double                  InpMinWickPct            = 20.0;                 // Tamanho Mínimo do Pavio (% do Candle)
input int                     InpMinWallVolume         = 200;                  // Volume Mínimo para Parede de Liquidez (Lotes)
input int                     InpScalpTakeProfitPts    = 250;                  // Alvo Padrão TP1 (Scalp 50%) em Pontos
input int                     InpMinSLPoints           = 50;                   // Distância Mínima de Stop Loss (Pontos)
input color                   InpColorBookmapVWAP      = clrMagenta;           // Cor da VWAP Total do Bookmap
input color                   InpColorBookmapPOC       = clrGold;              // Cor do POC da COMEX
input color                   InpColorBookmapVAH       = C'255,140,80';        // Cor do VAH (Value Area High 70%)
input color                   InpColorBookmapVAL       = C'100,180,255';       // Cor do VAL (Value Area Low 70%)
input color                   InpColorBookmapHVN       = clrDeepSkyBlue;       // Cor do Nó de Volume (HVN)
input color                   InpColorBidWall          = clrLimeGreen;         // Cor da Parede de Compra (Bid Wall)
input color                   InpColorAskWall          = clrRed;               // Cor da Parede de Venda (Ask Wall)
"""
    code = code.replace('input group "=== 7. PAINEL ARRASTÁVEL E MINIMIZÁVEL (HUD DASHBOARD) ==="', bm_inputs + '\ninput group "=== 7. PAINEL ARRASTÁVEL E MINIMIZÁVEL (HUD DASHBOARD) ==="')

    # Globals
    bm_globals = """
//+------------------------------------------------------------------+
//| ESTRUTURA DE DADOS DO BOOKMAP EM TEMPO REAL                      |
//+------------------------------------------------------------------+
struct SBookmapData
{
   string   symbol;
   double   lastPrice;
   double   vwap;
   double   poc;
   double   vah;
   double   val;
   double   hvn;
   double   profileHigh;
   double   profileLow;
   double   bidWallPrice;
   int      bidWallVol;
   double   askWallPrice;
   int      askWallVol;
   long     delta;
   long     cvd;
   long     totalVol;
   datetime lastUpdateTime;
   bool     isConnected;
};

SBookmapData g_bmData;
double       g_smoothedBasis       = 0.0;
int          g_socketHandle        = INVALID_HANDLE;
datetime     g_lastSocketTry       = 0;
ulong        g_lastFileRead        = 0;
bool         g_signalsActive       = true;       // Controle Manual de Sinais
bool         g_bookmapActive       = true;       // Controle Manual do Bookmap
int          g_lastSignalDirection = 0;          // 1 = Compra, -1 = Venda, 0 = Neutro
double       g_lastSignalEntry     = 0.0;
double       g_lastSignalSL        = 0.0;
double       g_lastSignalTP1       = 0.0;
double       g_lastSignalTP2       = 0.0;

// OTIMIZAÇÃO DE PERFORMANCE (ULTRA-LEVE)
ulong        g_lastRedrawTick      = 0;
int          g_lastSecRem          = -1;
double       g_lastBidPrice        = 0.0;
long         g_lastDelta           = 0;
double       g_lastRenderedVwap    = 0.0;
double       g_lastRenderedPoc     = 0.0;
double       g_lastRenderedVah     = 0.0;
double       g_lastRenderedVal     = 0.0;
double       g_lastRenderedHvn     = 0.0;
double       g_lastRenderedBidWall = 0.0;
double       g_lastRenderedAskWall = 0.0;
datetime     g_lastRenderTime      = 0;
"""
    code = code.replace("SActiveTradeMonitor g_activeTrade;", "SActiveTradeMonitor g_activeTrade;\n" + bm_globals)

    # Substituir GetLineRelY e CalculateDashboardDimensions
    dim_start = code.find("int GetLineRelY(int lineIndex)")
    dim_end = code.find("bool IsTrendAligned(", dim_start)
    code = code[:dim_start] + DIMENSIONS_BLOCK + "\n" + code[dim_end:]

    # Bookmap Helper Functions before OnCalculate
    bm_funcs = """
//+------------------------------------------------------------------+
//| MÓDULO DE INTEGRAÇÃO COM BOOKMAP (COMEX FLUXO REAL)              |
//+------------------------------------------------------------------+
string ExtractJsonString(string json, string key)
{
   int pos = StringFind(json, key);
   if(pos < 0) return "";
   pos += StringLen(key);
   if(StringGetCharacter(json, pos) == 34) pos++;
   int endPos = StringFind(json, CharToString(34), pos);
   if(endPos < 0) return "";
   return StringSubstr(json, pos, endPos - pos);
}

double ExtractJsonDouble(string json, string key)
{
   int pos = StringFind(json, key);
   if(pos < 0) return 0.0;
   pos += StringLen(key);
   string sub = StringSubstr(json, pos);
   return StringToDouble(sub);
}

void ParseBookmapJson(string json)
{
   if(StringLen(json) < 10) return;

   double lp = ExtractJsonDouble(json, "\\"lp\\":");
   if(lp <= 0.0) return;

   g_bmData.lastPrice    = lp;
   g_bmData.vwap         = ExtractJsonDouble(json, "\\"vwap\\":");
   g_bmData.poc          = ExtractJsonDouble(json, "\\"poc\\":");
   g_bmData.vah          = ExtractJsonDouble(json, "\\"vah\\":");
   g_bmData.val          = ExtractJsonDouble(json, "\\"val\\":");
   g_bmData.hvn          = ExtractJsonDouble(json, "\\"hvn\\":");
   g_bmData.profileHigh  = ExtractJsonDouble(json, "\\"prh\\":");
   g_bmData.profileLow   = ExtractJsonDouble(json, "\\"prl\\":");
   g_bmData.bidWallPrice = ExtractJsonDouble(json, "\\"bwp\\":");
   g_bmData.bidWallVol   = (int)ExtractJsonDouble(json, "\\"bwv\\":");
   g_bmData.askWallPrice = ExtractJsonDouble(json, "\\"awp\\":");
   g_bmData.askWallVol   = (int)ExtractJsonDouble(json, "\\"awv\\":");
   g_bmData.delta        = (long)ExtractJsonDouble(json, "\\"del\\":");
   g_bmData.cvd          = (long)ExtractJsonDouble(json, "\\"cvd\\":");
   g_bmData.totalVol     = (long)ExtractJsonDouble(json, "\\"vol\\":");

   double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(curBid <= 0.0) curBid = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Normalização Multi-Ativo Inteligente (Ouro GC, Bitcoin BTC, etc.)
   if(curBid > 0.0 && g_bmData.lastPrice > curBid * 5.0)
   {
      double ratio = MathRound(g_bmData.lastPrice / curBid);
      if(ratio >= 8.0 && ratio <= 12.0)
      {
         g_bmData.lastPrice    /= 10.0;
         if(g_bmData.vwap > 0.0) g_bmData.vwap /= 10.0;
         g_bmData.poc          /= 10.0;
         if(g_bmData.vah > 0.0)  g_bmData.vah  /= 10.0;
         if(g_bmData.val > 0.0)  g_bmData.val  /= 10.0;
         g_bmData.hvn          /= 10.0;
         if(g_bmData.profileHigh > 0.0) g_bmData.profileHigh /= 10.0;
         if(g_bmData.profileLow > 0.0)  g_bmData.profileLow  /= 10.0;
         if(g_bmData.bidWallPrice > 0.0) g_bmData.bidWallPrice /= 10.0;
         if(g_bmData.askWallPrice > 0.0) g_bmData.askWallPrice /= 10.0;
      }
      else if(ratio >= 80.0 && ratio <= 120.0)
      {
         g_bmData.lastPrice    /= 100.0;
         if(g_bmData.vwap > 0.0) g_bmData.vwap /= 100.0;
         g_bmData.poc          /= 100.0;
         if(g_bmData.vah > 0.0)  g_bmData.vah  /= 100.0;
         if(g_bmData.val > 0.0)  g_bmData.val  /= 100.0;
         g_bmData.hvn          /= 100.0;
         if(g_bmData.profileHigh > 0.0) g_bmData.profileHigh /= 100.0;
         if(g_bmData.profileLow > 0.0)  g_bmData.profileLow  /= 100.0;
         if(g_bmData.bidWallPrice > 0.0) g_bmData.bidWallPrice /= 100.0;
         if(g_bmData.askWallPrice > 0.0) g_bmData.askWallPrice /= 100.0;
      }
   }
   else if(g_bmData.lastPrice > 10000.0 && curBid < 10000.0)
   {
      g_bmData.lastPrice /= 10.0;
      if(g_bmData.vwap > 10000.0) g_bmData.vwap /= 10.0;
      g_bmData.poc /= 10.0;
      if(g_bmData.vah > 10000.0) g_bmData.vah /= 10.0;
      if(g_bmData.val > 10000.0) g_bmData.val /= 10.0;
      g_bmData.hvn /= 10.0;
      if(g_bmData.profileHigh > 10000.0) g_bmData.profileHigh /= 10.0;
      if(g_bmData.profileLow > 10000.0)  g_bmData.profileLow  /= 10.0;
      if(g_bmData.bidWallPrice > 10000.0) g_bmData.bidWallPrice /= 10.0;
      if(g_bmData.askWallPrice > 10000.0) g_bmData.askWallPrice /= 10.0;
   }

   double areaOffset = (curBid > 10000.0) ? (curBid * 0.003) : 3.0;
   if(g_bmData.vah <= 0.0 && g_bmData.poc > 0.0) g_bmData.vah = g_bmData.poc + areaOffset;
   if(g_bmData.val <= 0.0 && g_bmData.poc > 0.0) g_bmData.val = g_bmData.poc - areaOffset;
   if(g_bmData.profileHigh <= 0.0) g_bmData.profileHigh = (g_bmData.vah > 0.0) ? (g_bmData.vah + areaOffset * 1.5) : (g_bmData.lastPrice + areaOffset * 3.0);
   if(g_bmData.profileLow <= 0.0)  g_bmData.profileLow  = (g_bmData.val > 0.0) ? (g_bmData.val - areaOffset * 1.5) : (g_bmData.lastPrice - areaOffset * 3.0);

   if(g_bmData.lastPrice > 0.0)
   {
      if(!g_bmData.isConnected)
      {
         PrintFormat("⚡ [BOOKMAP CONECTADO] COMEX: %.2f USD | Delta: %d | Poc: %.2f | VAH: %.2f | VAL: %.2f | VWAP: %.2f", g_bmData.lastPrice, g_bmData.delta, g_bmData.poc, g_bmData.vah, g_bmData.val, g_bmData.vwap);
      }
      g_bmData.lastUpdateTime = TimeCurrent();
      g_bmData.isConnected = true;

      if(curBid > 0.0)
      {
         double rawBasis = g_bmData.lastPrice - curBid;
         if(InpAutoBasisTracking)
         {
            double basisThreshold = (curBid > 10000.0) ? 1000.0 : 50.0;
            if(g_smoothedBasis == 0.0 || MathAbs(g_smoothedBasis - rawBasis) > basisThreshold)
               g_smoothedBasis = rawBasis;
            else
               g_smoothedBasis = (g_smoothedBasis * 0.95) + (rawBasis * 0.05);
         }
         else
         {
            g_smoothedBasis = InpManualBasisOffset;
         }
      }
   }
}

void UpdateBookmapData()
{
   if(!InpUseBookmap) return;

   datetime now = TimeCurrent();
   string payload = "";

   // 1. Tentar ler do Socket TCP se disponível
   if(g_socketHandle == INVALID_HANDLE && (now - g_lastSocketTry >= 3))
   {
      g_lastSocketTry = now;
      g_socketHandle = SocketCreate();
      if(g_socketHandle != INVALID_HANDLE)
      {
         if(!SocketConnect(g_socketHandle, InpBookmapHost, InpBookmapPort, 50))
         {
            SocketClose(g_socketHandle);
            g_socketHandle = INVALID_HANDLE;
         }
      }
   }

   if(g_socketHandle != INVALID_HANDLE)
   {
      if(!SocketIsConnected(g_socketHandle))
      {
         SocketClose(g_socketHandle);
         g_socketHandle = INVALID_HANDLE;
      }
      else
      {
         uint readable = SocketIsReadable(g_socketHandle);
         if(readable > 0)
         {
            uchar buffer[];
            ArrayResize(buffer, (int)readable + 1);
            int bytesRead = SocketRead(g_socketHandle, buffer, readable, 20);
            if(bytesRead > 0)
            {
               buffer[bytesRead] = 0;
               payload = CharArrayToString(buffer, 0, bytesRead, CP_UTF8);
            }
         }
      }
   }

   // 2. Fallback de Arquivo com Throttling (no máximo a cada 250ms)
   if(payload == "" && (GetTickCount64() - g_lastFileRead >= 250))
   {
      g_lastFileRead = GetTickCount64();
      int fileHandle = FileOpen("bookmap_stream.json", FILE_READ|FILE_BIN|FILE_SHARE_READ|FILE_SHARE_WRITE);
      if(fileHandle == INVALID_HANDLE)
         fileHandle = FileOpen("bookmap_stream.json", FILE_READ|FILE_BIN|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_COMMON);

      if(fileHandle != INVALID_HANDLE)
      {
         ulong sz = FileSize(fileHandle);
         if(sz > 0 && sz < 4096)
         {
            uchar buf[];
            ArrayResize(buf, (int)sz + 1);
            uint bytesRead = FileReadArray(fileHandle, buf, 0, (int)sz);
            if(bytesRead > 0)
            {
               buf[bytesRead] = 0;
               payload = CharArrayToString(buf, 0, (int)bytesRead, CP_UTF8);
            }
         }
         FileClose(fileHandle);
      }
   }

   if(payload != "")
   {
      ParseBookmapJson(payload);
   }
   else if(g_bmData.lastUpdateTime > 0 && (now - g_bmData.lastUpdateTime > 10))
   {
      g_bmData.isConnected = false;
   }
}

void DrawRayLevel(string name, datetime t1, double p1, datetime t2, double p2, color c, ENUM_LINE_STYLE st, int w, string tooltip)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);

   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}

void RenderBookmapLevels()
{
   if(!InpPlotBookmapLevels || !g_bookmapActive || !g_bmData.isConnected || g_smoothedBasis == 0.0)
   {
      ObjectDelete(0, G_PREFIX + "BM_VWAP");
      ObjectDelete(0, G_PREFIX + "BM_POC");
      ObjectDelete(0, G_PREFIX + "BM_VAH");
      ObjectDelete(0, G_PREFIX + "BM_VAL");
      ObjectDelete(0, G_PREFIX + "BM_HVN");
      ObjectDelete(0, G_PREFIX + "BM_BidWall");
      ObjectDelete(0, G_PREFIX + "BM_AskWall");
      g_lastRenderedVwap    = 0.0;
      g_lastRenderedPoc     = 0.0;
      g_lastRenderedVah     = 0.0;
      g_lastRenderedVal     = 0.0;
      g_lastRenderedHvn     = 0.0;
      g_lastRenderedBidWall = 0.0;
      g_lastRenderedAskWall = 0.0;
      return;
   }

   double mt5_vwap    = (g_bmData.vwap > 0.0) ? (g_bmData.vwap - g_smoothedBasis) : 0.0;
   double mt5_poc     = (g_bmData.poc > 0.0) ? (g_bmData.poc - g_smoothedBasis) : 0.0;
   double mt5_vah     = (g_bmData.vah > 0.0) ? (g_bmData.vah - g_smoothedBasis) : 0.0;
   double mt5_val     = (g_bmData.val > 0.0) ? (g_bmData.val - g_smoothedBasis) : 0.0;
   double mt5_hvn     = (g_bmData.hvn > 0.0) ? (g_bmData.hvn - g_smoothedBasis) : 0.0;
   double mt5_bidWall = (g_bmData.bidWallPrice > 0.0) ? (g_bmData.bidWallPrice - g_smoothedBasis) : 0.0;
   double mt5_askWall = (g_bmData.askWallPrice > 0.0) ? (g_bmData.askWallPrice - g_smoothedBasis) : 0.0;

   datetime now = TimeCurrent();
   bool levelsChanged = (MathAbs(mt5_vwap - g_lastRenderedVwap) > 0.01 ||
                         MathAbs(mt5_poc - g_lastRenderedPoc) > 0.01 ||
                         MathAbs(mt5_vah - g_lastRenderedVah) > 0.01 ||
                         MathAbs(mt5_val - g_lastRenderedVal) > 0.01 ||
                         MathAbs(mt5_hvn - g_lastRenderedHvn) > 0.01 ||
                         MathAbs(mt5_bidWall - g_lastRenderedBidWall) > 0.01 ||
                         MathAbs(mt5_askWall - g_lastRenderedAskWall) > 0.01);

   if(!levelsChanged && (now - g_lastRenderTime < 30)) return;

   g_lastRenderedVwap    = mt5_vwap;
   g_lastRenderedPoc     = mt5_poc;
   g_lastRenderedVah     = mt5_vah;
   g_lastRenderedVal     = mt5_val;
   g_lastRenderedHvn     = mt5_hvn;
   g_lastRenderedBidWall = mt5_bidWall;
   g_lastRenderedAskWall = mt5_askWall;
   g_lastRenderTime      = now;

   datetime t1 = iTime(_Symbol, _Period, MathMin(30, iBars(_Symbol, _Period) - 1));
   datetime t2 = now + PeriodSeconds(_Period) * 15;

   if(mt5_vwap > 0.0)
   {
      string vwapDesc = StringFormat("🟣 VWAP TOTAL BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.vwap, g_smoothedBasis, mt5_vwap);
      DrawRayLevel(G_PREFIX + "BM_VWAP", t1, mt5_vwap, t2, mt5_vwap, InpColorBookmapVWAP, STYLE_DASHDOT, 2, vwapDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_VWAP");

   string pocDesc = StringFormat("★ POC BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.poc, g_smoothedBasis, mt5_poc);
   DrawRayLevel(G_PREFIX + "BM_POC", t1, mt5_poc, t2, mt5_poc, InpColorBookmapPOC, STYLE_SOLID, 2, pocDesc);

   if(mt5_vah > 0.0)
   {
      string vahDesc = StringFormat("🔺 VAH 70%% BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.vah, g_smoothedBasis, mt5_vah);
      DrawRayLevel(G_PREFIX + "BM_VAH", t1, mt5_vah, t2, mt5_vah, InpColorBookmapVAH, STYLE_DASH, 1, vahDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_VAH");

   if(mt5_val > 0.0)
   {
      string valDesc = StringFormat("🔻 VAL 70%% BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.val, g_smoothedBasis, mt5_val);
      DrawRayLevel(G_PREFIX + "BM_VAL", t1, mt5_val, t2, mt5_val, InpColorBookmapVAL, STYLE_DASH, 1, valDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_VAL");

   string hvnDesc = StringFormat("✦ HVN BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.hvn, g_smoothedBasis, mt5_hvn);
   DrawRayLevel(G_PREFIX + "BM_HVN", t1, mt5_hvn, t2, mt5_hvn, InpColorBookmapHVN, STYLE_DASH, 1, hvnDesc);
   DrawRayLevel(G_PREFIX + "BM_HVN", t1, mt5_hvn, t2, mt5_hvn, InpColorBookmapHVN, STYLE_DASH, 1, hvnDesc);

   if(g_bmData.bidWallVol >= InpMinWallVolume && mt5_bidWall > 0.0)
   {
      string bwDesc = StringFormat("🛡️ PAREDE COMPRA BOOKMAP [MT5 %.2f | %d Lotes]", mt5_bidWall, g_bmData.bidWallVol);
      DrawRayLevel(G_PREFIX + "BM_BidWall", t1, mt5_bidWall, t2, mt5_bidWall, InpColorBidWall, STYLE_SOLID, 2, bwDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_BidWall");

   if(g_bmData.askWallVol >= InpMinWallVolume && mt5_askWall > 0.0)
   {
      string awDesc = StringFormat("🏰 PAREDE VENDA BOOKMAP [MT5 %.2f | %d Lotes]", mt5_askWall, g_bmData.askWallVol);
      DrawRayLevel(G_PREFIX + "BM_AskWall", t1, mt5_askWall, t2, mt5_askWall, InpColorAskWall, STYLE_SOLID, 2, awDesc);
   }
   else ObjectDelete(0, G_PREFIX + "BM_AskWall");
}

//+------------------------------------------------------------------+
//| NOVO GATILHO: ABSORÇÃO DE VWAP NO PAVIO COM DELTA (INDICADOR)    |
//+------------------------------------------------------------------+
void CheckVwapWickAbsorptionInd(datetime bTime, double bOpen, double bHigh, double bLow, double bClose, bool isLive)
{
   if(!InpUseBookmap || !g_bmData.isConnected || g_smoothedBasis == 0.0 || g_bmData.vwap <= 0.0 || !InpUseVwapWickSignal) return;
   if(!g_bookmapActive || !g_signalsActive) return;

   double mt5_vwap = g_bmData.vwap - g_smoothedBasis;
   double range = bHigh - bLow;
   if(range <= 0.0) return;

   double bodyTop    = MathMax(bOpen, bClose);
   double bodyBottom = MathMin(bOpen, bClose);
   double lowerWick  = bodyBottom - bLow;
   double upperWick  = bHigh - bodyTop;
   double pt         = _Point > 0.0 ? _Point : 0.0001;
   double tol        = 10.0 * pt;

   // 1. COMPRA: VWAP Total no pavio inferior + Forte Agressão Compradora
   if(lowerWick >= range * (InpMinWickPct / 100.0))
   {
      if(mt5_vwap >= (bLow - tol) && mt5_vwap <= (bodyBottom + tol))
      {
         if(g_bmData.delta >= InpMinAggressionDelta)
         {
            string sigId = StringFormat("%sVwapAbs_Buy_%d", G_PREFIX, (int)bTime);
            if(ObjectFind(0, sigId) < 0)
            {
               ObjectCreate(0, sigId, OBJ_ARROW_BUY, 0, bTime, bLow - (15 * pt));
               ObjectSetInteger(0, sigId, OBJPROP_COLOR, clrLimeGreen);
               ObjectSetInteger(0, sigId, OBJPROP_WIDTH, 3);
               ObjectSetString(0, sigId, OBJPROP_TOOLTIP, StringFormat("⚡ ABSORÇÃO COMPRADORA: VWAP no Pavio Inferior @ %.2f | Delta: %+d", mt5_vwap, g_bmData.delta));
            }

            g_lastSignalDirection = 1;
            g_lastSignalText      = StringFormat("⚡ COMPRA: Absorção VWAP no Pavio Inferior (Delta %+d)", g_bmData.delta);
            g_lastSignalColor     = clrLimeGreen;

            SetupNewTradePlan(1, bClose, bTime, bLow, false);

            if(isLive)
            {
               DispatchNotification(StringFormat("⚡ [BOOKMAP ABSORÇÃO] COMPRA CONFIRMADA: VWAP @ %.2f no Pavio Inferior + Forte Delta Comprador (%+d) no %s @ %.2f!",
                                    mt5_vwap, g_bmData.delta, _Symbol, bClose), InpSoundBOS, true);
            }
            return;
         }
      }
   }

   // 2. VENDA: VWAP Total no pavio superior + Forte Agressão Vendedora
   if(upperWick >= range * (InpMinWickPct / 100.0))
   {
      if(mt5_vwap >= (bodyTop - tol) && mt5_vwap <= (bHigh + tol))
      {
         if(g_bmData.delta <= -InpMinAggressionDelta)
         {
            string sigId = StringFormat("%sVwapAbs_Sell_%d", G_PREFIX, (int)bTime);
            if(ObjectFind(0, sigId) < 0)
            {
               ObjectCreate(0, sigId, OBJ_ARROW_SELL, 0, bTime, bHigh + (15 * pt));
               ObjectSetInteger(0, sigId, OBJPROP_COLOR, clrRed);
               ObjectSetInteger(0, sigId, OBJPROP_WIDTH, 3);
               ObjectSetString(0, sigId, OBJPROP_TOOLTIP, StringFormat("⚡ ABSORÇÃO VENDEDORA: VWAP no Pavio Superior @ %.2f | Delta: %+d", mt5_vwap, g_bmData.delta));
            }

            g_lastSignalDirection = -1;
            g_lastSignalText      = StringFormat("⚡ VENDA: Absorção VWAP no Pavio Superior (Delta %+d)", g_bmData.delta);
            g_lastSignalColor     = clrRed;

            SetupNewTradePlan(-1, bClose, bTime, bHigh, false);

            if(isLive)
            {
               DispatchNotification(StringFormat("⚡ [BOOKMAP ABSORÇÃO] VENDA CONFIRMADA: VWAP @ %.2f no Pavio Superior + Forte Delta Vendedor (%+d) no %s @ %.2f!",
                                    mt5_vwap, g_bmData.delta, _Symbol, bClose), InpSoundBOS, true);
            }
            return;
         }
      }
   }
}
"""
    code = code.replace("int OnCalculate(", bm_funcs + "\nint OnCalculate(")

    # Inserir verificação de g_signalsActive em DispatchNotification
    disp_snippet = """void DispatchNotification(string message, string soundFile = "", bool isLive = false)
{
   if(!isLive || !g_signalsActive) return;"""
    code = code.replace("void DispatchNotification(string message, string soundFile = \"\", bool isLive = false)\n{\n   // BLINDAGEM CONTRA TRAVAMENTO: Nunca alertar em histórico!\n   if(!isLive) return;", disp_snippet)

    # Inserir chamada de CheckVwapWickAbsorptionInd no OnCalculate
    calc_find = """      // 2.4 Scalpers em Movimentos Intermediários
      if(InpEnableScalpers)
      {
         DetectIntermediateScalps(i, time, open, high, low, close, emaArr, adxArr, isLive, drawObjects);
      }
   }"""
    calc_replace = """      // 2.4 Scalpers em Movimentos Intermediários
      if(InpEnableScalpers)
      {
         DetectIntermediateScalps(i, time, open, high, low, close, emaArr, adxArr, isLive, drawObjects);
      }

      // 5. GATILHO INSTITUCIONAL BOOKMAP: Absorção na VWAP com Agressão
      if(InpUseBookmap && InpUseVwapWickSignal)
      {
         CheckVwapWickAbsorptionInd(time[i], open[i], high[i], low[i], close[i], isLive);
      }
   }"""
    code = code.replace(calc_find, calc_replace)

    # Inserir verificação da VWAP em tempo real no DiagnoseLiveCandleAction
    diag_find = """   if(pctLower >= 45.0)
   {
      g_candleActionText  = "🔥 ABSORÇÃO COMPRADORA (Pavio " + DoubleToString(pctLower, 0) + "%)";
      g_candleActionColor = clrLimeGreen;
   }"""
    diag_replace = """   if(InpUseBookmap && g_bmData.isConnected && g_bmData.vwap > 0.0 && g_smoothedBasis != 0.0)
   {
      double mt5_vwap = g_bmData.vwap - g_smoothedBasis;
      double bTop = MathMax(cOpen, cClose);
      double bBot = MathMin(cOpen, cClose);
      double tol  = 10.0 * _Point;

      if(mt5_vwap >= (cLow - tol) && mt5_vwap <= (bBot + tol) && pctLower >= InpMinWickPct)
      {
         g_candleActionText  = StringFormat("⚡ ABSORÇÃO VWAP NO PAVIO INFERIOR (Pavio %.0f%% | Delta %+d)", pctLower, g_bmData.delta);
         g_candleActionColor = (g_bmData.delta >= InpMinAggressionDelta) ? clrLimeGreen : clrGold;
      }
      else if(mt5_vwap >= (bTop - tol) && mt5_vwap <= (cHigh + tol) && pctUpper >= InpMinWickPct)
      {
         g_candleActionText  = StringFormat("⚡ ABSORÇÃO VWAP NO PAVIO SUPERIOR (Pavio %.0f%% | Delta %+d)", pctUpper, g_bmData.delta);
         g_candleActionColor = (g_bmData.delta <= -InpMinAggressionDelta) ? clrCrimson : clrGold;
      }
      else if(pctLower >= 45.0)
      {
         g_candleActionText  = "🔥 ABSORÇÃO COMPRADORA (Pavio " + DoubleToString(pctLower, 0) + "%)";
         g_candleActionColor = clrLimeGreen;
      }
      else if(pctUpper >= 45.0)
      {
         g_candleActionText  = "🔻 ABSORÇÃO VENDEDORA (Pavio " + DoubleToString(pctUpper, 0) + "%)";
         g_candleActionColor = clrCrimson;
      }
      else if(pctBody >= 68.0 && cClose > cOpen)
      {
         g_candleActionText  = "🚀 IMPULSO COMPRADOR (Corpo " + DoubleToString(pctBody, 0) + "%)";
         g_candleActionColor = clrLime;
      }
      else if(pctBody >= 68.0 && cClose < cOpen)
      {
         g_candleActionText  = "💥 IMPULSO VENDEDOR (Corpo " + DoubleToString(pctBody, 0) + "%)";
         g_candleActionColor = clrRed;
      }
      else
      {
         g_candleActionText  = "⚖ EQUILÍBRIO / MICRO-LATERAL (Corpo " + DoubleToString(pctBody, 0) + "%)";
         g_candleActionColor = clrSilver;
      }
   }
   else if(pctLower >= 45.0)
   {
      g_candleActionText  = "🔥 ABSORÇÃO COMPRADORA (Pavio " + DoubleToString(pctLower, 0) + "%)";
      g_candleActionColor = clrLimeGreen;
   }"""
    code = code.replace(diag_find, diag_replace)

    # Atualizar SetupNewTradePlan para registrar sinal
    plan_record_ind = """   g_lastSignalDirection = dir;
   g_lastSignalEntry     = entryP;
   g_lastSignalSL        = slPrice;
   g_lastSignalTP1       = (dir == 1) ? (entryP + InpScalpTakeProfitPts * point) : (entryP - InpScalpTakeProfitPts * point);
   g_lastSignalTP2       = tpPrice;

   datetime tEnd = entryT + PeriodSeconds(_Period) * 30;"""
    code = code.replace("datetime tEnd = entryT + PeriodSeconds(_Period) * 30;", plan_record_ind)

    # Atualizar OnInit e OnDeinit com Timer ultraleve (500ms)
    code = code.replace("ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);\n   return(INIT_SUCCEEDED);", 
                        "ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);\n   EventSetMillisecondTimer(500);\n   UpdateBookmapData();\n   RenderBookmapLevels();\n   return(INIT_SUCCEEDED);")

    code = code.replace("void OnDeinit(const int reason)\n{\n   CleanObjects(G_PREFIX);\n   ChartRedraw(0);\n}",
                        "void OnDeinit(const int reason)\n{\n   EventKillTimer();\n   if(g_socketHandle != INVALID_HANDLE) { SocketClose(g_socketHandle); g_socketHandle = INVALID_HANDLE; }\n   CleanObjects(G_PREFIX);\n   ChartRedraw(0);\n}")

    # Adicionar OnTimer ultraleve com Dirty-Check
    ontimer_block_ind = """
//+------------------------------------------------------------------+
//| EVENTO DE TIMER (ATUALIZAÇÃO INSTANTÂNEA BOOKMAP & DASHBOARD)    |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateBookmapData();
   RenderBookmapLevels();

   if(InpShowDashboard)
   {
      double curPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(curPrice > 0.0)
      {
         UpdateDashboardContent(curPrice);

         // Redraw Inteligente (Dirty Check): Só redesenha se houver alteração real
         datetime barTime = iTime(_Symbol, _Period, 0);
         int secRem = (int)((barTime + PeriodSeconds(_Period)) - TimeCurrent());
         ulong nowTick = GetTickCount64();

         bool priceChanged = MathAbs(curPrice - g_lastBidPrice) > (0.5 * _Point);
         bool secChanged   = (secRem != g_lastSecRem);
         bool deltaChanged = (g_bmData.delta != g_lastDelta);

         if(priceChanged || secChanged || deltaChanged || (nowTick - g_lastRedrawTick >= 1000))
         {
            g_lastBidPrice   = curPrice;
            g_lastSecRem     = secRem;
            g_lastDelta      = g_bmData.delta;
            g_lastRedrawTick = nowTick;
            ChartRedraw(0);
         }
      }
   }
}
"""
    code = code.replace("int OnCalculate(", ontimer_block_ind + "\nint OnCalculate(")

    # Substituir OnChartEvent
    oce_start = code.find("void OnChartEvent(const int id,")
    oce_end   = code.find("//| GERENCIAMENTO DE SWINGS E ESTRUTURAS", oce_start)

    oce_new_ind = """void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(!InpShowDashboard) return;

   // 1. Cliques nos Botões do Cabeçalho
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == G_PREFIX + "Btn_Min")
      {
         g_panelMinimized = !g_panelMinimized;
         ObjectSetString(0, G_PREFIX + "Btn_Min", OBJPROP_TEXT, g_panelMinimized ? "+" : "—");
         ObjectSetInteger(0, G_PREFIX + "Dash_BG", OBJPROP_YSIZE, g_panelMinimized ? g_panelHeightMin : g_panelHeightFull);
         UpdateDashboardVisibility();
         ChartRedraw(0);
         return;
      }

      if(sparam == G_PREFIX + "Btn_Reset")
      {
         g_totalTradesWon      = 0;
         g_totalTradesLost     = 0;
         g_totalValidPullbacks = 0;
         g_totalValidBOS       = 0;
         g_totalScalps         = 0;
         g_lastSignalDirection = 0;
         g_lastSignalText      = "Estatísticas Resetadas";
         g_lastSignalColor     = clrSilver;
         g_activeTrade.Reset();
         CleanObjects(G_PREFIX + "Trade_");
         CleanObjects(G_PREFIX + "Outcome_");
         CleanObjects(G_PREFIX + "Bull_Zone_");
         CleanObjects(G_PREFIX + "Bear_Zone_");
         UpdateDashboardContent(SymbolInfoDouble(_Symbol, SYMBOL_BID));
         ChartRedraw(0);
         return;
      }

      if(sparam == G_PREFIX + "Btn_ToggleSignals")
      {
         g_signalsActive = !g_signalsActive;
         ObjectSetString(0, G_PREFIX + "Btn_ToggleSignals", OBJPROP_TEXT, g_signalsActive ? "🟢 SINAIS: ON" : "🔴 SINAIS: OFF");
         ObjectSetInteger(0, G_PREFIX + "Btn_ToggleSignals", OBJPROP_BGCOLOR, g_signalsActive ? C'20,60,35' : C'70,25,25');
         UpdateDashboardContent(SymbolInfoDouble(_Symbol, SYMBOL_BID));
         ChartRedraw(0);
         return;
      }

      if(sparam == G_PREFIX + "Btn_ToggleBM")
      {
         g_bookmapActive = !g_bookmapActive;
         ObjectSetString(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_TEXT, g_bookmapActive ? "⚡ BM: ON" : "⚡ BM: OFF");
         ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_BGCOLOR, g_bookmapActive ? C'25,50,75' : C'50,50,50');
         ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_COLOR, g_bookmapActive ? clrAqua : clrSilver);
         if(!g_bookmapActive)
         {
            ObjectDelete(0, G_PREFIX + "BM_VWAP");
            ObjectDelete(0, G_PREFIX + "BM_POC");
            ObjectDelete(0, G_PREFIX + "BM_VAH");
            ObjectDelete(0, G_PREFIX + "BM_VAL");
            ObjectDelete(0, G_PREFIX + "BM_HVN");
            ObjectDelete(0, G_PREFIX + "BM_BidWall");
            ObjectDelete(0, G_PREFIX + "BM_AskWall");
         }
         else
         {
            RenderBookmapLevels();
         }
         ChartRedraw(0);
         return;
      }
   }

   // 2. Arrastar livremente com clique e arrasto no cabeçalho
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      uint mouseState = (uint)sparam;
      bool leftDown = ((mouseState & 1) == 1);

      if(leftDown)
      {
         if(!g_isDragging)
         {
            if(mouseX >= g_panelX && mouseX <= (g_panelX + g_panelWidth) &&
               mouseY >= g_panelY && mouseY <= (g_panelY + g_headerH))
            {
               g_isDragging  = true;
               g_dragOffsetX = mouseX - g_panelX;
               g_dragOffsetY = mouseY - g_panelY;
            }
         }
         else
         {
            g_panelX = mouseX - g_dragOffsetX;
            g_panelY = mouseY - g_dragOffsetY;

            int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
            int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

            if(g_panelX < 0) g_panelX = 0;
            if(g_panelY < 0) g_panelY = 0;
            if(g_panelX + g_panelWidth > chartW) g_panelX = MathMax(0, chartW - g_panelWidth);
            if(g_panelY + g_headerH > chartH)    g_panelY = MathMax(0, chartH - g_headerH);

            RepositionDashboard();
            ChartRedraw(0);
         }
      }
      else
      {
         g_isDragging = false;
      }
   }
}
"""
    code = code[:oce_start] + oce_new_ind + "\n//+------------------------------------------------------------------+\n" + code[oce_end:]

    # Substituir bloco do Dashboard (CreateInteractiveDashboard até CreateDashLabel)
    dash_start = code.find("void CreateInteractiveDashboard()")
    dash_end   = code.find("void CreateDashLabel(", dash_start)

    dash_new_ind = """void CreateInteractiveDashboard()
{
   CalculateDashboardDimensions();

   string bgName = G_PREFIX + "Dash_BG";
   ObjectDelete(0, bgName);
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, g_panelY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, g_panelWidth);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, g_panelMinimized ? g_panelHeightMin : g_panelHeightFull);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, InpPanelBgColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, InpPanelBorderColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);

   string hdName = G_PREFIX + "Dash_Header";
   ObjectDelete(0, hdName);
   ObjectCreate(0, hdName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, hdName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, hdName, OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, hdName, OBJPROP_YDISTANCE, g_panelY);
   ObjectSetInteger(0, hdName, OBJPROP_XSIZE, g_panelWidth);
   ObjectSetInteger(0, hdName, OBJPROP_YSIZE, g_headerH);
   ObjectSetInteger(0, hdName, OBJPROP_BGCOLOR, InpPanelHeaderColor);
   ObjectSetInteger(0, hdName, OBJPROP_BORDER_COLOR, InpPanelBorderColor);
   ObjectSetInteger(0, hdName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, hdName, OBJPROP_SELECTABLE, false);

   CreateDashLabel(G_PREFIX + "Lbl_Title", "★ VALID BOS INDICADOR PRO | @viniciusburgo", 12, (g_headerH - g_fontSize - 4) / 2, clrGold, g_fontSize, true);

   int btnH = (int)MathRound(20.0 * ((double)g_fontSize / 8.0));
   int btnY = (g_headerH - btnH) / 2;

   int wSig = 100;
   int wBM  = 80;
   int wMin = 22;
   int wRes = 22;

   int curX = g_panelWidth - 6;

   curX -= wRes;
   CreateDashButton(G_PREFIX + "Btn_Reset", "R", curX, btnY, wRes, btnH, C'50,30,40', clrLightCoral, g_fontSize);

   curX -= (wMin + 4);
   CreateDashButton(G_PREFIX + "Btn_Min", g_panelMinimized ? "+" : "—", curX, btnY, wMin, btnH, C'35,48,72', clrWhite, g_fontSize);

   curX -= (wBM + 4);
   CreateDashButton(G_PREFIX + "Btn_ToggleBM", g_bookmapActive ? "⚡ BM: ON" : "⚡ BM: OFF", curX, btnY, wBM, btnH, g_bookmapActive ? C'25,50,75' : C'50,50,50', g_bookmapActive ? clrAqua : clrSilver, g_fontSize - 1);

   curX -= (wSig + 4);
   CreateDashButton(G_PREFIX + "Btn_ToggleSignals", g_signalsActive ? "🟢 SINAIS: ON" : "🔴 SINAIS: OFF", curX, btnY, wSig, btnH, g_signalsActive ? C'20,60,35' : C'70,25,25', clrWhite, g_fontSize - 1);

   CreateDashLabel(G_PREFIX + "Txt_Timer",       "⏱ Candle: --:-- | Spread: -- pts | Corretora VT Markets", 12, GetLineRelY(0), clrAqua, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_Action",      "🎯 AÇÃO IMEDIATA: [ ⚪ MONITORANDO FLUXO ]", 12, GetLineRelY(1), clrGold, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_EntrySL",     "📍 ENTRADA EXATA: --- | 🛑 STOP LOSS: ---", 12, GetLineRelY(2), clrWhite, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_TPTargets",   "🎯 ALVOS: TP1 (Scalp 50%) --- | 🚀 TP2 (Runner 50%) ---", 12, GetLineRelY(3), clrDeepSkyBlue, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_RiskRule",    "🛡️ GESTÃO: Ao atingir TP1 ➔ Stop do Runner vai pro Zero a Zero (0x0)!", 12, GetLineRelY(4), clrYellowGreen, g_fontSize - 1, false);
   CreateDashLabel(G_PREFIX + "Txt_ResSup",      "Resistência Topo: --- | Suporte Fundo: ---", 12, GetLineRelY(5), clrOrange, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BMComp",      "⚡ BOOKMAP COMEX GC: --- | 🏦 VT MARKETS SPOT: ---", 12, GetLineRelY(6), clrAqua, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMBasis",     "⚖ DIFERENÇA (BASIS): --- ➔ Níveis projetados nas velas MT5", 12, GetLineRelY(7), clrGold, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMDelta",     "📊 DELTA COMEX: --- | CVD: ---", 12, GetLineRelY(8), clrSilver, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMNodes",     "🟣 VWAP: --- | ★ POC: --- | 🔺 VAH: --- | 🔻 VAL: ---", 12, GetLineRelY(9), clrGold, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BMVPVR",      "📊 VPVR: Range [--- ⟷ ---] | Status: Aguardando...", 12, GetLineRelY(10), clrAqua, g_fontSize, true);
   CreateDashLabel(G_PREFIX + "Txt_BMWalls",     "🏰 PAREDE VENDA: --- | 🛡️ PAREDE COMPRA: ---", 12, GetLineRelY(11), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_LiveCandle",  "Vela [0]: Monitorando microestrutura...", 12, GetLineRelY(12), clrWhite, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_Diag",        "Contexto Técnico: Analisando EMA / ADX...", 12, GetLineRelY(13), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BotStatus",   "STATUS OPERACIONAL: 🟢 SINAIS ATIVOS E MONITORANDO", 12, GetLineRelY(14), clrLimeGreen, g_fontSize, true);

   UpdateDashboardVisibility();
}

void RepositionDashboard()
{
   ObjectSetInteger(0, G_PREFIX + "Dash_BG", OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, G_PREFIX + "Dash_BG", OBJPROP_YDISTANCE, g_panelY);
   ObjectSetInteger(0, G_PREFIX + "Dash_Header", OBJPROP_XDISTANCE, g_panelX);
   ObjectSetInteger(0, G_PREFIX + "Dash_Header", OBJPROP_YDISTANCE, g_panelY);

   int btnH = (int)MathRound(20.0 * ((double)g_fontSize / 8.0));
   int btnY = (g_headerH - btnH) / 2;

   int wSig = 100;
   int wBM  = 80;
   int wMin = 22;
   int wRes = 22;

   ObjectSetInteger(0, G_PREFIX + "Lbl_Title", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Lbl_Title", OBJPROP_YDISTANCE, g_panelY + (g_headerH - g_fontSize - 4) / 2);

   int curX = g_panelWidth - 6;

   curX -= wRes;
   ObjectSetInteger(0, G_PREFIX + "Btn_Reset", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_Reset", OBJPROP_YDISTANCE, g_panelY + btnY);

   curX -= (wMin + 4);
   ObjectSetInteger(0, G_PREFIX + "Btn_Min", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_Min", OBJPROP_YDISTANCE, g_panelY + btnY);

   curX -= (wBM + 4);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleBM", OBJPROP_YDISTANCE, g_panelY + btnY);

   curX -= (wSig + 4);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleSignals", OBJPROP_XDISTANCE, g_panelX + curX);
   ObjectSetInteger(0, G_PREFIX + "Btn_ToggleSignals", OBJPROP_YDISTANCE, g_panelY + btnY);

   ObjectSetInteger(0, G_PREFIX + "Txt_Timer", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Timer", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(0));

   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(1));

   ObjectSetInteger(0, G_PREFIX + "Txt_EntrySL", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_EntrySL", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(2));

   ObjectSetInteger(0, G_PREFIX + "Txt_TPTargets", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_TPTargets", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(3));

   ObjectSetInteger(0, G_PREFIX + "Txt_RiskRule", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_RiskRule", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(4));

   ObjectSetInteger(0, G_PREFIX + "Txt_ResSup", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_ResSup", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(5));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMComp", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMComp", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(6));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMBasis", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMBasis", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(7));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(8));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMNodes", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMNodes", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(9));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(10));

   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(11));

   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(12));

   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(13));

   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(14));
}

void UpdateDashboardVisibility()
{
   long hiddenFlag = g_panelMinimized ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;

   ObjectSetInteger(0, G_PREFIX + "Txt_Timer", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_EntrySL", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_TPTargets", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_RiskRule", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_ResSup", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMComp", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_TIMEFRAMES, hiddenFlag);
}

void UpdateDashboardContent(double curPrice)
{
   if(g_panelMinimized) return;

   double pt = _Point > 0.0 ? _Point : 0.0001;

   datetime barTime = iTime(_Symbol, _Period, 0);
   int secRem = (int)((barTime + PeriodSeconds(_Period)) - TimeCurrent());
   if(secRem < 0) secRem = 0;
   int mins = secRem / 60;
   int secs = secRem % 60;
   string timerStr = StringFormat("⏱ Candle: %02d:%02d | Spread: %d pts | Corretora: VT Markets", mins, secs, (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   ObjectSetString(0, G_PREFIX + "Txt_Timer", OBJPROP_TEXT, timerStr);

   string actionTxt = "";
   color actionClr = clrGold;
   string entrySLTxt = "";
   string tpTargetsTxt = "";

   if(g_activeTrade.status == TRADE_RUNNING)
   {
      string posDir = (g_activeTrade.direction == 1) ? "COMPRA" : "VENDA";
      actionTxt = StringFormat("🎯 OPERAÇÃO EM CURSO: [ %s @ %.2f ]", posDir, g_activeTrade.entryPrice);
      actionClr = (g_activeTrade.direction == 1) ? clrLimeGreen : clrRed;

      double slDistPts = MathAbs(curPrice - g_activeTrade.slPrice) / pt;
      entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts] (Protegendo Capital)", g_activeTrade.entryPrice, g_activeTrade.slPrice, slDistPts);

      double tpDistPts = MathAbs(g_activeTrade.tpPrice - curPrice) / pt;
      tpTargetsTxt = StringFormat("🎯 TAKE PROFIT ATIVO: %.2f [%.0f pts restantes para o Alvo]", g_activeTrade.tpPrice, tpDistPts);
   }
   else
   {
      if(g_lastSignalDirection == 1)
      {
         actionTxt = "🎯 SINAL RECOMENDADO: [ 🟢 FORTE COMPRA NO PULLBACK / VWAP ]";
         actionClr = clrLimeGreen;
         double estSL = (g_lastSignalSL > 0.0) ? g_lastSignalSL : (g_currentSwingLow > 0.0 ? (g_currentSwingLow - InpSLBufferPoints * pt) : (curPrice - InpMinSLPoints * pt));
         double slPts = MathAbs(curPrice - estSL) / pt;
         entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts]", curPrice, estSL, slPts);
         double tp1 = curPrice + (InpScalpTakeProfitPts * pt);
         double tp2 = curPrice + (slPts * InpRiskRewardRatio * pt);
         tpTargetsTxt = StringFormat("🎯 TP1 (Scalp 50%%): %.2f [+%d pts] | 🚀 TP2 (Runner 50%%): %.2f", tp1, InpScalpTakeProfitPts, tp2);
      }
      else if(g_lastSignalDirection == -1)
      {
         actionTxt = "🎯 SINAL RECOMENDADO: [ 🔴 FORTE VENDA NO PULLBACK / VWAP ]";
         actionClr = clrRed;
         double estSL = (g_lastSignalSL > 0.0) ? g_lastSignalSL : (g_currentSwingHigh > 0.0 ? (g_currentSwingHigh + InpSLBufferPoints * pt) : (curPrice + InpMinSLPoints * pt));
         double slPts = MathAbs(estSL - curPrice) / pt;
         entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts]", curPrice, estSL, slPts);
         double tp1 = curPrice - (InpScalpTakeProfitPts * pt);
         double tp2 = curPrice - (slPts * InpRiskRewardRatio * pt);
         tpTargetsTxt = StringFormat("🎯 TP1 (Scalp 50%%): %.2f [-%d pts] | 🚀 TP2 (Runner 50%%): %.2f", tp1, InpScalpTakeProfitPts, tp2);
      }
      else
      {
         actionTxt = "🎯 AÇÃO IMEDIATA: [ ⚪ MONITORANDO FLUXO & ABSORÇÃO NA VWAP ]";
         actionClr = clrGold;
         entrySLTxt = StringFormat("📍 PRÓX. COMPRA: Acima de %.2f (Topo) | PRÓX. VENDA: Abaixo de %.2f (Fundo)", g_currentSwingHigh, g_currentSwingLow);
         tpTargetsTxt = StringFormat("🎯 ALVOS PADRÃO: TP1 Scalp %d pts | TP2 Runner Parede de Liquidez Bookmap", InpScalpTakeProfitPts);
      }
   }

   ObjectSetString(0, G_PREFIX + "Txt_Action", OBJPROP_TEXT, actionTxt);
   ObjectSetInteger(0, G_PREFIX + "Txt_Action", OBJPROP_COLOR, actionClr);

   ObjectSetString(0, G_PREFIX + "Txt_EntrySL", OBJPROP_TEXT, entrySLTxt);
   ObjectSetString(0, G_PREFIX + "Txt_TPTargets", OBJPROP_TEXT, tpTargetsTxt);

   ObjectSetString(0, G_PREFIX + "Txt_RiskRule", OBJPROP_TEXT, "🛡️ GESTÃO DE CAPITAL: Ao atingir TP1 ➔ SL da Perna Runner é puxado para o 0x0 (Break-Even)!");

   string resStr = "Resistência (Topo MT5): " + (g_currentSwingHigh > 0.0 ? DoubleToString(g_currentSwingHigh, _Digits) : "---");
   if(g_currentSwingHigh > 0.0) resStr += StringFormat(" [%.0f pts]", (g_currentSwingHigh - curPrice) / pt);
   string supStr = "Suporte (Fundo MT5): " + (g_currentSwingLow > 0.0 ? DoubleToString(g_currentSwingLow, _Digits) : "---");
   if(g_currentSwingLow > 0.0) supStr += StringFormat(" [%.0f pts]", (curPrice - g_currentSwingLow) / pt);
   ObjectSetString(0, G_PREFIX + "Txt_ResSup", OBJPROP_TEXT, resStr + " | " + supStr);

   if(g_bmData.isConnected && g_bmData.lastPrice > 0.0)
   {
      string bmSym = (g_bmData.symbol != "" ? g_bmData.symbol : (curPrice > 10000.0 ? "BTC" : "COMEX GC"));
      string compStr = StringFormat("⚡ BOOKMAP %s: %.2f USD | 🏦 %s SPOT: %.2f USD", bmSym, g_bmData.lastPrice, _Symbol, curPrice);
      ObjectSetString(0, G_PREFIX + "Txt_BMComp", OBJPROP_TEXT, compStr);

      string basisStr = StringFormat("⚖ DIFERENÇA (BASIS): %+.2f USD ➔ Níveis Bookmap sincronizados nas velas MT5", g_smoothedBasis);
      ObjectSetString(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TEXT, basisStr);

      string deltaDiag = (g_bmData.delta > 50) ? "[COMPRADORES ATIVOS]" : ((g_bmData.delta < -50) ? "[VENDEDORES ATIVOS]" : "[FLUXO EQUILIBRADO]");
      color deltaClr = (g_bmData.delta > 0) ? clrLimeGreen : ((g_bmData.delta < 0) ? clrCrimson : clrSilver);
      string deltaStr = StringFormat("📊 DELTA BOOKMAP: %+d %s | CVD: %+d | Vol Total: %d", g_bmData.delta, deltaDiag, g_bmData.cvd, g_bmData.totalVol);
      ObjectSetString(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TEXT, deltaStr);
      ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_COLOR, deltaClr);

      double mt5_vwap = (g_bmData.vwap > 0.0) ? (g_bmData.vwap - g_smoothedBasis) : 0.0;
      double mt5_poc  = (g_bmData.poc > 0.0) ? (g_bmData.poc - g_smoothedBasis) : 0.0;
      double mt5_vah  = (g_bmData.vah > 0.0) ? (g_bmData.vah - g_smoothedBasis) : 0.0;
      double mt5_val  = (g_bmData.val > 0.0) ? (g_bmData.val - g_smoothedBasis) : 0.0;
      string nodesStr = StringFormat("🟣 VWAP: %.2f | ★ POC: %.2f | 🔺 VAH: %.2f | 🔻 VAL: %.2f", mt5_vwap, mt5_poc, mt5_vah, mt5_val);
      ObjectSetString(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TEXT, nodesStr);

      double mt5_prh = (g_bmData.profileHigh > 0.0) ? (g_bmData.profileHigh - g_smoothedBasis) : (mt5_vah > 0.0 ? mt5_vah + 5.0 : curPrice + 10.0);
      double mt5_prl = (g_bmData.profileLow > 0.0) ? (g_bmData.profileLow - g_smoothedBasis) : (mt5_val > 0.0 ? mt5_val - 5.0 : curPrice - 10.0);
      string vpvrStatus = "";
      color  vpvrClr    = clrSilver;

      if(mt5_vah > 0.0 && mt5_val > 0.0)
      {
         if(curPrice > mt5_vah)
         {
            double diffPts = (curPrice - mt5_vah) / pt;
            vpvrStatus = StringFormat("🚀 ACIMA DO VAH (+%.0f pts) | EXPANSÃO COMPRADORA", diffPts);
            vpvrClr = clrLimeGreen;
         }
         else if(curPrice < mt5_val)
         {
            double diffPts = (mt5_val - curPrice) / pt;
            vpvrStatus = StringFormat("💥 ABAIXO DO VAL (-%.0f pts) | EXPANSÃO VENDEDORA", diffPts);
            vpvrClr = clrCrimson;
         }
         else
         {
            double distPoc = (curPrice - mt5_poc) / pt;
            vpvrStatus = StringFormat("⚖ NA VALUE AREA 70%% (Afast. POC %+.0f pts)", distPoc);
            vpvrClr = clrGold;
         }
      }
      else
      {
         vpvrStatus = "Calculando distribuição VPVR...";
         vpvrClr = clrSilver;
      }

      string vpvrStr = StringFormat("📊 VPVR: Range [%.2f ⟷ %.2f] | %s", mt5_prl, mt5_prh, vpvrStatus);
      ObjectSetString(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_TEXT, vpvrStr);
      ObjectSetInteger(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_COLOR, vpvrClr);


      double mt5_bidWall = (g_bmData.bidWallPrice > 0.0) ? (g_bmData.bidWallPrice - g_smoothedBasis) : 0.0;
      double mt5_askWall = (g_bmData.askWallPrice > 0.0) ? (g_bmData.askWallPrice - g_smoothedBasis) : 0.0;
      string wallsStr = "";
      if(g_bmData.askWallVol >= InpMinWallVolume && mt5_askWall > 0.0)
         wallsStr += StringFormat("🏰 VENDA: %.2f (%d lotes) ", mt5_askWall, g_bmData.askWallVol);
      else
         wallsStr += "🏰 VENDA: Sem parede massiva ";

      if(g_bmData.bidWallVol >= InpMinWallVolume && mt5_bidWall > 0.0)
         wallsStr += StringFormat("| 🛡️ COMPRA: %.2f (%d lotes)", mt5_bidWall, g_bmData.bidWallVol);
      else
         wallsStr += "| 🛡️ COMPRA: Sem parede massiva";
      ObjectSetString(0, G_PREFIX + "Txt_BMWalls", OBJPROP_TEXT, wallsStr);
   }
   else
   {
      ObjectSetString(0, G_PREFIX + "Txt_BMComp", OBJPROP_TEXT, "⚡ BOOKMAP: Conectando na porta 5555 / arquivo stream...");
      ObjectSetString(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TEXT, "⚖ DIFERENÇA (BASIS): Aguardando primeiro tick do COMEX...");
      ObjectSetString(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TEXT, "📊 DELTA BOOKMAP: Aguardando fluxo...");
      ObjectSetString(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TEXT, "🟣 VWAP & PROFILE (POC/VAH/VAL): Aguardando Bookmap...");
      ObjectSetString(0, G_PREFIX + "Txt_BMVPVR", OBJPROP_TEXT, "📊 VPVR: Aguardando distribuição de volume Bookmap...");
      ObjectSetString(0, G_PREFIX + "Txt_BMWalls", OBJPROP_TEXT, "🏰 PAREDES DE LIQUIDEZ: Aguardando profundidade DOM...");
   }

   ObjectSetString(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_TEXT, "Vela [0]: " + g_candleActionText);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_COLOR, g_candleActionColor);

   string filterStr = "";
   if(InpUseEMATrendFilter && g_handleEMA != INVALID_HANDLE)
   {
      double emaBuf[1];
      if(CopyBuffer(g_handleEMA, 0, 0, 1, emaBuf) > 0)
      {
         if(curPrice > emaBuf[0]) filterStr += "[EMA200: ALTA] ";
         else filterStr += "[EMA200: BAIXA] ";
      }
   }
   if(InpUseADXFilter && g_handleADX != INVALID_HANDLE)
   {
      double adxBuf[1];
      if(CopyBuffer(g_handleADX, 0, 0, 1, adxBuf) > 0)
      {
         if(adxBuf[0] >= InpMinADXLevel) filterStr += "[ADX: " + DoubleToString(adxBuf[0], 1) + " OK] ";
         else filterStr += "[ADX: " + DoubleToString(adxBuf[0], 1) + " LATERAL] ";
      }
   }
   ObjectSetString(0, G_PREFIX + "Txt_Diag", OBJPROP_TEXT, "Contexto: " + filterStr + g_candleContextDiag);

   string botStatusStr = g_signalsActive ? "STATUS: 🟢 SINAIS ATIVOS E MONITORANDO COM ALERTAS" : "STATUS: 🔴 SINAIS PAUSADOS PELO USUÁRIO (SILENCIADO)";
   ObjectSetString(0, G_PREFIX + "Txt_BotStatus", OBJPROP_TEXT, botStatusStr);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_COLOR, g_signalsActive ? clrLimeGreen : clrRed);
}
"""
    code = code[:dash_start] + dash_new_ind + "\n//+------------------------------------------------------------------+\n" + code[dash_end:]

    ind_out = os.path.join(PROJECT_DIR, "Valid_BOS_Bookmap_Ind.mq5")
    with open(ind_out, "w", encoding="utf-8") as f:
        f.write(code)
    print(f"Salvo Indicador: {ind_out} ({len(code)} bytes)")


def compile_and_verify():
    print("Sincronizando com pastas do MT5...")
    src_ea = os.path.join(PROJECT_DIR, "Valid_BOS_Bookmap_EA.mq5")
    dst_ea = os.path.join(MT5_TERM_DIR, "Experts", "Valid_BOS_Pullback", "Valid_BOS_Bookmap_EA.mq5")
    shutil.copy2(src_ea, dst_ea)

    src_ind = os.path.join(PROJECT_DIR, "Valid_BOS_Bookmap_Ind.mq5")
    dst_ind = os.path.join(MT5_TERM_DIR, "Indicators", "Valid_BOS_Pullback", "Valid_BOS_Bookmap_Ind.mq5")
    shutil.copy2(src_ind, dst_ind)

    print("Compilando Valid_BOS_Bookmap_EA.mq5...")
    subprocess.run([METAEDITOR, f"/compile:{dst_ea}", "/log"], capture_output=True, text=True)

    ea_log = dst_ea.replace(".mq5", ".log")
    if os.path.exists(ea_log):
        with open(ea_log, "r", encoding="utf-16le", errors="ignore") as f:
            log_content = f.read()
        print("--- EA LOG ---")
        lines = [l for l in log_content.splitlines() if "error" in l.lower() or "warning" in l.lower() or "result" in l.lower()]
        print("\n".join(lines[-10:]) if lines else "Sem erros!")

    print("Compilando Valid_BOS_Bookmap_Ind.mq5...")
    subprocess.run([METAEDITOR, f"/compile:{dst_ind}", "/log"], capture_output=True, text=True)

    ind_log = dst_ind.replace(".mq5", ".log")
    if os.path.exists(ind_log):
        with open(ind_log, "r", encoding="utf-16le", errors="ignore") as f:
            log_content = f.read()
        print("--- IND LOG ---")
        lines = [l for l in log_content.splitlines() if "error" in l.lower() or "warning" in l.lower() or "result" in l.lower()]
        print("\n".join(lines[-10:]) if lines else "Sem erros!")

    # Copiar .ex5 de volta
    dst_ea_ex5 = dst_ea.replace(".mq5", ".ex5")
    dst_ind_ex5 = dst_ind.replace(".mq5", ".ex5")
    if os.path.exists(dst_ea_ex5):
        shutil.copy2(dst_ea_ex5, src_ea.replace(".mq5", ".ex5"))
        print(f"EX5 do EA gerado e copiado com sucesso! ({os.path.getsize(dst_ea_ex5)} bytes)")
    else:
        print("ERRO: EX5 do EA não foi gerado.")

    if os.path.exists(dst_ind_ex5):
        shutil.copy2(dst_ind_ex5, src_ind.replace(".mq5", ".ex5"))
        print(f"EX5 do Indicador gerado e copiado com sucesso! ({os.path.getsize(dst_ind_ex5)} bytes)")
    else:
        print("ERRO: EX5 do Indicador não foi gerado.")

if __name__ == "__main__":
    build_ea()
    build_ind()
    compile_and_verify()
