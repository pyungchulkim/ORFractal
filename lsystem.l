/* Ordered Random Fractal (ORFractal) - see description.txt for details.
 * by Pyungchul Kim, 2026
 * https://orderedrandom.com
 */

#include <lpfgall.h>
#include <GL/gl.h>

////////////////////////////////////////////////
// Control parameters to run the simulation
////////////////////////////////////////////////

#define MAX_NODES 		4000	// # of nodes to stop simulation
#define MAX_ITERATIONS 		4	// # of iteration stop simulation
#define FOR_ORSTUDIO 		0	// for ORStudio input
#define CONTOUR_SIDES 		128	// # of sides in a node contour
#define SEED 			0	// 0 for no seed setting
#define MODE_CONTOUR		0	// non-zero for contour-only drawing
#define MODE_TRANSPARENT	1	// non-zero for transparent colors

/* Growth types and flags - see description.txt for details */
#define GT_2D			1	// grow in 2D
#define F_RESERVED1		0x01
#define F_UNIFORM		0x02	// uniform or random fanout (default)
#define F_HEAD_KEEP		0x04	// head angle: keep the same as mother
#define F_HEAD_RANDOM		0x08	// or random, or align (default)
#define F_RESERVED2		0x10	// reserved
#define F_RESERVED3		0x20	// reserved

/* Genes for a node - dictates how it grows */
typedef struct {		
	int typeGrowth;		// type of node growth such as GROWTH_1
	int idBaseShape;	// ID for the base contour (2D) or surface (3D) 
	unsigned flags;		// bit flags 
	float p1,p2,p3,p4,p5;	// parameters - interpreted by growth type
	float p6,p7;
} Genes;

/* Genes defined. Parameters (p1,p2,...) for each growth types are as follows:
 * GT_2D: prun, fanouts, angle, rotation, scale, gap, color
 */
Genes genes[] = {
  /* 0 */ {GT_2D, 0, F_HEAD_KEEP, 0.5, 3, 170, 60, 0.8, 0.5, 0},
  /* 1 */ {GT_2D, 1, F_HEAD_KEEP, 0.5, 3, 170, 60, 0.8, 1.5, 0},
  /* 2 */ {GT_2D, 2, F_HEAD_KEEP, 0.5, 3, 170, 60, 0.8, 1.5, 0},
  /* 3 */ {GT_2D, 3, F_HEAD_KEEP, 0.5, 3, 170, 60, 0.8, 1.0, 0},
  /* 4 */ {GT_2D, 4, F_HEAD_KEEP, 0.5, 3, 170, 60, 0.8, 1.0, 0},
  /* 5 */ {GT_2D, 5, F_HEAD_KEEP, 0.5, 3, 170, 40, 0.8, 1.5, 0},
  /* 6 */ {GT_2D, 6, F_HEAD_KEEP, 0.5, 3, 170, 40, 0.8, 1.5, 0},
  /* 7 */ {GT_2D, 3, 0, 0.2, 3, 90, 45, 0.7}
};

/* Seeding instruction - genes id and # of its seeds within the range */
#define SEEDING		\
			Seeding(0, 0, 10, 300, 800) \
			Seeding(0, 3, 10, 300, 800)

#define SEED_COVERAGE	0.5

/* Macros for genes parameters just for readability */
#define P_PRUN_RATE	p1
#define P_FANOUTS	p2
#define P_ANGLE		p3
#define P_ROTATION	p4
#define P_SCALE_RATE	p5
#define P_GAP_RATE	p6
#define P_COLOR		p7

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
	int color;		// color
} Node2D;

/* Contour data structure - it holds all vertices and edges as well as
 * the map to locate a vertex at a degree of [0, 360). Note that
 * (1) the degree grows counter-clock wise from the top;
 * (2) the edge vector is relative to its previous edge, assuming it started
 *     at edges[0] with degree 0 (straight-up direction) 
 */
