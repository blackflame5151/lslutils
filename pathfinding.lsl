//
//  Pathfinding library
//
//  IN PROGRESS - DO NOT USE YET
//
//  Makes Second Life pathfinding work reliably.
//
//  Animats
//  January, 2019
//  License: GPL
//
//  Adds checking and retry, which is essential to getting anything done reliably.
//
//  Works around Second Life bugs BUG-5021, BUG-226061.
//
//  To use this, change your code as follows:
//
//      llNavigateTo -> pathNavigateTo
//      llPursue -> pathPursue
//      llWander -> pathWander
//      llEvade -> pathEvade
//      llFlee -> pathFlee
//
//  Also:
//      path_update -> pathUpdateCallback - define this for your own callback
//      In your path_update, call pathUpdate.
//
//      (llPatrol is not implemented. Suggest using llNavigateTo for each goal point.)
//
//  and call pathTick from a timer or sensor at least once every 2 seconds when pathfinding.
//
//  Retrying will happen when necessary.  
//
//
//  Configuration
//
integer PATH_STALL_TIME = 120;                          // (secs) really stalled if greater than this
integer PATH_START_TIME = 2;                            // (secs) allow this long for path operation to start
float   PATH_GOAL_TOL = 3.0;                            // (m) how close to dest is success?
//
//  Constants
//
//  Pathmode - what we're doing now.
integer PATHMODE_OFF = 0;                                   // what we're doing now
integer PATHMODE_NAVIGATE_TO = 1;
integer PATHMODE_PURSUE = 2;
integer PATHMODE_WANDER = 3;
integer PATHMODE_EVADE = 4;
integer PATHMODE_FLEE_FROM = 5;
//
//  Path statuses.  Also, the LSL PU_* pathfinding statuses are used
integer PATHSTALL_NONE = -1;                                // not stalled, keep going
integer PATHSTALL_RETRY = -2;                               // unstick and retry
integer PATHSTALL_STALLED = -3;                             // failed, despite retries
integer PATHSTALL_CANNOT_MOVE = -4;                         // can't move at all at current position
//
//  Error levels
//
integer PATH_MSG_ERROR = 0;
integer PATH_MSG_WARN = 1;
integer PATH_MSG_INFO = 2;
//
//  Globals internal to this module
//
                                                            // the current request
integer gPathPathmode = PATHMODE_OFF;                       // what are we doing right now.  
key gPathTarget = NULL_KEY;                                 // target avatar, when pursuing
vector gPathGoal;                                           // goal when navigating
vector gPathDist;                                           // distance when wandering
list gPathOptions;                                          // options for all operations
float gPathTolerance;                                       // how close to end is success
 
                                                            // other state
integer gPathRequestStartTime;                              // UNIX time path operation started
integer gPathActionStartTime;                               // UNIX time path operation started
integer gPathMsgLevel = PATH_MSG_ERROR;                     // debug message level (set to change level)

//
//  Call these functions instead of the corresponding LSL functions
//
pathNavigateTo(vector goal, list options)
{   if (gPathPathmode != PATHMODE_OFF) { pathStop(); }      // stop whatever we are doing
    gPathTolerance = PATH_GOAL_TOL;                         // default tolerance
    gPathGoal = goal;                                       // head here
    gPathOptions = options;                                 // using these options
    pathActionStart(PATHMODE_NAVIGATE_TO);                  // use common function
}

pathPursue(key target, list options)
{
    if (gPathPathmode != PATHMODE_OFF) { pathStop(); }      // stop whatever we are doing
    gPathTolerance = PATH_GOAL_TOL;                         // default tolerance
    integer i;
    for (i=0; i<llGetListLength(gPathOptions); i++)         // search strided list
    {   if (llList2Integer(gPathOptions,i) == PURSUIT_GOAL_TOLERANCE) // if goal tolerance item
        {   gPathTolerance = llList2Float(gPathOptions,i+1);// get tolerance
            gPathTolerance = gPathTolerance + PATH_GOAL_TOL;    // add safety margin
            pathMsg(PATH_MSG_INFO, "Pursue tolerance (m): " + (string) gPathTolerance);
        }
    }
    gPathTarget = target;
    gPathOptions = options;
    pathActionStart(PATHMODE_PURSUE);                       // use common function
}
                
