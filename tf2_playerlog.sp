#include <sourcemod>
#include <system2>
#include <tf2>
#include <tf2_stocks>
#include <geoip>

#define DB_INACCESSIBLE "TOMHK LOGGING PLUGIN - DB is not connected."
#define DB_SUCCESS "TOMHK LOGGING PLUGIN - Data stored successfully."

#define SERVERHTTPLINK "http://httpsocket.tomhk.fr"


public Plugin myinfo =
{
	name = "Logging Plugin",
	author = "tomhk",
	description = "Log data from clients and stores it in DB.",
	version = "1.3",
	url = "https://www.tomhk.fr"
};

Database g_database;
int g_JoinTime[MAXPLAYERS +1];

public void OnPluginStart()
{
	PrintToServer("TOMHK LOGGING PLUGIN - Init...");
	
	HookEvent("player_death",event_PlayerDeathLog);
	HookEvent("player_connect",event_PlayerConnectLog);
	HookEvent("player_disconnect",event_PlayerDisconnectLog);
	//HookEvent("player_say",event_PlayerChatLog);
	
	RegConsoleCmd("say", cmd_Say);
	RegConsoleCmd("say2", cmd_Say);
	RegConsoleCmd("say_team", cmd_Say);
	
	HookEvent("player_team",event_OnTeamLog);
	HookEvent("player_changeclass",event_ChangeClass);
	//HookEvent("server_addban",event_PlayerBanLog);	
	//HookEvent("server_removeban",event_PlayerRemoveBanLog);
	HookEvent("player_activate",event_PlayerActivate);
	
	RegConsoleCmd("playerstats",cmd_Stats,"Shows the stats.");
	LoadTranslations("common.phrases.txt");
	
	Database.Connect(DBConnectCallback, "tf2"); 
	
	PrintToServer("TOMHK LOGGING PLUGIN - Running...");
}

public void DBConnectCallback(Database db, const char[] szError, any data) {
	if (db == null || szError[0]){
		SetFailState("Database cannot connect with error %s.",szError);
		return;
	}
	PrintToServer("TOMHK LOGGING PLUGIN - DB connected successfully.");
	g_database = db;
	g_database.SetCharset("utf8");
}

// =========== CMDs

public Action cmd_Stats(int client, int args) {
	if (g_database == null) {
		PrintToChat(client,DB_INACCESSIBLE);
		PrintToConsole(client,DB_INACCESSIBLE);
		return Plugin_Handled;
	}
	
	char clientAuthID[64];
	GetClientAuthId(client,AuthId_Steam3,clientAuthID,sizeof(clientAuthID),true);
	
	char querry[1024];
	FormatEx(querry, sizeof(querry),"SELECT join_times,total_kills,total_deaths,(SELECT AVG(total_kills/total_deaths) FROM tf2.player_log),(WITH cte AS (SELECT networkid,RANK() OVER (ORDER BY total_kills/total_deaths DESC) AS result FROM tf2.player_log WHERE total_kills > 10 OR total_deaths > 10) SELECT result FROM cte WHERE networkid = '%s'),(SELECT SUM(time_spent) FROM tf2.player_log_playtime WHERE networkid='%s'),(SELECT AVG(time_spent) FROM tf2.player_log_playtime WHERE networkid='%s'),(SELECT AVG(time_spent) FROM tf2.player_log_playtime WHERE time_spent > 60),(WITH cte AS ( WITH ctf AS (SELECT networkid,AVG(time_spent) AS timing FROM tf2.player_log_playtime WHERE time_spent >= 60 GROUP by networkid) SELECT networkid,RANK() OVER (ORDER BY timing DESC) AS result FROM ctf) SELECT result FROM cte WHERE networkid = '%s'),(SELECT COUNT(networkid) FROM tf2.player_log) FROM tf2.player_log WHERE networkid = '%s'",clientAuthID,clientAuthID,clientAuthID,clientAuthID,clientAuthID);
	g_database.Query(QuerryCallback_ShowStats,querry,client);
	return Plugin_Handled;
}


