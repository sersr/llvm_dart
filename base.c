#include <stdio.h>
#include <stdlib.h>

int vvs = 0;
void test_main()
{
  int y = 10;
  int x = 11;
}

typedef struct
{
  int x;
  int y;
  int z;
} Base;

typedef struct {
  int x;
} BaseC;
BaseC hh()
{
  BaseC b = {1};
  return b;
}

void test_base(Base base)
{
  base.x = 111;
}

char *global = "hello world";

int main(int argc, char **argv)
{
  test_main();
  Base base = {1, 2, 6};
  test_base(base);
  BaseC xa = hh();
  printf("字符串分开的两种形式 ");
  return 0;
}