typedef struct {
	V2f vertices[CONTOUR_SIDES];	// coordinates
	V2f edges[CONTOUR_SIDES];	// edges: x=angle, y=distance
	int angleToVertices[360];	// map from angle (int) to vertex id
} Contour;

/* production rules for LPFG */
module Seeding(int, int, int, float, float);
module GrowNode(NodeHandle);

module Initialize();
module DrawNode(NodeHandle);
module DrawCube(float, float, float);

/* Other functions */
float gRandom(float mean, float sd);	// Gaussian dist random generator
float uRandom(float range);		// Uniform dist random within [-range, range)
V2f getContourCoord(int idContour, float angle); // get coordinate from a contour
V2f rotateVector(V2f &vec, float degrees); // rotate a vector

/////////////////////////////////////////////////////////////
// Global variables
/////////////////////////////////////////////////////////////

int currIteration;		// current iteration number of the simulation
int nodesCreated;		// # of nodes created so far
int nodesCreatedLast;		// # of nodes created until the last iteration
Contour contours[MAX_CONTOURS];	// contour coordinates cache

/* OpenGL functions entry */
extern "C" { __attribute__((__stdcall__)) void* wglGetProcAddress(const char*); }
typedef void (__attribute__((__stdcall__)) *PFNGLBLENDEQUATIONPROC)(unsigned int mode);

PFNGLBLENDEQUATIONPROC glBlendEquation = NULL;

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
 *  startIter	- starting iteration (delay)
 *  gid 	- genes id 
 *  nSeeds 	- # of seeds to plant
 *  scaleMin, scaleMax - the coverage from the center of the reference cube
 */
