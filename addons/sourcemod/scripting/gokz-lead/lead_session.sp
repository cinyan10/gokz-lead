LeadSession g_Session[MAXPLAYERS + 1];
int g_BeamIndex = -1;

enum LeadMode
{
    LeadMode_None = 0,
    LeadMode_Lead,
    LeadMode_Ghost
}

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
    LeadMode mode;

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
        this.mode      = LeadMode_None;
    }

    bool Active() { return this.botSlot >= 0; }
}

stock void StopLead(int user)
{
    if (g_Session[user].timer != null && g_Session[user].timer != INVALID_HANDLE)
        CloseHandle(g_Session[user].timer);
    g_Session[user].timer = null;

    if (g_Session[user].botSlot >= 0)
    {
        GOKZ_RP_SetBotIsAuto(g_Session[user].botSlot, false);

        int bc = g_Session[user].botClient;
        if (bc > 0 && IsClientInGame(bc) && IsFakeClient(bc))
        {
            char name[MAX_NAME_LENGTH];
            GetClientName(bc, name, sizeof(name));
            ServerCommand("bot_kick %s", name);
        }
    }

    g_Session[user].Reset();
}

stock int FindOwnerByBotClient(int botClient)
{
    for (int i = 1; i <= MaxClients; i++)
        if (g_Session[i].Active() && g_Session[i].botClient == botClient)
            return i;
    return 0;
}
