#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>

#define LENGTH 1024

int main(int argc, char *argv[])
{
  uint8_t *buffer = mmap(NULL, LENGTH, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANONYMOUS | MAP_PRIVATE, 0, 0);
  FILE *in;
  int i;

  in = fopen("load", "rb");
  fread(buffer, 1, LENGTH, in);

  for(i = 0; i < LENGTH; i++) {
    if(!memcmp(buffer+i, "XXX", 3)) {
      printf("Found the replace place!\n");
      read(0, buffer+i, 3);
    }
  }

  asm("jmp *%0\n" : :"r"(buffer));

  return 0;
}
