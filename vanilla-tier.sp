#include <json>
#include <sourcemod>
#include <SteamWorks>

#define API_HOST    "https://vnlkz.com/api"
#define CHAT_PREFIX "[\x0Evnlkz.com\x01]"
#define LOAD_RETRY_DELAY 5.0

#pragma newdecls required
#pragma dynamic 262144

#define PLUGIN_VERSION "1.0.3"

public Plugin myinfo =
{
  name        = "Vanilla Tier Plugin",
  author      = "BuSheeZy",
  description = "Show tier information for vanilla maps. (vnlkz.com)",
  version     = PLUGIN_VERSION,
  url         = "https://BadServers.net"
};

enum struct VanillaMap
{
  int  id;
  char name[64];
  int  kztTier;
  int  proTier;
  int  tpTier;
  char notes[512];
}

enum struct UncompletedMap
{
  int  id;
  char name[64];
  int  kztTier;
  char notes[512];
}

VanillaMap     g_VanillaMaps[2048];
UncompletedMap g_UncompletedMaps[2048];

Handle g_VanillaMapsRetryTimer;
Handle g_UncompletedMapsRetryTimer;

public void OnPluginStart()
{
  RegConsoleCmd("sm_vnltier", OnVanillaTierCmd, "Show the map's vanilla tier.");

  LoadVanillaMaps();
  LoadUncompletedMaps();
  ScheduleVanillaMapsRetry();
  ScheduleUncompletedMapsRetry();
}

void ScheduleVanillaMapsRetry()
{
  if (g_VanillaMapsRetryTimer == null)
  {
    g_VanillaMapsRetryTimer = CreateTimer(LOAD_RETRY_DELAY, Timer_RetryLoadVanillaMaps);
  }
}

void ScheduleUncompletedMapsRetry()
{
  if (g_UncompletedMapsRetryTimer == null)
  {
    g_UncompletedMapsRetryTimer = CreateTimer(LOAD_RETRY_DELAY, Timer_RetryLoadUncompletedMaps);
  }
}

public Action Timer_RetryLoadVanillaMaps(Handle timer)
{
  g_VanillaMapsRetryTimer = null;
  LoadVanillaMaps();
  return Plugin_Stop;
}

public Action Timer_RetryLoadUncompletedMaps(Handle timer)
{
  g_UncompletedMapsRetryTimer = null;
  LoadUncompletedMaps();
  return Plugin_Stop;
}

public Action OnVanillaTierCmd(int client, int args)
{
  if (args == 0)
  {
    char currentMapName[128];
    GetCurrentMap(currentMapName, sizeof(currentMapName));

    OutputMapTierInfoIfFound(client, currentMapName);

    return Plugin_Handled;
  }

  char mapNameArg[128];
  GetCmdArg(1, mapNameArg, sizeof(mapNameArg));

  OutputMapTierInfoIfFound(client, mapNameArg);

  return Plugin_Handled;
}

int GetVanillaMapIndexByName(char[] mapName)
{
  for (int i = 0; i < sizeof(g_VanillaMaps); i++)
  {
    if (StrContains(g_VanillaMaps[i].name, mapName) == 0)
    {
      return i;
    }
  }

  for (int i = 0; i < sizeof(g_VanillaMaps); i++)
  {
    if (StrContains(g_VanillaMaps[i].name, mapName) != -1)
    {
      return i;
    }
  }

  return -1;
}

void ClearVanillaMaps()
{
  VanillaMap empty;

  for (int i = 0; i < sizeof(g_VanillaMaps); i++)
  {
    g_VanillaMaps[i] = empty;
  }
}

void ClearUncompletedMaps()
{
  UncompletedMap empty;

  for (int i = 0; i < sizeof(g_UncompletedMaps); i++)
  {
    g_UncompletedMaps[i] = empty;
  }
}

int GetUncompletedMapIndexByName(char[] mapName)
{
  for (int i = 0; i < sizeof(g_UncompletedMaps); i++)
  {
    if (StrContains(g_UncompletedMaps[i].name, mapName) == 0)
    {
      return i;
    }
  }

  for (int i = 0; i < sizeof(g_UncompletedMaps); i++)
  {
    if (StrContains(g_UncompletedMaps[i].name, mapName) != -1)
    {
      return i;
    }
  }

  return -1;
}