// =========== EVENTS

public void event_PlayerDeathLog(Event event, const char[] name, bool dontBreadcast) {
	if (g_database == null) {
		PrintToServer(DB_INACCESSIBLE);
		return;
	}
	
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (IsValidClient(client)) {
		char querryClient[256],clientAuthID[32];
		GetClientAuthId(client,AuthId_Steam3,clientAuthID,sizeof(clientAuthID),true);
		FormatEx(querryClient,sizeof(querryClient),"UPDATE tf2.player_log SET total_deaths = total_deaths + 1 WHERE networkid = '%s'",clientAuthID ); 
		g_database.Query(QuerryCallback_update,querryClient,attacker);
	}
	
	if (!IsValidClient(attacker) || attacker == client) 
		return;
	
	char querryAttacker[256],attackerAuthID[32];
	GetClientAuthId(attacker,AuthId_Steam3,attackerAuthID,sizeof(attackerAuthID),true);
	FormatEx(querryAttacker,sizeof(querryAttacker),"UPDATE tf2.player_log SET total_kills = total_kills + 1 %s WHERE networkid = '%s'", event.GetInt("crit_type") == 2 ? ", total_crit_kills = total_crit_kills + 1":"",attackerAuthID ); 
	g_database.Query(QuerryCallback_update,querryAttacker,attacker);
}

public void event_PlayerConnectLog(Event event, const char[] name, bool dontBreadcast) {
	if ( event.GetInt("bot") == 1 )  
		return;  // No need to log bot activities

	if (g_database == null) {
		PrintToServer(DB_INACCESSIBLE);
		return;
	}
	
	int client = event.GetInt("index") + 1; // +1 because of entity index -1 in index event parameter don't ask why.
	if(client == 0) // sometimes, it will show server name ?
		return;
	
	char querryClient[1024];
	char clientName[64];
	char clientAuthID[64];
	char clientIP[64];
	event.GetString("name", clientName, sizeof(clientName));
	event.GetString("networkid", clientAuthID, sizeof(clientAuthID));
	event.GetString("address", clientIP, sizeof(clientIP));
	
	// player_log normal
	FormatEx(querryClient,sizeof(querryClient),"INSERT INTO tf2.player_log (networkid) VALUES('%s') ON DUPLICATE KEY UPDATE join_times = join_times + 1",clientAuthID); 
	g_database.Query(QuerryCallback_update,querryClient,client);
	
	// playerlog_class
	FormatEx(querryClient,sizeof(querryClient),"INSERT IGNORE INTO tf2.player_log_class (networkid) VALUES ('%s')",clientAuthID ); 
	g_database.Query(QuerryCallback_update,querryClient,client);
	
	// Player log name
	ReplaceString(clientName,sizeof(clientName),"'","\\'"); // make sure that the query works !
	ReplaceString(clientName,sizeof(clientName),"|","");
	FormatEx(querryClient,sizeof(querryClient),"INSERT IGNORE INTO tf2.player_log_name (networkid, playername) VALUES('%s','%s')",clientAuthID,clientName ); 
	g_database.Query(QuerryCallback_update,querryClient,client);
	
	g_JoinTime[client] = GetTime();
	
	// Player log ip
	char playerCountryCode[3];
	char playerCountry[256];
	char playerContinent[256];
	char playerCountryRegion[256];
	char playerCity[256];
	char playerTimezone[256];
	
	float playerLatitude = GeoipLatitude(clientIP);
	float playerLongitude = GeoipLongitude(clientIP);
	
	GeoipCode2(clientIP,playerCountryCode);
	ReplaceString(playerCountryCode,sizeof(playerCountryCode),"'","\\'");
	GeoipCountry(clientIP,playerCountry,sizeof(playerCountry));
	ReplaceString(playerCountry,sizeof(playerCountry),"'","\\'");
	GeoipContinent(clientIP,playerContinent,sizeof(playerContinent));
	ReplaceString(playerContinent,sizeof(playerContinent),"'","\\'");
	GeoipRegion(clientIP,playerCountryRegion,sizeof(playerCountryRegion));
	ReplaceString(playerCountryRegion,sizeof(playerCountryRegion),"'","\\'");
	GeoipCity(clientIP,playerCity,sizeof(playerCity));
	ReplaceString(playerCity,sizeof(playerCity),"'","\\'");
	GeoipTimezone(clientIP,playerTimezone,sizeof(playerTimezone));
	ReplaceString(playerTimezone,sizeof(playerTimezone),"'","\\'");
	
	
	FormatEx(querryClient,sizeof(querryClient),"INSERT IGNORE INTO tf2.player_log_ip (networkid, ip,countrycode,country,countryregion,city,continent,timezone,latitude,longitude) VALUES('%s','%s','%s','%s','%s','%s','%s','%s','%f','%f')",clientAuthID,clientIP,playerCountryCode,playerCountry,playerCountryRegion,playerCity,playerContinent,playerTimezone,playerLatitude,playerLongitude ); 
	g_database.Query(QuerryCallback_update,querryClient,client);
	
	char request[512];
	FormatEx(request,sizeof(request),"SOCKETMANAGER|ADMIN|TF2 Connect|%s (%s) joined !",clientName,clientAuthID);
	System2HTTPRequest httpRequest = new System2HTTPRequest(HttpResponseCallback, SERVERHTTPLINK);
	httpRequest.SetData(request);
	httpRequest.POST(); 
	delete httpRequest;
}

