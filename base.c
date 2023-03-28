
#include <stdio.h>

extern int hhh();
typedef struct
{
  int32_t y;
  int32_t x;
  int32_t z;
} Gen;

int printxx(int32_t y)
{
  int hhhx = hhh();
  printf("hhhhh : %d\n", hhhx);
  printf("y: %d\n", y);
  return 11;
}

void strx(int y, Gen *g)
{
  printf("gen: %d, %d %d %d %d\n", y, g->y, g->x, g->z, (int)sizeof(g));
}

void stra(Gen g)
{
  printf("... %d\n", g.z);
}
void ggg(Gen *g)
{
  int y = g->y;
  printf("ggg%d,", y);
  int x = g->x;
  printf("ggg: %d, %d\n", y, x);
}

Gen getGen()
{
  Gen g = {10, 50};
  return g;
}

void hhhaa(Gen g) {
  int hxhx = g.y;
}