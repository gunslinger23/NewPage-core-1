#pragma semicolon 1
#pragma newdecls required

#include <NewPage>
#include <NewPage/vip>

#define P_NAME P_PRE ... " - Vip"
#define P_DESC "Vip"

#define VIPMAXLEVEL 8

int g_player[MAXPLAYERS+1][VIP];

// We haven't level 0 ;)
int g_ilevel[VIPMAXLEVEL+1];

bool g_bready = false;

public Plugin myinfo = 
{
    name        = P_NAME,
    author      = P_AUTHOR,
    description = P_DESC,
    version     = P_VERSION,
    url         = P_URLS
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("NP_Vip_ClientIsVip", Native_ClientIsVip);
    CreateNative("NP_Vip_GrantVip", Native_GrantVip);
    CreateNative("NP_Vip_DeleteVip", Native_DeleteVip);
    CreateNative("NP_Vip_GetVipLevel", Native_GetVipLevel);
    CreateNative("NP_Vip_GetVipPoint", Native_GetVipPoint);
    CreateNative("NP_Vip_AddVipPoint", Native_AddVipPoint);

    
    // lib
    RegPluginLibrary("np-vip");

    return APLRes_Success;
}

public int Native_ClientIsVip(Handle plugin, int numParams)
{
    return g_player[GetNativeCell(1)][Isvip];
}

public int Native_GrantVip(Handle plugin, int numParams)
{
    GrantVip(GetNativeCell(1), GetNativeCell(2));
}

public int Native_DeleteVip(Handle plugin, int numParams)
{
    DeleteVip(GetNativeCell(1));
}

public int Native_GetVipLevel(Handle plugin, int numParams)
{
    return g_player[GetNativeCell(1)][Level];
}

public int Native_GetVipPoint(Handle plugin, int numParams)
{
    return g_player[GetNativeCell(1)][Point];
}

public int Native_AddVipPoint(Handle plugin, int numParams)
{
    AddVipPoint(GetNativeCell(1), GetNativeCell(2));
}

public void OnPluginStart()
{
    // nothing ;)
}

public void NP_Core_OnAvailable(int serverId, int modId)
{
    GetLevelINF();
}

public void OnClientDataChecked(int client, bool Spt, int Vip, bool Ctb, bool Opt, bool Adm, bool Own)
{
    if(Vip <= 0)
        return;
    CheckVip(client);
}

public void OnClientDisconnect(int client)
{
    g_player[client][Isvip] = 0;
    g_player[client][Level] = 0;
    g_player[client][Point] = 0;
}


