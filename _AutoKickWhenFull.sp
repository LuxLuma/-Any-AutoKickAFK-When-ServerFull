#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

#define PLUGIN_VERSION "1.0"


static int iLastAction[MAXPLAYERS+1];
static Handle hCvar_CheckSpec = INVALID_HANDLE;
static bool bCheckSpec = false;
static Handle hCvar_AfkTime = INVALID_HANDLE;
static int iAfkTime = 420;
static Handle hCvar_KickOnFull = INVALID_HANDLE;
static bool bKickOnFull = true;

static Handle hCvar_VisibleMaxPlayers = INVALID_HANDLE;
static int iMaxVisiblePlayers = -1;

static bool bL4D = false;// only tested on l4d but should work on other games

public Plugin myinfo =
{
	name = "[Any]AutoKickAFK When ServerFull",
	author = "Lux",
	description = "Auto kicks a player who is afk when the server is full",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?p=2569852"
};

public void OnPluginStart()
{
	char sGameName[13];
	GetGameFolderName(sGameName, sizeof(sGameName));
	bL4D = (StrContains(sGameName, "left4dead", false) == 0);
	
	hCvar_VisibleMaxPlayers = FindConVar("sv_visiblemaxplayers");
	if(hCvar_VisibleMaxPlayers != INVALID_HANDLE)
		HookConVarChange(hCvar_VisibleMaxPlayers, eConvarChanged);
		
	for(int i = 1; i <= MAXPLAYERS; i++)
		iLastAction[i] = view_as<int>(GetEngineTime());// incase someone loaded plugin with cmd
	
	CreateConVar("konfull_AutoKickWhenFull_version", "AutoKickWhenFull plugin version", PLUGIN_VERSION, FCVAR_SPONLY|FCVAR_DONTRECORD|FCVAR_NOTIFY);
	
	hCvar_CheckSpec = CreateConVar("konfull_check_spec_for_movement", "1", "check spec team like players for movement [0 = consider spec as AFK! 1 = check as player]", FCVAR_NOTIFY);
	HookConVarChange(hCvar_CheckSpec, eConvarChanged);
	hCvar_AfkTime = CreateConVar("konfull_afk_time", "420", "(Seconds)afk time before they will get kicked", FCVAR_NOTIFY, true, 1.0);
	HookConVarChange(hCvar_AfkTime, eConvarChanged);
	hCvar_KickOnFull = CreateConVar("konfull_kick_on_full", "1", "Should we only kick when server is full [1 = true 0 = false]", FCVAR_NOTIFY);
	HookConVarChange(hCvar_KickOnFull, eConvarChanged);
	
	AutoExecConfig(true, "_AutoKickWhenFull");
	
	HookEvent("player_connect", ePlayerConnect, EventHookMode_Post);
	CreateTimer(1.0, AutoKick, INVALID_HANDLE, TIMER_REPEAT);
}

public Action AutoKick(Handle hTimer)
{
	if(!IsServerFull() && bKickOnFull)
		return Plugin_Continue;
	
	static bool bKick;
	bKick = true;
	static float fNow;
	fNow = GetEngineTime();
	
	static int i;
	for(i = 1; i <= MaxClients;i++)
	{
		if(!IsClientConnected(i) || IsFakeClient(i) || GetUserFlagBits(i) & ADMFLAG_RESERVATION|ADMFLAG_ROOT)
			continue;
		
		if(IsClientConnected(i) && !IsClientInGame(i))
		{
			iLastAction[i]++;
			continue;
		}
		
		if(!bKick)
			continue;
		
		if(iLastAction[i] < fNow - iAfkTime)
		{
			if(IsClientInGame(i))
				KickClient(i, "Server is full making room because you're AFK!");
			
			bKick = false;
		}
	}
	
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAngles[3], int &iWeapon, int &iSubtype, int &iCmdnum, int &iTickcount, int &iSeed, int iMouse[2])
{
	if(IsFakeClient(iClient) || GetUserFlagBits(iClient) & ADMFLAG_RESERVATION|ADMFLAG_ROOT)
		return Plugin_Continue;
	
	if(!bCheckSpec)
		if(GetClientTeam(iClient) < 2)
			return Plugin_Continue;
	
	static int iLastValues[MAXPLAYERS+1][3];
	
	if(bL4D)
	{
		if(IsMouseValsValid(iClient))
		{
			if(iLastValues[iClient][0] == iButtons && iLastValues[iClient][1] == iMouse[0] && iLastValues[iClient][2] == iMouse[1])
				return Plugin_Continue;
		}
		else if(iLastValues[iClient][0] == iButtons)
			return Plugin_Continue;
	}
	else
	{
		if(iLastValues[iClient][0] == iButtons && iLastValues[iClient][1] == iMouse[0] && iLastValues[iClient][2] == iMouse[1])
			return Plugin_Continue;
	}
	
	iLastAction[iClient] = RoundFloat(GetEngineTime());
	
	return Plugin_Continue;
}

static bool IsMouseValsValid(int iClient)
{
	if(GetEntProp(iClient, Prop_Send, "m_iObserverMode") != 4)
		return true;
	
	static int iTarget;
	iTarget = GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget");
	if(iTarget < 1 || iTarget > MaxClients)
		return true;
		
	if(!IsClientInGame(iTarget) || !IsPlayerAlive(iTarget))
		return true;
	
	if(!GetEntProp(iTarget, Prop_Send, "m_isIncapacitated", 1))
		return true;
	
	return false;
}

public void ePlayerConnect(Handle hEvent, const char[] sName, bool bDontBroadcast)
{	
	CreateTimer(1.0, CheckClient, GetEventInt(hEvent, "userid"), TIMER_REPEAT);
}

public Action CheckClient(Handle hTimer, any iUserID)
{
	int iClient = GetClientOfUserId(iUserID);
	
	if(iClient < 1 || iClient > MaxClients || !IsClientConnected(iClient) || IsFakeClient(iClient))
		return Plugin_Stop;
	
	if(!IsClientAuthorized(iClient))
		return Plugin_Continue;
	
	iLastAction[iClient] = RoundFloat(GetEngineTime());
	return Plugin_Stop;
}

static bool IsServerFull()
{
	static int iCount;
	iCount = 0;
	static int i;
	for(i = 1; i <= MaxClients; i++) 
	{
		if(!IsClientConnected(i) || IsFakeClient(i))
			continue;
		
		iCount++;
	}
	
	if(iMaxVisiblePlayers < 1)
		return (GetMaxHumanPlayers() <= iCount);
	return (iMaxVisiblePlayers <= iCount);
}

public void eConvarChanged(Handle hCvar, const char[] sOldVal, const char[] sNewVal)
{
	CvarsChanged();
}

void CvarsChanged()
{
	bCheckSpec = GetConVarInt(hCvar_CheckSpec) > 0;
	iAfkTime = GetConVarInt(hCvar_AfkTime);
	iMaxVisiblePlayers = GetConVarInt(hCvar_VisibleMaxPlayers);
	bKickOnFull = GetConVarInt(hCvar_KickOnFull) > 0;
}