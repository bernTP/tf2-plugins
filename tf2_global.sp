#include <sourcemod>
#include <tf2>
#include <sdktools>
#include <sdkhooks>

#include <system2>
#include <SteamWorks>

#define DB_ERROR "TOMHK GLOBAL PLUGIN - Error on querry : %s"
#define DB_SUCCESS "TOMHK GLOBAL PLUGIN - Data stored successfully."
#define DB_INACCESSIBLE "TOMHK GLOBAL PLUGIN - DB is not connected."
#define DB_INACCESSIBLE_CLIENT "\x03[Global Plugin]\x01 : Sorry, can't execute the command due to a DB error."

#define END_ROUND_ERROR "TOMHK GLOBAL PLUGIN - Can't end round, game_round_win can't be created..."
#define REPLAY_DELETE_ERROR "TOMHK GLOBAL PLUGIN - Can't delete replays !"

#define SERVERHTTPLINK "http://httpsocket.tomhk.fr"
#define GAME_SECTION_DESCRIPTION "TF2 FASTRESPAWN"
#define DOMAIN_NAME "" //tomhk.fr

#define TIMER_CHECK_MAP_TIME_LEFT 1.0
#define TIMER_REPLAY_CLEANER 90.0
#define TIMER_CHECK_REMAINING_PLAYERS 2.0
#define TIMER_WELCOME 3.0
#define TIMELIMIT 172800

#define TIMER_MESSAGE_REPEAT 720.0

char deleteReplayCommand[] = "rm /home/sourcegameserver/tf2replays/*"; // replay_docleanup force do nothing or crashes the server.


public Plugin myinfo =
{
	name = "Global Plugin",
	author = "tomhk",
	description = "Universal event forwards for tomhk.fr servers. It shows helper and forwards server commands.",
	version = "1.1.3",
	url = "https://www.tomhk.fr"
};

/*
if (!IsClientInGame(player) || IsFakeClient(player)) 
*/

Database g_database;
int g_realTimeLimit;
bool gb_playerAlreadyShowedWelcome[MAXPLAYERS +1] = false;
//bool gb_playerHasTag[MAXPLAYERS +1] = false;
//int gi_playerIndexes[MAXPLAYERS + 1];

public void OnPluginStart()
{
	PrintToServer("TOMHK GLOBAL PLUGIN - Init...");
	
	HookEvent("player_spawn",event_ClientSpawn);
	HookEvent("player_team",event_ClientTeam);
	
	// bot managin
	HookEvent("player_activate",event_PlayerActivate);
	HookEvent("player_disconnect",event_PlayerDisconnect);
	
	// Pre Events
	HookEvent("player_connect_client",eventPre_PlayerConnect,EventHookMode_Pre);
	HookEvent("player_team",eventPre_PlayerTeam,EventHookMode_Pre);
	HookEvent("player_disconnect",eventPre_PlayerDisconnect,EventHookMode_Pre);
	HookEvent("server_cvar",eventPre_ServerCvar,EventHookMode_Pre);
	
	// Helper
	//AddCommandListener(listener_SayHelper, "say");
	//AddCommandListener(listener_SayHelper, "say_team");
	RegConsoleCmd("h",cmd_Helper,"Help menu");
	RegServerCmd("restart_time_left",restartTimeLeft);
	
	LoadTranslations("common.phrases.txt"); // Required for FindTarget fail reply
	
	// timers
	CreateTimer(TIMER_MESSAGE_REPEAT, Timer_ShowRandomMessage, _, TIMER_REPEAT); // show a global message every 6 minutes
	
	// Check if map is over | It's already here
	CreateTimer(TIMER_CHECK_MAP_TIME_LEFT,Timer_CheckTimeLeft, _, TIMER_REPEAT);
	
	Database.Connect(DBConnectCallback, "tf2"); 

	PrintToServer("TOMHK GLOBAL PLUGIN - Running...");
}

public void DBConnectCallback(Database db, const char[] szError, any data) {
	if (db == null || szError[0]){
		SetFailState("Database cannot connect with error %s.",szError);
		return;
	}
	PrintToServer("TOMHK GLOBAL PLUGIN - DB connected successfully .");
	g_database = db;
	g_database.SetCharset("utf8");
}

