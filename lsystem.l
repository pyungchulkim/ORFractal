/* Ordered Random Fractal (ORFractal) - see description.txt for details.
 * by Pyungchul Kim, 2026
 * https://orderedrandom.com
 */

////////////////////////////////////////////////
// Control parameters to run the simulation
////////////////////////////////////////////////

#define MAX_NODES 		4000	// # of nodes to stop simulation
#define MAX_ITERATIONS 		40	// # of iteration stop simulation
#define FOR_ORSTUDIO 		1	// for ORStudio input
#define CONTOUR_SIDES 		128	// # of sides in a node contour
#define SEED 			0	// 0 for no seed setting

/* Growth types and flags - see description.txt for details */
#define GT_2D_UNIFORM		1
#define GT_2D_RANDOM		2
#define FLAG_KEEP_ANGLE		0x01	// keep the turtle angle

/* Genes for a node - dictates how it grows */
typedef struct {		
	int typeGrowth;		// type of node growth such as GROWTH_1
	int idBaseShape;	// ID for the base contour (2D) or surface (3D) 
	unsigned flags;		// bit flags 
	float p1,p2,p3,p4,p5; 	// parameters - interpreted by growth type
} Genes;

/* Genes defined. Parameters (p1,p2,...) for each growth types are as follows:
 * GT_2D_UNIFORM: prunRate, fanouts, angle, rotation, scaleFactor
 * GT_2D_RANDOM: prunRate, fanouts, angle, rotation, scaleFactor
 */
Genes genes[] = {
  /* 0 */ {GT_2D_RANDOM, 1, FLAG_KEEP_ANGLE, 0.5, 3, 120, 60, 1.0},
  /* 1 */ {GT_2D_RANDOM, 2, FLAG_KEEP_ANGLE, 0.5, 3, 120, 60, 0.8},
  /* 2 */ {GT_2D_RANDOM,  3, 0, 0.2, 3, 90, 45, 0.7}
};

/* Seeding instruction - genes id and # of its seeds */
#define SEEDING		Seeding(0, 50) \
			Seeding(1, 50)


#include <lpfgall.h>

////////////////////////////////////////////////
// Constants and macros
////////////////////////////////////////////////

/* Contours to be used. Note that the last contour in L-studio must be
 * name as "LAST_CONTOUR" so the following macro works.
 */
const int MAX_CONTOURS = LAST_CONTOUR - 1; // contour range = [0, MAX_CONTOURS)
const int MAX_COLORS = 255;		// color range = [1, MAX_COLORS]

/* Reference cube dimension */
const float CUBE_WIDTH = 4000.0;	// reference cube width
const float CUBE_HEIGHT = 3000.0;	// reference cube height
const float CUBE_DEPTH = 2000.0;	// reference cube depth

/* Useful shorthands */
#define DIM(ary)	(sizeof(ary) / sizeof(ary[0]))	// dimension of an array
#define ROUND(f)	((int)(f + 0.5f))		// simple round for positive float
#define MIN(a, b) 	(((a) < (b)) ? (a) : (b))	// pick min
#define MAX(a, b) 	(((a) > (b)) ? (a) : (b))	// pick max

/////////////////////////////////////////////////////////////
// Forward declarations of types, functions and modules
/////////////////////////////////////////////////////////////

typedef void* NodeHandle;	// generic pointer to a node

/* Common header for all node types */
typedef struct {
	int id;			// unique id of the node
	int birth;		// iteration at which the node was created
	NodeHandle pMother;	// the mother node
	int gid;		// genes id
} NodeHeader;

/* Node2D - generic structure for all nodes using 2D contour as shape */
typedef struct Node2D {
	NodeHeader header;	// common header - must be the first member
	V3f start;		// "directional relative" move to start location
	V2f direction;		// direction: x=angle, y=rotation
	int idContour;		// ID of the contour to be used
	float scale;		// scaling
	float color;		// color
} Node2D;

/* Contour data structure */
typedef struct {
	V2f vertices[CONTOUR_SIDES];	// coordinates
	V2f edges[CONTOUR_SIDES];	// edges: x=angle, y=distance
	V2f topVertex;			// top vertex
	V2f bottomVertex;		// bottom vertex
} Contour;

/* production rules for LPFG */
module Seeding(int, int);
module GrowNode(NodeHandle);

module Initialize();
module DrawNode(NodeHandle);
module DrawCube(float, float, float);

