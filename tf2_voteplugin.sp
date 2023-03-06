#include <sourcemod>
#include <system2>

#define MAX_OPTIONS 128
#define PLAYER_COOLDOWN 160
#define PLAYER_JOIN_COOLDOWN 120
#define VOTE_MAXDURATION 60

#define VOTE_DURATION 20
#define MENU_DURATION 30

#define MIN_CLIENT_DISABLE_COOLDOWN_UNTIL 2

#define DB_INACCESSIBLE "TOMHK VOTE PLUGIN - DB is not connected."
#define DB_INACCESSIBLE_CLIENT "\x03[Vote Plugin]\x01 Sorry, the vote database isn't functionnal."
#define DB_SUCCESS "TOMHK VOTE PLUGIN - Data stored successfully."
#define DB_ERROR "TOMHK VOTE PLUGIN - Error on querry : %s"

#define VOTECOMMAND_NOT_FOUND "\x03[Vote Plugin]\x01 There are no commands for now."

#define VOTE_IN_PROGRESS "\x03[Vote Plugin]\x01 Sorry, a vote is in progress. Please try again."
#define VOTE_FAILED_COOLDOWN "\x03[Vote Plugin]\x01 You can't create a vote now, you need to wait : %d seconds."

#define SERVERHTTPLINK "http://httpsocket.tomhk.fr"

public Plugin myinfo =
{
	name = "Vote Plugin",
	author = "tomhk",
	description = "Universal vote plugin for tomhk.fr servers. Do 'votemenu' in console for showing the menu.",
	version = "1.1.1",
	url = "https://tomhk.fr"
};

int gi_voteCooldowns[MAXPLAYERS +1]; // 1 minute and 1 minute global of wait.
int gi_voteCooldown; // wait 1 minute for every player to vote
int gi_playerAllowToVote; // number of voters in a vote
bool gb_voteInProgress = false;
int gi_playerVotes[MAXPLAYERS +1]; // store players' choice

Database g_database;
Handle g_timerVote; // store the timer before vote ends, we delete it if the vote has already ended.

bool gb_voteTimeStop = false; // stop the ongoing vote
char gc_commandToVote[MAXPLAYERS +1][256]; // 2d array because other players can create votes at the same time.
int gf_voteTimeToApply; // how many time before command execution, it will be converted into a float because it is used by a timer.
int gi_clientVoter; // store globally the client that started a vote.


public void OnPluginStart()
{
	PrintToServer("TOMHK VOTE PLUGIN - Init...");
	
	HookEvent("player_connect",event_ClientConnect);
	HookEvent("player_disconnect",event_ClientDisconnect);
	
	//AddCommandListener(listener_Say, "say");
	//AddCommandListener(listener_Say, "say_team");
	
	RegAdminCmd("votemenu", cmdVoteMenu,0); 
	LoadTranslations("common.phrases.txt"); // Required for FindTarget fail reply
	
	
	// CREATE REPEAT TIMER EACH SECOND TO DECREMENT COOLDOWNS
	CreateTimer(1.0, Timer_DecrementCooldowns, _, TIMER_REPEAT);
	
	Database.Connect(DBConnectCallback, "tf2"); 

	PrintToServer("TOMHK VOTE PLUGIN - Running...");
}

public void DBConnectCallback(Database db, const char[] szError, any data) {
	if (db == null || szError[0]){
		SetFailState("Database cannot connect with error %s.",szError);
		return;
	}
	PrintToServer("TOMHK VOTE PLUGIN - DB connected successfully .");
	g_database = db;
	g_database.SetCharset("utf8");
}

public bool ClientIsAvailableToVote(int client) {
	if (GetRealClientCount() <= MIN_CLIENT_DISABLE_COOLDOWN_UNTIL) 
		return true; // because why waiting when you're almost alone

	if (gi_voteCooldowns[client] > 0 || gi_voteCooldown > 0) {
		PrintToChat(client,VOTE_FAILED_COOLDOWN,gi_voteCooldowns[client]);
		return false;
	}
	return true;
}