public void event_PlayerDisconnectLog(Event event, const char[] name, bool dontBreadcast) {
	if ( event.GetInt("bot") == 1 )  
		return;

	if (g_database == null) {
		PrintToServer(DB_INACCESSIBLE);
		return;
	}
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsValidClient(client))
		return;
	
	int timeJoin = g_JoinTime[client];
	int timeExit = GetTime();
	int timePlayed = timeExit - timeJoin;
	g_JoinTime[client] = 0;
	
	if( timePlayed >= 31536000) { // HACK : For some reason timePlayed is GetTime() ???
		timePlayed = 0;
		timeJoin = timeExit;
	}
	
	char querryClient[512];
	char clientAuthID[64];
	char reason[128];
	event.GetString("networkid", clientAuthID, sizeof(clientAuthID));
	event.GetString("reason",reason,sizeof(reason));
	
	// Register disconnect reason
	FormatEx(querryClient,sizeof(querryClient),"INSERT INTO tf2.player_log_disconnect_reason (networkid, reason) VALUES('%s', '%s')",clientAuthID,reason); 
	g_database.Query(QuerryCallback_update,querryClient,client);
	
	// register the time
	FormatEx(querryClient,sizeof(querryClient),"INSERT INTO tf2.player_log_playtime (networkid, time_spent,time_join,time_exit) VALUES('%s', %d, %d, %d)",clientAuthID,timePlayed,timeJoin,timeExit); 
	g_database.Query(QuerryCallback_update,querryClient,client);
	
	char clientName[MAX_NAME_LENGTH]; 
	GetClientName(client,clientName,sizeof(clientName));
	ReplaceString(clientName,sizeof(clientName),"'","\\'");
	ReplaceString(clientName,sizeof(clientName),"|","");
	
	char request[512];
	FormatEx(request,sizeof(request),"SOCKETMANAGER|ADMIN|TF2 Disconnect|%s (%s) disconnect...",clientName,clientAuthID);
	
	System2HTTPRequest httpRequest = new System2HTTPRequest(HttpResponseCallback, SERVERHTTPLINK);
	httpRequest.SetData(request);
	httpRequest.POST(); 
	delete httpRequest;
}

