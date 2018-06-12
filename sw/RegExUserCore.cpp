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

#include <stdexcept>

#include "RegExUserCore.h"

using namespace fletcher;

RegExUserCore::RegExUserCore(std::shared_ptr<fletcher::FPGAPlatform> platform)
        : UserCore(platform)
{
        // Some settings that are different from standard implementation
        // concerning start, reset and status register.
        ctrl_start       = 0x0000000000000001;// 0x00000000000000FF;
        ctrl_reset       = 0x0000000000000002;// 0x000000000000FF00;
        done_status      = 0x0000000000000002;// 0x000000000000FF00;
        done_status_mask = 0x0000000000000003;// 0x000000000000FFFF;
}

fr_t RegExUserCore::generate_unit_arguments(uint32_t first_index,
                                                         uint32_t last_index)
{
        /*
         * Generate arguments for the haplotype ColumnReader
         * Because the arguments for each REM unit are two 32-bit integers,
         * but the register model for UserCores is 64-bit, we need to
         * determine each 64-bit register value.
         */

        if (first_index >= last_index) {
                throw std::runtime_error("First index cannot be larger than "
                                         "or equal to last index.");
        }
        
        // Every unit needs two 32 bit argument, which is one 64-bit argument
        reg_conv_t conv;
        // First indices
        conv.half.hi = first_index;
        conv.half.lo = last_index;

        return conv.full;
}

void RegExUserCore::set_arguments(uint32_t first_index, uint32_t last_index)
{
        std::vector<fr_t> arguments;
        arguments.push_back(this->generate_unit_arguments(first_index, last_index)); // Haplotype first & last idx
        arguments.push_back(this->generate_unit_arguments(first_index, last_index)); // Read first & last idx

        UserCore::set_arguments(arguments);
}

void RegExUserCore::get_matches(std::vector<uint32_t>& matches)
{
        int np = matches.size();

        reg_conv_t conv;
        this->platform()->read_mmio(REUC_RESULT_OFFSET, &conv.full);
        matches[0] += conv.half.hi;
        matches[1] += conv.half.lo;
}

void RegExUserCore::control_zero()
{
        this->platform()->write_mmio(REUC_CONTROL_OFFSET, 0x00000000);
}

void RegExUserCore::get_result(uint32_t& result)
{
        reg_conv_t conv;
        this->platform()->read_mmio(REUC_RESULT_OFFSET, &conv.full);
        result = conv.half.lo;
}