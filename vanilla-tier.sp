#include <json>
#include <sourcemod>
#include <SteamWorks>

#define API_HOST    "https://vnlkz.com/api"
#define CHAT_PREFIX "[\x0Evnlkz.com\x01]"
#define MAX_HTTP_BODY_SIZE 524288
#define LOAD_RETRY_DELAY 10.0

#pragma newdecls required

public Plugin myinfo =
{
  name        = "Vanilla Tier Plugin",
  author      = "BuSheeZy",
  description = "Show tier information for vanilla maps. (vnlkz.com)",
  version     = "1.0.0",
  url         = "https://BadServers.net"
};

enum struct VanillaMap
{
  int  id;
  char name[64];
  int  kztTier;
  int  proTier;
  int  tpTier;
}

enum struct UncompletedMap
{
  int  id;
  char name[64];
  int  kztTier;
}

VanillaMap     g_VanillaMaps[2048];
UncompletedMap g_UncompletedMaps[2048];
char           g_ResponseBody[MAX_HTTP_BODY_SIZE];

int  g_VanillaMapCount;
int  g_UncompletedMapCount;
bool g_VanillaMapsLoaded;
bool g_UncompletedMapsLoaded;
bool g_VanillaMapsLoading;
bool g_UncompletedMapsLoading;

Handle g_VanillaMapsRetryTimer;
Handle g_UncompletedMapsRetryTimer;

public void OnPluginStart()
{
  RegConsoleCmd("sm_vnltier", OnVanillaTierCmd, "Show the map's vanilla tier.");

  LoadVanillaMaps();
  LoadUncompletedMaps();
}

public void OnMapStart()
{
  LoadVanillaMaps();
  LoadUncompletedMaps();
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
  for (int i = 0; i < g_VanillaMapCount; i++)
  {
    if (StrContains(g_VanillaMaps[i].name, mapName, false) == 0)
    {
      return i;
    }
  }

  for (int i = 0; i < g_VanillaMapCount; i++)
  {
    if (StrContains(g_VanillaMaps[i].name, mapName, false) != -1)
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

  g_VanillaMapCount = 0;
}

void ClearUncompletedMaps()
{
  UncompletedMap empty;

  for (int i = 0; i < sizeof(g_UncompletedMaps); i++)
  {
    g_UncompletedMaps[i] = empty;
  }

  g_UncompletedMapCount = 0;
}

int GetUncompletedMapIndexByName(char[] mapName)
{
  for (int i = 0; i < g_UncompletedMapCount; i++)
  {
    if (StrContains(g_UncompletedMaps[i].name, mapName, false) == 0)
    {
      return i;
    }
  }

  for (int i = 0; i < g_UncompletedMapCount; i++)
  {
    if (StrContains(g_UncompletedMaps[i].name, mapName, false) != -1)
    {
      return i;
    }
  }

  return -1;
}

void OutputMapTierInfoIfFound(int client, char[] mapName)
{
  if (!g_VanillaMapsLoaded && !g_UncompletedMapsLoaded)
  {
    ReplyToCommand(client, "%s Tier data is still loading. Try again in a moment.", CHAT_PREFIX);
    return;
  }

  if (g_VanillaMapsLoaded)
  {
    int vanillaMapIndex = GetVanillaMapIndexByName(mapName);
    if (vanillaMapIndex != -1)
    {
      ReplyToCommand(client, "%s %s", CHAT_PREFIX, g_VanillaMaps[vanillaMapIndex].name);
      ReplyToCommand(client, "%s \x10VNL NUB: \x01%d", CHAT_PREFIX, g_VanillaMaps[vanillaMapIndex].tpTier);
      ReplyToCommand(client, "%s \x0BVNL PRO: \x01%d", CHAT_PREFIX, g_VanillaMaps[vanillaMapIndex].proTier);
      return;
    }
  }

  if (g_UncompletedMapsLoaded)
  {
    int uncompletedMapIndex = GetUncompletedMapIndexByName(mapName);
    if (uncompletedMapIndex != -1)
    {
      ReplyToCommand(client, "%s %s is not possible on vanilla.", CHAT_PREFIX, g_UncompletedMaps[uncompletedMapIndex].name);
      return;
    }
  }

  if (!g_VanillaMapsLoaded || !g_UncompletedMapsLoaded)
  {
    ReplyToCommand(client, "%s %s was not found in the loaded data. Some tier data is still loading.", CHAT_PREFIX, mapName);
    return;
  }

  ReplyToCommand(client, "%s %s was not found.", CHAT_PREFIX, mapName);
}

void ScheduleVanillaMapsRetry()
{
  if (!g_VanillaMapsLoaded && g_VanillaMapsRetryTimer == null)
  {
    g_VanillaMapsRetryTimer = CreateTimer(LOAD_RETRY_DELAY, Timer_RetryLoadVanillaMaps);
  }
}

void ScheduleUncompletedMapsRetry()
{
  if (!g_UncompletedMapsLoaded && g_UncompletedMapsRetryTimer == null)
  {
    g_UncompletedMapsRetryTimer = CreateTimer(LOAD_RETRY_DELAY, Timer_RetryLoadUncompletedMaps);
  }
}

public Action Timer_RetryLoadVanillaMaps(Handle timer)
{
  g_VanillaMapsRetryTimer = null;

  if (!g_VanillaMapsLoaded)
  {
    LoadVanillaMaps();
  }

  return Plugin_Stop;
}

public Action Timer_RetryLoadUncompletedMaps(Handle timer)
{
  g_UncompletedMapsRetryTimer = null;

  if (!g_UncompletedMapsLoaded)
  {
    LoadUncompletedMaps();
  }

  return Plugin_Stop;
}

void LoadVanillaMaps()
{
  if (g_VanillaMapsLoading)
  {
    return;
  }

  if (!SteamWorks_IsLoaded())
  {
    LogError("SteamWorks is not loaded yet; retrying maps request soon.");
    ScheduleVanillaMapsRetry();
    return;
  }

  g_VanillaMapsLoading = true;

  char mapsUrl[128];
  Format(mapsUrl, sizeof(mapsUrl), "%s/maps", API_HOST);

  Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, mapsUrl);
  if (request == null)
  {
    g_VanillaMapsLoading = false;
    LogError("maps request could not be created.");
    ScheduleVanillaMapsRetry();
    return;
  }

  SteamWorks_SetHTTPCallbacks(request, OnVanillaMapsRequestComplete);

  bool sent = SteamWorks_SendHTTPRequest(request);
  if (!sent)
  {
    LogError("maps request could not be made.");
    g_VanillaMapsLoading = false;
    delete request;
    ScheduleVanillaMapsRetry();
    return;
  }
}

