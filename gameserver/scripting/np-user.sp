#pragma semicolon 1
#pragma newdecls required

#include <NewPage>
#include <NewPage/user>

#define P_NAME P_PRE ... " - User Manager"
#define P_DESC "User Manager"

public Plugin myinfo = 
{
    name        = P_NAME,
    author      = P_AUTHOR,
    description = P_DESC,
    version     = P_VERSION,
    url         = P_URLS
};

int  g_iUserId[MAXPLAYERS+1];
int g_ivipLevel[MAXPLAYERS+1];
bool g_authClient[MAXPLAYERS+1][Authentication];
bool g_bAuthLoaded[MAXPLAYERS+1];
bool g_bBanChecked[MAXPLAYERS+1];
char g_szUsername[MAXPLAYERS+1][32];

Handle g_hOnUMAuthChecked;
Handle g_hOnUMDataChecked;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Auth
    CreateNative("NP_Users_IsAuthorized", Native_IsAuthorized);
    
    // Identity
    CreateNative("NP_Users_UserIdentity", Native_UserIdentity);
    
    // Banning
    CreateNative("NP_Users_BanClient",    Native_BanClient);
    CreateNative("NP_Users_BanIdentity",  Native_BanIdentity);

    // Vip
    CreateNative("NP_Users_IsVIP", Native_IsVIP);
    CreateNative("NP_Users_VIPLevel", Native_VIPLevel);
    
    // lib
    RegPluginLibrary("np-user");

    return APLRes_Success;
}

// Vip
public int Native_IsVIP(Handle plugin, int numParams)
{
    return g_authClient[GetNativeCell(1)][Vip];
}

public int Native_VIPLevel(Handle plugin, int numParams)
{
    return g_ivipLevel[GetNativeCell(1)];
}

// Auth
public int Native_IsAuthorized(Handle plugin, int numParams)
{
    return g_authClient[GetNativeCell(1)][GetNativeCell(2)];
}

// Identity
public int Native_UserIdentity(Handle plugin, int numParams)
{
    return g_iUserId[GetNativeCell(1)];
}

// Banning
public int Native_BanClient(Handle plugin, int numParams)
{
    int admin  = GetNativeCell(1);
    int target = GetNativeCell(2);
    int btype  = GetNativeCell(3);
    int length = GetNativeCell(4);
    char reason[128];
    GetNativeString(5, reason, 128);

    if(NP_Core_GetServerId() < 0)
        return;
    
    if(!NP_MySQL_IsConnected())
        return;
    
    Database db = NP_MySQL_GetDatabase();

    char ip[24];
    GetClientIP(target, ip, 24, false);
    
    char name[64], nickname[128];
    GetClientName(target, name, 64);
    db.Escape(name, nickname, 128);
    
    char adminName[64];
    db.Escape(g_szUsername[admin], adminName, 64);

    char bReason[256];
    db.Escape(reason, bReason, 256);
    
    char steamid[32];
    if(!GetClientAuthId(target, AuthId_SteamID64, steamid, 32, true))
    {
        NP_Core_LogError("User", "Native_BanClient", "We can not fetch target`s steamid64 -> \"%L\"", target);
        return;
    }

    char m_szQuery[1024];
    FormatEx(m_szQuery, 1024, "INSERT INTO %s_bans VALUES (DEFAULT, '%s', '%s', '%s', %d, %d, %d, %d, %d, %d, '%s', '%s', -1);", P_SQLPRE, steamid, ip, nickname, GetTime()+length*60, btype, NP_Core_GetServerId(), NP_Core_GetServerModId(), g_iUserId[admin], g_szUsername[admin], bReason);
    
    DataPack pack = new DataPack();
    pack.WriteCell(admin);
    pack.WriteCell(GetClientUserId(target));
    pack.WriteCell(btype);
    pack.WriteCell(length);
    pack.WriteString(reason);
    pack.WriteString(m_szQuery);

    db.Query(BanClientCallback, m_szQuery, pack);
}

