//
//   pathbuildutils.lsl -- components of a path building system
//
//   Part of a system for doing pathfinding in Second Life
//
//   Animats
//   June, 2019
//
//
//  Constants
//
integer CASTRAYRETRIES = 10;                                // retry up to 10 times
float CASTRAYRETRYDELAY = 0.200;                            // if a problem, retry slowly
#define INFINITY ((float)"inf")                             // is there a better way?
float GROUNDCLEARANCE = 0.05;                               // avoid false ground collisions
float MAXAVOIDMOVE = 8.0;                                   // max distance to avoid obstacle
//
//  
//
//  distpointtoline -- point to line distance, infinite line
//
//  Formula from geomalgorithms.com
//
float distpointtoline(vector p, vector p0, vector p1)
{
     vector v = p1 - p0;                // the line
     vector w = p - p0;                 
     float c1 = w*v;
     float c2 = v*v;                    // length squared
     vector pb;
     if (c2 > 0.00001)                  // nonzero line length
     {  float b = c1 / c2;              // would divide by 0 for null line
        pb = p0 + b * v;                // closest point on line to p
     } else {
        pb = p0;                        // zero length line case
     }
     return (llVecMag(p, pb));          // return distance
}
//
//  rotperpenonground  -- rotation to get line on ground perpendicular to vector
//
//  Used to construct the end lines of path segments.
//
rotation rotperpenonground(vector p0, vector p1)
{
    vector dir = llVecNorm(p1-p0);                          // direction for line
    rotation azimuthrot = llRotBetween(<1,0,0>, llVecNorm(<dir.x, dir.y, 0>));
    rotation elevrot = llRotBetween(llVecNorm(<dir.x, dir.y, 0>), dir); // elevation
    return(azimuthrot * elevrot);                           // apply in proper order
}
//
//  castray -- llCastRay with retry
//
//  llCastRay can fail under overload. This is rare, but we have to retry.
//
list castray(vector p0, vector p1, list params)
{
    ////llOwnerSay("Cast ray: " + (string)p0 + " " + (string)p1);   // ***TEMP***
    integer tries = CASTRAYRETRIES;                         // number of retries
    list castresult = [];
    while (tries-- > 0)
    {   castresult = llCastRay(p0, p1, params);             // try cast ray
        if (llList2Integer(castresult,-1) >= 0)             // if good status
        {   return(castresult); }                           // non-error, return
        llOwnerSay("Cast delayed: " + (string) llList2Integer(castresult,-1));  // ***TEMP***
        llSleep(CASTRAYRETRYDELAY);                         // error, wait and retry
    }
    //  Too many retries, give up
    return(castresult);                                     // return final failure
}
//
//  castbeam -- do multiple llCastRay operations to check if way is clear for movement
//
//  Returns distance, or INFINITY if no obstacle found, or negative of status code if error.
//  Ignores hits with walkable objects, so this is for horizontal scans only.
//
//  Minimum value of probecnt is 2.
//
float castbeam(vector p0, vector p1, float width, float height, float probecnt, integer wantnearest)
{   float yoffset;                                          // cast ray offset, Y dir in coords of vector
    float zoffset;                                          // cast ray offset, Z dir in coords of vector
    float nearestdist = INFINITY;                           // closest hit 
    if (probecnt < 2) { return(-4); }                       // Bad call
    vector dir = llVecNorm(p1-p0);                          // direction of raycast                     
    vector endoffsetdir = <0,1,0>*rotperpenonground(p0,p1);    // offset for horizontal part of scan
    ////llOwnerSay("End offset dir: " + (string)endoffsetdir);  // ***TEMP***
    for (yoffset = -width * 0.5; yoffset <= width * 0.5 + 0.001; yoffset += width/(probecnt-1))
    {   for (zoffset = GROUNDCLEARANCE; zoffset <= height  + 0.001; zoffset += (height - GROUNDCLEARANCE)/(probecnt-1))
        {   ////llOwnerSay("p0: " + (string)p0 + "  p1: " + (string)p1 + "  zoffset: " + (string)zoffset); // ***TEMP***
            vector yadjust = yoffset*endoffsetdir;          // offset for scan crosswise to path
            list castresult = castray(<p0.x, p0.y, p0.z+zoffset>+yadjust, <p1.x, p1.y, p1.z + zoffset>+yadjust, []);
            integer status = llList2Integer(castresult, -1);// status is last element in list
            if (status < 0)
            {   llOwnerSay("Cast ray status: " + (string)status);
                return((integer)status);                    // fails       
            }
            if (status > 0) { 
                vector hitpt = llList2Vector(castresult, 1); // get point of hit
                key hitobj = llList2Key(castresult, 0);     // get object hit
                list details = llGetObjectDetails(hitobj, [OBJECT_PATHFINDING_TYPE]);
                integer pathfindingtype = llList2Integer(details,0);    // get pathfinding type
                if (pathfindingtype != OPT_WALKABLE)        // if it's not a walkable
                {   float dist = (hitpt-p0) * dir;          // distance to hit
                    if (!wantnearest)                       // if don't need nearest
                    {   return(dist); }                     // just return first
                    if (dist < nearestdist)                 // save closest hit point
                    {   nearestdist = dist; }
                }
            }          
        }
    }
    return(nearestdist);   // no obstacles
}
//
//  obstaclecheckpath  -- is path obstacle-free?
//
//  Does both a ray check and a llGetStaticPath check.
//
integer obstaclecheckpath(vector p0, vector p1, float width, float height, integer chartype)
{
    float disttohit = castbeam(p0, p1, width, height, TESTPOINTS, FALSE);
    if (disttohit != INFINITY)
    {   ////llOwnerSay("Obstacle check path from " + (string)p0 + " " + (string)p1 + " hit at " + (string)(p0 + llVecNorm(p1-p0)*disttohit));
        return(FALSE);
    }
#ifdef TEMPTURNOFF // need to check for redundant collinear points
    list path = llGetStaticPath(p0,p1,width*0.5, [CHARACTER_TYPE, CHARTYPE]);
    integer status = llList2Integer(path,-1);                   // last item is status
    if (status != 0 || llGetListLength(path) != 3)
    {   llOwnerSay("Path static check failed for " + (string)p0 + " to " + (string)p1 + ": " + llDumpList2String(path,","));
        return(FALSE);
    }
#endif // TEMPTURNOFF   
    return(TRUE);                                               // success
}
//
//  simpleobstacletrypath -- try one path for simple obstacle avoidance
//
list simpleobstacletrypath(vector p0, vector p1, float width, float height, integer chartype, float offset)
{
    vector sidewaysdir = <0,1,0>*rotperpenonground(p0,p1);      // offset for horizontal part of scan
    vector interp0 = p0 + sidewaysdir*offset;                   // first intermediate point, sideways move
    vector interp1 = p1 + sidewaysdir*offset;                   // second intermediate point
    ////llOwnerSay("try path, offset: " + (string) offset + "  " + (string) interp0 + " " + (string)interp1);
    if (!obstaclecheckpath(p0, interp0, width, height, chartype)) { return([]);} // fail
    if (!obstaclecheckpath(interp0, interp1, width, height, chartype)) { return([]);} // fail
    if (!obstaclecheckpath(interp1, p1, width, height, chartype)) { return([]);} // fail
    return([p0, interp0, interp1, p1]);                         // success, return new path
}

