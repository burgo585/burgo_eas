# -*- coding: utf-8 -*-
"""
build_full_updated_tools.py
Implementa todas as funcionalidades solicitadas pelo usuário em:
1. Valid_BOS_Bookmap_EA.mq5
2. Valid_BOS_Bookmap_Ind.mq5
"""

import os
import re
import shutil
import subprocess

MT5_DATA_DIR = r"C:\Users\Vini_Burgo\AppData\Roaming\MetaQuotes\Terminal\9AF8328437A6A393B2016FC9156E6753\MQL5"
METAEDITOR = r"C:\Program Files\MetaTrader 5\metaeditor64.exe"

def update_ea():
    ea_path = r"c:\Robo Virada de Delta\Valid_BOS_Pullback\Valid_BOS_Bookmap_EA.mq5"
    with open(ea_path, "r", encoding="utf-8") as f:
        code = f.read()

    # 1. Variáveis globais
    if "bool g_botActive = true;" not in code:
        code = code.replace("SBookmapData g_bmData;", "SBookmapData g_bmData;\nbool g_botActive = true;       // Controle manual do Robô pelo botão do painel\nbool g_bookmapActive = true;   // Controle manual do Bookmap pelo botão do painel")

    # 2. Bloqueio no ExecuteRealOrder
    if "if(!g_botActive)" not in code:
        idx = code.find("void ExecuteRealOrder(")
        if idx != -1:
            body_start = code.find("{", idx)
            block = "\n   if(!g_botActive)\n   {\n      Print(\"⛔ [ROBÔ PAUSADO] Ordem bloqueada pelo usuário no botão do painel.\");\n      return;\n   }\n"
            code = code[:body_start+1] + block + code[body_start+1:]

    # 3. ParseBookmapJson com normalização de escala
    parse_bm_new = '''void ParseBookmapJson(string json)
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

   double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Normalização se o Bookmap enviar em pips/ticks inteiros (ex: 41988 vs 4198)
   if(g_bmData.lastPrice > 10000.0 && curBid < 10000.0)
   {
      g_bmData.lastPrice /= 10.0;
      g_bmData.poc /= 10.0;
      g_bmData.hvn /= 10.0;
      if(g_bmData.bidWallPrice > 10000.0) g_bmData.bidWallPrice /= 10.0;
      if(g_bmData.askWallPrice > 10000.0) g_bmData.askWallPrice /= 10.0;
   }

   if(g_bmData.lastPrice > 0.0)
   {
      g_bmData.lastUpdateTime = TimeCurrent();
      g_bmData.isConnected = true;

      if(curBid > 0.0)
      {
         double rawBasis = g_bmData.lastPrice - curBid;
         if(InpAutoBasisTracking)
         {
            if(g_smoothedBasis == 0.0 || MathAbs(g_smoothedBasis - rawBasis) > 50.0)
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
}'''

    # Substitui ParseBookmapJson
    pattern_parse = re.compile(r"void ParseBookmapJson\(string json\)\s*\{.*?\n\}", re.DOTALL)
    code = pattern_parse.sub(parse_bm_new, code)

    # 4. RenderBookmapLevels com tooltips claros e checagem g_bookmapActive
    render_bm_new = '''void RenderBookmapLevels()
{
   if(!InpPlotBookmapLevels || !g_bookmapActive || !g_bmData.isConnected || g_smoothedBasis == 0.0)
   {
      ObjectDelete(0, G_PREFIX + "BM_POC");
      ObjectDelete(0, G_PREFIX + "BM_HVN");
      ObjectDelete(0, G_PREFIX + "BM_BidWall");
      ObjectDelete(0, G_PREFIX + "BM_AskWall");
      return;
   }

   double mt5_poc     = g_bmData.poc - g_smoothedBasis;
   double mt5_hvn     = g_bmData.hvn - g_smoothedBasis;
   double mt5_bidWall = (g_bmData.bidWallPrice > 0.0) ? (g_bmData.bidWallPrice - g_smoothedBasis) : 0.0;
   double mt5_askWall = (g_bmData.askWallPrice > 0.0) ? (g_bmData.askWallPrice - g_smoothedBasis) : 0.0;

   datetime t1 = iTime(_Symbol, _Period, MathMin(30, iBars(_Symbol, _Period) - 1));
   datetime t2 = TimeCurrent() + PeriodSeconds(_Period) * 15;

   string pocDesc = StringFormat("★ POC BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.poc, g_smoothedBasis, mt5_poc);
   DrawRayLevel(G_PREFIX + "BM_POC", t1, mt5_poc, t2, mt5_poc, InpColorBookmapPOC, STYLE_SOLID, 2, pocDesc);

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
}'''
    pattern_render = re.compile(r"void RenderBookmapLevels\(\)\s*\{.*?\n\}", re.DOTALL)
    code = pattern_render.sub(render_bm_new, code)

    # 5. Substituir bloco Dashboard inteiro e OnChartEvent
    dash_block = '''//+------------------------------------------------------------------+
//| DIMENSÕES DINÂMICAS DO PAINEL                                    |
//+------------------------------------------------------------------+
int GetLineRelY(int lineIndex)
{
   int extraGap = 0;
   if(lineIndex >= 2) extraGap += 3;
   if(lineIndex >= 5) extraGap += 4;
   if(lineIndex >= 8) extraGap += 4;
   if(lineIndex >= 11) extraGap += 4;
   return g_lineYStart + (lineIndex * g_lineH) + extraGap;
}

void CalculateDashboardDimensions()
{
   g_fontSize = MathMax(7, MathMin(14, InpFontSize));
   double scale = (double)g_fontSize / 8.0;

   g_headerH    = (int)MathRound(34.0 * scale);
   g_lineH      = (int)MathRound(19.0 * scale);
   g_lineYStart = g_headerH + 6;

   int totalLines = 14;
   g_panelHeightFull = g_lineYStart + (totalLines * g_lineH) + 20;
   g_panelHeightMin  = g_headerH + 4;
   g_panelWidth      = (int)MathRound(540.0 * scale);
}

//+------------------------------------------------------------------+
//| CRIAÇÃO DO PAINEL ARRASTÁVEL E MINIMIZÁVEL                       |
//+------------------------------------------------------------------+
void CreateInteractiveDashboard()
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
   CreateDashLabel(G_PREFIX + "Txt_BMNodes",     "★ POC BOOKMAP: --- | ✦ HVN: ---", 12, GetLineRelY(9), clrGold, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BMWalls",     "🏰 PAREDE VENDA: --- | 🛡️ PAREDE COMPRA: ---", 12, GetLineRelY(10), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_LiveCandle",  "Vela [0]: Monitorando microestrutura...", 12, GetLineRelY(11), clrWhite, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_Diag",        "Contexto Técnico: Analisando EMA / ADX...", 12, GetLineRelY(12), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BotStatus",   "STATUS OPERACIONAL: 🟢 ROBÔ ATIVO OPERANDO", 12, GetLineRelY(13), clrLimeGreen, g_fontSize, true);

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

   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(10));

   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(11));

   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(12));

   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(13));
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
   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_TIMEFRAMES, hiddenFlag);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_TIMEFRAMES, hiddenFlag);
}

void UpdateDashboardContent(double curPrice)
{
   if(g_panelMinimized) return;

   double pt = _Point > 0.0 ? _Point : 0.0001;

   // 0. Timer e Spread
   datetime barTime = iTime(_Symbol, _Period, 0);
   int secRem = (int)((barTime + PeriodSeconds(_Period)) - TimeCurrent());
   if(secRem < 0) secRem = 0;
   int mins = secRem / 60;
   int secs = secRem % 60;
   string timerStr = StringFormat("⏱ Candle: %02d:%02d | Spread: %d pts | Corretora: VT Markets", mins, secs, (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   ObjectSetString(0, G_PREFIX + "Txt_Timer", OBJPROP_TEXT, timerStr);

   // 1. Ação Imediata & Posição Ativa
   bool hasPos = false;
   double posOpenPrice = 0.0;
   double posSL = 0.0;
   double posTP = 0.0;
   double posProfit = 0.0;
   string posDir = "";
   double posVol = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
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
         actionTxt = "🎯 SINAL RECOMENDADO: [ 🟢 FORTE COMPRA NO PULLBACK ]";
         actionClr = clrLimeGreen;
         double estSL = g_currentSwingLow > 0.0 ? (g_currentSwingLow - InpSLBufferPoints * pt) : (curPrice - InpMinSLPoints * pt);
         double slPts = MathAbs(curPrice - estSL) / pt;
         entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts]", curPrice, estSL, slPts);
         double tp1 = curPrice + (InpScalpTakeProfitPts * pt);
         double tp2 = curPrice + (slPts * InpRiskRewardRatio * pt);
         tpTargetsTxt = StringFormat("🎯 TP1 (Scalp 50%%): %.2f [+%d pts] | 🚀 TP2 (Runner 50%%): %.2f", tp1, InpScalpTakeProfitPts, tp2);
      }
      else if(g_lastSignalDirection == -1)
      {
         actionTxt = "🎯 SINAL RECOMENDADO: [ 🔴 FORTE VENDA NO PULLBACK ]";
         actionClr = clrRed;
         double estSL = g_currentSwingHigh > 0.0 ? (g_currentSwingHigh + InpSLBufferPoints * pt) : (curPrice + InpMinSLPoints * pt);
         double slPts = MathAbs(estSL - curPrice) / pt;
         entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts]", curPrice, estSL, slPts);
         double tp1 = curPrice - (InpScalpTakeProfitPts * pt);
         double tp2 = curPrice - (slPts * InpRiskRewardRatio * pt);
         tpTargetsTxt = StringFormat("🎯 TP1 (Scalp 50%%): %.2f [-%d pts] | 🚀 TP2 (Runner 50%%): %.2f", tp1, InpScalpTakeProfitPts, tp2);
      }
      else
      {
         actionTxt = "🎯 AÇÃO IMEDIATA: [ ⚪ AGUARDANDO TOQUE / ROMPIMENTO DE ESTRUTURA ]";
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
      string compStr = StringFormat("⚡ BOOKMAP COMEX GC: %.2f USD | 🏦 VT MARKETS SPOT: %.2f USD", g_bmData.lastPrice, curPrice);
      ObjectSetString(0, G_PREFIX + "Txt_BMComp", OBJPROP_TEXT, compStr);

      string basisStr = StringFormat("⚖ DIFERENÇA (BASIS): %+.2f USD ➔ Níveis Bookmap sincronizados nas velas MT5", g_smoothedBasis);
      ObjectSetString(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TEXT, basisStr);

      string deltaDiag = (g_bmData.delta > 50) ? "[COMPRADORES ATIVOS]" : ((g_bmData.delta < -50) ? "[VENDEDORES ATIVOS]" : "[FLUXO EQUILIBRADO]");
      color deltaClr = (g_bmData.delta > 0) ? clrLimeGreen : ((g_bmData.delta < 0) ? clrCrimson : clrSilver);
      string deltaStr = StringFormat("📊 DELTA BOOKMAP: %+d %s | CVD: %+d | Vol Total: %d", g_bmData.delta, deltaDiag, g_bmData.cvd, g_bmData.totalVol);
      ObjectSetString(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TEXT, deltaStr);
      ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_COLOR, deltaClr);

      double mt5_poc = g_bmData.poc - g_smoothedBasis;
      double mt5_hvn = g_bmData.hvn - g_smoothedBasis;
      string nodesStr = StringFormat("★ POC BOOKMAP: %.2f (COMEX %.2f) | ✦ HVN: %.2f (COMEX %.2f)", mt5_poc, g_bmData.poc, mt5_hvn, g_bmData.hvn);
      ObjectSetString(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TEXT, nodesStr);

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
      ObjectSetString(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TEXT, "★ POC BOOKMAP: Aguardando perfil de volume...");
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

   string botStatusStr = g_botActive ? "STATUS: 🟢 ROBÔ ATIVO (AUTOMÁTICO LIGADO) | Magic: " + IntegerToString(InpMagicNumber) : "STATUS: 🔴 ROBÔ PAUSADO PELO USUÁRIO (NÃO ABRE ORDENS)";
   ObjectSetString(0, G_PREFIX + "Txt_BotStatus", OBJPROP_TEXT, botStatusStr);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_COLOR, g_botActive ? clrLimeGreen : clrRed);
}

//+------------------------------------------------------------------+
//| EVENTOS DE GRÁFICO (MOUSE / DRAG / BOTÕES DO PAINEL)             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(!InpShowDashboard) return;

   // 1. Cliques nos Botões do Painel
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
            ObjectDelete(0, G_PREFIX + "BM_POC");
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

   // 2. ARRASTAR LIVREMENTE AO CLICAR E MOVER PELA PARTE SUPERIOR (HEADER)
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
'''
    # Substitui bloco de Dashboard até CreateDashLabel
    idx_calc = code.find("void CalculateDashboardDimensions()")
    if idx_calc != -1:
        # Encontra onde começa OnChartEvent ou CreateDashLabel
        idx_dash_label = code.find("void CreateDashLabel(")
        if idx_dash_label != -1:
            code = code[:idx_calc] + dash_block + "\n" + code[idx_dash_label:]

    # Remove OnChartEvent antigo se tiver sobrado antes
    old_oce_idx = code.find("void OnChartEvent(const int id,")
    # se houver duas definições de OnChartEvent, remove a primeira
    first_oce = code.find("void OnChartEvent(")
    last_oce = code.rfind("void OnChartEvent(")
    if first_oce != -1 and last_oce != -1 and first_oce != last_oce:
        # Remove a primeira definição
        oce_end = code.find("//+---", first_oce + 20)
        if oce_end != -1:
            code = code[:first_oce] + code[oce_end:]

    with open(ea_path, "w", encoding="utf-8") as f:
        f.write(code)

    print("Valid_BOS_Bookmap_EA.mq5 atualizado!")


