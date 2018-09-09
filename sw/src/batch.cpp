#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <posit/posit>
#include <iostream>
#include <iomanip>

#include "batch.hpp"
#include "utils.hpp"
#include "defines.hpp"

using namespace std;
using namespace sw::unum;

posit<NBITS, ES> random_number(float offset, float dev) {
    float num_float;
    posit<NBITS, 2> num_posit_2;
    posit<NBITS, 3> num_posit_3;

    do {
        num_float = offset + (rand() * dev / RAND_MAX);
        num_posit_2 = num_float;
        num_posit_3 = num_float;
    } while (num_posit_2 != num_float || num_posit_3 != num_float);

    return posit<NBITS, ES>(num_float);
}

uint32_t getProb(unsigned char rb) {
    uint32_t prob_A = 0x39201000;
    uint32_t prob_C = 0x39202000;
    uint32_t prob_T = 0x39203000;
    uint32_t prob_G = 0x39204000;
    // uint32_t prob_A = 0x39038FA0;
    // uint32_t prob_C = 0x398B1970;
    // uint32_t prob_T = 0x387CDA80;
    // uint32_t prob_G = 0x38393A00;

    if(rb == 'A') return prob_A;
    if(rb == 'C') return prob_C;
    if(rb == 'T') return prob_T;
    if(rb == 'G') return prob_G;
    return 0x38741A00;
}

void fill_batch(t_batch& batch, string& x_string, string& y_string, int batch_num, int x, int y, float initial) {
    t_inits& init = batch.init;
    std::vector<t_bbase>& read = batch.read;
    std::vector<t_bbase>& hapl = batch.hapl;
    std::vector<t_probs>& prob = batch.prob;

    int xp = px(x, y); // Padded read size
    int xbp = pbp(xp); // Padded base pair (how many reads)
    int yp = py(y); // Padded haplotype size
    int ybp = pbp(yp); // Padded base pair (how many haplos)

    read.resize(xp + x - 1); prob.resize(xp + x - 1); // TODO correct?
    hapl.resize(yp + y - 1);
    // hapl.resize(yp);

    init.x_size = xp;
    init.x_padded = xp;
    init.x_bppadded = xbp;
    init.y_size = yp;
    init.y_padded = ybp;

    std::array<posit<NBITS, ES>, 99> zeta, eta, epsilon, delta, beta, alpha, distm_diff, distm_simi;
    for (int i = 0; i < xp + x - 1; i++) {
        srand((i) * xp + x * 9949 + y * 9133); // Seed number generator

        // eta[i] = random_number(0.5, 0.1);
        // zeta[i] = random_number(0.125, 0.05);
        // epsilon[i] = random_number(0.5, 0.1);
        // delta[i] = random_number(0.125, 0.05);
        // beta[i] = random_number(0.5, 0.1);
        // alpha[i] = random_number(0.125, 0.05);//cout << x_string[batch_num * (xp + x - 1) + i] << " - " << hexstring(alpha[i].collect()) << endl;
        // distm_diff[i] = random_number(0.5, 0.1);
        // distm_simi[i] = random_number(0.125, 0.05);

        eta[i].set_raw_bits((getProb(x_string[batch_num * (xp + x - 1) + i]))); cout << x_string[batch_num * (xp + x - 1) + i] << " - " << hexstring(eta[i].collect()) << endl;
        zeta[i].set_raw_bits((getProb(x_string[batch_num * (xp + x - 1) + i])));
        epsilon[i].set_raw_bits((getProb(x_string[batch_num * (xp + x - 1) + i])));
        delta[i].set_raw_bits((getProb(x_string[batch_num * (xp + x - 1) + i])));
        beta[i].set_raw_bits((getProb(x_string[batch_num * (xp + x - 1) + i])));
        alpha[i].set_raw_bits((getProb(x_string[batch_num * (xp + x - 1) + i])));
        distm_diff[i].set_raw_bits((getProb(x_string[batch_num * (xp + x - 1) + i])));
        distm_simi[i].set_raw_bits((getProb(x_string[batch_num * (xp + x - 1) + i])));
    }
    cout << endl;

    posit<NBITS, ES> initial_posit(initial / yp);

    cout << "INITIAL: "  << hexstring(initial_posit.collect()) << endl;

    // Get raw bits to send to HW
    for(int k = 0; k < PIPE_DEPTH; k++) {
        init.initials[k] = to_uint(initial_posit);
    }

    for (int i = 0; i < xp + x - 1; i++) {
        read[i].base = x_string[batch_num * (xp + x - 1) + i];
    }

    for (int i = 0; i < yp + y - 1; i++) {
    // for (int i = 0; i < yp; i++) {
        hapl[i].base = y_string[batch_num * (yp + y - 1) + i];
        // hapl[i].base = y_string[batch_num * (yp) + i];
    }

    for (int i = 0; i < xp + x - 1; i++) {
        prob[i].p[0].b = (int) eta[i].collect().to_ulong();
        prob[i].p[1].b = (int) zeta[i].collect().to_ulong();
        prob[i].p[2].b = (int) epsilon[i].collect().to_ulong();
        prob[i].p[3].b = (int) delta[i].collect().to_ulong();
        prob[i].p[4].b = (int) beta[i].collect().to_ulong();
        prob[i].p[5].b = (int) alpha[i].collect().to_ulong();
        prob[i].p[6].b = (int) distm_diff[i].collect().to_ulong();
        prob[i].p[7].b = (int) distm_simi[i].collect().to_ulong();
    }
} // fill_batch

int batchToCore(int batch, std::vector<uint32_t>& batch_offsets) {
    int core = 0;
    for(uint32_t& offset : batch_offsets) {
        if(batch < offset) {
            return core - 1;
        }
        core++;
    }
    return -1;
}

int batchToCoreBatch(int batch, std::vector<uint32_t>& batch_length) {
    int batch_rem = batch;
    for(uint32_t& length : batch_length) {
        if(length >= batch_rem) {
            return batch_rem;
        }
        batch_rem = batch_rem - length;
    }
    return -1;
}
