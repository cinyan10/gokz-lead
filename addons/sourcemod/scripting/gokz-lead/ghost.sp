
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
