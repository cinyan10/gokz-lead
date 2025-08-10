#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#include <gokz/core>
#include <gokz/replays>

#include "gokz-lead/utils.sp"

enum struct LeadSession
{
    int   user;
    int   botSlot;
    int   botClient;
    Handle timer;
    int   stopDist;
    int   startDist;
    float lastPos[3];
    bool  trail;

    void Reset()
    {
        this.user      = 0;
        this.botSlot   = -1;
        this.botClient = 0;
        // if (this.timer != null && this.timer != INVALID_HANDLE)
        // {
        //     CloseHandle(this.timer);
        // }
        this.timer     = null;
        this.stopDist  = 500;
        this.startDist = 200;
        this.lastPos[0] = this.lastPos[1] = this.lastPos[2] = 0.0;
        this.trail     = false;
    }

    bool Active() { return this.botSlot >= 0; }
}

static LeadSession g_Session[MAXPLAYERS + 1];
static int g_BeamIndex = -1;

// tiny helper
static void CopyVec(const float src[3], float dest[3])
{
    dest[0] = src[0];
    dest[1] = src[1];
    dest[2] = src[2];
}

public Plugin myinfo =
{
    name        = "GOKZ Replay Bot Lead",
    author      = "Cinyan10",
    description = "Per-user lead bots with distance pause/resume.",
    version     = "1.1.0",
    url         = "https://axekz.com/"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_lead", Command_Lead);
    for (int i = 1; i <= MaxClients; i++)
        g_Session[i].Reset();
}

public void OnMapStart()
{
    g_BeamIndex = PrecacheModel("materials/sprites/purplelaser1.vmt", true);
    for (int i = 1; i <= MaxClients; i++)
        g_Session[i].Reset();
}

public void OnClientDisconnect_Post(int client)
{
    if (client <= 0) return;

    // If a user with an active session leaves, stop their lead.
    if (client <= MaxClients && g_Session[client].Active())
    {
        StopLead(client);
        return;
    }

    // If a replay bot used by someone disconnected (likely auto-kicked),
    // just clean that user's session without kicking/SetBotIsAuto again.
    int owner = FindOwnerByBotClient(client);
    if (owner > 0)
    {
        // close timer once
        if (g_Session[owner].timer != null && g_Session[owner].timer != INVALID_HANDLE)
            CloseHandle(g_Session[owner].timer);
        g_Session[owner].timer = null;

        // zero out bot references; leave other fields intact
        g_Session[owner].botClient = 0;
        g_Session[owner].botSlot   = -1;
        g_Session[owner].trail     = false;

        // Optional UX:
        // GOKZ_PrintToChat(owner, true, "Your lead bot has disconnected.");
    }
}


