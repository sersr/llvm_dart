#define STR
#ifndef STR

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

int printxxa(int32_t *y)
{
  printf("xxa: y_p: %d\n", *y);
  *y = 50505;
  return 1;
}

void strx(Gen *g)
{
}

void stra()
{
  Gen ss = {301, 544442, 553};
  printf("hellor");
  yy(12, ss);
  int y = 100022;
  printf("... end %d\n", y);
  // printf("gen y: %d x: %d z: %d \n", xa.y, xa.x, xa.z);
}

typedef union
{
  int32_t y;
  int32_t xx;
} Ms;

void hhhx(Gen g)
{
  Ms u = {10};
}

#else
#include <stdio.h>

typedef struct
{
  int32_t x;
  int64_t y;

} Gen;

extern void gn(Gen g);

void printxx(int y)
{
  printf("y: %d\n", y);
}
void print64(int64_t x) {
  float aa = 3.0;
  const char* cc = "64: %ld x %f\n";
  printf(cc, 55, 55.0);
}

void printfp(float x)
{
  printf("x: %f\n", x);
  Gen g = {10, 5555};
  gn(g);
}

void printstr(char *str)
{
  printf("str: %s\n", str);
}
#endif