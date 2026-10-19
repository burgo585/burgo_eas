//+------------------------------------------------------------------+
//|                                                  CanalDrawer.mq5 |
//|                                        Lógica de Linhas Manuais  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "4.10"

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Parâmetros de Entrada (Configurações para arquivos .set)         |
//+------------------------------------------------------------------+
input group "--- Configurações de Canais ---"
input int      InpProjUp       = 2;          // Canais padrão para Cima
input int      InpProjDown     = 2;          // Canais padrão para Baixo
input bool     InpPaintZones   = true;       // Pintar Zonas (CR / ZN) por padrão
input bool     InpPushAlert    = false;      // Alertas Push no Celular por padrão

input group "--- Configurações de Fibonacci ---"
input bool     InpUseFibo      = true;       // Ativar Fibonacci por padrão
input int      InpFiboMode     = 0;          // Modo Fibo (0=Canal Base, 1=Range do Dia, 2=Perna Estrutural)

//+------------------------------------------------------------------+
//| Includes                                                         |
//+------------------------------------------------------------------+
#include <Controls\Dialog.mqh>
#include <Controls\Button.mqh>
#include <Controls\Edit.mqh>
#include <Controls\Label.mqh>
#include <Controls\CheckBox.mqh>

//+------------------------------------------------------------------+
//| Variáveis Globais                                                |
//+------------------------------------------------------------------+
CDialog          Dialog;
CButton          BtnMinMax;     
CButton          BtnStart;
CButton          BtnProject;
CButton          BtnClear;
CButton          BtnHideShow;
CLabel           LabelStatus;
CEdit            EditProjUp;    
CEdit            EditProjDown;  
CEdit            EditFiboMode;  
CCheckBox        CheckZones;
CCheckBox        CheckFibo;     
CCheckBox        CheckPush;
CLabel           lblUp;
CLabel           lblDown;
CLabel           lblFiboMode;

string           g_prefix = "CanalDraw_";
string           g_tempLine1 = "TempLine_1";
string           g_tempLine2 = "TempLine_2";
string           g_fiboDayName = "Fibo_Dinamica_Dia";

int              g_step = 0; // 0=Parado, 1=Aguardando Linha 1, 2=Aguardando Linha 2, 3=Pronto para Projetar
bool             g_isVisible = true;
bool             g_isMinimized = false;
datetime         g_lastAlert = 0;
double           g_highestProj = 0.0;
double           g_lowestProj = 0.0;
bool             g_hasProjections = false;
bool             g_alertedHigh = false;
bool             g_alertedLow  = false;

//+------------------------------------------------------------------+
//| Prefixos para Variáveis Globais de Terminal                      |
//+------------------------------------------------------------------+
string GetGVPrefix()
{
   return "CanalDrw_" + IntegerToString(ChartID()) + "_";
}

void SalvarEstadoGlobal(double baseTop, double baseBottom, double highProj, double lowProj,
                        int projUp, int projDown, int fiboMode,
                        bool paintZones, bool useFibo, bool pushAlert,
                        bool isVisible, bool isMinimized)
{
   string p = GetGVPrefix();
   GlobalVariableSet(p + "has_proj", 1.0);
   GlobalVariableSet(p + "base_top", baseTop);
   GlobalVariableSet(p + "base_bottom", baseBottom);
   GlobalVariableSet(p + "high_proj", highProj);
   GlobalVariableSet(p + "low_proj", lowProj);
   GlobalVariableSet(p + "proj_up", (double)projUp);
   GlobalVariableSet(p + "proj_down", (double)projDown);
   GlobalVariableSet(p + "fibo_mode", (double)fiboMode);
   GlobalVariableSet(p + "zones", paintZones ? 1.0 : 0.0);
   GlobalVariableSet(p + "fibo", useFibo ? 1.0 : 0.0);
   GlobalVariableSet(p + "push", pushAlert ? 1.0 : 0.0);
   GlobalVariableSet(p + "visible", isVisible ? 1.0 : 0.0);
   GlobalVariableSet(p + "minimized", isMinimized ? 1.0 : 0.0);
}

void LimparVariaveisGlobais()
{
   string p = GetGVPrefix();
   GlobalVariableDel(p + "has_proj");
   GlobalVariableDel(p + "base_top");
   GlobalVariableDel(p + "base_bottom");
   GlobalVariableDel(p + "high_proj");
   GlobalVariableDel(p + "low_proj");
   GlobalVariableDel(p + "proj_up");
   GlobalVariableDel(p + "proj_down");
   GlobalVariableDel(p + "fibo_mode");
   GlobalVariableDel(p + "zones");
   GlobalVariableDel(p + "fibo");
   GlobalVariableDel(p + "push");
   GlobalVariableDel(p + "visible");
   GlobalVariableDel(p + "minimized");
}

