#include <sourcemod>

#define DB_ERROR "TOMHK GLOBAL PLUGIN - Error on querry : %s"
#define DB_SUCCESS "TOMHK GLOBAL PLUGIN - Data stored successfully."
#define DB_INACCESSIBLE "TOMHK GLOBAL PLUGIN - DB is not connected."
#define DB_INACCESSIBLE_CLIENT "\x03[Global Plugin]\x01 : Sorry, can't execute the command due to a DB error."

#define DEFAULT_BAN_REASON "VAC Anticheat has detected suspicious activities during this session. This incident will be reported"

public Plugin myinfo =
{
	name = "Ban system",
	author = "tomhk",
	description = "Handle bans, mutes and other things.",
	version = "1.0",
	url = "https://www.tomhk.fr"
};

Database g_database;

gb_isMuted[MAXPLAYERS +1] = false;

public void OnPluginStart()
{
	PrintToServer("TOMHK BAN PLUGIN - Init...");
	
	HookEvent("player_connect",event_ClientConnect);
	HookEvent("player_disconnect",event_ClientDisconnect);
	
	RegConsoleCmd("say", cmd_Say);
	RegConsoleCmd("say2", cmd_Say);
	RegConsoleCmd("say_team", cmd_Say);
	
	RegAdminCmd("advban",cmd_Ban,ADMFLAG_BAN,"Ban people and kick them."); // the vanilla ban system is so shitty i have to write it myself
	RegAdminCmd("advunban",cmd_Unban,ADMFLAG_BAN,"Ban people and kick them."); 

	RegAdminCmd("advmute",cmd_Mute,ADMFLAG_BAN,"Ban people and kick them."); // the vanilla ban system is so shitty i have to write it myself
	RegAdminCmd("advunmute",cmd_Unmute,ADMFLAG_BAN,"Ban people and kick them."); 
	
	LoadTranslations("common.phrases.txt"); // Required for FindTarget fail reply
	
	Database.Connect(DBConnectCallback, "tf2"); 
	PrintToServer("TOMHK BAN PLUGIN - Running...");
}

public void DBConnectCallback(Database db, const char[] szError, any data) {
	if (db == null || szError[0]){
		SetFailState("Database cannot connect with error %s.",szError);
		return;
	}
	PrintToServer("TOMHK BAN PLUGIN - DB connected successfully.");
	g_database = db;
	g_database.SetCharset("utf8");
}

// ==== Events ====

public void event_ClientConnect(Event event, const char[] name, bool dontBreadcast) {
	if ( event.GetInt("bot") == 1 )  
		return;  
		
	int client = event.GetInt("index") + 1;
	char clientAuthID[32];
	event.GetString("networkid", clientAuthID, sizeof(clientAuthID));
	
	char querry[256];
	FormatEx(querry, sizeof(querry),"SELECT is_muted FROM tf2.player_log WHERE networkid = '%s' AND is_muted = 1",clientAuthID);
	g_database.Query(QuerryCallback_IsMuted,querry,client);
	FormatEx(querry, sizeof(querry),"SELECT time_unban,reason,networkid FROM tf2.player_log WHERE networkid = '%s' AND is_ban = 1",clientAuthID);
	g_database.Query(QuerryCallback_IsBan,querry,client);
}

public void event_ClientDisconnect(Event event, const char[] name, bool dontBreadcast) {
	if ( event.GetInt("bot") == 1 )  
		return;  
	int client = GetClientOfUserId(event.GetInt("userid"));
	gb_isMuted[client] = false;
}

// ==== Regular Commands ==== 

public Action cmd_Say(int client, int args) {
	if (IsValidClient(client)){
		if (gb_isMuted[client])
			return Plugin_Handled;		
	}
	return Plugin_Continue;
}

// ==== Admin Commands ====

