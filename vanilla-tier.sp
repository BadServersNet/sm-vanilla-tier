#include <json>
#include <sourcemod>
#include <SteamWorks>

#define API_HOST    "https://vnlkz.com/api"
#define CHAT_PREFIX "[\x0Evnlkz.com\x01]"

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

int  g_VanillaMapCount;
int  g_UncompletedMapCount;
bool g_VanillaMapsLoaded;
bool g_UncompletedMapsLoaded;

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
  if (!g_VanillaMapsLoaded || !g_UncompletedMapsLoaded)
  {
    ReplyToCommand(client, "%s Tier data is still loading. Try again in a moment.", CHAT_PREFIX);
    return;
  }

  int vanillaMapIndex = GetVanillaMapIndexByName(mapName);
  if (vanillaMapIndex != -1)
  {
    ReplyToCommand(client, "%s %s", CHAT_PREFIX, g_VanillaMaps[vanillaMapIndex].name);
    ReplyToCommand(client, "%s \x10VNL NUB: \x01%d", CHAT_PREFIX, g_VanillaMaps[vanillaMapIndex].tpTier);
    ReplyToCommand(client, "%s \x0BVNL PRO: \x01%d", CHAT_PREFIX, g_VanillaMaps[vanillaMapIndex].proTier);
    return;
  }

  int uncompletedMapIndex = GetUncompletedMapIndexByName(mapName);
  if (uncompletedMapIndex != -1)
  {
    ReplyToCommand(client, "%s %s is not possible on vanilla.", CHAT_PREFIX, g_UncompletedMaps[uncompletedMapIndex].name);
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
    return;
  }

  SteamWorks_SetHTTPCallbacks(request, OnVanillaMapsRequestComplete);

  bool sent = SteamWorks_SendHTTPRequest(request);
  if (!sent)
  {
    LogError("maps request could not be made.");
    delete request;
    return;
  }
}

public int OnVanillaMapsRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
  int status = view_as<int>(eStatusCode);
  if (bFailure || !bRequestSuccessful || status >= 300)
  {
    LogError("maps request failed, status: %d", status);
    delete hRequest;
    return 0;
  }

  int bodySize;
  if (!SteamWorks_GetHTTPResponseBodySize(hRequest, bodySize) || bodySize <= 0)
  {
    LogError("maps response had no body.");
    delete hRequest;
    return 0;
  }

  char[] body = new char[bodySize + 1];
  if (!SteamWorks_GetHTTPResponseBodyData(hRequest, body, bodySize + 1))
  {
    LogError("maps response body could not be read.");
    delete hRequest;
    return 0;
  }
  body[bodySize] = '\0';

  JSON_Array vanillaMaps = view_as<JSON_Array>(json_decode(body));
  if (vanillaMaps == null)
  {
    char jsonError[256];
    json_get_last_error(jsonError, sizeof(jsonError));
    LogError("maps response could not be decoded as JSON: %s", jsonError);
    delete hRequest;
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

  json_cleanup_and_delete(vanillaMaps);
  delete hRequest;

  return 0;
}

void LoadUncompletedMaps()
{
  char mapsUrl[128];
  Format(mapsUrl, sizeof(mapsUrl), "%s/uncompleted", API_HOST);

  Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, mapsUrl);
  if (request == null)
  {
    return;
  }

  SteamWorks_SetHTTPCallbacks(request, OnUncompletedMapsRequestComplete);

  bool sent = SteamWorks_SendHTTPRequest(request);
  if (!sent)
  {
    LogError("Uncompleted maps request could not be made.");
    delete request;
    return;
  }
}

public int OnUncompletedMapsRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
  int status = view_as<int>(eStatusCode);
  if (bFailure || !bRequestSuccessful || status >= 300)
  {
    LogError("Uncompleted maps request failed, status: %d", status);
    delete hRequest;
    return 0;
  }

  int bodySize;
  if (!SteamWorks_GetHTTPResponseBodySize(hRequest, bodySize) || bodySize <= 0)
  {
    LogError("Uncompleted maps response had no body.");
    delete hRequest;
    return 0;
  }

  char[] body = new char[bodySize + 1];
  if (!SteamWorks_GetHTTPResponseBodyData(hRequest, body, bodySize + 1))
  {
    LogError("Uncompleted maps response body could not be read.");
    delete hRequest;
    return 0;
  }
  body[bodySize] = '\0';

  JSON_Array vanillaMaps = view_as<JSON_Array>(json_decode(body));
  if (vanillaMaps == null)
  {
    char jsonError[256];
    json_get_last_error(jsonError, sizeof(jsonError));
    LogError("Uncompleted maps response could not be decoded as JSON: %s", jsonError);
    delete hRequest;
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

  json_cleanup_and_delete(vanillaMaps);
  delete hRequest;

  return 0;
}