void LimparMarcacoesGrafico()
{
   ObjectsDeleteAll(0, g_prefix);
   ObjectDelete(0, g_tempLine1);
   ObjectDelete(0, g_tempLine2);
   ObjectDelete(0, g_fiboDayName);
}

//+------------------------------------------------------------------+
//| Inicialização do Indicador                                       |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!CreatePanel())
   {
      Print("Erro ao criar painel de controle!");
      return(INIT_FAILED);
   }
   
   // Restaura o estado salvo ao trocar de tempo gráfico
   RestaurarEstado();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Restaurar estado após mudança de tempo gráfico                   |
//+------------------------------------------------------------------+
void RestaurarEstado()
{
   string p = GetGVPrefix();
   if(GlobalVariableCheck(p + "has_proj") && GlobalVariableGet(p + "has_proj") > 0.5)
   {
      g_hasProjections = true;
      g_highestProj    = GlobalVariableGet(p + "high_proj");
      g_lowestProj     = GlobalVariableGet(p + "low_proj");
      
      int projUp       = (int)GlobalVariableGet(p + "proj_up");
      int projDown     = (int)GlobalVariableGet(p + "proj_down");
      int fiboMode     = (int)GlobalVariableGet(p + "fibo_mode");
      bool paintZones  = (GlobalVariableGet(p + "zones") > 0.5);
      bool useFibo     = (GlobalVariableGet(p + "fibo") > 0.5);
      bool pushAlert   = (GlobalVariableGet(p + "push") > 0.5);
      g_isVisible      = (GlobalVariableGet(p + "visible") > 0.5);
      bool wasMinimized= (GlobalVariableGet(p + "minimized") > 0.5);
      
      EditProjUp.Text(IntegerToString(projUp));
      EditProjDown.Text(IntegerToString(projDown));
      EditFiboMode.Text(IntegerToString(fiboMode));
      CheckZones.Checked(paintZones);
      CheckFibo.Checked(useFibo);
      CheckPush.Checked(pushAlert);
      
      BtnHideShow.Text(g_isVisible ? "Ocultar Linhas (Modo Limpo)" : "Mostrar Linhas");
      LabelStatus.Text("Status: Canal Ativo.");
      LabelStatus.Color(clrBlue);
      
      if(wasMinimized && !g_isMinimized)
      {
         ToggleMinimize();
      }
      
      if(!g_isVisible)
      {
         ToggleVisibility();
      }
      
      if(useFibo)
      {
         double bTop = GlobalVariableGet(p + "base_top");
         double bBot = GlobalVariableGet(p + "base_bottom");
         GerenciarFibonacci(fiboMode, bBot, bTop);
      }
   }
   else
   {
      LabelStatus.Text("Status: Parado.");
      LabelStatus.Color(clrBlue);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Criação do Painel Gráfico                                        |
//+------------------------------------------------------------------+
bool CreatePanel()
{
   int x1 = 20, y1 = 50, x2 = 280, y2 = 470; 
   
   if(!Dialog.Create(0, "CanalPanel", 0, x1, y1, x2, y2)) 
      return(false);
      
   Dialog.Caption("Projetor de Frequencia - PRO");
   
   // Botão Minimizar / Maximizar
   if(!BtnMinMax.Create(0, "BtnMinMax", 0, 230, 2, 255, 20)) 
      return(false);
   BtnMinMax.Text("[-]");
   BtnMinMax.Color(clrBlack);
   Dialog.Add(BtnMinMax);
   
   // Botão 1: Iniciar Marcação
   if(!BtnStart.Create(0, "BtnStart", 0, 10, 35, 250, 65)) 
      return(false);
   BtnStart.Text("1. Iniciar Marcação");
   Dialog.Add(BtnStart);
   
   // Botão 2: Projetar Canais
   if(!BtnProject.Create(0, "BtnProject", 0, 10, 75, 250, 105)) 
      return(false);
   BtnProject.Text("2. Projetar Canais (Concluir)");
   Dialog.Add(BtnProject);
   
   // Campo Edit: Canais Acima
   if(!EditProjUp.Create(0, "EditProjUp", 0, 10, 120, 60, 140)) 
      return(false);
   EditProjUp.Text(IntegerToString(InpProjUp)); 
   EditProjUp.ColorBackground(clrWhite);
   EditProjUp.Color(clrBlack);
   Dialog.Add(EditProjUp);
   
   if(!lblUp.Create(0, "LabelProjUp", 0, 70, 120, 250, 140)) 
      return(false);
   lblUp.Text("Canais para CIMA");
   lblUp.Color(clrBlack);
   Dialog.Add(lblUp);

   // Campo Edit: Canais Abaixo
   if(!EditProjDown.Create(0, "EditProjDown", 0, 10, 150, 60, 170)) 
      return(false);
   EditProjDown.Text(IntegerToString(InpProjDown)); 
   EditProjDown.ColorBackground(clrWhite);
   EditProjDown.Color(clrBlack);
   Dialog.Add(EditProjDown);
   
   if(!lblDown.Create(0, "LabelProjDown", 0, 70, 150, 250, 170)) 
      return(false);
   lblDown.Text("Canais para BAIXO");
   lblDown.Color(clrBlack);
   Dialog.Add(lblDown);

   // Campo Edit: Modo da Fibo (0, 1 ou 2)
   if(!EditFiboMode.Create(0, "EditFiboMode", 0, 10, 180, 60, 200)) 
      return(false);
   EditFiboMode.Text(IntegerToString(InpFiboMode)); 
   EditFiboMode.ColorBackground(clrWhite);
   EditFiboMode.Color(clrBlack);
   Dialog.Add(EditFiboMode);
   
   if(!lblFiboMode.Create(0, "LabelFiboMode", 0, 70, 180, 250, 200)) 
      return(false);
   lblFiboMode.Text("Modo Fibo (0, 1 ou 2)");
   lblFiboMode.Color(clrBlack);
   Dialog.Add(lblFiboMode);

   // CheckBox: Pintar Zonas
   if(!CheckZones.Create(0, "CheckZones", 0, 10, 210, 250, 230)) 
      return(false);
   CheckZones.Text("Pintar Zonas (CR / ZN)");
   CheckZones.Color(clrBlack);
   CheckZones.Checked(InpPaintZones);
   Dialog.Add(CheckZones);

   // CheckBox: Confluência Fibonacci
   if(!CheckFibo.Create(0, "CheckFibo", 0, 10, 235, 250, 255)) 
      return(false);
   CheckFibo.Text("Ativar Fibonacci");
   CheckFibo.Color(clrBlack);
   CheckFibo.Checked(InpUseFibo);
   Dialog.Add(CheckFibo);

   // CheckBox: Alertas Push
   if(!CheckPush.Create(0, "CheckPush", 0, 10, 260, 250, 280)) 
      return(false);
   CheckPush.Text("Alertas Push no Rompimento");
   CheckPush.Color(clrBlack);
   CheckPush.Checked(InpPushAlert);
   Dialog.Add(CheckPush);

   // Botão: Ocultar/Mostrar Linhas (Modo Limpo)
   if(!BtnHideShow.Create(0, "BtnHideShow", 0, 10, 295, 250, 325)) 
      return(false);
   BtnHideShow.Text("Ocultar Linhas (Modo Limpo)");
   BtnHideShow.Color(clrDarkBlue);
   Dialog.Add(BtnHideShow);

   // Botão: Limpar Tudo
   if(!BtnClear.Create(0, "BtnClear", 0, 10, 335, 250, 365)) 
      return(false);
   BtnClear.Text("Limpar Tudo");
   BtnClear.Color(clrRed);
   Dialog.Add(BtnClear);
   
   // Label de Status
   if(!LabelStatus.Create(0, "LabelStatus", 0, 10, 380, 250, 400)) 
      return(false);
   LabelStatus.Text("Status: Parado.");
   LabelStatus.Color(clrBlue);
   Dialog.Add(LabelStatus);
   
   Dialog.Show();
   return(true);
}

//+------------------------------------------------------------------+
//| Alternar Minimização                                             |
//+------------------------------------------------------------------+
void ToggleMinimize()
{
   g_isMinimized = !g_isMinimized;
   
   if(g_isMinimized)
   {
      BtnMinMax.Text("[+]");
      BtnStart.Hide();
      BtnProject.Hide();
      EditProjUp.Hide();
      EditProjDown.Hide();
      EditFiboMode.Hide();
      CheckZones.Hide();
      CheckFibo.Hide();
      CheckPush.Hide();
      BtnHideShow.Hide();
      BtnClear.Hide();
      LabelStatus.Hide();
      lblUp.Hide();
      lblDown.Hide();
      lblFiboMode.Hide();
      
      Dialog.Height(30); 
   }
   else
   {
      BtnMinMax.Text("[-]");
      Dialog.Height(430); 
      
      BtnStart.Show();
      BtnProject.Show();
      EditProjUp.Show();
      EditProjDown.Show();
      EditFiboMode.Show();
      CheckZones.Show();
      CheckFibo.Show();
      CheckPush.Show();
      BtnHideShow.Show();
      BtnClear.Show();
      LabelStatus.Show();
      lblUp.Show();
      lblDown.Show();
      lblFiboMode.Show();
   }
   
   if(g_hasProjections)
   {
      GlobalVariableSet(GetGVPrefix() + "minimized", g_isMinimized ? 1.0 : 0.0);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Finalização do Indicador                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Apenas apaga os canais e variáveis globais se o indicador foi REALMENTE removido do gráfico
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
   {
      LimparMarcacoesGrafico();
      LimparVariaveisGlobais();
   }
   else
   {
      // Se apenas mudou de tempo gráfico (REASON_CHARTCHANGE) ou parâmetros:
      // Remove apenas linhas temporárias de marcação não finalizadas
      ObjectDelete(0, g_tempLine1);
      ObjectDelete(0, g_tempLine2);
   }
   
   Dialog.Destroy();
}

//+------------------------------------------------------------------+
//| Tratamento de Eventos do Gráfico e Painel                        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Propaga eventos para os controles da Dialog (fundamental para CheckBoxes e Edits)
   Dialog.OnEvent(id, lparam, dparam, sparam);

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "BtnMinMax") ToggleMinimize();
      
      if(sparam == "BtnStart")
      {
         ObjectDelete(0, g_tempLine1);
         ObjectDelete(0, g_tempLine2);
         g_step = 1;
         LabelStatus.Text("Status: Clique p/ Linha 1");
         LabelStatus.Color(clrRed);
         ChartRedraw();
      }
      
      if(sparam == "BtnProject")
      {
         if(g_step == 3) ProjetarCanais();
         else MessageBox("Posicione as duas linhas no gráfico primeiro!", "Aviso", MB_OK | MB_ICONWARNING);
      }

      if(sparam == "BtnHideShow")
      {
         g_isVisible = !g_isVisible;
         ToggleVisibility();
         BtnHideShow.Text(g_isVisible ? "Ocultar Linhas (Modo Limpo)" : "Mostrar Linhas");
         if(g_hasProjections)
         {
            GlobalVariableSet(GetGVPrefix() + "visible", g_isVisible ? 1.0 : 0.0);
         }
         ChartRedraw();
      }
      
      if(sparam == "BtnClear")
      {
         LimparMarcacoesGrafico();
         LimparVariaveisGlobais();
         g_step = 0;
         g_hasProjections = false;
         g_alertedHigh = false;
         g_alertedLow  = false;
         LabelStatus.Text("Status: Tudo Limpo.");
         LabelStatus.Color(clrBlue);
         ChartRedraw();
      }
   }
   
   if(id == CHARTEVENT_CLICK && (g_step == 1 || g_step == 2))
   {
      int x = (int)lparam, y = (int)dparam;
      
      // Evita marcar se clicou em cima do painel
      if(Dialog.Contains(x, y))
         return;

      int subwindow;
      datetime time; double price;
      
      if(ChartXYToTimePrice(0, x, y, subwindow, time, price))
      {
         if(g_step == 1)
         {
            CriarLinhaTemporaria(g_tempLine1, price);
            g_step = 2;
            LabelStatus.Text("Status: Clique p/ Linha 2");
            LabelStatus.Color(clrRed);
         }
         else if(g_step == 2)
         {
            CriarLinhaTemporaria(g_tempLine2, price);
            g_step = 3;
            LabelStatus.Text("Ajuste as linhas e clique em PROJETAR");
            LabelStatus.Color(clrLimeGreen);
         }
         ChartRedraw();
      }
   }
}

