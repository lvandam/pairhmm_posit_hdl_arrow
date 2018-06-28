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

const char XDATA[] = "GTGGTGCGAGTAGTGAGTAGTGGCTTCCATTGGCGACCGGCCGATATTGCTGCCTACTTGGAGATTTTAAGTACTACTGTTAGTAATCGCGTAATCGCCTTTGTTCTGCGAACACTCGTCATCATATCATACGTACGTCTTTGCTGCACCGTAGCGGGCAATAGGAGGAAGTCCCGGCCCGGTTGCAAAAACCCAATAGTCACTGTGGTACGATAGTGGTATCACCGTGTCAATAATTAGACCATGTTGTCCATATGTGACCGTTCAGCGCACTTAAAATGCTCTGTACTATAAGTTGATGGAATACTACGGCGTTAATCGGGTCTTTTGTCGTACGAATTTAGACGGCCTACATCTTGACAACGCCGGCTTTTGTTGGATGGCCCGTAATCCAATGGAACACAGTTTCTGTAGCATTGAGCAGTACCCGGTATAGACTTCTGCGCTCTAACCTTACTGTATATATCTGTGGTTGTTCCGTAGCCGTTGAGTCGAGCTTTGTAAAAGCAGGGCCTGCGGTAACGTAGAATGATCCTCCCATGGCCGGGGAGCCGTCAAGG";
const char YDATA[] = "ATTGTCTGCCTCCACCACCTTGAATCGTAAATCGAGCACGATCACCCGTACGGTTATCGGCCAGATACTCCTCTGAAGGTGGTGCGAGAGCTGTAACATCGCTTGACGGACAGGCCCTCCAGGGTCAACCCCACGGATAATGACATGCGCCACCCAACTACATTTTTATTACTTAGTAGACACCGTACACACGTGGTGCCGAGACGTATTAGTGTTGTTAATTTTACAGTCGCACTGCGTGACGGGTGCCGCGCATGCCTGTAGGTGGGCGTCTGCCCATATGTGTCTTACAAGATGTGAGCCTTTGAGGGGACATAAAATTGGGTTTAAACTAGCATACATTTTTGATCAGCGAGATTGTTGCTCCCGACTAGTCGGCGTCCTCAGGTGGCCCTTTTCCTGCAACTGGTTTAAACGTGGTATGTCGCTTGGCCCGTGTCACGTCCTTTGCTGAAGGTGCCAGACACCATTGGGCAGACTGCTATGGGGATCACGAGGGCTATGGTGACTGCTACAACTGCGATTACTGACCAGCGAAACACTTTTACTACTTATAGGTG";

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

void fill_batch(t_batch& batch, int batch_num, int x, int y, float initial) {
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

    init.x_size = xp;
    init.x_padded = xp;
    init.x_bppadded = xbp;
    init.y_size = yp;
    init.y_padded = ybp;

    std::array<posit<NBITS, ES>, 99> zeta, eta, epsilon, delta, beta, alpha, distm_diff, distm_simi;
    for (int i = 0; i < xp + x - 1; i++) {
        srand((i) * xp + x * 9949 + y * 9133); // Seed number generator

        eta[i] = random_number(0.5, 0.1);
        zeta[i] = random_number(0.125, 0.05);
        epsilon[i] = random_number(0.5, 0.1);
        delta[i] = random_number(0.125, 0.05);
        beta[i] = random_number(0.5, 0.1);
        alpha[i] = random_number(0.125, 0.05);
        distm_diff[i] = random_number(0.5, 0.1);
        distm_simi[i] = random_number(0.125, 0.05);
    }

    posit<NBITS, ES> initial_posit(initial / yp);

    // Get raw bits to send to HW
    for(int k = 0; k < PIPE_DEPTH; k++) {
        init.initials[k] = to_uint(initial_posit);
    }

    for (int i = 0; i < xp + x - 1; i++) {
        read[i].base = XDATA[batch_num * (xp + x - 1) + i];
    }

    for (int i = 0; i < yp + y - 1; i++) {
        hapl[i].base = YDATA[batch_num * (yp + y - 1) + i];
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