pathWander(vector goal, vector dist, list options)
{
    if (gPathPathmode != PATHMODE_OFF) { pathStop(); }      // stop whatever we are doing
    gPathGoal = goal;                                       // wander around here
    gPathDist = dist;                                       // within this distance
    gPathOptions = options;                                 // using these options
    pathActionStart(PATHMODE_WANDER);                       // use common function
}

pathEvade(key target, list options)
{
    if (gPathPathmode != PATHMODE_OFF) { pathStop(); }      // stop whatever we are doing  
    gPathTarget = target;
    gPathOptions = options;
    pathActionStart(PATHMODE_EVADE);
}

pathFleeFrom(vector goal, float distmag, list options)
{
    if (gPathPathmode != PATHMODE_OFF) { pathStop(); }      // stop whatever we are doing
    gPathGoal = goal;
    gPathDist = <distmag,0,0>;                              // because we only use the magnitude
    gPathOptions = options;
    pathActionStart(PATHMODE_FLEE_FROM);                        // use common fn
}
//
//  pathInit -- call this at startup/rez to initialize the variables
//
pathInit()
{
    gPathPathmode = PATHMODE_OFF;
    gPathTarget = NULL_KEY;
}
//
//  pathTick --  call this at least once every 2 seconds.
//
pathTick()
{
    if (gPathPathmode == PATHMODE_OFF) { return; }              // not pathfinding, nothing to do.
    integer status = pathStallCheck();                          // are we stuck?
    if (status == PATHSTALL_NONE) { return; }                   // no problem, keep going
    if (status == PU_GOAL_REACHED)                              // success
    {   pathUpdateCallback(status);                             // call user-defined completion fn
        return;
    }
    if (status == PATHSTALL_STALLED)                            // total fail
    {   pathStop();                                             // stop operation in progress
        pathUpdateCallback(status);                             // call user defined completion function
        return;
    }
    //  Possible recoverable problem
    pathMsg(PATH_MSG_WARN, "Retrying path operation");
    integer success = pathUnstick();                            // try to unstick situation
    if (success)
    {   pathActionRestart();                                    // and restart
    } else {                                                    // unable to unstick
        pathStop();                                             // fails
        pathUpdateCallback(PATHSTALL_CANNOT_MOVE);              // we are stuck
        return;
    }
}
//
//  Internal functions
//
pathMsg(integer level, string msg)                              // print debug message
{   if (level > gPathMsgLevel) { return; }                      // ignore if suppressed
    llOwnerSay("Pathfinding: " + msg);                          // message
}

pathStop()
{
    llExecCharacterCmd(CHARACTER_CMD_STOP,[]);                  // stop whatever is going oin
    gPathPathmode = PATHMODE_OFF;                               // not pathfinding
}

pathActionStart(integer pathmode)
{
    gPathPathmode = pathmode;
    pathMsg(PATH_MSG_INFO, "Starting pathfinding.");
    gPathRequestStartTime = llGetUnixTime();                    // start time of path operation
    pathActionRestart();                                        // start the task
}

