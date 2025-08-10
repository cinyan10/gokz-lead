public Action Command_Ghost(int client, int args)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Handled;

    // Block if they're using !lead
    if (g_Session[client].Active() && g_Session[client].mode == LeadMode_Lead)
    {
        GOKZ_PlayErrorSound(client);
        GOKZ_PrintToChat(client, true, "You're already using !lead. Use !lead again to stop first.");
        return Plugin_Handled;
    }

    // Toggle OFF if already ghosting
    if (g_Session[client].Active() && g_Session[client].mode == LeadMode_Ghost)
    {
        // Stop & clean up the ghost bot we spawned
        StopLead(client);
        GOKZ_PrintToChat(client, true, "Ghost stopped.");
        return Plugin_Handled;
    }

    // Find best replay path
    char bestPath[PLATFORM_MAX_PATH];
    if (!FindBestReplayFilePath(bestPath, sizeof(bestPath)))
    {
        GOKZ_PrintToChat(client, true, "No replay found for this map.");
        return Plugin_Handled;
    }

    // Spawn a NEW replay bot (returns bot slot)
    int botSlot = GOKZ_RP_LoadJumpReplay(client, bestPath, true);
    if (botSlot < 0)
    {
        GOKZ_PrintToChat(client, true, "Failed to create replay bot. Try again.");
        return Plugin_Handled;
    }

    // Prime session for ghost
    g_Session[client].Reset();
    g_Session[client].user    = client;
    g_Session[client].botSlot = botSlot;
    g_Session[client].mode    = LeadMode_Ghost;

    // Attach 0.2s later (no distance timer for ghost)
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    CreateTimer(0.2, Timer_AttachGhost, pack, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}

public Action Timer_AttachGhost(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    delete pack;

    int user = GetClientOfUserId(userId);
    if (!user || !IsClientInGame(user) || IsFakeClient(user))
        return Plugin_Stop;

    if (!g_Session[user].Active() || g_Session[user].mode != LeadMode_Ghost)
        return Plugin_Stop;

    int botClient = GOKZ_RP_GetClientFromBot(g_Session[user].botSlot);
    if (botClient <= 0 || !IsClientInGame(botClient) || !IsFakeClient(botClient))
    {
        GOKZ_PrintToChat(user, true, "Replay bot not ready.");
        // Clean up ghost session on failure
        StopLead(user);
        return Plugin_Stop;
    }

    g_Session[user].botClient = botClient;
    g_Session[user].trail     = true; // show beam for the owner
    GetClientAbsOrigin(botClient, g_Session[user].lastPos);

    // Pause immediately; ghost will resume when the player's timer starts
    GOKZ_RP_Pause(g_Session[user].botSlot);

    GOKZ_PrintToChat(user, true, "Ghost started. Use !ghost again to stop.");
    return Plugin_Stop;
}

public void GOKZ_OnTimerStart_Post(int client, int course)
{
    if (g_Session[client].Active() && g_Session[client].mode == LeadMode_Ghost)
    {
        // Start a little ahead so it doesn't overlap your start
        GOKZ_RP_SkipToTick(g_Session[client].botSlot, 256);
        GOKZ_RP_Resume(g_Session[client].botSlot);
    }
}

public void GOKZ_OnPause_Post(int client)
{
    if (g_Session[client].Active() && g_Session[client].mode == LeadMode_Ghost)
        GOKZ_RP_Pause(g_Session[client].botSlot);
}

public void GOKZ_OnResume_Post(int client)
{
    if (g_Session[client].Active() && g_Session[client].mode == LeadMode_Ghost)
        GOKZ_RP_Resume(g_Session[client].botSlot);
}
