#pragma once

#include <memory>

// Apache Arrow
#include <arrow/api.h>

#include "utils.hpp"
#include "batch.hpp"

using namespace std;

shared_ptr<arrow::Table> create_table_hapl(t_batch& batch);
shared_ptr<arrow::Table> create_table_reads_reads(t_batch& batch);
shared_ptr<arrow::Table> create_table_reads_probs(t_batch& batch);