public void OnConfigsExecuted() { // DEAR LORD DO NOT USE OnMapStart THIS IS A TRAP DO NOT USE IT !!!

	SteamWorks_SetGameDescription(GAME_SECTION_DESCRIPTION);
	// This trick permits to be on top of server list
	char command[255];
	char hostName[64];
	ConVar hostname = FindConVar("hostname");
	GetConVarString(hostname,hostName,sizeof(hostName));
	FormatEx(command,sizeof(command),"hostname %s",hostName);
	ServerCommand(command); 
}

public void OnMapEnd() {

	char output[256];
	bool result = System2_Execute(output,256, deleteReplayCommand) ;
	if(!result) 
		PrintToServer(REPLAY_DELETE_ERROR);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual("func_brush",classname))
		if ( IsValidEntity(entity) )
			SDKHook( entity, SDKHook_Spawn, OnEntitySpawned);
}

public void OnMapStart() {
	g_realTimeLimit = TIMELIMIT; // maps are during 172800 seconds...
}

//======= Hooks

public void OnEntitySpawned(int entity) { 
	if ( !IsValidEdict(entity) )
		return;
		
	char classname[32];
	GetEdictClassname(entity, classname, sizeof(classname));
	
	if (StrEqual("func_brush",classname)) // we delete some key values that block tf_projectiles : arena_watchtower
		DispatchKeyValue(entity,"solidbsp","0");
}

// ====== Events PRE Forwards

public Action eventPre_PlayerConnect(Event event, const char[] name, bool dontBroadcast) { 
	if(event.GetInt("bot"))
		event.BroadcastDisabled = true;
	return Plugin_Continue;
}

public Action eventPre_PlayerTeam(Event event, const char[] name, bool dontBroadcast) { 
	if(event.GetInt("bot"))
		event.BroadcastDisabled = true;
	return Plugin_Continue;
}

public Action eventPre_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) { 
	if(event.GetInt("bot"))
		event.BroadcastDisabled = true;
	return Plugin_Continue;
}

public Action eventPre_ServerCvar(Event event, const char[] name, bool dontBroadcast) { 
	// On s'en fout
	event.BroadcastDisabled = true;
	return Plugin_Continue;
}

//============ Event Forwards

public void event_PlayerActivate(Event event, const char[] name, bool dontBroadcast) { 
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsValidClient(client) || IsFakeClient(client))
		return;
	
	int clients = GetRealClientCount();
	if (clients == 1) {
		ServerCommand("rcbotd config max_bots 17");
	}
}

public void event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {

	CreateTimer(TIMER_CHECK_REMAINING_PLAYERS,Timer_CheckRemainingPlayer,event.GetInt("bot"));
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsValidClient(client) || IsFakeClient(client))
		return;
	
	gb_playerAlreadyShowedWelcome[client] = false;
}

public void event_ClientSpawn(Event event, const char[] name, bool dontBroadcast) {
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientInGame(client) || IsFakeClient(client)) return;
	
	CreateTimer(0.1,Timer_ShowTag,client); //0.1 because if immediate, it would break.
}

public void event_ClientTeam(Event event, const char[] name, bool dontBroadcast) {
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientInGame(client) || IsFakeClient(client)) return;
	
	if(!gb_playerAlreadyShowedWelcome[client] && g_database != null) {
		CreateTimer(TIMER_WELCOME,Timer_Welcome,client);
	}
}

/*public Action listener_SayHelper(int client, const char[] command, int args) {

	bool isChat = true;
	char arg[256];
	GetCmdArg(1, arg, sizeof(arg));
	
	if((StrContains(arg,"/h") == -1) && (StrContains(arg,"!h") == -1)){
		return Plugin_Continue;
	}
	
	if (g_database == null) {
		PrintToChat(client,DB_INACCESSIBLE_CLIENT);
		return Plugin_Changed;
	}
	
	DataPack dpClientAndIsChat = new DataPack();
	dpClientAndIsChat.WriteCell(client); // write cell is always first
	dpClientAndIsChat.WriteCell(isChat);
	
	char querry[256];
	FormatEx(querry, sizeof(querry),"SELECT command,description,votecommand FROM tf2.commands WHERE is_using = 1");
	g_database.Query(QuerryCallback_helper,querry,dpClientAndIsChat);
	return Plugin_Changed;
}*/

