//+------------------------------------------------------------------+
//| S1_Rule80.mqh - Playbook 1: Regla del 80% (rotación de valor)     |
//+------------------------------------------------------------------+
#ifndef PB_S1_MQH
#define PB_S1_MQH

#include "Strategy.mqh"

class CS1Rule80 : public CStrategy
{
public:
   bool done;

   CS1Rule80() { done = false; timeStopNY = 720; }   // cierre por tiempo 12:00 NY
   virtual void OnNewDay() { done = false; }

   virtual void OnNewBar()
   {
      if(!enabled || done || !LV.ok || HasPosition()) return;
      datetime now = TimeCurrent();
      int m = NYMin(now);
      int openMin = IsGold() ? 500 : 180;                 // 08:20 NY (oro) o 03:00 NY (divisas)
      if(m < openMin + 30 || m > openMin + 240) return;

      double atrD = ATR(PERIOD_D1);
      double a30  = ATR(PERIOD_M30);
      if(atrD <= 0.0 || a30 <= 0.0) return;

      datetime openT = NYClockToSrv(now, openMin);
      int sh = iBarShift(_Symbol, PERIOD_M5, openT, false);
      if(sh < 0) return;
      double openPx = iOpen(_Symbol, PERIOD_M5, sh);

      double vaW = LV.vah - LV.val;
      if(vaW < 0.3 * atrD || vaW > 0.9 * atrD) return;           // ancho del área de valor
      if(MathAbs(openPx - LV.yC) > 0.6 * atrD) return;           // gap/deriva excesiva
      bool above = (openPx > LV.vah);
      bool below = (openPx < LV.val);
      if(!above && !below) return;
      if(openPx > LV.yH || openPx < LV.yL) return;                // apertura dentro del rango de ayer

      //--- dos cierres M30 consecutivos dentro del área de valor (el anterior, fuera)
      double c1 = iClose(_Symbol, PERIOD_M30, 1);
      double c2 = iClose(_Symbol, PERIOD_M30, 2);
      double c3 = iClose(_Symbol, PERIOD_M30, 3);
      bool in1 = (c1 <= LV.vah && c1 >= LV.val);
      bool in2 = (c2 <= LV.vah && c2 >= LV.val);
      bool out3 = above ? (c3 > LV.vah) : (c3 < LV.val);
      if(!(in1 && in2 && out3)) return;

      //--- extremo alcanzado desde la apertura
      double sl;
      ENUM_ORDER_TYPE side;
      double entry;
      if(above)
      {
         int ih = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, sh + 1, 0);
         double ex = iHigh(_Symbol, PERIOD_M5, ih);
         sl = ex + 0.2 * a30;
         side = ORDER_TYPE_SELL;
         entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      else
      {
         int il = iLowest(_Symbol, PERIOD_M5, MODE_LOW, sh + 1, 0);
         double ex = iLow(_Symbol, PERIOD_M5, il);
         sl = ex - 0.2 * a30;
         side = ORDER_TYPE_BUY;
         entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      }
      double dist = MathAbs(entry - sl);
      if(dist > 1.5 * a30) return;

      double tp1 = LV.poc;
      double tp2 = above ? LV.val : LV.vah;
      if(!RRok(side, entry, sl, tp2, 1.5)) return;

      if(Execute(side, sl, tp1, tp2, 0.0, "S1 Regla80")) done = true;
   }
};

#endif