/*public void event_PlayerChatLog(Event event, const char[] name, bool dontBreadcast) {
	if (g_database == null) {
		PrintToServer(DB_INACCESSIBLE);
		return;
	}
	
	char querryClient[512];
	char chat[256];
	char clientAuthID[64];
	event.GetString("text", chat, sizeof(chat));
	int client = event.GetInt("userid");
	char clientName[MAX_NAME_LENGTH]; 
	
	ReplaceString(chat,sizeof(chat),"'","\\'");
	ReplaceString(chat,sizeof(chat),"|","");
	
	if (client == 0) {
		Format(clientAuthID,sizeof(clientAuthID),"[Console]");
		Format(clientName,sizeof(clientName),"Console");
	}
	
	else {
		client = GetClientOfUserId(client);
		GetClientAuthId(client,AuthId_Steam3,clientAuthID,sizeof(clientAuthID),true);
		
		GetClientName(client,clientName,sizeof(clientName));
		ReplaceString(clientName,sizeof(clientName),"'","\\'");
		ReplaceString(clientName,sizeof(clientName),"|","");
	}
	
	int clients = GetRealClientCount();
	int time = GetTime();
	
	char request[512];
	FormatEx(request,sizeof(request),"SOCKETMANAGER|ADMIN|TF2 Chat|%s (%s) : %s",clientName,clientAuthID,chat);
	System2HTTPRequest httpRequest = new System2HTTPRequest(HttpResponseCallback, SERVERHTTPLINK);
	httpRequest.SetData(request);
	httpRequest.POST(); 
	delete httpRequest;
	
	int is_command = StrContains(chat,"!") != -1 || StrContains(chat,"/") != -1 ? 1 : 0;
	FormatEx(querryClient,sizeof(querryClient),"INSERT INTO tf2.player_log_chat (networkid, chat ,is_command,time,playersingame) VALUES('%s', '%s', '%d','%d','%d')",clientAuthID,chat,is_command,time,clients); 
	g_database.Query(QuerryCallback_update,querryClient,client);
}*/

public Action cmd_Say(int client, int args) { // event_PlayerChatLog
	if (g_database == null) {
		PrintToServer(DB_INACCESSIBLE);
		return Plugin_Continue;
	}
	
	if (args < 1)
		return Plugin_Continue;
	
	char querryClient[512];
	char clientAuthID[64];
	char chat[256];
	char clientName[MAX_NAME_LENGTH]; 
	
	GetCmdArg(1,chat,sizeof(chat));
	
	ReplaceString(chat,sizeof(chat),"'","\\'");
	ReplaceString(chat,sizeof(chat),"|","");
	
	if (client == 0) {
		Format(clientAuthID,sizeof(clientAuthID),"[Console]");
		Format(clientName,sizeof(clientName),"Console");
	}
	
	else {
		GetClientAuthId(client,AuthId_Steam3,clientAuthID,sizeof(clientAuthID),true);
		
		GetClientName(client,clientName,sizeof(clientName));
		ReplaceString(clientName,sizeof(clientName),"'","\\'");
		ReplaceString(clientName,sizeof(clientName),"|","");
	}
	
	int clients = GetRealClientCount();
	int time = GetTime();
	
	FormatEx(querryClient,sizeof(querryClient),"INSERT INTO tf2.player_log_chat (networkid, chat,was_muted,time,playersingame) VALUES('%s', '%s',(SELECT is_muted FROM tf2.player_log WHERE networkid = '%s'), '%d','%d')",clientAuthID,chat,clientAuthID,time,clients); 
	g_database.Query(QuerryCallback_update,querryClient,client);
	
	char request[512];
	FormatEx(request,sizeof(request),"SOCKETMANAGER|ADMIN|TF2 Chat|%s (%s) : %s",clientName,clientAuthID,chat);
	System2HTTPRequest httpRequest = new System2HTTPRequest(HttpResponseCallback, SERVERHTTPLINK);
	httpRequest.SetData(request);
	httpRequest.POST(); 
	delete httpRequest;
	
	return Plugin_Continue;
}

