#ifndef __UTILS_H
#define __UTILS_H

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <posit/posit>

// #include "debug_values.hpp"
// #include "pairhmm_float.hpp"
// #include "pairhmm_posit.hpp"
#include "defines.hpp"
#include "batch.hpp"

using namespace std;
using namespace sw::unum;

// cpp_dec_float_50 decimal_accuracy(cpp_dec_float_50 exact, cpp_dec_float_50 computed);
//
// void writeBenchmark(PairHMMFloat<cpp_dec_float_50> &pairhmm_dec50, PairHMMFloat<float> &pairhmm_float,
//                     PairHMMPosit &pairhmm_posit, DebugValues<posit<NBITS, ES>> &hw_debug_values,
//                     std::string filename = "pairhmm_values.txt", bool printDate = true, bool overwrite = false);

void print_batch_info(t_batch& batch);

int px(int x, int y);

int pbp(int x);

int py(int y);

t_workload *gen_workload(unsigned long pairs, unsigned long fixedX, unsigned long fixedY);

void copyProbBytes(t_probs& probs, uint8_t bytesArray[]);

struct Entry {
    string name;
    cpp_dec_float_50 value;
};

struct find_entry {
    string name;

    find_entry(string name) : name(name) {}

    bool operator()(const Entry &m) const {
        return m.name == name;
    }
};

template<size_t nbits>
std::string hexstring(bitblock<nbits> bits) {
    char str[8];
    const char *hexits = "0123456789ABCDEF";
    unsigned int max = 8;
    for (unsigned int i = 0; i < max; i++) {
        unsigned int hexit = (bits[3] << 3) + (bits[2] << 2) + (bits[1] << 1) + bits[0];
        str[max - 1 - i] = hexits[hexit];
        bits >>= 4;
    }
    return std::string(str);
}

template<size_t nbits, size_t es>
uint32_t to_uint(posit<nbits, es> number) {
    return (uint32_t) number.collect().to_ulong();
}

#endif //__UTILS_H
