#include <sourcemod>
#include <gokz/replays>
#include <sdktools>
#include <colorlib>

int leadUserClient = 0; // The player using the lead bot
int leadBotClient = 0;  // The bot client in-game
int leadBotIndex = -1;  // The replay bot index
bool botPaused = false;
Handle hLeadTimer = INVALID_HANDLE;
#define REPLAY_DIR_FORMAT "addons/sourcemod/data/gokz-replays/_runs/%s/"

public Plugin myinfo = 
{
    name = "GOKZ Lead Bot",
    author = "Cinyan10",
    description = "Allows players to follow a replay bot which pauses/resumes based on distance.",
    version = "1.0.0",
    url = "https://axekz.com/"
};

public void OnPluginStart() {
    if (!LibraryExists("gokz-replays")) {
        SetFailState("GOKZ Replays plugin not found!");
    }

    RegConsoleCmd("sm_lead", Command_Lead);
}

public void OnClientPutInServer(int client) {
    if (!IsFakeClient(client)) {
        int humanCount = 0;
        for (int i = 1; i <= MaxClients; i++) {
            if (i != client && IsClientInGame(i) && !IsFakeClient(i)) {
                humanCount++;
            }
        }

        if (humanCount == 0) {
            StartReplayForCurrentMap();
        }
    }
}

public void OnMapStart() {
    leadUserClient = 0;
    leadBotClient = 0;
    leadBotIndex = -1;
    botPaused = false;
    hLeadTimer = INVALID_HANDLE;

    if (GetClientCount(true) > 0) {
        CreateTimer(1.0, Timer_ReplayNext);
    }
}

public void OnPlayerDisconnect(Handle event, const char[] name, bool dontBroadcast) {
    int userid = GetEventInt(event, "userid");
    int client = GetClientOfUserId(userid);
    if (client <= 0) return;

    if (IsFakeClient(client)) {
        if (leadBotClient == client) {
            leadBotClient = 0;
            leadBotIndex = -1;
            leadUserClient = 0;
            KillLeadTimer();
        }
        if (GetClientCount(true) > 0) {
            CreateTimer(1.0, Timer_ReplayNext);
        }
    } else {
        if (leadUserClient == client) {
            leadUserClient = 0;
            leadBotIndex = -1;
            KillLeadTimer();
        }
        if (GetClientCount(true) == 0) {
            // autoReplayActive = false;
        }
    }
}

void KillLeadTimer() {
    if (hLeadTimer != INVALID_HANDLE) {
        CloseHandle(hLeadTimer);
        hLeadTimer = INVALID_HANDLE;
    }
}

public int FindFirstHumanClient() {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            return i;
        }
    }
    return 0;
}

public Action Timer_ReplayNext(Handle timer) {
    int client = FindFirstHumanClient();
    if (client != 0) {
        StartReplayForCurrentMap();
    }
    return Plugin_Stop;
}

void StartReplayForCurrentMap()
{
    char bestPath[PLATFORM_MAX_PATH];
    if (!FindBestReplayFilePath(bestPath, sizeof(bestPath)))
    {
        LogMessage("[ReplayProgress] No valid replay found for this map.");
        return;
    }
    LogMessage("[ReplayProgress] found best path %s", bestPath)
    int client = FindFirstHumanClient();
    if (client == 0)
    {
        LogMessage("[ReplayProgress] No human client found.");
        return;
    }

    GOKZ_RP_LoadJumpReplay(client, bestPath, true);
    LogMessage("[ReplayProgress] Loaded replay: %s", bestPath);
}

