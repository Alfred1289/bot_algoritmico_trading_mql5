//+------------------------------------------------------------------+
//| Guard.mqh - Guardián de cuenta (reglas de la firma de fondeo)     |
//| No genera señales: solo autoriza o bloquea y cierra por límites.  |
//| Comparte estado entre instancias (gráficos) con variables         |
//| globales del terminal.                                            |
//+------------------------------------------------------------------+
#ifndef PB_GUARD_MQH
#define PB_GUARD_MQH

#include "Core.mqh"

string GvName(string k)
{
   return "PB_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + k;
}

//--- día del servidor (la firma reinicia el límite diario a las 00:00 hora de plataforma)
datetime SrvDayKey()
{
   datetime t = TimeCurrent();
   return t - (t % 86400);
}

void GuardUpdateDay()
{
   datetime dk = SrvDayKey();
   string kD = GvName("DAY");
   double stored = GlobalVariableCheck(kD) ? GlobalVariableGet(kD) : 0.0;
   if((datetime)stored != dk)
   {
      // referencia = el mayor entre balance y equity de apertura del día
      double ref = MathMax(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
      GlobalVariableSet(GvName("REF"), ref);
      GlobalVariableSet(kD, (double)dk);
   }
}

double DayRef()
{
   string k = GvName("REF");
   return GlobalVariableCheck(k) ? GlobalVariableGet(k) : AccountInfoDouble(ACCOUNT_BALANCE);
}

bool DayLocked()
{
   string k = GvName("LOCK");
   return (GlobalVariableCheck(k) && (datetime)GlobalVariableGet(k) == SrvDayKey());
}
void SetDayLock()  { GlobalVariableSet(GvName("LOCK"), (double)SrvDayKey()); }

bool HardLocked()
{
   string k = GvName("HARD");
   return (GlobalVariableCheck(k) && GlobalVariableGet(k) > 0.0);
}
void SetHardLock()   { GlobalVariableSet(GvName("HARD"), 1.0); }
void ClearHardLock() { GlobalVariableDel(GvName("HARD")); }

//--- pisos internos (en dinero de la cuenta)
double DayFloorInternal()  { return DayRef() - CFG.initialBalance * CFG.dailyStopPct / 100.0; }
double HardFloorInternal() { return CFG.initialBalance * (1.0 - CFG.maxStopPct / 100.0); }
double DayFloorFirm()      { return DayRef() - CFG.initialBalance * CFG.dailyLimitPct / 100.0; }
double HardFloorFirm()     { return CFG.initialBalance * (1.0 - CFG.maxLossPct / 100.0); }

bool IsBotMagic(long m) { return (m > PB_MAGIC_BASE && m <= PB_MAGIC_BASE + 99); }

//--- Avisos: siempre al registro; al móvil/alerta solo si está activado (o si es crítico)
void NotifyUser(string msg, bool critical = false)
{
   Print(msg);
   if(critical)
   {
      Alert(msg);
      SendNotification(msg);
   }
   else if(CFG.push)
      SendNotification(msg);
}

//--- Avisa al 50% y al 75% del tope interno (diario y máximo), una sola vez por nivel
void WarnLevel(string key, double used, string what)
{
   int lvl = (used >= 0.75) ? 2 : ((used >= 0.5) ? 1 : 0);
   string k = GvName(key);
   double stored = GlobalVariableCheck(k) ? GlobalVariableGet(k) : 0.0;
   double code = (key == "WD") ? (double)SrvDayKey() * 10.0 + (double)lvl : (double)lvl;
   if(lvl > 0 && code > stored)
   {
      GlobalVariableSet(k, code);
      NotifyUser(StringFormat("PropBot AVISO: %s al %.0f%% del tope interno", what, used * 100.0));
   }
   else if(key == "WM" && (double)lvl < stored)
      GlobalVariableSet(k, (double)lvl);
}

void GuardWarnings()
{
   static datetime lastChk = 0;
   datetime now = TimeCurrent();
   if(now - lastChk < 5) return;
   lastChk = now;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dTop = CFG.initialBalance * CFG.dailyStopPct / 100.0;
   double mTop = CFG.initialBalance * CFG.maxStopPct / 100.0;
   double dLoss = DayRef() - eq;
   double mLoss = CFG.initialBalance - eq;
   if(dTop > 0.0) WarnLevel("WD", (dLoss > 0.0) ? dLoss / dTop : 0.0, "pérdida del día");
   if(mTop > 0.0) WarnLevel("WM", (mLoss > 0.0) ? mLoss / mTop : 0.0, "pérdida máxima");
}

//--- riesgo desde el precio de apertura hasta el SL (de la posición seleccionada)
double PositionRiskFromOpen()
{
   string s = PositionGetString(POSITION_SYMBOL);
   double vol = PositionGetDouble(POSITION_VOLUME);
   double op  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl  = PositionGetDouble(POSITION_SL);
   double tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0.0) tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE);
   if(sl <= 0.0 || ts <= 0.0) return AccountInfoDouble(ACCOUNT_EQUITY) * 0.05;   // sin SL = riesgo enorme
   long type = PositionGetInteger(POSITION_TYPE);
   double dist = (type == POSITION_TYPE_BUY) ? (op - sl) : (sl - op);
   if(dist <= 0.0) return 0.0;   // SL en equilibrio o en beneficio
   return dist / ts * tv * vol;
}

