#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>

#define LENGTH 10000

int main(int argc, char *argv[])
{
  uint8_t *buffer = mmap(NULL, LENGTH, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANONYMOUS | MAP_PRIVATE, 0, 0);
  FILE *in;
  int i;
  uint8_t replacement[3];

  in = fopen("load", "rb");
  fread(buffer, 1, LENGTH, in);
  read(0, replacement, 3);
  fclose(in);

  printf("Replacement: %x %x %x\n", replacement[0], replacement[1], replacement[2]);

  for(i = 0; i < LENGTH; i++) {
    if(!memcmp(buffer+i, "XXX", 3)) {
      printf("Found the replace place!\n");
      memcpy(buffer+i, replacement, 3);
    }
  }

  asm("jmp *%0\n" : :"r"(buffer));

  return 0;
}