public Action cmd_Ban(int client, int args) {
	if(args < 2) {
		PrintToChatEx(client,"\x03[ERROR]\x01 : Syntax : advban <time> \"<#userid/[networkid]>\" <?reason>");
		return Plugin_Handled;
	}
	
	bool banresult;
	
	char charTime[32]; // GetCmdArgInt doesn't work.
	GetCmdArg(1,charTime,sizeof(charTime));
	int time = StringToInt(charTime);
	int dbtime = time == 0 ? time : GetTime()+ time*60;

	char arg_target[64];
	GetCmdArg(2, arg_target, sizeof(arg_target));
	bool isuserid = true;
	
	if(StrContains(arg_target,"[") != -1) // array slicing doesn't seem to work 
		isuserid = false;
	
	char reason[256];
	if(args == 3) {
		GetCmdArg(3, reason, sizeof(reason));
	}
	else {
		FormatEx(reason,sizeof(reason),DEFAULT_BAN_REASON);
	}
	char finalReason[256];
	FormatEx(finalReason,sizeof(finalReason),"Banned : %s",reason);

	char targetAuthID[32];
	if(isuserid) {
		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) { // you have parsed networkid
			PrintToChatEx(client,"\x03[ERROR]\x01 Bad userid...");
			return Plugin_Handled;
		}
		GetClientAuthId(target,AuthId_Steam3,targetAuthID,sizeof(targetAuthID),true);
		banresult = BanClient(target,time,BANFLAG_AUTHID,finalReason,finalReason);
		if(!banresult)
			PrintToChatEx(client,"\x03[ERROR]\x01 Ban failed ! Will ban via identity instead...");
		KickClientEx(target,finalReason);
	}
	else {
		bool isfound = false;
		for(int player = 1; player <= MaxClients; player++) // try to find him to kick him
		{
			if(!IsValidClient(player))
				continue;
			
			GetClientAuthId(player,AuthId_Steam3,targetAuthID,sizeof(targetAuthID),true);
			if(strcmp(targetAuthID,arg_target,true) == 0) {
				isfound = true;
				banresult = BanClient(player,time,BANFLAG_AUTHID,finalReason,finalReason);
				if(!banresult)
					PrintToChatEx(client,"\x03[ERROR]\x01 Ban failed ! Will ban via identity instead...");	
				KickClientEx(player,finalReason);
				break;
			}
		}
		if(!isfound) // he was gone, just assume you knew his networkid
			FormatEx(targetAuthID,sizeof(targetAuthID),arg_target);
	}
	
	if (g_database == null) {
		PrintToChatEx(client,DB_INACCESSIBLE_CLIENT);
		return Plugin_Handled;
	}
	
	banresult = BanIdentity(targetAuthID,time,BANFLAG_AUTHID,finalReason);
	if(!banresult)
		PrintToChatEx(client,"\x03[ERROR]\x01 Ban ID failed ! Will ban via database...");
	
	ReplaceString(reason,sizeof(reason),"'","\\'");
	char querry[256];
	FormatEx(querry, sizeof(querry),"UPDATE tf2.player_log SET is_ban = 1, time_unban = %d, number_ban = number_ban + 1, reason = '%s' WHERE networkid = '%s'",dbtime,reason,targetAuthID)
	g_database.Query(QuerryCallback_update,querry,client);
	
	PrintToChatEx(client,"\x03[SUCCESS]\x01 Player was ban and should be kicked !");
	return Plugin_Handled;
}

public Action cmd_Unban(int client, int args) {
	if(args < 1) {
		PrintToChatEx(client,"\x03[ERROR]\x01 : Syntax : advunban <#userid/[networkid]>");
		return Plugin_Handled;
	}
	char targetAuthID[32];
	GetCmdArg(1, targetAuthID, sizeof(targetAuthID));
	
	bool result = RemoveBan(targetAuthID,BANFLAG_AUTHID);
	result ? PrintToChatEx(client,"\x03[SUCCESS]\x01 Player was unbanned !") : PrintToChatEx(client,"\x03[ERROR]\x01 Unban failed ! Will remove ban from database. Check the userid...");
	
	char querry[256];
	FormatEx(querry, sizeof(querry),"UPDATE tf2.player_log SET is_ban = 0, time_unban = NULL WHERE networkid = '%s'",targetAuthID)
	g_database.Query(QuerryCallback_update,querry,client);
	return Plugin_Handled;
}

public Action cmd_Mute(int client, int args) {
	if(args < 1) {
		PrintToChatEx(client,"\x03[ERROR]\x01 : Syntax : advmute \"<#userid/[networkid]>\"");
		return Plugin_Handled;
	}
	
	char arg_target[64];
	GetCmdArg(1, arg_target, sizeof(arg_target));
	bool isuserid = true;
	
	if(StrContains(arg_target,"[") != -1) // array slicing doesn't seem to work 
		isuserid = false;
	
	char targetAuthID[32];
	if(isuserid) {
		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) { // you have parsed networkid
			PrintToChatEx(client,"\x03[ERROR]\x01 Bad userid...");
			return Plugin_Handled;
		}
		GetClientAuthId(target,AuthId_Steam3,targetAuthID,sizeof(targetAuthID),true);
		gb_isMuted[target] = true;
	}
	else {
		bool isfound = false;
		for(int player = 1; player <= MaxClients; player++) // try to find him to kick him
		{
			if(!IsValidClient(player))
				continue;
			
			GetClientAuthId(player,AuthId_Steam3,targetAuthID,sizeof(targetAuthID),true);
			if(strcmp(targetAuthID,arg_target,true) == 0) {
				isfound = true;
				gb_isMuted[player] = true;
				break;
			}
		}
		if(!isfound) // he was gone, just assume you knew his networkid
			FormatEx(targetAuthID,sizeof(targetAuthID),arg_target);
	}
	
	if (g_database == null) {
		PrintToChatEx(client,DB_INACCESSIBLE_CLIENT);
		return Plugin_Handled;
	}
	
	char querry[256];
	FormatEx(querry, sizeof(querry),"UPDATE css.player_log SET is_muted = 1 WHERE networkid = '%s'",targetAuthID)
	g_database.Query(QuerryCallback_update,querry,client);
	
	PrintToChatEx(client,"\x03[SUCCESS]\x01 Player was muted !");
	return Plugin_Handled;
}

