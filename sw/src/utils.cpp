#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <chrono>
#include <ctime>
#include <iostream>
#include <cmath>
#include <cfloat>

#include <posit/posit>
#include <boost/range/combine.hpp>
#include <boost/multiprecision/cpp_dec_float.hpp>

#include "defines.hpp"
#include "batch.hpp"
#include "utils.hpp"

using namespace std;
using namespace sw::unum;
using boost::multiprecision::cpp_dec_float_50;

// cpp_dec_float_50 decimal_accuracy(cpp_dec_float_50 exact, cpp_dec_float_50 computed) {
//     if (boost::math::isnan(exact) || boost::math::isnan(computed) ||
//         (boost::math::sign(exact) != boost::math::sign(computed))) {
//         return std::numeric_limits<cpp_dec_float_50>::quiet_NaN();
//     } else if (exact == computed) {
//         return std::numeric_limits<cpp_dec_float_50>::infinity();
//     } else if ((exact == std::numeric_limits<cpp_dec_float_50>::infinity() &&
//                 computed != std::numeric_limits<cpp_dec_float_50>::infinity()) ||
//                (exact != std::numeric_limits<cpp_dec_float_50>::infinity() &&
//                 computed == std::numeric_limits<cpp_dec_float_50>::infinity()) || (exact == 0 && computed != 0) ||
//                (exact != 0 && computed == 0)) {
//         return -std::numeric_limits<cpp_dec_float_50>::infinity();
//     } else {
//         return -log10(abs(log10(computed / exact)));
//     }
// }

// void writeBenchmark(PairHMMFloat<cpp_dec_float_50> &pairhmm_dec50, PairHMMFloat<float> &pairhmm_float,
//                     PairHMMPosit &pairhmm_posit, DebugValues<posit<NBITS, ES>> &hw_debug_values, std::string filename,
//                     bool printDate, bool overwrite) {
//     time_t t = chrono::system_clock::to_time_t(chrono::system_clock::now());
//
//     ofstream outfile(filename, ios::out);
//     if (printDate)
//         outfile << endl << ctime(&t) << endl << "===================" << endl;
//
//     auto dec_values = pairhmm_dec50.debug_values.items;
//     auto float_values = pairhmm_float.debug_values.items;
//     auto posit_values = pairhmm_posit.debug_values.items;
//     auto hw_values = hw_debug_values.items;
//
//     outfile << "name,dE_f,dE_p,dE_hw,log(abs(dE_f)),log(abs(dE_p)),log(abs(dE_hw)),E,E_f,E_p,E_hw,da_F,da_P,da_HW"
//             << endl;
//     for (int i = 0; i < dec_values.size(); i++) {
//         cpp_dec_float_50 E, E_f, E_p, E_hw, dE_f, dE_p, dE_hw;
//         cpp_dec_float_50 da_F, da_P, da_HW; // decimal accuracies
//
//         string name = dec_values[i].name;
//         E = dec_values[i].value;
//
//         auto E_f_entry = std::find_if(float_values.begin(), float_values.end(), find_entry(name));
//         E_f = E_f_entry->value;
//
//         auto E_p_entry = std::find_if(posit_values.begin(), posit_values.end(), find_entry(name));
//         E_p = E_p_entry->value;
//
//         auto E_hw_entry = std::find_if(hw_values.begin(), hw_values.end(), find_entry(name));
//         E_hw = E_hw_entry->value;
//
//         if (name != E_f_entry->name || name != E_p_entry->name || name != E_hw_entry->name) {
//             cout << "Error: mismatching names! Could not find name '" << E_f_entry->name << endl;
//         }
//
//         da_F = decimal_accuracy(E, E_f);
//         da_P = decimal_accuracy(E, E_p);
//         da_HW = decimal_accuracy(E, E_hw);
//
//         if (E == 0) {
//             dE_f = 0;
//             dE_p = 0;
//             dE_hw = 0;
//         } else {
//             dE_f = (E_f - E) / E;
//             dE_p = (E_p - E) / E;
//             dE_hw = (E_hw - E) / E;
//         }
//
//         // Relative error values
//         outfile << setprecision(50) << fixed << name << ","
//                 << dE_f << "," << dE_p << "," << dE_hw << ","
//                 << log10(abs(dE_f)) << "," << log10(abs(dE_p)) << "," << log10(abs(dE_hw)) << ","
//                 << E << "," << E_f << "," << E_p << "," << E_hw << ","
//                 << da_F << "," << da_P << "," << da_HW << endl;
//     }
//     outfile.close();
// }


