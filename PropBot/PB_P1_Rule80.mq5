//+------------------------------------------------------------------+
//| PB_P1.mq5 - P1 Regla del 80%
//| Rotación de valor con perfil de volumen. Mejor candidato: EURUSD.
//| EA INDEPENDIENTE: solo este playbook (magic 880001). Comparte con los
//| demás EAs únicamente el guardián de cuenta (variables globales del
//| terminal). Adjuntar al gráfico M5 del símbolo deseado.
//+------------------------------------------------------------------+
#property copyright "PropBot"
#property version   "1.10"
#property description "P1 Regla del 80% - EA independiente con guardian de cuenta"

#include "Common.mqh"
#include "S1_Rule80.mqh"

input group "=== P1 Regla del 80% ==="
input bool   InpS_On         = true;
input double InpS_Risk       = 1.0;     // multiplicador de riesgo (solo modo %)
input int    InpS_MaxTrades  = 1;       // operaciones máximas por día
input int    InpS_MaxLoss    = 2;       // pérdidas seguidas que pausan el día
input string InpS_Sess       = "FLN";   // Sesiones: F=Frankfurt L=Londres N=Nueva York

CStrategy *g_arr[1];

int OnInit()
{
   if(!PB_InitConfig()) return INIT_PARAMETERS_INCORRECT;
   g_arr[0] = new CS1Rule80();
   g_arr[0].Setup(1, "P1 Regla80", InpS_On, InpS_Risk, InpS_MaxTrades, InpS_MaxLoss);
   string m = InpS_Sess;
   StringToUpper(m);
   g_arr[0].sessMask = m;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(CheckPointer(g_arr[0]) == POINTER_DYNAMIC) { delete g_arr[0]; g_arr[0] = NULL; }
   Comment("");
}

void OnTick()
{
   PB_TickCommon();
   g_arr[0].CheckDay();
   g_arr[0].Manage();
   if(PB_NewBar())
   {
      RefreshLevels();
      if(LV.ok && !HardLocked() && !DayLocked())
         g_arr[0].OnNewBar();
   }
   PB_Dashboard("P1 Regla80", g_arr, 1);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   double pr;
   if(PB_ParseDeal(trans, g_arr[0].magic, pr))
   {
      if(pr > 0.0)      g_arr[0].consecLoss = 0;
      else if(pr < 0.0) g_arr[0].consecLoss++;
   }
}
