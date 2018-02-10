#if defined _NewPage_Stats_Include_
    #endinput
#endif

#define _NewPage_Stats_Include_

native int NP_Stats_TodayOnlineTime(int client);
native int NP_Stats_TotalOnlineTime(int client);
native int NP_Stats_ObserveOnlineTime(int client);
native int NP_Stats_PlayOnlineTime(int client);
native int NP_Stats_Vitality(int client);

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