//=========== Commands

public Action cmd_Helper(int client, int args) {
	if (g_database == null) {
		PrintToChat(client,DB_INACCESSIBLE_CLIENT);
		return Plugin_Changed;
	}
	
	char querry[256];
	FormatEx(querry, sizeof(querry),"SELECT command,description,votecommand FROM tf2.commands WHERE is_using = 1");
	g_database.Query(QuerryCallback_helper,querry,client);
	return Plugin_Changed;
}

public Action restartTimeLeft(int args) {
	PrintToServer("Time left before restart : %d",g_realTimeLimit);
	return Plugin_Handled;
}

//============ Timers

public Action Timer_ShowRandomMessage(Handle timer) {

	if (g_database == null || GetClientCount() == 0) 
		return Plugin_Handled;
		
	char querry[128];
	FormatEx(querry, sizeof(querry),"SELECT text FROM tf2.global_messages WHERE isnecessary = 0");
	g_database.Query(QuerryCallback_TimerRandomMessage,querry,0);
	return Plugin_Handled;
}

public Action Timer_ShowTag(Handle timer, int client) {
	if(!IsClientInGame(client))
		return Plugin_Handled;
	Handle hudText = CreateHudSynchronizer();
	SetHudTextParams(0.236,0.926,2880.0,255,255,255,100);
	ShowSyncHudText(client, hudText, DOMAIN_NAME);
	CloseHandle(hudText);
	return Plugin_Handled;
}

public Action Timer_Welcome(Handle timer, int client) {
	if(!IsClientInGame(client))
		return Plugin_Handled;
	
	gb_playerAlreadyShowedWelcome[client] = true;
	PrintHintText(client,"Say '/h' in the chat to see all the available commands.");
	if(GetRealClientCount() == 1) {
		Menu menu = new Menu(Menu_KickBots_Callback);
		menu.SetTitle("Do you want to HAVE bots ? (automatically yes) :");
		menu.AddItem("yes","Yes",ITEMDRAW_DEFAULT);
		menu.AddItem("no","No",ITEMDRAW_DEFAULT);
		menu.Display(client,30); 
	}
	char querry[128];
	FormatEx(querry, sizeof(querry),"SELECT text FROM tf2.global_messages WHERE isnecessary = 1");
	g_database.Query(QuerryCallback_ImportantMessage,querry,client);
	return Plugin_Handled;
}

public Action Timer_CheckRemainingPlayer(Handle timer, int isbot) {
	int clients = GetRealClientCount();
	if (clients == 0) {
		ServerCommand("rcbotd config max_bots 1");
		CreateTimer(TIMER_REPLAY_CLEANER,Timer_ReplayCleaner,isbot);
	}
	return Plugin_Handled;
}

public Action Timer_ShowImportantMessage(Handle timer,DataPack dpTextAndClient) {

	DataPack pack = view_as<DataPack>(dpTextAndClient);
	pack.Reset();
	int client = pack.ReadCell();
	
	char text[256];
	char textFormated[384];
	pack.ReadString(text,sizeof(text));
	FormatEx(textFormated,sizeof(textFormated),"\x03[Notice]\x01 : %s",text);
	
	delete pack;
	
	if (!IsClientInGame(client)) 
		return Plugin_Handled;

	PrintToChat(client,textFormated);
	return Plugin_Handled;
}

public Action Timer_ReplayCleaner(Handle timer, int isbot) {
	if (isbot)
		return Plugin_Handled;
		
	char output[256];
	bool result = System2_Execute(output,256, deleteReplayCommand) ;
	if(!result) 
		PrintToServer(REPLAY_DELETE_ERROR);
	return Plugin_Handled;
}

public Action Timer_CheckTimeLeft(Handle timer) {

	g_realTimeLimit -= 1;
	if(!(g_realTimeLimit == 0)) 
		return Plugin_Handled;
	PrintToChatAll("\x03[Notice]\x01 : Times up, the server needs to restart in 10 seconds.");
	PrintHintTextToAll("\x03[Notice]\x01 : Times up, the server needs to restart in 10 seconds.");
	
	CreateTimer(10.0,async_EndRound);
	return Plugin_Handled;
}

//========= Async Functions ==========

