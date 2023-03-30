
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

extern Gen yy(int32_t y, Gen g);


int printxx(int32_t y)
{
  // int hhhx = hhh();
  // printf("hhhhh : %d\n", hhhx);
  printf("y: %d\n", y);
  return 11;
}

int printxxa(int32_t* y) {
  printf("xxa: y_p: %d\n", *y);
  *y = 50505;
  return 1;
}

void strx(int y, Gen *g)
{
  printf("gen: %d %d %d\n", y, g->y, (int)sizeof(g));
}

void stra()
{
  Gen ss = {301, 544442, 553};
 yy(12,  ss);
  // printf("gen y: %d x: %d z: %d \n", xa.y, xa.x, xa.z);

}


void hhhx(Gen g) {
  
}