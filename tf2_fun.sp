#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>
#include <sdkhooks>

#define PLAYER_FOUND "\x03[SUCCESS]\x01 Player %s was found !"
#define EXTERNAL_COMMAND "\x0732CD32[EXTERNAL]\x01 The execution of this command was made by admin."
#define TARGET_NOT_FOUND "\x03[ERROR]\x01 Target is invalid, try using names instead of userids..."

#define BUFF_CHANCE_TO_BE_KILLED 4

#define WALLHACK_MAX_DURATION 600
#define EF_BONEMERGE (1 << 0)


public Plugin myinfo =
{
	name = "Fun Plugin",
	author = "tomhk",
	description = "Special TF2 fun plugin for some fun commands.",
	version = "1.6",
	url = "https://www.tomhk.fr"
};

ConVar gcvar_allowthirdperson = null;
ConVar gcvar_allowrobot = null;
bool gb_hasThirdperson[MAXPLAYERS+1] = false;
bool gb_isJournalist[MAXPLAYERS+1] = false;
bool gb_isRobot[MAXPLAYERS+1] = false;
bool gb_isBuffPlayer[MAXPLAYERS +1] = false;
int gi_isNerfedPlayer[MAXPLAYERS +1] = 0;
bool gb_hasWallhack[MAXPLAYERS +1] = false;
float gf_Speeds[MAXPLAYERS+1] = 0.0;

gi_wallhackModelIndexes[MAXPLAYERS +1] = INVALID_ENT_REFERENCE;
gi_wallhackGlowIndexes[MAXPLAYERS +1] = INVALID_ENT_REFERENCE;

int gi_OffsetCollisions;
int gi_OffsetCloak;
int gi_OffsetAmmo;
int gi_OffsetClip;

int gi_wallhackers = 0;
//int gi_speeders = 0;
//int gi_journalists = 0;

//int gi_laserModel;
//int g_BeamSprite;
//int g_HaloSprite;

Handle gh_journalistCloackRecover;
Handle gh_speedRecovery; // since maxspeed can be altered by some unkown forces...
//Handle gh_wallhackUpdate; 

public void OnPluginStart()
{
	PrintToServer("TOMHK FUN PLUGIN - Init...");
	
	HookEvent("player_disconnect",event_PlayerDisconnect);
	HookEvent("player_death",event_PlayerDeath);
	HookEvent("player_class",event_ChangeClass); 
	HookEvent("player_changeclass",event_ChangeClass); 
	HookEvent("player_team",event_ChangeClass); // Prettry much the same thing, don't need to redo a function for this.
	
	HookEvent("player_builtobject",event_ObjectCreated);
	HookEvent("object_destroyed",event_ObjectDestroyed);

	AddNormalSoundHook(SoundHook);
	
	gi_OffsetCollisions = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	gi_OffsetCloak = FindSendPropInfo("CTFPlayer", "m_flCloakMeter");
	gi_OffsetAmmo = FindSendPropInfo("CBasePlayer", "m_iAmmo");
	gi_OffsetClip = FindSendPropInfo("CBaseCombatWeapon", "m_iClip1");
	if (gi_OffsetCollisions == -1)
		PrintToServer("TOMHK FUN ERROR : Offset CBaseEntity::m_CollisionGroup DOESN'T EXIST.");
	if (gi_OffsetCloak == -1)
		PrintToServer("TOMHK FUN ERROR : Offset CTFPlayer::m_flCloakMeter DOESN'T EXIST.");
	if (gi_OffsetAmmo == -1)
		PrintToServer("TOMHK FUN ERROR : Offset CBasePlayer::m_iAmmo DOESN'T EXIST.");
	if (gi_OffsetClip == -1)
		PrintToServer("TOMHK FUN ERROR : Offset CBaseCombatWeapon::m_iClip1 DOESN'T EXIST.");
	
	RegConsoleCmd("rtd",cmd_RTD,"Will warn you that it doesn't exist.");
	RegConsoleCmd("tp",cmd_Thirdperson,"Toggle thirdperson, please vote mp_allowthirdperson before.");
	//RegConsoleCmd("tp2",cmd_ThirdpersonMedieval,"Toggle thirdperson but anotehr angle, please vote mp_allowthirdperson before.");
	RegConsoleCmd("fp",cmd_Firstperson,"Toggle firstperson (because you were in thirdperson...)");
	RegConsoleCmd("civ",cmd_Civilian,"Become reference pose / t-pose / civilian. You should normally don't shoot.");
	RegConsoleCmd("robot",cmd_Robot,"Become a robot from the future.");
	RegAdminCmd("nclip",cmd_Noclip,ADMFLAG_CHEATS,"Noclip without cheats and makes it silent.");
	RegAdminCmd("deus",cmd_Deus,ADMFLAG_CHEATS,"Godmode without cheats and makes it silent.");
	RegAdminCmd("uldeus",cmd_ULDeus,ADMFLAG_CHEATS,"Godmode and no push without cheats and makes it silent.");
	RegAdminCmd("gravity",cmd_Gravity,ADMFLAG_CHEATS,"Set gravity at first argument, it's also silent.");
	RegAdminCmd("speed",cmd_Speed,ADMFLAG_CHEATS,"Set speed at first argument, it's also silent.");
	RegAdminCmd("sethealth",cmd_Health,ADMFLAG_CHEATS,"Set heatlh.");
	RegAdminCmd("ammo",cmd_Ammo,ADMFLAG_CHEATS,"Set ammo.");
	RegAdminCmd("regen",cmd_Regen,ADMFLAG_CHEATS,"Regen all stats (not health).");
	RegAdminCmd("buff",cmd_BuffPlayer,ADMFLAG_CHEATS,"Makes you harder to kill.");
	RegAdminCmd("nerf",cmd_NerfPlayer,ADMFLAG_CHEATS,"Nerf enemy, no damage except to himself."); 
	RegAdminCmd("wallhack",cmd_WallHack,ADMFLAG_CHEATS,"Server-sided ESP that shows a glow of players. IT'S GLITCHY AND RESOURCE INTENSIVE DONT USE IT.");
	RegAdminCmd("journalist",cmd_Journalist,ADMFLAG_CHEATS,"Journalist will let you be forever invisible + (don't bump to enemies = impossible). You will however take damage.");
	
	gcvar_allowthirdperson = CreateConVar("mp_allowthirdperson", "1", "Allow third person.");
	gcvar_allowrobot = CreateConVar("mp_allowrobotmodel", "1", "Allow people to have a robot player model.");
	
	CreateTimer(2.0,Timer_UpdateRandomSeed,_,TIMER_REPEAT); // The footstep sounds of robots souns bad, having a timer makes it sound better.
	
	precaching();
	LoadTranslations("common.phrases");
	
	PrintToServer("TOMHK FUN PLUGIN - Running...");
}

