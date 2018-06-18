#ifndef __DEFINES_H
#define __DEFINES_H

#include <posit/posit>

using namespace std;
using namespace sw::unum;

// POSIT CONFIGURATION
#define NBITS 32
#define ES 3

#define DEBUG              1

#ifndef DEBUG_PRECISION
#define DEBUG_PRECISION 40
#endif // DEBUG_PRECISION

// PAIR-HMM Constants:

// Maximum number of basepairs in a read/haplotype pair
// MAX_BP_STRING must be an integer multiple of 128
#define MAX_BP_STRING    512
#define PES              16
#define FREQ             166666666.666666666666
#define MAX_CUPS         (double)PES * (double)FREQ

#define PASSES(Y)    1 + ((Y - 1) / PES)

// Batch size (or number of pipeline stages)
#define PIPE_DEPTH    16

// Length of pairs must be multiples of this number
// This is due to howmany bases fit in one cacheline
#define BASE_STEPS               8

// The error margin allowed
#define ERROR_MARGIN             0.0000001
#define ERR_LOWER                1.0f - ERROR_MARGIN
#define ERR_UPPER                1.0f + ERROR_MARGIN

// Debug printf macro
#ifdef DEBUG
#define DEBUG_PRINT(...)    do { fprintf(stderr, __VA_ARGS__); } while (0)
#define BENCH_PRINT(...)    do { } while (0)
#else
#define DEBUG_PRINT(...)    do { } while (0)
#define BENCH_PRINT(...)    do { fprintf(stderr, __VA_ARGS__); } while (0)
#endif

#define PROBABILITIES 8
#define PROBS_BYTES (PROBABILITIES * 4)

#endif //__DEFINES_H