public int OnVanillaMapsRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
  int status = view_as<int>(eStatusCode);
  if (bFailure || !bRequestSuccessful || status >= 300)
  {
    LogError("maps request failed, status: %d", status);
    g_VanillaMapsLoading = false;
    delete hRequest;
    ScheduleVanillaMapsRetry();
    return 0;
  }

  int bodySize;
  if (!SteamWorks_GetHTTPResponseBodySize(hRequest, bodySize) || bodySize <= 0)
  {
    LogError("maps response had no body.");
    g_VanillaMapsLoading = false;
    delete hRequest;
    ScheduleVanillaMapsRetry();
    return 0;
  }

  if (bodySize >= sizeof(g_ResponseBody))
  {
    LogError("maps response is %d bytes, but only %d bytes can be read.", bodySize, sizeof(g_ResponseBody) - 1);
    g_VanillaMapsLoading = false;
    delete hRequest;
    ScheduleVanillaMapsRetry();
    return 0;
  }

  if (!SteamWorks_GetHTTPResponseBodyData(hRequest, g_ResponseBody, sizeof(g_ResponseBody)))
  {
    LogError("maps response body could not be read.");
    g_VanillaMapsLoading = false;
    delete hRequest;
    ScheduleVanillaMapsRetry();
    return 0;
  }
  g_ResponseBody[bodySize] = '\0';

  JSON_Array vanillaMaps = view_as<JSON_Array>(json_decode(g_ResponseBody));
  if (vanillaMaps == null)
  {
    char jsonError[256];
    json_get_last_error(jsonError, sizeof(jsonError));
    LogError("maps response could not be decoded as JSON: %s", jsonError);
    g_VanillaMapsLoading = false;
    delete hRequest;
    ScheduleVanillaMapsRetry();
    return 0;
  }

  int length = vanillaMaps.Length;
  if (length > sizeof(g_VanillaMaps))
  {
    LogError("maps response has %d records, but only %d can be stored.", length, sizeof(g_VanillaMaps));
    length = sizeof(g_VanillaMaps);
  }

  ClearVanillaMaps();

  for (int i = 0; i < length; i++)
  {
    JSON_Object map = vanillaMaps.GetObject(i);

    VanillaMap vanillaMap;
    vanillaMap.id = map.GetInt("id");
    map.GetString("name", vanillaMap.name, sizeof(vanillaMap.name));
    vanillaMap.kztTier = map.GetInt("kztTier");
    vanillaMap.proTier = map.GetInt("proTier");
    vanillaMap.tpTier  = map.GetInt("tpTier");

    g_VanillaMaps[i] = vanillaMap;
  }

  g_VanillaMapCount = length;
  g_VanillaMapsLoaded = true;
  g_VanillaMapsLoading = false;

  json_cleanup_and_delete(vanillaMaps);
  delete hRequest;

  return 0;
}