public void event_ClientConnect(Event event, const char[] name, bool dontBreadcast) {
	int client = event.GetInt("index") + 1; // why not using get userid ? i don't touch this since it seems it's working
	// connected clients are not allowed to vote if they weren't there before
	gi_voteCooldowns[client] = PLAYER_JOIN_COOLDOWN; // 60 seconds cooldown, this avoid players disconnect and reconnect to make another vote
}

public void event_ClientDisconnect(Event event, const char[] name, bool dontBreadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(gb_voteInProgress) {
		gi_playerVotes[client] = 0; // fixed because if quits and only one to vote while another person is here (like 2 players), vote will pass.
		gi_playerAllowToVote -= 1;
		VoteApply();
	}
}

//========= Vote Scheme ============

/*public Action listener_Say(int client, const char[] command, int args) {

	char arg[256];
	GetCmdArg(1, arg, sizeof(arg));

	if((StrContains(arg,"/votemenu") == -1) && (StrContains(arg,"!votemenu") == -1)){
		return Plugin_Continue;
	}
	
	if (g_database == null) {
		PrintToChat(client,DB_INACCESSIBLE_CLIENT);
		return Plugin_Changed;
	}

	if(gb_voteInProgress) {
		PrintToChat(client,VOTE_IN_PROGRESS);
		return Plugin_Changed;
	}

	if(!ClientIsAvailableToVote(client)) 
		return Plugin_Changed;
	
	char querry[256];
	FormatEx(querry, sizeof(querry),"SELECT command FROM tf2.commands WHERE votecommand = 1 AND is_using = 1");
	g_database.Query(QuerryCallback_BeginnerVote,querry,client);
	return Plugin_Changed;
}*/

public Action cmdVoteMenu(int client, int args) {
	
	if (g_database == null) {
		PrintToChat(client,DB_INACCESSIBLE_CLIENT);
		return Plugin_Continue;
	}

	if(gb_voteInProgress) {
		PrintToChat(client,VOTE_IN_PROGRESS);
		return Plugin_Continue;
	}

	if(!ClientIsAvailableToVote(client)) 
		return Plugin_Continue;

	char querry[256];
	FormatEx(querry, sizeof(querry),"SELECT command FROM tf2.commands WHERE votecommand = 1 AND is_using = 1");
	g_database.Query(QuerryCallback_BeginnerVote,querry,client);
	PrintToConsole(client,"[Vote Plugin] You need to resume the game to access the menu.");
	return Plugin_Handled;
}

public void QuerryCallback_BeginnerVote(Database hDatabase, DBResultSet results, const char[] sError, int client) {
	
	if (!IsClientInGame(client) || IsFakeClient(client)) return;

	if(gb_voteInProgress) {
		PrintToChat(client,VOTE_IN_PROGRESS);
		return;
	}

	if(sError[0]) {
		LogError(DB_ERROR, sError); 
		return; 
	}
	
	DBResult status;
	
	Menu menu = new Menu(Menu_Beginner_Callback);
	menu.SetTitle("Please choose a vote option :");
	
	while(results.FetchRow()) // fetch all commands
	{
		char command[64];
		results.FetchString(0,command,sizeof(command),status);
		menu.AddItem(command,command,ITEMDRAW_DEFAULT);
	}
	menu.Display(client,MENU_DURATION); // amount of time in seconds
}

public int Menu_Beginner_Callback(Menu menu, MenuAction action, int clientVoter, int param2) {
	
	switch(action) {
		case MenuAction_Select: {
			char item[64];
			menu.GetItem(param2,item,sizeof(item));
			if (g_database == null) {
				PrintToChat(clientVoter,DB_INACCESSIBLE_CLIENT);
			}
			else {
				char querry[256];
				FormatEx(querry, sizeof(querry),"SELECT command,argsType,specifications,convar,admin_immunity,dont_check FROM tf2.commands WHERE command = '%s'",item);
				g_database.Query(QuerryCallback_IntermediateVote,querry,clientVoter);
			}
		}
		
		case MenuAction_End: {
			delete menu;
		}
	}
}