public void OnConfigsExecuted() { // DEAR LORD DO NOT USE OnMapStart THIS IS A TRAP DO NOT USE IT !!!
	precaching();
}

// ==== Event Forwards

public void event_PlayerDisconnect(Event event, const char[] name, bool dontBreadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if ( event.GetInt("bot") < 1 )  {
		gb_hasThirdperson[client] = false;
		gb_isJournalist[client] = false;
		gb_isRobot[client] = false;
		gf_Speeds[client] = 0.0;
		if(gb_hasWallhack[client]) {
			gi_wallhackers -= 1;
			gb_hasWallhack[client] = false;
			RemoveAllSkin();
			//SDKUnhook(gi_wallhackModelIndexes[client], SDKHook_SetTransmit,OnSetTransmit);
			//SDKUnhook(gi_wallhackGlowIndexes[client], SDKHook_SetTransmit,OnSetTransmit);
		}
		if(gb_isBuffPlayer[client]) {
			gb_isBuffPlayer[client] = false;
			SDKUnhook(client, SDKHook_OnTakeDamage, hook_ClientHurtBuff);
		}
	}
	if(gi_isNerfedPlayer[client] > 0) {
		gi_isNerfedPlayer[client] = 0;
		SDKUnhook(client, SDKHook_TraceAttack, hook_ClientNerf)
		SDKUnhook(client, SDKHook_OnTakeDamage, hook_ClientNerfTakeDamage);
	}
}

public void event_PlayerDeath(Event event, const char[] name, bool dontBreadcast) {
	if ( event.GetInt("bot") == 1 )  
		return;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(GetClientHealth(client) >= 1) // dead ringer for example BUT CANT FUCKING IsPlayerAlive WORK CORRECTLY, isalive is true when dead...
		return; 
	gb_hasThirdperson[client] = false;
	gf_Speeds[client] = 0.0;
	if(gb_isJournalist[client]) {
		SetEntityRenderMode(client,RENDER_NORMAL);
		setRenderWearable(client,RENDER_NORMAL);
	}
	gb_isJournalist[client] = false;
	if(gb_isRobot[client])
		PrintToChat(client,"\x03[INFO]\x01 You are STILL a robot.");
}

public void event_ChangeClass(Event event, const char[] name, bool dontBreadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if ( event.GetInt("bot") < 1 )  {
		gb_hasThirdperson[client] = false;
		gb_isJournalist[client] = false;
		gf_Speeds[client] = 0.0;
		if(gb_isRobot[client])
			PrintToChat(client,"\x03[INFO]\x01 You are NO LONGER a robot.");
		gb_isRobot[client] = false;
	}
	if(gi_isNerfedPlayer[client] == 0) { // means no yet went to server
		SDKHook(client, SDKHook_TraceAttack, hook_ClientNerf);
		SDKHook(client, SDKHook_OnTakeDamage, hook_ClientNerfTakeDamage);
		gi_isNerfedPlayer[client] = 1;
	}
}

public void event_ObjectCreated(Event event, const char[] name, bool dontBreadcast) {
	int clientobject = event.GetInt("index");
	if(clientobject <= 1)
		return;
	
	SDKHook(clientobject, SDKHook_TraceAttack, hook_ClientNerf);
	SDKHook(clientobject, SDKHook_OnTakeDamage, hook_ClientNerfTakeDamage);
}

public void event_ObjectDestroyed(Event event, const char[] name, bool dontBreadcast) {
	int clientobject = event.GetInt("index");
	if(clientobject <= 1)
		return;
	SDKUnhook(clientobject, SDKHook_TraceAttack, hook_ClientNerf);
	SDKUnhook(clientobject, SDKHook_OnTakeDamage, hook_ClientNerfTakeDamage);
}

// === Hooks 

public Action hook_ClientHurtBuff(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3]) {
	if(victim == attacker)
		return Plugin_Continue;
		
	if(!gb_isBuffPlayer[victim]) 
		return Plugin_Continue;
	
	int maxHealth = GetEntProp(victim,Prop_Data,"m_iMaxHealth",2,0);
	int health = GetEntProp(victim, Prop_Data, "m_iHealth", 2, 0);
	
	if(maxHealth <= damage*0.85 || health == 1)
		return Plugin_Continue; // you're dead, if not that would be suspicious
		
	if(damagetype & DMG_CRIT || damagetype & DMG_BURN) { // critDMG_FALL 
		PrintToConsole(victim,"Sorry for the crit/after burn !!");
		return Plugin_Continue;
	}
	
	switch(weapon) {
		case 14: { // sniper rifle
			return Plugin_Continue;
		}
	}
	
	//if(health - damage < 0) { // mmhhh we're susposed to be dead, let's change it !!
	int rand = GetRandomInt(0,BUFF_CHANCE_TO_BE_KILLED);	
	if(rand < 1)
		return Plugin_Changed; // ok we lost
	if(rand <= BUFF_CHANCE_TO_BE_KILLED/2.3) {
		damage = damage/4.0;
		PrintToConsole(victim,"2.0 chance ! : %.2f (rnd : %d)",damage,rand);
		return Plugin_Changed;
	}
	if (rand < BUFF_CHANCE_TO_BE_KILLED/1.2) {
		float newdamage = damage*1.2 - float(health)+ 10.0;
		if(newdamage < 0)
			damage = damage*0.3;
		else
			damage = newdamage;
		PrintToConsole(victim,"1.5 chance !! : %.2f (rnd : %d)",damage,rand);
		return Plugin_Changed;
	}
	damage = maxHealth * 0.11;
	PrintToConsole(victim,"NO DAMAGE !!!!! : %.2f (rnd : %d)",damage,rand);
	return Plugin_Changed;
	
}

