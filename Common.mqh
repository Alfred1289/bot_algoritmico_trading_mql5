//+------------------------------------------------------------------+
//| Common.mqh - parámetros y funciones comunes a todos los EAs       |
//| (PropBot.mq5 todo-en-uno y los seis EAs PB_P1..PB_P6)             |
//+------------------------------------------------------------------+
#ifndef PB_COMMON_MQH
#define PB_COMMON_MQH

#include "Core.mqh"
#include "Guard.mqh"
#include "Strategy.mqh"

//=== Cuenta de fondeo ===============================================
input group "=== Cuenta de fondeo (FundingPips 2 Step Pro) ==="
input double InpInitialBalance   = 5000.0;  // Balance inicial de la cuenta
input double InpFirmDailyPct     = 3.0;     // Límite diario de la firma (%)
input double InpFirmMaxPct       = 6.0;     // Pérdida máxima estática de la firma (%)

input group "=== Guardián interno (siempre MÁS estricto que la firma) ==="
input double InpDailyStopPct     = 2.0;     // Parada diaria interna (% del balance inicial)
input double InpMaxStopPct       = 4.0;     // Parada máxima interna (% del balance inicial)
input double InpMaxOpenRiskPct   = 1.5;     // Riesgo abierto total (%)
input double InpMaxRiskTradePct  = 0.50;    // Riesgo máximo por operación (%)
input double InpMaxSpreadPctStop = 10.0;    // Spread máximo (% de la distancia al stop)
input bool   InpResetHardLock    = false;   // Quitar bloqueo permanente al iniciar (solo tras revisar)

input group "=== Tamaño de posición ==="
input ENUM_LOT_MODE InpLotMode   = LOT_FIXED; // Modo de lote
input double InpLotFx            = 0.08;    // Lote fijo EURUSD / GBPUSD
input double InpLotGold          = 0.01;    // Lote fijo Oro
input double InpRiskPct          = 0.30;    // Riesgo por operación en modo % (x multiplicador)

input group "=== Noticias y hora ==="
input bool   InpUseNews          = true;    // Bloquear entradas cerca de noticias de impacto alto
input int    InpNewsMinutes      = 15;      // Minutos antes y después de la noticia
input bool   InpAutoOffset       = true;    // Detectar desfase servidor-GMT automáticamente
input int    InpManualOffsetH    = 3;       // Desfase manual del servidor respecto a GMT (si no es automático)

input group "=== Sesiones permitidas (hora de Nueva York) ==="
input bool   InpSessF_On         = true;      // Frankfurt activa
input string InpSessF_Start      = "02:00";   // Frankfurt inicio (aprox. 08:00 CET)
input string InpSessF_End        = "11:00";   // Frankfurt fin
input bool   InpSessL_On         = true;      // Londres activa
input string InpSessL_Start      = "03:00";   // Londres inicio (08:00 Londres)
input string InpSessL_End        = "12:00";   // Londres fin
input bool   InpSessN_On         = true;      // Nueva York activa
input string InpSessN_Start      = "08:00";   // Nueva York inicio
input string InpSessN_End        = "17:00";   // Nueva York fin
input bool   InpFlatAtEnd        = true;      // Cerrar todo al final de la última sesión
input string InpFlatTime         = "16:45";   // Hora de cierre total (NY); no se abre nada desde esa hora

input group "=== Monitoreo: avisos al móvil ==="
input bool   InpPush             = true;    // Notificaciones push (requiere MetaQuotes ID en Herramientas > Opciones > Notificaciones)