//
//  pathActionRestart  -- restart whatever was running
//
pathActionRestart()
{
    gPathActionStartTime = llGetUnixTime();                     // start timing
    if (gPathPathmode == PATHMODE_NAVIGATE_TO)                  // depending on operation in progress
    {   llNavigateTo(gPathGoal, gPathOptions);                  // restart using stored values
    } else if (gPathPathmode == PATHMODE_PURSUE)
    {   llPursue(gPathTarget, gPathOptions);
    } else if (gPathPathmode == PATHMODE_WANDER)
    {   llWanderWithin(gPathGoal, gPathDist, gPathOptions);
    } else if (gPathPathmode == PATHMODE_EVADE)
    {   llEvade(gPathTarget, gPathOptions); 
    } else if (gPathPathmode == PATHMODE_FLEE_FROM)
    {   llFleeFrom(gPathGoal, llVecMag(gPathDist), gPathOptions);
    } else {
        pathMsg(PATH_MSG_ERROR, "pathActionRestart called incorrectly with pathmode = " 
            + (string)gPathPathmode);
    }
}

//
//  pathStallCheck  --  is pathfinding stalled?
//
//  Checks:
//      1. Stall timeout - entire operation took too long. Usual limit is about 2 minutes.
//      2. We're at the goal, so stop.
//      3. Zero velocity and zero angular rate - pathfinding quit on us.
//      4. No significant progress in last few seconds - pathfinding is stalled dynamically.
//
integer pathStallCheck()
{
    if (gPathPathmode == PATHMODE_OFF) { return(PATHSTALL_NONE); } // idle, cannot stall
    if (gPathPathmode == PATHMODE_WANDER 
    || gPathPathmode == PATHMODE_EVADE 
    || gPathPathmode == PATHMODE_FLEE_FROM) { return(PATHSTALL_NONE); }  // no meaningful completion criterion 
    //  Stall timeout
    integer now = llGetUnixTime();                  // UNIX time since epoch, sects
    if (now - gPathRequestStartTime > PATH_STALL_TIME)// if totally stalled
    {   pathStop();                                 // stop whatever is going on
        pathMsg(PATH_MSG_ERROR, "Request stalled after " + (string)PATH_STALL_TIME + " seconds."); 
        return(PATHSTALL_STALLED);
    }
    //  At-goal check. Usually happens when start and goal are too close
    if (pathAtGoal())
    {   pathStop();                                 // request complete
        return(PU_GOAL_REACHED);                    // Happy ending
    }

    //  Zero velocity check
    if (now - gPathActionStartTime > PATH_START_TIME) // if enough time for pathfinding to engage
    {   if (llVecMag(llGetVel()) < 0.01 && llVecMag(llGetOmega()) < 0.01)
        {   pathMsg(PATH_MSG_WARN, "Not moving");
            return(PATHSTALL_RETRY);                // retry needed
        }
    }
    //  ***MORE*** need check for dynamically stalled, moving but not making progress
    return(PATHSTALL_NONE);                         // we are OK
}

integer pathAtGoal()                                // are we at the goal?
{
    //  At-goal check. Usually happens when start and goal are too close
    if (gPathPathmode == PATHMODE_NAVIGATE_TO)          // only if Navigate To
    {   if (llVecMag(llGetPos() - gPathGoal) < gPathTolerance) // if arrived.
        {   pathMsg(PATH_MSG_WARN, "At Navigate To goal.");
            return(TRUE);                    // Happy ending
        }
    } else if (gPathPathmode == PATHMODE_PURSUE)
    {   if (llVecMag(llGetPos() - llList2Vector(llGetObjectDetails(gPathTarget, [OBJECT_POS]),0)) <= gPathTolerance)
        {   pathMsg(PATH_MSG_WARN, "At Pursuit goal.");
            return(TRUE);                    // Happy ending
        }
    }
    return(FALSE);                           // not at goal
}

