//+------------------------------------------------------------------+
//| S3_Sweep.mqh - Playbook 3: barrida de liquidez en Londres         |
//+------------------------------------------------------------------+
#ifndef PB_S3_MQH
#define PB_S3_MQH

#include "Strategy.mqh"

class CS3Sweep : public CStrategy
{
public:
   bool doneHigh, doneLow;

   CS3Sweep() { doneHigh = false; doneLow = false; timeStopNY = 600; }   // cierre por tiempo 10:00 NY
   virtual void OnNewDay() { doneHigh = false; doneLow = false; }

   virtual void OnNewBar()
   {
      if(!enabled || !LV.ok || HasPosition()) return;
      int m = NYMin(TimeCurrent());
      if(m < 120 || m > 360) return;                         // 02:00-06:00 NY
      if(LV.aH <= 0.0 || LV.aL <= 0.0) return;

      double atrD = ATR(PERIOD_D1);
      double a15  = ATR(PERIOD_M15);
      if(atrD <= 0.0 || a15 <= 0.0) return;
      double asiaW = LV.aH - LV.aL;
      if(asiaW < 0.2 * atrD || asiaW > 0.6 * atrD) return;   // rango asiático útil

      MqlRates r[];
      if(!Rates(PERIOD_M5, 12, r)) return;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double mid = (LV.aH + LV.aL) / 2.0;

      //--- barrida de máximos (venta)
      if(!doneHigh)
      {
         double lv[2];
         lv[0] = LV.aH;
         lv[1] = LV.yH;
         for(int k = 0; k < 2; k++)
         {
            double L = lv[k];
            double ex = 0.0;
            for(int i = 1; i <= 6; i++) ex = MathMax(ex, r[i].high);
            bool pierced = (ex > L + 0.1 * a15 && ex < L + 1.0 * a15);
            if(!pierced) continue;
            if(r[1].close < L && r[1].close < r[2].low)
            {
               double sl = ex + 0.1 * a15;
               if(MathAbs(sl - bid) > 1.0 * a15) continue;
               if(!RRok(ORDER_TYPE_SELL, bid, sl, LV.aL, 1.5)) continue;
               if(Execute(ORDER_TYPE_SELL, sl, mid, LV.aL, 0.0, "S3 sweep alto")) { doneHigh = true; return; }
            }
         }
      }
      //--- barrida de mínimos (compra)
      if(!doneLow)
      {
         double lw[2];
         lw[0] = LV.aL;
         lw[1] = LV.yL;
         for(int k = 0; k < 2; k++)
         {
            double L = lw[k];
            double ex = DBL_MAX;
            for(int i = 1; i <= 6; i++) ex = MathMin(ex, r[i].low);
            bool pierced = (ex < L - 0.1 * a15 && ex > L - 1.0 * a15);
            if(!pierced) continue;
            if(r[1].close > L && r[1].close > r[2].high)
            {
               double sl = ex - 0.1 * a15;
               if(MathAbs(ask - sl) > 1.0 * a15) continue;
               if(!RRok(ORDER_TYPE_BUY, ask, sl, LV.aH, 1.5)) continue;
               if(Execute(ORDER_TYPE_BUY, sl, mid, LV.aH, 0.0, "S3 sweep bajo")) { doneLow = true; return; }
            }
         }
      }
   }
};

#endif
