#pragma semicolon 1
#pragma newdecls required

#include <NewPage>
#include <NewPage/user>
#include <NewPage/vip>

#define P_NAME P_PRE ... " - VIP"
#define P_DESC "API of VIP"

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
    CreateNative("NP_Vip_GrantVip", Native_GrantVip);
    CreateNative("NP_Vip_DeleteVip", Native_DeleteVip);
    CreateNative("NP_Vip_AddVipPoint", Native_AddVipPoint);
    
    // lib
    RegPluginLibrary("np-vip");

    return APLRes_Success;
}

public int Native_GrantVip(Handle plugin, int numParams)
{
    GrantVip(GetNativeCell(1), GetNativeCell(2));
}

public int Native_DeleteVip(Handle plugin, int numParams)
{
    DeleteVip(GetNativeCell(1));
}

public int Native_AddVipPoint(Handle plugin, int numParams)
{
    AddVipPoint(GetNativeCell(1), GetNativeCell(2));
}

public void OnPluginStart()
{
    // nothing ;)
}

void GrantVip(int client, int duration)
{
    if(!NP_MySQL_IsConnected())
    {
        NP_Core_LogError("Vip", "GrantVip", "Error: SQL is unavailable -> \"%L\"", client);
        return;
    }

    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "UPDATE %s_users SET vipexpired = '%d' WHERE uid = '%d'", P_SQLPRE, GetTime()+duration*86400, NP_Users_UserIdentity(client));
    NP_MySQL_SaveDatabase(m_szQuery);
}

void DeleteVip(int client)
{
    //if player isn's vip
    if(!g_player[client][Isvip])
        return;

    if(!NP_MySQL_IsConnected())
    {
        NP_Core_LogError("Vip", "GrantVip", "Error: SQL is unavailable -> \"%L\"", client);
        return;
    }

    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "UPDATE %s_users SET vipexpired = '%d' WHERE uid = '%d'", P_SQLPRE, 0, NP_Users_UserIdentity(client));
    NP_MySQL_SaveDatabase(m_szQuery);
}

void AddVipPoint(int client, int point)
{
    //if player isn's vip
    if(!g_player[client][Isvip])
        return;

    if(!NP_MySQL_IsConnected())
    {
        NP_Core_LogError("Vip", "GrantVip", "Error: SQL is unavailable -> \"%L\"", client);
        return;
    }

    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "UPDATE %s_users SET vippoint = '%d' WHERE uid = '%d'", P_SQLPRE, g_player[client][Point] + point, NP_Users_UserIdentity(client));
    NP_MySQL_SaveDatabase(m_szQuery);
}