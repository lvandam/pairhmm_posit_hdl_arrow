#pragma once

#include <memory>

// Apache Arrow
#include <arrow/api.h>

#include "utils.hpp"
#include "batch.hpp"

using namespace std;

shared_ptr<arrow::Table> create_table_hapl(std::vector<t_batch>& batches);
shared_ptr<arrow::Table> create_table_reads_reads(std::vector<t_batch>& batches);
shared_ptr<arrow::Table> create_table_reads_probs(std::vector<t_batch>& batches);
