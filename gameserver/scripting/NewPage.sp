#pragma semicolon 1
#pragma newdecls required

#include <NewPage>

// game rules.
#include <sdktools_gamerules>

#define P_NAME P_PRE ... " - Core"
#define P_DESC "API of Data Processing"

public Plugin myinfo = 
{
    name        = P_NAME,
    author      = P_AUTHOR,
    description = P_DESC,
    version     = P_VERSION,
    url         = P_URLS
};


int g_iServerId = -1;
int g_iServerPort = 27015;
int g_iServerModId = -1;

bool g_bConnected = false;

char g_szServerIp[24]  = "127.0.0.1";
char g_szRconPswd[24]  = "RCONPASSWORD";
char g_szHostName[128] = "NewPage Server";

Handle g_hOnConnected = INVALID_HANDLE;
Handle g_hOnAvailable = INVALID_HANDLE;

Database      g_hSQL = null;
EngineVersion g_Engine = Engine_Unknown;


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // connections
    CreateNative("NP_MySQL_IsConnected", Native_IsConnected);
    CreateNative("NP_MySQL_GetDatabase", Native_GetDatabase);

    // quick handle
    CreateNative("NP_MySQL_EscapeString", Native_EscapeString);
    CreateNative("NP_MySQL_SaveDatabase", Native_SaveDatabase);
    CreateNative("NP_MySQL_ExecDatabase", Native_ExecDatabase);
    
    // core
    CreateNative("NP_Core_GetServerId",    Native_GetServerId);
    CreateNative("NP_Core_GetServerModId", Native_GetServerModId);
    
    // logs
    CreateNative("NP_Core_LogError",   Native_LogError);
    CreateNative("NP_Core_LogMessage", Native_LogMessage);

    // lib
    RegPluginLibrary("NewPage");

    /* Init plugin */
    SetConVarInt(FindConVar("sv_hibernate_when_empty"), 0);
    g_Engine = GetEngineVersion();
    int ip = GetConVarInt(FindConVar("hostip"));
    FormatEx(g_szServerIp, 24, "%d.%d.%d.%d", ((ip & 0xFF000000) >> 24) & 0xFF, ((ip & 0x00FF0000) >> 16) & 0xFF, ((ip & 0x0000FF00) >>  8) & 0xFF, ((ip & 0x000000FF) >>  0) & 0xFF);
    g_iServerPort = GetConVarInt(FindConVar("hostport"));

    return APLRes_Success;
}

public int Native_IsConnected(Handle plugin, int numParams)
{
    return g_bConnected;
}

public int Native_GetDatabase(Handle plugin, int numParams)
{
    return view_as<int>(g_hSQL);
}

public int Native_EscapeString(Handle plugin, int numParams)
{
    // database is unavailable
    if(!g_bConnected || g_hSQL == null)
        return false;
    
    // dynamic length
    int inLen = 0;
    GetNativeStringLength(1, inLen);
    char[] input = new char[inLen+1];
    if(GetNativeString(1, input, inLen+1) != SP_ERROR_NONE)
        return false;
    
    char[] output = new char[GetNativeCell(3)];
    if(!g_hSQL.Escape(input, output, GetNativeCell(3)))
        return false;
    
    return (SetNativeString(2, output, GetNativeCell(3), true) == SP_ERROR_NONE);
}

public int Native_SaveDatabase(Handle plugin, int numParams)
{
    // database is unavailable
    if(!g_bConnected || g_hSQL == null)
        return;
    
    // dynamic length
    int inLen = 0;
    GetNativeStringLength(1, inLen);
    char[] input = new char[inLen+1];
    if(GetNativeString(1, input, inLen+1) != SP_ERROR_NONE)
        return;
    
    DataPack data = new DataPack();
    data.WriteString(input);

    g_hSQL.Query(NativeSave_Callback, input, data);
    return;
}