//
//  simpleobstacleavoid  -- simple planner to get around simple obstacles
//
//  This just tries a sideways move, then a forward move, then a sideways move back to the end point.
//
//  Worth trying before bringing up the heavy machinery of A*
//
//  p0 must be in clear space and clear for a "width" circle around p0.
//
list simpleobstacleavoid(vector p0, vector p1, float width, float height, integer chartype)
{
    vector sidewaysdir = <0,1,0>*rotperpenonground(p0,p1);      // offset for horizontal part of scan
    float rightmax = castbeam(p0, p0+sidewaysdir*MAXAVOIDMOVE, width, height, TESTPOINTS, TRUE); // max dist to scan to right 
    float leftmax = castbeam(p0, p0-sidewaysdir*MAXAVOIDMOVE, width, height, TESTPOINTS, TRUE);  // max dist to scan to right 
    float offsetlim = MAXAVOIDMOVE;
    float maxoffset = rightmax;
    if (leftmax > maxoffset) { maxoffset = leftmax; }
    if (maxoffset > MAXAVOIDMOVE) { maxoffset = MAXAVOIDMOVE; } // bound range to search
    float offset;
    //  Linear search. Expensive. Consider making bigger moves, then smaller ones.
    for (offset = 0.0; offset <= maxoffset + 0.001; offset += width)   // all offsets to try
    {   
        if (offset <= rightmax)
        {   list avoidpath = simpleobstacletrypath(p0, p1, width, height, chartype, offset); // try avoiding obstacle by going right
            if (llGetListLength(avoidpath) > 0) { return(avoidpath); }  // alternate route found
        }
        if (offset <= leftmax)
        {   list avoidpath = simpleobstacletrypath(p0, p1, width, height, chartype, -offset); // try avoiding obstacle by going right
            if (llGetListLength(avoidpath) > 0) { return(avoidpath); }  // alternate route found
        }
    }
    return([]);                                                         // no route found
}
