#pragma semicolon 1
#pragma newdecls required

#include <NewPage>
#include <NewPage/user>
#include <NewPage/stats>

#define P_NAME P_PRE ... " - Stats"
#define P_DESC "User Stats"

#define TEAM_OB 1
#define TEAM_TE 2
#define TEAM_CT 3

#define STATS_SESSION 0
#define STATS_TOTAL   1

public Plugin myinfo = 
{
    name        = P_NAME,
    author      = P_AUTHOR,
    description = P_DESC,
    version     = P_VERSION,
    url         = P_URLS
};

int g_iToday;

enum Stats
{
    iObserveOnlineTime,
    iPlayOnlineTime,
    iTotalOnlineTime,
    iTodayOnlineTime,
}

int g_iTrackingId[MAXPLAYERS+1];
int g_StatsClient[MAXPLAYERS+1][2][Stats];
int g_iConnectTimes[MAXPLAYERS+1];
int g_iClientVitality[MAXPLAYERS+1];

Handle g_TimerClient[MAXPLAYERS+1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("NP_Stats_TodayOnlineTime",   Native_TodayOnlineTime);
    CreateNative("NP_Stats_TotalOnlineTime",   Native_TotalOnlineTime);
    CreateNative("NP_Stats_ObserveOnlineTime", Native_ObserveOnlineTime);
    CreateNative("NP_Stats_PlayOnlineTime",    Native_PlayOnlineTime);
    CreateNative("NP_Stats_Vitality",          Native_Vitality);
    
    RegPluginLibrary("np-stats");

    return APLRes_Success;
}

public int Native_TodayOnlineTime(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return g_StatsClient[client][STATS_SESSION][iTodayOnlineTime] + g_StatsClient[client][STATS_TOTAL][iTodayOnlineTime];
}

public int Native_TotalOnlineTime(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return g_StatsClient[client][STATS_SESSION][iTotalOnlineTime] + g_StatsClient[client][STATS_TOTAL][iTotalOnlineTime];
}

public int Native_ObserveOnlineTime(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return g_StatsClient[client][STATS_SESSION][iObserveOnlineTime] + g_StatsClient[client][STATS_TOTAL][iObserveOnlineTime];
}

public int Native_PlayOnlineTime(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return g_StatsClient[client][STATS_SESSION][iPlayOnlineTime] + g_StatsClient[client][STATS_TOTAL][iPlayOnlineTime];
}

public int Native_Vitality(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return g_iClientVitality[client];
}

public void OnPluginStart()
{
    // init
    g_iToday = GetDay();
    
    // global timer
    CreateTimer(1.0, Timer_Global, _, TIMER_REPEAT);
}

public Action Timer_Global(Handle timer)
{
    int today = GetDay();

    if(today != g_iToday)
    {
        g_iToday = today;
        
        for(int client = 1; client <= MaxClients; ++client)
        {
            g_StatsClient[client][STATS_SESSION][iTodayOnlineTime] = 0;
            g_StatsClient[client][STATS_TOTAL][iTodayOnlineTime]   = 0;
        }
    }
    
    return Plugin_Continue;
}

public void OnClientConnected(int client)
{
    g_iTrackingId[client]   = -1;
    g_iConnectTimes[client] = 0;

    for(int i = 0; i < view_as<int>(Stats); ++i)
    {
        g_StatsClient[client][STATS_SESSION][i] = 0;
        g_StatsClient[client][STATS_TOTAL][i] = 0;
    }

    if(IsFakeClient(client) || IsClientSourceTV(client))
        return;

    g_TimerClient[client] = CreateTimer(1.0, Timer_Client, client, TIMER_REPEAT);
}

