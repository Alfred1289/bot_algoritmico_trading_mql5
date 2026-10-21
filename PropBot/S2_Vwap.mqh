//+------------------------------------------------------------------+
//| S2_Vwap.mqh - Playbook 2: VWAP con bandas (reversión) y           |
//| Anchored VWAP (continuación)                                      |
//+------------------------------------------------------------------+
#ifndef PB_S2_MQH
#define PB_S2_MQH

#include "Strategy.mqh"

class CS2Vwap : public CStrategy
{
public:
   int touchUp, touchDn;

   CS2Vwap() { touchUp = 0; touchDn = 0; timeStopNY = 720; }
   virtual void OnNewDay() { touchUp = 0; touchDn = 0; }

   virtual void OnNewBar()
   {
      if(!enabled || !LV.ok || LV.sigma <= 0.0 || HasPosition()) return;
      int m = NYMin(TimeCurrent());
      if(m < 180 || m >= 720) return;                 // 03:00-12:00 NY
      if(VW_HIST[6] <= 0.0) return;

      double atrD = ATR(PERIOD_D1);
      double a5   = ATR(PERIOD_M5);
      if(atrD <= 0.0 || a5 <= 0.0) return;
      MqlRates r[];
      if(!Rates(PERIOD_M5, 60, r)) return;

      double vw = LV.vwap;
      double slope = VW_HIST[0] - VW_HIST[6];         // pendiente en 30 minutos
      int cross = 0;
      for(int i = 1; i < 12; i++)
      {
         bool s1 = (r[i].close > vw);
         bool s2 = (r[i + 1].close > vw);
         if(s1 != s2) cross++;
      }
      bool above6 = true, below6 = true;
      for(int i = 1; i <= 6; i++)
      {
         if(r[i].close <= vw) above6 = false;
         if(r[i].close >= vw) below6 = false;
      }
      bool modeA = (cross >= 2 && MathAbs(slope) < 0.1 * atrD);
      bool modeB = ((above6 && slope > 0.05 * atrD) || (below6 && slope < -0.05 * atrD));

      if(modeA)      ModeA(r, a5);
      else if(modeB) ModeB(r, a5, atrD, above6);
   }

   //--- Modo A: reversión en la banda de ±2 desviaciones
   void ModeA(MqlRates &r[], double a5)
   {
      double vw = LV.vwap, sg = LV.sigma;
      double up2 = vw + 2.0 * sg, dn2 = vw - 2.0 * sg;
      double avgv = AvgTickVol(r, 2, 20);
      bool volOk = ((double)r[1].tick_volume > 1.2 * avgv);   // proxy de absorción: pico de volumen de ticks
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(r[1].high >= up2)
      {
         touchUp++;
         if(touchUp <= 2 && r[1].close < up2 && volOk)
         {
            double sl = r[1].high + 0.5 * a5;
            if(RRok(ORDER_TYPE_SELL, bid, sl, vw, 1.5))
               if(Execute(ORDER_TYPE_SELL, sl, vw + sg, vw, 0.0, "S2A")) return;
         }
      }
      if(r[1].low <= dn2)
      {
         touchDn++;
         if(touchDn <= 2 && r[1].close > dn2 && volOk)
         {
            double sl = r[1].low - 0.5 * a5;
            if(RRok(ORDER_TYPE_BUY, ask, sl, vw, 1.5))
               Execute(ORDER_TYPE_BUY, sl, vw - sg, vw, 0.0, "S2A");
         }
      }
   }

   //--- Modo B: continuación en el retroceso al VWAP anclado al swing
   void ModeB(MqlRates &r[], double a5, double atrD, bool up)
   {
      if((LV.dayHi - LV.dayLo) >= 1.0 * atrD) return;           // movimiento ya agotado
      int anchor = 1;
      if(up)
      {
         double lo = r[1].low;
         for(int i = 1; i <= 36; i++) if(r[i].low < lo) { lo = r[i].low; anchor = i; }
      }
      else
      {
         double hi = r[1].high;
         for(int i = 1; i <= 36; i++) if(r[i].high > hi) { hi = r[i].high; anchor = i; }
      }
      if(anchor < 4) return;
      double av = AnchoredVwapSeries(r, anchor, 1);
      if(av <= 0.0) return;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(up)
      {
         if(r[1].low <= av + 0.05 * a5 && r[1].close > av && r[1].close > r[1].open)
         {
            double sl = MathMin(av, r[1].low) - 0.5 * a5;
            double d = ask - sl;
            if(d <= 0.0 || d > 1.2 * a5) return;
            Execute(ORDER_TYPE_BUY, sl, ask + d, 0.0, 1.0, "S2B");
         }
      }
      else
      {
         if(r[1].high >= av - 0.05 * a5 && r[1].close < av && r[1].close < r[1].open)
         {
            double sl = MathMax(av, r[1].high) + 0.5 * a5;
            double d = sl - bid;
            if(d <= 0.0 || d > 1.2 * a5) return;
            Execute(ORDER_TYPE_SELL, sl, bid - d, 0.0, 1.0, "S2B");
         }
      }
   }
};

#endif