//
//  pathUnstick  -- get stuck object moving again
//
//  Unstick steps:
//      1. Wander a small amount.
//      2. Do a small move with llPos.
//
integer pathUnstick()
{
    pathMsg(PATH_MSG_WARN,"Attempting recovery - wandering briefly.");
    vector pos = llGetPos();
    llWanderWithin(pos, <2.0, 2.0, 1.0>,[]);    // move randomly to get unstuck
    llSleep(2.0);
    llExecCharacterCmd(CHARACTER_CMD_STOP, []);
    llSleep(1.0);
    if (llVecMag(llGetPos() - pos) < 0.01) // if character did not move
    {   pathMsg(PATH_MSG_WARN,"Wandering recovery did not work.  Trying forced move.");
        pos.x = pos.x + 0.5;                // ***NEEDS TO BE SAFER ABOUT OBSTACLES***
        pos.y = pos.y + 0.5;
        llSetPos(pos);                              // force a move
        //  Try second wander. If it doesn't move, we're really stuck.
        llWanderWithin(pos, <2.0, 2.0, 1.0>,[]);    // move randomly to get unstuck
        llSleep(2.0);
        llExecCharacterCmd(CHARACTER_CMD_STOP, []);
        llSleep(1.0);
        if (llVecMag(llGetPos() - pos) < 0.01) // if character did not move
        {   pathMsg(PATH_MSG_ERROR,"Second recovery did not work. Help.");
            return(FALSE);  // failed
        }
    }
    return(TRUE);                               // unable to move at all
}

//  
//  pathUpdate  -- Pathfinding system reports completion
//
pathUpdate(integer status, list reserved)
{
    if (gPathPathmode == PATHMODE_OFF)                  // idle, should not happen
    {   pathMsg(PATH_MSG_ERROR, "Unexpected path_update call, status " + (string)status);
        return;
    }
    if (status == PU_GOAL_REACHED)                      // may be at goal, or not.
    {   //  Pathfinding system thinks goal reached. 
        if (pathAtGoal()) 
        {   pathStop();
            pathUpdateCallback(PU_GOAL_REACHED);                // tell user
            return;                                     // done
        }   
        //  Not at goal,  
    } else if (status == PU_EVADE_HIDDEN 
            || status == PU_EVADE_SPOTTED 
            || status == PU_SLOWDOWN_DISTANCE_REACHED)
    {   pathMsg(PATH_MSG_INFO, "Misc. path update status report: " + (string)status);
        pathUpdateCallback(status);                             // tell user
        return;
    } 
    //  Not done, and not a misc. status report. Fail.
    pathMsg(PATH_MSG_WARN, "Path operation failed, status " + (string) status);
    pathStop();
    pathUpdateCallback(status);                                         // tell user
}
//
//  Useful utility functions. Optional.
//
//  pathErrMsg -- path error number to string.  Mostly for debug.
//
string pathErrMsg(integer patherr)
{   list patherrspos =[
    "Character is near current goal.",
    "Character has reached the goal.",
    "Character cannot navigate from the current location - e.g., the character is off the navmesh or too high above it.",
    "Goal is not on the navmesh and cannot be reached.",
    "Goal is no longer reachable for some reason - e.g., an obstacle blocks the path.",
    "Target (for llPursue or llEvade) can no longer be tracked - e.g., it left the region or is an avatar that is now more than about 30m outside the region.",
    "There's no good place for the character to go - e.g., it is patrolling and all the patrol points are now unreachable.",
    "An llEvade character thinks it has hidden from its pursuer.",
    "An llEvade character switches from hiding to running",
    "A fatal error reported to a character when there is no navmesh for the region. This usually indicates a server failure and users should file a bug report and include the time and region in which they received this message.",
    "Character entered a region with dynamic pathfinding disabled.",
    "A character failed to enter a parcel because it is not allowed to enter, e.g. because the parcel is already full or because object entry was disabled after the navmesh was baked."];

    list patherrsneg = [
        "Error 0", 
        "Retrying pathfinding", 
        "Pathfinding stall timeout",
        "Cannot move from current position"];
        
    if (patherr >= 0 && patherr < llGetListLength(patherrspos)) // positive numbers, defined by LL
    {   return(llList2String(patherrspos,patherr));
    } else if (-patherr < llGetListLength(patherrsneg))          // negative numbers, defined by us
    {    return(llList2String(patherrsneg, -patherr)); 
    } else {
        return("Unknown path error " + (string) patherr);       // some bogus number
    }
}