public Action async_EndRound(Handle timer) {

	char map[64];
	GetRealClientCount() == 0 ? FormatEx(map,sizeof(map),"ctf_2fort") : GetCurrentMap(map,sizeof(map));
	ServerCommand("changelevel %s",map);
	return Plugin_Handled;

}

//========= Utility functions =========

public int GetRealClientCount() {
	int count;
	for (int player = 1 ; player <= MaxClients;  player++) 
	{
		if (!IsClientInGame(player) || IsFakeClient(player) || IsClientReplay(player)) continue;
		count++;
	}
	return count;
}

public bool IsValidClient(client) {
	if (client <= 0 || client > MaxClients) 
		return false;
	if (!IsClientInGame(client)) 
		return false;
	if (IsClientSourceTV(client) || IsClientReplay(client)) 
		return false;
	return true;
}

//========= Querry Callbacks =========

public void QuerryCallback_TimerRandomMessage(Database hDatabase, DBResultSet results, const char[] sError, int unused) {
	
	if(sError[0]) {
		LogError(DB_ERROR, sError); 
		return; 
	}
	
	DBResult status;
	
	SetRandomSeed(GetTime());
	int randomNumber = GetRandomInt(0,results.RowCount-1);
	for (int i; i <= randomNumber; i++) { results.FetchRow();}
	
	char text[256];
	char textFormated[384];
	results.FetchString(0,text,sizeof(text),status);
	FormatEx(textFormated,sizeof(textFormated),"\x03[Notice]\x01 : %s",text);
	PrintToChatAll(textFormated);
}

public void QuerryCallback_ImportantMessage(Database hDatabase, DBResultSet results, const char[] sError, int client) {

	if(sError[0]) {
		LogError(DB_ERROR, sError); 
		return; 
	}
	
	DBResult status;
	
	float counter = 6.0;
	while(results.FetchRow()) {
	
		char text[256];
		results.FetchString(0,text,sizeof(text),status);
		
		DataPack dpTextAndClient = new DataPack();
		dpTextAndClient.WriteCell(client); // write cell is always first
		dpTextAndClient.WriteString(text);
		
		CreateTimer(counter, Timer_ShowImportantMessage,dpTextAndClient);
		counter += 7;
	}
}

public void QuerryCallback_helper(Database hDatabase, DBResultSet results, const char[] sError, int client) {
	
	if(sError[0]) {
		LogError(DB_ERROR, sError); 
		return; 
	}
	
	DBResult status;
	
	char beginning[] = "\n\x04[Global Plugin]\x01 : Here are all the commands available, you need to do votemenu for the (VOTE) commands first to execute them :\n ";
	PrintToChat(client,beginning);
	PrintToConsole(client,beginning);
	
	char votePluginHelp[] = "\x03votemenu\x01 = Shows a menu to execute some commands.\n";
	PrintToChat(client,votePluginHelp);
	PrintToConsole(client,votePluginHelp);

	while(results.FetchRow()) 
	{
		char command[64];
		char description[256];
		char voteHelper[256];
		results.FetchString(0,command,sizeof(command),status);
		results.FetchString(1,description,sizeof(description),status);
		FormatEx(voteHelper,sizeof(voteHelper),"\x03%s\x01 =%s %s\n",command,results.FetchInt(2) ? " (VOTE)" : "",description);
		PrintToChat(client,voteHelper)
		PrintToConsole(client,voteHelper);
	}
}

public void HttpResponseCallback(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method) {

	if (success) {
		char lastURL[128];
		response.GetLastURL(lastURL, sizeof(lastURL));
		int statusCode = response.StatusCode;
		float totalTime = response.TotalTime;

		PrintToServer("Request to %s finished with status code %d in %.2f seconds", lastURL, statusCode, totalTime);
	} 
	else {
		PrintToServer("Error on request: %s", error);
	}
}

// ==== Menu callback

public int Menu_KickBots_Callback(Menu menu, MenuAction action, int clientVoter, int param2) {
	switch(action) {
		case MenuAction_Select: {
			char item[4];
			menu.GetItem(param2,item,sizeof(item));
			if(strcmp(item,"no") == 0) {
				ServerCommand("rcbotd config max_bots 1");
			}
		}
		
		case MenuAction_End: {
			delete menu;
		}
	}
}