static GlobalForward H_OnReplaySaved;
static GlobalForward H_OnReplayDiscarded;
static GlobalForward H_OnTimerEnd_Post;

// =====[ NATIVES ]=====

void CreateNatives()
{
	CreateNative("GOKZ_RP_GetPlaybackInfo", Native_RP_GetPlaybackInfo);
	CreateNative("GOKZ_RP_LoadJumpReplay", Native_RP_LoadJumpReplay);
	CreateNative("GOKZ_RP_UpdateReplayControlMenu", Native_RP_UpdateReplayControlMenu);
	CreateNative("GOKZ_RP_Pause", Native_RP_Pause);
	CreateNative("GOKZ_RP_Resume", Native_RP_Resume);
	CreateNative("GOKZ_RP_GetBotSlotFromClient", Native_RP_GetBotSlotFromClient);
	CreateNative("GOKZ_RP_SkipToTick", Native_RP_SkipToTick);
	CreateNative("GOKZ_RP_GetTickCount", Native_RP_GetTickCount);
	CreateNative("GOKZ_RP_GetTickData", Native_RP_GetTickData);
}

public int Native_RP_GetTickData(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	int tick = GetNativeCell(2);

	any output[RP_V2_TICK_DATA_BLOCKSIZE];
	if (!GetReplayTickData(bot, tick, output))
		return false;

	SetNativeArray(3, output, RP_V2_TICK_DATA_BLOCKSIZE);
	return true;
}


public int Native_RP_SkipToTick(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	int tick = GetNativeCell(2);

	if (bot < 0 || bot >= RP_MAX_BOTS || tick < 0) return false;

	PlaybackSkipToTick(bot, tick);
	return true;
}

public int Native_RP_GetTickCount(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	return GetTickCount(bot);
}

public int Native_RP_GetBotSlotFromClient(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return GetBotFromClient(client);
}

public int Native_RP_GetPlaybackInfo(Handle plugin, int numParams)
{
	HUDInfo info;
	GetPlaybackState(GetNativeCell(1), info);
	SetNativeArray(2, info, sizeof(HUDInfo));
	return 1;
}

public int Native_RP_Pause(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	if (bot < 0 || bot >= RP_MAX_BOTS) return false;

	PlaybackPause(bot);
	return true;
}

public int Native_RP_Resume(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	if (bot < 0 || bot >= RP_MAX_BOTS) return false;

	PlaybackResume(bot);
	return true;
}

public int Native_RP_LoadJumpReplay(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(2, len);
	char[] path = new char[len + 1];
	GetNativeString(2, path, len + 1);

	bool isAuto = false;
	if (numParams >= 3)
	{
		isAuto = GetNativeCell(3);
	}

	int client = GetNativeCell(1);
	int botClient = LoadReplayBot(client, path, isAuto);
	return botClient;
}

public int Native_RP_UpdateReplayControlMenu(Handle plugin, int numParams)
{
	return view_as<int>(UpdateReplayControlMenu(GetNativeCell(1)));
}

// =====[ FORWARDS ]=====

void CreateGlobalForwards()
{
	H_OnReplaySaved = new GlobalForward("GOKZ_RP_OnReplaySaved", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_Float, Param_String, Param_Cell);
	H_OnReplayDiscarded = new GlobalForward("GOKZ_RP_OnReplayDiscarded", ET_Ignore, Param_Cell);
	H_OnTimerEnd_Post = new GlobalForward("GOKZ_RP_OnTimerEnd_Post", ET_Ignore, Param_Cell, Param_String, Param_Cell, Param_Float, Param_Cell);
}

Action Call_OnReplaySaved(int client, int replayType, const char[] map, int course, int timeType, float time, const char[] filePath, bool tempReplay)
{
	Action result;
	Call_StartForward(H_OnReplaySaved);
	Call_PushCell(client);
	Call_PushCell(replayType);
	Call_PushString(map);
	Call_PushCell(course);
	Call_PushCell(timeType);
	Call_PushFloat(time);
	Call_PushString(filePath);
	Call_PushCell(tempReplay);
	Call_Finish(result);
	return result;
}

void Call_OnReplayDiscarded(int client)
{
	Call_StartForward(H_OnReplayDiscarded);
	Call_PushCell(client);
	Call_Finish();
}

void Call_OnTimerEnd_Post(int client, const char[] filePath, int course, float time, int teleportsUsed)
{
	Call_StartForward(H_OnTimerEnd_Post);
	Call_PushCell(client);
	Call_PushString(filePath);
	Call_PushCell(course);
	Call_PushFloat(time);
	Call_PushCell(teleportsUsed);
	Call_Finish();
} 
