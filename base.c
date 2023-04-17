#define STRxxxxx
#ifndef STRxxxxx

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
  int32_t y;
  int64_t x;
  int32_t h;
} Gen;

void printxx(int y)
{
  printf("y: %d\n", y);
}
void print64(int64_t x)
{
  float aa = 3.0;
  const char *cc = "64: %ld x %f\n";
  printf(cc, 55, 55.0);
}

// extern Gen yy(int32_t y, Gen g);

void printfp(float x)
{
  printf("x: %f\n", x);
}

void printstr(char *str)
{
  printf("str: %s\n", str);
}

extern void printC(Gen g);

void printG(Gen g)
{
  g.y = 333;
  printf("c: y: %d, x: %lld, h: %d\n", g.y, g.x, g.h);
  Gen ha = {22, 55, 7788};
  // yy(22, ha);
  printC(ha);
}

#endif