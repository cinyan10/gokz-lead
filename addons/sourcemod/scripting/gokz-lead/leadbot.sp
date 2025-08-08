enum LeadBotType
{
    LeadBotType_Lead = 0,
    LeadBotType_Ghost
}

enum struct LeadBot
{
    int user;
    int botClient;
    int botIndex;
    bool paused;
    float lastPos[3];
    Handle timer;
    LeadBotType type; // NEW: bot type
}

LeadBot g_Lead;
bool g_bTrail[MAXPLAYERS + 1];

void LeadBot_Reset()
{
    if (g_Lead.botClient > 0 && g_Lead.botClient <= MaxClients)
    {
        g_bTrail[g_Lead.botClient] = false;
    }

    g_Lead.user = 0;
    g_Lead.botClient = 0;
    g_Lead.botIndex = -1;
    g_Lead.paused = false;
    g_Lead.type = LeadBotType_Lead; // default type

    if (g_Lead.timer != INVALID_HANDLE)
    {
        CloseHandle(g_Lead.timer);
        g_Lead.timer = INVALID_HANDLE;
    }
}

bool LeadBot_IsValid()
{
    return g_Lead.user > 0 && g_Lead.botClient > 0 && g_Lead.botIndex >= 0;
}
