#include <stdio.h>


int vvs = 0;
void test_main()
{
  int y = 10;
  int x = 11;
}

typedef struct {
  int x;
  int y;
  int z;
} Base;

void test_base(Base base) {
  base.x = 111;

}

int main(int argc, char **argv)
{
  test_main();
  Base base = {1,2,6};
  test_base(base);
  return 0;
}