/* Other functions */
float gRandom(float mean, float sd);	// Gaussian dist random generator
float uRandom(float range);		// Uniform dist random within [-range, range)
V2f getContourCoord(int idContour, float angle); // get coordinate from a contour

/////////////////////////////////////////////////////////////
// Global variables
/////////////////////////////////////////////////////////////

int currIteration;		// current iteration number of the simulation
int nodesCreated;		// # of nodes created so far
int nodesCreatedLast;		// # of nodes created until the last iteration
Contour contours[MAX_CONTOURS];	// contour coordinates cache

/////////////////////////////////////////////////////////////
// LPFG Simulation codes
/////////////////////////////////////////////////////////////
Start: 
{
  currIteration = 0;	// current iteration no.
  nodesCreated = 0;	// # of nodes created (not drawn)
  if (SEED != 0) srand(SEED);	// set random seed
}

StartEach: 
{
  nodesCreatedLast = nodesCreated;
  Printf("Iteration: %d starts with %d nodes.\n", currIteration, nodesCreated);
}

EndEach: 
{
  // Stop simulation when either iterations have exhausted or 
  // no new nodes were created during the current iteration.
  if (currIteration >= MAX_ITERATIONS || nodesCreated == nodesCreatedLast) {
    Printf("\nSimulation ended. In total, %d nodes have been created.\n", nodesCreated);
    Stop();
  }

  currIteration++;
}

derivation length: 100000;

Axiom: 	Initialize() // Initialize data structures before production
	DrawCube(CUBE_WIDTH, CUBE_HEIGHT, CUBE_DEPTH) // reference cube
	SEEDING;

/* Seed initial nodes for the genes.
 *  gid 	- genes id 
 *  nSeeds 	- # of seeds to plant
 */
Seeding(gid, nSeeds) : 
{
  if (gid < 0 || gid >= DIM(genes)) {
    Printf("No such genes with id=%d is defined.\n", gid);
    Stop();
  }

  Genes *pGenes = &genes[gid];

  for (int i = 0; i < nSeeds; i++) {
    V3f center = V3f(0, CUBE_HEIGHT / 2, -CUBE_DEPTH / 2);
    V3f start;
    float scale = 300 + uRandom(200);
    float color;

    // Detemine the location and color of the seed node
    if (nodesCreated == 0) { // first one - put it at the vintage point
      start = center;
    } else {
      start.x = center.x + uRandom(CUBE_WIDTH / 2);
      start.y = center.y + uRandom(CUBE_HEIGHT / 2);
      start.z = center.z + uRandom(CUBE_DEPTH / 2);
    }
    color = 160; // default color - brown
    if (FOR_ORSTUDIO == 1) {  // use different colors for ORStudio
      // skipping index 0 (reserved for background by LPFG) */
      color = ran(MAX_COLORS) + 1; 
    }

    // Allocate a node and populate the node specific info
    NodeHandle pNode = NULL;

    switch (pGenes->typeGrowth) {
      case GT_2D_UNIFORM:
      case GT_2D_RANDOM: {
	Node2D *pn = new Node2D;
	pn->header.id = nodesCreated++;
	pn->header.birth = currIteration;
	pn->header.pMother = NULL;
	pn->header.gid = gid;
	pn->start = start;
	pn->direction.x = (pGenes->flags | FLAG_KEEP_ANGLE) ? 0 : ran(360);
	pn->direction.y = uRandom(pGenes->p4);
	pn->idContour = pGenes->idBaseShape;
	pn->scale = scale;
	pn->color = color;
	pNode = pn;
	break;
      }
      default: {
	Printf("THE GROWTH TYPE IS NOT IMPLEMENTED.\n");
	Stop();
	break;
      }
    }

    nproduce SB();
    nproduce GrowNode(pNode);
    nproduce EB();
  }

  Printf("Seeding(%d,%d) completed.\n", gid, nSeeds); 
  produce ;
}

/* Draw the current node and grow next nodes from it.
 *
 */
