
#include <cstrike>
#include <sdktools_functions>

public Plugin:myinfo =
{
	name = "Hold the Site",
	author = "Kristopher Ives",
	description = "Take turns holding the bomb site",
	version = "0.1",
	url = "https://github.com/krisives/csgo-apoc"
};

// Current map to avoid reloading data unless map actually changes
new String:currentMap[32];

// Players unwilling to try and handle the site currently
new bool:bitches[32];

// Current player that is playing rambo
new ramboClientID = -1;

// When the player started holding the site
new ramboHoldStart = -1;

// How many kills rambo has had while holding the site
new ramboKills = 0;
new ramboHeadshotKills = 0;

new bool:ramboBombPlanted = false;

// How many bombsites are on the map
new siteCount = 0;

// Which site is currently being played
new currentSite = -1;

// Position of each bombsite where rambo will spawn (up to 10 sites)
new Float:sitePos[10][3];

// Each site has a name (up to 32 chars)
new String:siteName[10][32];

// Players that get too close will be teleported away
new Float:siteSize[10];

// Outside each bombsite are (up to 32 spawn points)
new spawnCount[10];
new Float:spawnPos[10][32][3];

new Float:lastValidPos[64][3];

new nextSpawn = 0;

public OnPluginStart()
{
	PrintToServer("[HTS] Hold the Site Plugin Loaded");
	
	RegConsoleCmd("hts_help", HTS_HelpCommand);
	RegConsoleCmd("hts_site", HTS_SiteCommand);
	RegConsoleCmd("hts_addspawn", HTS_AddSpawnCommand);
	RegConsoleCmd("hts_clear", HTS_ClearCommand);
	RegConsoleCmd("hts_save", HTS_SaveCommand);
	RegConsoleCmd("hts_load", HTS_LoadCommand);
	RegConsoleCmd("hts_next", HTS_NextCommand);
	
	HookEvent("round_end", HTS_FinishRound, EventHookMode_Post);
	HookEvent("round_start", HTS_BeforeStartRound, EventHookMode_Pre);
	HookEvent("round_start", HTS_StartRound, EventHookMode_Post);
	HookEvent("player_death", HTS_TrackKill, EventHookMode_Post);
	HookEvent("player_spawn", HTS_AfterPlayerSpawn, EventHookMode_Post);
	HookEvent("bomb_defused", HTS_BombDefused, EventHookMode_Post);
	
	AddCommandListener(HTS_PreventTeamChange, "jointeam"); 
	
	ServerCommand("mp_ignore_round_win_conditions 1");
	ServerCommand("mp_freezetime 0");
	ServerCommand("mp_autoteambalance 0");
	ServerCommand("mp_do_warmup_period 0")
	
	CreateTimer(3.0, HTS_ResetBombTimer, INVALID_HANDLE, TIMER_REPEAT);
	CreateTimer(1.0, HTS_RespawnTimer, INVALID_HANDLE, TIMER_REPEAT);
	CreateTimer(1.0, HTS_KeepPlayersAway, INVALID_HANDLE, TIMER_REPEAT);
}

public OnClientPutInServer(client) {
	HTS_WelcomeClient(client);
}

