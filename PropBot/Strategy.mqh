//+------------------------------------------------------------------+
//| Strategy.mqh - clase base de estrategia independiente             |
//| Cada estrategia: su magic, sus límites diarios, su estado y su    |
//| gestión de posiciones. Solo comparte con las demás el guardián    |
//| de cuenta (que protege las reglas de la firma).                   |
//+------------------------------------------------------------------+
#ifndef PB_STRATEGY_MQH
#define PB_STRATEGY_MQH

#include "Core.mqh"
#include "Guard.mqh"

class CStrategy
{
public:
   int      id;
   string   name;
   long     magic;
   bool     enabled;
   double   riskMult;        // multiplicador de riesgo propio (modo %)
   int      maxTradesDay;
   int      maxConsecLoss;
   int      tradesToday;
   int      consecLoss;
   datetime dayKey;
   int      timeStopNY;      // minutos NY para cierre por tiempo (0 = sin cierre)
   string   sessMask;        // sesiones donde esta estrategia puede abrir: F, L, N

   CStrategy()
   {
      sessMask = "FLN";
      id = 0; name = ""; magic = 0; enabled = true; riskMult = 1.0;
      maxTradesDay = 2; maxConsecLoss = 3; tradesToday = 0; consecLoss = 0;
      dayKey = 0; timeStopNY = 0;
   }
   virtual ~CStrategy() {}

   virtual void OnNewBar() {}
   virtual void OnNewDay() {}

   void Setup(int id_, string nm, bool en, double rm, int maxT, int maxL)
   {
      id = id_; name = nm; enabled = en; riskMult = rm;
      maxTradesDay = maxT; maxConsecLoss = maxL;
      magic = PB_MAGIC_BASE + id_;
   }

   void CheckDay()
   {
      datetime dk = TradingDayStartSrv(TimeCurrent());
      if(dk != dayKey)
      {
         dayKey = dk;
         tradesToday = 0;
         consecLoss = 0;
         OnNewDay();
      }
   }

   string GvKey(string k) { return "PB_" + IntegerToString(magic) + "_" + _Symbol + "_" + k; }