public int Native_BanIdentity(Handle plugin, int numParams)
{
    int admin = GetNativeCell(1);
    
    char steamIdentity[32];
    GetNativeString(2, steamIdentity, 32);

    int btype  = GetNativeCell(3);
    int length = GetNativeCell(4);
    char reason[128];
    GetNativeString(5, reason, 128);
    
    if(NP_Core_GetServerId() < 0)
        return;

    // we using php auto-check target`s steam nickname.

    char adminName[64];
    NP_MySQL_EscapeString(g_szUsername[admin], adminName, 64);

    char bReason[256];
    NP_MySQL_EscapeString(reason, bReason, 256);

    char m_szQuery[1024];
    FormatEx(m_szQuery, 1024, "INSERT INTO %s_bans VALUES (DEFAULT, '%s', '127.0.0.1', 'php_auto_check', %d, %d, %d, %d, %d, %d, '%s', '%s', -1);", P_SQLPRE, steamIdentity, GetTime()+length*60, btype, NP_Core_GetServerId(), NP_Core_GetServerModId(), g_iUserId[admin], g_szUsername[admin], bReason);

    NP_MySQL_SaveDatabase(m_szQuery);
    
    PrintToChatAll("%t", "Ban by server message", steamIdentity);
}

public void OnPluginStart()
{
    // console command
    AddCommandListener(Command_Who, "sm_who");

    // global forwards
    g_hOnUMAuthChecked = CreateGlobalForward("OnClientAuthChecked", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
    g_hOnUMDataChecked = CreateGlobalForward("OnClientDataChecked", ET_Ignore, Param_Cell, Param_Cell);

    // init console
    g_iUserId[0] = 0;
    g_szUsername[0] = "CONSOLE";
}

public void OnClientConnected(int client)
{
    for(int i = 0; i < view_as<int>(Authentication); ++i)
        g_authClient[client][i] = false;

    g_bAuthLoaded[client] = false;
    g_bBanChecked[client] = false;
    g_szUsername[client][0] = '\0';
    
    g_iUserId[client] = 0;
}

// we call this forward after client is fully in-game.
// this forward -> tell other plugins, we are available, allow to load client`s data.
public void OnClientPutInServer(int client)
{
    if(IsFakeClient(client) || IsClientSourceTV(client))
    {
        CallDataForward(client);
        return;
    }

    if(!g_bAuthLoaded[client] || g_iUserId[client] <= 0)
    {
        CreateTimer(1.0, Timer_Waiting, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    CallDataForward(client);
}

public Action Timer_Waiting(Handle timer, int client)
{
    if(!IsClientInGame(client))
        return Plugin_Stop;
    
    OnClientPutInServer(client);

    return Plugin_Stop;
}

public void OnRebuildAdminCache(AdminCachePart part)
{
    if(part == AdminCache_Admins)
        for(int client = 1; client <= MaxClients; ++client)
            if(IsClientAuthorized(client))
                OnClientAuthorized(client, "");
}

public Action Command_Who(int client, const char[] command, int argc)
{
    if(!IsValidClient(client))
        return Plugin_Handled;

    static int _iLastUse[MAXPLAYERS+1] = {0, ...};
    
    if(_iLastUse[client] > GetTime() - 5)
        return Plugin_Handled;
    
    _iLastUse[client] = GetTime();

    // dont print all in one time. if players > 48 will not working.
    CreateTimer(0.3, Timer_PrintConsole, client, TIMER_REPEAT);
    
    return Plugin_Handled;
}

public Action Timer_PrintConsole(Handle timer, int client)
{
    static int _iCurrentIndex[MAXPLAYERS+1] = {0, ...};
    
    if(!IsClientInGame(client))
    {
        _iCurrentIndex[client] = 0;
        return Plugin_Stop;
    }

    int left = 16; // we loop 16 clients one time.
    while(left--)
    {
        if(_iCurrentIndex[client] == 0)
            PrintToConsole(client, "#slot    userid      name      Supporter    Vip    Contributor    Operator    Administrator    Owner");

        int index = ++_iCurrentIndex[client];
        
        if(index >= MaxClients)
        {
            _iCurrentIndex[client] = 0;
            return Plugin_Stop;
        }

        if(!IsValidClient(index))
            continue;
        
        char strSlot[8], strUser[8];
        StringPad(index, 4, ' ', strSlot, 8);
        StringPad(GetClientUserId(index), 6, ' ', strUser, 8);
        char strFlag[5][4];
        for(int x = 0; x < 5; ++x)
            TickOrCross(g_authClient[index][x], strFlag[x]);
        PrintToConsole(client, "#%s    %s    %N    %s    %s    %s    %s    %s", strSlot, strUser, index, strFlag[0], strFlag[1], strFlag[2], strFlag[3], strFlag[4]);
    }

    return Plugin_Continue;
}

public void OnClientAuthorized(int client, const char[] auth)
{
    if(strcmp(auth, "BOT") == 0 || IsFakeClient(client) || IsClientSourceTV(client))
    {
        CallAuthForward(client);
        return;
    }

    char steamid[32];
    if(!GetClientAuthId(client, AuthId_SteamID64, steamid, 32, true))
    {
        NP_Core_LogMessage("User", "OnClientAuthorized", "Error: We can not verify client`s SteamId64 -> \"%L\"", client);
        CreateTimer(0.1, Timer_ReAuthorize, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    LoadClientAuth(client, steamid);
    CheckClientBanStats(client, steamid);
}

public Action Timer_ReAuthorize(Handle timer, int client)
{
    if(!IsClientConnected(client))
        return Plugin_Stop;

    char steamid[32];
    if(!GetClientAuthId(client, AuthId_SteamID64, steamid, 32, true))
    {
        NP_Core_LogMessage("User", "OnClientAuthorized", "Error: We can not verify client`s SteamId64 -> \"%L\"", client);
        return Plugin_Continue;
    }

    LoadClientAuth(client, steamid);
    CheckClientBanStats(client, steamid);
    
    return Plugin_Stop;
}

void LoadClientAuth(int client, const char[] steamid)
{
    if(g_bAuthLoaded[client])
        return; 

    if(!NP_MySQL_IsConnected())
    {
        NP_Core_LogError("User", "LoadClientAuth", "Error: SQL is unavailable -> \"%L\"", client);
        CreateTimer(5.0, Timer_ReAuthorize, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    Database db = NP_MySQL_GetDatabase();

    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "CALL user_loadvip (%d)", NP_Users_UserIdentity(client));
    db.Query(LoadVIPCallback, m_szQuery, GetClientUserId(client));
    
    FormatEx(m_szQuery, 256, "SELECT uid, username, imm, spt, vip, ctb, opt, adm, own FROM %s_users WHERE steamid = '%s'", P_SQLPRE, steamid);
    db.Query(LoadClientCallback, m_szQuery, GetClientUserId(client));
}

public void LoadVIPCallback(Database db, DBResultSet results, const char[] error, int userid)
{
    int client = GetClientOfUserId(userid);
    if(!client)
        return;

    if(results == null || error[0])
    {
        NP_Core_LogError("User", "LoadVIPCallback", "SQL Error:  %s -> \"%L\"", error, client);
        CreateTimer(5.0, Timer_ReAuthorize, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
    
    if(results.RowCount <= 0 || !results.FetchRow())
    {
        InsertNewUserData(client);
        CallAuthForward(client);
        return;
    }

    g_ivipLevel[client] = results.FetchInt(0);
}

void CheckClientBanStats(int client, const char[] steamid)
{
    if(g_bBanChecked[client])
        return;

    if(!NP_MySQL_IsConnected())
    {
        NP_Core_LogError("User", "LoadClientAuth", "Error: SQL is unavailable -> \"%L\"", client);
        CreateTimer(5.0, Timer_ReAuthorize, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    Database db = NP_MySQL_GetDatabase();

    char m_szQuery[256];
    FormatEx(m_szQuery, 256, "SELECT bType, bSrv, bSrvMod, bCreated, bLength, bReason, id FROM %s_bans WHERE steamid = '%s' AND bRemovedBy = -1", P_SQLPRE, steamid);
    db.Query(CheckBanCallback, m_szQuery, GetClientUserId(client));
}

public void LoadClientCallback(Database db, DBResultSet results, const char[] error, int userid)
{
    int client = GetClientOfUserId(userid);
    if(!client)
        return;

    if(results == null || error[0])
    {
        NP_Core_LogError("User", "LoadClientCallback", "SQL Error:  %s -> \"%L\"", error, client);
        CreateTimer(5.0, Timer_ReAuthorize, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
    
    g_bAuthLoaded[client] = true;

    if(results.RowCount <= 0 || !results.FetchRow())
    {
        InsertNewUserData(client);
        CallAuthForward(client);
        return;
    }

    g_iUserId[client] = results.FetchInt(0);
    results.FetchString(1, g_szUsername[client], 32);
    g_authClient[client][Spt] = (results.FetchInt(3) == 1);
    g_authClient[client][Vip] = (results.FetchInt(4) == 1);
    g_authClient[client][Ctb] = (results.FetchInt(5) == 1);
    g_authClient[client][Opt] = (results.FetchInt(6) == 1);
    g_authClient[client][Adm] = (results.FetchInt(7) == 1);
    g_authClient[client][Own] = (results.FetchInt(8) == 1);

    if(g_authClient[client][Ctb] || g_authClient[client][Opt] || g_authClient[client][Adm] || g_authClient[client][Own])
    {
        AdminId _admin = GetUserAdmin(client);
        if(_admin != INVALID_ADMIN_ID)
        {
            RemoveAdmin(_admin);
            SetUserAdmin(client, INVALID_ADMIN_ID);
        }

        _admin = CreateAdmin(g_szUsername[client]);
        SetUserAdmin(client, _admin, true);
        SetAdminImmunityLevel(_admin, results.FetchInt(2));

        _admin.SetFlag(Admin_Reservation, true);
        _admin.SetFlag(Admin_Generic, true);
        _admin.SetFlag(Admin_Kick, true);
        _admin.SetFlag(Admin_Slay, true);
        _admin.SetFlag(Admin_Chat, true);
        _admin.SetFlag(Admin_Vote, true);
        _admin.SetFlag(Admin_Changemap, true);

        if(g_authClient[client][Opt] || g_authClient[client][Adm] || g_authClient[client][Own])
        {
            _admin.SetFlag(Admin_Ban, true);
            _admin.SetFlag(Admin_Unban, true);

            if(g_authClient[client][Adm] || g_authClient[client][Own])
            {
                _admin.SetFlag(Admin_Convars, true);
                _admin.SetFlag(Admin_Config, true);

                if(g_authClient[client][Own])
                {
                    _admin.SetFlag(Admin_Password, true);
                    _admin.SetFlag(Admin_Cheats, true);
                    _admin.SetFlag(Admin_RCON, true);
                    _admin.SetFlag(Admin_Root, true);
                }
            }
        }

        // we give admin perm before client admin check
        if(IsClientInGame(client))
            RunAdminCacheChecks(client);
    }
    else if(g_authClient[client][Vip])
    {
        AdminId _admin = GetUserAdmin(client);
        if(_admin != INVALID_ADMIN_ID)
        {
            RemoveAdmin(_admin);
            SetUserAdmin(client, INVALID_ADMIN_ID);
        }

        _admin = CreateAdmin(g_szUsername[client]);
        SetUserAdmin(client, _admin, true);

        _admin.SetFlag(Admin_Reservation, true);

        // we give admin perm before client admin check
        if(IsClientInGame(client))
            RunAdminCacheChecks(client);
    }
    
    CallAuthForward(client);
}

void InsertNewUserData(int client)
{
    char steamid[32];
    if(!GetClientAuthId(client, AuthId_SteamID64, steamid, 32, true))
    {
        KickClient(client, "%t", "System cant find you steamid");
        return;
    }

    char m_szQuery[128];
    FormatEx(m_szQuery, 128, "INSERT INTO %s_users (`steamid`, `firstjoin`) VALUES ('%s', %d);", P_SQLPRE, steamid, GetTime());
    NP_MySQL_GetDatabase().Query(InserUserCallback, m_szQuery, GetClientUserId(client));
}

public void InserUserCallback(Database db, DBResultSet results, const char[] error, int userid)
{
    int client = GetClientOfUserId(userid);
    if(!client)
        return;
    
    if(results == null || error[0])
    {
        NP_Core_LogError("User", "CheckBanCallback", "SQL Error:  %s -> \"%L\"", error, client);
        CreateTimer(5.0, Timer_ReAuthorize, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    // Refresh client
    OnClientConnected(client);
    CreateTimer(1.0, Timer_ReAuthorize, client, TIMER_FLAG_NO_MAPCHANGE);
}

public void CheckBanCallback(Database db, DBResultSet results, const char[] error, int userid)
{
    int client = GetClientOfUserId(userid);
    if(!client)
        return;

    if(results == null || error[0])
    {
        NP_Core_LogError("User", "CheckBanCallback", "SQL Error:  %s -> \"%L\"", error, client);
        CreateTimer(5.0, Timer_ReAuthorize, client, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
    
    g_bBanChecked[client] = true;
    
    if(results.RowCount <= 0)
        return;

    while(results.FetchRow())
    {
        //bType, bSrv, bSrvMod, bCreated, bLength, bReason, id

        char bReason[32];
        int bType    = results.FetchInt(0);
        int bSrv     = results.FetchInt(1);
        int bSrvMod  = results.FetchInt(2);
        int bCreated = results.FetchInt(3);
        int bLength  = results.FetchInt(4);
        results.FetchString(5, bReason, 32);

        /* process results */
        
        // if srv ban and current server id != ban server id
        if(bType == 2 && NP_Core_GetServerId() != bSrv)
            continue;
        
        // if mod ban and current server mod != ban mod id
        if(bType == 1 && NP_Core_GetServerModId() != bSrvMod)
            continue;

        char ip[32];
        GetClientIP(client, ip, 32);
         
        char m_szQuery[256];
        FormatEx(m_szQuery, 256, "INSERT INTO %s_blocks VALUES (DEFAULT, %d, '%s', %d)", P_SQLPRE, results.FetchInt(6), ip, GetTime());
        NP_MySQL_SaveDatabase(m_szQuery);

        char timeExpired[64];
        if(bLength != 0)
            FormatTime(timeExpired, 64, "%Y.%m.%d %H:%M:%S", bCreated+bLength);
        else
            FormatEx(timeExpired, 64, "%t", "Permanent ban");

        char kickReason[256];
        char g_banType[32];
        Bantype(bType, g_banType, 32);
        FormatEx(kickReason, 256, "%t", "Blocking information", g_banType, bReason, timeExpired, NP_BANURL);
        //KickClient(client, kickReason);
        BanClient(client, 5, BANFLAG_AUTHID, kickReason, kickReason);

        break;
    }
}

public void BanClientCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();
    int admin  = pack.ReadCell();
    int target = pack.ReadCell(); target = GetClientOfUserId(target);
    int btype  = pack.ReadCell();
    int length = pack.ReadCell();
    char reason[128];
    pack.ReadString(reason, 128);
    char query[1024];
    pack.ReadString(query, 1024);
    delete pack;

    if(results == null || error[0])
    {
        NP_Core_LogError("User", "BanClientCallback", "SQL Error:  %s -> \n%s", error, query);
        return;
    }
    
    if(!target || !IsClientConnected(target))
        return;
    
    char adminName[32];
    if(IsClientInGame(admin))
        GetClientName(admin, adminName, 32);
    else
        strcopy(adminName, 32, g_szUsername[admin]);

    char targetName[32];
    if(IsClientInGame(target))
        GetClientName(target, targetName, 32);
    else
        strcopy(targetName, 32, g_szUsername[target]);

    PrintToChatAll("%t", "Ban by admin message", targetName, adminName, reason);

    char timeExpired[64];
    if(length != 0)
        FormatTime(timeExpired, 64, "%Y.%m.%d %H:%M:%S", GetTime()+length*60);
    else
        FormatEx(timeExpired, 64, "%t", "Permanent ban");

    char kickReason[256];
    char g_banType[32];
    Bantype(btype, g_banType, 32);
    FormatEx(kickReason, 256, "%t", "Blocking information", g_banType, reason, timeExpired, NP_BANURL);
    BanClient(target, 5, BANFLAG_AUTHID, kickReason, kickReason);
}

void CallAuthForward(int client)
{
    Call_StartForward(g_hOnUMAuthChecked);
    Call_PushCell(client);
    for(int i = 0; i < view_as<int>(Authentication); ++i)
        Call_PushCell(g_authClient[client][i]);
    Call_Finish();
}

void CallDataForward(int client)
{
    Call_StartForward(g_hOnUMDataChecked);
    Call_PushCell(client);
    Call_PushCell(g_iUserId[client]);
    Call_Finish();
}