void CheckVip(int client)
{
    char steamid[32];
    if(!GetClientAuthId(client, AuthId_SteamID64, steamid, 32, true))
    {
        NP_Core_LogMessage("Vip", "CheckVip", "Error: We can not verify client`s SteamId64 -> \"%L\"", client);
        return;
    }

    if(!NP_MySQL_IsConnected())
    {
        NP_Core_LogError("Vip", "CheckVip", "Error: SQL is unavailable -> \"%L\"", client);
        CreateTimer(5.0, Timer_ReCheckVIP, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    Database db = NP_MySQL_GetDatabase();

    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "SELECT vip, vippoint FROM %s_users WHERE steamid = '%s'", P_SQLPRE, steamid);
    db.Query(CheckVipCallback, m_szQuery, GetClientUserId(client));
}

public void CheckVipCallback(Database db, DBResultSet results, const char[] error, int userid)
{
    int client = GetClientOfUserId(userid);
    if(!client)
        return;

    if(results == null || error[0])
    {
        NP_Core_LogError("Vip", "CheckVip", "SQL Error:  %s -> \"%L\"", error, client);
        CreateTimer(5.0, Timer_ReCheckVIP, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    if(results.RowCount <= 0)
        return;

    while(results.FetchRow())
    {
        // vip, vippoint
        int time = results.FetchInt(0);
        int vippoint = results.FetchInt(1);

        /* process results */
        
        // if player have not vip
        if(time <= 0)
            return;

        // if player's vip hasn't expired
        char t_ntime[8], t_ltime[8];
        FormatTime(t_ntime, 10, "%Y%m%d", GetTime());
        FormatTime(t_ltime, 10, "%Y%m%d", time);

        if(StringToInt(t_ntime) <= StringToInt(t_ltime))
        {
            g_player[client][Isvip] = 1;
            g_player[client][Point] = vippoint;
            g_player[client][Level] = GetLevel(vippoint);
        }

        break;
    }
}

public Action Timer_ReCheckVIP(Handle timer, int client)
{
    if(!IsClientConnected(client))
        return Plugin_Stop;

    CheckVip(client);
    
    return Plugin_Stop;
}

void GrantVip(int client, int duration)
{
    char steamid[32];
    if(!GetClientAuthId(client, AuthId_SteamID64, steamid, 32, true))
    {
        NP_Core_LogMessage("Vip", "GrantVip", "Error: We can not verify client`s SteamId64 -> \"%L\"", client);
        return;
    }

    if(!NP_MySQL_IsConnected())
    {
        NP_Core_LogError("Vip", "GrantVip", "Error: SQL is unavailable -> \"%L\"", client);
        return;
    }

    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "UPDATE %s_users SET vip = '%i' WHERE steamid = '%s'", P_SQLPRE, GetTime()+duration*86400, steamid);
    NP_MySQL_SaveDatabase(m_szQuery);
}

void DeleteVip(int client)
{
    //if player isn's vip
    if(!g_player[client][Isvip])
        return;

    char steamid[32];
    if(!GetClientAuthId(client, AuthId_SteamID64, steamid, 32, true))
    {
        NP_Core_LogMessage("Vip", "DeleteVip", "Error: We can not verify client`s SteamId64 -> \"%L\"", client);
        return;
    }

    if(!NP_MySQL_IsConnected())
    {
        NP_Core_LogError("Vip", "GrantVip", "Error: SQL is unavailable -> \"%L\"", client);
        return;
    }

    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "UPDATE %s_users SET vip = '%i' WHERE steamid = '%s'", P_SQLPRE, GetTime()-86400, steamid);
    NP_MySQL_SaveDatabase(m_szQuery);
}

void AddVipPoint(int client, int point)
{
    //if player isn's vip
    if(!g_player[client][Isvip])
        return;

    char steamid[32];
    if(!GetClientAuthId(client, AuthId_SteamID64, steamid, 32, true))
    {
        NP_Core_LogMessage("Vip", "AddVipPoint", "Error: We can not verify client`s SteamId64 -> \"%L\"", client);
        return;
    }

    if(!NP_MySQL_IsConnected())
    {
        NP_Core_LogError("Vip", "GrantVip", "Error: SQL is unavailable -> \"%L\"", client);
        return;
    }

    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "UPDATE %s_users SET vippoint = '%i' WHERE steamid = '%s'", P_SQLPRE, g_player[client][Point] + point, steamid);
    NP_MySQL_SaveDatabase(m_szQuery);
}

int GetLevel(int point)
{
    if(!g_bready)
    {
        NP_Core_LogError("Vip", "GetLevelINF", "Error: Cant get vip level");
        return 0;
    }

    int level = 0;
    while(point > g_ilevel[0])
        level++;
    return level;
}

void GetLevelINF()
{
    if(!NP_MySQL_IsConnected())
    {
        NP_Core_LogError("Vip", "GetLevelINF", "Error: SQL is unavailable");
        CreateTimer(5.0, Timer_ReGetLevelINF, 0, TIMER_FLAG_NO_MAPCHANGE);
        return ;
    }

    Database db = NP_MySQL_GetDatabase();
    
    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "SELECT level, point FROM %s_viplevel", P_SQLPRE);
    db.Query(GetLevelINFCallback, m_szQuery, 0);
}

public Action Timer_ReGetLevelINF(Handle timer, int data)
{
    GetLevelINF();
    return Plugin_Stop;
}

public void GetLevelINFCallback(Database db, DBResultSet results, const char[] error, int data)
{
    if(results == null || error[0])
    {
        NP_Core_LogError("Vip", "GetLevelINF", "SQL Error:  %s", error);
        CreateTimer(5.0, Timer_ReGetLevelINF, 0, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    if(results.RowCount <= 0)
        return;

    while(results.FetchRow())
    {
        // level, point
        int level = results.FetchInt(0);
        int point = results.FetchInt(1);
        g_ilevel[level] = point;
    }
    g_bready = true;
}