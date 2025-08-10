public Action Command_Lead(int client, int args)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Handled;

    if (g_Session[client].Active() && g_Session[client].mode == LeadMode_Ghost)
    {
        GOKZ_PlayErrorSound(client);
        GOKZ_PrintToChat(client, true, "You're already using !ghost. Use !ghost again to stop first.");
        return Plugin_Handled;
    }    

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

    g_Session[client].mode = LeadMode_Lead;

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