def update_ind():
    ind_path = r"c:\Robo Virada de Delta\Valid_BOS_Pullback\Valid_BOS_Bookmap_Ind.mq5"
    with open(ind_path, "r", encoding="utf-8") as f:
        code = f.read()

    # 1. Variáveis globais
    if "bool g_signalsActive = true;" not in code:
        code = code.replace("SBookmapData g_bmData;", "SBookmapData g_bmData;\nbool g_signalsActive = true;   // Controle manual de Sinais pelo botão do painel\nbool g_bookmapActive = true;   // Controle manual do Bookmap pelo botão do painel")

    # 2. ParseBookmapJson com normalização de escala
    parse_bm_new = '''void ParseBookmapJson(string json)
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

   double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Normalização se o Bookmap enviar em pips/ticks inteiros (ex: 41988 vs 4198)
   if(g_bmData.lastPrice > 10000.0 && curBid < 10000.0)
   {
      g_bmData.lastPrice /= 10.0;
      g_bmData.poc /= 10.0;
      g_bmData.hvn /= 10.0;
      if(g_bmData.bidWallPrice > 10000.0) g_bmData.bidWallPrice /= 10.0;
      if(g_bmData.askWallPrice > 10000.0) g_bmData.askWallPrice /= 10.0;
   }

   if(g_bmData.lastPrice > 0.0)
   {
      g_bmData.lastUpdateTime = TimeCurrent();
      g_bmData.isConnected = true;

      if(curBid > 0.0)
      {
         double rawBasis = g_bmData.lastPrice - curBid;
         if(InpAutoBasisTracking)
         {
            if(g_smoothedBasis == 0.0 || MathAbs(g_smoothedBasis - rawBasis) > 50.0)
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
}'''
    pattern_parse = re.compile(r"void ParseBookmapJson\(string json\)\s*\{.*?\n\}", re.DOTALL)
    code = pattern_parse.sub(parse_bm_new, code)

    # 3. RenderBookmapLevels com tooltips claros e checagem g_bookmapActive
    render_bm_new = '''void RenderBookmapLevels()
{
   if(!InpPlotBookmapLevels || !g_bookmapActive || !g_bmData.isConnected || g_smoothedBasis == 0.0)
   {
      ObjectDelete(0, G_PREFIX + "BM_POC");
      ObjectDelete(0, G_PREFIX + "BM_HVN");
      ObjectDelete(0, G_PREFIX + "BM_BidWall");
      ObjectDelete(0, G_PREFIX + "BM_AskWall");
      return;
   }

   double mt5_poc     = g_bmData.poc - g_smoothedBasis;
   double mt5_hvn     = g_bmData.hvn - g_smoothedBasis;
   double mt5_bidWall = (g_bmData.bidWallPrice > 0.0) ? (g_bmData.bidWallPrice - g_smoothedBasis) : 0.0;
   double mt5_askWall = (g_bmData.askWallPrice > 0.0) ? (g_bmData.askWallPrice - g_smoothedBasis) : 0.0;

   datetime t1 = iTime(_Symbol, _Period, MathMin(30, iBars(_Symbol, _Period) - 1));
   datetime t2 = TimeCurrent() + PeriodSeconds(_Period) * 15;

   string pocDesc = StringFormat("★ POC BOOKMAP [COMEX %.2f - Basis %.2f = MT5 %.2f]", g_bmData.poc, g_smoothedBasis, mt5_poc);
   DrawRayLevel(G_PREFIX + "BM_POC", t1, mt5_poc, t2, mt5_poc, InpColorBookmapPOC, STYLE_SOLID, 2, pocDesc);

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
}'''
    pattern_render = re.compile(r"void RenderBookmapLevels\(\)\s*\{.*?\n\}", re.DOTALL)
    code = pattern_render.sub(render_bm_new, code)

    # 4. Bloco Dashboard do Indicador
    dash_block_ind = '''//+------------------------------------------------------------------+
//| DIMENSÕES DINÂMICAS DO PAINEL                                    |
//+------------------------------------------------------------------+
int GetLineRelY(int lineIndex)
{
   int extraGap = 0;
   if(lineIndex >= 2) extraGap += 3;
   if(lineIndex >= 5) extraGap += 4;
   if(lineIndex >= 8) extraGap += 4;
   if(lineIndex >= 11) extraGap += 4;
   return g_lineYStart + (lineIndex * g_lineH) + extraGap;
}

void CalculateDashboardDimensions()
{
   g_fontSize = MathMax(7, MathMin(14, InpFontSize));
   double scale = (double)g_fontSize / 8.0;

   g_headerH    = (int)MathRound(34.0 * scale);
   g_lineH      = (int)MathRound(19.0 * scale);
   g_lineYStart = g_headerH + 6;

   int totalLines = 14;
   g_panelHeightFull = g_lineYStart + (totalLines * g_lineH) + 20;
   g_panelHeightMin  = g_headerH + 4;
   g_panelWidth      = (int)MathRound(540.0 * scale);
}

//+------------------------------------------------------------------+
//| CRIAÇÃO DO PAINEL ARRASTÁVEL E MINIMIZÁVEL                       |
//+------------------------------------------------------------------+
void CreateInteractiveDashboard()
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
   CreateDashLabel(G_PREFIX + "Txt_BMNodes",     "★ POC BOOKMAP: --- | ✦ HVN: ---", 12, GetLineRelY(9), clrGold, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BMWalls",     "🏰 PAREDE VENDA: --- | 🛡️ PAREDE COMPRA: ---", 12, GetLineRelY(10), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_LiveCandle",  "Vela [0]: Monitorando microestrutura...", 12, GetLineRelY(11), clrWhite, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_Diag",        "Contexto Técnico: Analisando EMA / ADX...", 12, GetLineRelY(12), clrSilver, g_fontSize, false);
   CreateDashLabel(G_PREFIX + "Txt_BotStatus",   "STATUS OPERACIONAL: 🟢 SINAIS ATIVOS E MONITORANDO", 12, GetLineRelY(13), clrLimeGreen, g_fontSize, true);

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

   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BMWalls", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(10));

   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_LiveCandle", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(11));

   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_Diag", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(12));

   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_XDISTANCE, g_panelX + 12);
   ObjectSetInteger(0, G_PREFIX + "Txt_BotStatus", OBJPROP_YDISTANCE, g_panelY + GetLineRelY(13));
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
         actionTxt = "🎯 SINAL RECOMENDADO: [ 🟢 FORTE COMPRA NO PULLBACK ]";
         actionClr = clrLimeGreen;
         double estSL = g_currentSwingLow > 0.0 ? (g_currentSwingLow - InpSLBufferPoints * pt) : (curPrice - InpMinSLPoints * pt);
         double slPts = MathAbs(curPrice - estSL) / pt;
         entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts]", curPrice, estSL, slPts);
         double tp1 = curPrice + (InpScalpTakeProfitPts * pt);
         double tp2 = curPrice + (slPts * InpRiskRewardRatio * pt);
         tpTargetsTxt = StringFormat("🎯 TP1 (Scalp 50%%): %.2f [+%d pts] | 🚀 TP2 (Runner 50%%): %.2f", tp1, InpScalpTakeProfitPts, tp2);
      }
      else if(g_lastSignalDirection == -1)
      {
         actionTxt = "🎯 SINAL RECOMENDADO: [ 🔴 FORTE VENDA NO PULLBACK ]";
         actionClr = clrRed;
         double estSL = g_currentSwingHigh > 0.0 ? (g_currentSwingHigh + InpSLBufferPoints * pt) : (curPrice + InpMinSLPoints * pt);
         double slPts = MathAbs(estSL - curPrice) / pt;
         entrySLTxt = StringFormat("📍 ENTRADA: %.2f | 🛑 STOP LOSS: %.2f [%.0f pts]", curPrice, estSL, slPts);
         double tp1 = curPrice - (InpScalpTakeProfitPts * pt);
         double tp2 = curPrice - (slPts * InpRiskRewardRatio * pt);
         tpTargetsTxt = StringFormat("🎯 TP1 (Scalp 50%%): %.2f [-%d pts] | 🚀 TP2 (Runner 50%%): %.2f", tp1, InpScalpTakeProfitPts, tp2);
      }
      else
      {
         actionTxt = "🎯 AÇÃO IMEDIATA: [ ⚪ AGUARDANDO TOQUE / ROMPIMENTO DE ESTRUTURA ]";
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
      string compStr = StringFormat("⚡ BOOKMAP COMEX GC: %.2f USD | 🏦 VT MARKETS SPOT: %.2f USD", g_bmData.lastPrice, curPrice);
      ObjectSetString(0, G_PREFIX + "Txt_BMComp", OBJPROP_TEXT, compStr);

      string basisStr = StringFormat("⚖ DIFERENÇA (BASIS): %+.2f USD ➔ Níveis Bookmap sincronizados nas velas MT5", g_smoothedBasis);
      ObjectSetString(0, G_PREFIX + "Txt_BMBasis", OBJPROP_TEXT, basisStr);

      string deltaDiag = (g_bmData.delta > 50) ? "[COMPRADORES ATIVOS]" : ((g_bmData.delta < -50) ? "[VENDEDORES ATIVOS]" : "[FLUXO EQUILIBRADO]");
      color deltaClr = (g_bmData.delta > 0) ? clrLimeGreen : ((g_bmData.delta < 0) ? clrCrimson : clrSilver);
      string deltaStr = StringFormat("📊 DELTA BOOKMAP: %+d %s | CVD: %+d | Vol Total: %d", g_bmData.delta, deltaDiag, g_bmData.cvd, g_bmData.totalVol);
      ObjectSetString(0, G_PREFIX + "Txt_BMDelta", OBJPROP_TEXT, deltaStr);
      ObjectSetInteger(0, G_PREFIX + "Txt_BMDelta", OBJPROP_COLOR, deltaClr);

      double mt5_poc = g_bmData.poc - g_smoothedBasis;
      double mt5_hvn = g_bmData.hvn - g_smoothedBasis;
      string nodesStr = StringFormat("★ POC BOOKMAP: %.2f (COMEX %.2f) | ✦ HVN: %.2f (COMEX %.2f)", mt5_poc, g_bmData.poc, mt5_hvn, g_bmData.hvn);
      ObjectSetString(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TEXT, nodesStr);

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
      ObjectSetString(0, G_PREFIX + "Txt_BMNodes", OBJPROP_TEXT, "★ POC BOOKMAP: Aguardando perfil de volume...");
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

//+------------------------------------------------------------------+
//| EVENTOS DE GRÁFICO (MOUSE / DRAG / BOTÕES DO PAINEL)             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(!InpShowDashboard) return;

   // 1. Cliques nos Botões do Painel
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
            ObjectDelete(0, G_PREFIX + "BM_POC");
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

   // 2. ARRASTAR LIVREMENTE AO CLICAR E MOVER PELA PARTE SUPERIOR (HEADER)
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
'''
    idx_calc = code.find("void CalculateDashboardDimensions()")
    if idx_calc != -1:
        idx_dash_label = code.find("void CreateDashLabel(")
        if idx_dash_label != -1:
            code = code[:idx_calc] + dash_block_ind + "\n" + code[idx_dash_label:]

    # Remove OnChartEvent antigo se duplicado
    first_oce = code.find("void OnChartEvent(")
    last_oce = code.rfind("void OnChartEvent(")
    if first_oce != -1 and last_oce != -1 and first_oce != last_oce:
        oce_end = code.find("//+---", first_oce + 20)
        if oce_end != -1:
            code = code[:first_oce] + code[oce_end:]

    with open(ind_path, "w", encoding="utf-8") as f:
        f.write(code)

    print("Valid_BOS_Bookmap_Ind.mq5 atualizado!")


