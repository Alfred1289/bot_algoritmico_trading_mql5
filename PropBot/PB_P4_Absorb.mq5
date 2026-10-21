//+------------------------------------------------------------------+
//| PB_P4.mq5 - P4 Absorcion (aprox. con ticks)
//| Absorción con delta aproximado por ticks. DESACTIVADO por defecto.
//| EA INDEPENDIENTE: solo este playbook (magic 880004). Comparte con los
//| demás EAs únicamente el guardián de cuenta (variables globales del
//| terminal). Adjuntar al gráfico M5 del símbolo deseado.
//+------------------------------------------------------------------+
#property copyright "PropBot"
#property version   "1.10"
#property description "P4 Absorcion (aprox. con ticks) - EA independiente con guardian de cuenta"

#include "Common.mqh"
#include "S4_Absorb.mqh"

input group "=== P4 Absorcion (aprox. con ticks) ==="
input bool   InpS_On         = false;
input double InpS_Risk       = 0.5;     // multiplicador de riesgo (solo modo %)
input int    InpS_MaxTrades  = 2;       // operaciones máximas por día
input int    InpS_MaxLoss    = 2;       // pérdidas seguidas que pausan el día
input string InpS_Sess       = "FLN";   // Sesiones: F=Frankfurt L=Londres N=Nueva York

CStrategy *g_arr[1];

int OnInit()
{
   if(!PB_InitConfig()) return INIT_PARAMETERS_INCORRECT;
   g_arr[0] = new CS4Absorb();
   g_arr[0].Setup(4, "P4 Absorcion", InpS_On, InpS_Risk, InpS_MaxTrades, InpS_MaxLoss);
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
   PB_Dashboard("P4 Absorcion", g_arr, 1);
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