void SanitizeHtmlFromNotes(char[] notes, int maxLength)
{
  if (maxLength <= 0)
  {
    return;
  }

  bool inTag        = false;
  bool lastWasSpace = true;
  int  writeIndex = 0;

  for (int readIndex = 0; readIndex < maxLength && notes[readIndex] != '\0'; readIndex++)
  {
    char currentChar = notes[readIndex];

    bool consumed = ConsumeHtmlTag(currentChar, inTag, lastWasSpace, notes, maxLength, writeIndex);
    if (consumed)
    {
      continue;
    }

    currentChar = NormalizeNoteWhitespace(currentChar);

    if (currentChar == ' ')
    {
      if (lastWasSpace)
      {
        continue;
      }

      lastWasSpace = true;
    }
    else
    {
      lastWasSpace = false;
    }

    if (writeIndex >= maxLength - 1)
    {
      break;
    }

    notes[writeIndex++] = currentChar;
  }

  notes[writeIndex] = '\0';
  TrimString(notes);

  ReplaceString(notes, maxLength, "&nbsp;", " ", false);
  ReplaceString(notes, maxLength, "&amp;", "&", false);
  ReplaceString(notes, maxLength, "&lt;", "<", false);
  ReplaceString(notes, maxLength, "&gt;", ">", false);
  ReplaceString(notes, maxLength, "&quot;", "\"", false);
  ReplaceString(notes, maxLength, "&#39;", "'", false);
  ReplaceString(notes, maxLength, "&apos;", "'", false);
}

void OutputMapTierInfoIfFound(int client, char[] mapName)
{
  int vanillaMapIndex = GetVanillaMapIndexByName(mapName);
  if (vanillaMapIndex != -1)
  {
    ReplyToCommand(client, "%s %s", CHAT_PREFIX, g_VanillaMaps[vanillaMapIndex].name);
    ReplyToCommand(client, "%s \x10VNL NUB: \x01%d", CHAT_PREFIX, g_VanillaMaps[vanillaMapIndex].tpTier);
    ReplyToCommand(client, "%s \x0BVNL PRO: \x01%d", CHAT_PREFIX, g_VanillaMaps[vanillaMapIndex].proTier);
     
    if (strlen(g_VanillaMaps[vanillaMapIndex].notes) > 0)
    {
      ReplyToCommand(client, "%s \x0CNotes: \x01%s", CHAT_PREFIX, g_VanillaMaps[vanillaMapIndex].notes);
    }
    return;
  }

  int uncompletedMapIndex = GetUncompletedMapIndexByName(mapName);
  if (uncompletedMapIndex != -1)
  {
    ReplyToCommand(client, "%s %s is not possible on vanilla.", CHAT_PREFIX, g_UncompletedMaps[uncompletedMapIndex].name);

    if (strlen(g_UncompletedMaps[uncompletedMapIndex].notes) > 0)
    {
      ReplyToCommand(client, "%s \x0CNotes: \x01%s", CHAT_PREFIX, g_UncompletedMaps[uncompletedMapIndex].notes);
    }
    return;
  }

  ReplyToCommand(client, "%s %s was not found.", CHAT_PREFIX, mapName);
}

void LoadVanillaMaps()
{
  char mapsUrl[128];
  Format(mapsUrl, sizeof(mapsUrl), "%s/maps", API_HOST);

  Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, mapsUrl);
  if (request == null)
  {
    ScheduleVanillaMapsRetry();
    return;
  }

  SteamWorks_SetHTTPCallbacks(request, OnVanillaMapsRequestComplete);

  bool sent = SteamWorks_SendHTTPRequest(request);
  if (!sent)
  {
    LogError("maps request could not be made.");
    delete request;
    ScheduleVanillaMapsRetry();
    return;
  }
}

public int OnVanillaMapsRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
  JSON_Array vanillaMaps = ReadMapResponse(hRequest, bFailure, bRequestSuccessful, eStatusCode, sizeof(g_VanillaMaps));
  delete hRequest;
  if (vanillaMaps == null)
  {
    ScheduleVanillaMapsRetry();
    return 0;
  }

  ClearVanillaMaps();

  int length = vanillaMaps.Length;

  for (int i = 0; i < length; i++)
  {
    JSON_Object map = vanillaMaps.GetObject(i);

    VanillaMap vanillaMap;
    vanillaMap.id = map.GetInt("id");
    map.GetString("name", vanillaMap.name, sizeof(vanillaMap.name));
    vanillaMap.kztTier = map.GetInt("kztTier");
    vanillaMap.proTier = map.GetInt("proTier");
    vanillaMap.tpTier  = map.GetInt("tpTier");
    map.GetString("notes", vanillaMap.notes, sizeof(vanillaMap.notes));
    SanitizeHtmlFromNotes(vanillaMap.notes, sizeof(vanillaMap.notes));

    g_VanillaMaps[i] = vanillaMap;
  }

  json_cleanup_and_delete(vanillaMaps);

  return 0;
}

