#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/time.h>

#define SIZE 64

typedef union {
  float f;
  unsigned int i;
}foo;

struct timeval st[12];

int st2time (struct timeval st_) 
{
  return st_.tv_sec * 1000 * 1000 + st_.tv_usec;
}

int main(int argc, char** argv)
{
  int i, j;
  foo container;

  int flat[(SIZE/4) * (SIZE + 1)];
  int mat[SIZE/4][SIZE];
  int input[SIZE/4];
  int output[SIZE];
  int output_fpga[SIZE];

  // initialization
  FILE *fd;
  fd = fopen("./input.txt", "r");

  unsigned int a;
  i = 0;
  while ( !feof(fd) )
  {
    if (fscanf(fd, "%X", &a) != EOF)
    {
      container.i = a;
      //printf("%f %X\n", container.f, container.i);
      if (i < SIZE/4)
        input[i] = container.i;
      else
        mat[i % 16][i/16 - 1] = container.i;

      flat[i] = container.i;
      //printf("%d, %f\n", i, container.f);
      i++;
    }
  }
  fclose(fd);

  for (i = 0; i < SIZE; i++)
    output[i] = 0;

  gettimeofday (&st[0], NULL);
  // computation
  for (i = 0; i < SIZE; i++)
    for (j = 0; j < SIZE; j++)
      output[i] += ((input[(SIZE-1-j)/4] >> (8*(3-(j%4)))) % (1<<8)) * ((mat[(SIZE-1-j)/4][i] >> (8*(3-(j%4)))) % (1<<8));
  gettimeofday (&st[1], NULL);

  // FPGA offloading
  // memory load
  int foo;
  foo = open("/dev/mem", O_RDWR);
  int *ps_dram = mmap(NULL, (SIZE * (SIZE + 1))* sizeof(int), PROT_READ|PROT_WRITE, MAP_SHARED, foo, 0x10000000);

  // PRE: prepare data
  gettimeofday (&st[2], NULL);
  memcpy( ps_dram, flat, 4160 );
  /*
  for (i = 0; i < SIZE * (SIZE + 1); i++)
  {
    *(ps_dram + i) = flat[i];
  }
  */
  gettimeofday (&st[3], NULL);

  // DMA1: move
  unsigned int *fpga_dma = mmap(NULL, 16*sizeof(unsigned int), PROT_READ|PROT_WRITE, MAP_SHARED, foo, 0x7E200000);

  gettimeofday (&st[4], NULL);
  *(fpga_dma+6) = 0x10000000;
  *(fpga_dma+8) = 0xC0000000;
  *(fpga_dma+10) = 4160;
  while ((*(fpga_dma+1) & 0x00000002) == 0);
  gettimeofday (&st[5], NULL);
 
  // MV: run
  unsigned int *fpga_ip = mmap(NULL, 16*sizeof(unsigned int), PROT_READ|PROT_WRITE, MAP_SHARED, foo, 0x43C00000);

  gettimeofday (&st[6], NULL);
  *fpga_ip = 0x5555;
  while (*fpga_ip == 0x5555);
  gettimeofday (&st[7], NULL);

  // DMA2: move back
  gettimeofday (&st[8], NULL);
  *(fpga_dma+6) = 0xC0000000;
  *(fpga_dma+8) = 0x10000000;
  *(fpga_dma+10) = 256;
  while ((*(fpga_dma+1) & 0x00000002) == 0);
  gettimeofday (&st[9], NULL);

  // POST: harvest data
  gettimeofday (&st[10], NULL);
  for (i = 0; i < SIZE; i++)
    output_fpga[i] = *(ps_dram + i); 
  gettimeofday (&st[11], NULL);


  // display
  printf("%-10s%-10s%-10s%-10s\n", "index", "CPU", "FPGA", "FPGA(hex)");
  for (i = 0; i < SIZE; i++)
  {
    container.i = output_fpga[i];
    printf("%-10d%-10d%-10d%-10d\n", i, output[i], output_fpga[i], container.i);
  }

  printf("%s: %d\n", "CPU ", st2time(st[ 1]) - st2time(st[ 0]));
  printf("%s: %d\n", "PRE ", st2time(st[ 3]) - st2time(st[ 2]));
  printf("%s: %d\n", "DMA1", st2time(st[ 5]) - st2time(st[ 4]));
  printf("%s: %d\n", "MV  ", st2time(st[ 7]) - st2time(st[ 6]));
  printf("%s: %d\n", "DMA2", st2time(st[ 9]) - st2time(st[ 8]));
  printf("%s: %d\n", "POST", st2time(st[11]) - st2time(st[10]));

  close(foo);

  return 0;
}
