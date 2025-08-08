#include <sourcemod>
#include <sdktools>

#include <gokz/core>
#include <gokz/replays>

#include "gokz-lead/utils.sp"
#include "gokz-lead/leadbot.sp"

// Handle hLeadTimer = INVALID_HANDLE;
int g_BeamIndex = -1;
static bool hasSpawned[MAXPLAYERS + 1];

public Plugin myinfo = 
{
    name = "GOKZ Replay Bot Lead",
    author = "Cinyan10",
    description = "Allows players to follow a replay bot which pauses/resumes based on distance.",
    version = "1.0.0",
    url = "https://axekz.com/"
};

public void OnPluginStart() {
    LeadBot_Reset();
    RegConsoleCmd("sm_lead", Command_Lead);
    RegConsoleCmd("sm_ghost", Command_Ghost); // new
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
}

public void OnMapStart() {
    LeadBot_Reset();
    g_BeamIndex = PrecacheModel("materials/sprites/purplelaser1.vmt", true);
}

public void OnClientPutInServer(int client) {
    OnClientPutInServer_FirstSpawn(client);
}

void OnClientPutInServer_FirstSpawn(int client)
{
	hasSpawned[client] = false;
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)  // player_spawn post hook
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsFakeClient(client)) {
        int humanCount = 0;
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && !IsFakeClient(i)) {
                humanCount++;
            }
        }

        if (humanCount == 1) {
            CreateTimer(0.1, Timer_KickBotsThenStartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public Action Timer_KickBotsThenStartReplay(Handle timer, any data) {
    ServerCommand("bot_kick")
    CreateTimer(0.5, Timer_StartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_StartReplay(Handle timer, any data) {
    StartReplayForCurrentMap();
    return Plugin_Stop;
}

public void OnClientDisconnect_Post(int client)
{
    if (client <= 0)
        return;

    if (client == g_Lead.user)
        LeadBot_Reset();
}

public Action GOKZ_RP_OnReplaySaved(int client, int replayType, const char[] map, int course, int timeType, float time, const char[] filePath, bool tempReplay)
{
    CreateTimer(2.0, Timer_CheckReplayUpdate, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Timer_CheckReplayUpdate(Handle timer, any data)
{
    char bestPath[PLATFORM_MAX_PATH];
    if (!FindBestReplayFilePath(bestPath, sizeof(bestPath)))
    {
        return Plugin_Stop;
    }

    int bestTickCount = 0;
    ReadReplayTickCount(bestPath, bestTickCount);

    // Always reload if no bot is currently running
    if (g_Lead.botIndex == -1 || g_Lead.botClient == 0 || !IsClientInGame(g_Lead.botClient))
    {
        CreateTimer(0.1, Timer_KickBotsThenStartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    int currentTickCount = GOKZ_RP_GetTickCount(g_Lead.botIndex);

    if (bestTickCount != currentTickCount)
    {
        CreateTimer(0.1, Timer_KickBotsThenStartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    return Plugin_Stop;
}

public int FindFirstHumanClient() {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            return i;
        }
    }
    return 0;
}

void StartReplayForCurrentMap()
{
    char bestPath[PLATFORM_MAX_PATH];
    if (!FindBestReplayFilePath(bestPath, sizeof(bestPath)))
    {
        return;
    }
    int client = FindFirstHumanClient();
    if (client == 0)
    {
        LogMessage("No human client found.");
        return;
    }

    GOKZ_RP_LoadJumpReplay(client, bestPath, true);
    LogMessage("Loaded replay: %s", bestPath);
}

public Action Command_Ghost(int client, int args)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Handled;

    if (g_Lead.user == client)
    {
        GOKZ_RP_Resume(g_Lead.botIndex);
        LeadBot_Reset();
        GOKZ_PrintToChat(client, true, "Ghost stopped.");
        return Plugin_Handled;
    }

    if (LeadBot_IsValid())
    {
        GOKZ_PrintToChat(client, true, "Another player is already using the replay bot.");
        return Plugin_Handled;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        int bot = GOKZ_RP_GetBotSlotFromClient(i);
        if (bot >= 0)
        {
            g_Lead.user = client;
            g_Lead.botClient = i;
            g_Lead.botIndex = bot;
            g_Lead.type = LeadBotType_Ghost; // ghost mode
            g_bTrail[i] = true;

            char name[MAX_NAME_LENGTH];
            GetClientName(i, name, sizeof(name));
            GOKZ_PrintToChat(client, true, "Using existing replay bot {teamcolor}%s{default} as your ghost. Use !ghost again to stop.", name);
            return Plugin_Handled;
        }
    }

    GOKZ_PrintToChat(client, true, "No available replay bot found on this map.");
    return Plugin_Handled;
}

public Action Command_Lead(int client, int args) {
    LogMessage("user %d used !lead", client)
    if (!IsClientInGame(client) || IsFakeClient(client)) return Plugin_Handled;

    // use command again to stop lead
    if (g_Lead.user == client) {
        GOKZ_RP_Resume(g_Lead.botIndex);
        LeadBot_Reset();

        GOKZ_PrintToChat(client, true, "Lead stopped.");
        return Plugin_Handled;
    }

    // args for manually set distance
    int stopDist = 500;
    int startDist = 200;
    if (args >= 2) {
        char arg1[16], arg2[16];
        GetCmdArg(1, arg1, sizeof(arg1));
        GetCmdArg(2, arg2, sizeof(arg2));
        stopDist = StringToInt(arg1);
        startDist = StringToInt(arg2);

        if (startDist <= 10 || startDist >= 500 || stopDist <= 300 || stopDist >= 1000 || stopDist <= startDist) {
            GOKZ_PrintToChat(client, true, "Invalid distances. Use: 300 < stopDist < 1000, 10 < startDist < 500, and stopDist > startDist.");
            return Plugin_Handled;
        }
    }

    if (LeadBot_IsValid()) {
        GOKZ_PrintToChat(client, true, "Another player is already using the lead bot.");
        return Plugin_Handled;
    }

    int bot = -1;
    for (int i = 1; i <= MaxClients; i++) {
        bot = GOKZ_RP_GetBotSlotFromClient(i);
        if (bot >= 0) {
            g_Lead.user = client;
            g_Lead.botClient = i;
            g_Lead.botIndex = bot;
            g_bTrail[i] = true;
            GetClientAbsOrigin(i, g_Lead.lastPos);

            char name[MAX_NAME_LENGTH];
            GetClientName(i, name, sizeof(name));
            GOKZ_PrintToChat(client, true, "Using existing replay bot {teamcolor}%s{default} as your lead. Use !lead again to stop.", name);

            StartLeadFromNearestPoint(g_Lead.user, g_Lead.botIndex);

            DataPack pack = new DataPack();
            pack.WriteCell(stopDist);
            pack.WriteCell(startDist);
            g_Lead.timer = CreateTimer(0.2, Timer_LeadCheck, pack, TIMER_REPEAT);
            return Plugin_Handled;
        }
    }
    
    // TODO: add bot for another player
    GOKZ_PrintToChat(client, true, "No available replay bot found on this map.");
    return Plugin_Handled;
}

// Draw beam
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3],
    int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (client == g_Lead.botClient && g_bTrail[client] && IsPlayerAlive(client)) {
        float v1[3], v2[3];
        GetClientAbsOrigin(client, v1);
        v2 = g_Lead.lastPos;

        TE_SetupBeamPoints(v1, v2, g_BeamIndex, 0, 0, 0, 2.5, 3.0, 3.0, 10, 0.0, {42, 165, 247, 255}, 0);
        TE_SendToAll();

        g_Lead.lastPos = v1;
    }
    return Plugin_Continue;
}

public Action Timer_LeadCheck(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int stopDist = pack.ReadCell();
    int startDist = pack.ReadCell();

    if (g_Lead.user == 0 || g_Lead.botClient == 0) return Plugin_Stop;
    if (!IsClientInGame(g_Lead.user) || !IsClientInGame(g_Lead.botClient)) return Plugin_Stop;
    if (!IsPlayerAlive(g_Lead.user) || !IsPlayerAlive(g_Lead.botClient)) return Plugin_Stop;

    float vecClient[3], vecBot[3];
    GetClientAbsOrigin(g_Lead.user, vecClient);
    GetClientAbsOrigin(g_Lead.botClient, vecBot);
    float dist = GetVectorDistance(vecClient, vecBot);

    if (dist > float(stopDist))
        GOKZ_RP_Pause(g_Lead.botIndex);
    else if (dist < float(startDist))
        GOKZ_RP_Resume(g_Lead.botIndex);

    return Plugin_Continue;
}

void StartLeadFromNearestPoint(int client, int botIndex)
{
	int totalTicks = GOKZ_RP_GetTickCount(botIndex);

	float vecClient[3];
	GetClientAbsOrigin(client, vecClient);

	const int tickStep = 32;
	float closestDist = -1.0;
	int closestTick = -1;

	float vecBot[3];
	for (int tick = 0; tick < totalTicks; tick += tickStep)
	{
		if (!GetReplayTickOrigin(botIndex, tick, vecBot))
			continue;

		float dist = GetVectorDistance(vecClient, vecBot);

		if (closestTick == -1 || dist < closestDist)
		{
			closestDist = dist;
			closestTick = tick;
		}
	}

	if (closestTick != -1)
	{
        GOKZ_RP_SkipToTick(botIndex, closestTick);
        GOKZ_RP_Resume(botIndex);
        GOKZ_PrintToChat(client, true, "Resuming replay from tick {teamcolor}%d{default} (closest distance: %.1f)", closestTick, closestDist);
	}
	else
	{
        GOKZ_PrintToChat(client, true, "No valid tick found.");
	}
}

public void GOKZ_OnTimerStart_Post(int client, int course)
{
    if (g_Lead.type == LeadBotType_Ghost && g_Lead.user == client && LeadBot_IsValid())
    {
        GOKZ_RP_SkipToTick(g_Lead.botIndex, 256);
        GOKZ_RP_Resume(g_Lead.botIndex);
    }
}

public void GOKZ_OnPause_Post(int client)
{
    if (g_Lead.type == LeadBotType_Ghost && g_Lead.user == client && LeadBot_IsValid())
    {
        GOKZ_RP_Pause(g_Lead.botIndex);
    }
}

public void GOKZ_OnResume_Post(int client)
{
    if (g_Lead.type == LeadBotType_Ghost && g_Lead.user == client && LeadBot_IsValid())
    {
        GOKZ_RP_Resume(g_Lead.botIndex);
    }
}
