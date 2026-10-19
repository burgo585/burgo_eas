# -*- coding: utf-8 -*-
"""
Gerador Limpo dos Novos Módulos Bookmap Pro:
- Valid_BOS_Bookmap_EA.mq5
- Valid_BOS_Bookmap_Ind.mq5
"""

import os
import shutil
import subprocess

PROJECT_DIR = r"c:\Robo Virada de Delta\Valid_BOS_Pullback"
MT5_TERM_DIR = r"C:\Users\Vini_Burgo\AppData\Roaming\MetaQuotes\Terminal\9AF8328437A6A393B2016FC9156E6753\MQL5"
COMPILER_PATH = r"C:\Program Files\MetaTrader 5 - Copia\metaeditor64.exe"

def build_ea():
    with open(os.path.join(PROJECT_DIR, "Valid_BOS_Pullback_EA.mq5"), "r", encoding="utf-8") as f:
        lines = f.readlines()

    out = []
    i = 0
    while i < len(lines):
        line = lines[i]

        # 1. Cabeçalho
        if "Valid_BOS_Pullback_EA.mq5" in line:
            line = line.replace("Valid_BOS_Pullback_EA.mq5", "Valid_BOS_Bookmap_EA.mq5")
        if "Robô Quantitativo Institucional Pro Max" in line:
            line = line.replace("Robô Quantitativo Institucional Pro Max", "Robô Institucional Bookmap Pro Max (COMEX GC)")
        if '#define G_PREFIX "VBPEA_"' in line:
            line = '#define G_PREFIX "VBPEA_BM_"\n'

        # 2. Inserção de Novos Inputs após o Painel
        if "input color                   InpPanelBorderColor" in line:
            out.append(line)
            out.append("\n//+------------------------------------------------------------------+\n")
            out.append("//| PARÂMETROS INSTITUCIONAIS BOOKMAP & EXECUÇÃO DUAL-TRANCHE        |\n")
            out.append("//+------------------------------------------------------------------+\n")
            out.append('input group "=== 10. INTEGRAÇÃO INSTITUCIONAL BOOKMAP (COMEX GC) ==="\n')
            out.append('input bool                    InpUseBookmap            = true;                 // Ativar Conexão com Bookmap (COMEX Fluxo Real)?\n')
            out.append('input string                  InpBookmapHost           = "127.0.0.1";          // Host do Servidor Bookmap\n')
            out.append('input int                     InpBookmapPort           = 5555;                 // Porta do Servidor Bookmap\n')
            out.append('input bool                    InpAutoBasisTracking     = true;                 // Rastreamento Automático do Desconto (Basis)?\n')
            out.append('input double                  InpManualBasisOffset     = 20.0;                 // Desconto Manual (se Auto-Rastreamento = false)\n')
            out.append('input bool                    InpPlotBookmapLevels     = true;                 // Plotar Linhas de Liquidez do Bookmap no Gráfico?\n')
            out.append('input bool                    InpFilterTradesByDelta   = true;                 // Filtrar Entradas por Delta Institucional do Bookmap?\n')
            out.append('input int                     InpMinWallVolume         = 200;                  // Volume Mínimo para Parede de Liquidez (Lotes)\n')
            out.append('input color                   InpColorBookmapPOC       = clrGold;              // Cor do POC da COMEX\n')
            out.append('input color                   InpColorBookmapHVN       = clrDeepSkyBlue;       // Cor do Nó de Volume (HVN)\n')
            out.append('input color                   InpColorBidWall          = clrLimeGreen;         // Cor da Parede de Compra (Bid Wall)\n')
            out.append('input color                   InpColorAskWall          = clrRed;               // Cor da Parede de Venda (Ask Wall)\n')
            out.append('\ninput group "=== 11. EXECUÇÃO DE 2 PERNAS (SCALP PRECISO + SURFAR TENDÊNCIA) ==="\n')
            out.append('input bool                    InpUseDualTranche        = true;                 // Ativar Operação Dividida (Scalp + Runner)?\n')
            out.append('input int                     InpScalpSplitPercent     = 50;                   // % do Lote para a Perna de Scalp (ex: 50%)\n')
            out.append('input int                     InpScalpTakeProfitPts    = 250;                  // Take Profit da Perna de Scalp em Pontos (ex: 25 pips)\n')
            out.append('input bool                    InpAutoBreakEvenOnScalpTP= true;                 // Mover Perna Runner para Zero a Zero quando Scalp bater Take?\n')
            out.append('input int                     InpRunnerTrailingPts     = 300;                  // Trailing Stop da Perna Runner (Pontos)\n')
            out.append('input bool                    InpTargetRunnerToWall    = true;                 // Mirar Take da Perna Runner na Parede de Liquidez do Bookmap?\n')
            i += 1
            continue

        # 3. Variáveis Globais do Bookmap
        if "SActiveTradeMonitor g_activeTrade;" in line:
            out.append(line)
            out.append("""
//+------------------------------------------------------------------+
//| ESTRUTURA DE DADOS DO BOOKMAP EM TEMPO REAL                      |
//+------------------------------------------------------------------+
struct SBookmapData
{
   string   symbol;
   double   lastPrice;
   double   poc;
   double   hvn;
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
double       g_smoothedBasis  = 0.0;
int          g_socketHandle   = INVALID_HANDLE;
datetime     g_lastSocketTry  = 0;
datetime     g_lastFileRead   = 0;
""")
            i += 1
            continue

        # 4. Inserção de Funções do Bookmap antes de ExecuteRealOrder
        if "void ExecuteRealOrder(ENUM_ORDER_TYPE orderType, double entryRefPrice, double stopRefPrice, bool isScalp)" in line:
            out.append("""
//+------------------------------------------------------------------+
//| MÓDULO DE INTEGRAÇÃO COM BOOKMAP (COMEX FLUXO REAL)              |
//+------------------------------------------------------------------+
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
   g_bmData.lastPrice    = ExtractJsonDouble(json, "\\"lp\\":");
   g_bmData.poc          = ExtractJsonDouble(json, "\\"poc\\":");
   g_bmData.hvn          = ExtractJsonDouble(json, "\\"hvn\\":");
   g_bmData.bidWallPrice = ExtractJsonDouble(json, "\\"bwp\\":");
   g_bmData.bidWallVol   = (int)ExtractJsonDouble(json, "\\"bwv\\":");
   g_bmData.askWallPrice = ExtractJsonDouble(json, "\\"awp\\":");
   g_bmData.askWallVol   = (int)ExtractJsonDouble(json, "\\"awv\\":");
   g_bmData.delta        = (long)ExtractJsonDouble(json, "\\"del\\":");
   g_bmData.cvd          = (long)ExtractJsonDouble(json, "\\"cvd\\":");
   g_bmData.totalVol     = (long)ExtractJsonDouble(json, "\\"vol\\":");

   if(g_bmData.lastPrice > 0.0)
   {
      g_bmData.lastUpdateTime = TimeCurrent();
      g_bmData.isConnected = true;

      double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(curBid > 0.0)
      {
         double rawBasis = g_bmData.lastPrice - curBid;
         if(InpAutoBasisTracking)
         {
            if(g_smoothedBasis == 0.0)
               g_smoothedBasis = rawBasis;
            else
               g_smoothedBasis = (g_smoothedBasis * 0.90) + (rawBasis * 0.10);
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
      uint readable = SocketIsReadable(g_socketHandle);
      if(readable > 0)
      {
         uchar buffer[];
         ArrayResize(buffer, (int)readable + 1);
         int bytesRead = SocketRead(g_socketHandle, buffer, readable, 20);
         if(bytesRead > 0)
         {
            buffer[bytesRead] = 0;
            payload = CharArrayToString(buffer, 0, bytesRead);
         }
      }
   }

   if(payload == "" && (GetTickCount() - g_lastFileRead >= 100))
   {
      g_lastFileRead = GetTickCount();
      int fileHandle = FileOpen("bookmap_stream.json", FILE_READ|FILE_TXT|FILE_SHARE_READ|FILE_ANSI);
      if(fileHandle != INVALID_HANDLE)
      {
         payload = FileReadString(fileHandle);
         FileClose(fileHandle);
      }
   }

   if(payload != "")
   {
      ParseBookmapJson(payload);
   }
   else if(now - g_bmData.lastUpdateTime > 5)
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
   if(!InpPlotBookmapLevels || !g_bmData.isConnected || g_smoothedBasis == 0.0) return;

   double mt5_poc     = g_bmData.poc - g_smoothedBasis;
   double mt5_hvn     = g_bmData.hvn - g_smoothedBasis;
   double mt5_bidWall = g_bmData.bidWallPrice - g_smoothedBasis;
   double mt5_askWall = g_bmData.askWallPrice - g_smoothedBasis;

   datetime t1 = iTime(_Symbol, _Period, 25);
   datetime t2 = TimeCurrent() + PeriodSeconds(_Period) * 15;

   DrawRayLevel(G_PREFIX + "BM_POC", t1, mt5_poc, t2, mt5_poc, InpColorBookmapPOC, STYLE_SOLID, 2, "★ POC COMEX: " + DoubleToString(g_bmData.poc, 2));
   DrawRayLevel(G_PREFIX + "BM_HVN", t1, mt5_hvn, t2, mt5_hvn, InpColorBookmapHVN, STYLE_DASH, 1, "✦ HVN COMEX: " + DoubleToString(g_bmData.hvn, 2));

   if(g_bmData.bidWallVol >= InpMinWallVolume && mt5_bidWall > 0.0)
      DrawRayLevel(G_PREFIX + "BM_BidWall", t1, mt5_bidWall, t2, mt5_bidWall, InpColorBidWall, STYLE_SOLID, 2, "🛡️ PAREDE COMPRA COMEX: " + IntegerToString(g_bmData.bidWallVol) + " Lotes");
   else ObjectDelete(0, G_PREFIX + "BM_BidWall");

   if(g_bmData.askWallVol >= InpMinWallVolume && mt5_askWall > 0.0)
      DrawRayLevel(G_PREFIX + "BM_AskWall", t1, mt5_askWall, t2, mt5_askWall, InpColorAskWall, STYLE_SOLID, 2, "🏰 PAREDE VENDA COMEX: " + IntegerToString(g_bmData.askWallVol) + " Lotes");
   else ObjectDelete(0, G_PREFIX + "BM_AskWall");
}
\n""")

        # 5. Dual-Tranche na Execução de Ordens
        if "if(orderType == ORDER_TYPE_BUY)\n" in line and "m_trade.Buy(lot" in lines[min(len(lines)-1, i+2)]:
            out.append("""   // FILTRO BOOKMAP: Verifica se o Delta institucional apoia a operação
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

      double tpScalp = (orderType == ORDER_TYPE_BUY) ? (ask + InpScalpTakeProfitPts * point) : (bid - InpScalpTakeProfitPts * point);
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

      m_trade.SetExpertMagicNumber(InpMagicNumber);
      if(orderType == ORDER_TYPE_BUY)
         m_trade.Buy(lotScalp, _Symbol, ask, slPrice, tpScalp, "VBP_Scalp_Tranche");
      else
         m_trade.Sell(lotScalp, _Symbol, bid, slPrice, tpScalp, "VBP_Scalp_Tranche");

      m_trade.SetExpertMagicNumber(InpMagicNumber + 1);
      if(orderType == ORDER_TYPE_BUY)
         m_trade.Buy(lotRunner, _Symbol, ask, slPrice, tpRunner, "VBP_Runner_Tranche");
      else
         m_trade.Sell(lotRunner, _Symbol, bid, slPrice, tpRunner, "VBP_Runner_Tranche");

      m_trade.SetExpertMagicNumber(InpMagicNumber);
      return;
   }
""")
            out.append(line)
            i += 1
            continue

        # 6. Break-Even Automático na Perna Runner
        if "void ManageOpenPositions()" in line:
            out.append(line)
            out.append(lines[i+1]) # {
            out.append("""   // BREAK-EVEN AUTOMÁTICO NA PERNA RUNNER APÓS SCALP BATER TAKE
   if(InpUseDualTranche && InpAutoBreakEvenOnScalpTP)
   {
      bool scalpIsOpen = false;
      ulong runnerTicket = 0;
      double runnerOpenPrice = 0.0;
      ENUM_POSITION_TYPE runnerType = POSITION_TYPE_BUY;

      for(int pIdx = PositionsTotal() - 1; pIdx >= 0; pIdx--)
      {
         if(m_pos.SelectByIndex(pIdx))
         {
            if(m_pos.Symbol() == _Symbol)
            {
               if(m_pos.Magic() == InpMagicNumber)
                  scalpIsOpen = true;
               else if(m_pos.Magic() == InpMagicNumber + 1)
               {
                  runnerTicket = m_pos.Ticket();
                  runnerOpenPrice = m_pos.PriceOpen();
                  runnerType = m_pos.PositionType();
               }
            }
         }
      }

      if(!scalpIsOpen && runnerTicket > 0)
      {
         if(m_pos.SelectByTicket(runnerTicket))
         {
            double curSL = m_pos.StopLoss();
            double pt = _Point > 0.0 ? _Point : 0.0001;
            if(runnerType == POSITION_TYPE_BUY)
            {
               double bePrice = runnerOpenPrice + (InpBreakEvenExtraPoints * pt);
               if(curSL < bePrice)
                  m_trade.PositionModify(runnerTicket, bePrice, m_pos.TakeProfit());
            }
            else
            {
               double bePrice = runnerOpenPrice - (InpBreakEvenExtraPoints * pt);
               if(curSL > bePrice || curSL == 0.0)
                  m_trade.PositionModify(runnerTicket, bePrice, m_pos.TakeProfit());
            }
         }
      }
   }
""")
            i += 2
            continue

        # 7. Chamada de Leitura no OnTick
        if "CheckDailyCircuitBreaker();" in line and "void OnTick()" in lines[max(0, i-5)]:
            out.append("   UpdateBookmapData();\n   RenderBookmapLevels();\n")
            out.append(line)
            i += 1
            continue

        # 8. Fechar Socket no OnDeinit
        if "CleanObjects(G_PREFIX);" in line and "void OnDeinit" in lines[max(0, i-5)]:
            out.append("   if(g_socketHandle != INVALID_HANDLE) { SocketClose(g_socketHandle); g_socketHandle = INVALID_HANDLE; }\n")
            out.append(line)
            i += 1
            continue

        # 9. Dashboard (16 Linhas e Labels)
        if "int totalLines = 13;" in line:
            line = "   int totalLines = 16;\n"

        if 'CreateDashLabel(G_PREFIX + "Lbl_L12_T"' in line:
            out.append(line)
            out.append(lines[i+1])
            out.append("""   CreateDashLabel(G_PREFIX + "Lbl_L13_T", "STATUS BOOKMAP (COMEX):", 12, g_lineYStart + (12 * g_lineH), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Lbl_L13_V", "CONECTANDO...", 160, g_lineYStart + (12 * g_lineH), clrYellow, g_fontSize, true);

   CreateDashLabel(G_PREFIX + "Lbl_L14_T", "DESCONTO BASIS / DELTA:", 12, g_lineYStart + (13 * g_lineH), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Lbl_L14_V", "Rastreando...", 160, g_lineYStart + (13 * g_lineH), clrWhite, g_fontSize, true);

   CreateDashLabel(G_PREFIX + "Lbl_L15_T", "PAREDES LIQUIDEZ COMEX:", 12, g_lineYStart + (14 * g_lineH), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Lbl_L15_V", "Mapeando...", 160, g_lineYStart + (14 * g_lineH), clrAqua, g_fontSize, true);
""")
            i += 2
            continue

        if 'UpdateDashText(G_PREFIX + "Lbl_L12_V"' in line:
            out.append(line)
            out.append("""   // Linhas Bookmap
   string bmStatus = g_bmData.isConnected ? "🟢 ONLINE (COMEX GC)" : "🔴 OFFLINE / AGUARDANDO";
   color  bmColor  = g_bmData.isConnected ? clrLimeGreen : clrCrimson;
   UpdateDashText(G_PREFIX + "Lbl_L13_V", bmStatus, bmColor);

   string basisText = StringFormat("Offset: -$%.2f | Delta: %+d", g_smoothedBasis, g_bmData.delta);
   UpdateDashText(G_PREFIX + "Lbl_L14_V", basisText, clrGold);

   string wallsText = StringFormat("Bid: %d Lotes | Ask: %d Lotes", g_bmData.bidWallVol, g_bmData.askWallVol);
   UpdateDashText(G_PREFIX + "Lbl_L15_V", wallsText, clrDeepSkyBlue);
""")
            i += 1
            continue

        out.append(line)
        i += 1

    content = "".join(out)
    target = os.path.join(PROJECT_DIR, "Valid_BOS_Bookmap_EA.mq5")
    with open(target, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[OK] Gerado {target} ({len(content)} bytes)")
    return target

def build_ind():
    with open(os.path.join(PROJECT_DIR, "Valid_BOS_Pullback_Ind.mq5"), "r", encoding="utf-8") as f:
        lines = f.readlines()

    out = []
    i = 0
    while i < len(lines):
        line = lines[i]

        if "Valid_BOS_Pullback_Ind.mq5" in line:
            line = line.replace("Valid_BOS_Pullback_Ind.mq5", "Valid_BOS_Bookmap_Ind.mq5")
        if "Indicador Quantitativo Institucional Pro Max" in line:
            line = line.replace("Indicador Quantitativo Institucional Pro Max", "Indicador Institucional com Nós de Volume Bookmap (COMEX GC)")
        if '#define G_PREFIX "VBP_"' in line:
            line = '#define G_PREFIX "VBP_BM_"\n'

        if "input color                   InpPanelBorderColor" in line:
            out.append(line)
            out.append("\n//+------------------------------------------------------------------+\n")
            out.append("//| PARÂMETROS INSTITUCIONAIS BOOKMAP (NÓS DE VOLUME & LIQUIDEZ)     |\n")
            out.append("//+------------------------------------------------------------------+\n")
            out.append('input group "=== 8. INTEGRAÇÃO INSTITUCIONAL BOOKMAP (COMEX GC) ==="\n')
            out.append('input bool                    InpUseBookmap            = true;                 // Ativar Conexão com Bookmap (COMEX Fluxo Real)?\n')
            out.append('input string                  InpBookmapHost           = "127.0.0.1";          // Host do Servidor Bookmap\n')
            out.append('input int                     InpBookmapPort           = 5555;                 // Porta do Servidor Bookmap\n')
            out.append('input bool                    InpAutoBasisTracking     = true;                 // Rastreamento Automático do Desconto (Basis)?\n')
            out.append('input double                  InpManualBasisOffset     = 20.0;                 // Desconto Manual (se Auto-Rastreamento = false)\n')
            out.append('input bool                    InpPlotBookmapLevels     = true;                 // Plotar Linhas de Liquidez do Bookmap no Gráfico?\n')
            out.append('input int                     InpMinWallVolume         = 200;                  // Volume Mínimo para Parede de Liquidez (Lotes)\n')
            out.append('input color                   InpColorBookmapPOC       = clrGold;              // Cor do POC da COMEX\n')
            out.append('input color                   InpColorBookmapHVN       = clrDeepSkyBlue;       // Cor do Nó de Volume (HVN)\n')
            out.append('input color                   InpColorBidWall          = clrLimeGreen;         // Cor da Parede de Compra (Bid Wall)\n')
            out.append('input color                   InpColorAskWall          = clrRed;               // Cor da Parede de Venda (Ask Wall)\n')
            i += 1
            continue

        if "SActiveTradeMonitor g_activeTrade;" in line:
            out.append(line)
            out.append("""
//+------------------------------------------------------------------+
//| ESTRUTURA DE DADOS DO BOOKMAP EM TEMPO REAL                      |
//+------------------------------------------------------------------+
struct SBookmapData
{
   string   symbol;
   double   lastPrice;
   double   poc;
   double   hvn;
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
double       g_smoothedBasis  = 0.0;
int          g_socketHandle   = INVALID_HANDLE;
datetime     g_lastSocketTry  = 0;
datetime     g_lastFileRead   = 0;
""")
            i += 1
            continue

        if "void DrawZoneBox(string name," in line:
            out.append("""
//+------------------------------------------------------------------+
//| MÓDULO DE INTEGRAÇÃO COM BOOKMAP (COMEX FLUXO REAL)              |
//+------------------------------------------------------------------+
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
   g_bmData.lastPrice    = ExtractJsonDouble(json, "\\"lp\\":");
   g_bmData.poc          = ExtractJsonDouble(json, "\\"poc\\":");
   g_bmData.hvn          = ExtractJsonDouble(json, "\\"hvn\\":");
   g_bmData.bidWallPrice = ExtractJsonDouble(json, "\\"bwp\\":");
   g_bmData.bidWallVol   = (int)ExtractJsonDouble(json, "\\"bwv\\":");
   g_bmData.askWallPrice = ExtractJsonDouble(json, "\\"awp\\":");
   g_bmData.askWallVol   = (int)ExtractJsonDouble(json, "\\"awv\\":");
   g_bmData.delta        = (long)ExtractJsonDouble(json, "\\"del\\":");
   g_bmData.cvd          = (long)ExtractJsonDouble(json, "\\"cvd\\":");
   g_bmData.totalVol     = (long)ExtractJsonDouble(json, "\\"vol\\":");

   if(g_bmData.lastPrice > 0.0)
   {
      g_bmData.lastUpdateTime = TimeCurrent();
      g_bmData.isConnected = true;

      double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(curBid > 0.0)
      {
         double rawBasis = g_bmData.lastPrice - curBid;
         if(InpAutoBasisTracking)
         {
            if(g_smoothedBasis == 0.0)
               g_smoothedBasis = rawBasis;
            else
               g_smoothedBasis = (g_smoothedBasis * 0.90) + (rawBasis * 0.10);
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
      uint readable = SocketIsReadable(g_socketHandle);
      if(readable > 0)
      {
         uchar buffer[];
         ArrayResize(buffer, (int)readable + 1);
         int bytesRead = SocketRead(g_socketHandle, buffer, readable, 20);
         if(bytesRead > 0)
         {
            buffer[bytesRead] = 0;
            payload = CharArrayToString(buffer, 0, bytesRead);
         }
      }
   }

   if(payload == "" && (GetTickCount() - g_lastFileRead >= 100))
   {
      g_lastFileRead = GetTickCount();
      int fileHandle = FileOpen("bookmap_stream.json", FILE_READ|FILE_TXT|FILE_SHARE_READ|FILE_ANSI);
      if(fileHandle != INVALID_HANDLE)
      {
         payload = FileReadString(fileHandle);
         FileClose(fileHandle);
      }
   }

   if(payload != "")
   {
      ParseBookmapJson(payload);
   }
   else if(now - g_bmData.lastUpdateTime > 5)
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
   if(!InpPlotBookmapLevels || !g_bmData.isConnected || g_smoothedBasis == 0.0) return;

   double mt5_poc     = g_bmData.poc - g_smoothedBasis;
   double mt5_hvn     = g_bmData.hvn - g_smoothedBasis;
   double mt5_bidWall = g_bmData.bidWallPrice - g_smoothedBasis;
   double mt5_askWall = g_bmData.askWallPrice - g_smoothedBasis;

   datetime t1 = iTime(_Symbol, _Period, 25);
   datetime t2 = TimeCurrent() + PeriodSeconds(_Period) * 15;

   DrawRayLevel(G_PREFIX + "BM_POC", t1, mt5_poc, t2, mt5_poc, InpColorBookmapPOC, STYLE_SOLID, 2, "★ POC COMEX: " + DoubleToString(g_bmData.poc, 2));
   DrawRayLevel(G_PREFIX + "BM_HVN", t1, mt5_hvn, t2, mt5_hvn, InpColorBookmapHVN, STYLE_DASH, 1, "✦ HVN COMEX: " + DoubleToString(g_bmData.hvn, 2));

   if(g_bmData.bidWallVol >= InpMinWallVolume && mt5_bidWall > 0.0)
      DrawRayLevel(G_PREFIX + "BM_BidWall", t1, mt5_bidWall, t2, mt5_bidWall, InpColorBidWall, STYLE_SOLID, 2, "🛡️ PAREDE COMPRA COMEX: " + IntegerToString(g_bmData.bidWallVol) + " Lotes");
   else ObjectDelete(0, G_PREFIX + "BM_BidWall");

   if(g_bmData.askWallVol >= InpMinWallVolume && mt5_askWall > 0.0)
      DrawRayLevel(G_PREFIX + "BM_AskWall", t1, mt5_askWall, t2, mt5_askWall, InpColorAskWall, STYLE_SOLID, 2, "🏰 PAREDE VENDA COMEX: " + IntegerToString(g_bmData.askWallVol) + " Lotes");
   else ObjectDelete(0, G_PREFIX + "BM_AskWall");
}
\n""")
            out.append(line)
            i += 1
            continue

        if "if(InpShowActiveLevels)\n" in line and "RenderActiveLevels();" in lines[min(len(lines)-1, i+1)]:
            out.append("   UpdateBookmapData();\n   RenderBookmapLevels();\n")
            out.append(line)
            i += 1
            continue

        if "CleanObjects(G_PREFIX);" in line and "void OnDeinit" in lines[max(0, i-5)]:
            out.append("   if(g_socketHandle != INVALID_HANDLE) { SocketClose(g_socketHandle); g_socketHandle = INVALID_HANDLE; }\n")
            out.append(line)
            i += 1
            continue

        if "int totalLines = 13;" in line:
            line = "   int totalLines = 16;\n"

        if 'CreateDashLabel(G_PREFIX + "Lbl_L12_T"' in line:
            out.append(line)
            out.append(lines[i+1])
            out.append("""   CreateDashLabel(G_PREFIX + "Lbl_L13_T", "STATUS BOOKMAP (COMEX):", 12, g_lineYStart + (12 * g_lineH), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Lbl_L13_V", "CONECTANDO...", 160, g_lineYStart + (12 * g_lineH), clrYellow, g_fontSize, true);

   CreateDashLabel(G_PREFIX + "Lbl_L14_T", "DESCONTO BASIS / DELTA:", 12, g_lineYStart + (13 * g_lineH), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Lbl_L14_V", "Rastreando...", 160, g_lineYStart + (13 * g_lineH), clrWhite, g_fontSize, true);

   CreateDashLabel(G_PREFIX + "Lbl_L15_T", "PAREDES LIQUIDEZ COMEX:", 12, g_lineYStart + (14 * g_lineH), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Lbl_L15_V", "Mapeando...", 160, g_lineYStart + (14 * g_lineH), clrAqua, g_fontSize, true);
""")
            i += 2
            continue

        if 'UpdateDashText(G_PREFIX + "Lbl_L12_V"' in line:
            out.append(line)
            out.append("""   // Linhas Bookmap
   string bmStatus = g_bmData.isConnected ? "🟢 ONLINE (COMEX GC)" : "🔴 OFFLINE / AGUARDANDO";
   color  bmColor  = g_bmData.isConnected ? clrLimeGreen : clrCrimson;
   UpdateDashText(G_PREFIX + "Lbl_L13_V", bmStatus, bmColor);

   string basisText = StringFormat("Offset: -$%.2f | Delta: %+d", g_smoothedBasis, g_bmData.delta);
   UpdateDashText(G_PREFIX + "Lbl_L14_V", basisText, clrGold);

   string wallsText = StringFormat("Bid: %d Lotes | Ask: %d Lotes", g_bmData.bidWallVol, g_bmData.askWallVol);
   UpdateDashText(G_PREFIX + "Lbl_L15_V", wallsText, clrDeepSkyBlue);
""")
            i += 1
            continue

        out.append(line)
        i += 1

    content = "".join(out)
    target = os.path.join(PROJECT_DIR, "Valid_BOS_Bookmap_Ind.mq5")
    with open(target, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"[OK] Gerado {target} ({len(content)} bytes)")
    return target

def compile_file(mq5_path, target_dir, ex5_name):
    print(f"\n--- Compilando {os.path.basename(mq5_path)} ---")
    log_name = os.path.basename(mq5_path).replace(".mq5", ".log")
    log_file = os.path.join(target_dir, log_name)
    if os.path.exists(log_file):
        os.remove(log_file)

    cmd = f'"{COMPILER_PATH}" /compile:"{mq5_path}" /log'
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    if os.path.exists(log_file):
        with open(log_file, "r", encoding="utf-16le", errors="ignore") as f:
            lines = f.readlines()
            for l in lines[-12:]:
                print(l.rstrip())

    ex5_mt5 = mq5_path.replace(".mq5", ".ex5")
    if os.path.exists(ex5_mt5):
        local_ex5 = os.path.join(PROJECT_DIR, ex5_name)
        shutil.copyfile(ex5_mt5, local_ex5)
        print(f"Binário sincronizado com sucesso: {local_ex5} ({os.path.getsize(local_ex5)} bytes)")

if __name__ == "__main__":
    ea_file = build_ea()
    ind_file = build_ind()

    ea_target_dir = os.path.join(MT5_TERM_DIR, "Experts", "Valid_BOS_Pullback")
    ind_target_dir = os.path.join(MT5_TERM_DIR, "Indicators", "Valid_BOS_Pullback")
    os.makedirs(ea_target_dir, exist_ok=True)
    os.makedirs(ind_target_dir, exist_ok=True)

    ea_mt5 = os.path.join(ea_target_dir, "Valid_BOS_Bookmap_EA.mq5")
    ind_mt5 = os.path.join(ind_target_dir, "Valid_BOS_Bookmap_Ind.mq5")
    shutil.copy2(ea_file, ea_mt5)
    shutil.copy2(ind_file, ind_mt5)

    compile_file(ea_mt5, ea_target_dir, "Valid_BOS_Bookmap_EA.ex5")
    compile_file(ind_mt5, ind_target_dir, "Valid_BOS_Bookmap_Ind.ex5")
