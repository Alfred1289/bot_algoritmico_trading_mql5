//+------------------------------------------------------------------+
//| Core.mqh - configuración, tiempo (NY), ATR, niveles y noticias    |
//+------------------------------------------------------------------+
#ifndef PB_CORE_MQH
#define PB_CORE_MQH

#include <Trade\Trade.mqh>

#define PB_MAGIC_BASE 880000

enum ENUM_LOT_MODE { LOT_FIXED = 0, LOT_RISK_PCT = 1 };

struct SConfig
{
   double        initialBalance;
   double        dailyLimitPct;     // regla de la firma (informativo)
   double        maxLossPct;        // regla de la firma (informativo)
   double        dailyStopPct;      // tope interno diario
   double        maxStopPct;        // tope interno de pérdida máxima
   double        maxOpenRiskPct;    // riesgo abierto total
   double        maxRiskTradePct;   // riesgo máximo por operación
   double        riskPct;           // riesgo por operación (modo %)
   ENUM_LOT_MODE lotMode;
   double        lotFx;
   double        lotGold;
   double        maxSpreadPctStop;  // spread máximo como % del stop
   bool          useNews;
   int           newsMinutes;
   bool          autoOffset;
   int           manualOffsetH;
   bool          sessF, sessL, sessN;     // sesiones activas: Frankfurt, Londres, Nueva York
   int           fS, fE, lS, lE, nS, nE;  // ventanas en minutos de Nueva York [inicio, fin)
   bool          push;                    // notificaciones push + alertas
   bool          flatOn;                  // cerrar todo al final de la última sesión
   int           flatMin;                 // minutos NY del cierre
};

SConfig CFG;
CTrade  g_trade;

//--- Niveles compartidos (se recalculan en cada barra M5 cerrada)
struct SLevels
{
   bool   ok;
   double yH, yL, yC;       // máximo, mínimo y cierre del día de trading previo
   double poc, vah, val;    // perfil del día previo (70%)
   double aH, aL;           // rango asiático (19:00-02:00 NY)
   double vwap, sigma;      // VWAP de sesión y desviación
   double dayHi, dayLo;     // rango de hoy
};
SLevels LV;
double  VW_HIST[13];       // VWAP de las últimas 13 barras M5 (0 = más reciente)

//+------------------------------------------------------------------+
bool IsGold()
{
   return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0);
}

//--- Hora: servidor -> UTC -> Nueva York (con horario de verano de EE. UU.)
int ServerOffsetSec()
{
   if(!CFG.autoOffset)
      return CFG.manualOffsetH * 3600;
   double d = (double)(TimeCurrent() - TimeGMT()) / 3600.0;
   return (int)MathRound(d) * 3600;
}

datetime NthSunday(int year, int mon, int n)
{
   MqlDateTime d;
   ZeroMemory(d);
   d.year = year;
   d.mon  = mon;
   d.day  = 1;
   datetime t = StructToTime(d);
   TimeToStruct(t, d);
   int firstSun = ((7 - d.day_of_week) % 7) + 1;
   d.day  = firstSun + (n - 1) * 7;
   d.hour = 0;
   d.min  = 0;
   d.sec  = 0;
   return StructToTime(d);
}

bool IsUsDst(datetime utc)
{
   MqlDateTime u;
   TimeToStruct(utc, u);
   datetime s = NthSunday(u.year, 3, 2) + 7 * 3600;    // 2º domingo de marzo, 02:00 EST = 07:00 UTC
   datetime e = NthSunday(u.year, 11, 1) + 6 * 3600;   // 1er domingo de noviembre, 02:00 EDT = 06:00 UTC
   return (utc >= s && utc < e);
}

datetime ServerToNY(datetime srv)
{
   datetime utc = srv - ServerOffsetSec();
   return utc + (IsUsDst(utc) ? -4 * 3600 : -5 * 3600);
}

int NYMin(datetime srv)
{
   MqlDateTime t;
   TimeToStruct(ServerToNY(srv), t);
   return t.hour * 60 + t.min;
}

//--- "HH:MM" -> minutos
int ParseHM(string s)
{
   string p[];
   if(StringSplit(s, ':', p) < 2) return 0;
   return (int)StringToInteger(p[0]) * 60 + (int)StringToInteger(p[1]);
}

//--- ¿estamos dentro de alguna de las sesiones permitidas por la máscara?
//--- mask: letras F (Frankfurt), L (Londres), N (Nueva York)
bool InSessionMask(string mask)
{
   int m = NYMin(TimeCurrent());
   if(CFG.flatOn && m >= CFG.flatMin) return false;
   if(CFG.sessF && StringFind(mask, "F") >= 0 && m >= CFG.fS && m < CFG.fE) return true;
   if(CFG.sessL && StringFind(mask, "L") >= 0 && m >= CFG.lS && m < CFG.lE) return true;
   if(CFG.sessN && StringFind(mask, "N") >= 0 && m >= CFG.nS && m < CFG.nE) return true;
   return false;
}

