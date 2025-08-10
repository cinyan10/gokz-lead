#include <sourcemod>
#include <sdktools>

#include <gokz/core>
#include <gokz/replays>

#include "gokz-lead/utils.sp"

bool g_CurrentIsServerRecord = false;

public Plugin myinfo =
{
    name        = "GOKZ Auto Replay Bot",
    author      = "Cinyan10",
    description = "Automatically loads a replay bot when the first human joins.",
    version     = "1.0.0",
    url         = "https://axekz.com/"
};

public void OnPluginStart()
{
    CreateTimer(1.0, Timer_KickBotsThenStartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int client) {
    if (!IsValidClient(client) || IsFakeClient(client))
        return;

    int humans = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            humans++;
    }

    if (humans == 1)
    {
        CreateTimer(1.0, Timer_KickBotsThenStartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action GOKZ_RP_OnReplaySaved(int client, int replayType, const char[] map, int course, int timeType, float time, const char[] filePath, bool tempReplay)
{
    // CreateTimer(2.0, Timer_CheckAndMaybeReloadReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Timer_KickBotsThenStartReplay(Handle timer, any data)
{
    ServerCommand("bot_kick"); // make sure no classic bots remain
    CreateTimer(1.0, Timer_StartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_StartReplay(Handle timer, any data)
{
    StartReplayForCurrentMap();
    return Plugin_Stop;
}

static void StartReplayForCurrentMap()
{
    char bestPath[PLATFORM_MAX_PATH];

    bool foundServerRecord = FindBestServerRecordReplay(bestPath, sizeof(bestPath));
    bool found = foundServerRecord;

    if (!foundServerRecord)
    {
        LogMessage("[AutoReplay] No server-record replay found; falling back to any replay…");
        found = FindBestReplayFilePath(bestPath, sizeof(bestPath));
        if (!found)
        {
            LogMessage("[AutoReplay] No replay found at all for this map.");
            return;
        }
    }

    int client = FindFirstHumanClient();
    if (client == 0)
    {
        LogMessage("[AutoReplay] No human client to own the replay load.");
        return;
    }

    if (GOKZ_RP_LoadJumpReplay(client, bestPath, true))
    {
        g_CurrentIsServerRecord = foundServerRecord;
        LogMessage("[AutoReplay] Loaded replay: %s (serverRecord=%d)", bestPath, g_CurrentIsServerRecord);
    }

}


public Action Timer_CheckAndMaybeReloadReplay(Handle timer, any data)
{
    char bestPath[PLATFORM_MAX_PATH];

    // Prefer server-record; remember if we found one
    bool foundServerRecord = FindBestServerRecordReplay(bestPath, sizeof(bestPath));
    bool found = foundServerRecord;
    if (!found)
        found = FindBestReplayFilePath(bestPath, sizeof(bestPath));

    if (!found)
    {
        return Plugin_Stop;
    }

    int bestTicks = -1;
    ReadReplayTickCount(bestPath, bestTicks);
    bool bestIsServerRecord = foundServerRecord;  // ← no helper needed

    // Find current bot (if any)
    int currentBotIndex = -1;
    for (int i = 1; i <= MaxClients; i++)
    {
        int idx = GOKZ_RP_GetBotSlotFromClient(i);
        if (idx >= 0) { currentBotIndex = idx; break; }
    }

    if (currentBotIndex < 0)
    {
        CreateTimer(0.1, Timer_StartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    int currentTicks = GOKZ_RP_GetTickCount(currentBotIndex);

    // Upgrade to server-record even if ticks are equal
    if (bestIsServerRecord && !g_CurrentIsServerRecord)
    {
        CreateTimer(0.5, Timer_KickBotsThenStartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    // Otherwise reload only if strictly better
    if (bestTicks > 0 && (currentTicks <= 0 || bestTicks < currentTicks))
    {
        CreateTimer(0.5, Timer_KickBotsThenStartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    }

    return Plugin_Stop;
}
