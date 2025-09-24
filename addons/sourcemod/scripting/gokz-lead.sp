#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#include <gokz/core>
#include <gokz/replays>

#include "gokz-lead/lead_session.sp"
#include "gokz-lead/utils.sp"
#include "gokz-lead/lead.sp"
#include "gokz-lead/ghost.sp"

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
    RegConsoleCmd("sm_ghost", Command_Ghost);
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

    TE_SetupBeamPoints(v1, v2, g_BeamIndex, 0, 0, 0, 4.0, 10.0, 10.0, 10, 0.0, {42, 165, 247, 255}, 0);
    TE_SendToClient(owner);

    CopyVec(v1, g_Session[owner].lastPos);
    return Plugin_Continue;
}