public Action Command_Lead(int client, int args) {
    if (!IsClientInGame(client) || IsFakeClient(client)) return Plugin_Handled;

    if (leadUserClient == client) {
        GOKZ_RP_Resume(leadBotIndex);
        botPaused = false;

        CPrintToChat(client, "{lightgreen}[gokz-lead]{default} Lead stopped.");
        leadUserClient = 0;
        leadBotClient = 0;
        leadBotIndex = -1;
        KillLeadTimer();
        return Plugin_Handled;
    }

    int stopDist = 500;
    int startDist = 200;

    if (args >= 2) {
        char arg1[16], arg2[16];
        GetCmdArg(1, arg1, sizeof(arg1));
        GetCmdArg(2, arg2, sizeof(arg2));
        stopDist = StringToInt(arg1);
        startDist = StringToInt(arg2);

        if (startDist <= 10 || startDist >= 500 || stopDist <= 300 || stopDist >= 1000 || stopDist <= startDist) {
            CPrintToChat(client, "{lightgreen}[gokz-lead]{default} Invalid distances. Use: 300 < stopDist < 1000, 10 < startDist < 500, and stopDist > startDist.");
            return Plugin_Handled;
        }
    }

    if (leadUserClient > 0) {
        CPrintToChat(client, "{lightgreen}[gokz-lead]{default} Another player is already using the lead bot.");
        return Plugin_Handled;
    }

    int bot = -1;
    for (int i = 1; i <= MaxClients; i++) {
        bot = GOKZ_RP_GetBotSlotFromClient(i);
        if (bot >= 0) {
            leadBotIndex = bot;
            leadBotClient = i;
            leadUserClient = client;
            botPaused = false;

            char name[MAX_NAME_LENGTH];
            GetClientName(i, name, sizeof(name));
            CPrintToChat(client, "{lightgreen}[gokz-lead]{default} Using existing replay bot {teamcolor}%s{default} as your lead. Use !lead again to stop.", name);

            StartLeadFromNearestPoint(leadUserClient, leadBotIndex);

            KillLeadTimer();
            DataPack pack = new DataPack();
            pack.WriteCell(stopDist);
            pack.WriteCell(startDist);
            hLeadTimer = CreateTimer(0.2, Timer_LeadCheck, pack, TIMER_REPEAT);
            return Plugin_Handled;
        }
    }
    
    // add bot for another player
    CPrintToChat(client, "{lightgreen}[gokz-lead]{default} No available replay bot found on this map.");
    return Plugin_Handled;
}

public Action Timer_LeadCheck(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int stopDist = pack.ReadCell();
    int startDist = pack.ReadCell();

    if (leadUserClient == 0 || leadBotClient == 0) return Plugin_Stop;
    if (!IsClientInGame(leadUserClient) || !IsClientInGame(leadBotClient)) return Plugin_Stop;
    if (!IsPlayerAlive(leadUserClient) || !IsPlayerAlive(leadBotClient)) return Plugin_Stop;

    float vecClient[3], vecBot[3];
    GetClientAbsOrigin(leadUserClient, vecClient);
    GetClientAbsOrigin(leadBotClient, vecBot);
    float dist = GetVectorDistance(vecClient, vecBot);

    if (dist > float(stopDist) && !botPaused) {
        GOKZ_RP_Pause(leadBotIndex);
        botPaused = true;
    } else if (dist < float(startDist) && botPaused) {
        GOKZ_RP_Resume(leadBotIndex);
        botPaused = false;
    }

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
    
        CPrintToChat(client, "{lightgreen}[gokz-lead]{default} Resuming replay from tick {teamcolor}%d{default} (closest distance: %.1f)", closestTick, closestDist);
	}
	else
	{
        CPrintToChat(client, "{lightgreen}[gokz-lead]{default} No valid tick found.");
	}
}


bool GetReplayTickOrigin(int botIndex, int tick, float vec[3])
{
	any data[RP_V2_TICK_DATA_BLOCKSIZE];
	if (!GOKZ_RP_GetTickData(botIndex, tick, data))
		return false;

	vec[0] = data[7];  // origin.x
	vec[1] = data[8];  // origin.y
	vec[2] = data[9];  // origin.z
	return true;
}