public void OnClientDataChecked(int client, int uid)
{
    if(IsFakeClient(client) || IsClientSourceTV(client))
        return;
    
    if(!NP_MySQL_IsConnected())
    {
        CreateTimer(3.0, Timer_Retry, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    Database db = NP_MySQL_GetDatabase();
    
    char m_szQuery[128];
    FormatEx(m_szQuery, 128, "SELECT onlineTotal, onlineToday, onlineOB, onlinePlay, connectTimes, vitality FROM %s_stats WHERE uid = %d", P_SQLPRE, uid);
    db.Query(LoadClientCallback, m_szQuery, GetClientUserId(client));
}

public void OnClientDisconnect(int client)
{
    if(g_TimerClient[client] != INVALID_HANDLE)
        KillTimer(g_TimerClient[client]);

    g_TimerClient[client] = INVALID_HANDLE;

    if(g_iTrackingId[client] <= 0)
        return;
    
    char m_szQuery[512];
    FormatEx(m_szQuery, 512, "UPDATE %s_stats AS a, %s_analytics AS b SET a.connectTimes=a.connectTimes+1, a.onlineToday=a.onlineToday+%d, a.onlineTotal=a.onlineTotal+%d, a.onlineOB=a.onlineOB+%d, a.onlinePlay=a.onlinePlay+%d, b.duration=%d WHERE a.uid=%d AND b.id=%d", P_SQLPRE, P_SQLPRE, g_StatsClient[client][STATS_SESSION][iTodayOnlineTime], g_StatsClient[client][STATS_SESSION][iTotalOnlineTime], g_StatsClient[client][STATS_SESSION][iObserveOnlineTime], g_StatsClient[client][STATS_SESSION][iPlayOnlineTime], g_StatsClient[client][STATS_SESSION][iTotalOnlineTime], NP_Users_UserIdentity(client), g_iTrackingId[client]);
    NP_MySQL_SaveDatabase(m_szQuery);
}

public Action Timer_Retry(Handle timer, int client)
{
    if(!IsClientInGame(client))
        return Plugin_Stop;
    
    OnClientDataChecked(client, NP_Users_UserIdentity(client));
    
    return Plugin_Stop;
}

public void LoadClientCallback(Database db, DBResultSet results, const char[] error, int userid)
{
    int client = GetClientOfUserId(userid);
    if(!client)
        return;

    if(results == null || error[0])
    {
        NP_Core_LogError("Stats", "LoadClientCallback", "SQL Error:  %s -> \"%L\"", error, client);
        CreateTimer(3.0, Timer_Retry, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
    
    if(results.RowCount <= 0 || !results.FetchRow())
    {
        InsertNewUserData(client);
        return;
    }
    
    g_StatsClient[client][STATS_TOTAL][iTotalOnlineTime]   = results.FetchInt(0);
    g_StatsClient[client][STATS_TOTAL][iTodayOnlineTime]   = results.FetchInt(1);
    g_StatsClient[client][STATS_TOTAL][iObserveOnlineTime] = results.FetchInt(2);
    g_StatsClient[client][STATS_TOTAL][iPlayOnlineTime]    = results.FetchInt(3);

    g_iConnectTimes[client]   = results.FetchInt(4)+1;
    g_iClientVitality[client] = results.FetchInt(5);
    
    char ip[32];
    GetClientIP(client, ip, 32);
    
    char map[128];
    GetCurrentMap(map, 128);
    
    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "INSERT INTO %s_analytics VALUES (DEFAULT, %d, %d, '%s', '%s', %d, %d, -1);", P_SQLPRE, NP_Users_UserIdentity(client), NP_Core_GetServerId(), ip, map, GetTime(), g_iToday);
    NP_MySQL_GetDatabase().Query(InserAnalyticsCallback, m_szQuery, GetClientUserId(client));
}

void InsertNewUserData(int client)
{
    char m_szQuery[128];
    FormatEx(m_szQuery, 128, "INSERT INTO %s_stats (`uid`) VALUES ('%d');", P_SQLPRE, NP_Users_UserIdentity(client));
    NP_MySQL_GetDatabase().Query(InserUserCallback, m_szQuery, GetClientUserId(client));
}

public void InserUserCallback(Database db, DBResultSet results, const char[] error, int userid)
{
    int client = GetClientOfUserId(userid);
    if(!client)
        return;
    
    CreateTimer(1.0, Timer_Retry, client, TIMER_FLAG_NO_MAPCHANGE);

    if(results == null || error[0])
        NP_Core_LogError("Stats", "InserUserCallback", "SQL Error:  %s -> \"%L\"", error, client);
}

public void InserAnalyticsCallback(Database db, DBResultSet results, const char[] error, int userid)
{
    int client = GetClientOfUserId(userid);
    if(!client)
        return;

    if(results == null || error[0])
    {
        NP_Core_LogError("Stats", "InserAnalyticsCallback", "SQL Error:  %s -> \"%L\"", error, client);
        return;
    }
    
    g_iTrackingId[client] = results.InsertId;
}

public Action Timer_Client(Handle timer, int client)
{
    if(IsClientInGame(client) && GetClientTeam(client) > TEAM_OB)
    {
        g_StatsClient[client][STATS_SESSION][iPlayOnlineTime]++;
    }
    else
    {
        g_StatsClient[client][STATS_SESSION][iObserveOnlineTime]++;
    }
    
    g_StatsClient[client][STATS_SESSION][iTodayOnlineTime]++;
    g_StatsClient[client][STATS_SESSION][iTotalOnlineTime]++;
 
    return Plugin_Continue;
}