   bool HasPosition()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) == magic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
      return false;
   }

   //--- ¿el objetivo está del lado correcto y cumple la relación R:R mínima?
   bool RRok(ENUM_ORDER_TYPE side, double entry, double sl, double tp, double minRR)
   {
      double risk = MathAbs(entry - sl);
      if(risk <= 0.0) return false;
      if(side == ORDER_TYPE_BUY  && (tp <= entry || sl >= entry)) return false;
      if(side == ORDER_TYPE_SELL && (tp >= entry || sl <= entry)) return false;
      return (MathAbs(tp - entry) / risk >= minRR);
   }

   double CalcLots(double dist)
   {
      double lots;
      if(CFG.lotMode == LOT_FIXED)
         lots = IsGold() ? CFG.lotGold : CFG.lotFx;
      else
      {
         double riskMoney = CFG.initialBalance * CFG.riskPct / 100.0 * riskMult;
         double perLot = MoneyForDistance(dist, 1.0);
         if(perLot <= 0.0) return 0.0;
         lots = riskMoney / perLot;
      }
      return NormVol(lots);
   }

   //--- Abre una operación a mercado con SL, TP final (tp2), objetivo parcial (tp1) y trailing opcional
   bool Execute(ENUM_ORDER_TYPE side, double sl, double tp1, double tp2, double trailAtr, string cmt)
   {
      if(!enabled) return false;
      if(tradesToday >= maxTradesDay || consecLoss >= maxConsecLoss) return false;
      if(HasPosition()) return false;
      if(!InSessionMask(sessMask)) return false;   // solo Frankfurt / Londres / Nueva York
      if(NewsBlocked()) return false;

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double entry = (side == ORDER_TYPE_BUY) ? ask : bid;
      double dist = MathAbs(entry - sl);
      if(dist <= 0.0) return false;
      if(side == ORDER_TYPE_BUY  && sl >= entry) return false;
      if(side == ORDER_TYPE_SELL && sl <= entry) return false;

      //--- spread y distancia mínima del broker
      if((ask - bid) > CFG.maxSpreadPctStop / 100.0 * dist) return false;
      long stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist = (double)stopsLvl * _Point;
      if(dist < minDist) return false;

      //--- objetivos válidos
      if(tp1 > 0.0)
      {
         bool bad = (side == ORDER_TYPE_BUY) ? (tp1 <= entry) : (tp1 >= entry);
         if(bad) tp1 = 0.0;
      }
      if(tp2 > 0.0)
      {
         bool bad2 = (side == ORDER_TYPE_BUY) ? (tp2 <= entry) : (tp2 >= entry);
         if(bad2) return false;
         if(MathAbs(tp2 - entry) < minDist) tp2 = 0.0;
      }

      double lots = CalcLots(dist);
      if(lots <= 0.0) return false;
      double risk = MoneyForDistance(dist, lots);

      string why = "";
      if(!GuardAllows(risk, why))
      {
         PrintFormat("PropBot [%s %s] operación bloqueada: %s (riesgo %.2f)", name, _Symbol, why, risk);
         return false;
      }

      g_trade.SetExpertMagicNumber((ulong)magic);
      g_trade.SetDeviationInPoints(30);
      g_trade.SetTypeFillingBySymbol(_Symbol);
      double slN  = NormalizeDouble(sl, _Digits);
      double tpN  = (tp2 > 0.0) ? NormalizeDouble(tp2, _Digits) : 0.0;
      bool ok = (side == ORDER_TYPE_BUY) ? g_trade.Buy(lots, _Symbol, 0.0, slN, tpN, cmt)
                                         : g_trade.Sell(lots, _Symbol, 0.0, slN, tpN, cmt);
      if(ok)
      {
         tradesToday++;
         GlobalVariableSet(GvKey("TP1"), tp1);
         GlobalVariableSet(GvKey("DONE"), 0.0);
         GlobalVariableSet(GvKey("TRAIL"), trailAtr);
         PrintFormat("PropBot [%s %s] %s %.2f lotes SL %.5f TP1 %.5f TP2 %.5f riesgo %.2f",
                     name, _Symbol, (side == ORDER_TYPE_BUY ? "COMPRA" : "VENTA"), lots, slN, tp1, tpN, risk);
      }
      else
         PrintFormat("PropBot [%s %s] error al enviar orden: %d %s", name, _Symbol, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return ok;
   }

   //--- Gestión de posiciones de esta estrategia (parcial en TP1, equilibrio, trailing, cierre por tiempo)
   void Manage()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

         long   type = PositionGetInteger(POSITION_TYPE);
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl   = PositionGetDouble(POSITION_SL);
         double tp   = PositionGetDouble(POSITION_TP);
         double vol  = PositionGetDouble(POSITION_VOLUME);
         datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
         double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double px   = (type == POSITION_TYPE_BUY) ? bid : ask;

         g_trade.SetExpertMagicNumber((ulong)magic);

         //--- cierre por tiempo
         if(timeStopNY > 0)
         {
            int nowM = NYMin(TimeCurrent());
            int openM = NYMin(ot);
            if(nowM >= timeStopNY && openM < timeStopNY)
            {
               g_trade.PositionClose(ticket);
               continue;
            }
         }

         string kT1 = GvKey("TP1"), kDn = GvKey("DONE"), kTr = GvKey("TRAIL");
         double tp1   = GlobalVariableCheck(kT1) ? GlobalVariableGet(kT1) : 0.0;
         bool   done  = (GlobalVariableCheck(kDn) && GlobalVariableGet(kDn) > 0.0);
         double trail = GlobalVariableCheck(kTr) ? GlobalVariableGet(kTr) : 0.0;

         //--- objetivo parcial + equilibrio
         if(tp1 > 0.0 && !done)
         {
            bool hit = (type == POSITION_TYPE_BUY) ? (px >= tp1) : (px <= tp1);
            if(hit)
            {
               double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double half = NormVol(vol * 0.5);
               if(half >= vmin && (vol - half) >= vmin - 1e-9)
                  g_trade.PositionClosePartial(ticket, half);
               if(PositionSelectByTicket(ticket))
               {
                  double curSl = PositionGetDouble(POSITION_SL);
                  bool better = (type == POSITION_TYPE_BUY) ? (open > curSl) : (curSl <= 0.0 || open < curSl);
                  if(better) g_trade.PositionModify(ticket, NormalizeDouble(open, _Digits), tp);
               }
               GlobalVariableSet(kDn, 1.0);
               continue;
            }
         }

         //--- trailing tras el parcial
         if(done && trail > 0.0)
         {
            double atr = ATR(PERIOD_M5);
            if(atr > 0.0)
            {
               double nsl = (type == POSITION_TYPE_BUY) ? (bid - trail * atr) : (ask + trail * atr);
               bool improve = (type == POSITION_TYPE_BUY) ? (nsl > sl + _Point) : (sl <= 0.0 || nsl < sl - _Point);
               if(improve) g_trade.PositionModify(ticket, NormalizeDouble(nsl, _Digits), tp);
            }
         }
      }
   }
};

#endif
