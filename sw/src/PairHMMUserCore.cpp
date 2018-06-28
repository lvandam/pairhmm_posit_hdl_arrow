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
#include "defines.hpp"
#include "utils.hpp"

using namespace fletcher;

PairHMMUserCore::PairHMMUserCore(std::shared_ptr<fletcher::FPGAPlatform> platform)
        : UserCore(platform)
{
        // Some settings that are different from standard implementation
        // concerning start, reset and status register.
        ctrl_start       = 0x0000000000000003;// 0x00000000000000FF;
        ctrl_reset       = 0x000000000000000C;// 0x000000000000FF00;
        done_status      = 0x000000000000000C;// 0x000000000000FF00;
        done_status_mask = 0x000000000000000C;// 0x000000000000FFFF;
}

void PairHMMUserCore::set_batch_offsets(std::vector<uint32_t>& offsets) {
        for (int i = 0; i < MAX_CORES / 2; i++) {
            reg_conv_t reg;

            if(i < CORES) {
                reg.half.hi = offsets[2 * i];
                reg.half.lo = offsets[2 * i + 1];
            } else {
                reg.half.hi = 0x00000000;
                reg.half.lo = 0x00000000;
            }

            this->platform()->write_mmio(REG_BATCH_OFFSET + i, reg.full);
        }
}

void PairHMMUserCore::set_batch_init(std::vector<t_inits>& init, std::vector<uint32_t>& xlen, std::vector<uint32_t>& ylen) {
    for (int i = 0; i < (int)ceil((float)CORES / 2); i++) {
        reg_conv_t reg;

        reg.half.hi = xlen[2 * i];
        reg.half.lo = xlen[2 * i + 1];
        this->platform()->write_mmio(REG_XLEN_OFFSET + i, reg.full);

        reg.half.hi = ylen[2 * i];
        reg.half.lo = ylen[2 * i + 1];
        this->platform()->write_mmio(REG_YLEN_OFFSET + i, reg.full);

        reg.half.hi = init[2 * i].x_size;
        reg.half.lo = init[2 * i + 1].x_size;
        this->platform()->write_mmio(REG_X_OFFSET + i, reg.full);

        reg.half.hi = init[2 * i].y_size;
        reg.half.lo = init[2 * i + 1].y_size;
        this->platform()->write_mmio(REG_Y_OFFSET + i, reg.full);

        reg.half.hi = init[2 * i].x_padded;
        reg.half.lo = init[2 * i + 1].x_padded;
        this->platform()->write_mmio(REG_XP_OFFSET + i, reg.full);

        reg.half.hi = init[2 * i].y_padded;
        reg.half.lo = init[2 * i + 1].y_padded;
        this->platform()->write_mmio(REG_YP_OFFSET + i, reg.full);

        reg.half.hi = init[2 * i].x_bppadded;
        reg.half.lo = init[2 * i + 1].x_bppadded;
        this->platform()->write_mmio(REG_XBPP_OFFSET + i, reg.full);

        reg.half.hi = init[2 * i].initials[0];
        reg.half.lo = init[2 * i + 1].initials[0];
        this->platform()->write_mmio(REG_INITIAL_OFFSET + i, reg.full);
    }
}

void PairHMMUserCore::control_zero()
{
        this->platform()->write_mmio(REG_CONTROL_OFFSET, 0x00000000);
}