void print_batch_info(t_batch& batch) {
    // DEBUG_PRINT("Batch pointers:");
    // DEBUG_PRINT("Init: %016lX ", (uint64_t) (batch->init));
    // DEBUG_PRINT("Read: %016lX ", (uint64_t) (batch->read));
    // DEBUG_PRINT("Hapl: %016lX ", (uint64_t) (batch->hapl));
    // DEBUG_PRINT("Prob: %016lX \n", (uint64_t) (batch->prob));
    DEBUG_PRINT("X:%d, PX:%d, PBPX:%d, Y:%d, PY:%d\n",
                batch.init.x_size,
                batch.init.x_padded,
                batch.init.x_bppadded,
                batch.init.y_size,
                batch.init.y_padded
    );
}


// padded read size
int px(int x, int y) {
    if (py(y) > PES)         // if feedback fifo is used
    {
        if (x <= PES)        // and x is equal or smaller than number of PES
        {
            x = PES + 1;     // x will be no. PES + 1, +1 is due to delay in the feedback fifo path
        }
    } else              // feedback fifo is not used
    {
        if (x < PES)  // x is smaller than no. PES
        {
            x = PES;  // pad x to be equal to no. PES
        }
    }
    return (x);
}


int pbp(int x) {
    return ((x / BASE_STEPS + (x % BASE_STEPS != 0)) * BASE_STEPS);
}


// padded haplotype size
int py(int y) {
    // divide Y by PES and round up and multiply:
    return ((y / PES + (y % PES != 0)) * PES);
}

t_workload *gen_workload(unsigned long pairs, unsigned long fixedX, unsigned long fixedY) {
    DEBUG_PRINT("Generating workload for %d pairs, with X=%d and Y=%d\n", (int) pairs, (int) fixedX, (int) fixedY);
    t_workload *workload = (t_workload *) malloc(sizeof(t_workload));

    if (fixedY < fixedX) {
        //printf("Haplotype cannot be smaller than read.\n");
        //exit(EXIT_FAILURE);
    }

    workload->pairs = pairs;

    if (workload->pairs % PIPE_DEPTH != 0) {
        printf("Number of pairs must be an integer multiple of %d.\n", PIPE_DEPTH);
        exit(EXIT_FAILURE);
    }

    workload->batches = pairs / PIPE_DEPTH;

    // Allocate memory
    workload->hapl = (uint32_t *) malloc(workload->pairs * sizeof(uint32_t));
    workload->read = (uint32_t *) malloc(workload->pairs * sizeof(uint32_t));
    workload->bx = (uint32_t *) malloc(workload->batches * sizeof(uint32_t));
    workload->by = (uint32_t *) malloc(workload->batches * sizeof(uint32_t));
    workload->bbytes = (size_t *) malloc(workload->batches * sizeof(size_t));

    for (int i = 0; i < workload->pairs; i++) {
        workload->hapl[i] = fixedY;
        workload->read[i] = fixedX;
    }

    // Set batch info
    DEBUG_PRINT("Batch ║ MAX X ║ MAX Y ║ Passes ║\n");
    DEBUG_PRINT("════════════════════════════════\n");

    for (int b = 0; b < workload->pairs / PIPE_DEPTH; b++) {
        int xmax = 0;
        int ymax = 0;
        for (int p = 0; p < PIPE_DEPTH; p++) {
            if (workload->read[b * PIPE_DEPTH + p] > xmax) {
                xmax = workload->read[b * PIPE_DEPTH + p];
            }
            if (workload->hapl[b * PIPE_DEPTH + p] > ymax) {
                ymax = workload->hapl[b * PIPE_DEPTH + p];
            }
        }
        workload->bx[b] = xmax;
        workload->by[b] = ymax;
        // workload->bbytes[b] = calc_batch_size(xmax, ymax, PES);
        // workload->bytes += workload->bbytes[b];

        DEBUG_PRINT("%5d ║ %5d ║ %5d ║ %6d ║\n", b, xmax, ymax, PASSES(ymax));//, (unsigned int) workload->bbytes[b]);
    }

    return (workload);
} // gen_workload

void copyProbBytes(t_probs& probs, uint8_t bytesArray[]) {
    int pos = 0;
    for(int i = 0; i < 8; i++) {
        bytesArray[pos++] = probs.p[i].x[0];
        bytesArray[pos++] = probs.p[i].x[1];
        bytesArray[pos++] = probs.p[i].x[2];
        bytesArray[pos++] = probs.p[i].x[3];
    }
}
