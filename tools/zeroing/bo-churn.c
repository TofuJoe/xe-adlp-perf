// Deterministic BO churn against xe: create and destroy N system-memory BOs of a
// known size, so page-clearing cost can be normalised per MiB instead of per call.
//   gcc -O2 -I<ktree>/include/uapi -o bo-churn bo-churn.c
//   ./bo-churn [count] [MiB]
#define _GNU_SOURCE
#include <drm/drm.h>
#include <drm/xe_drm.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec * 1e-9;
}

int main(int argc, char **argv)
{
	unsigned n = argc > 1 ? atoi(argv[1]) : 200;
	unsigned mib = argc > 2 ? atoi(argv[2]) : 8;
	int fd = open("/dev/dri/renderD128", O_RDWR);
	if (fd < 0) { perror("open"); return 1; }

	double t_create = 0, t_close = 0;
	for (unsigned i = 0; i < n; i++) {
		struct drm_xe_gem_create c = {
			.size = (unsigned long long)mib << 20,
			.placement = 1,			/* system memory instance 0 */
			.cpu_caching = DRM_XE_GEM_CPU_CACHING_WB,
		};
		double a = now();
		if (ioctl(fd, DRM_IOCTL_XE_GEM_CREATE, &c)) { perror("gem_create"); return 1; }
		double b = now();
		struct drm_gem_close g = { .handle = c.handle };
		if (ioctl(fd, DRM_IOCTL_GEM_CLOSE, &g)) { perror("gem_close"); return 1; }
		double d = now();
		t_create += b - a;
		t_close += d - b;
	}
	double gib = (double)n * mib / 1024.0;
	printf("%u x %u MiB = %.2f GiB\n", n, mib, gib);
	printf("  create: %8.1f us/BO  %7.1f us/MiB  (%.1f GB/s)\n",
	       t_create / n * 1e6, t_create / (n * (double)mib) * 1e6,
	       (double)n * mib * (1 << 20) / t_create / 1e9);
	printf("  close:  %8.1f us/BO  %7.1f us/MiB  (%.1f GB/s)\n",
	       t_close / n * 1e6, t_close / (n * (double)mib) * 1e6,
	       (double)n * mib * (1 << 20) / t_close / 1e9);
	close(fd);
	return 0;
}