//--- Inicio (hora servidor) del día de trading vigente: 17:00 NY
datetime TradingDayStartSrv(datetime srv)
{
   datetime ny    = ServerToNY(srv);
   long     delta = (long)ny - (long)srv;
   long     sh    = (long)ny - 17 * 3600;
   long     fl    = sh - (sh % 86400);
   long     st    = fl + 17 * 3600;
   return (datetime)(st - delta);
}

//--- Hora de servidor correspondiente a "minutos NY" del día NY de srvRef
datetime NYClockToSrv(datetime srvRef, int minutes)
{
   datetime ny    = ServerToNY(srvRef);
   long     delta = (long)ny - (long)srvRef;
   long     mid   = (long)ny - ((long)ny % 86400);
   return (datetime)(mid + (long)minutes * 60 - delta);
}

//+------------------------------------------------------------------+
//| ATR con caché de handles                                          |
//+------------------------------------------------------------------+
int             g_atrN = 0;
ENUM_TIMEFRAMES g_atrTf[8];
int             g_atrH[8];

double ATR(ENUM_TIMEFRAMES tf, int shift = 1)
{
   int h = INVALID_HANDLE;
   for(int i = 0; i < g_atrN; i++)
      if(g_atrTf[i] == tf) { h = g_atrH[i]; break; }
   if(h == INVALID_HANDLE)
   {
      h = iATR(_Symbol, tf, 14);
      if(g_atrN < 8) { g_atrTf[g_atrN] = tf; g_atrH[g_atrN] = h; g_atrN++; }
   }
   if(h == INVALID_HANDLE) return 0.0;
   double b[];
   ArraySetAsSeries(b, true);
   if(CopyBuffer(h, 0, shift, 1, b) < 1) return 0.0;
   return b[0];
}

//--- Barras en orden "serie" (0 = barra en formación, 1 = última cerrada)
bool Rates(ENUM_TIMEFRAMES tf, int count, MqlRates &r[])
{
   ArraySetAsSeries(r, true);
   return (CopyRates(_Symbol, tf, 0, count, r) == count);
}

double AvgTickVol(MqlRates &r[], int from, int n)
{
   double s = 0.0;
   for(int i = from; i < from + n; i++) s += (double)r[i].tick_volume;
   return s / (double)n;
}

//--- VWAP anclado sobre un arreglo en orden "serie" (oldest >= newest)
double AnchoredVwapSeries(MqlRates &r[], int oldest, int newest)
{
   double sv = 0.0, spv = 0.0;
   for(int i = oldest; i >= newest; i--)
   {
      double tp = (r[i].high + r[i].low + r[i].close) / 3.0;
      double v  = (double)r[i].tick_volume;
      spv += tp * v;
      sv  += v;
   }
   return (sv > 0.0) ? spv / sv : 0.0;
}

//+------------------------------------------------------------------+
//| Perfil de volumen (volumen de ticks repartido por rango de barra) |
//| r[] en orden cronológico                                          |
//+------------------------------------------------------------------+
bool BuildProfile(MqlRates &r[], int n, int bins, double vaPct, double &poc, double &vah, double &val)
{
   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int i = 0; i < n; i++)
   {
      hi = MathMax(hi, r[i].high);
      lo = MathMin(lo, r[i].low);
   }
   double step = (hi - lo) / (double)bins;
   if(step <= 0.0) return false;

   double prof[];
   ArrayResize(prof, bins);
   ArrayInitialize(prof, 0.0);
   for(int i = 0; i < n; i++)
   {
      int i0 = (int)MathFloor((r[i].low - lo) / step);
      int i1 = (int)MathFloor((r[i].high - lo) / step);
      i0 = MathMax(0, MathMin(bins - 1, i0));
      i1 = MathMax(0, MathMin(bins - 1, i1));
      double share = (double)r[i].tick_volume / (double)(i1 - i0 + 1);
      for(int j = i0; j <= i1; j++) prof[j] += share;
   }
   int p = ArrayMaximum(prof);
   double total = 0.0;
   for(int j = 0; j < bins; j++) total += prof[j];
   if(total <= 0.0) return false;

   double acc = prof[p];
   int a = p, b = p;
   while(acc < vaPct * total && (a > 0 || b < bins - 1))
   {
      double dn = (a > 0)        ? prof[a - 1] : -1.0;
      double up = (b < bins - 1) ? prof[b + 1] : -1.0;
      if(up >= dn) { b++; acc += up; }
      else         { a--; acc += dn; }
   }
   poc = lo + ((double)p + 0.5) * step;
   vah = lo + (double)(b + 1) * step;
   val = lo + (double)a * step;
   return true;
}

