// Measure achievable zeroing bandwidth on this CPU, at the granularities the
// kernel actually uses (4 KiB per clear_highpage) vs large contiguous fills.
#define _GNU_SOURCE
#include <immintrin.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define SZ (64u << 20)
#define ITER 20

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec * 1e-9;
}

static void fill_memset(char *p, size_t n) { memset(p, 0, n); }

static void fill_memset_4k(char *p, size_t n)
{
	for (size_t o = 0; o < n; o += 4096)
		memset(p + o, 0, 4096);
}

static void fill_nt(char *p, size_t n)
{
	__m256i z = _mm256_setzero_si256();
	for (size_t o = 0; o < n; o += 128) {
		_mm256_stream_si256((__m256i *)(p + o), z);
		_mm256_stream_si256((__m256i *)(p + o + 32), z);
		_mm256_stream_si256((__m256i *)(p + o + 64), z);
		_mm256_stream_si256((__m256i *)(p + o + 96), z);
	}
	_mm_sfence();
}

static void fill_nt_4k(char *p, size_t n)
{
	for (size_t o = 0; o < n; o += 4096)
		fill_nt(p + o, 4096);
}

static void fill_movdir64b(char *p, size_t n)
{
	char src[64] __attribute__((aligned(64))) = { 0 };
	for (size_t o = 0; o < n; o += 64)
		__builtin_ia32_movdir64b(p + o, src);
	_mm_sfence();
}

static void bench(const char *name, void (*fn)(char *, size_t), char *p, size_t n)
{
	fn(p, n); // warm
	double best = 1e9;
	for (int i = 0; i < ITER; i++) {
		double t0 = now();
		fn(p, n);
		double d = now() - t0;
		if (d < best) best = d;
	}
	printf("  %-22s %6.1f GB/s   (6 MiB would take %5.0f us)\n",
	       name, n / best / 1e9, 6.0 * (1 << 20) / (n / best) * 1e6);
}

int main(void)
{
	char *p;
	if (posix_memalign((void **)&p, 4096, SZ)) return 1;
	memset(p, 1, SZ);
	printf("zeroing %u MiB buffers, best of %d:\n", SZ >> 20, ITER);
	bench("memset (whole range)", fill_memset, p, SZ);
	bench("memset 4 KiB chunks", fill_memset_4k, p, SZ);
	bench("AVX2 NT (whole range)", fill_nt, p, SZ);
	bench("AVX2 NT 4 KiB chunks", fill_nt_4k, p, SZ);
	bench("movdir64b", fill_movdir64b, p, SZ);
	free(p);
	return 0;
}
