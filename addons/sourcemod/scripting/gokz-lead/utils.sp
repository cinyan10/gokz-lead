
#define REPLAY_DIR_FORMAT "addons/sourcemod/data/gokz-replays/_runs/%s/"

stock void ReadReplayHeader(const char[] path, int &tickCount, char[] mapNameOut, int mapNameSize, int &course)
{
    File file = OpenFile(path, "rb");
    if (file == null) return;

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
        delete file;
        return;
    }

    // Copy map name out
    strcopy(mapNameOut, mapNameSize, mapName);

    delete file;
}

stock bool FindBestReplayFilePath(char[] outPath, int maxlen)
{
    char map[64];
    GetCurrentMap(map, sizeof(map));

    char dir[PLATFORM_MAX_PATH];
    Format(dir, sizeof(dir), REPLAY_DIR_FORMAT, map);

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

        // Must be current map & course 0
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

stock bool GetReplayTickOrigin(int botIndex, int tick, float vec[3])
{
	any data[RP_V2_TICK_DATA_BLOCKSIZE];
	if (!GOKZ_RP_GetTickData(botIndex, tick, data))
		return false;

	vec[0] = data[7];  // origin.x
	vec[1] = data[8];  // origin.y
	vec[2] = data[9];  // origin.z
	return true;
}

stock void kickNonReplayBot()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i))
            continue;

        char name[MAX_NAME_LENGTH];
        GetClientName(i, name, sizeof(name));

        int len = strlen(name);
        bool isReplay = (len >= 8 && StrContains(name, ":") != -1 && StrContains(name, ".") != -1 && name[len - 1] == ')');

        if (!isReplay)
        {
            KickClient(i, "Kicking non-replay bot.");
        }
    }
}

stock void ReadReplayTickCount(const char[] path, int &tickCount)
{
    File file = OpenFile(path, "rb");
    if (file == null) {
        LogMessage(" Failed to open file: %s", path);
        return;
    }

    int magic; file.ReadInt32(magic);
    int format; file.ReadInt8(format);
    int type; file.ReadInt8(type);

    int len;
    file.ReadInt8(len);
    char gokzVersion[64];
    file.ReadString(gokzVersion, sizeof(gokzVersion), len);

    file.ReadInt8(len);
    char mapName[64];
    file.ReadString(mapName, sizeof(mapName), len);

    int mapFileSize; file.ReadInt32(mapFileSize);
    int ip; file.ReadInt32(ip);
    int timestamp; file.ReadInt32(timestamp);

    file.ReadInt8(len);
    char alias[64];
    file.ReadString(alias, sizeof(alias), len);

    int steamid; file.ReadInt32(steamid);
    int mode; file.ReadInt8(mode);
    int style; file.ReadInt8(style);
    int sens; file.ReadInt32(sens);
    int yaw; file.ReadInt32(yaw);
    int tickrate; file.ReadInt32(tickrate);
    file.ReadInt32(tickCount);
    int weapon; file.ReadInt32(weapon);
    int knife; file.ReadInt32(knife);

    delete file;
}

stock int FindFirstHumanClient()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            return i;
    }
    return 0;
}

static bool EndsWith(const char[] s, const char[] suffix)
{
    int ls = strlen(s), lf = strlen(suffix);
    if (lf > ls) return false;
    return StrEqual(s[ls - lf], suffix, false);
}

static bool HasServerPrefix(const char[] file)
{
    // must START with one of these, case-insensitive
    if (strncmp(file, "0_KZT", 5, false) == 0) return true;
    if (strncmp(file, "0_VNL", 5, false) == 0) return true;
    if (strncmp(file, "0_SKZ", 5, false) == 0) return true;
    return false;
}

stock bool FindBestServerRecordReplay(char[] outPath, int maxlen)
{
    char map[64];
    GetCurrentMap(map, sizeof(map));

    char dir[PLATFORM_MAX_PATH];
    Format(dir, sizeof(dir), REPLAY_DIR_FORMAT, map);

    if (!DirExists(dir))
    {
        LogMessage("[FindBestServerRecordReplay] Dir not found: %s", dir);
        return false;
    }

    DirectoryListing files = OpenDirectory(dir);
    if (files == null)
    {
        LogMessage("[FindBestServerRecordReplay] OpenDirectory failed: %s", dir);
        return false;
    }

    int bestTicks = -1;
    char bestPath[PLATFORM_MAX_PATH];
    FileType type;
    char fileName[PLATFORM_MAX_PATH];

    int scanned = 0, considered = 0;

    while (files.GetNext(fileName, sizeof(fileName), type))
    {
        if (type != FileType_File) continue;
        scanned++;

        if (!HasServerPrefix(fileName)) continue;
        if (!EndsWith(fileName, ".replay")) continue;

        considered++;

        char fullPath[PLATFORM_MAX_PATH];
        Format(fullPath, sizeof(fullPath), "%s%s", dir, fileName);

        int tickCount = -1, course = -1;
        char mapName[64] = "";

        // your ReadReplayHeader has a void return — just call it
        ReadReplayHeader(fullPath, tickCount, mapName, sizeof(mapName), course);

        // Must be same map & course 0, and tickCount parsed
        if (tickCount <= 0) { LogMessage("[SR] skip (ticks<=0): %s", fileName); continue; }
        if (!StrEqual(mapName, map, false)) { LogMessage("[SR] skip (map mismatch %s!=%s): %s", mapName, map, fileName); continue; }
        if (course != 0) { LogMessage("[SR] skip (course=%d): %s", course, fileName); continue; }

        if (bestTicks == -1 || tickCount < bestTicks)
        {
            bestTicks = tickCount;
            strcopy(bestPath, sizeof(bestPath), fullPath);
        }
    }

    delete files;

    LogMessage("[FindBestServerRecordReplay] Scanned=%d, Considered=%d, BestTicks=%d, Dir=%s",
               scanned, considered, bestTicks, dir);

    if (bestTicks > 0)
    {
        strcopy(outPath, maxlen, bestPath);
        LogMessage("[FindBestServerRecordReplay] Best: %s", bestPath);
        return true;
    }

    LogMessage("[FindBestServerRecordReplay] No best replay found under: %s", dir);
    return false;
}
