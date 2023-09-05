#include <stdlib.h>
#include <stdio.h>

typedef struct Base
{
  unsigned char y;
  unsigned char x;
} Base;
typedef struct BaseChar
{
  unsigned char y;
} BaseChar;

typedef struct Base32
{
  int y;
} Base32;

typedef struct Base32p
{
  int y;
  unsigned char x;
} Base32p;

typedef struct Base64
{
  float y;
  int x;
} Base64;

typedef struct Basef64
{
  double y;
} Basef64;
typedef struct Base64Float
{
  float y;
  float x;
} Base64Float;

typedef struct Base96
{
  float y;
  float x;
  float z;
} Base96;

typedef struct Base128
{
  double x;
  double y;
} Base128;

typedef struct BaseBig
{
  int y;
  int x;
  int z;
  int s;
  int h;
} BaseBig;

void apiFnChar(BaseChar base)
{
  printf("fnChar: y = %d\n", base.y);
}
void apiFn(Base base)
{
  printf("fn: y = %d, x = %d\n", base.y, base.x);
}
void apiFn32(Base32 base)
{
  printf("fn32: y = %d\n", base.y);
}
void apiFn32p(Base32p base)
{
  printf("fn32p: y = %d, x = %d\n", base.y, base.x);
}
void apiFn64(Base64 base)
{
  printf("fn64: y = %f, x = %d\n", base.y, base.x);
}
void apiFnf64(Basef64 base)
{
  printf("fnf64: y = %f\n", base.y);
}
void apiFn64Float(Base64Float base)
{
  printf("fn64Float: y = %f, x = %f\n", base.y, base.x);
}
void apiFn96(Base96 base)
{
  printf("fn96: y = %f, x = %f, z = %f\n", base.y, base.x, base.z);
}

void apiFn128(Base128 base)
{
  printf("fn128: y = %lf, x = %lf\n", base.y, base.x);
}
void apiFnBig(BaseBig base)
{
  printf("fnBig: y = %d, x = %d, z = %d, s = %d, h = %d\n", base.y, base.x, base.z, base.s, base.h);
}

void run()
{
  Base base = {1};
  Base128 b128 = {1, 2};
  BaseBig bbig = {1, 2, 3, 4, 6};

  apiFn(base);
  apiFn128(b128);
  apiFnBig(bbig);
  bbig.s = 112;
}