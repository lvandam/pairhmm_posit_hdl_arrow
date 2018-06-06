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

/**
 * Main file for the regular expression matching example application.
 *
 * This example works only under the following constraints:
 *
 * - The number of rows MUST be an integer multiple of the number of active
 *   units (due to naive work distribution)
 *
 * Output format (all times are in seconds):
 * - no. rows, no. bytes (all buffers), table fill time,
 *   C++ run time, C++ using Arrow run time,
 *   C++ using OpenMP run time, C++ using OpenMP and Arrow run time,
 *   FPGA Copy time, FPGA run time
 *
 * TODO:
 * - Somehow, only on the Amazon instance on CentOS after using dev toolkit 6
 *   the program will end with a segmentation fault. GDB/Valgrind reveal that
 *   it has something to do with the Arrow schema, when the shared_ptr tries
 *   to clean up the last use count. However, at this time I have no idea how
 *   to fix it. I cannot reproduce the error on any other configuration. This
 *   code may be wrong or it may be something in Arrow internally. -johanpel
 *
 */
#include <cstdint>
#include <memory>
#include <vector>
#include <string>
#include <numeric>
#include <iostream>
#include <iomanip>
#include <fstream>
#include <omp.h>

// RE2 regular expressions library
#include <re2/re2.h>

// Apache Arrow
#include <arrow/api.h>

// Fletcher
#include <fletcher/fletcher.h>

// RegEx FPGA UserCore
#include "RegExUserCore.h"

#ifndef PLATFORM
  #define PLATFORM 0
#endif

#ifndef DEBUG
    #define DEBUG 1
#endif

#define PRINT_INT(X) cout << dec << X << ", " << flush
#define PRINT_HEX(X) cout << hex << X << dec << endl << flush


using namespace std;

/**
 * Create an Arrow table containing one column of random bases.
 */
shared_ptr<arrow::Table> create_table(const string& string)
{
        arrow::StringBuilder str_builder(arrow::default_memory_pool());

        str_builder.Append(string);

        // Define the schema
        auto column_field = arrow::field("haplos", arrow::utf8(), false);
        vector<shared_ptr<arrow::Field> > fields = { column_field };

        shared_ptr<arrow::Schema> schema = make_shared<arrow::Schema>(fields);

        // Create an array and finish the builder
        shared_ptr<arrow::Array> str_array;
        str_builder.Finish(&str_array);

        // Create and return the table
        return move(arrow::Table::Make(schema, { str_array }));
}

/**
 * Main function for the regular expression matching example
 */
int main(int argc, char ** argv)
{
        srand(0);

        uint32_t num_rows = 1;

        flush(cout);

        // Aggregators
        uint64_t bytes_copied = 0;

        // Result
        uint32_t fpga_result;

        uint32_t first_index = 0;
        uint32_t last_index = num_rows;

        PRINT_INT(num_rows);

        // Make a table with random strings containing some other string effectively serializing the data
        shared_ptr<arrow::Table> table = create_table("actg");

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
        bytes_copied = platform->prepare_column_chunks(table->column(0));

        // Create a UserCore
        RegExUserCore uc(static_pointer_cast<fletcher::FPGAPlatform>(platform));

        // Reset it
        uc.reset();

        // Run the example
        uc.set_arguments(first_index, last_index);
        uc.start();

        uc.control_zero();

#ifdef DEBUG
        uc.wait_for_finish(1000000);
#else
        uc.wait_for_finish(10);
#endif

        // Get the number of matches from the UserCore
        // uc.get_matches(m_fpga[e]);
        // Get the result from FPGA
        uc.get_result(fpga_result);

        PRINT_INT(bytes_copied);

        cout << "RESULT: " << hex << fpga_result << endl;
        cout << endl;

        return 0;
}