def sync_and_compile():
    print("Sincronizando arquivos com MetaTrader 5...")
    src_ea = r"c:\Robo Virada de Delta\Valid_BOS_Pullback\Valid_BOS_Bookmap_EA.mq5"
    dst_ea = os.path.join(MT5_DATA_DIR, "Experts", "Valid_BOS_Pullback", "Valid_BOS_Bookmap_EA.mq5")
    shutil.copy2(src_ea, dst_ea)

    src_ind = r"c:\Robo Virada de Delta\Valid_BOS_Pullback\Valid_BOS_Bookmap_Ind.mq5"
    dst_ind = os.path.join(MT5_DATA_DIR, "Indicators", "Valid_BOS_Pullback", "Valid_BOS_Bookmap_Ind.mq5")
    shutil.copy2(src_ind, dst_ind)

    print("Compilando EA...")
    res_ea = subprocess.run([METAEDITOR, f"/compile:{dst_ea}", "/log"], capture_output=True, text=True)
    print("EA Retorno:", res_ea.returncode)

    print("Compilando Indicador...")
    res_ind = subprocess.run([METAEDITOR, f"/compile:{dst_ind}", "/log"], capture_output=True, text=True)
    print("Ind Retorno:", res_ind.returncode)

    # Copiar os ex5 de volta para o workspace
    dst_ea_ex5 = dst_ea.replace(".mq5", ".ex5")
    dst_ind_ex5 = dst_ind.replace(".mq5", ".ex5")
    shutil.copy2(dst_ea_ex5, src_ea.replace(".mq5", ".ex5"))
    shutil.copy2(dst_ind_ex5, src_ind.replace(".mq5", ".ex5"))
    print("Concluído com sucesso!")

if __name__ == "__main__":
    update_ea()
    update_ind()
    sync_and_compile()