public Action cmd_Unmute(int client, int args) {
	if(args < 1) {
		PrintToChatEx(client,"\x03[ERROR]\x01 : Syntax : advunmute \"<#userid/[networkid]>\"");
		return Plugin_Handled;
	}
	if(args < 1) {
		PrintToChatEx(client,"\x03[ERROR]\x01 : Syntax : advmute \"<#userid/[networkid]>\"");
		return Plugin_Handled;
	}
	
	char arg_target[64];
	GetCmdArg(1, arg_target, sizeof(arg_target));
	bool isuserid = true;
	
	if(StrContains(arg_target,"[") != -1) // array slicing doesn't seem to work 
		isuserid = false;
	
	char targetAuthID[32];
	if(isuserid) {
		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) { // you have parsed networkid
			PrintToChatEx(client,"\x03[ERROR]\x01 Bad userid...");
			return Plugin_Handled;
		}
		GetClientAuthId(target,AuthId_Steam3,targetAuthID,sizeof(targetAuthID),true);
		gb_isMuted[target] = false;
	}
	else {
		bool isfound = false;
		for(int player = 1; player <= MaxClients; player++) // try to find him to kick him
		{
			if(!IsValidClient(player))
				continue;
			
			GetClientAuthId(player,AuthId_Steam3,targetAuthID,sizeof(targetAuthID),true);
			if(strcmp(targetAuthID,arg_target,true) == 0) {
				isfound = true;
				gb_isMuted[player] = false;
				break;
			}
		}
		if(!isfound) // he was gone, just assume you knew his networkid
			FormatEx(targetAuthID,sizeof(targetAuthID),arg_target);
	}
	
	if (g_database == null) {
		PrintToChatEx(client,DB_INACCESSIBLE_CLIENT);
		return Plugin_Handled;
	}
	
	char querry[256];
	FormatEx(querry, sizeof(querry),"UPDATE css.player_log SET is_muted = 0 WHERE networkid = '%s'",targetAuthID)
	g_database.Query(QuerryCallback_update,querry,client);
	
	PrintToChatEx(client,"\x03[SUCCESS]\x01 Player was UNmuted !");
	return Plugin_Handled;
}

// ==== Query callbacks ====

public void QuerryCallback_IsMuted(Database hDatabase, DBResultSet results, const char[] sError, int client) {
	if(sError[0]) {
		LogError(DB_ERROR, sError); 
		return; 
	}

	while(results.FetchRow()) { // should be one row
		gb_isMuted[client] = true;
	}
}

public void QuerryCallback_IsBan(Database hDatabase, DBResultSet results, const char[] sError, int client) {
	if(sError[0]) {
		LogError(DB_ERROR, sError); 
		return; 
	}
	
	DBResult status;

	while(results.FetchRow()) { // should be one row
		if(IsClientConnected(client)) {
			int timeend = results.FetchInt(0,status);
			int currentTime = GetTime();
			if(timeend == 0 || currentTime < timeend) {
				char reason[256];
				results.FetchString(1,reason,sizeof(reason)); //networkid
				char timereason[256];
				char finalreason[256];
				int timeleft = (timeend-currentTime)/60;
				if(timeend == 0)
					FormatEx(timereason,sizeof(timereason),"never");
				else {
					FormatEx(timereason,sizeof(timereason),"%d minute(s)",timeleft);
				}
				FormatEx(finalreason,sizeof(finalreason),"Time before unban : %s.\nReason : %s",timereason,reason);
				bool result = BanClient(client,timeleft,BANFLAG_AUTHID,finalreason,finalreason);
				if(!result)
					KickClientEx(client,finalreason);
				return;
			}
			
			// if not, just unban...
			char clientAuthID[32];
			results.FetchString(2,clientAuthID,sizeof(clientAuthID)); //networkid
			
			char querry[256];
			FormatEx(querry, sizeof(querry),"UPDATE tf2.player_log SET is_ban = 0, time_unban = NULL WHERE networkid = '%s'",clientAuthID)
			g_database.Query(QuerryCallback_update,querry,client);
		}	
	}
} 

public void QuerryCallback_update(Database hDatabase, DBResultSet results, const char[] sError, int client) {
	if(sError[0]) {
		LogError("DB Error during UPDATE querry: %s", sError); 
		return; 
	}
} 

// ==== Utils ====

public bool IsValidClient(client) {
	if (client <= 0 || client > MaxClients) 
		return false;
	if (!IsClientInGame(client)) 
		return false;
	if (IsClientSourceTV(client)) 
		return false;
	return true;
}

public void PrintToChatEx(int client, char[] message) {  // client can be server as well as admin
	if(client == 0) {
		PrintToServer(message);
		return;
	}
	PrintToChat(client,message);
}