//+------------------------------------------------------------------+
//| Criar linha temporária ajustável                                 |
//+------------------------------------------------------------------+
void CriarLinhaTemporaria(string nome, double price)
{
   ObjectCreate(0, nome, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, clrMagenta);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, nome, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, nome, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, nome, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
//| Desenhar linha horizontal final definitiva                       |
//+------------------------------------------------------------------+
void DesenharHLine(string name, double price, color clr, int style)
{
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
//| Desenhar zonas preenchidas (CR e ZN)                             |
//+------------------------------------------------------------------+
void DesenharZona(string name, double priceTop, double priceBottom, color clr)
{
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, D'1970.01.01', priceTop, D'2099.12.31', priceBottom);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
//| Desenhar Fibonacci de acordo com o modo escolhido                |
//+------------------------------------------------------------------+
void GerenciarFibonacci(int modo, double canalBottom, double canalTop)
{
   ObjectDelete(0, g_fiboDayName);
   
   datetime t1 = 0;
   datetime t2 = 0;
   double pBottom = 0;
   double pTop = 0;
   
   if(modo == 0) // Modo 0: Fibo fixa cravada no Canal Base estático
   {
      pBottom = canalBottom;
      pTop = canalTop;
      t1 = TimeCurrent() - (PeriodSeconds() * 200);
      t2 = TimeCurrent();
   }
   else if(modo == 1) // Modo 1: Fibo Dinâmica baseada no Range do Dia (High/Low atual)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(_Symbol, PERIOD_D1, 0, 1, rates);
      if(copied > 0)
      {
         pBottom = rates[0].low;
         pTop = rates[0].high;
         t1 = rates[0].time;
         t2 = rates[0].time + 86400;
      }
      else return;
   }
   else if(modo == 2) // Modo 2: Fibo Estrutural (Amplitude do canal base no preço atual)
   {
      double amplitude = canalTop - canalBottom;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      pBottom = bid - amplitude;
      pTop = bid + amplitude;
      t1 = TimeCurrent() - (PeriodSeconds() * 100);
      t2 = TimeCurrent();
   }
   
   if(pTop > pBottom)
   {
      ObjectCreate(0, g_fiboDayName, OBJ_FIBO, 0, t1, pBottom, t2, pTop);
      ObjectSetInteger(0, g_fiboDayName, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, g_fiboDayName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, g_fiboDayName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, g_fiboDayName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, g_fiboDayName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, g_fiboDayName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
}

//+------------------------------------------------------------------+
//| Alternar Visibilidade das Linhas (Modo Limpo)                    |
//+------------------------------------------------------------------+
void ToggleVisibility()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0 || name == g_fiboDayName)
      {
         if(g_isVisible) 
            ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         else 
            ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      }
   }
}