public void event_OnTeamLog(Event event, const char[] name, bool dontBreadcast) { 

	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (!IsClientInGame(client) || IsFakeClient(client)) 
		return; 

	if (g_database == null) {
		PrintToServer(DB_INACCESSIBLE);
		return;
	}
	
	int team = event.GetInt("team");
	char querryClient[512];
	char clientAuthID[64];
	GetClientAuthId(client,AuthId_Steam3,clientAuthID,sizeof(clientAuthID),true);
	
	switch (team) {
		case 1: //spec
		{
			FormatEx(querryClient,sizeof(querryClient),"UPDATE tf2.player_log SET team_spec = team_spec + 1 WHERE networkid = '%s'",clientAuthID); 
		}
		case 2: // team_red
		{
			FormatEx(querryClient,sizeof(querryClient),"UPDATE tf2.player_log SET team_red = team_red + 1 WHERE networkid = '%s'",clientAuthID); 
		}
		case 3: // team_blue
		{
			FormatEx(querryClient,sizeof(querryClient),"UPDATE tf2.player_log SET team_blue = team_blue + 1 WHERE networkid = '%s'",clientAuthID); 
		}
		default: 
		{
			return; // we don't know the team then ?
		}
	}
	
	g_database.Query(QuerryCallback_update,querryClient,client);
}


/*public void event_PlayerBanLog(Event event, const char[] name, bool dontBreadcast) {
	if (g_database == null) {
		PrintToServer(DB_INACCESSIBLE);
		return;
	}
	
	// Normally, no bots should be voteban...
	
	char querryClient[512];
	char clientAuthID[64];
	event.GetString("networkid", clientAuthID, sizeof(clientAuthID));

	char banBy[MAX_NAME_LENGTH];
	event.GetString("by", banBy, sizeof(banBy));
	
	char duration[16];
	event.GetString("duration", duration, sizeof(duration));

	FormatEx(querryClient,sizeof(querryClient),"UPDATE tf2.player_log SET is_ban = 1, number_ban = number_ban + 1, length_ban = '%s', banby = '%s' WHERE networkid = '%s'",duration,banBy,clientAuthID); 
	g_database.Query(QuerryCallback_update,querryClient,0);
	
}

public void event_PlayerRemoveBanLog(Event event, const char[] name, bool dontBreadcast) {
	if (g_database == null) {
		PrintToServer(DB_INACCESSIBLE);
		return;
	}
	
	char querryClient[512];
	char clientAuthID[64];
	event.GetString("networkid", clientAuthID, sizeof(clientAuthID));

	char removedBanBy[MAX_NAME_LENGTH];
	event.GetString("by", removedBanBy, sizeof(removedBanBy));

	FormatEx(querryClient,sizeof(querryClient),"UPDATE tf2.player_log SET is_ban = 0, length_ban = 0, removedbanby = '%s' WHERE networkid = '%s'",removedBanBy,clientAuthID); 
	g_database.Query(QuerryCallback_update,querryClient,0);
	
}*/

public void event_ChangeClass(Event event, const char[] name, bool dontBreadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (!IsClientInGame(client) || IsFakeClient(client)) 
		return; 
		
	if (g_database == null) {
		PrintToServer(DB_INACCESSIBLE);
		return;
	}
		
	char querryClient[512];
	char clientAuthID[64];
	char classname[16];
	
	GetClientAuthId(client,AuthId_Steam3,clientAuthID,sizeof(clientAuthID),true);
	
	switch (event.GetInt("class")) 
	{
		case TFClass_Scout:
			Format(classname,sizeof(classname),"scout");
		case TFClass_Soldier:
			Format(classname,sizeof(classname),"soldier");
		case TFClass_Pyro:
			Format(classname,sizeof(classname),"pyro");
		case TFClass_DemoMan:
			Format(classname,sizeof(classname),"demoman");
		case TFClass_Heavy:
			Format(classname,sizeof(classname),"heavy");
		case TFClass_Engineer:
			Format(classname,sizeof(classname),"engineer");
		case TFClass_Medic:
			Format(classname,sizeof(classname),"medic");
		case TFClass_Sniper:
			Format(classname,sizeof(classname),"sniper");
		case TFClass_Spy:
			Format(classname,sizeof(classname),"spy");
	}
	
	FormatEx(querryClient,sizeof(querryClient),"UPDATE tf2.player_log_class SET %s = %s + 1 WHERE networkid = '%s'",classname,classname,clientAuthID); 
	g_database.Query(QuerryCallback_update,querryClient,0);
}

