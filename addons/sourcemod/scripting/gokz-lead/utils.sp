
#define REPLAY_DIR_FORMAT "addons/sourcemod/data/gokz-replays/_runs/%s/"

stock void ReadReplayHeader(const char[] path, int &tickCount, char[] mapNameOut, int mapNameSize, int &course)
{
    tickCount = -1;
    course = -1;
    if (mapNameSize > 0) mapNameOut[0] = '\0';

    File file = OpenFile(path, "rb");
    if (file == null) return;

    int magic;  file.ReadInt32(magic);
    int format; file.ReadInt8(format);
    int type;   file.ReadInt8(type); // 0=Run, 1=Jump, 2=Cheater

    char mapName[64];

    if (format == 1)
    {
        // Skip GOKZ version
        char tmp[2];
        ReadPascalStringClamped(file, tmp, sizeof(tmp));

        // Map name
        ReadPascalStringClamped(file, mapName, sizeof(mapName));

        // Read course
        file.ReadInt32(course);

        // Skip mode + style (2x Int32)
        file.Seek(8, SEEK_CUR);

        // Skip time, teleports, steamID (3x Int32)
        file.Seek(12, SEEK_CUR);

        // Skip SteamID2
        ReadPascalStringClamped(file, tmp, sizeof(tmp));

        // Skip IP
        ReadPascalStringClamped(file, tmp, sizeof(tmp));

        // Skip alias
        ReadPascalStringClamped(file, tmp, sizeof(tmp));

        // Read tick count
        file.ReadInt32(tickCount);
    }
    else if (format == 2)
    {
        // Skip GOKZ version
        char tmp[2];
        ReadPascalStringClamped(file, tmp, sizeof(tmp));

        // Map name
        ReadPascalStringClamped(file, mapName, sizeof(mapName));

        // Skip mapFileSize, ip, timestamp (3x Int32)
        file.Seek(12, SEEK_CUR);

        // Skip alias
        ReadPascalStringClamped(file, tmp, sizeof(tmp));

        // Skip steamid (Int32), mode (Int8), style (Int8), sens (Int32), yaw (Int32), tickrate (Int32)
        file.Seek(4 + 1 + 1 + 4 + 4 + 4, SEEK_CUR);

        // Read tick count
        file.ReadInt32(tickCount);

        // Skip weapon, knife
        file.Seek(8, SEEK_CUR);

        // If it's a run, skip time and read course
        if (type == 0 /* ReplayType_Run */)
        {
            file.Seek(4, SEEK_CUR);     // time
            file.ReadInt8(course);      // course
        }
        else
        {
            course = -1;
        }
    }
    // Unknown format: leave defaults

    // Copy map name out
    if (mapNameSize > 0)
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
    FileType ftype;

    while (files.GetNext(fileName, sizeof(fileName), ftype))
    {
        if (ftype != FileType_File) continue;
        if (StrContains(fileName, ".replay", false) == -1) continue;

        char fullPath[PLATFORM_MAX_PATH];
        Format(fullPath, sizeof(fullPath), "%s%s", dir, fileName);

        int tickCount = -1, course = -1;
        char mapName[64] = "";
        ReadReplayHeader(fullPath, tickCount, mapName, sizeof(mapName), course);

        if (tickCount <= 0) continue;
        if (!StrEqual(mapName, map, false)) continue;
        if (course != 0) continue;

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
    tickCount = -1;
    File file = OpenFile(path, "rb");
    if (file == null) return;

    int magic;  file.ReadInt32(magic);
    int format; file.ReadInt8(format);
    int type;   file.ReadInt8(type);

    char scratch[64];

    // gokzVersion
    ReadPascalStringClamped(file, scratch, sizeof(scratch));
    // mapName
    ReadPascalStringClamped(file, scratch, sizeof(scratch));

    // mapFileSize, ip, timestamp
    file.Seek(12, SEEK_CUR);

    // alias
    ReadPascalStringClamped(file, scratch, sizeof(scratch));

    // steamid, mode, style, sens, yaw, tickrate
    file.Seek(4 + 1 + 1 + 4 + 4 + 4, SEEK_CUR);

    // tickCount
    file.ReadInt32(tickCount);

    // weapon, knife
    file.Seek(8, SEEK_CUR);

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

    if (!DirExists(dir)) return false;

    DirectoryListing files = OpenDirectory(dir);
    if (files == null) return false;

    int bestTicks = -1;
    char bestPath[PLATFORM_MAX_PATH];
    FileType ftype;
    char fileName[PLATFORM_MAX_PATH];

    while (files.GetNext(fileName, sizeof(fileName), ftype))
    {
        if (ftype != FileType_File) continue;
        if (!HasServerPrefix(fileName)) continue;
        if (!EndsWith(fileName, ".replay")) continue;

        char fullPath[PLATFORM_MAX_PATH];
        Format(fullPath, sizeof(fullPath), "%s%s", dir, fileName);

        int tickCount = -1, course = -1;
        char mapName[64] = "";
        ReadReplayHeader(fullPath, tickCount, mapName, sizeof(mapName), course);

        if (tickCount <= 0) continue;
        if (!StrEqual(mapName, map, false)) continue;
        if (course != 0) continue;

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
        return true;
    }
    return false;
}
stock void CopyVec(const float src[3], float dest[3])
{
    dest[0] = src[0];
    dest[1] = src[1];
    dest[2] = src[2];
}

static void ReadPascalStringClamped(File file, char[] out, int outSize)
{
    int len; 
    file.ReadInt8(len);

    if (outSize <= 0) return;

    int copyLen = len;
    if (copyLen > outSize - 1) copyLen = outSize - 1;
    if (copyLen < 0) copyLen = 0;

    if (copyLen > 0)
        file.ReadString(out, outSize, copyLen);
    else
        out[0] = '\0';

    // Skip any remaining bytes from this field if it was longer than our buffer.
    if (len > copyLen)
        file.Seek(len - copyLen, SEEK_CUR);

    // Ensure null-termination (ReadString with explicit count doesn't do it).
    out[copyLen] = '\0';
}