//+------------------------------------------------------------------+
bool PB_InitConfig()
{
   if(InpDailyStopPct >= InpFirmDailyPct || InpMaxStopPct >= InpFirmMaxPct)
   {
      Print("PropBot: los topes internos deben ser MENORES que los de la firma. Corrige los parámetros.");
      return false;
   }
   if(Period() != PERIOD_M5)
      Print("PropBot: se recomienda el gráfico M5. Periodo actual distinto.");

   CFG.initialBalance   = InpInitialBalance;
   CFG.dailyLimitPct    = InpFirmDailyPct;
   CFG.maxLossPct       = InpFirmMaxPct;
   CFG.dailyStopPct     = InpDailyStopPct;
   CFG.maxStopPct       = InpMaxStopPct;
   CFG.maxOpenRiskPct   = InpMaxOpenRiskPct;
   CFG.maxRiskTradePct  = InpMaxRiskTradePct;
   CFG.riskPct          = InpRiskPct;
   CFG.lotMode          = InpLotMode;
   CFG.lotFx            = InpLotFx;
   CFG.lotGold          = InpLotGold;
   CFG.maxSpreadPctStop = InpMaxSpreadPctStop;
   CFG.useNews          = InpUseNews;
   CFG.newsMinutes      = InpNewsMinutes;
   CFG.autoOffset       = InpAutoOffset;
   CFG.manualOffsetH    = InpManualOffsetH;
   CFG.sessF = InpSessF_On;  CFG.fS = ParseHM(InpSessF_Start);  CFG.fE = ParseHM(InpSessF_End);
   CFG.sessL = InpSessL_On;  CFG.lS = ParseHM(InpSessL_Start);  CFG.lE = ParseHM(InpSessL_End);
   CFG.sessN = InpSessN_On;  CFG.nS = ParseHM(InpSessN_Start);  CFG.nE = ParseHM(InpSessN_End);
   CFG.push    = InpPush;
   CFG.flatOn  = InpFlatAtEnd;
   CFG.flatMin = ParseHM(InpFlatTime);

   ArrayInitialize(VW_HIST, 0.0);
   ZeroMemory(LV);
   if(InpResetHardLock) ClearHardLock();
   GuardUpdateDay();
   PrintFormat("PropBot iniciado en %s. Offset servidor-GMT: %d h. Noticias: %s. Push: %s",
               _Symbol, ServerOffsetSec() / 3600, InpUseNews ? "activas" : "inactivas", InpPush ? "si" : "no");
   return true;
}

//--- true una vez por cada barra M5 nueva
bool PB_NewBar()
{
   static datetime last = 0;
   datetime b = iTime(_Symbol, PERIOD_M5, 0);
   if(b != last) { last = b; return true; }
   return false;
}

//--- guardián + avisos + cierre al final de la última sesión (cada tick)
void PB_TickCommon()
{
   GuardEnforce();
   GuardWarnings();
   if(CFG.flatOn)
   {
      int m = NYMin(TimeCurrent());
      if(m >= CFG.flatMin && m < CFG.flatMin + 120 && HasBotPositions())
         CloseAllBot("fin de sesión");
   }
}

//--- panel en el gráfico (title + una o varias estrategias)
void PB_Dashboard(string title, CStrategy *&arr[], int n)
{
   static datetime lastDash = 0;
   datetime now = TimeCurrent();
   if(now - lastDash < 5) return;
   lastDash = now;
   string s = title + "  " + _Symbol + "\n" + GuardStatus() + "\n";
   s += "Sesión permitida ahora: " + (InSessionMask("FLN") ? "SÍ" : "NO") + "\n";
   for(int i = 0; i < n; i++)
      s += StringFormat("%s: %s | op. hoy %d | pérdidas seguidas %d\n",
                        arr[i].name, arr[i].enabled ? "ON" : "off", arr[i].tradesToday, arr[i].consecLoss);
   Comment(s);
}

//--- Procesa un deal: avisa de aperturas y cierres de esta estrategia/símbolo.
//--- Devuelve true y el resultado neto si fue un cierre (para contar pérdidas seguidas).
bool PB_ParseDeal(const MqlTradeTransaction &trans, long magic, double &pr)
{
   pr = 0.0;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return false;
   if(!HistoryDealSelect(trans.deal)) return false;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return false;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != magic) return false;
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
   {
      NotifyUser(StringFormat("PropBot: abierta %s %s %.2f lotes",
                 _Symbol, (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY ? "compra" : "venta"),
                 HistoryDealGetDouble(trans.deal, DEAL_VOLUME)));
      return false;
   }
   if(entry != DEAL_ENTRY_OUT) return false;
   pr = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
      + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
      + HistoryDealGetDouble(trans.deal, DEAL_SWAP);
   NotifyUser(StringFormat("PropBot: cerrada %s resultado %.2f USD | equity %.2f",
              _Symbol, pr, AccountInfoDouble(ACCOUNT_EQUITY)));
   return true;
}

#endif
