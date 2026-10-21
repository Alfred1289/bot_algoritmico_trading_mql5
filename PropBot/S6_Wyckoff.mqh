//+------------------------------------------------------------------+
//| S6_Wyckoff.mqh - Playbook 6: Spring y Upthrust en rangos H1       |
//+------------------------------------------------------------------+
#ifndef PB_S6_MQH
#define PB_S6_MQH

#include "Strategy.mqh"

class CS6Wyckoff : public CStrategy
{
public:
   bool     doneBuy, doneSell;
   datetime lastM15;

   CS6Wyckoff() { doneBuy = false; doneSell = false; lastM15 = 0; timeStopNY = 900; }   // cierre 15:00 NY
   virtual void OnNewDay() { doneBuy = false; doneSell = false; }

   virtual void OnNewBar()
   {
      if(!enabled || !LV.ok || HasPosition()) return;
      datetime t15 = iTime(_Symbol, PERIOD_M15, 0);
      if(t15 == lastM15) return;               // solo al abrir cada barra M15
      lastM15 = t15;

      int m = NYMin(TimeCurrent());
      if(m < 180 || m >= 900) return;
      double atrD = ATR(PERIOD_D1);
      double a15  = ATR(PERIOD_M15);
      if(atrD <= 0.0 || a15 <= 0.0) return;

      int rb = IsGold() ? 48 : 20;             // antigüedad mínima del rango (barras H1)
      MqlRates h[];
      if(!Rates(PERIOD_H1, rb + 75, h)) return;

      //--- rango: barras H1 2..rb+1
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = 2; i <= rb + 1; i++)
      {
         hi = MathMax(hi, h[i].high);
         lo = MathMin(lo, h[i].low);
      }
      if(hi - lo >= 1.5 * atrD) return;
      double tol = 0.1 * atrD;
      int th = 0, tl = 0;
      for(int i = 2; i <= rb + 1; i++)
      {
         if(h[i].high >= hi - tol) th++;
         if(h[i].low <= lo + tol) tl++;
      }
      if(th < 2 || tl < 2) return;

      //--- media de 50 casi plana
      double s0 = 0.0, s20 = 0.0;
      for(int i = 1; i <= 50; i++) { s0 += h[i].close; s20 += h[i + 20].close; }
      s0 /= 50.0;
      s20 /= 50.0;
      if(MathAbs(s0 - s20) >= 0.2 * atrD) return;

      //--- un cierre H1 fuera del rango anula el patrón
      if(h[1].close > hi || h[1].close < lo) return;

      MqlRates q[];
      if(!Rates(PERIOD_M15, 30, q)) return;
      double avgv = AvgTickVol(q, 5, 20);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double midR = (hi + lo) / 2.0;

      for(int s = 2; s <= 4; s++)
      {
         bool lowVol = ((double)q[s].tick_volume < 1.2 * avgv);
         //--- spring (compra)
         if(!doneBuy && lowVol && q[s].low < lo - 0.1 * a15 && q[s].low > lo - 0.6 * a15
            && q[1].close > lo && q[1].close > q[s].high)
         {
            double sl = q[s].low - 0.1 * a15;
            double tp2 = hi - 0.1 * atrD;
            if(RRok(ORDER_TYPE_BUY, ask, sl, tp2, 2.0))
               if(Execute(ORDER_TYPE_BUY, sl, midR, tp2, 0.0, "S6 spring")) { doneBuy = true; return; }
         }
         //--- upthrust (venta)
         if(!doneSell && lowVol && q[s].high > hi + 0.1 * a15 && q[s].high < hi + 0.6 * a15
            && q[1].close < hi && q[1].close < q[s].low)
         {
            double sl = q[s].high + 0.1 * a15;
            double tp2 = lo + 0.1 * atrD;
            if(RRok(ORDER_TYPE_SELL, bid, sl, tp2, 2.0))
               if(Execute(ORDER_TYPE_SELL, sl, midR, tp2, 0.0, "S6 upthrust")) { doneSell = true; return; }
         }
      }
   }
};

#endif
