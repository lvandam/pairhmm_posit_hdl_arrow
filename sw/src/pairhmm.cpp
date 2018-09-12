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
  #define PLATFORM 2
#endif

/* Burst step length in bytes */
#define BURST_LENGTH 4096

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
        // Times
        double start, stop;
        double t_fill_batch, t_fill_table, t_prepare_column, t_create_core, t_fpga, t_sw, t_float, t_dec = 0.0;

        srand(0);
        flush(cout);

        t_workload *workload;
        std::vector<t_batch> batches;

        int rc = 0;

        float f_hw = 125e6;
        float max_cups = f_hw * (float)16;

        unsigned long pairs, x, y = 0;
        int initial_constant_power = 1;
        bool calculate_sw = true;
        bool show_results = false;
        bool show_table = false;

        DEBUG_PRINT("Parsing input arguments...\n");
        if (argc > 4) {
                pairs = strtoul(argv[1], NULL, 0);
                x = strtoul(argv[2], NULL, 0);
                y = strtoul(argv[3], NULL, 0);
                initial_constant_power = strtoul(argv[4], NULL, 0);

                workload = gen_workload(pairs, x, y);

                BENCH_PRINT("M, ");
                BENCH_PRINT("%8d, %8d, %8d, ", workload->pairs, x, y);
        } else {
                fprintf(stderr,
                        "ERROR: Correct usage is: %s <pairs> <X> <Y> <initial constant power>\n",
                        "pairhmm");
                return (EXIT_FAILURE);
        }

        batches = std::vector<t_batch>(workload->batches);
        start = omp_get_wtime();

        // Generate random basepair strings for reads and haplotypes
        std::string x_string = randomBasepairs(workload->batches * (px(x, y) + x - 1));
        std::string y_string = randomBasepairs(workload->batches * (py(y) + y - 1));

        for (int q = 0; q < workload->batches; q++) {
                fill_batch(batches[q], x_string, y_string, q, workload->bx[q], workload->by[q], powf(2.0, initial_constant_power)); // HW unit starts with last batch
        }
        stop = omp_get_wtime();
        t_fill_batch = stop - start;

        PairHMMPosit pairhmm_posit(workload, show_results, show_table);
        PairHMMFloat<float> pairhmm_float(workload, show_results, show_table);
        PairHMMFloat<cpp_dec_float_100> pairhmm_dec50(workload, show_results, show_table);

        if (calculate_sw) {
                DEBUG_PRINT("Calculating on host...\n");

                start = omp_get_wtime();
                pairhmm_posit.calculate(batches);
                stop = omp_get_wtime();
                t_sw = stop - start;

                start = omp_get_wtime();
                pairhmm_float.calculate(batches);
                stop = omp_get_wtime();
                t_float = stop - start;

                start = omp_get_wtime();
                pairhmm_dec50.calculate(batches);
                stop = omp_get_wtime();
                t_dec = stop - start;
        }

        DEBUG_PRINT("Creating Arrow table...\n");
        start = omp_get_wtime();
        // Make a table with haplotypes
        shared_ptr<arrow::Table> table_hapl = create_table_hapl(batches);
        // Create the read and probabilities columns
        shared_ptr<arrow::Table> table_reads_reads = create_table_reads_reads(batches);
        shared_ptr<arrow::Table> table_reads_probs = create_table_reads_probs(batches);
        stop = omp_get_wtime();
        t_fill_table = stop - start;

        // Calculate on FPGA
        // Create a platform
        shared_ptr<fletcher::SNAPPlatform> platform(new fletcher::SNAPPlatform());

        DEBUG_PRINT("Preparing column buffers...\n");
        // Prepare the colummn buffers
        start = omp_get_wtime();
        std::vector<std::shared_ptr<arrow::Column> > columns;
        columns.push_back(table_hapl->column(0));
        columns.push_back(table_reads_reads->column(0));
        columns.push_back(table_reads_probs->column(0));
        platform->prepare_column_chunks(columns); // This requires a modification in Fletcher (to accept vectors)
        stop = omp_get_wtime();
        t_prepare_column = stop - start;

        DEBUG_PRINT("Creating UserCore instance...\n");
        start = omp_get_wtime();
        // Create a UserCore
        PairHMMUserCore uc(static_pointer_cast<fletcher::FPGAPlatform>(platform));

        // Reset UserCore
        uc.reset();

        // Initial values for each core
        std::vector<t_inits> inits(roundToMultiple(CORES, 2));
        // Number of batches for each core
        std::vector<uint32_t> batch_length(roundToMultiple(CORES, 2));
        // X & Y length for each core
        std::vector<uint32_t> x_len(roundToMultiple(CORES, 2));
        std::vector<uint32_t> y_len(roundToMultiple(CORES, 2));

        int batch_length_total = 0;
        // Balance total batches over multiple cores
        int avg_batches_per_core = floor((float)workload->batches / CORES);

        for(int i = 0; i < roundToMultiple(CORES, 2); i++) {
                // For now, duplicate batch information across all core MMIO registers
                batch_length[i] = (i == 0 && workload->batches % avg_batches_per_core > 0) ? avg_batches_per_core + 1 : avg_batches_per_core; // Remainder of batches is done by first core
                inits[i] = (i > CORES - 1) ? batches[0].init : batches[i].init;
                x_len[i] = (i > CORES - 1) ? 0 : workload->bx[i];
                y_len[i] = (i > CORES - 1) ? 0 : workload->by[i];
        }

        // Write result buffer addresses
        // Create arrays for results to be written to (per SA core)
        std::vector<uint32_t *> result_hw(roundToMultiple(CORES, 2));
        for(int i = 0; i < roundToMultiple(CORES, 2); i++) {
                rc = posix_memalign((void * * ) &(result_hw[i]), BURST_LENGTH, sizeof(uint32_t) * roundToMultiple(batch_length[i], 2) * PIPE_DEPTH);
                // clear values buffer
                for (uint32_t j = 0; j < roundToMultiple(batch_length[i], 2) * PIPE_DEPTH; j++) {
                        result_hw[i][j] = 0xDEADBEEF;
                }

                addr_lohi val;
                val.full = (uint64_t) result_hw[i];
                platform->write_mmio(REG_RESULT_DATA_OFFSET + i, val.full);
        }
        stop = omp_get_wtime();
        t_create_core = stop - start;

        // Configure the pair HMM SA cores
        uc.set_batch_init(batch_length, inits, x_len, y_len);

        std::vector<uint32_t> batch_offsets;
        batch_offsets.resize(roundToMultiple(CORES, 2));
        int batch_counter = 0;
        for(int i = 0; i < roundToMultiple(CORES, 2); i++) {
                batch_offsets[i] = batch_counter;
                batch_counter = batch_counter + batch_length[i];
        }
        uc.set_batch_offsets(batch_offsets);

        // Run
        DEBUG_PRINT("Starting accelerator computation...\n");
        start = omp_get_wtime();
        uc.start();

        uc.wait_for_finish();

        // Wait for last result of last SA core
        do {
                // for(int i = 0; i < CORES; i++) {
                //         cout << "==================================" << endl;
                //         cout << "== CORE " << i << endl;
                //         cout << "==================================" << endl;
                //         for(int j = 0; j < batch_length[i] * PIPE_DEPTH; j++) {
                //                 cout << dec << j <<": " << hex << result_hw[i][j] << dec <<endl;
                //         }
                //         cout << "==================================" << endl;
                //         cout << endl;
                // }

                usleep(1);
        }
        while ((result_hw[CORES - 1][batch_length[CORES - 1] * PIPE_DEPTH - 1] == 0xDEADBEEF));
        stop = omp_get_wtime();
        t_fpga = stop - start;

        for(int i = 0; i < CORES; i++) {
                cout << "==================================" << endl;
                cout << "== CORE " << i << endl;
                cout << "==================================" << endl;
                for(int j = 0; j < batch_length[i] * PIPE_DEPTH; j++) {
                        cout << dec << j <<": " << hex << result_hw[i][j] << dec <<endl;
                }
                cout << "==================================" << endl;
                cout << endl;
        }

        // Check for errors with SW calculation
        if (calculate_sw) {
                DebugValues<posit<NBITS, ES> > hw_debug_values;

                for (int c = 0; c < CORES; c++) {
                        for (int i = 0; i < batch_length[c]; i++) {
                                for(int j = 0; j < PIPE_DEPTH; j++) {
                                        // Store HW posit result for decimal accuracy calculation
                                        posit<NBITS, ES> res_hw;
                                        res_hw.set_raw_bits(result_hw[c][i * PIPE_DEPTH + j]);
                                        hw_debug_values.debugValue(res_hw, "result[%d][%d]", batch_offsets[c] + (batch_length[c] - i - 1), j);
                                }
                        }
                }

                cout << "Writing benchmark file..." << endl;
                writeBenchmark(pairhmm_dec50, pairhmm_float, pairhmm_posit, hw_debug_values,
                               "pairhmm_es" + std::to_string(ES) + "_" + std::to_string(CORES) + "core_" + std::to_string(pairs) + "_" + std::to_string(x) + "_" + std::to_string(y) + "_" + std::to_string(initial_constant_power) + ".txt",
                               false, true);

                DEBUG_PRINT("Checking errors...\n");
                int errs_posit = 0;
                errs_posit = pairhmm_posit.count_errors(batch_offsets, batch_length, result_hw);
                DEBUG_PRINT("Posit errors: %d\n", errs_posit);
        }

        cout << "Resetting user core..." << endl;
        // Reset UserCore
        uc.reset();

        float p_fpga      = ((double)workload->cups / (double)t_fpga)  / 1000000; // in MCUPS
        float p_sw        = ((double)workload->cups / (double)t_sw)    / 1000000; // in MCUPS
        float p_float     = ((double)workload->cups / (double)t_float) / 1000000; // in MCUPS
        float p_dec       = ((double)workload->cups / (double)t_dec)   / 1000000; // in MCUPS
        float utilization = ((double)workload->cups / (double)t_fpga)  / max_cups;
        float speedup     = t_sw / t_fpga;

        cout << "Adding timing data..." << endl;
        time_t t = chrono::system_clock::to_time_t(chrono::system_clock::now());
        ofstream outfile("pairhmm_es" + std::to_string(ES) + "_" + std::to_string(CORES) + "core_" + std::to_string(pairs) + "_" + std::to_string(x) + "_" + std::to_string(y) + "_" + std::to_string(initial_constant_power) + ".txt", ios::out | ios::app);
        outfile << endl << "===================" << endl;
        outfile << ctime(&t) << endl;
        outfile << "Pairs = " << pairs << endl;
        outfile << "X = " << x << endl;
        outfile << "Y = " << y << endl;
        outfile << "Initial Constant = " << initial_constant_power << endl;
        outfile << "cups,t_fill_batch,t_fill_table,t_prepare_column,t_create_core,t_fpga,p_fpga,t_sw,p_sw,t_float,p_float,t_dec,p_dec,utilization,speedup" << endl;
        outfile << setprecision(20) << fixed << workload->cups <<","<< t_fill_batch <<","<< t_fill_table <<","<< t_prepare_column <<","<< t_create_core <<","<< t_fpga <<","<< p_fpga <<","<< t_sw <<","<< p_sw <<","<< t_float <<","<< p_float <<","<< t_dec <<","<< p_dec <<","<< utilization <<","<< speedup << endl;
        outfile.close();

        return 0;
}
