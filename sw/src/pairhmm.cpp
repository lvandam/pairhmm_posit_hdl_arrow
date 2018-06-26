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

// #include "debug_values.hpp"
#include "utils.hpp"
#include "batch.hpp"

#ifndef PLATFORM
  #define PLATFORM 0
#endif

#ifndef DEBUG
    #define DEBUG 1
#endif

/* Burst step length in bytes */
#define BURST_LENGTH    16

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

        // Result
        uint32_t fpga_result;

        uint32_t first_index = 0;
        uint32_t last_index = 1;

        t_workload *workload;
        std::vector<t_batch> batches;

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
                fill_batch(batches[q], workload->bx[q], workload->by[q], powf(2.0, initial_constant_power));
                print_batch_info(batches[q]);
        }

        PairHMMPosit pairhmm_posit(workload, show_results, show_table);
        // PairHMMFloat<float> pairhmm_float(workload, show_results, show_table);
        // PairHMMFloat<cpp_dec_float_50> pairhmm_dec50(workload, show_results, show_table);
        //
        if (calculate_sw) {
                DEBUG_PRINT("Calculating on host...\n");
                pairhmm_posit.calculate(batches);
                //     pairhmm_float.calculate(batches);
                //     pairhmm_dec50.calculate(batches);
        }

        // TODO for now, only first batch is supported
        // Make a table with haplotypes
        shared_ptr<arrow::Table> table_hapl = create_table_hapl(batches[0]);

        // Create the read and probabilities columns
        shared_ptr<arrow::Table> table_reads_reads = create_table_reads_reads(batches[0]);
        shared_ptr<arrow::Table> table_reads_probs = create_table_reads_probs(batches[0]);

        // Match on FPGA
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

        int rc = 0;
        uint32_t num_rows = 32;
        uint32_t * val_buf;
        rc = posix_memalign((void * * ) & val_buf, BURST_LENGTH, sizeof(uint32_t) * num_rows);
        // clear values buffer
        for (uint32_t i = 0; i < num_rows; i++) {
                val_buf[i] = 0xDEADBEEF;
        }
        addr_lohi val;
        val.full = (uint64_t) val_buf;
        printf("Values buffer @ %016lX\n", val.full);
        platform->write_mmio(REG_RESULT_DATA_OFFSET, val.full);

        // Reset it
        uc.reset();

        // Run
        uc.set_batch_init(batches[0].init, 6, 6); // Correctly convert x and y to uint32_t
        uc.start();

#ifdef DEBUG
        uc.wait_for_finish(1000000);
#else
        uc.wait_for_finish(10);
#endif

        // Wait for last result
        do {
          usleep(10);
        }
        while ((val_buf[15] == 0xDEADBEEF));

        // Get the number of matches from the UserCore
        for(int i = 0; i < num_rows; i++) {
                cout << "RESULT: " << hex << val_buf[i] << endl;
        }
        cout << endl;

        return 0;
}