/*public Action hook_ClientNerf(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3]) {
	if(gi_isNerfedPlayer[attacker] < 2) // so not nerfed and not connected
		return Plugin_Continue;
		
	if(victim == attacker)
		return Plugin_Continue;
		
	damage = 0.0;
	return Plugin_Changed;
}*/

public Action hook_ClientNerf(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup) {
	if(!IsValidClient(attacker))
		return Plugin_Continue;
		
	if(gi_isNerfedPlayer[attacker] < 2) // so not nerfed and not connected
		return Plugin_Continue;
		
	if(victim == attacker)
		return Plugin_Continue;
		
	damage = 0.0;
	return Plugin_Changed;
}

public Action hook_ClientNerfTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3]) {

	if(!IsValidClient(attacker))
		return Plugin_Continue;
		
	if(gi_isNerfedPlayer[attacker] < 2) // so not nerfed and not connected
		return Plugin_Continue;
		
	if(victim == attacker)
		return Plugin_Continue;
		
	damage = 0.0;
	return Plugin_Changed;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if(gi_isNerfedPlayer[client] != 2 || !IsValidClient(client)) 
		return Plugin_Continue;
	
	/*if(buttons & IN_ATTACK2) 
		buttons &= ~IN_ATTACK2;

	else if(buttons & IN_ATTACK) 
		buttons &= ~IN_ATTACK;
		
	return Plugin_Changed;*/
	
	
	int clientWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(clientWeapon < 0)
		return Plugin_Continue;
	
	char weaponClassName[MAX_NAME_LENGTH];
	GetEntityClassname(clientWeapon,weaponClassName,sizeof(weaponClassName));
	
	if(	strcmp(weaponClassName,"tf_weapon_flamethrower",true) == 0 // no airblast
		|| strcmp(weaponClassName,"tf_weapon_handgun_scout_primary",true) == 0) { // no scout pushing
		if(buttons & IN_ATTACK2) {
			buttons &= ~IN_ATTACK2;
			return Plugin_Changed;
        }
	}
	
	if(	strcmp(weaponClassName,"tf_weapon_jar",true) == 0 || strcmp(weaponClassName,"tf_weapon_jar_gas",true) == 0 || strcmp(weaponClassName,"tf_weapon_jar_milk",true) == 0 || strcmp(weaponClassName,"tf_weapon_sapper",true) == 0 || (strcmp(weaponClassName,"tf_weapon_builder",true) == 0 && TF2_GetPlayerClass(client) == TFClass_Spy)) {
		if(buttons & IN_ATTACK) {
			buttons &= ~IN_ATTACK;
			return Plugin_Changed;
		}
	}
    
	return Plugin_Continue;
    /*switch(weapon) {
        case 21, 40, 208, 215,741: // https://wiki.alliedmods.net/Team_fortress_2_item_definition_indexes#Primary_.5BSlot_0.5D_3

    }*/
}

public Action OnSetTransmit(int entity, int client) {
	if(gb_hasWallhack[client])
		return Plugin_Continue;
	return Plugin_Handled; 	
}

// ==== COMMANDS

public Action cmd_RTD(int client, int args) {
	PrintToChat(client,"\x03[ERROR]\x01 This server doesn't support RTD.");
	return Plugin_Handled;
}

public Action cmd_Thirdperson(int client, int args) {

	if(!GetConVarBool(gcvar_allowthirdperson) && (GetUserAdmin(client) == INVALID_ADMIN_ID)) {
		PrintToChat(client,"\x03[ERROR]\x01 You don't have the permission, please vote (saying in chat !votemenu) for mp_allowthirdperson to enable thirdperson.");
		return Plugin_Handled;
	}
	
	if(IsPlayerAlive(client)) {
		SetVariantInt(gb_hasThirdperson[client] ? 0 : 1);
		AcceptEntityInput(client, "SetForcedTauntCam");
		gb_hasThirdperson[client] = !gb_hasThirdperson[client]; // toggle values
		PrintToChat(client,gb_hasThirdperson[client] ? "\x03[SUCCESS]\x01 You're now in thirdperson. Note that you can toggle it by saying again tp." : "\x03[SUCCESS]\x01 You're now in firstperson.");
	}
	return Plugin_Handled;
}

public Action cmd_ThirdpersonMedieval(int client, int args) { // no way of doing this since it's all clientside

	if(!GetConVarBool(gcvar_allowthirdperson) && (GetUserAdmin(client) == INVALID_ADMIN_ID)) {
		PrintToChat(client,"\x03[ERROR]\x01 You don't have the permission, please vote (saying in chat !votemenu) for mp_allowthirdperson to enable thirdperson.");
		return Plugin_Handled;
	}
	
	if(IsPlayerAlive(client)) {
		SetVariantInt(gb_hasThirdperson[client] ? 0 : 1);
		AcceptEntityInput(client, "SetForcedTauntCam");
		gb_hasThirdperson[client] = !gb_hasThirdperson[client]; // toggle values
		PrintToChat(client,gb_hasThirdperson[client] ? "\x03[SUCCESS]\x01 You're now in thirdperson. Note that you can toggle it by saying again tp." : "\x03[SUCCESS]\x01 You're now in firstperson.");
	}
	return Plugin_Handled;
}

public Action cmd_Firstperson(int client, int args) {
	SetVariantInt(0);
	AcceptEntityInput(client, "SetForcedTauntCam");
	PrintToChat(client,"\x03[SUCCESS]\x01 You're now in firstperson.");
	return Plugin_Handled;
}

public Action cmd_Civilian(int client, int args) {	
	SetEntProp(client, Prop_Send, "m_hActiveWeapon", -1);
	PrintToChat(client,"\x03[SUCCESS]\x01 You're now a civilian ! Select a weapon to cancel it.");
	return Plugin_Handled;
}

