// Copyright 2018 Delft University of Technology
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <cstdint>
#include <memory>
#include <vector>
#include <string>
#include <numeric>
#include <iostream>
#include <iomanip>
#include <fstream>
#include <omp.h>

// Apache Arrow
#include <arrow/api.h>

// Fletcher
#include <fletcher/fletcher.h>

// Pair-HMM FPGA UserCore
#include "scheme.hpp"
#include "PairHMMUserCore.h"
#include "pairhmm.hpp"

#include "debug_values.hpp"
#include "utils.hpp"
#include "batch.hpp"

#ifndef PLATFORM
  #define PLATFORM 0
#endif

#ifndef DEBUG
    #define DEBUG 1
#endif

/* Burst step length in bytes */
#define BURST_LENGTH 128

using namespace std;

/* Structure to easily convert from 64-bit addresses to 2x32-bit registers */
typedef struct _lohi {
        uint32_t lo;
        uint32_t hi;
}
lohi;

typedef union _addr_lohi {
        uint64_t full;
        lohi half;
}
addr_lohi;

/**
 * Main function for pair HMM accelerator
 */
int main(int argc, char ** argv)
{
        srand(0);
        flush(cout);

        t_workload *workload;
        std::vector<t_batch> batches;

        int rc = 0;
        uint32_t num_rows = BATCHES_PER_CORE * PIPE_DEPTH;

        unsigned long pairs, x, y = 0;
        int initial_constant_power = 1;
        bool calculate_sw = true;
        bool show_results = false;
        bool show_table = false;

        DEBUG_PRINT("Parsing input arguments...\n");
        if (argc < 5) {
                fprintf(stderr,
                        "ERROR: Correct usage is: %s <-m = manual> ... \n-m: <pairs> <X> <Y> <initial constant power> ... \n-f: <input file>\n... <sw solve?*> <show results?*> <show MID table?*> (* is optional)\n",
                        "pairhmm");
                return (-1);
        } else {
                if (strncmp(argv[1], "-m", 2) == 0) {
                        DEBUG_PRINT("Manual input mode selected. %d arguments supplied.\n", argc);
                        int pairs = strtoul(argv[2], NULL, 0);
                        int x = strtoul(argv[3], NULL, 0);
                        int y = strtoul(argv[4], NULL, 0);
                        initial_constant_power = strtoul(argv[5], NULL, 0);

                        workload = gen_workload(pairs, x, y);

                        if (argc >= 7) istringstream(argv[6]) >> calculate_sw;
                        if (argc >= 8) istringstream(argv[7]) >> show_results;
                        if (argc >= 9) istringstream(argv[8]) >> show_table;

                        BENCH_PRINT("M, ");
                        BENCH_PRINT("%8d, %8d, %8d, ", workload->pairs, x, y);
                } else {
                        fprintf(stderr,
                                "ERROR: Correct usage is: %s <-m = manual> ... \n-m: <pairs> <X> <Y> <initial constant power> ... \n-f: <input file>\n... <sw solve?*> <show results?*> <show MID table?*> (* is optional)\n",
                                "pairhmm");
                        return (EXIT_FAILURE);
                }
        }

        batches = std::vector<t_batch>(workload->batches);
        for (int q = 0; q < workload->batches; q++) {
                fill_batch(batches[q], q, workload->bx[q], workload->by[q], powf(2.0, initial_constant_power)); // HW unit starts with last batch
                print_batch_info(batches[q]);
        }

        PairHMMPosit pairhmm_posit(workload, show_results, show_table);
        PairHMMFloat<float> pairhmm_float(workload, show_results, show_table);
        PairHMMFloat<cpp_dec_float_50> pairhmm_dec50(workload, show_results, show_table);

        if (calculate_sw) {
                DEBUG_PRINT("Calculating on host...\n");
                pairhmm_posit.calculate(batches);
                pairhmm_float.calculate(batches);
                pairhmm_dec50.calculate(batches);
        }

        // Make a table with haplotypes
        shared_ptr<arrow::Table> table_hapl = create_table_hapl(batches);
        // Create the read and probabilities columns
        shared_ptr<arrow::Table> table_reads_reads = create_table_reads_reads(batches);
        shared_ptr<arrow::Table> table_reads_probs = create_table_reads_probs(batches);

        // Calculate on FPGA
        // Create a platform
#if (PLATFORM == 0)
        shared_ptr<fletcher::EchoPlatform> platform(new fletcher::EchoPlatform());
#elif (PLATFORM == 2)
        shared_ptr<fletcher::SNAPPlatform> platform(new fletcher::SNAPPlatform());
#else
#error "PLATFORM must be 0 or 2"
#endif

        // Prepare the colummn buffers
        std::vector<std::shared_ptr<arrow::Column> > columns;
        columns.push_back(table_hapl->column(0));
        columns.push_back(table_reads_reads->column(0));
        columns.push_back(table_reads_probs->column(0));

        platform->prepare_column_chunks(columns); // This requires a modification in Fletcher (to accept vectors)

        // Create a UserCore
        PairHMMUserCore uc(static_pointer_cast<fletcher::FPGAPlatform>(platform));

        // Reset UserCore
        uc.reset();

        // Write result buffer addresses
        // Create arrays for results to be written to (per SA core)
        std::vector<uint32_t *> result_hw(roundToMultiple(CORES, 2));
        // for(int i = 0; i < roundToMultiple(CORES, 2); i++) {
            int i = 0;
                rc = posix_memalign((void * * ) &(result_hw[i]), BURST_LENGTH, sizeof(uint32_t) * num_rows);
                cout << rc << endl;
                // clear values buffer
                for (uint32_t j = 0; j < num_rows; j++) {
                        result_hw[i][j] = 0xDEADBEEF;
                }

                addr_lohi val;
                val.full = (uint64_t) result_hw[i];
                printf("Values buffer @ %016lX\n", val.full);
                platform->write_mmio(REG_RESULT_DATA_OFFSET + i, val.full);
        // }

        // Configure the pair HMM SA cores
        std::vector<t_inits> inits(roundToMultiple(CORES, 2));
        std::vector<uint32_t> x_len(roundToMultiple(CORES, 2)), y_len(roundToMultiple(CORES, 2));
        for(int i = 0; i < roundToMultiple(CORES, 2); i++) {
                // For now, duplicate batch information across all core MMIO registers
                inits[i] = batches[0].init;
                x_len[i] = workload->by[0];
                y_len[i] = workload->by[0];
        }

        uc.set_batch_init(inits, x_len, y_len);

        std::vector<uint32_t> batch_offsets;
        batch_offsets.reserve(roundToMultiple(CORES, 2));
        for(int i = 0; i < roundToMultiple(CORES, 2); i++) {
                // For now, same amount of batches for all cores
                batch_offsets[i] = i * BATCHES_PER_CORE;
        }
        uc.set_batch_offsets(batch_offsets);

        // Run
        uc.start();

#ifdef DEBUG
        uc.wait_for_finish(1000000);
#else
        uc.wait_for_finish(10);
#endif

        // Wait for last result of last SA core
        do {
            // Get the number of matches from the UserCore
            for(int i = 0; i < CORES; i++) {
                    cout << "==================================" << endl;
                    cout << "== CORE " << i << endl;
                    cout << "==================================" << endl;
                    for(int j = 0; j < num_rows; j++) {
                            cout << dec << j <<": " << hex << result_hw[i][j] << dec <<endl;
                    }
                    cout << "==================================" << endl;
                    cout << endl;
            }
            usleep(200000);
        }
        while ((result_hw[CORES - 1][num_rows - 1] == 0xDEADBEEF));



        // Check for errors with SW calculation
        if (calculate_sw) {
                DebugValues<posit<NBITS, ES> > hw_debug_values;

                for (int c = 0; c < CORES; c++) {
                        for (int i = 0; i < BATCHES_PER_CORE; i++) {
                                for(int j = 0; j < PIPE_DEPTH; j++) {
                                        // Store HW posit result for decimal accuracy calculation
                                        posit<NBITS, ES> res_hw;
                                        res_hw.set_raw_bits(result_hw[c][i * PIPE_DEPTH + j]);
                                        hw_debug_values.debugValue(res_hw, "result[%d][%d]", c * BATCHES_PER_CORE + (BATCHES_PER_CORE - i - 1), j);
                                }
                        }
                }

                writeBenchmark(pairhmm_dec50, pairhmm_float, pairhmm_posit, hw_debug_values,
                               std::to_string(initial_constant_power) + ".txt", false, true);

                int errs_posit = 0;
                errs_posit = pairhmm_posit.count_errors(result_hw);
                DEBUG_PRINT("Posit errors: %d\n", errs_posit);
        }

        // Reset UserCore
        uc.reset();

        return 0;
}