public void QuerryCallback_IntermediateVote(Database hDatabase, DBResultSet results, const char[] sError, int client) {
	
	if (!IsClientInGame(client) || IsFakeClient(client)) return;

	if(gb_voteInProgress) {
		PrintToChat(client,VOTE_IN_PROGRESS);
		return;
	}
	
	if(sError[0]) {
		LogError(DB_ERROR, sError); 
		return; 
	}
	
	DBResult status;
	if (!results.FetchRow()) {
		PrintToChat(client,VOTECOMMAND_NOT_FOUND);
		return;
	}
	
	int argsType = results.FetchInt(1,status);
	int dontCheck = results.FetchInt(5,status);
	
	char command[64];
	results.FetchString(0,command,sizeof(command),status); 
	
	FormatEx(gc_commandToVote[client],sizeof(gc_commandToVote[]),"%s",command);
	

	switch(argsType) 
	{
		case 0: { // args is a client name
		
			Menu menu = new Menu(Menu_Intermediate_Callback);
			menu.SetTitle("Please choose a player :");
			char clientName[MAX_NAME_LENGTH];
			int adminImmunity = results.FetchInt(4,status);
			for (int player = 1; player <= MaxClients; player++) 
			{
				if (!IsClientInGame(player) || IsClientReplay(player) || IsFakeClient(player)) 
					continue;
					
				bool drawDisable = client==player;
				if (adminImmunity)
					drawDisable = drawDisable || (GetUserAdmin(player) != INVALID_ADMIN_ID); // we don't want admins to be kicked !
				
				GetClientName(player,clientName,sizeof(clientName));
				char playerIndex[2];
				IntToString(player,playerIndex,sizeof(playerIndex));
				menu.AddItem(playerIndex,clientName, drawDisable ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT); // get player index to ban/kick/mute etc...

			}
			menu.Display(client,MENU_DURATION); 
		}
		case 1 : { //args is a number
		
			Menu menu = new Menu(Menu_Intermediate_Callback);
			menu.SetTitle("Please choose a number :");
			char strMax[11];
			char strMin[5];
			results.FetchString(2,strMax,sizeof(strMax),status); // specifications
			SplitString(strMax,"/",strMin,sizeof(strMin)); // means to minimum at maximum
			ReplaceString(strMax,sizeof(strMax),"/","");
			int max = StringToInt(strMax);
			int min = StringToInt(strMin);
			
			char convar[256];
			char convarFormatted[256];
			results.FetchString(3,convar,sizeof(convar),status);
			FormatEx(convarFormatted,sizeof(convarFormatted),convar,""); // there is a %s in the convar, we need to format it.
			TrimString(convarFormatted); // trim because there might be a space.
			
			int convarInt;
			if(dontCheck == 0){
				ConVar cvCommand = FindConVar(convarFormatted); 
				
				if (cvCommand == null) {
					PrintToConsole(client,"The command was not found.");
					return;
				}
				convarInt = GetConVarInt(cvCommand)
			}
			else
				convarInt = 0x7FFFFFFF; // max int beacuse why making a command above 1000
			
			for (int i = min; i <= max; i++) 
			{
				char display[32];
				IntToString(i,display,sizeof(display));
				menu.AddItem(display,display,i==convarInt ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
			}
			menu.Display(client,MENU_DURATION); 
		}
		case 2 : { //args is a boolean (on/off)
		
			Menu menu = new Menu(Menu_Intermediate_Callback);
			ConVar cvCommand = FindConVar(command);
			if (cvCommand == null) {
				PrintToConsole(client,"The command was not found.");
				return;
			}
			
			bool convarBool =  GetConVarBool(cvCommand);
			menu.SetTitle("Please choose an option :");
			menu.AddItem("on","On",convarBool ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
			menu.AddItem("off","Off",convarBool ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
			menu.Display(client,MENU_DURATION); 
		}
		case 3 : { //args generate a menu to select a string
			Menu menu = new Menu(Menu_Intermediate_Callback);
			if(StrEqual(command,"changemap")) {
				menu.SetTitle("Please choose a map :");
				char path_mapcycle[256];
	
				BuildPath(Path_SM, path_mapcycle, sizeof(path_mapcycle), "../../mapcycle.txt");
				if (!FileExists(path_mapcycle)) return;
				File mapcycle = OpenFile(path_mapcycle,"r");
				
				char mapname[128];
				while (!IsEndOfFile(mapcycle)) 
				{
					ReadFileLine(mapcycle,mapname,sizeof(mapname));
					menu.AddItem(mapname,mapname,ITEMDRAW_DEFAULT);
				}
			}
			menu.Display(client,MENU_DURATION);
		}
		case 4: { // no args, we just need to execute the command.
			char querry[256];
			FormatEx(querry, sizeof(querry),"SELECT specifications,argsType,menutitle,timeapply,convar,'' FROM tf2.commands WHERE command = '%s'",gc_commandToVote[client]); 
			g_database.Query(QuerryCallback_FinalVote,querry,client);
		}
	}
}

public int Menu_Intermediate_Callback(Menu menu, MenuAction action, int clientVoter, int param2) {
	
	switch(action) {
		case MenuAction_Select: {
			char args[32];
			menu.GetItem(param2,args,sizeof(args));
			
			if (g_database == null) {
				PrintToChat(clientVoter,DB_INACCESSIBLE_CLIENT);
			}
			else {
				char querry[256];
				FormatEx(querry, sizeof(querry),"SELECT specifications,argsType,menutitle,timeapply,convar,'%s' FROM tf2.commands WHERE command = '%s'",args,gc_commandToVote[clientVoter]); // HACK : since callbacks are allowed to one value, i'm parsing the args on the querry...
				g_database.Query(QuerryCallback_FinalVote,querry,clientVoter);
			}
		}
		
		case MenuAction_End: {
			delete menu;
		}
	}
}

public void QuerryCallback_FinalVote(Database hDatabase, DBResultSet results, const char[] sError, int client) {

	if (!IsClientInGame(client) || IsFakeClient(client)) return;

	if(gb_voteInProgress) {
		PrintToChat(client,VOTE_IN_PROGRESS);
		return;
	}
	
	if(sError[0]) {
		LogError(DB_ERROR, sError); 
		return; 
	}
	
	DBResult status;
	if (!results.FetchRow()) {
		PrintToChat(client,VOTECOMMAND_NOT_FOUND);
		return;
	}
	
	char convar[256];
	results.FetchString(4,convar,sizeof(convar),status); // convar
	
	char specifications[32];
	results.FetchString(0,specifications,sizeof(specifications),status);
	
	int argsType = results.FetchInt(1,status);
	
	char args[32];
	results.FetchString(5,args,sizeof(args),status);
	
	gi_clientVoter = client;
	
	gb_voteInProgress = true;
	gi_voteCooldowns[client] = PLAYER_COOLDOWN;
	gi_voteCooldown = VOTE_MAXDURATION; 
	
	char voterName[MAX_NAME_LENGTH];
	GetClientName(client,voterName,sizeof(voterName));
	char menuTitle[256];
	char menuTitleFormated[256];
	results.FetchString(2,menuTitle,sizeof(menuTitle),status);
	
	gf_voteTimeToApply = results.FetchInt(3,status);
	
	switch (argsType)
	{
		case 0: {
			int clientTarget = StringToInt(args);
			char targetName[MAX_NAME_LENGTH];
			GetClientName(clientTarget,targetName,sizeof(targetName));
			
			FormatEx(menuTitleFormated,sizeof(menuTitleFormated),menuTitle,voterName,targetName);
			FormatEx(gc_commandToVote[client],sizeof(gc_commandToVote[]),"%s",convar);
			
			if (StrEqual(specifications,"authid")) {
				char clientAuthID[64];
				GetClientAuthId(clientTarget,AuthId_Steam3,clientAuthID,sizeof(clientAuthID),true);
				
				FormatEx(gc_commandToVote[client],sizeof(gc_commandToVote[]),convar,clientAuthID);
				//FormatEx(gc_commandToVote[client],sizeof(gc_commandToVote[]),"%s",clientAuthID);
			} 
			else {
				Format(gc_commandToVote[client],sizeof(gc_commandToVote[]),convar,targetName);
			}
		}
		case 1: {
			if(StrEqual(gc_commandToVote[client],"set_quota_bot_number")) { // HACK FOR RCBOT,QUOTA IS args+ 1!
				FormatEx(menuTitleFormated,sizeof(menuTitleFormated),menuTitle,voterName,args);
				char newArgs[sizeof(args)];
				FormatEx(newArgs,sizeof(newArgs),"%d",StringToInt(args) +1);
				Format(gc_commandToVote[client],sizeof(gc_commandToVote[]),convar,newArgs);

			}
			else {
				FormatEx(menuTitleFormated,sizeof(menuTitleFormated),menuTitle,voterName,args);
				Format(gc_commandToVote[client],sizeof(gc_commandToVote[]),convar,args);
			}
		}
		case 2: {
			FormatEx(menuTitleFormated,sizeof(menuTitleFormated),menuTitle,voterName,args);
			FormatEx(gc_commandToVote[client],sizeof(gc_commandToVote[]),"%s",convar);

			if (StrEqual(args,"on") )
				FormatEx(gc_commandToVote[client],sizeof(gc_commandToVote[]),convar,"1");
			else 
				FormatEx(gc_commandToVote[client],sizeof(gc_commandToVote[]),convar,"0");
		}
		default: {
			FormatEx(menuTitleFormated,sizeof(menuTitleFormated),menuTitle,voterName,args);
			Format(gc_commandToVote[client],sizeof(gc_commandToVote[]),convar,args);
		}
	}
	
	//PrintToServer("here we go !");
	for (int player = 1; player <= MaxClients; player++) 
	{
		if (!IsClientInGame(player) || IsFakeClient(player) || IsClientReplay(player)) continue;
		
		Menu menu = new Menu(Menu_GlobalVote_Callback);
		gi_playerAllowToVote += 1;
		
		menu.SetTitle(menuTitleFormated);
		menu.AddItem("yes","Yes",ITEMDRAW_DEFAULT);
		menu.AddItem("no","No", ITEMDRAW_DEFAULT);
		menu.Display(player,30); // amoint of time in seconds
	}
	g_timerVote = CreateTimer(30.0, Timer_VoteTimer);
	PrintToChatAll("\x04[Vote Plugin]\x01 A vote started. %d players are allowed to vote.",gi_playerAllowToVote);	
}

public int Menu_GlobalVote_Callback(Menu menu, MenuAction action, int clientVoter, int param2) {
	
	switch(action) {
		case MenuAction_Select: { 
			if(!gb_voteInProgress) return; // that means the vote has already passed
			char item[32];
			menu.GetItem(param2,item,sizeof(item));
			if(StrEqual(item,"yes")) {
				gi_playerVotes[clientVoter] = 1;
			}
			else if (StrEqual(item,"no")) {
				gi_playerVotes[clientVoter] = 2;
			}
			VoteApply();
		}
		case MenuAction_End: {
			delete menu;
		}
	}
}

public void VoteApply(){

	if(!gb_voteInProgress) return;
	
	int numberOfTrue;
	int numberOfFalse;
	for (int i = 1; i <= MaxClients; i++)
	{
		if(gi_playerVotes[i] == 1)
			numberOfTrue++;
		else if (gi_playerVotes[i] == 2) 
			numberOfFalse++;
	}
	
	int votesLeft = gi_playerAllowToVote - (numberOfTrue + numberOfFalse);
	float dividedVoters = float(gi_playerAllowToVote)/float(2); // without float conversion, it wasn't working, fixed july 2022 : error reported since march 2022
	
	if ( gi_playerAllowToVote-numberOfTrue < dividedVoters || gi_playerAllowToVote-numberOfFalse < dividedVoters || votesLeft == 0) {
		gb_voteTimeStop = true;
	}
		
	if(!gb_voteTimeStop) {
		PrintToChatAll("\x04[Vote Plugin]\x01 A new vote has been registered : %d player(s) for \x04YES\x01, %d player(s) for \x03NO\x01, %d vote(s) left.",numberOfTrue,numberOfFalse,votesLeft,gi_playerAllowToVote);
		return;
	}
	
	// Democracy time
	
	if (numberOfTrue <= numberOfFalse) {// "no" majority or equality
		PrintToChatAll("\x04[Vote Plugin]\x01 Vote \x03FAILED\x01, %d player(s) voted \x04YES\x01, %d player(s) voted \x03NO\x01 (%d abstention(s))",numberOfTrue,numberOfFalse,votesLeft);
	}
	else {
		PrintToChatAll("\x04[Vote Plugin]\x01 Vote \x04PASSED\x01, %d player(s) voted \x04YES\x01, %d player(s) voted \x03NO\x01 (%d abstention(s)).",numberOfTrue,numberOfFalse,votesLeft);
		if (gf_voteTimeToApply > 2) 
			PrintToChatAll("\x04[Vote Plugin]\x01 The vote will be applied in %d seconds.",gf_voteTimeToApply);
		CreateTimer(float(gf_voteTimeToApply), Async_ApplyCommand);
	}
	
	
	// Create cooldowns and reset vote parameters
	delete g_timerVote; // delete timer because it can close other votes  
	
	char request[512];
	
	char voterName[MAX_NAME_LENGTH];
	GetClientName(gi_clientVoter,voterName,sizeof(voterName));
	
	char clientAuthID[32];
	GetClientAuthId(gi_clientVoter,AuthId_Steam3,clientAuthID,sizeof(clientAuthID),true);
	
	FormatEx(request,sizeof(request),"SOCKETMANAGER|ADMIN|TF2 Vote|Vote occured about '%s' by : %s (Networkid : %s) : Yes : %d ; No : %d (Numbers of voters : %d)",gc_commandToVote[gi_clientVoter],voterName,clientAuthID,numberOfTrue,numberOfFalse,gi_playerAllowToVote);
	
	System2HTTPRequest httpRequest = new System2HTTPRequest(HttpResponseCallback, SERVERHTTPLINK);
	httpRequest.SetData(request);
	httpRequest.POST();
	delete httpRequest;
	
	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		gi_playerVotes[i] = 0;
	}
	gb_voteTimeStop = false;
	gb_voteInProgress = false;
	gi_playerAllowToVote = 0
	
}

public Action Async_ApplyCommand(Handle timer) {
	PrintToServer("[Vote Plugin] Voted Command : %s", gc_commandToVote[gi_clientVoter]),
	ServerCommand(gc_commandToVote[gi_clientVoter]);
	gi_clientVoter = 0;

	return Plugin_Handled;
}

//========= Action Repeat Timers =========

public Action Timer_DecrementCooldowns(Handle timer) {

	for (int player = 1 ;player <= MaxClients; player++) // entity 0 is server
	{
		gi_voteCooldowns[player] = max(0,gi_voteCooldowns[player] - 1);
		gi_voteCooldown = max(0,gi_voteCooldown - 1);
	}	
	return Plugin_Handled;
}

public Action Timer_VoteTimer(Handle timer, int client) {
	gb_voteTimeStop = true;
	VoteApply();
	return Plugin_Handled;
}

//========= Utility Functions =========

public int min(int a, int b) {
	return a < b ? a : b; 
}

public int max(int a, int b) {
	return a > b ? a : b; 
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