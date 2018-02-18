#define NP_BANURL "https://new-page.cc/ban"

#if defined _NewPage_User_Manager_Include_
    #endinput
#endif

#define _NewPage_User_Manager_Include_

#define VIPMAXLEVEL 8

enum Authentication
{
    Spt,  //Supporter
    Vip,  //VIP
    Ctb,  //Contributor
    Opt,  //Operator
    Adm,  //Administrator
    Own   //Owner
}


forward void OnClientAuthChecked(int client, bool Spt, bool Vip, bool Ctb, bool Opt, bool Adm, bool Own);
forward void OnClientDataChecked(int client, int UserIdentity);
native int NP_Users_UserIdentity(int client);
native int NP_Users_VIPLevel(int client);
native bool NP_Users_IsVIP(int client);
native bool NP_Users_IsAuthorized(int client, Authentication auth);
native void NP_Users_BanClient(int admin,  int target, int banType, int banLength, const char[] banReason);
native void NP_Users_BanIdentity(int admin, const char[] steamIdentity, int banType, int banLength, const char[] banReason);

public SharedPlugin __pl_np_stats =
{
	name = "np-stats",
	file = "np-stats.smx",
#if !defined REQUIRE_PLUGIN
    required = 0
#else
    required = 1
#endif
};

/* Ban type translation */
stock void Bantype(const int btype, char[] buffer, int maxlength)
{
    switch(btype)
    {
        case 0:
        {
            FormatEx(buffer, maxlength, "Ban type 0");
        }
        case 1:
        {
            FormatEx(buffer, maxlength, "Ban type 1");
        }
        case 2:
        {
            FormatEx(buffer, maxlength, "Ban type 2");
        }
    }
}