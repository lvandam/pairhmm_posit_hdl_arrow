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

#include "PairHMMUserCore.h"

using namespace fletcher;

PairHMMUserCore::PairHMMUserCore(std::shared_ptr<fletcher::FPGAPlatform> platform)
        : UserCore(platform)
{
        // Some settings that are different from standard implementation
        // concerning start, reset and status register.
        ctrl_start       = 0x0000000000000001;// 0x00000000000000FF;
        ctrl_reset       = 0x0000000000000002;// 0x000000000000FF00;
        done_status      = 0x0000000000000002;// 0x000000000000FF00;
        done_status_mask = 0x0000000000000003;// 0x000000000000FFFF;
}

void PairHMMUserCore::set_batch_init(t_inits& init, uint32_t xlen, uint32_t ylen) {
    // X len & Y len
    reg_conv_t xlen_ylen;
    xlen_ylen.half.hi = xlen;
    xlen_ylen.half.lo = ylen;
    this->platform()->write_mmio(REG_XLEN_YLEN_OFFSET, xlen_ylen.full);

    // X size & Y size
    reg_conv_t x_y;
    x_y.half.hi = init.x_size;
    x_y.half.lo = init.y_size;
    this->platform()->write_mmio(REG_X_Y_OFFSET, x_y.full);

    // X padded size & Y padded size
    reg_conv_t xp_yp;
    xp_yp.half.hi = init.x_padded;
    xp_yp.half.lo = init.y_padded;
    this->platform()->write_mmio(REG_XP_YP_OFFSET, xp_yp.full);

    // X BP padded size
    reg_conv_t xbpp_initial;
    xbpp_initial.half.hi = init.x_bppadded;
    xbpp_initial.half.lo = init.initials[0];
    this->platform()->write_mmio(REG_XBPP_INITIAL_OFFSET, xbpp_initial.full);
}

void PairHMMUserCore::get_matches(std::vector<uint32_t>& matches)
{
        int np = matches.size();

        reg_conv_t conv;
        this->platform()->read_mmio(REG_RESULT_OFFSET, &conv.full);
        matches[0] += conv.half.hi;
        matches[1] += conv.half.lo;
}

void PairHMMUserCore::control_zero()
{
        this->platform()->write_mmio(REG_CONTROL_OFFSET, 0x00000000);
}

void PairHMMUserCore::get_result(uint32_t& result)
{
        reg_conv_t conv;
        this->platform()->read_mmio(REG_RESULT_OFFSET, &conv.full);
        result = conv.half.lo;
}


// write_mmio