public Action:OnClientSayCommand(client, const String:command[], const String:text[]) {
	if (StrContains(text, "!bug") == 0) {
		HTS_ReportBug(client, text);
		return Plugin_Handled;
	}
	
	if (StrContains(text, "!unqueue") == 0) {
		HTS_Unqueue(client);
		return Plugin_Handled;
	}
	
	if (StrContains(text, "!queue") == 0) {
		HTS_Queue(client);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public OnMapStart() {
	new String:mapName[32];
	
	ServerCommand("mp_ignore_round_win_conditions 1");
	ServerCommand("mp_freezetime 0");
	ServerCommand("mp_autoteambalance 0");
	ServerCommand("mp_do_warmup_period 0");
	
	GetCurrentMap(mapName, sizeof(mapName));
	
	if (strcmp(mapName, currentMap) != 0) {
		strcopy(currentMap, sizeof(currentMap), mapName);
		HTS_Load();
	}
	
	HTS_StartMap();
}

public OnEntityCreated(entity, const String:classname[]){
	if(StrEqual(classname, "planted_c4")) {
		HTS_TrackBombPlant(entity);
	}
}

// ----------------------------------------------------------------------------

public HTS_Debug(String:msg[]) {
	PrintToServer("[HTS] %s", msg);
}

public HTS_ReportBug(client, const String:text[]) {
	PrintToChat(client, "For now please submit bugs to this URL:");
	PrintToChat(client, "https://github.com/sourcemod-plugins/holdthesite/issues");
}

public Action:HTS_HelpCommand(client, argCount) {
	PrintToConsole(client, "Hold the Site");
	PrintToConsole(client, "");
	PrintToConsole(client, "hts_help      What you are reading right now");
	PrintToConsole(client, "hts_site      Add or change position of a bomb site");
	PrintToConsole(client, "hts_addspawn  Adds a spawn to a bomb site");
	PrintToConsole(client, "hts_clear     Remove a site or all sites from the map");
	PrintToConsole(client, "hts_save      Save the configuration for this map");
	PrintToConsole(client, "hts_load      Reload the configuration for this map");
	PrintToConsole(client, "hts_next      Start a new round with a new player");
}

public HTS_RememberValidPos(client, const Float:pos[3]) {
	lastValidPos[client][0] = pos[0];
	lastValidPos[client][1] = pos[1];
	lastValidPos[client][2] = pos[2];
}

public Action:HTS_ResetBombTimer(Handle:timer) {
	new lastEntity = -1;
	new entity = -1;
	
	while ((entity = FindEntityByClassname(lastEntity, "planted_c4")) != -1) {
		lastEntity = entity;
		
		SetEntPropFloat(entity, Prop_Send, "m_flC4Blow", GetTime() + 60.0);
	}
}

public Action:HTS_KeepPlayersAway(Handle:timer) {
	
}

public Action:HTS_RespawnTimer(Handle:timer) {
	new max = GetMaxClients();
	
	if (ramboClientID > 0) {
		if (!IsClientConnected(ramboClientID) || !IsClientInGame(ramboClientID)) {
			ramboClientID = -1;
			CS_TerminateRound(1.5, CSRoundEnd_CTWin);
		}
	}
	
	if (currentSite == -1) {
		return;
	}
	
	if (spawnCount[currentSite] <= 0) {
		return;
	}
	
	for (new i=1; i < max; i++) {
		if (!IsClientConnected(i)) {
			continue;
		}
		
		if (!IsClientInGame(i)) {
			continue;
		}
		
		if (i == ramboClientID) {
			continue;
		}
		
		if (IsPlayerAlive(i)) {
			if (GetClientTeam(i) == CS_TEAM_T) {
				ForcePlayerSuicide(i);
				CS_SwitchTeam(i, CS_TEAM_CT);
			}
			
			continue;
		}
		
		nextSpawn = (nextSpawn + 1) % spawnCount[currentSite];
		TeleportEntity(i, spawnPos[currentSite][nextSpawn], NULL_VECTOR, NULL_VECTOR);
		CS_RespawnPlayer(i);
	}
}

public HTS_WelcomeClient(client) {
	if (client < 0) {
		HTS_Debug("Tried to welcome an invalid client index");
		return;
	}
	
	if (!IsClientInGame(client)) {
		HTS_Debug("Tried to welcome a client not in game");
		return;
	}
	
	bitches[client] = false;
	FakeClientCommand(client, "joingame");
	CS_SwitchTeam(client, CS_TEAM_CT);
	
	PrintToChat(client, "\x05Thanks for trying Hold the Site!");
	PrintToChat(client, "\x05This plugin is still in beta. Please type !bug to report a bug");
	
	PrintToChat(client, "\x06When it's your turn you can try and hold the bomb site alone");
	PrintToChat(client, "\x06Type !help for a list of chat commands");
	
	if (ramboClientID <= 0) {
		CS_TerminateRound(1.5, CSRoundEnd_CTWin);
	}
}

public Action:HTS_PreventTeamChange(client, const String:command[], args) {
	new team;
	
	if (client == 0) {
		return Plugin_Continue;
	}
	
	//if (!IsActive(client, true))) {
	//	return Plugin_Continue;
	//}
	
	team = GetClientTeam(client);
	
	if (team <= 0) {
		return Plugin_Continue;
	}
	
	if (ramboClientID == client && team != CS_TEAM_T) {
		return Plugin_Stop;
	}
	
	if (ramboClientID != client && team != CS_TEAM_CT) {
		ForcePlayerSuicide(client);
		CS_SwitchTeam(client, CS_TEAM_CT);
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

public HTS_TrackBombPlant(entity) {
	ramboBombPlanted = true;
	
	PrintToChatAll("\x02Bomb has been planted");
	PrintToChatAll("\x05One player may enter the site at a time");
}


public HTS_BeforePlayerSpawn(Handle:event, const String:killed[], bool:dontBroadcast) {
	new client = GetEventInt(event, "userid");
	
	if (currentSite < 0) {
		return;
	}
	
	if (client <= 0 || !IsClientConnected(client)) {
		return;
	}
	
	if (client > 0) {
		if (client != ramboClientID && GetClientTeam(client) != CS_TEAM_CT) {
			CS_SwitchTeam(client, CS_TEAM_CT);
		}
	}
}

public HTS_AfterPlayerSpawn(Handle:event, const String:killed[], bool:dontBroadcast) {
	new client = GetEventInt(event, "userid");
	
	if (currentSite < 0) {
		return;
	}
	
	if (client <= 0 || !IsClientConnected(client)) {
		return;
	}
	
	nextSpawn = (nextSpawn + 1) % spawnCount[currentSite];
	TeleportEntity(client, spawnPos[currentSite][nextSpawn], NULL_VECTOR, NULL_VECTOR);
}


public HTS_TrackKill(Handle:event, const String:killed[], bool:dontBroadcast) {
	new victimUserID = GetEventInt(event, "userid");
	new killerUserID = GetEventInt(event, "attacker");
	new bool:isHeadshot = GetEventBool(event, "headshot");
	new killerID = GetClientOfUserId(killerUserID);
	new victimID = GetClientOfUserId(victimUserID);
	
	if (victimID <= 0 || killerID <= 0) {
		return;
	}
	
	if (victimID == ramboClientID) {
		CS_TerminateRound(1.5, CSRoundEnd_CTWin);
		return;
	}
	
	if (killerID != ramboClientID) {
		return;
	}
	
	ramboKills++;
	
	if (isHeadshot) {
		ramboHeadshotKills++;
	}
}

public HTS_BombDefused(Handle:event, const String:killed[], bool:dontBroadcast) {
	CS_TerminateRound(1.5, CSRoundEnd_BombDefused);
}

public HTS_Queue(client) {
	if (bitches[client]) {
		return;
	}
	
	PrintToChat(client, "You have been placed back into the queue");
}

public HTS_Unqueue(client) {
	if (!bitches[client]) {
		return;
	}
	
	PrintToChat(client, "You have exited the queue and will not be selected to hold the site.");
	PrintToChat(client, "Use !queue to re-enter the queue.");
}

public bool:HTS_IsReady() {
	if (GetClientCount() <  2) {
		PrintToChatAll("Waiting for at least 2 players to join");
		return false;
	}
	
	if (siteCount <= 0) {
		PrintToChatAll("Cannot start because there are no bombsites on this map");
		PrintToChatAll("Use hts_site and hts_addspawn to configure this map");
		return false;
	}
	
	return true;
}

public HTS_SelectRandomPlayer() {
	new count = GetClientCount();
	new selected = RoundToNearest(1 + GetURandomFloat() * count);
	new max = GetMaxClients();
	
	if (count <= 0 || max <= 0) {
		return -1;
	}
	
	while (selected >= 0) {
		for (new i=1; i < max; i++) {
			if (!IsClientInGame(i)) {
				continue;
			}
			
			if (IsFakeClient(i)) {
				continue;
			}
			
			if (bitches[i]) {
				continue;
			}
			
			selected--;
			
			if (selected <= 0) {
				return i;
			}
		}
	}
	
	return -1;
}

public HTS_SelectRandomSite() {
	if (siteCount <= 0) {
		return -1;
	}
	
	return RoundToNearest(GetURandomFloat() * siteCount) % siteCount;
}


// Empties all the lists and arrays
public HTS_Cleanup() {
	siteCount = 0;
	currentSite = -1;
	ramboClientID = -1;
	
	for (new i=0; i < 10; i++) {
		sitePos[i][0] = 0.0;
		sitePos[i][1] = 0.0;
		sitePos[i][2] = 0.0;
		siteSize[i] = 0.0;
		spawnCount[i] = 0;
	}
}


// Adds a bomb site
public HTS_AddSite(const String:name[], Float:x, Float:y, Float:z, Float:size) {
	new site = -1;
	
	if (strlen(name) <= 0) {
		HTS_Debug("Missing site name");
		return -1;
	}
	
	if (size <= 0) {
		HTS_Debug("Size ommitted");
		return -1;
	}
	
	site = HTS_FindSite(name);
	
	if (site == -1) {
		site = siteCount;
		siteCount++;
	}
	
	sitePos[site][0] = x;
	sitePos[site][1] = y;
	sitePos[site][2] = z;
	siteSize[site] = size;
	strcopy(siteName[site], 32, name);
	spawnCount[site] = 0;
	
	return site;
}

public Action:HTS_SiteCommand(client, argCount) {
	new String:name[32];
	new Float:pos[3];
	new String:sizeText[32];
	new Float:size;
	new site = -1;
	
	if (argCount <= 0) {
		HTS_Debug("Missing bomb site name");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, name, sizeof(name));
	GetCmdArg(2, sizeText, sizeof(sizeText));
	size = StringToFloat(sizeText);
	GetClientAbsOrigin(client, pos);
	
	site = HTS_AddSite(name, pos[0], pos[1], pos[2], size);
	
	if (site >= 0) {
		PrintToChat(client, "Set bombsite position %s", name);
	}
	
	return Plugin_Handled;
}


public HTS_AddSpawn(site, const Float:pos[3]) {
	new spawn = -1;
	
	if (site < 0) {
		PrintToChatAll("Tried to add spawn to unknown bombsite");
		return -1;
	}
	
	if (HTS_GetDistanceFromSite(site, pos) < siteSize[site]) {
		PrintToChatAll("Spawn is too close to bomb site");
		return -1;
	}
	
	spawn = spawnCount[site];
	spawnCount[site] = spawnCount[site] + 1;
	
	spawnPos[site][spawn][0] = pos[0];
	spawnPos[site][spawn][1] = pos[1];
	spawnPos[site][spawn][2] = pos[2];
	
	return spawn;
}

public Float:HTS_GetDistanceFromSite(site, const Float:pos[3]) {
	new Float:dx = pos[0] - sitePos[site][0];
	new Float:dy = pos[1] - sitePos[site][1];
	new Float:dz = pos[2] - sitePos[site][2];
	
	return SquareRoot(dx*dx + dy*dy + dz*dz);
}

public HTS_FindSite(const String:name[]) {
	for (new i=0; i < siteCount; i++) {
		if (StrEqual(name, siteName[i])) {
			return i;
		}
	}
	
	return -1;
}


public Action:HTS_AddSpawnCommand(client, argCount) {
	new String:name[32];
	new site = -1;
	new spawn = -1;
	new Float:pos[3];
	
	GetCmdArg(1, name, sizeof(name));
	GetClientAbsOrigin(client, pos);
	
	site = HTS_FindSite(name);
	
	if (site == -1) {
		HTS_Debug("Cannot add spawn to unknown site");
		return;
	}
	
	spawn = HTS_AddSpawn(site, pos);
	
	if (spawn >= 0) {
		PrintToChat(client, "Added spawn to bombsite %s", name);
	}
}


public HTS_ClearSpawns(site) {
	if (site < 0) {
		HTS_Debug("Cannot clear spawns from invalid bomb site");
		return;
	}
	
	spawnCount[site] = 0;
}

public HTS_ClearAllSpawns() {
	for (new i=0; i < siteCount; i++) {
		spawnCount[i] = 0;
	}
}

public Action:HTS_ClearCommand(client, argCount) {
	new String:name[32];
	new site = -1;
	
	GetCmdArg(1, name, sizeof(name));
	
	if (strcmp(name, "*") == 0) {
		HTS_ClearAllSpawns();
		return Plugin_Handled;
	}
	
	site = HTS_FindSite(name);
	
	if (site == -1) {
		HTS_Debug("Cannot clear spawns for unknown bomb site");
		return Plugin_Handled;
	}
	
	HTS_ClearSpawns(site);
	return Plugin_Handled;
}


public HTS_StartMap() {
	
}

// Places the player holding the site on T and the rest on CT
public HTS_ChangeTeams() {
	new max = GetMaxClients();
	
	if (!HTS_IsReady()) {
		return;
	}
	
	if (ramboClientID >= 0) {
		CS_SwitchTeam(ramboClientID, CS_TEAM_T);
	}
	
	for (new i=1; i < max; i++) {
		if (!IsClientInGame(i)) {
			continue;
		}
		
		if (i == ramboClientID) {
			continue;
		}
		
		CS_SwitchTeam(i, CS_TEAM_CT);
	}
}

public HTS_TeleportPlayers() {
	//new max = GetMaxClients();
	
	if (currentSite < 0) {
		PrintToChatAll("Cannot find bomb site to teleport players to")
		return;
	}
	
	if (ramboClientID >= 0) {
		TeleportEntity(ramboClientID, sitePos[currentSite], NULL_VECTOR, NULL_VECTOR);
		GivePlayerItem(ramboClientID, "weapon_c4");
	}
	
	/*
	for (new i=1; i < max; i++) {
		if (!IsClientInGame(i)) {
			continue;
		}
		
		if (i == ramboClientID) {
			continue;
		}
		
		nextSpawn = (nextSpawn + 1) % spawnCount[currentSite];
		TeleportEntity(i, spawnPos[currentSite][nextSpawn], NULL_VECTOR, NULL_VECTOR);
		//HTS_RememberValidPos(i, spawnPos[currentSite][nextSpawn]);
	}
	
	*/
}

public HTS_BeforeStartRound(Handle:event, const String:name[], bool:dontBroadcast) {
	ramboClientID = HTS_SelectRandomPlayer();
	currentSite = HTS_SelectRandomSite();
	
	HTS_ChangeTeams();
}

public HTS_StartRound(Handle:event, const String:name[], bool:dontBroadcast) {
	new String:ramboName[32];
	
	if (!HTS_IsReady()) {
		return;
	}
	
	if (ramboClientID < 0) {
		ramboClientID = HTS_SelectRandomPlayer();
	}
	
	if (ramboClientID < 0) {
		PrintToChatAll("Cannot select a player to hold the site");
		return;
	}
	
	if (currentSite == -1) {
		currentSite = HTS_SelectRandomSite();
	}
	
	if (currentSite < 0) {
		PrintToChatAll("Cannot find a bomb site");
		return;
	}
	
	ramboBombPlanted = false;
	ramboHoldStart = GetTime();
	ramboKills = 0;
	ramboHeadshotKills = 0;
	
	HTS_TeleportPlayers();
	
	GetClientName(ramboClientID, ramboName, sizeof(ramboName));
	PrintToChatAll("Hold the site \x02(%s) \x06%s\x01!", siteName[currentSite], ramboName);
	
	HTS_StartPlantCountdown();
}

public HTS_StartPlantCountdown() {
	PrintToChatAll("\x02Plant the bomb within the next 10 seconds");
}

public HTS_FinishRound(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!HTS_IsReady()) {
		return;
	}
	
	HTS_PrintStats();
	HTS_ChangeTeams();
}

public HTS_PrintStats() {
	new String:name[32];
	new now;
	new seconds;
	new Float:minutes;
	
	if (ramboClientID < 0) {
		return;
	}
	
	GetClientName(ramboClientID, name, sizeof(name));
	now = GetTime();
	seconds = now - ramboHoldStart;
	minutes = seconds / 60.0;
	
	PrintToChatAll("%s held the site for %02.2f minutes", name, minutes);
	PrintToChatAll("Total Kills: %d (%02.2f%% headshots)", ramboKills, ramboHeadshotKills);
}



public Action:HTS_NextCommand(client, argCount) {
	HTS_Next();
	return Plugin_Handled;
}

public HTS_Next() {
	CS_TerminateRound(1.5, CSRoundEnd_CTWin);
}


public Action:HTS_LoadCommand(client, argCount) {
	HTS_Load();
	return Plugin_Handled;
}

public HTS_Load() {
	new String:path[256];
	new Handle:fp;
	new String:line[512];
	new String:args[8][32];
	new argCount;
	
	Format(path, sizeof(path), "maps/%s.hts.cfg", currentMap);
	
	if (!FileExists(path)) {
		return;
	}
	
	fp = OpenFile(path, "r");
	
	if (fp == INVALID_HANDLE) {
		HTS_Debug("Unable to read existing map config");
		return;
	}
	
	while (ReadFileLine(fp, line, sizeof(line))) {
		TrimString(line);
		
		if (strlen(line) <= 0) {
			continue;
		}
		
		argCount = ExplodeString(line, " ", args, 8, 32);
		
		if (argCount <= 0) {
			continue;
		}
		
		if (strcmp(args[0], "site") == 0) {
			HTS_LoadSite(args);
			continue;
		}
		
		if (strcmp(args[0], "spawn") == 0) {
			HTS_LoadSpawn(args);
			continue;
		}
		
		PrintToServer("[HTS] Unknown key in config '%s'", args[0]);
	}
	
	CloseHandle(fp);
	
	PrintToServer("[HTS] Saved config %s", path);
}

public HTS_LoadSite(const String:args[][]) {
	//new String:name[32] = args[1];
	new Float:x = StringToFloat(args[2]);
	new Float:y = StringToFloat(args[3]);
	new Float:z = StringToFloat(args[4]);
	new Float:size = StringToFloat(args[5]);
	
	HTS_AddSite(args[1], x, y, z, size);
}

public HTS_LoadSpawn(const String:args[][]) {
	new site = HTS_FindSite(args[1]);
	new Float:pos[3];
	
	pos[0] = StringToFloat(args[2]);
	pos[1] = StringToFloat(args[3]);
	pos[2] = StringToFloat(args[4]);
	
	HTS_AddSpawn(site, pos);
}


public Action:HTS_SaveCommand(client, argCount) {
	HTS_Save();
	return Plugin_Handled;
}

public HTS_Save() {
	new String:path[256];
	new Handle:fp = INVALID_HANDLE;
	
	Format(path, sizeof(path), "maps/%s.hts.cfg", currentMap);
	fp = OpenFile(path, "w");
	
	for (new i=0; i < siteCount; i++) {
		HTS_SaveSite(fp, i);
	}
	
	CloseHandle(fp);
	PrintToServer("[HTS] Saved config %s", path);
}

public HTS_SaveSite(Handle:fp, site) {
	new Float:x = sitePos[site][0];
	new Float:y = sitePos[site][1];
	new Float:z = sitePos[site][2];
	new Float:size = siteSize[site];
	
	WriteFileLine(fp, "site %s %f %f %f %f", siteName[site], x, y, z, size);
	HTS_SaveSpawns(fp, site);
}

public HTS_SaveSpawns(Handle:fp, site) {
	new Float:x;
	new Float:y;
	new Float:z;
	
	for (new i=0; i < spawnCount[site]; i++) {
		x = spawnPos[site][i][0];
		y = spawnPos[site][i][1];
		z = spawnPos[site][i][2];
		
		WriteFileLine(fp, "spawn %s %f %f %f", siteName[site], x, y, z);
	}
}