void LoadUncompletedMaps()
{
  char mapsUrl[128];
  Format(mapsUrl, sizeof(mapsUrl), "%s/uncompleted", API_HOST);

  Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, mapsUrl);
  if (request == null)
  {
    ScheduleUncompletedMapsRetry();
    return;
  }

  SteamWorks_SetHTTPCallbacks(request, OnUncompletedMapsRequestComplete);

  bool sent = SteamWorks_SendHTTPRequest(request);
  if (!sent)
  {
    LogError("Uncompleted maps request could not be made.");
    delete request;
    ScheduleUncompletedMapsRetry();
    return;
  }
}

public int OnUncompletedMapsRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
  JSON_Array vanillaMaps = ReadMapResponse(hRequest, bFailure, bRequestSuccessful, eStatusCode, sizeof(g_UncompletedMaps));
  delete hRequest;
  if (vanillaMaps == null)
  {
    ScheduleUncompletedMapsRetry();
    return 0;
  }

  ClearUncompletedMaps();

  int length = vanillaMaps.Length;

  for (int i = 0; i < length; i++)
  {
    JSON_Object map = vanillaMaps.GetObject(i);

    UncompletedMap uncompletedMap;
    uncompletedMap.id = map.GetInt("id");
    map.GetString("map_name", uncompletedMap.name, sizeof(uncompletedMap.name));
    uncompletedMap.kztTier = map.GetInt("kztTier");
    map.GetString("notes", uncompletedMap.notes, sizeof(uncompletedMap.notes));
    SanitizeHtmlFromNotes(uncompletedMap.notes, sizeof(uncompletedMap.notes));

    g_UncompletedMaps[i] = uncompletedMap;
  }

  json_cleanup_and_delete(vanillaMaps);

  return 0;
}

bool ConsumeHtmlTag(char character, bool &inTag, bool &lastWasSpace, char[] notes, int maxLength, int &writeIndex)
{
  if (character == '<')
  {
    inTag = true;
    if (!lastWasSpace && writeIndex < maxLength - 1)
    {
      notes[writeIndex++] = ' ';
      lastWasSpace = true;
    }
    return true;
  }
  if (!inTag)
  {
    return false;
  }
  if (character == '>')
  {
    inTag = false;
  }
  return true;
}

char NormalizeNoteWhitespace(char character)
{
  if (character == '\r' || character == '\n' || character == '\t')
  {
    return ' ';
  }
  return character;
}

JSON_Array ReadMapResponse(Handle request, bool failure, bool successful, EHTTPStatusCode statusCode, int maxMaps)
{
  int status = view_as<int>(statusCode);
  if (failure || !successful || status < 200 || status >= 300)
  {
    LogError("Map API request failed. status=%d", status);
    return null;
  }

  int bodySize;
  if (!SteamWorks_GetHTTPResponseBodySize(request, bodySize))
  {
    LogError("Could not read map API response size.");
    return null;
  }
  if (bodySize <= 0 || bodySize >= 256000)
  {
    LogError("Map API response has an invalid size: %d", bodySize);
    return null;
  }

  int bufferSize = bodySize + 1;
  char[] body = new char[bufferSize];
  if (!SteamWorks_GetHTTPResponseBodyData(request, body, bodySize))
  {
    LogError("Could not read map API response body.");
    return null;
  }
  body[bodySize] = '\0';
  JSON_Object decoded = json_decode(body);
  bool valid = IsValidMapArray(decoded, maxMaps);
  if (!valid)
  {
    json_cleanup_and_delete(decoded);
    LogError("Map API response must be an array of at most %d map objects.", maxMaps);
    return null;
  }
  return view_as<JSON_Array>(decoded);
}

bool IsValidMapArray(JSON_Object decoded, int maxMaps)
{
  if (decoded == null)
  {
    return false;
  }
  if (!decoded.IsArray)
  {
    return false;
  }
  JSON_Array maps = view_as<JSON_Array>(decoded);
  int count = maps.Length;
  if (count > maxMaps)
  {
    return false;
  }
  for (int i = 0; i < count; i++)
  {
    JSONCellType type = maps.GetType(i);
    if (type != JSON_Type_Object)
    {
      return false;
    }
    JSON_Object map = maps.GetObject(i);
    if (map == null)
    {
      return false;
    }
    if (map.IsArray)
    {
      return false;
    }
  }
  return true;
}
