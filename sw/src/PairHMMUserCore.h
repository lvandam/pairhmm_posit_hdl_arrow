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

#pragma once

#include <memory>

#include "fletcher/FPGAPlatform.h"
#include "fletcher/UserCore.h"

#include "batch.hpp"

#define CORES   2
#define MAX_CORES 8
#define BATCHES_PER_CORE 2

#define REG_CONTROL_OFFSET  1

#define REG_RESULT_DATA_OFFSET 8

#define REG_BATCH_OFFSET 16

#define REG_XLEN_OFFSET 20
#define REG_YLEN_OFFSET 24

#define REG_X_OFFSET 28
#define REG_Y_OFFSET 32

#define REG_XP_OFFSET 36
#define REG_YP_OFFSET 40

#define REG_XBPP_OFFSET 44
#define REG_INITIAL_OFFSET 48

/**
 * \class PairHMMUserCore
 *
 * A class to provide interaction with the regular expression matching UserCore example.
 */
class PairHMMUserCore : public fletcher::UserCore
{
public:
/**
 * \param platform  The platform to run the PairHMMUserCore on.
 */
PairHMMUserCore(std::shared_ptr<fletcher::FPGAPlatform> platform);

void set_batch_offsets(std::vector<uint32_t>& offsets);

void set_batch_init(std::vector<t_inits>& init, std::vector<uint32_t>& xlen, std::vector<uint32_t>& ylen);

void control_zero();

private:


};