void LoadUncompletedMaps()
{
  if (g_UncompletedMapsLoading)
  {
    return;
  }

  if (!SteamWorks_IsLoaded())
  {
    LogError("SteamWorks is not loaded yet; retrying Uncompleted maps request soon.");
    ScheduleUncompletedMapsRetry();
    return;
  }

  g_UncompletedMapsLoading = true;

  char mapsUrl[128];
  Format(mapsUrl, sizeof(mapsUrl), "%s/uncompleted", API_HOST);

  Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, mapsUrl);
  if (request == null)
  {
    g_UncompletedMapsLoading = false;
    LogError("Uncompleted maps request could not be created.");
    ScheduleUncompletedMapsRetry();
    return;
  }

  SteamWorks_SetHTTPCallbacks(request, OnUncompletedMapsRequestComplete);

  bool sent = SteamWorks_SendHTTPRequest(request);
  if (!sent)
  {
    LogError("Uncompleted maps request could not be made.");
    g_UncompletedMapsLoading = false;
    delete request;
    ScheduleUncompletedMapsRetry();
    return;
  }
}

public int OnUncompletedMapsRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
  int status = view_as<int>(eStatusCode);
  if (bFailure || !bRequestSuccessful || status >= 300)
  {
    LogError("Uncompleted maps request failed, status: %d", status);
    g_UncompletedMapsLoading = false;
    delete hRequest;
    ScheduleUncompletedMapsRetry();
    return 0;
  }

  int bodySize;
  if (!SteamWorks_GetHTTPResponseBodySize(hRequest, bodySize) || bodySize <= 0)
  {
    LogError("Uncompleted maps response had no body.");
    g_UncompletedMapsLoading = false;
    delete hRequest;
    ScheduleUncompletedMapsRetry();
    return 0;
  }

  if (bodySize >= sizeof(g_ResponseBody))
  {
    LogError("Uncompleted maps response is %d bytes, but only %d bytes can be read.", bodySize, sizeof(g_ResponseBody) - 1);
    g_UncompletedMapsLoading = false;
    delete hRequest;
    ScheduleUncompletedMapsRetry();
    return 0;
  }

  if (!SteamWorks_GetHTTPResponseBodyData(hRequest, g_ResponseBody, sizeof(g_ResponseBody)))
  {
    LogError("Uncompleted maps response body could not be read.");
    g_UncompletedMapsLoading = false;
    delete hRequest;
    ScheduleUncompletedMapsRetry();
    return 0;
  }
  g_ResponseBody[bodySize] = '\0';

  JSON_Array vanillaMaps = view_as<JSON_Array>(json_decode(g_ResponseBody));
  if (vanillaMaps == null)
  {
    char jsonError[256];
    json_get_last_error(jsonError, sizeof(jsonError));
    LogError("Uncompleted maps response could not be decoded as JSON: %s", jsonError);
    g_UncompletedMapsLoading = false;
    delete hRequest;
    ScheduleUncompletedMapsRetry();
    return 0;
  }

  int length = vanillaMaps.Length;
  if (length > sizeof(g_UncompletedMaps))
  {
    LogError("Uncompleted maps response has %d records, but only %d can be stored.", length, sizeof(g_UncompletedMaps));
    length = sizeof(g_UncompletedMaps);
  }

  ClearUncompletedMaps();

  for (int i = 0; i < length; i++)
  {
    JSON_Object map = vanillaMaps.GetObject(i);

    UncompletedMap uncompletedMap;
    uncompletedMap.id = map.GetInt("map_id");
    map.GetString("map_name", uncompletedMap.name, sizeof(uncompletedMap.name));
    uncompletedMap.kztTier = map.GetInt("kztTier");

    g_UncompletedMaps[i] = uncompletedMap;
  }

  g_UncompletedMapCount = length;
  g_UncompletedMapsLoaded = true;
  g_UncompletedMapsLoading = false;

  json_cleanup_and_delete(vanillaMaps);
  delete hRequest;

  return 0;
}