//--- lo que aún se perdería desde el precio actual si salta el SL
double PositionLossToStop()
{
   string s = PositionGetString(POSITION_SYMBOL);
   double vol = PositionGetDouble(POSITION_VOLUME);
   double cur = PositionGetDouble(POSITION_PRICE_CURRENT);
   double sl  = PositionGetDouble(POSITION_SL);
   double tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0.0) tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE);
   if(sl <= 0.0 || ts <= 0.0) return AccountInfoDouble(ACCOUNT_EQUITY) * 0.05;
   long type = PositionGetInteger(POSITION_TYPE);
   double dist = (type == POSITION_TYPE_BUY) ? (cur - sl) : (sl - cur);
   if(dist <= 0.0) return 0.0;
   return dist / ts * tv * vol;
}

double OpenRiskTotal()
{
   double sum = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!IsBotMagic(PositionGetInteger(POSITION_MAGIC))) continue;
      sum += PositionRiskFromOpen();
   }
   return sum;
}

//--- equity si todas las posiciones del bot tocan su SL ahora
double StopOutEquity()
{
   double loss = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!IsBotMagic(PositionGetInteger(POSITION_MAGIC))) continue;
      loss += PositionLossToStop();
   }
   return AccountInfoDouble(ACCOUNT_EQUITY) - loss;
}

bool HasBotPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(IsBotMagic(PositionGetInteger(POSITION_MAGIC))) return true;
   }
   return false;
}

void CloseAllBot(string why)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!IsBotMagic(PositionGetInteger(POSITION_MAGIC))) continue;
      g_trade.PositionClose(t);
   }
   Print("PropBot: posiciones cerradas por guardián -> ", why);
}

//+------------------------------------------------------------------+
//| ¿Se permite abrir una operación con este riesgo (en dinero)?      |
//+------------------------------------------------------------------+
bool GuardAllows(double newRisk, string &why)
{
   GuardUpdateDay();
   if(HardLocked()) { why = "bloqueo permanente por pérdida máxima"; return false; }
   if(DayLocked())  { why = "bloqueo diario"; return false; }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayFl  = DayFloorInternal();
   double hardFl = HardFloorInternal();
   if(eq <= dayFl || eq <= hardFl) { why = "equity bajo el piso interno"; return false; }

   if(newRisk > CFG.initialBalance * CFG.maxRiskTradePct / 100.0)
   { why = "riesgo de la operación supera el tope por operación"; return false; }

   double open = OpenRiskTotal();
   if(open + newRisk > CFG.initialBalance * CFG.maxOpenRiskPct / 100.0)
   { why = "supera el riesgo abierto total"; return false; }

   double worst = StopOutEquity() - newRisk;
   if(worst <= dayFl)  { why = "si saltan los stops se rompería el piso diario interno"; return false; }
   if(worst <= hardFl) { why = "si saltan los stops se rompería el piso máximo interno"; return false; }
   return true;
}

//+------------------------------------------------------------------+
//| Se ejecuta en cada tick: cierra todo y bloquea si se tocan pisos  |
//+------------------------------------------------------------------+
void GuardEnforce()
{
   GuardUpdateDay();
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= HardFloorInternal())
   {
      if(!HardLocked())
      {
         CloseAllBot("piso máximo interno");
         SetHardLock();
         NotifyUser("PropBot CRÍTICO: pérdida máxima interna alcanzada. Todo cerrado y bot bloqueado hasta revisión manual.", true);
      }
   }
   else if(eq <= DayFloorInternal())
   {
      if(!DayLocked())
      {
         CloseAllBot("piso diario interno");
         SetDayLock();
         NotifyUser("PropBot CRÍTICO: pérdida diaria interna alcanzada. Todo cerrado; sin operaciones hasta el próximo día.", true);
      }
   }
}

string GuardStatus()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   string s = "";
   s += StringFormat("Equity %.2f | Ref. día %.2f\n", eq, DayRef());
   s += StringFormat("Piso diario interno %.2f (firma %.2f)\n", DayFloorInternal(), DayFloorFirm());
   s += StringFormat("Piso máximo interno %.2f (firma %.2f)\n", HardFloorInternal(), HardFloorFirm());
   s += StringFormat("Riesgo abierto %.2f / tope %.2f\n", OpenRiskTotal(), CFG.initialBalance * CFG.maxOpenRiskPct / 100.0);
   s += "Estado: ";
   if(HardLocked()) s += "BLOQUEO PERMANENTE";
   else if(DayLocked()) s += "BLOQUEO DIARIO";
   else s += "operando";
   return s;
}

#endif