public Action Command_Lead(int client, int args)
{
    LogMessage("user %d used !lead", client);

    if (!IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Handled;

    // Toggle OFF
    if (g_Session[client].Active())
    {
        StopLead(client);
        GOKZ_PrintToChat(client, true, "Lead stopped.");
        return Plugin_Handled;
    }

    // Distances
    int stopDist = 500, startDist = 200;
    if (args >= 2)
    {
        char a1[16], a2[16];
        GetCmdArg(1, a1, sizeof(a1));
        GetCmdArg(2, a2, sizeof(a2));
        stopDist  = StringToInt(a1);
        startDist = StringToInt(a2);

        if (startDist <= 10 || startDist >= 500 || stopDist <= 300 || stopDist >= 1000 || stopDist <= startDist)
        {
            GOKZ_PrintToChat(client, true, "Invalid distances. Use: 300 < stopDist < 1000, 10 < startDist < 500, and stopDist > startDist.");
            return Plugin_Handled;
        }
    }

    // Replay path
    char bestPath[PLATFORM_MAX_PATH];
    if (!FindBestReplayFilePath(bestPath, sizeof(bestPath)))
    {
        GOKZ_PrintToChat(client, true, "No replay found for this map.");
        return Plugin_Handled;
    }

    // Spawn (returns BOT SLOT)
    int botSlot = GOKZ_RP_LoadJumpReplay(client, bestPath, true);
    if (botSlot < 0)
    {
        GOKZ_PrintToChat(client, true, "Failed to create replay bot. Try again.");
        return Plugin_Handled;
    }

    // Prime session
    g_Session[client].Reset();
    g_Session[client].user      = client;
    g_Session[client].botSlot   = botSlot;
    g_Session[client].stopDist  = stopDist;
    g_Session[client].startDist = startDist;

    // Attach 0.2s later
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    CreateTimer(0.2, Timer_AttachLead, pack, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}

public Action Timer_AttachLead(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    delete pack;

    int user = GetClientOfUserId(userId);
    if (!user || !IsClientInGame(user) || IsFakeClient(user))
        return Plugin_Stop;

    if (!g_Session[user].Active())
        return Plugin_Stop;

    int botClient = GOKZ_RP_GetClientFromBot(g_Session[user].botSlot);
    if (botClient <= 0 || !IsClientInGame(botClient) || !IsFakeClient(botClient))
    {
        GOKZ_PrintToChat(user, true, "Replay bot not ready.");
        StopLead(user);
        return Plugin_Stop;
    }

    g_Session[user].botClient = botClient;
    g_Session[user].trail     = true;
    GetClientAbsOrigin(botClient, g_Session[user].lastPos);

    StartLeadFromNearestPoint(user, g_Session[user].botSlot);

    DataPack t = new DataPack();
    t.WriteCell(GetClientUserId(user));
    g_Session[user].timer = CreateTimer(0.2, Timer_LeadTick, t, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    GOKZ_PrintToChat(user, true, "Lead started. Use !lead again to stop.");
    return Plugin_Stop;
}

public Action Timer_LeadTick(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    // don't delete pack; repeating timer keeps it alive

    int user = GetClientOfUserId(userId);
    if (!user || !IsClientInGame(user))
        return Plugin_Stop;

    if (!g_Session[user].Active())
        return Plugin_Stop;

    int bot = g_Session[user].botClient;
    if (!IsClientInGame(bot) || !IsPlayerAlive(user) || !IsPlayerAlive(bot))
        return Plugin_Continue;

    float u[3], b[3];
    GetClientAbsOrigin(user, u);
    GetClientAbsOrigin(bot,  b);
    float dist = GetVectorDistance(u, b);

    if (dist > float(g_Session[user].stopDist))
        GOKZ_RP_Pause(g_Session[user].botSlot);
    else if (dist < float(g_Session[user].startDist))
        GOKZ_RP_Resume(g_Session[user].botSlot);

    return Plugin_Continue;
}

static void StopLead(int user)
{
    // close per-user timer once
    if (g_Session[user].timer != null && g_Session[user].timer != INVALID_HANDLE)
        CloseHandle(g_Session[user].timer);
    g_Session[user].timer = null;

    // tell replays side we’re done
    if (g_Session[user].botSlot >= 0)
    {
        GOKZ_RP_SetBotIsAuto(g_Session[user].botSlot, false);
        GOKZ_RP_Resume(g_Session[user].botSlot);
    }

    // if the bot is still around, kick it; otherwise skip
    int bc = g_Session[user].botClient;
    if (bc > 0 && IsClientInGame(bc) && IsFakeClient(bc))
    {
        char name[MAX_NAME_LENGTH];
        GetClientName(bc, name, sizeof(name));
        ServerCommand("bot_kick %s", name);
    }

    g_Session[user].Reset();
}

static int FindOwnerByBotClient(int botClient)
{
    for (int i = 1; i <= MaxClients; i++)
        if (g_Session[i].Active() && g_Session[i].botClient == botClient)
            return i;
    return 0;
}

static void StartLeadFromNearestPoint(int user, int botSlot)
{
    int total = GOKZ_RP_GetTickCount(botSlot);

    float vecUser[3];
    GetClientAbsOrigin(user, vecUser);

    const int step = 32;
    float best = -1.0;
    int   bestTick = -1;

    float vecBot[3];
    for (int t = 0; t < total; t += step)
    {
        if (!GetReplayTickOrigin(botSlot, t, vecBot))
            continue;

        float d = GetVectorDistance(vecUser, vecBot);
        if (bestTick == -1 || d < best)
        {
            best = d;
            bestTick = t;
        }
    }

    if (bestTick != -1)
    {
        GOKZ_RP_SkipToTick(botSlot, bestTick);
        GOKZ_RP_Resume(botSlot);
        GOKZ_PrintToChat(user, true, "Resuming from tick {teamcolor}%d{default} (%.1f units).", bestTick, best);
    }
    else
    {
        GOKZ_PrintToChat(user, true, "No valid tick found.");
    }
}

// Draw beam
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3],
    int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    int owner = FindOwnerByBotClient(client);
    if (owner <= 0 || !g_Session[owner].trail)
        return Plugin_Continue;

    float v1[3], v2[3];
    GetClientAbsOrigin(client, v1);
    CopyVec(g_Session[owner].lastPos, v2);

    TE_SetupBeamPoints(v1, v2, g_BeamIndex, 0, 0, 0, 2.5, 3.0, 3.0, 10, 0.0, {42, 165, 247, 255}, 0);
    TE_SendToClient(owner);

    CopyVec(v1, g_Session[owner].lastPos);
    return Plugin_Continue;
}