//+------------------------------------------------------------------+
//| Executar o cálculo e projeção dos canais                         |
//+------------------------------------------------------------------+
void ProjetarCanais()
{
   double price1 = ObjectGetDouble(0, g_tempLine1, OBJPROP_PRICE);
   double price2 = ObjectGetDouble(0, g_tempLine2, OBJPROP_PRICE);
   
   double topPrice = MathMax(price1, price2);
   double bottomPrice = MathMin(price1, price2);
   double amplitude = topPrice - bottomPrice;
   
   if(amplitude <= 0)
   {
      MessageBox("A amplitude não pode ser zero. Afaste as linhas de referência.", "Erro", MB_OK | MB_ICONERROR);
      return;
   }
   
   // Limpa projeções anteriores para não acumular
   ObjectsDeleteAll(0, g_prefix);
   ObjectDelete(0, g_fiboDayName);
   
   int projUp = (int)StringToInteger(EditProjUp.Text());
   int projDown = (int)StringToInteger(EditProjDown.Text());
   int fiboMode = (int)StringToInteger(EditFiboMode.Text());
   bool paintZones = CheckZones.Checked();
   bool useFibo = CheckFibo.Checked();
   bool pushAlert = CheckPush.Checked();
   
   color corRef = clrDarkSlateGray; 
   color corNeut = clrDimGray;      
   
   // Canal Base (Principal)
   double midPrice = bottomPrice + (amplitude / 2.0);
   if(paintZones) 
      DesenharZona(g_prefix + "Zone_Base", topPrice, bottomPrice, corRef);
      
   DesenharHLine(g_prefix + "Top", topPrice, clrRed, STYLE_SOLID);
   DesenharHLine(g_prefix + "Bottom", bottomPrice, clrRed, STYLE_SOLID);
   DesenharHLine(g_prefix + "Mid", midPrice, clrYellow, STYLE_DASH);
   
   g_highestProj = topPrice;
   g_lowestProj = bottomPrice;

   // Projeções para CIMA
   for(int i = 1; i <= projUp; i++)
   {
      double pTop = topPrice + (i * amplitude);
      double pBottom = topPrice + ((i - 1) * amplitude);
      double pMid = pTop - (amplitude / 2.0);
      
      if(paintZones) 
         DesenharZona(g_prefix + "ZoneUp_" + IntegerToString(i), pTop, pBottom, (i%2==0) ? corRef : corNeut);
      DesenharHLine(g_prefix + "ProjUp_" + IntegerToString(i), pTop, clrRed, STYLE_SOLID);
      DesenharHLine(g_prefix + "ProjUpMid_" + IntegerToString(i), pMid, clrYellow, STYLE_DASH);
      
      g_highestProj = pTop;
   }
   
   // Projeções para BAIXO
   for(int i = 1; i <= projDown; i++)
   {
      double pBottom = bottomPrice - (i * amplitude);
      double pTop = bottomPrice - ((i - 1) * amplitude);
      double pMid = pBottom + (amplitude / 2.0);
      
      if(paintZones) 
         DesenharZona(g_prefix + "ZoneDown_" + IntegerToString(i), pTop, pBottom, (i%2==0) ? corRef : corNeut);
      DesenharHLine(g_prefix + "ProjDown_" + IntegerToString(i), pBottom, clrRed, STYLE_SOLID);
      DesenharHLine(g_prefix + "ProjDownMid_" + IntegerToString(i), pMid, clrYellow, STYLE_DASH);
      
      g_lowestProj = pBottom;
   }
   
   // Gerencia a Fibonacci com base no modo escolhido
   if(useFibo)
   {
      GerenciarFibonacci(fiboMode, bottomPrice, topPrice);
   }
   
   // Salva nas Variáveis Globais de Terminal para sobrevivência à mudança de tempo gráfico
   SalvarEstadoGlobal(topPrice, bottomPrice, g_highestProj, g_lowestProj,
                      projUp, projDown, fiboMode,
                      paintZones, useFibo, pushAlert,
                      g_isVisible, g_isMinimized);

   // Remove as linhas de marcação temporárias
   ObjectDelete(0, g_tempLine1);
   ObjectDelete(0, g_tempLine2);
   
   g_step = 0;
   g_hasProjections = true;
   g_isVisible = true;
   g_alertedHigh = false;
   g_alertedLow  = false;
   BtnHideShow.Text("Ocultar Linhas (Modo Limpo)");
   
   LabelStatus.Text("Status: Canais Projetados!");
   LabelStatus.Color(clrBlue);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Função principal do indicador (chamada a cada tick)              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(g_hasProjections && CheckFibo.Checked() && StringToInteger(EditFiboMode.Text()) == 1)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, PERIOD_D1, 0, 1, rates) > 0)
      {
         if(ObjectFind(0, g_fiboDayName) >= 0)
         {
            ObjectSetDouble(0, g_fiboDayName, OBJPROP_PRICE, 0, rates[0].low);
            ObjectSetDouble(0, g_fiboDayName, OBJPROP_PRICE, 1, rates[0].high);
            ObjectSetInteger(0, g_fiboDayName, OBJPROP_TIME, 0, rates[0].time);
            ObjectSetInteger(0, g_fiboDayName, OBJPROP_TIME, 1, rates[0].time + 86400);
         }
      }
   }

   if(g_hasProjections && CheckPush.Checked())
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Alerta de Rompimento Superior
      if(currentPrice > g_highestProj)
      {
         if(!g_alertedHigh && (TimeCurrent() - g_lastAlert > 10))
         {
            SendNotification(_Symbol + " - ROMPIMENTO DE EXTREMIDADE (ALTA): " + DoubleToString(currentPrice, _Digits));
            g_lastAlert = TimeCurrent();
            g_alertedHigh = true;
         }
      }
      else
      {
         g_alertedHigh = false; // Rearma quando o preço retorna
      }
      
      // Alerta de Rompimento Inferior
      if(currentPrice < g_lowestProj)
      {
         if(!g_alertedLow && (TimeCurrent() - g_lastAlert > 10))
         {
            SendNotification(_Symbol + " - ROMPIMENTO DE EXTREMIDADE (BAIXA): " + DoubleToString(currentPrice, _Digits));
            g_lastAlert = TimeCurrent();
            g_alertedLow = true;
         }
      }
      else
      {
         g_alertedLow = false; // Rearma quando o preço retorna
      }
   }
   return(rates_total);
}
//+------------------------------------------------------------------+