public int Native_ExecDatabase(Handle plugin, int numParams)
{
    // database is unavailable
    if(!g_bConnected || g_hSQL == null)
        return view_as<int>(INVALID_HANDLE);
    
    // dynamic length
    int inLen = 0;
    GetNativeStringLength(1, inLen);
    char[] input = new char[inLen+1];
    if(GetNativeString(1, input, inLen+1) != SP_ERROR_NONE)
        return view_as<int>(INVALID_HANDLE);

    return view_as<int>(SQL_Query(g_hSQL, input));
}

public int Native_GetServerId(Handle plugin, int numParams)
{
    return g_iServerId;
}

public int Native_GetServerModId(Handle plugin, int numParams)
{
    return g_iServerModId;
}

public int Native_LogError(Handle plugin, int numParams)
{
    char module[32], func[64], format[256];
    GetNativeString(1, module,  32);
    GetNativeString(2, func,    64);
    GetNativeString(3, format, 256);

    char error[2048];
    FormatNativeString(0, 0, 4, 2048, _, error, format);
    
    char path[128];
    BuildPath(Path_SM, path, 128, "logs/NewPage/%s_err.log", module);
    
    LogToFileEx(path, "[%s] -> %s", func, error);
}

public int Native_LogMessage(Handle plugin, int numParams)
{
    char module[32], func[64], format[256];
    GetNativeString(1, module,  32);
    GetNativeString(2, func,    64);
    GetNativeString(3, format, 256);

    char message[2048];
    FormatNativeString(0, 0, 4, 2048, _, message, format);
    
    char path[128];
    BuildPath(Path_SM, path, 128, "logs/NewPage/%s_msg.log", module);
    
    LogToFileEx(path, "[%s] -> %s", func, message);
}

public void OnPluginStart()
{
    // forwards
    g_hOnConnected = CreateGlobalForward("NP_MySQL_OnConnected", ET_Ignore, Param_Cell);
    g_hOnAvailable = CreateGlobalForward("NP_Core_OnAvailable",  ET_Ignore, Param_Cell, Param_Cell);

    // connections
    ConnectToDatabase(0);
    
    // log dir
    CheckLogsDirectory();
}

public void CheckLogsDirectory()
{
    char path[128];
    BuildPath(Path_SM, path, 128, "logs/NewPage");
    if(!DirExists(path))
        CreateDirectory(path, 755);
}

void ConnectToDatabase(int retry)
{
    // connected?
    if(g_bConnected)
        return;

    // not null
    if(g_hSQL != null)
    {
        g_bConnected = true;
        Call_StartForward(g_hOnConnected);
        Call_PushCell(g_hSQL);
        Call_Finish();
        return;
    }

    Database.Connect(OnConnected, "default", retry);
}

public void OnConnected(Database db, const char[] error, int retry)
{
    if(db == null)
    {
        NP_Core_LogError("MySQL", "OnConnected", "Connect failed -> %s", error);
        if(++retry <= 10)
            CreateTimer(5.0, Timer_Reconnect, retry);
        else
            SetFailState("connect to database failed! -> %s", error);
        return;
    }

    g_hSQL = db;
    g_hSQL.SetCharset("utf8mb4"); //Support special UTF8 characters
    g_bConnected = true;
    
    PrintToServer("Database Connected!");
    
    Call_StartForward(g_hOnConnected);
    Call_PushCell(g_hSQL);
    Call_Finish();
    
    // parse data
    CheckingServer();
}

public Action Timer_Reconnect(Handle timer, int retry)
{
    ConnectToDatabase(retry);
    return Plugin_Stop;
}

public void NativeSave_Callback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    if(results == null || error[0] || results.AffectedRows == 0)
    {
        char m_szQueryString[2048];
        pack.Reset();
        pack.ReadString(m_szQueryString, 2048);
        NP_Core_LogError("MySQL", "NativeSave_Callback", "SQL Error: %s\nQuery: %s", (results == null || error[0]) ? error : "No affected row", m_szQueryString);
    }

    delete pack;
}

