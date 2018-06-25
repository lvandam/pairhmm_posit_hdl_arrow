#include <cstdint>
#include <memory>
#include <vector>
#include <string>
#include <numeric>
#include <iostream>
#include <iomanip>

// Apache Arrow
#include <arrow/api.h>

#include "utils.hpp"
#include "batch.hpp"

using namespace std;

/**
 * Create an Arrow table containing one column of random bases.
 */
shared_ptr<arrow::Table> create_table_hapl(t_batch& batch)
{
        std::vector<t_bbase> haplos = batch.hapl;
        // char vector to string
        std::string hapl_string;
        for(t_bbase base : haplos) {
                hapl_string += base.base;
        }

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

shared_ptr<arrow::Table> create_table_reads_reads(t_batch& batch)
{
        std::vector<t_bbase>& reads = batch.read;
        // char vector to string
        std::string read_string;
        for(t_bbase base : reads) {
                read_string += base.base;
        }

        //
        // listprim(8)
        //
        arrow::MemoryPool* pool = arrow::default_memory_pool();

        arrow::StringBuilder read_str_builder(pool);
        read_str_builder.Append(read_string);

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

shared_ptr<arrow::Table> create_table_reads_probs(t_batch& batch)
{
        std::vector<t_probs>& probs = batch.prob;

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

        for (int i = 0; i < batch.read.size(); ++i) {
                t_probs& read_probs = probs[i];

                // Pack probabilities & append for this read
                uint8_t probs_bytes[PROBS_BYTES];
                copyProbBytes(read_probs, probs_bytes);

                builder_->Append(probs_bytes);
        }

        // Create an array and finish the builder
        shared_ptr<arrow::Array> probs_array;
        builder_->Finish(&probs_array);

        // Create and return the table
        return move(arrow::Table::Make(schema, { probs_array }));
}

/**
 * Create an Arrow table containing one column of results
 */
shared_ptr<arrow::Table> create_table_result()
{
    //
    // listprim(fixed_size_binary(32))
    //
    arrow::MemoryPool* pool = arrow::default_memory_pool();

    // Define the schema
    vector<shared_ptr<arrow::Field> > schema_fields = { arrow::field("result", arrow::fixed_size_binary(32), false) };

    const std::vector<std::string> keys = {"fletcher_mode"};
    const std::vector<std::string> values = {"read"};
    auto schema_meta = std::make_shared<arrow::KeyValueMetadata>(keys, values);

    auto schema = std::make_shared<arrow::Schema>(schema_fields, schema_meta);

    std::shared_ptr<arrow::DataType> type_ = arrow::fixed_size_binary(32);

    std::unique_ptr<arrow::ArrayBuilder> tmp;
    arrow::MakeBuilder(pool, type_, &tmp);

    std::unique_ptr<arrow::FixedSizeBinaryBuilder> builder_;
    builder_.reset(static_cast<arrow::FixedSizeBinaryBuilder*>(tmp.release()));

    // Create an array and finish the builder
    shared_ptr<arrow::Array> result_array;
    builder_->Finish(&result_array);

    // Create and return the table
    return move(arrow::Table::Make(schema, { result_array }));
}
