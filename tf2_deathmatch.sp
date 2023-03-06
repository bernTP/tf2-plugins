#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>
#include <sdkhooks>

#define LOOSE_INVICIBILITY 3.2
#define RESPAWN_ONJOIN 5.0
#define RESPAWN_AFTER_DEATH 1.5

#define TIMER_CHECK_MAP_TIME_LEFT 30.0

#define HEALTH_REGEN_PLAYER_REPEAT 5.0
#define HEALTH_REGEN_COOLDOWN 15.0
#define HEALTH_PER_ACTION 10

public Plugin myinfo =
{
	name = "TF2 Deathmatch Plugin",
	author = "tomhk",
	description = "A plugin for a deathmatch mod, fast respawn and win conditions disabled.",
	version = "1.0",
	url = "https://tomhk.fr"
};

ConVar gcvar_autoregen = null;
int gfspi_Health;
bool areWoundedRecently[MAXPLAYERS +1];

public void OnPluginStart()
{
	PrintToServer("TOMHK DEATHMATCH PLUGIN - Init...");
	
	HookEvent("player_death",event_PlayerDeath);
	HookEvent("player_spawn",event_PlayerSpawn);
	HookEvent("player_hurt",event_OnHurt);

	ServerCommand("tf_arena_first_blood 0");
	ServerCommand("tf_arena_use_queue 0");
	ServerCommand("tf_arena_override_team_size 1");
	
	gcvar_autoregen = CreateConVar("toggle_regen", "1", "Auto regen players");
	gfspi_Health = FindSendPropInfo("CBasePlayer", "m_iHealth");
	CreateTimer(HEALTH_REGEN_PLAYER_REPEAT, Timer_RegenPlayer, _, TIMER_REPEAT);

	PrintToServer("TOMHK DEATHMATCH PLUGIN - Running...");
}

public void OnConfigsExecuted() { 

	//ServerCommand("sm_cvar mp_waitingforplayers_time 1");
	//ServerCommand("mp_tournament_readymode_countdown 2880"); // prevents to actually go on
	//ServerCommand("mp_tournament 1");
	//ServerCommand("mp_tournament_restart");
}

public void OnEntityCreated(int entity, const char[] classname) {

	if (StrEqual("game_round_win",classname) || StrEqual("tf_logic_koth",classname) || StrEqual("team_control_point_master",classname) || StrEqual("func_capturezone",classname) || StrEqual("item_teamflag",classname) || StrEqual("trigger_capture_area",classname) || StrEqual("tf_logic_arena",classname) || StrEqual("team_round_timer",classname)) 
		if ( IsValidEntity(entity) )
			SDKHook( entity, SDKHook_SpawnPost, OnEntitySpawned);
}

//======= Hooks

public void OnEntitySpawned(int entity) {
	if ( !IsValidEdict(entity) )
		return;
		
	char classname[32];
	GetEdictClassname(entity, classname, sizeof(classname));
	// By the way we can't make switch of strings in sourcepawn...
	
	if (StrEqual("game_round_win",classname) || StrEqual("tf_logic_koth",classname)) 
		RemoveEdict(entity); // we can't disable it...
	else if (StrEqual("tf_logic_arena",classname)) {
		FireEntityOutput(entity,"OnArenaRoundStart");
		FireEntityOutput(entity,"OnCapEnabled");
		RemoveEdict(entity);
	}
	else if (StrEqual("team_control_point_master",classname) || StrEqual("func_capturezone",classname) || StrEqual("item_teamflag",classname) || StrEqual("trigger_capture_area",classname))
		AcceptEntityInput(entity,"Disable");
}

//======= Events

public void event_PlayerDeath(Event event, const char[] name, bool dontBreadcast) {
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	CreateTimer(RESPAWN_AFTER_DEATH, async_ForceSpawnPlayer,client);	// timer because it's asynchronous for some reasons
}

