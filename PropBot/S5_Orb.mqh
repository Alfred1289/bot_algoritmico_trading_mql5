//+------------------------------------------------------------------+
//| S5_Orb.mqh - Playbook 5: Opening Range / Initial Balance          |
//| Modo A: ruptura con volumen. Modo B: ruptura fallida.             |
//+------------------------------------------------------------------+
#ifndef PB_S5_MQH
#define PB_S5_MQH

#include "Strategy.mqh"

class CS5Orb : public CStrategy
{
public:
   bool   ibOk, ibValid, doneA, doneB;
   double ibH, ibL;

   CS5Orb() { Reset(); timeStopNY = 720; }
   void Reset() { ibOk = false; ibValid = false; doneA = false; doneB = false; ibH = 0.0; ibL = 0.0; }
   virtual void OnNewDay() { Reset(); }

   virtual void OnNewBar()
   {
      if(!enabled || HasPosition()) return;
      datetime now = TimeCurrent();
      int m = NYMin(now);
      int ibS = IsGold() ? 500 : 180;        // 08:20 NY (oro) o 03:00 NY (divisas)
      int ibE = ibS + 60;
      if(m < ibE || m > ibE + 240) return;

      double atrD = ATR(PERIOD_D1);
      double a5   = ATR(PERIOD_M5);
      double a15  = ATR(PERIOD_M15);
      if(atrD <= 0.0 || a5 <= 0.0 || a15 <= 0.0) return;

      if(!ibOk)
      {
         datetime ts = NYClockToSrv(now, ibS);
         datetime te = NYClockToSrv(now, ibE);
         MqlRates b[];
         int n = CopyRates(_Symbol, PERIOD_M5, ts, te - 1, b);
         if(n < 8) return;
         ibH = b[0].high;
         ibL = b[0].low;
         for(int i = 0; i < n; i++)
         {
            ibH = MathMax(ibH, b[i].high);
            ibL = MathMin(ibL, b[i].low);
         }
         ibOk = true;
         double w0 = ibH - ibL;
         ibValid = (w0 >= 0.25 * atrD && w0 <= 0.8 * atrD);
      }
      if(!ibValid) return;

      MqlRates r[];
      if(!Rates(PERIOD_M5, 30, r)) return;
      double w   = ibH - ibL;
      double mid = (ibH + ibL) / 2.0;
      double c   = r[1].close;
      double avgv = AvgTickVol(r, 2, 20);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      //--- Modo A: ruptura con volumen a favor del VWAP
      if(!doneA && LV.ok && LV.vwap > 0.0 && (double)r[1].tick_volume > 1.5 * avgv)
      {
         if(c > ibH && c > LV.vwap)
         {
            double sl = MathMax(mid, ibH - 0.5 * a5);
            double d = ask - sl;
            if(d > 0.0 && d <= a15)
               if(Execute(ORDER_TYPE_BUY, sl, ask + w, ask + 2.0 * w, 0.0, "S5A ruptura alza")) { doneA = true; return; }
         }
         if(c < ibL && c < LV.vwap)
         {
            double sl = MathMin(mid, ibL + 0.5 * a5);
            double d = sl - bid;
            if(d > 0.0 && d <= a15)
               if(Execute(ORDER_TYPE_SELL, sl, bid - w, bid - 2.0 * w, 0.0, "S5A ruptura baja")) { doneA = true; return; }
         }
      }

      //--- Modo B: ruptura fallida (cierra fuera en las barras 2-3 y vuelve dentro en la 1)
      if(!doneB)
      {
         double exH = MathMax(r[1].high, MathMax(r[2].high, r[3].high));
         double exL = MathMin(r[1].low, MathMin(r[2].low, r[3].low));
         bool failUp = ((r[2].close > ibH || r[3].close > ibH) && c < ibH && c > ibL);
         bool failDn = ((r[2].close < ibL || r[3].close < ibL) && c > ibL && c < ibH);
         if(failUp)
         {
            double sl = exH + 0.1 * a5;
            if(RRok(ORDER_TYPE_SELL, bid, sl, ibL, 1.5))
               if(Execute(ORDER_TYPE_SELL, sl, mid, ibL, 0.0, "S5B fallida alza")) { doneB = true; return; }
         }
         if(failDn)
         {
            double sl = exL - 0.1 * a5;
            if(RRok(ORDER_TYPE_BUY, ask, sl, ibH, 1.5))
               if(Execute(ORDER_TYPE_BUY, sl, mid, ibH, 0.0, "S5B fallida baja")) { doneB = true; return; }
         }
      }
   }
};

#endif