public void event_PlayerActivate(Event event, const char[] name, bool dontBreadcast) {
	if ( event.GetInt("bot") == 1 )  
		return; 
		
	if (g_database == null) {
		PrintToServer(DB_INACCESSIBLE);
		return;
	}
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if( IsFakeClient(client)) // weird error
		return;
	
	char querryClient[512];
	char clientAuthID[64];
	GetClientAuthId(client,AuthId_Steam3,clientAuthID,sizeof(clientAuthID),true);
	float latency = GetClientLatency(client,NetFlow_Both);
	
	FormatEx(querryClient,sizeof(querryClient),"UPDATE tf2.player_log SET latency = %f WHERE networkid='%s'",latency,clientAuthID);
	g_database.Query(QuerryCallback_update,querryClient,0);
}

// ===== others

public int GetRealClientCount() {
	int count;
	for (int player = 1; player <= MaxClients;  player++) 
	{
		if (!IsClientInGame(player) || IsFakeClient(player)) continue;
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

//====== Callbacks

public void QuerryCallback_update(Database hDatabase, DBResultSet results, const char[] sError, int client) {
	if(sError[0]) {
		LogError("DB Error during UPDATE querry: %s", sError); 
		return; 
	}
}

public void QuerryCallback_ShowStats(Database hDatabase, DBResultSet results, const char[] sError, int client) {
	
	if(sError[0]) {
		LogError("DB Error during UPDATE querry: %s", sError); 
		return; 
	}
	
	DBResult status;
	results.FetchRow();
	
	int join_times = results.FetchInt(0,status);
	int total_kills = results.FetchInt(1,status);
	int total_deaths = results.FetchInt(2,status);
	float ratio = float(total_kills)/float(total_deaths);
	float averageRatio = results.FetchFloat(3,status);
	int rankRatio = results.FetchInt(4,status);
	
	char charTotalPlaytime[32];
	int totalPlaytime = results.FetchInt(5,status); 
	FormatEx(charTotalPlaytime,sizeof(charTotalPlaytime),"%dh:%dm:%ds",(totalPlaytime / 3600) % 24,(totalPlaytime / 60) % 60,totalPlaytime % 60);
	
	char charAveragePlaytime[32];
	int averagePlaytime = RoundFloat(results.FetchFloat(6,status));
	FormatEx(charAveragePlaytime,sizeof(charAveragePlaytime),"%dh:%dm:%ds",(averagePlaytime / 3600) % 24,(averagePlaytime / 60) % 60,averagePlaytime % 60);
	
	char charAverageServerTime[32];
	int averageServerTime = RoundFloat(results.FetchFloat(7,status));
	FormatEx(charAverageServerTime,sizeof(charAverageServerTime),"%dh:%dm:%ds",(averageServerTime / 3600) % 24,(averageServerTime / 60) % 60,averageServerTime % 60);
	
	int rank_playtime = results.FetchInt(8,status);
	int count = results.FetchInt(9,status);
	
	char textFormated1[256];
	char textFormated2[256];
	FormatEx(textFormated1,sizeof(textFormated1),"\x03[Stats]\x01 :\nJoin times : %d\nTotal Kills : %d\nTotal Deaths: %d\nRatio : %.2f\n(Server ratio) : %.2f\nYour ratio rank : %d/%d\n",join_times,total_kills,total_deaths,ratio,averageRatio,rankRatio,count);
	FormatEx(textFormated2,sizeof(textFormated2),"\nYour total playtime : %s\nYour average playtime : %s\n(Server time average) : %s\n Your rank among other average play time : %d/%d",charTotalPlaytime,charAveragePlaytime,charAverageServerTime,rank_playtime,count);
	PrintToChat(client,textFormated1);
	PrintToChat(client,textFormated2);
	PrintToConsole(client,textFormated1);
	PrintToConsole(client,textFormated2);
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