void CheckingServer()
{
    char m_szQuery[128];
    FormatEx(m_szQuery, 128, "SELECT * FROM `%s_servers` WHERE `ip`='%s' AND `port`='%d'", P_SQLPRE, g_szServerIp, g_iServerPort);
    DBResultSet _result = SQL_Query(g_hSQL, m_szQuery);
    if(_result == null)
    {
        char error[256];
        SQL_GetError(g_hSQL, error, 256);
        NP_Core_LogError("MySQL", "CheckingServer", "SQL Error: %s", error);
        RetrieveInfoFromKV();
        return;
    }
    
    if(!_result.FetchRow())
    {
        NP_Core_LogError("MySQL", "CheckingServer", "Not Found this server in database");
        SetFailState("Not Found this server in database");
        return;
    }
    
    g_iServerId = _result.FetchInt(0);
    g_iServerModId = _result.FetchInt(1);
    _result.FetchString(2, g_szHostName, 128);
    
    delete _result;

    if(g_Engine == Engine_CSGO)
    {
        // fix host name in gotv
        ConVar host_name_store = FindConVar("host_name_store");
        if(host_name_store != null)
            host_name_store.SetString("1", false, false);
    }

    SetConVarString(FindConVar("hostname"), g_szHostName, false, false);

    SaveInfoToKV();

    // we used random rcon password.
    GenerateRandomString(g_szRconPswd, 24);

    // sync to database
    FormatEx(m_szQuery, 128, "UPDATE `%s_servers` SET `rcon`='%s' WHERE `sid`='%d';", P_SQLPRE, g_szRconPswd, g_iServerId);
    NP_MySQL_SaveDatabase(m_szQuery);

    Call_StartForward(g_hOnAvailable);
    Call_PushCell(g_iServerId);
    Call_PushCell(g_iServerModId);
    Call_Finish();
}

void RetrieveInfoFromKV()
{
    char path[128];
    BuildPath(Path_SM, path, 128, "configs/NewPage/core.cfg");
    
    if(!FileExists(path))
        SetFailState("Connect to database error and kv NOT FOUND");
    
    KeyValues kv = new KeyValues("NewPage");
    
    if(!kv.ImportFromFile(path))
        SetFailState("Connect to database error and kv load failed!");
    
    g_iServerId = kv.GetNum("ServerId", -1);
    g_iServerModId = kv.GetNum("ServerModId", -1);
    kv.GetString("Hostname", g_szHostName, 128, "NewPage Server");
    
    delete kv;
    
    if(g_iServerId == -1)
        SetFailState("Why your server id still is -1");
    
    Call_StartForward(g_hOnAvailable);
    Call_PushCell(g_iServerId);
    Call_PushCell(g_iServerModId);
    Call_Finish();
}

void SaveInfoToKV()
{
    KeyValues kv = new KeyValues("NewPage");
    
    kv.SetNum("ServerId", g_iServerId);
    kv.SetNum("ServerModId", g_iServerModId);
    kv.SetString("Hostname", g_szHostName);
    kv.Rewind();

    char path[128];
    BuildPath(Path_SM, path, 128, "configs/NewPage/core.cfg");
    kv.ExportToFile(path);
    
    delete kv;
}

void GenerateRandomString(char[] buffer, int maxLen)
{
    // terminator
    maxLen--;

    char random[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234556789";
    int randlen = strlen(random) - 1;

    int n = 0;
    int c = 0;

    while(n < maxLen)
    {
        if(random[0] == '\0')
        {
            c = GetRandomInt(33, 126);
            buffer[n] = c;
        }
        else
        {
            c = GetRandomInt(0, randlen);
            buffer[n] = random[c];
        }

        n++;
    }

    buffer[maxLen] = '\0';
}

public void OnMapStart()
{
    // only use in csgo.
    if(g_Engine != Engine_CSGO)
        return;
        
    // fake offical server
    GameRules_SetProp("m_bIsValveDS", 1, 0, 0, true);
}