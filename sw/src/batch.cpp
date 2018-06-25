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

void fill_batch(t_batch& batch, int x, int y, float initial) {
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
        init.initials[k] = 0x10000000;//to_uint(initial_posit); -- TODO Laurens: remove this
    }

    for (int i = 0; i < xp + x - 1; i++) {
//        if (i < x) {
            read[i].base = XDATA[i];
//        } else // padding:
//        {
//            read[i].base = 'S';
//        }
    }

    for (int i = 0; i < yp + y - 1; i++) {
//        if (i < y) { // TODO Laurens correct to remove this?
            hapl[i].base = YDATA[i];
//        } else {
//            hapl[i].base = 'S';
//        }
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

//    for (int k = 0; k < PIPE_DEPTH; k++) {
//        posit<NBITS, ES> initial_posit(initial / yp);
//
//        // Get raw bits to send to HW
//        init.initials[k] = 0x10000000;//to_uint(initial_posit);
//
//        for (int i = 0; i < xbp; i++) {
//            if (i < x) {
//                read[i+k].base = XDATA[i + k];
//            } else // padding:
//            {
//                read[i+k].base = 'S';
//            }
//        }
//
//        for (int i = 0; i < ybp; i++) {
//            if (i < y) {
//                hapl[i+k].base = YDATA[i + k];
//            } else {
//                hapl[i+k].base = 'S';
//            }
//        }
//
//        for (int i = 0; i < xp; i++) {
////            srand((k * PIPE_DEPTH + i) * xp + x * 9949 + y * 9133); // Seed number generator
////
////            eta = random_number(0.5, 0.1);
////            zeta = random_number(0.125, 0.05);
////            epsilon = random_number(0.5, 0.1);
////            delta = random_number(0.125, 0.05);
////            beta = random_number(0.5, 0.1);
////            alpha = random_number(0.125, 0.05);
////            distm_diff = random_number(0.5, 0.1);
////            distm_simi = random_number(0.125, 0.05);
//
//            prob[i+k].p[0].b = (int) eta[i].collect().to_ulong();
//            prob[i+k].p[1].b = (int) zeta[i].collect().to_ulong();
//            prob[i+k].p[2].b = (int) epsilon[i].collect().to_ulong();
//            prob[i+k].p[3].b = (int) delta[i].collect().to_ulong();
//            prob[i+k].p[4].b = (int) beta[i].collect().to_ulong();
//            prob[i+k].p[5].b = (int) alpha[i].collect().to_ulong();
//            prob[i+k].p[6].b = (int) distm_diff[i].collect().to_ulong();
//            prob[i+k].p[7].b = (int) distm_simi[i].collect().to_ulong();
//
//        }
//    }

    // for (int k = 0; k < PIPE_DEPTH; k++) {
    //     posit<NBITS, ES> initial_posit(initial / yp);
    //
    //     // Get raw bits to send to HW
    //     init.initials[k] = to_uint(initial_posit);
    //
    //     for (int i = 0; i < xbp; i++) {
    //         if (i < x) {
    //             read[i].base[k] = XDATA[i + k];
    //         } else // padding:
    //         {
    //             read[i].base[k] = 'S';
    //         }
    //     }
    //
    //     for (int i = 0; i < ybp; i++) {
    //         if (i < y) {
    //             hapl[i].base[k] = YDATA[i + k];
    //         } else {
    //             hapl[i].base[k] = 'S';
    //         }
    //     }
    //
    //     for (int i = 0; i < xp; i++) {
    //         srand((k * PIPE_DEPTH + i) * xp + x * 9949 + y * 9133); // Seed number generator
    //
    //         eta = random_number(0.5, 0.1);
    //         zeta = random_number(0.125, 0.05);
    //         epsilon = random_number(0.5, 0.1);
    //         delta = random_number(0.125, 0.05);
    //         beta = random_number(0.5, 0.1);
    //         alpha = random_number(0.125, 0.05);
    //         distm_diff = random_number(0.5, 0.1);
    //         distm_simi = random_number(0.125, 0.05);
    //
    //         prob[i * PIPE_DEPTH + k].p[0].b = (int) eta.collect().to_ulong();
    //         prob[i * PIPE_DEPTH + k].p[1].b = (int) zeta.collect().to_ulong();
    //         prob[i * PIPE_DEPTH + k].p[2].b = (int) epsilon.collect().to_ulong();
    //         prob[i * PIPE_DEPTH + k].p[3].b = (int) delta.collect().to_ulong();
    //         prob[i * PIPE_DEPTH + k].p[4].b = (int) beta.collect().to_ulong();
    //         prob[i * PIPE_DEPTH + k].p[5].b = (int) alpha.collect().to_ulong();
    //         prob[i * PIPE_DEPTH + k].p[6].b = (int) distm_diff.collect().to_ulong();
    //         prob[i * PIPE_DEPTH + k].p[7].b = (int) distm_simi.collect().to_ulong();
    //     }
    // }
} // fill_batch