GrowNode(pNode) :
{
  // Draw the node
  nproduce DrawNode(pNode);

  if (nodesCreated >= MAX_NODES) {	// maxed out. no more growth
    produce ;
    return;
  }

  int gid = ((NodeHeader *)pNode)->gid;
  Genes *pGenes = &genes[gid];

  // Grow the node according to the growth type
  switch (pGenes->typeGrowth) {

    case GT_2D_UNIFORM:
    case GT_2D_RANDOM: {	// See Overview for details of the growth rule

      Node2D *pThis = (Node2D *)pNode;

      // pull out growth parameters specific to the growth types
      float prunRate = pGenes->p1;
      int nFanouts = pGenes->p2;
      int angle = pGenes->p3;
      float rotation = pGenes->p4;
      float scaleFactor = pGenes->p5;
      bool bKeepAngle = pGenes->flags | FLAG_KEEP_ANGLE;

      // Generate angles for fanouts
      float *fanouts = new float[nFanouts];
      switch (pGenes->typeGrowth) {
	case GT_2D_UNIFORM: {	// equally distribute at [-angle, angle]
	  float curr = (nFanouts == 1) ? 0 : -angle;
	  float delta = (nFanouts == 1) ? 360 : (2 * angle) / (nFanouts - 1);
	  for (int i = 0; i < nFanouts; i++, curr += delta) {
	    fanouts[i] = curr;
	  }
	  break;
	}
	default:
	case GT_2D_RANDOM: {	// randomly distribute at [-angle, angle]
	  for (int i = 0; i < nFanouts; i++) {
	    fanouts[i] = ran(2 * angle) - angle;
	  }
	  break;
	}
      }

      // Generate new node at the fanouts
      for (int i = 0; i < nFanouts; i++) {
	if (ran(1.0) < prunRate)
	  continue;	// prun (skip) it

	// get the coordinate of the contour at the angle
	V2f v = getContourCoord(pThis->idContour, fanouts[i]) * pThis->scale;

	Node2D *pn = new Node2D;
	pn->header.id = nodesCreated++;
	pn->header.birth = currIteration;
	pn->header.pMother = pThis;
	pn->header.gid = gid;
	pn->start = V3f(v.x, v.y, 0);
	pn->direction = V2f((bKeepAngle) ? 0 : fanouts[i], uRandom(rotation));
	pn->idContour = pThis->idContour;
	pn->scale = pThis->scale * (scaleFactor + uRandom(scaleFactor * 0.3));
	pn->color = (pThis->color == MAX_COLORS) ? 1 : pThis->color + 1;

	nproduce SB();
	nproduce GrowNode(pn);
	nproduce EB();
      }
      delete fanouts;
      break;
    } // GT_2D_UNIFORM, GT_2D_RANDOM

    default: {
      Printf("THE GROWTH TYPE IS NOT IMPLEMENTED.\n");
      Stop();
      break;
    }
  }
  
  produce ;	// done with the node
}

/* TRICK: I need to populate the contour coordinates before any productions
 * so my node growth algorithm can use the coordinates.
 * However, those coordinates are available only at interpretation stage.
 * Having a query such as GetPos() at predecessor of a rule triggers
 * interpretation stage prior to production.
 */
GetPos(x,y,z) : { }

/* Rules to interpret the production to draw */

interpretation:

/* Initialize the interpretation phase in terms of preparing
 * data structure to be re-used for other interpretation modules
 */
Initialize() : {

  nproduce SB();

  // Load the node contour vectors
  for (int i = 0; i < MAX_CONTOURS; i++) {

    int nSides = DIM(contours[i].vertices);
    int cid = i + 1;	// contour id in LPFG starts from 1 
    nproduce CurrentContour(cid);
    nproduce ContourSides(255);	// set the sides highest to read in

    // find the bottom position of the contour
    float topY = -1e9;
    float bottomY = 1e9;
    float topL = 0;
    float bottomL = 0;
    for (int s = 0; s < nSides; s++) {
      float t = (float)s / nSides;
      V2f v = curveXY(cid, t);
      if (v.y > topY) {
	topY = v.y;
	topL = t;
      }
      if (v.y < bottomY) {
	bottomY = v.y;
	bottomL = t;
      }
    }

    // topL/bottomL now has the arc length of top/bottom of the node contour.
    contours[i].topVertex = curveXY(cid, topL);
    contours[i].bottomVertex = curveXY(cid, bottomL);

    // re-read and cache the contour vertices starting from the bottom
    // and adjust the coordinates relative to the bottom
    for (int s = 0; s < nSides; s++) {
      float t = bottomL + (float)s / nSides;
      if (t >= 1.0) t -= 1.0;	// circular
      V2f v = curveXY(cid, t);
      v -= contours[i].bottomVertex;	// relative to the bottom
      contours[i].vertices[s] = v;
    }

    // populate node edges from the vertices so we can use turtle
    // (Left(a) f(l)) to draw the contour.
    // note that f(l) is relative to the current direction/position.
    float pa = 90;		// previous angle relative to hypot()
    for (int s = 0; s < nSides; s++) {
      int ns = (s == nSides - 1) ? 0 : (s + 1); // next vertex index
      V2f d = contours[i].vertices[ns] - contours[i].vertices[s];
      float a = atan2(d.y, d.x) * (180.0 / M_PI);	// angle
      contours[i].edges[s].x = a - pa;	// relative to previous angle
      contours[i].edges[s].y = hypot(d.y, d.x);	// distance
      pa = a;
    }
  }

  produce EB();
}

