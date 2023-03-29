
#include <stdio.h>

typedef struct
{
  int32_t y;
  int32_t x;
  int32_t z;
} Gen;

Gen getGen()
{
  Gen g = {10, 555, 224};
  return g;
}

extern int hhh();
extern Gen yy(int32_t y, Gen g);


int printxx(int32_t y)
{
  // int hhhx = hhh();
  // printf("hhhhh : %d\n", hhhx);
  printf("y: %d\n", y);
  return 11;
}

void strx(int y, Gen *g)
{
  printf("gen: %d %d %d\n", y, g->y, (int)sizeof(g));
}

void stra(Gen g)
{
  printf("... %d\n", g.y);
  printf("... ......\n");
  Gen ss = {301, 544442, 553};
  Gen xa =  yy(12,  ss);
  printf("gen y: %d x: %d z: %d \n", xa.y, xa.x, xa.z);

}
void ggg(Gen *g)
{
  int y = g->y;
  if( y > 10) {
    int64_t x = 10101;
  }
  printf("ggg%d,", y);
}


void hhhaa(Gen g) {
  int hxhx = g.y;
}

Gen cG() {
   Gen g =  {15,11,11};
   int y = g.z;
   return g;
}