public Action cmd_Robot(int client, int args) {
	if(!GetConVarBool(gcvar_allowrobot) && (GetUserAdmin(client) == INVALID_ADMIN_ID)) {
		PrintToChat(client,"\x03[ERROR]\x01 You don't have the permission, please vote (saying in chat !votemenu) for mp_allowrobotmodel to enable robot models.");
		return Plugin_Handled;
	}
	
	if (!gb_isRobot[client]) {
		char classname[10];
		switch (TF2_GetPlayerClass(client)) 
		{
			case TFClass_Scout:
				Format(classname,sizeof(classname),"scout");
			case TFClass_Soldier:
				Format(classname,sizeof(classname),"soldier");
			case TFClass_Pyro:
				Format(classname,sizeof(classname),"pyro");
			case TFClass_DemoMan:
				Format(classname,sizeof(classname),"demo");
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
		
		char mdlPath[PLATFORM_MAX_PATH];
		Format(mdlPath, sizeof(mdlPath), "models/bots/%s/bot_%s.mdl", classname, classname);
		SetVariantString(mdlPath);
		AcceptEntityInput(client, "SetCustomModel");
		SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
		SetEntProp(client,Prop_Data,"m_bloodColor",3); // tech blood
		setRenderWearable(client, RENDER_NONE);
		PrintToChat(client,"\x03[SUCCESS]\x01 You are now a ROBOT from the future, say the command again to toggle it !");
		
		gb_isRobot[client] = true;
	}
	else {
	
		SetVariantString("");
		AcceptEntityInput(client, "SetCustomModel");
		setRenderWearable(client, RENDER_NORMAL);
		SetEntProp(client,Prop_Data,"m_bloodColor",1); // human blood
		PrintToChat(client,"\x03[SUCCESS]\x01 You are now a HUMAN !");
		gb_isRobot[client] = false;
	}
	return Plugin_Handled;
}

// ADMIN COMMANDS

public Action cmd_Noclip(int client, int args) {
	if (args > 0) {
		char arg_target[64];
		GetCmdArg(1, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	if (GetEntProp(client, Prop_Send, "movetype", 1) == 8) {
		SetEntProp(client, Prop_Send, "movetype", 2, 1);
		PrintToChat(client,"\x03[SUCCESS]\x01 Noclip OFF !");
	}
	else {
		SetEntProp(client, Prop_Send, "movetype", 8, 1);
		PrintToChat(client,"\x03[SUCCESS]\x01 Noclip ON !");
	}
	return Plugin_Handled;
}

public Action cmd_Deus(int client, int args) {
	if (args > 0) {
		char arg_target[64];
		GetCmdArg(1, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	if(GetEntProp(client,Prop_Data, "m_takedamage") == 2) {
		SetEntProp(client, Prop_Data, "m_takedamage", 1, 1);
		PrintToChat(client,"\x03[SUCCESS]\x01 You ARE deus now.");
	}
	else {
		SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
		PrintToChat(client,"\x03[SUCCESS]\x01 You are NOT deus anymore.");
	}
	return Plugin_Handled;
}

public Action cmd_ULDeus(int client, int args) {
	if (args > 0) {
		char arg_target[64];
		GetCmdArg(1, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	if(GetEntProp(client,Prop_Data, "m_takedamage") == 2) {
		SetEntProp(client, Prop_Data, "m_takedamage", 0, 1);
		PrintToChat(client,"\x03[SUCCESS]\x01 You ARE ULTIMATE deus now.");
	}
	else {
		SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
		PrintToChat(client,"\x03[SUCCESS]\x01 You are NOT ULTIMATE deus anymore.");
	}
	return Plugin_Handled;
}

public Action cmd_Journalist(int client, int args) {
	if (args > 0) {
		char arg_target[64];
		GetCmdArg(1, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	if(IsPlayerAlive(client)) {
		if(TF2_GetPlayerClass(client) != TFClass_Spy) {
			PrintToChat(client,"\x03[ERROR]\x01 You must be spy.");
			return Plugin_Handled;
		}
		
		if (gi_OffsetCollisions != -1 && gi_OffsetCloak != 1) {
			SetEntData(client, gi_OffsetCollisions, 0, 4, true);
			gb_isJournalist[client] = true;
			SetEntityRenderMode(client,RENDER_NONE);			
			setRenderWearable(client,RENDER_NONE);
			int weaponIndex;
			for (int weaponSlot = 0; weaponSlot < 4; weaponSlot++) {
				weaponIndex = GetPlayerWeaponSlot(client, weaponSlot);
				if (weaponSlot == 2) {
					SetEntityRenderMode(weaponIndex,RENDER_NONE);
					continue;
				}
				RemoveEdict(weaponIndex);
			}
		}
		
		if (gh_journalistCloackRecover == INVALID_HANDLE) {
			gh_journalistCloackRecover = CreateTimer(1.0,Timer_JournalistCloak, _, TIMER_REPEAT);
		}
		PrintToChat(client,"\x03[SUCCESS]\x01 You are a journalist now.");
	}
	return Plugin_Handled;
}

public Action cmd_Gravity(int client, int args) {

	if (args < 1) { // Necessary args
		ReplyToCommand(client, "\x03[ERROR]\x01 : Syntax : gravity <float:value> ? <#userid|name> ");
		return Plugin_Handled;
	}
	
	char arg1[64]; // GetCmdArgFloat doesn't work.
	GetCmdArg(1,arg1,sizeof(arg1));
	float gravity = StringToFloat(arg1);
	
	if (args == 2) {
		char arg_target[64];
		GetCmdArg(2, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	PrintToChat(client,"\x03[SUCCESS]\x01 Gravity is modified to %.2f.",gravity);
	SetEntityGravity(client,gravity);
	return Plugin_Handled;
}

public Action cmd_Speed(int client, int args) {

	if (args < 1) { // Necessary args
		ReplyToCommand(client, "\x03[ERROR]\x01 Syntax : speed <float:value> ? <#userid|name> ");
		return Plugin_Handled;
	}
	
	char arg1[64]; // GetCmdArgFloat doesn't work.
	GetCmdArg(1,arg1,sizeof(arg1));
	float speed = StringToFloat(arg1);
	
	if (args == 2) {
		char arg_target[64];
		GetCmdArg(2, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	gf_Speeds[client] = speed;
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", speed);
	if (gh_speedRecovery == INVALID_HANDLE) {
		gh_speedRecovery = CreateTimer(0.1,Timer_Speed, _, TIMER_REPEAT);
	}
	
	PrintToChat(client,"\x03[SUCCESS]\x01 Speed is modified to %.2f.",speed);
	return Plugin_Handled;
}

public Action cmd_BuffPlayer(int client, int args) {
	if (args > 0) {
		char arg_target[64];
		GetCmdArg(1, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	gb_isBuffPlayer[client] = !gb_isBuffPlayer[client]; // toggle
	PrintToChat(client,gb_isBuffPlayer[client] ? "\x03[SUCCESS]\x01 You're now Buffed ! (Killing you is harder, try it...)" : "\x03[SUCCESS]\x01 You are NO LONGER buffed.");
	gb_isBuffPlayer[client] ? SDKHook(client,SDKHook_OnTakeDamage,hook_ClientHurtBuff) : SDKUnhook(client,SDKHook_OnTakeDamage,hook_ClientHurtBuff);
	return Plugin_Handled;
}

public Action cmd_NerfPlayer(int client, int args) {
	if (args > 0) {
		char arg_target[64];
		GetCmdArg(1, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		client = target;
	}
	
	gi_isNerfedPlayer[client] = gi_isNerfedPlayer[client] == 1 ?  2 : 1; // 2 => is nerfed, 1 => is not nerfe, 0 => not connected to server so not hooked
	
	char clientName[MAX_NAME_LENGTH];
	GetClientName(client,clientName,sizeof(clientName));
	
	gi_isNerfedPlayer[client] == 2 ? PrintToConsoleAll("%s is nerfed, this person won't do any damage !",clientName) : PrintToConsoleAll("%s is NO MORE nerfed !",clientName);
	//PrintToChat(client,gi_isNerfedPlayer[client] ? "\x03[SUCCESS]\x01 You're now nerfed !" : "\x03[SUCCESS]\x01 You are NO LONGER nerfed.");
	//gi_isNerfedPlayer[client] ? SDKHook(client,SDKHook_OnTakeDamage,hook_ClientHurtBuff) : SDKUnhook(client,SDKHook_OnTakeDamage,hook_ClientHurtBuff);
	return Plugin_Handled;
}

public Action cmd_WallHack(int client, int args) {

// first i thought of m_bClientSideGlowEnabled but it's client-side, means we need a hack the client code and impossible via the server and it would vac ban if they have a mode for it on the client.
// i use code from the sourcemod beacon instead but only render clientside with SDKHook_SetTransmit only to specific clients.

	if (args > 0) {
		char arg_target[64];
		GetCmdArg(1, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	gb_hasWallhack[client] = !gb_hasWallhack[client]; // toggle
	
	if(gb_hasWallhack[client]) {
		for(int player = 1; player < MaxClients; player++) 
		{
			if(player==client)
				continue;
			if(!IsClientInGame(player))
				continue;

			CreatePlayerModelProp(player,client);		
		}
	}
	else { // remove the glows and all the effects
		RemoveAllSkin();
		//SDKUnhook(gi_wallhackModelIndexes[client], SDKHook_SetTransmit,OnSetTransmit);
		//SDKUnhook(gi_wallhackGlowIndexes[client], SDKHook_SetTransmit,OnSetTransmit);
	}
	
	PrintToChat(client,gb_hasWallhack[client] ? "\x03[SUCCESS]\x01 You're now wallhacking !" : "\x03[SUCCESS]\x01 You are NO LONGER wallhacking.");
	gi_wallhackers = gb_hasWallhack[client] ? gi_wallhackers + 1 : gi_wallhackers - 1;
	/*
	if (gh_wallhackUpdate == INVALID_HANDLE) {
		gh_wallhackUpdate = CreateTimer(0.1,Timer_WallHack, client, TIMER_REPEAT);
	} 
	*/
	return Plugin_Handled;
}

public Action cmd_Health(int client, int args) {
	if (args < 1) { // Necessary args
		ReplyToCommand(client, "\x03[ERROR]\x01 Syntax : sethealth <int:value> ? <#userid|name> ");
		return Plugin_Handled;
	}
	
	if (args == 2) {
		char arg_target[64];
		GetCmdArg(2, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	char arg1[64]; // GetCmdArgFloat doesn't work.
	GetCmdArg(1,arg1,sizeof(arg1));
	int health = StringToInt(arg1);
	SetEntityHealth(client,health);
	return Plugin_Handled;
}

public Action cmd_Ammo(int client, int args) {
	if (args < 1) { // Necessary args
		ReplyToCommand(client, "\x03[ERROR]\x01 Syntax : setammo <int:value> ? <#userid|name> ");
		return Plugin_Handled;
	}
	
	if (args == 2) {
		char arg_target[64];
		GetCmdArg(2, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	char arg1[64]; // GetCmdArgFloat doesn't work.
	GetCmdArg(1,arg1,sizeof(arg1));
	int ammoAmmount = StringToInt(arg1);
	
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(!IsValidEntity(weapon)) {
		PrintToChat(client,"\x03[ERROR]\x01 You have an invalid weapon !");
		return Plugin_Handled;
	}
	
	int ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType")*4;
	SetEntData(weapon, gi_OffsetClip, ammoAmmount, 4, true);
	SetEntData(client, ammotype+gi_OffsetAmmo, ammoAmmount, 4, true);
	return Plugin_Handled;
}

public Action cmd_Regen(int client, int args) {
	if (args > 0) {
		char arg_target[64];
		GetCmdArg(1, arg_target, sizeof(arg_target));

		int target = FindTarget(client, arg_target);
		if(!IsValidClient(target)) {
			PrintToChat(client,TARGET_NOT_FOUND);
			return Plugin_Handled;
		}
		
		char targetName[MAX_NAME_LENGTH];
		GetClientName(target,targetName,sizeof(targetName));
		
		PrintToChat(client,PLAYER_FOUND,targetName);
		PrintToChat(target,EXTERNAL_COMMAND);
		client = target;
	}
	
	
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(!IsValidEntity(weapon)) {
		PrintToChat(client,"\x03[ERROR]\x01 You have an invalid weapon !");
		return Plugin_Handled;
	}
	char weaponclassname[32];
	GetEntityClassname(weapon, weaponclassname, sizeof(weaponclassname));
	TFClassType playerclass = TF2_GetPlayerClass(client);
	switch(playerclass)
	{
		case TFClass_Scout:{
			SetEntPropFloat(client, Prop_Send, "m_flHypeMeter", 100.0);					
			SetEntPropFloat(client, Prop_Send, "m_flEnergyDrinkMeter", 100.0);
			if(GetClientButtons(client) & IN_ATTACK2){
				TF2_RemoveCondition(client, TFCond_Bonked); 
			}
		}
		case TFClass_Soldier:{
			if(!GetEntPropFloat(client, Prop_Send, "m_flRageMeter"))
			{

				SetEntPropFloat(client, Prop_Send, "m_flRageMeter", 100.0);
			}
		}
		case TFClass_DemoMan:{
			if(!TF2_IsPlayerInCondition(client, TFCond_Charging)) {
				SetEntPropFloat(client, Prop_Send, "m_flChargeMeter", 100.0);
			}
			//SetEntProp(client, Prop_Send, "m_iDecapitations", 99);
		}
		case TFClass_Engineer:{
			SetEntData(client, FindDataMapInfo(client, "m_iAmmo")+12, 200, 4);
		}
		case TFClass_Medic:{
			if((StrEqual(weaponclassname, "tf_weapon_medigun", false)) && !GetEntPropFloat(weapon, Prop_Send, "m_flChargeLevel")){
				SetEntPropFloat(weapon, Prop_Send, "m_flChargeLevel", 1.00);
			}
		}
		case TFClass_Sniper:{
			SetEntProp(client, Prop_Send, "m_iDecapitations", 99);
		}
		case TFClass_Spy:{
			SetEntPropFloat(client, Prop_Send, "m_flCloakMeter", 100.0);
			int knife = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
			if(IsValidEntity(knife)) {
				if(GetEntProp(knife, Prop_Send, "m_iItemDefinitionIndex") == 649)
				{
					SetEntPropFloat(knife, Prop_Send, "m_flKnifeRegenerateDuration", 0.0);
				}
			}
		}
	}
	
	int weaponindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	switch(weaponindex)
	{
		case 441,442,588:{
			SetEntPropFloat(weapon, Prop_Send, "m_flEnergy", 100.0);
		}
		case 141,525,595:{
			SetEntProp(client, Prop_Send, "m_iRevengeCrits", 10);
		}
		case 307:{
			SetEntProp(weapon, Prop_Send, "m_bBroken", 0);
			SetEntProp(weapon, Prop_Send, "m_iDetonated", 0);					
		}
		case 594:{
			if(!GetEntPropFloat(client, Prop_Send, "m_flRageMeter")){
				SetEntPropFloat(client, Prop_Send, "m_flRageMeter", 100.0);
			}					
		}
		case 752:{
			if(GetEntPropFloat(client, Prop_Send, "m_flRageMeter") == 0.00){
				SetEntPropFloat(client, Prop_Send, "m_flRageMeter", 100.0);
			}		
		}
	}
	
	//heatlh 
	SetEntityHealth(client,GetEntProp(client,Prop_Data,"m_iMaxHealth",2,0));
	return Plugin_Handled;
}

// ==== TIMERS

public Action Timer_JournalistCloak(Handle timer) {
	int journalists = 0;
	for(int player = 1; player <= MaxClients; player++)
	{
		if(IsClientInGame(player) && gb_isJournalist[player] && IsPlayerAlive(player)) {
			SetEntDataFloat(player, gi_OffsetCloak, 100.0);
			journalists += 1
		}
	}
	if (journalists == 0) {// prevent the clock to run while it's useless 
		//delete gh_journalistCloackRecover;
		gh_journalistCloackRecover = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	return Plugin_Handled;
}

public Action Timer_Speed(Handle timer) {
	int speeders = 0;
	for(int player = 1; player <= MaxClients; player++)
	{
		if(IsClientInGame(player) && gf_Speeds[player] != 0.0 && IsPlayerAlive(player)) {
			SetEntPropFloat(player, Prop_Send, "m_flMaxspeed", gf_Speeds[player]);
			speeders += 1
		}
	}
	if (speeders == 0) {// prevent the clock to run while it's useless {
		//delete gh_speedRecovery;
		gh_speedRecovery = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	return	Plugin_Handled;
}

public Action Timer_UpdateRandomSeed(Handle timer) {
	SetRandomSeed(GetTime());
	return Plugin_Handled;
}

/*public Action Timer_WallHack(Handle timer, int client) {
	if (gi_wallhackers == 0) {// prevent the clock to run while it's useless 
		//delete gh_wallhackUpdate;
		gh_wallhackUpdate = INVALID_HANDLE;
		return Plugin_Stop;
	}
		
	if(!IsClientInGame(client)) {
		return Plugin_Handled;
	}
	
	for(int player = 1; player < MaxClients; player++) 
	{
		if(player==client)
			continue;
		if(!IsClientInGame(player))
			continue;
		
		int skin = -1;
		skin = CreatePlayerModelProp(player);
		if(skin <= MaxClients)
			continue;
			
		TFTeam playerTeam = TF2_GetClientTeam(player);
		int color[4] = 0;
		color[3] = 255; // amplitude
		switch(playerTeam) 
		{
			case TFTeam_Red: {
				color[0] = 255;
			}
			case TFTeam_Blue: {
				color[2] = 255;
			}
			case TFTeam_Unassigned,TFTeam_Spectator: {
				continue; // they are not playing...
			}	
		}
		
		if(SDKHookEx(skin, SDKHook_SetTransmit,OnSetTransmit)) {
			static offset;
			// Get sendprop offset for prop_dynamic_override
			if (!offset && (offset = GetEntSendPropOffs(skin, "m_clrGlow")) == -1) {
				LogError("Unable to find property offset: \"m_clrGlow\"!");
				return Plugin_Handled;
			}

			// Enable glow for custom skin
			SetEntProp(skin, Prop_Send, "m_bShouldGlow", true);
			SetEntProp(skin, Prop_Send, "m_nGlowStyle", 0);
			SetEntPropFloat(skin, Prop_Send, "m_flGlowMaxDist", 10000.0);

			// So now setup given glow colors for the skin
			for(int i=0;i<3;i++) {
				SetEntData(skin, offset + i, color[i], _, true); 
			}
		}
	}
		//TE_SetupBeamPoints(vecMin,vecMax,gi_laserModel,0,0,0,0.1,2.0,2.0,0,0.0,color,15);
		
		//TE_SetupBeamPoints(vecMin, vecMax, gi_laserModel, gi_laserModel, 0, 1, 0.7, 20.0, 50.0, 1, 1.5, color, 10);
		//TE_SendToClient(client,0.1); // only client sees, which is a must !!
		
		float vec[3];
		float up[3];
		up[2] += 128;
		
		GetClientAbsAngles(player, vec);
		TE_SetupBeamPoints(vec, up, gi_laserModel, 0, 0, 0, 0.1, 3.0, 3.0, 7, 0.0, color, 0);
		//TE_SetupBeamRingPoint(vec, 10.0, 600.0, gi_laserModel, g_HaloSprite, 0, 15, 0.5, 5.0, 0.0, color, 10, 0);
		TE_SendToClient(client,0.1);
	
	return	Plugin_Handled;
}*/

// === Wallhack utils 

public void CreatePlayerModelProp(int player, int client) {
	RemoveSkin(player);
	char modelName[128];
	GetEntPropString(player, Prop_Data, "m_ModelName", modelName, sizeof(modelName));

	int skin = -1;
	skin = CreateEntityByName("prop_dynamic"); //prop_dynamic_glow doesn't exist in TF2
	if(skin == -1)
		return;
		
	DispatchKeyValue(skin, "model", modelName);
	
	char name[32];
	Format(name,sizeof(name),"glowmodel_%d",player);
	
	DispatchKeyValue(skin, "targetname", name);
	DispatchKeyValue(skin, "solid", "0");
	DispatchKeyValue(skin, "fadescale", "0");
	SetEntProp(skin, Prop_Send, "m_CollisionGroup", 0);
	
	DispatchSpawn(skin);
	
	SetEntityRenderMode(skin, RENDER_GLOW);
	SetEntityRenderColor(skin, 0, 0, 0, 0);
	SetEntProp(skin, Prop_Send, "m_fEffects", EF_BONEMERGE); // takes too much resources...
	SetVariantString("!activator");
	AcceptEntityInput(skin, "SetParent", player, skin);
	
	SetVariantString("foot_L"); // left foot
	AcceptEntityInput(skin, "SetParentAttachment", skin, skin, 0);
	
	SetVariantString("OnUser1 !self:Kill::0.1:-1");
	AcceptEntityInput(skin, "AddOutput");
	AcceptEntityInput(skin,"TurnOff"); // turnoff when we hook it.
	gi_wallhackModelIndexes[player] = EntIndexToEntRef(skin); // best way to track indexes...
	
	////// Glow ///////
	
	TFTeam playerTeam = TF2_GetClientTeam(player);
	
	int glow = -1;
	glow = CreateEntityByName("tf_glow");
	if(glow == -1)
		return;
		
	int color[4] = 0;
	color[3] = 255; // amplitude
	switch(playerTeam) 
	{
		case TFTeam_Red: {
			color[0] = 255;
		}
		case TFTeam_Blue: {
			color[2] = 255;
		}
		case TFTeam_Unassigned,TFTeam_Spectator: {
			return; // they are not playing...
		}	
	}
		
	char targetname[32];
	Format(targetname,sizeof(targetname),"glowmodel_%d",player);
	
	DispatchKeyValue(glow, "target", targetname);
	DispatchKeyValue(glow, "Mode", "0");
	DispatchSpawn(glow);
	
	SetVariantColor(color);
	AcceptEntityInput(glow, "SetGlowColor");
	SetVariantString("OnUser1 !self:Kill::0.1:-1");
	AcceptEntityInput(glow, "AddOutput");
	
	gi_wallhackGlowIndexes[player] = EntIndexToEntRef(glow);
	
	/////////// item_teamflag ///////////
	
	/*int skin = -1;
	skin = CreateEntityByName("item_teamflag"); //prop_dynamic_glow doesn't exist in TF2
	if(skin == -1)
		return;
		
	DispatchKeyValue(skin, "model", modelName);
	DispatchKeyValue(skin, "solid", "0");
	DispatchKeyValue(skin, "fadescale", "0");
	DispatchKeyValue(skin, "TeamNum", "0"); 
	DispatchKeyValue(skin, "trail_effect", "0");
	DispatchKeyValue(skin, "ReturnTime", "999999");
	DispatchKeyValue(skin, "StartDisabled", "1");
	SetEntProp(skin, Prop_Send, "m_CollisionGroup", 0);
	
	DispatchSpawn(skin);
	SetEntProp(skin, Prop_Send, "m_fEffects", EF_BONEMERGE); // takes too much resources...
	SetVariantString("!activator");
	AcceptEntityInput(skin, "SetParent", player, skin);
	
	SetEntProp(skin, Prop_Send, "m_bGlowEnabled", 1, 1);
	
	SetVariantString("OnUser1 !self:Kill::0.1:-1");
	AcceptEntityInput(skin, "AddOutput");
	gi_wallhackModelIndexes[player] = EntIndexToEntRef(skin); // best way to track indexes...*/
	
	
	
	if(SDKHookEx(skin, SDKHook_SetTransmit, OnSetTransmit) ) {//&& SDKHookEx(glow, SDKHook_SetTransmit, OnSetTransmit)) {
		AcceptEntityInput(skin,"TurnOn");
		AcceptEntityInput(glow, "Enable");
		PrintToChat(client,"Index of model : %d ",skin);
	}
}

public void RemoveSkin(int player) { // also removes glows
	int skinIndex = EntRefToEntIndex(gi_wallhackModelIndexes[player]);
	int glowIndex = EntRefToEntIndex(gi_wallhackGlowIndexes[player]);
	
	if((skinIndex == INVALID_ENT_REFERENCE || !IsValidEntity(skinIndex)) ||(glowIndex == INVALID_ENT_REFERENCE || !IsValidEntity(glowIndex)))
		return;
		
	if(skinIndex > MaxClients && IsValidEntity(skinIndex)) {
		AcceptEntityInput(skinIndex, "FireUser1");
	}
	if(glowIndex > MaxClients && IsValidEntity(glowIndex)) {
		AcceptEntityInput(skinIndex, "FireUser1");
	}
	gi_wallhackModelIndexes[player] = INVALID_ENT_REFERENCE;
	//SDKUnhook(gi_wallhackModelIndexes[player],SDKHook_SetTransmit,OnSetTransmit);
}

public void RemoveAllSkin() {
	for(int player = 1; player < MaxClients; player++)  
	{
		RemoveSkin(player);
	}
}



// ==== HookSingleEntityOutput

public Action SoundHook(clients[64], &numClients, String:sound[PLATFORM_MAX_PATH], &Ent, &channel, &Float:volume, &level, &pitch, &flags) // be the robot plugin : https://forums.alliedmods.net/showthread.php?t=193067
{
	if (!IsValidClient(Ent) || volume == 0.0 || volume == 0.9997)
		return Plugin_Continue;
	
	int client = Ent;
	if (gb_isRobot[client]) {
		TFClassType class = TF2_GetPlayerClass(client);
		if (StrContains(sound, "player/footsteps/", false) != -1 && class != TFClass_Medic) {
			int rand = GetRandomInt(1,18);
			Format(sound, sizeof(sound), "mvm/player/footsteps/robostep_%s%i.wav", (rand < 10) ? "0" : "", rand);
			pitch = GetRandomInt(95, 100);
			EmitSoundToAll(sound, client, _, _, _, 0.25, pitch);
			return Plugin_Changed;
		}
		if (StrContains(sound, "vo/", false) == -1 || StrContains(sound, "announcer", false) != -1) 
			return Plugin_Continue;
		
		//if (volume == 0.99997) return Plugin_Continue; why is it here again ?
		ReplaceString(sound, sizeof(sound), "vo/", "vo/mvm/norm/", false);
		ReplaceString(sound, sizeof(sound), ".wav", ".mp3", false);
		char classname[10]
		char classname_mvm[15];
		switch (class) 
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
		
		Format(classname_mvm, sizeof(classname_mvm), "%s_mvm", classname);
		ReplaceString(sound, sizeof(sound), classname, classname_mvm, false);
		char soundchk[PLATFORM_MAX_PATH];
		Format(soundchk, sizeof(soundchk), "sound/%s", sound);
		
		if (!FileExists(soundchk, true)) 
			return Plugin_Continue;
		
		PrecacheSound(sound);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

// ==== OTHERS

public void setRenderWearable(int client,RenderMode render_mode) {
	int maxEnt = GetMaxEntities();
	char classname[32];
	for (int entity = MaxClients +1; entity <= maxEnt; entity++)  
	{
		if(!IsValidEntity(entity) || !IsValidEdict(entity))
			continue;
		
		GetEntityClassname(entity, classname, sizeof(classname));
		if(StrContains(classname,"tf_wearable") != -1) {
			if(GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client) {
				SetEntityRenderMode(entity,render_mode);
			}
		}
	}
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

public void precaching() {

	// wallhack
	//gi_laserModel = PrecacheModel("sprites/laserbeam.vmt");
	
	//TEMP_REQUIRE_EXTENSIONS
	//g_BeamSprite = PrecacheModel("sprites/laser.vmt");
	//g_HaloSprite = PrecacheModel("sprites/glow01.vmt");

	// robots
	for (int i = 1; i <= 18; i++)	{
		char snd[PLATFORM_MAX_PATH];
		Format(snd, sizeof(snd), "mvm/player/footsteps/robostep_%s%i.wav", (i < 10) ? "0" : "", i);
		PrecacheSound(snd, true);
		/*if (i <= 4)
		{
			Format(snd, sizeof(snd), "mvm/sentrybuster/mvm_sentrybuster_step_0%i.wav", i);
			PrecacheSound(snd, true);
		}
		if (i <= 6)
		{
			Format(snd, sizeof(snd), "vo/mvm_sentry_buster_alerts0%i.wav", i);
			PrecacheSound(snd, true);
		}*/
	}
		/*PrecacheSound("mvm/sentrybuster/mvm_sentrybuster_explode.wav", true);
	PrecacheSound("mvm/sentrybuster/mvm_sentrybuster_intro.wav", true);
	PrecacheSound("mvm/sentrybuster/mvm_sentrybuster_loop.wav", true);
	PrecacheSound("mvm/sentrybuster/mvm_sentrybuster_spin.wav", true);
	PrecacheModel("models/bots/demo/bot_sentry_buster.mdl", true);*/
	
	// why caching sentry buster sounds and model ?

}


/*
old way of args of player :

int newclient = 0;
char name[64];
GetCmdArg(2, name, sizeof(name)); // 1 or 2
int targetArray[MAXPLAYERS];
bool tn_is_ml;
char target_name[MAX_TARGET_LENGTH];
int numtargets = ProcessTargetString(name, newclient, targetArray, MAXPLAYERS, 0, target_name,sizeof(target_name), tn_is_ml);

if(numtargets <= 0){
	ReplyToTargetError(client, numtargets);
	return Plugin_Handled;
}
for(int i = 0; i < numtargets; i++)
{
	if(IsClientInGame(targetArray[i]))
		newclient = targetArray[i];
}

PrintToChat(client,PLAYER_FOUND,target_name);
PrintToChat(newclient,EXTERNAL_COMMAND);
client = newclient;

*/