/* Draw the node with the direction and shape information. */
DrawNode(pNode) : 
{
  Genes *pGenes = &genes[((NodeHeader *)pNode)->gid];

  // Draw the node according to the growth type
  switch (pGenes->typeGrowth) {

    case GT_2D_UNIFORM:
    case GT_2D_RANDOM: {	// Use contour to draw the shape

      Node2D *pThis = (Node2D *)pNode;

      // Make a directional relative move to the start position.
      nproduce Right(90) g(pThis->start.x)
	       Left(90) g(pThis->start.y)
	       Up(90) g(pThis->start.z)
	       Up(-90);

      // Set the direction and color.
      nproduce Left(pThis->direction.x) RollR(pThis->direction.y)
	       SetColor(pThis->color);

      // Start the polygon. Make sure the polygon to be enclosed in a block
      // so the initial turtle direction remains unchanged.
      nproduce SB() SP();

      int ci = pThis->idContour;
      int nSides = DIM(contours[ci].edges);
      for (int i = 0; i < nSides; i++) {
	float l = contours[ci].edges[i].y * pThis->scale;
	nproduce Left(contours[ci].edges[i].x) f(l);
      }

      produce EP() EB();
      break;
    }

    default: {
      Printf("THE GROWTH TYPE IS NOT IMPLEMENTED.\n");
      Stop();
      break;
    }
  }
}

/* circular rod (cylinder) *
L(l) --> [&(90)@c] F(l) [&(90)@c]
*/

/* Draw the reference cube with width, height and depth */
DrawCube(w,h,d) : 
{
  if (FOR_ORSTUDIO != 1) {
    nproduce SB()SetWidth(5)SetColor(255)
		 SB()MoveTo(w/2,0,0)F(h)Left(90)F(w)Left(90)F(h)Left(90)F(w)EB()
		 SB()MoveTo(w/2,0,-d)F(h)Left(90)F(w)Left(90)F(h)Left(90)F(w)EB()
		 SB()Down(90)MoveTo(-w/2,0,0)F(d)MoveTo(-w/2,h,0)F(d)MoveTo(w/2,h,0)F(d)MoveTo(w/2,0,0)F(d)EB()
	     EB();
  }
  produce ;
}

////////////////////////////////////////////////
// My Own Functions
////////////////////////////////////////////////

/* Gaussian distribution random number using Box-Muller transformation. */
float gRandom(float mean, float sd)
{
  // Two independent uniform random variables between 0 and 1
  float u1 = ran(1.0);
  if (u1 < 1e-9) u1 = 1e-9;
  float u2 = ran(1.0);

  // Box-Muller transform formula
  float z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
    
  // Scale by standard deviation and shift by mean
  return z0 * sd + mean;
}

/* Uniform distribution random number ranging [-range, range) */
float uRandom(float range)
{
  return ran(range * 2) - range;
}

/* Get the coordinate of the contour at the given angle.
 * LPFG contour interface only allows to get coordinate by arc length,
 * which is not exactly proportional to angle. However, I assume that
 * this is good approximation.
 * Also, note that the angle 0 indicates the top of the contour and
 * it grows counterclockwise while the contour array starts at the bottom of
 * the counter and grows clockwise.
 */
V2f getContourCoord(int idContour, float angle)
{
  int nSides = DIM(contours[idContour].vertices);
  angle += 180;	// adjust the angle to start at the bottome and counterclockwise 
  int i = (int)(nSides * (1 - angle / 360)) - 1; // index of the vertex at the angle
  
  // Cap the index within the valid range
  i = MIN(i, nSides - 1); i = MAX(i, 0);
  return contours[idContour].vertices[i];
}

