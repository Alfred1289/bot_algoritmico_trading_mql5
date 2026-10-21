//+------------------------------------------------------------------+
//| PropBot.mq5 - OPCIÓN TODO-EN-UNO                                  |
//| Los 6 playbooks en un solo EA (cada uno independiente).           |
//| Si prefieres un robot por playbook, usa PB_P1 ... PB_P6.          |
//| Adjuntar al gráfico M5. Probar primero en demo.                   |
//| Código sin compilar ni probar en MetaEditor: ver README.          |
//+------------------------------------------------------------------+
#property copyright "PropBot"
#property version   "1.10"
#property description "6 playbooks independientes en un solo EA + guardian de cuenta de fondeo"

#include "Common.mqh"
#include "S1_Rule80.mqh"
#include "S2_Vwap.mqh"
#include "S3_Sweep.mqh"
#include "S4_Absorb.mqh"
#include "S5_Orb.mqh"
#include "S6_Wyckoff.mqh"

input group "=== P1 Regla del 80% ==="
input bool   InpS1_On            = true;
input double InpS1_Risk          = 1.0;
input int    InpS1_MaxTrades     = 1;
input int    InpS1_MaxLoss       = 2;
input string InpS1_Sess          = "FLN";   // Sesiones: F=Frankfurt L=Londres N=Nueva York

input group "=== P2 VWAP bandas / AVWAP ==="
input bool   InpS2_On            = true;
input double InpS2_Risk          = 1.0;
input int    InpS2_MaxTrades     = 2;
input int    InpS2_MaxLoss       = 2;
input string InpS2_Sess          = "FLN";

input group "=== P3 Sweep de liquidez Londres ==="
input bool   InpS3_On            = true;
input double InpS3_Risk          = 1.0;
input int    InpS3_MaxTrades     = 2;
input int    InpS3_MaxLoss       = 2;
input string InpS3_Sess          = "FL";    // Frankfurt y Londres

input group "=== P4 Absorción (aproximada con ticks) ==="
input bool   InpS4_On            = false;   // DESACTIVADO por defecto
input double InpS4_Risk          = 0.5;
input int    InpS4_MaxTrades     = 2;
input int    InpS4_MaxLoss       = 2;
input string InpS4_Sess          = "FLN";

input group "=== P5 Opening Range / IB ==="
input bool   InpS5_On            = true;
input double InpS5_Risk          = 1.0;
input int    InpS5_MaxTrades     = 2;
input int    InpS5_MaxLoss       = 2;
input string InpS5_Sess          = "FLN";

input group "=== P6 Spring / Upthrust ==="
input bool   InpS6_On            = true;
input double InpS6_Risk          = 1.0;
input int    InpS6_MaxTrades     = 2;
input int    InpS6_MaxLoss       = 2;
input string InpS6_Sess          = "FLN";

#define PB_NSTRAT 6
CStrategy *g_strat[PB_NSTRAT];

//+------------------------------------------------------------------+
int OnInit()
{
   if(!PB_InitConfig()) return INIT_PARAMETERS_INCORRECT;

   g_strat[0] = new CS1Rule80();
   g_strat[0].Setup(1, "P1 Regla80",   InpS1_On, InpS1_Risk, InpS1_MaxTrades, InpS1_MaxLoss);
   g_strat[1] = new CS2Vwap();
   g_strat[1].Setup(2, "P2 VWAP",      InpS2_On, InpS2_Risk, InpS2_MaxTrades, InpS2_MaxLoss);
   g_strat[2] = new CS3Sweep();
   g_strat[2].Setup(3, "P3 Sweep",     InpS3_On, InpS3_Risk, InpS3_MaxTrades, InpS3_MaxLoss);
   g_strat[3] = new CS4Absorb();
   g_strat[3].Setup(4, "P4 Absorcion", InpS4_On, InpS4_Risk, InpS4_MaxTrades, InpS4_MaxLoss);
   g_strat[4] = new CS5Orb();
   g_strat[4].Setup(5, "P5 ORB",       InpS5_On, InpS5_Risk, InpS5_MaxTrades, InpS5_MaxLoss);
   g_strat[5] = new CS6Wyckoff();
   g_strat[5].Setup(6, "P6 Wyckoff",   InpS6_On, InpS6_Risk, InpS6_MaxTrades, InpS6_MaxLoss);

   string masks[PB_NSTRAT];
   masks[0] = InpS1_Sess; masks[1] = InpS2_Sess; masks[2] = InpS3_Sess;
   masks[3] = InpS4_Sess; masks[4] = InpS5_Sess; masks[5] = InpS6_Sess;
   for(int i = 0; i < PB_NSTRAT; i++)
   {
      StringToUpper(masks[i]);
      g_strat[i].sessMask = masks[i];
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   for(int i = 0; i < PB_NSTRAT; i++)
      if(CheckPointer(g_strat[i]) == POINTER_DYNAMIC) { delete g_strat[i]; g_strat[i] = NULL; }
   Comment("");
}

void OnTick()
{
   PB_TickCommon();
   for(int i = 0; i < PB_NSTRAT; i++)
   {
      g_strat[i].CheckDay();
      g_strat[i].Manage();
   }
   if(PB_NewBar())
   {
      RefreshLevels();
      if(LV.ok && !HardLocked() && !DayLocked())
         for(int i = 0; i < PB_NSTRAT; i++)
            g_strat[i].OnNewBar();
   }
   PB_Dashboard("PropBot todo-en-uno", g_strat, PB_NSTRAT);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   for(int i = 0; i < PB_NSTRAT; i++)
   {
      double pr;
      if(PB_ParseDeal(trans, g_strat[i].magic, pr))
      {
         if(pr > 0.0)      g_strat[i].consecLoss = 0;
         else if(pr < 0.0) g_strat[i].consecLoss++;
      }
   }
}
