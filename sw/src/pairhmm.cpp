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
#define BURST_LENGTH    8

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

        // Create result column
        // shared_ptr<arrow::Table> table_results = create_table_result();

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
        // columns.push_back(table_results->column(0));

        platform->prepare_column_chunks(columns); // This requires a modification in Fletcher (to accept vectors)

        // Create a UserCore
        PairHMMUserCore uc(static_pointer_cast<fletcher::FPGAPlatform>(platform));

        // TODO Temporary
        int rc = 0;
        uint32_t num_rows = 32;
        uint32_t * off_buf;
        uint32_t * val_buf;
        rc = posix_memalign((void * * ) &off_buf, BURST_LENGTH, sizeof(uint32_t) * (num_rows + 1));
        // clear offset buffer
        for (uint32_t i = 0; i < num_rows + 1; i++) {
                off_buf[i] = 0xDEADBEEF;
        }
        rc = posix_memalign((void * * ) &val_buf, BURST_LENGTH, sizeof(uint32_t) * num_rows);
        // clear values buffer
        for (uint32_t i = 0; i < num_rows; i++) {
                val_buf[i] = 0x00000000;
        }
        addr_lohi off, val;
        off.full = (uint64_t) off_buf;
        val.full = (uint64_t) val_buf;
        printf("Offsets buffer @ %016lX\n", off.full);
        printf("Values buffer @ %016lX\n", val.full);
        platform->write_mmio(REG_RESULT_OFF_OFFSET, off.full);
        platform->write_mmio(REG_RESULT_DATA_OFFSET, val.full);
        // TODO END Temporary

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

        // Get the number of matches from the UserCore
        // uc.get_matches(m_fpga[e]);
        // Get the result from FPGA
        uc.get_result(fpga_result);

        // cout << "RESULT: " << hex << fpga_result << endl;
        for(int i = 0; i < 32; i++) {
            cout << "RESULT: " << hex << (uint32_t)val_buf[i] << endl;
        }
        cout << endl;

        return 0;
}

// shared_ptr<arrow::Table> create_table_reads(const std::vector<uint8_t>& reads) {  // For struct column
//         //
//         // list(struct(prim(8),prim(256)))
//         //
//         arrow::MemoryPool* pool = arrow::default_memory_pool();
//
//         std::vector<std::shared_ptr<arrow::Field> > schema_fields = {
//                 arrow::field("read",
//                              arrow::list(
//                                      arrow::field("item",
//                                                   arrow::struct_({arrow::field("basepairs", arrow::uint8(), false),
//                                                                   arrow::field("probabilities",
//                                                                                arrow::fixed_size_binary(32),
//                                                                                false)}),
//                                                   false)), false)};
//
//         const std::vector<std::string> keys = {"fletcher_mode"};
//         const std::vector<std::string> values = {"read"};
//         auto schema_meta = std::make_shared<arrow::KeyValueMetadata>(keys, values);
//         auto schema = std::make_shared<arrow::Schema>(schema_fields, schema_meta);
//
//         // Build item struct
//         std::vector<std::shared_ptr<arrow::Field> > fields;
//         fields.push_back(arrow::field("basepairs", arrow::uint8(), false));
//         fields.push_back(arrow::field("probabilities", arrow::fixed_size_binary(32), false));
//
//         std::shared_ptr<arrow::DataType> type_ = arrow::struct_(fields);
//
//         std::unique_ptr<arrow::ArrayBuilder> tmp;
//         arrow::MakeBuilder(pool, type_, &tmp);
//
//         std::unique_ptr<arrow::StructBuilder> builder_;
//         builder_.reset(static_cast<arrow::StructBuilder*>(tmp.release()));
//
//         arrow::UInt8Builder* read_vb = static_cast<arrow::UInt8Builder*>(builder_->field_builder(0));
//         arrow::FixedSizeBinaryBuilder* probs_vb = static_cast<arrow::FixedSizeBinaryBuilder*>(builder_->field_builder(1));
//
//
//         vector<char> list_values = {'A', 'C', 'T', 'G'};
//         vector<int> list_lengths = {4};
//         vector<int> list_offsets = {0};
//         vector<uint8_t> list_is_valid = {1};
//
//         // Resize to correct size
//         read_vb->Resize(reads.size());
//         probs_vb->Resize(reads.size());
//
//         for (size_t i = 0; i < reads.size(); ++i) {
//                 read_vb->UnsafeAppend(reads[i]);
//
//                 // // Pack probabilities & append for this read
//                 // float eta, zeta, epsilon, delta, beta, alpha, distm_diff, distm_simi;
//                 //
//                 // eta = 0.5;
//                 // zeta = 0.25;
//                 // epsilon = 0.5;
//                 // delta = 0.25;
//                 // beta = 0.5;
//                 // alpha = 0.25;
//                 // distm_diff = 0.5;
//                 // distm_simi = 0.25;
//                 //
//                 // std::vector<float> probs(PROBABILITIES);
//                 // probs.push_back(eta);
//                 // probs.push_back(zeta);
//                 // probs.push_back(epsilon);
//                 // probs.push_back(delta);
//                 // probs.push_back(beta);
//                 // probs.push_back(alpha);
//                 // probs.push_back(distm_diff);
//                 // probs.push_back(distm_simi);
//
//                 uint8_t probs_bytes[PROBS_BYTES];
//                 for(int i = 0; i < PROBS_BYTES/4; i++) {
//                     probs_bytes[i*4+0] = 0x01;
//                     probs_bytes[i*4+1] = 0x02;
//                     probs_bytes[i*4+2] = 0x03;
//                     probs_bytes[i*4+3] = 0x04;
//                 }
//                 // void * p = probs_bytes;
//                 // memcpy(p, &probs, sizeof(probs));
//
//                 probs_vb->Append(probs_bytes);
//         }
//
//         // Struct valid array
//         for (size_t i = 0; i < reads.size(); ++i) {
//                 builder_->Append(1);
//         }
//
//         arrow::ListBuilder components_builder(pool, std::move(builder_));
//
//         for (size_t i = 0; i < reads.size(); ++i) {
//             components_builder.Append();
//         }
//
//         std::shared_ptr<arrow::Array> list_array;
//         components_builder.Finish(&list_array);
//
//         std::shared_ptr<arrow::Table> table = arrow::Table::Make(schema, { list_array });
//
//         return move(table);
//     }
