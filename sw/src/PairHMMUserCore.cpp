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
        ctrl_start       = 0x0000000000000001;// 0x00000000000000FF;
        ctrl_reset       = 0x0000000000000002;// 0x000000000000FF00;
        done_status      = 0x0000000000000002;// 0x000000000000FF00;
        done_status_mask = 0x0000000000000003;// 0x000000000000FFFF;
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

void PairHMMUserCore::set_batch_init(t_inits& init, uint32_t xlen, uint32_t ylen) {
    // For now, duplicate batch information across all core MMIO registers
    uint32_t xlens[CORES], ylens[CORES], xsizes[CORES], ysizes[CORES], x_paddeds[CORES], y_paddeds[CORES], xbpps[CORES], initials[CORES];
    for (int i = 0; i < roundToMultiple(CORES, 2); i++) {
        xlens[i] = xlen;
        ylens[i] = ylen;
        xsizes[i] = init.x_size;
        ysizes[i] = init.y_size;
        x_paddeds[i] = init.x_padded;
        y_paddeds[i] = init.y_padded;
        xbpps[i] = init.x_bppadded;
        initials[i] = init.initials[0];
    }

    for (int i = 0; i < (int)ceil((float)CORES / 2); i++) {
        reg_conv_t reg;

        reg.half.hi = xlens[2 * i];
        reg.half.lo = xlens[2 * i + 1];
        this->platform()->write_mmio(REG_XLEN_OFFSET + i, reg.full);

        reg.half.hi = ylens[2 * i];
        reg.half.lo = ylens[2 * i + 1];
        this->platform()->write_mmio(REG_YLEN_OFFSET + i, reg.full);

        reg.half.hi = xsizes[2 * i];
        reg.half.lo = xsizes[2 * i + 1];
        this->platform()->write_mmio(REG_X_OFFSET + i, reg.full);

        reg.half.hi = ysizes[2 * i];
        reg.half.lo = ysizes[2 * i + 1];
        this->platform()->write_mmio(REG_Y_OFFSET + i, reg.full);

        reg.half.hi = x_paddeds[2 * i];
        reg.half.lo = x_paddeds[2 * i + 1];
        this->platform()->write_mmio(REG_XP_OFFSET + i, reg.full);

        reg.half.hi = y_paddeds[2 * i];
        reg.half.lo = y_paddeds[2 * i + 1];
        this->platform()->write_mmio(REG_YP_OFFSET + i, reg.full);

        reg.half.hi = xbpps[2 * i];
        reg.half.lo = xbpps[2 * i + 1];
        this->platform()->write_mmio(REG_XBPP_OFFSET + i, reg.full);

        reg.half.hi = initials[2 * i];
        reg.half.lo = initials[2 * i + 1];
        this->platform()->write_mmio(REG_INITIAL_OFFSET + i, reg.full);
    }
}

void PairHMMUserCore::control_zero()
{
        this->platform()->write_mmio(REG_CONTROL_OFFSET, 0x00000000);
}