bool FindBestReplayFilePath(char[] outPath, int maxlen)
{
    char map[64];
    GetCurrentMap(map, sizeof(map));

    char dir[PLATFORM_MAX_PATH];
    Format(dir, sizeof(dir), REPLAY_DIR_FORMAT, map); // e.g. "addons/sourcemod/data/gokz-replays/_runs/bkz_goldbhop/"

    DirectoryListing files = OpenDirectory(dir);
    if (files == null) return false;

    int bestTicks = -1;
    char bestPath[PLATFORM_MAX_PATH];
    char fileName[PLATFORM_MAX_PATH];
    FileType type;

    while (files.GetNext(fileName, sizeof(fileName), type))
    {
        if (type != FileType_File || !StrContains(fileName, ".replay", false))
            continue;

        char fullPath[PLATFORM_MAX_PATH];
        Format(fullPath, sizeof(fullPath), "%s%s", dir, fileName);

        int tickCount, course;
        char mapName[64];
        ReadReplayHeader(fullPath, tickCount, mapName, sizeof(mapName), course);

        // 必须是当前地图 & course 0
        if (!StrEqual(mapName, map, false) || course != 0)
            continue;

        if (bestTicks == -1 || tickCount < bestTicks)
        {
            bestTicks = tickCount;
            strcopy(bestPath, sizeof(bestPath), fullPath);
        }
    }

    delete files;

    if (bestTicks > 0)
    {
        strcopy(outPath, maxlen, bestPath);
        LogMessage("Best replay path: %s (tickCount = %d)", bestPath, bestTicks);
        return true;
    }

    return false;
}

void ReadReplayHeader(const char[] path, int &tickCount, char[] mapNameOut, int mapNameSize, int &course)
{
    File file = OpenFile(path, "rb");
    if (file == null) {
        LogMessage("[ReplayLoader] Failed to open file: %s", path);
        return;
    }

    int magic; file.ReadInt32(magic);
    int format; file.ReadInt8(format);
    int type; file.ReadInt8(type); // 0=Run, 1=Jump, 2=Cheater

    int len;
    char mapName[64];

    if (format == 1)
    {
        // Skip GOKZ version
        file.ReadInt8(len);
        file.Seek(len, SEEK_CUR);

        // Map name
        file.ReadInt8(len);
        file.ReadString(mapName, sizeof(mapName), len);
        mapName[len] = '\0';

        // Read course
        file.ReadInt32(course);

        // Skip mode + style (2x Int32)
        file.Seek(8, SEEK_CUR);

        // Skip time, teleports, steamID (3x Int32)
        file.Seek(12, SEEK_CUR);

        // Skip SteamID2
        file.ReadInt8(len);
        file.Seek(len, SEEK_CUR);

        // Skip IP
        file.ReadInt8(len);
        file.Seek(len, SEEK_CUR);

        // Skip alias
        file.ReadInt8(len);
        file.Seek(len, SEEK_CUR);

        // Read tick count
        file.ReadInt32(tickCount);
    }
    else if (format == 2)
    {
        // Skip GOKZ version
        file.ReadInt8(len);
        file.Seek(len, SEEK_CUR);

        // Map name
        file.ReadInt8(len);
        file.ReadString(mapName, sizeof(mapName), len);
        mapName[len] = '\0';

        // Skip mapFileSize, ip, timestamp (3x Int32)
        file.Seek(12, SEEK_CUR);

        // Skip alias
        file.ReadInt8(len);
        file.Seek(len, SEEK_CUR);

        // Skip steamid (Int32), mode (Int8), style (Int8), sens (Int32), yaw (Int32), tickrate (Int32)
        file.Seek(4 + 1 + 1 + 4 + 4 + 4, SEEK_CUR);

        // Read tick count
        file.ReadInt32(tickCount);

        // Skip weapon, knife
        file.Seek(8, SEEK_CUR);

        // If it's a run, read time and course
        if (type == ReplayType_Run)
        {
            // Skip time
            file.Seek(4, SEEK_CUR);

            // Read course
            file.ReadInt8(course);
        }
        else
        {
            course = -1; // N/A
        }
    }
    else
    {
        LogMessage("[ReplayLoader] Unknown replay format: %d", format);
        delete file;
        return;
    }

    // Copy map name out
    strcopy(mapNameOut, mapNameSize, mapName);

    LogMessage("[ReplayLoader] Header Info:\n Format = %d\n Type = %d\n Map = %s\n Course = %d\n TickCount = %d",
        format, type, mapNameOut, course, tickCount);

    delete file;
}
