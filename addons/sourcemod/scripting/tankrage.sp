#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <colors>


public Plugin myinfo = {
    name        = "Tank Rage",
    author      = "Sir, TouchMe",
    description = "Manage Tank Rage when Survivors are running back",
    version     = "build_0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_tankrage"
};


#define TEAM_SURVIVOR 2

ConVar g_cvVsBossBuffer = null;
ConVar g_cvFreezeTime = null;
ConVar g_cvDistancePerSecond = null;


Handle g_hTankTimer = null;

bool bHaveHadFlowOrStaticTank = false;

int g_iTankSpawned = -1;

float g_fTankSpawnedSurvivorFlowDistance = 0.0;


public APLRes AskPluginLoad2(Handle myself, bool bLate, char[] szErr, int iErrLen)
{
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(szErr, iErrLen, "Plugin only supports Left 4 Dead 2.");
        return APLRes_SilentFailure;
    }

    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("tankrage.phrases");

    g_cvVsBossBuffer = FindConVar("versus_boss_buffer");
    g_cvFreezeTime = CreateConVar("sm_tankrage_freezetime", "4.0", "Time in seconds to freeze the Tank's frustration when survivors have ran back");
    g_cvDistancePerSecond = CreateConVar("sm_tankrage_distance_per_second", "300.0", "");

    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_Post);
    HookEvent("round_start", Event_ResetTank, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_ResetTank, EventHookMode_Post);
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post()
{
    g_fTankSpawnedSurvivorFlowDistance = L4D2Direct_GetVSTankFlowPercent(InSecondHalfOfRound()) ?
        L4D2Direct_GetVSTankFlowPercent(InSecondHalfOfRound()) * L4D2Direct_GetMapMaxFlowDistance() : 0.0;
}

void Event_TankSpawn(Event hEvent, char[] szEventName, bool bDontBroadcast)
{
    g_iTankSpawned = GetClientOfUserId(hEvent.GetInt("userid"));

    if (bHaveHadFlowOrStaticTank) {
        return;
    }

    /*
        This is needed for maps that do not have a flow tank.
        We will however be checking if the map is the last map in the campaign as we don't want to mess with finale tanks
        tankSpawnedSuvivorFlow will always be 0 for static tanks, so we need to rely on another method in this check.
    */
    if (FloatCompare(g_fTankSpawnedSurvivorFlowDistance, 0.0) == 0)
    {
        if (L4D_IsMissionFinalMap()) {
            return;
        }

        g_fTankSpawnedSurvivorFlowDistance = fmin(L4D2_GetFurthestSurvivorFlow() + g_cvVsBossBuffer.FloatValue, L4D2Direct_GetMapMaxFlowDistance());
    }

    if (!IsFakeClient(g_iTankSpawned))
    {
        CPrintToChatAll("%t%t", "TAG", "SURVIVORS_RUN_BACK",
            (g_cvFreezeTime.FloatValue * g_cvDistancePerSecond.FloatValue) / L4D2Direct_GetMapMaxFlowDistance() * 100.0,
            g_cvFreezeTime.FloatValue
        );
        g_hTankTimer = CreateTimer(0.1, Timer_Tank, .flags = TIMER_REPEAT);
        bHaveHadFlowOrStaticTank = true;
    }
}

void Event_ResetTank(Event hEvent, char[] szEventName, bool bDontBroadcast)
{
    if (strcmp(szEventName, "player_death") == 0)
    {
        char szVictimName[32];
        hEvent.GetString("victimname", szVictimName, sizeof(szVictimName), "None");

        if (strcmp(szVictimName, "Tank") != 0) {
            return;
        }
    }
    else
    {
        bHaveHadFlowOrStaticTank = false;
        g_fTankSpawnedSurvivorFlowDistance = 0.0;
        g_iTankSpawned = -1;
    }

    delete g_hTankTimer;
}

Action Timer_Tank(Handle hTimer)
{
    if (IsClientInGame(g_iTankSpawned) && !IsFakeClient(g_iTankSpawned))
    {
        float fSurvivorCompletion = GetMaxSurvivorCompletionFlowDistance();

        if (FloatCompare(fSurvivorCompletion, 0.0) == 0) {
            return Plugin_Continue;
        }

        float fCurrentDistance = fSurvivorCompletion + g_cvVsBossBuffer.FloatValue;
        float fFreezeDistance = g_cvFreezeTime.FloatValue * g_cvDistancePerSecond.FloatValue;

        if (g_fTankSpawnedSurvivorFlowDistance - fCurrentDistance >= fFreezeDistance)
        {
            for (;;)
            {
                if (g_fTankSpawnedSurvivorFlowDistance - fCurrentDistance >= fFreezeDistance)
                {
                    g_fTankSpawnedSurvivorFlowDistance -= fFreezeDistance;
                    continue;
                }

                break;
            }

            float fTankGrace = CTimer_GetRemainingTime(GetFrustrationTimer(g_iTankSpawned));

            if (fTankGrace < 0.0) {
                fTankGrace = 0.0;
            }

            fTankGrace += g_cvFreezeTime.FloatValue;
            CTimer_Start(GetFrustrationTimer(g_iTankSpawned), fTankGrace);
        }
    }

    return Plugin_Continue;
}

CountdownTimer GetFrustrationTimer(int iClient)
{
    static int s_iOffs_m_frustrationTimer = -1;
    if (s_iOffs_m_frustrationTimer == -1) {
        s_iOffs_m_frustrationTimer = FindSendPropInfo("CTerrorPlayer", "m_frustration") + 4;
    }

    return view_as<CountdownTimer>(GetEntityAddress(iClient) + view_as<Address>(s_iOffs_m_frustrationTimer));
}

float GetMaxSurvivorCompletionFlowDistance()
{
    float flow = 0.0, tmp_flow = 0.0;
    Address pNavArea = Address_Null;
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (IsClientInGame(iClient) && IsClientSurvivor(iClient) && IsPlayerAlive(iClient))
        {
            pNavArea = L4D_GetLastKnownArea(iClient);

            if (pNavArea != Address_Null)
            {
                tmp_flow = L4D2Direct_GetTerrorNavAreaFlow(pNavArea);
                flow = (flow > tmp_flow) ? flow : tmp_flow;
            }
            else return 0.0;
        }
    }

    return flow;
}

/**
 * Checks if the game is currently in the second half of the round.
 *
 * @return              1 if the game is in the second half,
 *                      0 otherwise.
 */
int InSecondHalfOfRound() {
    return GameRules_GetProp("m_bInSecondHalfOfRound");
}

/**
 * Determines whether a given client is a survivor.
 *
 * @param iClient       Client index.
 * @return              true if the client is on the survivor team,
 *                      false otherwise.
 */
bool IsClientSurvivor(int iClient) {
    return GetClientTeam(iClient) == TEAM_SURVIVOR;
}

/**
 * Returns the smaller of two floating-point values.
 *
 * @param a             First value.
 * @param b             Second value.
 * @return              The minimum of the two values.
 */
float fmin(float a, float b) {
    return a < b ? a : b;
}
