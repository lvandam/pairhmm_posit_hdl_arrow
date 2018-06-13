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
#include "PairHMMUserCore.h"
#include "pairhmm.h"

#ifndef PLATFORM
  #define PLATFORM 0
#endif

#ifndef DEBUG
    #define DEBUG 1
#endif

#define PRINT_INT(X) cout << dec << X << ", " << flush
#define PRINT_HEX(X) cout << hex << X << dec << endl << flush

#define PROBABILITIES 8
#define PROBS_BYTES (PROBABILITIES * 4)

using namespace std;

/**
 * Create an Arrow table containing one column of random bases.
 */
shared_ptr<arrow::Table> create_table_hapl(const string& hapl_string)
{
        //
        // listprim(8)
        //
        arrow::MemoryPool* pool = arrow::default_memory_pool();

        arrow::StringBuilder hapl_str_builder(pool);
        hapl_str_builder.Append(hapl_string);

        // Define the schema
        vector<shared_ptr<arrow::Field> > schema_fields = { arrow::field("haplotype", arrow::binary(), false) };

        const std::vector<std::string> keys = {"fletcher_mode"};
        const std::vector<std::string> values = {"read"};
        auto schema_meta = std::make_shared<arrow::KeyValueMetadata>(keys, values);

        auto schema = std::make_shared<arrow::Schema>(schema_fields, schema_meta);

        // Create an array and finish the builder
        shared_ptr<arrow::Array> hapl_array;
        hapl_str_builder.Finish(&hapl_array);

        // Create and return the table
        return move(arrow::Table::Make(schema, { hapl_array }));
}

shared_ptr<arrow::Table> create_table_reads_reads(const std::string& reads) {
    //
    // listprim(8)
    //
    arrow::MemoryPool* pool = arrow::default_memory_pool();

    arrow::StringBuilder read_str_builder(pool);
    read_str_builder.Append(reads);

    // Define the schema
    vector<shared_ptr<arrow::Field> > schema_fields = { arrow::field("read", arrow::uint8(), false) };

    const std::vector<std::string> keys = {"fletcher_mode"};
    const std::vector<std::string> values = {"read"};
    auto schema_meta = std::make_shared<arrow::KeyValueMetadata>(keys, values);

    auto schema = std::make_shared<arrow::Schema>(schema_fields, schema_meta);

    // Create an array and finish the builder
    shared_ptr<arrow::Array> read_array;
    read_str_builder.Finish(&read_array);

    // Create and return the table
    return move(arrow::Table::Make(schema, { read_array }));
}

shared_ptr<arrow::Table> create_table_reads_probs(int readSize) {
    //
    // listprim(fixed_size_binary(32))
    //
    arrow::MemoryPool* pool = arrow::default_memory_pool();

    // Define the schema
    vector<shared_ptr<arrow::Field> > schema_fields = { arrow::field("probs", arrow::fixed_size_binary(32), false) };

    const std::vector<std::string> keys = {"fletcher_mode"};
    const std::vector<std::string> values = {"read"};
    auto schema_meta = std::make_shared<arrow::KeyValueMetadata>(keys, values);

    auto schema = std::make_shared<arrow::Schema>(schema_fields, schema_meta);

    std::shared_ptr<arrow::DataType> type_ = arrow::fixed_size_binary(32);

    std::unique_ptr<arrow::ArrayBuilder> tmp;
    arrow::MakeBuilder(pool, type_, &tmp);

    std::unique_ptr<arrow::FixedSizeBinaryBuilder> builder_;
    builder_.reset(static_cast<arrow::FixedSizeBinaryBuilder*>(tmp.release()));

    for (int i = 0; i < readSize; ++i) {
            // Pack probabilities & append for this read
            ReadProb eta, zeta, epsilon, delta, beta, alpha, distm_diff, distm_simi;

            eta.f = 0.5;
            zeta.f = 0.25;
            epsilon.f = 0.5;
            delta.f = 0.25;
            beta.f = 0.5;
            alpha.f = 0.25;
            distm_diff.f = 0.5;
            distm_simi.f = 0.25;

            std::vector<ReadProb> probs;
            probs.push_back(distm_simi);
            probs.push_back(distm_diff);
            probs.push_back(alpha);
            probs.push_back(beta);
            probs.push_back(delta);
            probs.push_back(epsilon);
            probs.push_back(zeta);
            probs.push_back(eta);

            uint8_t probs_bytes[PROBS_BYTES];
            copyProbBytes(probs, probs_bytes);

            builder_->Append(probs_bytes);
    }

    // Create an array and finish the builder
    shared_ptr<arrow::Array> probs_array;
    builder_->Finish(&probs_array);

    // Create and return the table
    return move(arrow::Table::Make(schema, { probs_array }));
}

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

        // Make a table with haplotypes
        shared_ptr<arrow::Table> table_hapl = create_table_hapl("ACTGGTCA");

        // Make a table with reads
        // std::vector<uint8_t> reads = {'A', 'C', 'T', 'G', 'G', 'T', 'C', 'A'};
        // shared_ptr<arrow::Table> table_reads = create_table_reads(reads); // For struct

        // Dummy read string
        std::string reads = "AACCTTGG";
        // Create the read and probabilities columns
        shared_ptr<arrow::Table> table_reads_reads = create_table_reads_reads(reads);
        shared_ptr<arrow::Table> table_reads_probs = create_table_reads_probs(reads.size());

        // Match on FPGA
        // Create a platform
#if (PLATFORM == 0)
        shared_ptr<fletcher::EchoPlatform> platform(new fletcher::EchoPlatform());
#elif (PLATFORM == 2)
        shared_ptr<fletcher::SNAPPlatform> platform(new fletcher::SNAPPlatform());
#else
#error "PLATFORM must be 0, 1 or 2"
#endif

        // Prepare the colummn buffers
        std::vector<std::shared_ptr<arrow::Column>> columns;
        columns.push_back(table_hapl->column(0));
        columns.push_back(table_reads_reads->column(0));
        columns.push_back(table_reads_probs->column(0));

        platform->prepare_column_chunks(columns); // This requires a modification in Fletcher (to accept vectors)
        // platform->prepare_column_chunks(table_hapl->column(0), table_reads->column(0)); // This requires a modification in Fletcher // For struct
        // platform->prepare_column_chunks(table_reads->column(0));

        // Create a UserCore
        PairHMMUserCore uc(static_pointer_cast<fletcher::FPGAPlatform>(platform));

        // Reset it
        uc.reset();

        // Run
        uc.set_arguments(first_index, last_index);
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

        cout << "RESULT: " << hex << fpga_result << endl;
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