Seeding(startIter, gid, nSeeds, scaleMin, scaleMax) : 
{
  if (startIter > currIteration) return;	// wait until the starting iteration

  if (gid < 0 || gid >= DIM(genes)) {
    Printf("Invalid gid: %d.\n", gid);
    Stop();
  }

  Genes *pGenes = &genes[gid];

  for (int i = 0; i < nSeeds; i++) {
    V3f center = V3f(0, CUBE_HEIGHT / 2, -CUBE_DEPTH / 2);
    V3f start;
    float scale = scaleMin + ran(scaleMax - scaleMin);

    // Detemine the location and color of the seed node
    if (nodesCreated == 0) { // first one - put it at the vintage point
      start = center;
    } else {
      start.x = center.x + uRandom(CUBE_WIDTH / 2 * SEED_COVERAGE);
      start.y = center.y + uRandom(CUBE_HEIGHT / 2 * SEED_COVERAGE);
      start.z = center.z + uRandom(CUBE_DEPTH / 2 * SEED_COVERAGE);
    }

    // Allocate a node and populate the node specific info
    NodeHandle pNode = NULL;

    switch (pGenes->typeGrowth) {
      case GT_2D:
      {
	Node2D *pn = new Node2D;
	pn->header.id = nodesCreated++;
	pn->header.birth = currIteration;
	pn->header.pMother = NULL;
	pn->header.gid = gid;
	pn->start = start;
	pn->direction.x = (pGenes->flags & F_HEAD_KEEP) ? 0 : ran(360);
	pn->direction.y = uRandom(pGenes->P_ROTATION);
	pn->idContour = pGenes->idBaseShape;
	pn->scale = scale;
	pn->color = pGenes->P_COLOR;
	if (pn->color == 0)	// unspecified. random pick
	  pn->color = ran(MAX_COLORS) + 1;
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

    case GT_2D: {

      Node2D *pThis = (Node2D *)pNode;

      // pull out growth parameters specific to the growth types
      float prunRate = pGenes->P_PRUN_RATE;
      int nFanouts = pGenes->P_FANOUTS;
      int angle = pGenes->P_ANGLE;
      float rotation = pGenes->P_ROTATION;
      float scaleRate = pGenes->P_SCALE_RATE;

      // Generate angles for fanouts
      float *fanouts = new float[nFanouts];
      if (pGenes->flags & F_UNIFORM) {	// equally distribute at [-angle, angle]
	float curr = (nFanouts <= 1) ? 0 : -angle;
	float delta = (nFanouts <= 1) ? 360 : (2 * angle) / (nFanouts - 1);
	for (int i = 0; i < nFanouts; i++, curr += delta) {
	  fanouts[i] = curr;
	}
      } else {  // randomly distribute at [-angle, angle]
	for (int i = 0; i < nFanouts; i++) {
	  fanouts[i] = ran(2 * angle) - angle;
	}
      }

      // Generate new node at the fanouts
      for (int i = 0; i < nFanouts; i++) {
	if (ran(1.0) < prunRate)
	  continue;	// prun (skip) it

	Node2D *pn = new Node2D;
	pn->header.id = nodesCreated++;
	pn->header.birth = currIteration;
	pn->header.pMother = pThis;
	pn->header.gid = gid;

	// set the direction and rotation of the node
	if (pGenes->flags & F_HEAD_KEEP)
	  pn->direction.x = 0;	 // no change: head angle the same as mother
	else if (pGenes->flags & F_HEAD_RANDOM)
	  pn->direction.x = ran(360);	// head to random direction
	else
	  pn->direction.x = fanouts[i];	// head along the fanout angle
	pn->direction.y = uRandom(rotation);

	pn->idContour = pThis->idContour;
	pn->scale = pThis->scale * (scaleRate + uRandom(scaleRate * 0.3));
	pn->color = pGenes->P_COLOR;
	if (pn->color == 0)	// unspecified. advance to the next color
	  pn->color = (pThis->color == MAX_COLORS) ? 1 : pThis->color + 1;

	// Calculate the center coordinate of the new node.
	// The gap is distance between v1 and v2 where v1 is a vertex of
	// mother node and v2 is a vertex of the new node, and the line
	// connecting v1, v2 are the same line connecting the centers of the
	// two nodes. The gap in general indicates the gap between
	// the mother node and the new node contours.

	V2f v1 = getContourCoord(pThis->idContour, fanouts[i]) * pThis->scale;
	float gapRate = pGenes->P_GAP_RATE + uRandom(pGenes->P_GAP_RATE * 0.3);
	V2f v2 = v1 * (1 + gapRate);	// move by gap rate
	float d2 = 180 + fanouts[i] - pn->direction.x;
	V2f v3 = getContourCoord(pThis->idContour, d2) * pn->scale;
	V2f vc = v2 - rotateVector(v3, pn->direction.x); // the center of the new node
	pn->start = V3f(vc.x, vc.y, 0);

	nproduce SB();
	nproduce GrowNode(pn);
	nproduce EB();
      }
      delete fanouts;
      break;
    } // GT_2D

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
GetPos(x, y, z) : { }

/* Rules to interpret the production to draw */

interpretation:

/* Initialize the interpretation phase in terms of setting the environment
 * and preparing data structure to be re-used for other interpretation modules
 */
Initialize() : 
{
  // Use low-level OpenGL directly to set up blending mode
  // to simulate pigment mixing when in the transparent mode.
  if (MODE_TRANSPARENT) {
    if (!glBlendEquation) {	// load glBlendEquation()
      glBlendEquation = (PFNGLBLENDEQUATIONPROC)wglGetProcAddress("glBlendEquation");
    }
    if (glBlendEquation) {	// simulate pigment mixing
      glEnable(GL_BLEND);
      glBlendEquation(0x8006 /*=GL_FUNC_ADD*/);
      glBlendFunc(GL_DST_COLOR, GL_ZERO);
    }
  }

  nproduce SB();

  // Load the node contour vectors
  for (int i = 0; i < MAX_CONTOURS; i++) {

    int nSides = DIM(contours[i].vertices);
    int cid = i + 1;	// contour id in LPFG starts from 1 
    nproduce CurrentContour(cid);
    nproduce ContourSides(255);	// set the sides highest to read in

    // Load and cache the contour vertices
    for (int s = 0; s < nSides; s++) {
      float t = (float)s / nSides;
      V2f v = curveXY(cid, t);
      contours[i].vertices[s] = curveXY(cid, t);
    }

    // Populate node edges from the vertices so we can use turtle
    // (Left(a) f(l)) to draw the contour.
    // Note that f(l) is relative to the current direction/position.
    // Also note that the edges needs to be plotted sequentially from
    // 0-th edge with straight up turtle (90-degree in hypot() world).
    float pa = 90;		// previous angle relative to hypot()
    for (int s = 0; s < nSides; s++) {
      int ns = (s == nSides - 1) ? 0 : (s + 1); // next vertex index
      V2f d = contours[i].vertices[ns] - contours[i].vertices[s];
      float a = atan2(d.y, d.x) * (180.0 / M_PI);	// angle
      contours[i].edges[s].x = a - pa;	// relative to previous angle
      contours[i].edges[s].y = hypot(d.y, d.x);	// distance
      pa = a;
    }

    // Populate angletoVertices for direct look up a vertice by angle later 
    // Note that the angle grows counterclockwise from the top
    float *angles = new float[nSides];
    for (int s = 0; s < nSides; s++) {
      V2f v = contours[i].vertices[s];
      angles[s] = atan2(v.y, v.x) * (180.0 / M_PI); // angle in [-180, 180)
      angles[s] -= 90;	// adjust it so the top is angle 0.
    }
    for (int a = 0; a < DIM(contours[i].angleToVertices); a++) {
      // locate the vertex closest to angle a
      float min = 1e9;
      int mv = -1;
      for (int s = 0; s < nSides; s++) {
	float d = abs(fmod(angles[s] + 360.0, 360.0) - a);
	if (d < min) {
	  min = d;
	  mv = s;
	}
      }
      contours[i].angleToVertices[a] = mv;
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

    case GT_2D: {	// Use 2D contour to draw the shape

      Node2D *pThis = (Node2D *)pNode;
      int ci = pThis->idContour;

      // Make a directional relative move to the new center position.
      nproduce Right(90) g(pThis->start.x)
	       Left(90) g(pThis->start.y)
	       Up(90) g(pThis->start.z)
	       Up(-90);

      // Set the direction and color
      nproduce Left(pThis->direction.x) RollR(pThis->direction.y)
	       SetColor(pThis->color);

      // Start the polygon. Make sure the polygon to be enclosed in a block
      // so the turtle center location and direction remain unchanged.
      nproduce SB();

      // Move to the first (starting) vertex location.
      V2f start = contours[ci].vertices[0] * pThis->scale;
      nproduce Right(90) g(start.x) Left(90) g(start.y);

      // Draw the contour lines
      if (MODE_CONTOUR) {
	nproduce SetWidth(5);
	int nSides = DIM(contours[ci].edges);
	for (int i = 0; i < nSides; i++) {
	  float l = contours[ci].edges[i].y * pThis->scale;
	  nproduce Left(contours[ci].edges[i].x) F(l);
	}
      }
      else {
	nproduce SP();
	int nSides = DIM(contours[ci].edges);
	for (int i = 0; i < nSides; i++) {
	  float l = contours[ci].edges[i].y * pThis->scale;
	  nproduce Left(contours[ci].edges[i].x) f(l);
	}
	nproduce EP();
      }

      produce EB();
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
    nproduce SB()SetWidth(5)SetColor(15)
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
 */
V2f getContourCoord(int idContour, float angle)
{
  int ai = fmod(angle + 360.0, 360.0);  // map it to [0, 360)
  int vi = contours[idContour].angleToVertices[ai];
  return contours[idContour].vertices[vi];
}

/* Rotate a vector counterclockwise
 */
V2f rotateVector(V2f& vec, float degrees)
{
  // 1. Convert degrees to radians
  float radians = degrees * (M_PI / 180.0);
  float cosTheta = std::cos(radians);
  float sinTheta = std::sin(radians);

  // 2. Apply rotation formulas
  V2f rotated;
  rotated.x = vec.x * cosTheta - vec.y * sinTheta;
  rotated.y = vec.x * sinTheta + vec.y * cosTheta;

  return rotated;
}