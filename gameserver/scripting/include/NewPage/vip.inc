#if defined _NewPage_Vip_Include_
    #endinput
#endif

#define _NewPage_Vip_Include_

native void NP_Vip_GrantVip(int client, int duration);
native void NP_Vip_DeleteVip(int client);
native void NP_Vip_AddVipPoint(int client, int point);

public SharedPlugin __pl_np_vip =
{
	name = "np-vip",
	file = "np-vip.smx",
#if !defined REQUIRE_PLUGIN
    required = 0
#else
    required = 1
#endif
};