// Zero memory for N seconds in the given mode; print total bytes cleared.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#define SZ (64u << 20)
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec*1e-9;}
int main(int argc,char**argv){
	char*p; if(posix_memalign((void**)&p,4096,SZ))return 1; memset(p,1,SZ);
	int chunk = argc>1 && !strcmp(argv[1],"chunk4k");
	double end = now() + atof(argv[2]); unsigned long long bytes=0;
	while(now()<end){
		asm volatile("" :: "r"(p) : "memory");
		if(chunk) for(size_t o=0;o<SZ;o+=4096) memset(p+o,0,4096);
		else memset(p,0,SZ);
		asm volatile("" :: "r"(p) : "memory");
		bytes+=SZ;
	}
	printf("%llu\n",bytes); free(p); return 0;
}