//+------------------------------------------------------------------+
//| Recalcula niveles del día (llamar en cada barra M5 cerrada)       |
//+------------------------------------------------------------------+
void RefreshLevels()
{
   LV.ok = false;
   datetime now = TimeCurrent();
   datetime ds  = TradingDayStartSrv(now);

   //--- día de trading previo con datos (salta fines de semana)
   MqlRates y[];
   int ny = 0;
   for(int k = 1; k <= 5; k++)
   {
      datetime a = ds - (datetime)(k * 86400);
      datetime b = ds - (datetime)((k - 1) * 86400);
      ny = CopyRates(_Symbol, PERIOD_M5, a, b - 1, y);
      if(ny >= 100) break;
   }
   if(ny < 100) return;

   LV.yH = y[0].high;
   LV.yL = y[0].low;
   for(int i = 0; i < ny; i++)
   {
      LV.yH = MathMax(LV.yH, y[i].high);
      LV.yL = MathMin(LV.yL, y[i].low);
   }
   LV.yC = y[ny - 1].close;
   if(!BuildProfile(y, ny, 60, 0.70, LV.poc, LV.vah, LV.val)) return;

   //--- rango asiático 19:00-02:00 NY
   LV.aH = 0.0;
   LV.aL = 0.0;
   datetime ae = NYClockToSrv(now, 120);
   datetime as = ae - 7 * 3600;
   if(now < ae) { ae -= 86400; as -= 86400; }
   MqlRates a[];
   int na = CopyRates(_Symbol, PERIOD_M5, as, ae - 1, a);
   if(na >= 10)
   {
      LV.aH = a[0].high;
      LV.aL = a[0].low;
      for(int i = 0; i < na; i++)
      {
         LV.aH = MathMax(LV.aH, a[i].high);
         LV.aL = MathMin(LV.aL, a[i].low);
      }
   }

   //--- VWAP de sesión (barras cerradas) y rango de hoy
   LV.vwap = 0.0;
   LV.sigma = 0.0;
   LV.dayHi = 0.0;
   LV.dayLo = 0.0;
   MqlRates t[];
   int nt = CopyRates(_Symbol, PERIOD_M5, ds, now, t);
   if(nt >= 3)
   {
      int n = nt - 1;   // excluye la barra en formación
      double sv = 0.0, spv = 0.0;
      for(int i = 0; i < n; i++)
      {
         double tp = (t[i].high + t[i].low + t[i].close) / 3.0;
         double v  = (double)t[i].tick_volume;
         spv += tp * v;
         sv  += v;
      }
      if(sv > 0.0)
      {
         LV.vwap = spv / sv;
         double s2 = 0.0;
         for(int i = 0; i < n; i++)
         {
            double tp = (t[i].high + t[i].low + t[i].close) / 3.0;
            double v  = (double)t[i].tick_volume;
            s2 += v * (tp - LV.vwap) * (tp - LV.vwap);
         }
         LV.sigma = MathSqrt(s2 / sv);
      }
      LV.dayHi = t[0].high;
      LV.dayLo = t[0].low;
      for(int i = 0; i < nt; i++)
      {
         LV.dayHi = MathMax(LV.dayHi, t[i].high);
         LV.dayLo = MathMin(LV.dayLo, t[i].low);
      }
   }
   //--- historial del VWAP
   for(int i = 12; i > 0; i--) VW_HIST[i] = VW_HIST[i - 1];
   VW_HIST[0] = LV.vwap;

   LV.ok = true;
}

//+------------------------------------------------------------------+
//| Filtro de noticias (calendario económico de MT5, impacto alto)    |
//| No funciona en el probador de estrategias.                        |
//+------------------------------------------------------------------+
datetime g_newsChecked = 0;
bool     g_newsBlocked = false;
bool     g_calWarned   = false;

bool NewsBlocked()
{
   if(!CFG.useNews) return false;
   datetime now = TimeCurrent();
   if(now - g_newsChecked < 30) return g_newsBlocked;
   g_newsChecked = now;
   g_newsBlocked = false;

   string cur[2];
   cur[0] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   cur[1] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   for(int c = 0; c < 2; c++)
   {
      if(cur[c] == "" || cur[c] == "XAU") continue;
      MqlCalendarValue v[];
      ResetLastError();
      if(!CalendarValueHistory(v, now - CFG.newsMinutes * 60, now + CFG.newsMinutes * 60, NULL, cur[c]))
      {
         if(!g_calWarned) { Print("PropBot: calendario económico no disponible (", GetLastError(), "). Filtro de noticias inactivo."); g_calWarned = true; }
         continue;
      }
      for(int i = 0; i < ArraySize(v); i++)
      {
         MqlCalendarEvent ev;
         if(CalendarEventById(v[i].event_id, ev) && ev.importance == CALENDAR_IMPORTANCE_HIGH)
         {
            g_newsBlocked = true;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Volumen / dinero                                                  |
//+------------------------------------------------------------------+
double NormVol(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   lots = MathMax(vmin, MathMin(vmax, lots));
   int dig = (int)MathMax(0.0, MathRound(-MathLog10(step)));
   return NormalizeDouble(lots, dig);
}

//--- pérdida en dinero de la cuenta por mover "dist" (precio) con "lots" en el símbolo actual
double MoneyForDistance(double dist, double lots)
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0.0) tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) return 0.0;
   return dist / ts * tv * lots;
}

#endif