public void event_PlayerSpawn(Event event, const char[] name, bool dontBreadcast) {

	int client = GetClientOfUserId(event.GetInt("userid")); 
	SetEntProp(client, Prop_Data, "m_takedamage", 0, 1); // No damage
	SetEntityRenderFx (client,RENDERFX_DISTORT); // render transparent
	CreateTimer(LOOSE_INVICIBILITY, async_LooseInvincibility ,client);	
}

public void event_OnHurt(Event event, const char[] name, bool dontBreadcast) {

	int client = GetClientOfUserId(event.GetInt("userid")); 
	if(!IsPlayerAlive(client)) return;
	
	areWoundedRecently[client] = true;
	CreateTimer(HEALTH_REGEN_COOLDOWN, async_CanRegen ,client); // take some time before regen 
}

//======= Async Functions

public Action async_ForceSpawnPlayer(Handle timer, int client) {

	if (!IsValidEntity(client) || !IsValidEdict(client)) 
		return Plugin_Handled;
		
	if (IsPlayerAlive(client)) // in case of dead ringer
		return Plugin_Handled;
	
	if (TF2_GetClientTeam(client) == TFTeam_Spectator) 
		return Plugin_Handled; //and we don't want to spawn spectators
	
	TF2_RespawnPlayer(client);
	return Plugin_Handled;
}

public Action async_LooseInvincibility(Handle timer, int client) {

	if (!IsValidEntity(client) || !IsValidEdict(client)) return Plugin_Handled;
	
	SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
	SetEntityRenderFx (client,RENDERFX_NONE);
	return Plugin_Handled;
}

public Action async_CanRegen(Handle timer, int client) {

	// No validation of entity because he might have quit and the new plyare with the same player index won't get regen or whatever.
	areWoundedRecently[client] = false;
	return Plugin_Handled;
}

//======= Timer functions

public Action Timer_RegenPlayer(Handle timer) {

	if (!GetConVarBool(gcvar_autoregen)) 
		return Plugin_Handled;
	
	for (int player = 1 ;player<=MaxClients;player++) // entity 0 is server
	{
		if ( IsValidEdict(player) && IsValidEntity(player) ) {
			if(IsClientReplay(player)) 
				continue;
			if (IsPlayerAlive(player) && !TF2_IsPlayerInCondition(player,TFCond_OnFire)) { // check if he's not on fire
				int health = GetEntProp(player, Prop_Data, "m_iHealth", 2, 0);
				int maxHealth = GetEntProp(player,Prop_Data,"m_iMaxHealth",2,0);
				if (health < maxHealth && !areWoundedRecently[player]) 
					SetEntData(player, gfspi_Health, min(health + HEALTH_PER_ACTION,maxHealth)); 
			}	
		}
	}	
	return Plugin_Handled;
}

//======= Other Functions

public void DisableWinConditions() {
	
	// game_round_win, team_control_point_master, func_capturezone, item_teamflag, trigger_capture_area, tf_logic_arena, tf_logic_koth
	int maxEnt = GetMaxEntities();
	char classname[32];
	for (int entity = MaxClients +1; entity <= maxEnt; entity++)  
	{
		if(!IsValidEntity(entity) || !IsValidEdict(entity))
			continue;
		
		GetEntityClassname(entity, classname, sizeof(classname));
		
		if(StrContains(classname,"logic") != -1)
			PrintToServer("classname is : %s",classname);
		// By the way we can't make switch of strings in sourcepawn...
		if (StrEqual("game_round_win",classname) || StrEqual("tf_logic_arena",classname) || StrEqual("tf_logic_koth",classname)) 
			RemoveEntity(entity); // we can't disable it...
		else if (StrEqual("team_control_point_master",classname) || StrEqual("func_capturezone",classname) || StrEqual("item_teamflag",classname) || StrEqual("trigger_capture_area",classname))
			RemoveEntity(entity);
		
	}
	
}

public int GetRealClientCount() {
	int count;
	for (int player = 1 ; player <= MaxClients;  player++) 
	{
		if (!IsClientInGame(player) || IsFakeClient(player) || IsClientReplay(player)) continue;
		count++;
	}
	return count;
}

//========= Math Functions =========

public int min(int a, int b) {
	return a < b ? a : b; 
}


