#pragma once

#include <cstdint>
#include <memory>
#include <vector>
#include <string>
#include <numeric>
#include <iostream>
#include <iomanip>
#include <fstream>
#include <omp.h>

using namespace std;

union ReadProb
{
        float f;
        unsigned char b[sizeof(float)];
};

void copyProbBytes(std::vector<ReadProb>& probs, uint8_t bytesArray[]) {
    int pos = 0;
    for(ReadProb prob : probs) {
        bytesArray[pos++] = prob.b[0];
        bytesArray[pos++] = prob.b[1];
        bytesArray[pos++] = prob.b[2];
        bytesArray[pos++] = prob.b[3];
    }
}
