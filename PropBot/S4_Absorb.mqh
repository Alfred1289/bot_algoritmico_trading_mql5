//+------------------------------------------------------------------+
//| S4_Absorb.mqh - Playbook 4: absorción y agotamiento (order flow)  |
//|                                                                   |
//| IMPORTANTE: en CFD de MT5 no hay volumen real ni bid/ask por     |
//| nivel. Esta versión APROXIMA el delta con la regla del tick       |
//| (tick al alza = compra, a la baja = venta) y usa la cantidad de   |
//| ticks como volumen. Es una aproximación, no un footprint real.    |
//| Viene DESACTIVADA por defecto. Si ClusterDelta ofrece una         |
//| interfaz para MT5, reemplaza BarDelta() por su dato.              |
//+------------------------------------------------------------------+
#ifndef PB_S4_MQH
#define PB_S4_MQH

#include "Strategy.mqh"

class CS4Absorb : public CStrategy
{
public:
   CS4Absorb() { timeStopNY = 720; }

   //--- delta aproximado y volumen (nº de ticks) de una barra [t0, t1)
   bool BarDelta(datetime t0, datetime t1, double &delta, double &vol)
   {
      MqlTick tk[];
      ulong from = (ulong)t0 * 1000;
      ulong to   = (ulong)t1 * 1000 - 1;
      int n = CopyTicksRange(_Symbol, tk, COPY_TICKS_ALL, from, to);
      if(n < 5) return false;
      double last = (tk[0].bid + tk[0].ask) / 2.0;
      delta = 0.0;
      vol = (double)n;
      for(int i = 1; i < n; i++)
      {
         double mid = (tk[i].bid + tk[i].ask) / 2.0;
         if(mid > last)      delta += 1.0;
         else if(mid < last) delta -= 1.0;
         last = mid;
      }
      return true;
   }

   virtual void OnNewBar()
   {
      if(!enabled || !LV.ok || LV.sigma <= 0.0 || HasPosition()) return;
      int m = NYMin(TimeCurrent());
      if(m < 180 || m >= 720) return;
      double a5 = ATR(PERIOD_M5);
      if(a5 <= 0.0) return;
      MqlRates r[];
      if(!Rates(PERIOD_M5, 26, r)) return;

      double dl[26], vl[26], cd[26];
      ArrayInitialize(dl, 0.0);
      ArrayInitialize(vl, 0.0);
      ArrayInitialize(cd, 0.0);
      for(int i = 1; i <= 24; i++)
         if(!BarDelta(r[i].time, r[i].time + 300, dl[i], vl[i])) return;

      int a = 2;   // barra de absorción; la barra 1 es la confirmación
      double mv = 0.0, mad = 0.0;
      for(int i = 3; i <= 24; i++) { mv += vl[i]; mad += MathAbs(dl[i]); }
      mv /= 22.0;
      mad /= 22.0;
      double rng = r[a].high - r[a].low;
      if(!((vl[a] > 2.0 * mv) && (MathAbs(dl[a]) > 1.5 * mad) && (rng < 0.5 * a5))) return;

      bool sellSetup = (dl[a] > 0.0 && r[a].close <= r[a].open);   // compras agresivas que no avanzan
      bool buySetup  = (dl[a] < 0.0 && r[a].close >= r[a].open);   // ventas agresivas que no avanzan
      if(!sellSetup && !buySetup) return;

      //--- niveles relevantes
      double lv[8];
      lv[0] = LV.poc;  lv[1] = LV.vah;  lv[2] = LV.val;  lv[3] = LV.yH;
      lv[4] = LV.yL;   lv[5] = LV.vwap; lv[6] = LV.vwap + 2.0 * LV.sigma; lv[7] = LV.vwap - 2.0 * LV.sigma;
      double ext = sellSetup ? r[a].high : r[a].low;
      bool nearLvl = false;
      for(int k = 0; k < 8; k++) if(MathAbs(ext - lv[k]) <= 0.15 * a5) nearLvl = true;
      if(!nearLvl) return;

      //--- divergencia de delta acumulado
      double cum = 0.0;
      for(int i = 24; i >= 1; i--) { cum += dl[i]; cd[i] = cum; }
      double maxH = -DBL_MAX, minL = DBL_MAX, maxCd = -DBL_MAX, minCd = DBL_MAX;
      for(int i = 3; i <= 24; i++)
      {
         maxH = MathMax(maxH, r[i].high);
         minL = MathMin(minL, r[i].low);
         maxCd = MathMax(maxCd, cd[i]);
         minCd = MathMin(minCd, cd[i]);
      }
      bool diverg = sellSetup ? (r[a].high >= maxH && cd[a] < maxCd)
                           : (r[a].low <= minL && cd[a] > minCd);
      if(!diverg) return;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(sellSetup)
      {
         if(!(r[1].close < r[a].low)) return;                      // confirmación
         double sl = r[a].high + 0.05 * a5;
         double d = sl - bid;
         if(d < 0.3 * a5) { sl = bid + 0.3 * a5; d = 0.3 * a5; }
         if(d > 1.0 * a5) return;
         double tp2 = 0.0;
         for(int k = 0; k < 8; k++)
            if(lv[k] < bid - 2.0 * d && (tp2 == 0.0 || lv[k] > tp2)) tp2 = lv[k];
         if(tp2 == 0.0) return;                                    // sin objetivo con R:R >= 2
         Execute(ORDER_TYPE_SELL, sl, bid - d, tp2, 0.0, "S4 absorcion venta");
      }
      else
      {
         if(!(r[1].close > r[a].high)) return;
         double sl = r[a].low - 0.05 * a5;
         double d = ask - sl;
         if(d < 0.3 * a5) { sl = ask - 0.3 * a5; d = 0.3 * a5; }
         if(d > 1.0 * a5) return;
         double tp2 = 0.0;
         for(int k = 0; k < 8; k++)
            if(lv[k] > ask + 2.0 * d && (tp2 == 0.0 || lv[k] < tp2)) tp2 = lv[k];
         if(tp2 == 0.0) return;
         Execute(ORDER_TYPE_BUY, sl, ask + d, tp2, 0.0, "S4 absorcion compra");
      }
   }
};

#endif
