//
// Created by laurens on 18-4-18.
//

#ifndef PAIRHMM_FLOAT_HPP
#define PAIRHMM_FLOAT_HPP

#include <iostream>
#include <vector>
#include <posit/posit>

#include "debug_values.hpp"
#include "defines.hpp"
#include "utils.hpp"
#include "batch.hpp"

using namespace std;
using namespace sw::unum;

template<class T>
class PairHMMFloat {
typedef vector<T> t_result_sw;
typedef vector<t_result_sw> t_matrix;

private:
std::vector<t_result_sw> result_sw, result_sw_m, result_sw_i;
t_workload *workload;
bool show_results, show_table;

public:
DebugValues<T> debug_values;

PairHMMFloat(t_workload *wl, bool show_results, bool show_table) : workload(wl), show_results(show_results),
        show_table(show_table) {
        result_sw.resize(workload->batches * (PIPE_DEPTH + 1));
        result_sw_m.resize(workload->batches * (PIPE_DEPTH + 1));
        result_sw_i.resize(workload->batches * (PIPE_DEPTH + 1));
        for (int i = 0; i < workload->batches * (PIPE_DEPTH + 1); i++) {
                result_sw[i] = t_result_sw(3, 0);
                result_sw_m[i] = t_result_sw(3, 0);
                result_sw_i[i] = t_result_sw(3, 0);
        }
}

void calculate(std::vector<t_batch>& batches) {
        for (int i = 0; i < workload->batches; i++) {
                int x = workload->bx[i];
                int y = workload->by[i];

                t_matrix M(x + 1, vector<T>(y + 1));
                t_matrix I(x + 1, vector<T>(y + 1));
                t_matrix D(x + 1, vector<T>(y + 1));

                // Calculate results
                for (int j = 0; j < PIPE_DEPTH; j++) {
                        calculate_mids(batches[i], j, x, y, M, I, D);

                        // result_sw[i * PIPE_DEPTH + j][0] = 0.0;
                        result_sw[i * PIPE_DEPTH + j][0] = 0.0;
                        result_sw_m[i * PIPE_DEPTH + j][0] = 0.0;
                        result_sw_i[i * PIPE_DEPTH + j][0] = 0.0;
                        for (int c = 1; c < y + 1; c++) {
                                result_sw_m[i * PIPE_DEPTH + j][0] += M[x][c];
                                result_sw_i[i * PIPE_DEPTH + j][0] += I[x][c];
                        }
                        result_sw[i*PIPE_DEPTH+j][0] = result_sw_m[i * PIPE_DEPTH + j][0] + result_sw_i[i * PIPE_DEPTH + j][0];

                        debug_values.debugValue(result_sw[i * PIPE_DEPTH + j][0], "result[%d][%d]", i, j);//(i * PIPE_DEPTH + j));

                        if (show_table) {
                                print_mid_table(batches[i], j, x, y, M, I, D);
                        }
                }
        }

        if (show_results) {
                print_results();
        }
}

void calculate_mids(t_batch& batch, int pair, int x, int y, t_matrix& M, t_matrix& I, t_matrix& D) {
        t_inits& init = batch.init;
        std::vector<t_bbase>& read = batch.read;
        std::vector<t_bbase>& hapl = batch.hapl;
        std::vector<t_probs>& prob = batch.prob;

        posit<NBITS, ES> initial;
        initial.set_raw_bits(init.initials[pair]);

        // Set to zero and intial value in the X direction
        for (int j = 0; j < x + 1; j++) {
                M[0][j] = 0;
                I[0][j] = 0;
                D[0][j] = (T) initial;
        }

        // Set to zero in Y direction
        for (int i = 1; i < y + 1; i++) {
                M[i][0] = 0;
                I[i][0] = 0;
                D[i][0] = 0;
        }

        posit<NBITS, ES> distm_simi, distm_diff, alpha, beta, delta, epsilon, zeta, eta, distm;
        for (int i = 1; i < x + 1; i++) {
                unsigned char rb = read[i - 1 + pair].base;

                eta.set_raw_bits(prob[(i - 1) + pair].p[0].b);
                zeta.set_raw_bits(prob[(i - 1) + pair].p[1].b);
                epsilon.set_raw_bits(prob[(i - 1) + pair].p[2].b);
                delta.set_raw_bits(prob[(i - 1) + pair].p[3].b);
                beta.set_raw_bits(prob[(i - 1) + pair].p[4].b);
                alpha.set_raw_bits(prob[(i - 1) + pair].p[5].b);
                distm_diff.set_raw_bits(prob[(i - 1) + pair].p[6].b);
                distm_simi.set_raw_bits(prob[(i - 1) + pair].p[7].b);

                for (int j = 1; j < y + 1; j++) {
                        unsigned char hb = hapl[j - 1 + pair].base;

                        if (rb == hb || rb == 'N' || hb == 'N') {
                                distm = distm_simi;
                        } else {
                                distm = distm_diff;
                        }

                        M[i][j] = (T)distm * ((T)alpha * M[i - 1][j - 1] + (T)beta * I[i - 1][j - 1] + (T)beta * D[i - 1][j - 1]);
                        I[i][j] = (T)delta * M[i - 1][j] + (T)epsilon * I[i - 1][j];
                        D[i][j] = (T)zeta * M[i][j - 1] + (T)eta * D[i][j - 1];
                }
        }
}     // calculate_mids

void print_mid_table(t_batch& batch, int pair, int r, int c, t_matrix& M, t_matrix& I, t_matrix& D) {
        int w = c + 1;
        std::vector<t_bbase>& read = batch.read;
        std::vector<t_bbase>& hapl = batch.hapl;

        T res[3];

        res[0] = static_cast<T>(0.0);

        printf("════╦");
        for (uint32_t i = 0; i < c + 1; i++) {
                printf("══════════════════════════╦");
        }
        printf("\n");
        printf("    ║");
        for (uint32_t i = 0; i < c + 1; i++) {
                printf("      %5d , %c           ║", i, (i > 0) ? (hapl[i - 1 + pair].base) : '-');
        }
        printf("\n");
        printf("%3d ║", pair);
        for (uint32_t i = 0; i < c + 1; i++) {
                printf("══════════════════════════╣");
        }
        printf("\n");
        printf("    ║");
        for (uint32_t i = 0; i < c + 1; i++) {
                printf("   M        I        D    ║");
        }
        printf("\n");
        printf("════╣");
        for (uint32_t i = 0; i < c + 1; i++) {
                printf("══════════════════════════╣");
        }
        printf("\n");

        // loop over rows
        for (uint32_t j = 0; j < r + 1; j++) {
                printf("%2d,%c║", j, (j > 0) ? (read[j - 1 + pair].base) : ('-'));
                // loop over columns
                for (uint32_t i = 0; i < c + 1; i++) {
                        printf("%08X %08X %08X║", (float) M[j][i], (float) I[j][i], (float) D[j][i]);
                }
                printf("\n");
        }
        printf("════╣");
        for (uint32_t i = 0; i < c + 1; i++) {
                printf("══════════════════════════╣");
        }
        printf("\n");
        // Result row
        printf("res:║");
        for (uint32_t i = 0; i < c + 1; i++) {
                res[0] += M[r][i];
                res[0] += I[r][i];

                cout << "                  " << hex << res[0] << "║";
        }
        printf("\n");
        printf("═════");
        for (uint32_t i = 0; i < c + 1; i++) {
                printf("═══════════════════════════");
        }
        printf("\n");
}     // print_mid_table

void print_results() {
        cout << "══════════════════════════════════════════════════════════════" << endl;

        if (strcmp(typeid(T).name(), "f") == 0) {
                cout << "════════════════════════════ FLOAT ═══════════════════════════" << endl;
        } else {
                cout << "═══════════════════════ CPP_DEC_FLOAT_100 ════════════════════" << endl;
        }

        cout << "══════════════════════════════════════════════════════════════" << endl;
        cout << "╔═════════════════════════════════════╗" << endl;
        for (int i = 0; i < workload->batches; i++) {
                cout << "║ RESULT FOR BATCH " << i << ":                 ║       DECIMAL" << endl;
                cout << "╠═════════════════════════════════════╣" << endl;
                for (int j = 0; j < PIPE_DEPTH; j++) {
                        printf("║%2d: ", j);
                        cout << setw(10) << result_sw[i * PIPE_DEPTH + j][0];
                        cout << " ";
                        cout << setw(10) << result_sw[i * PIPE_DEPTH + j][1];
                        cout << " ";
                        cout << setw(10) << result_sw[i * PIPE_DEPTH + j][2];
                        cout << " ║       ";
                        cout << setprecision(10) << result_sw[i * PIPE_DEPTH + j][0];
                        cout << endl;
                }
                cout << "╚═════════════════════════════════════╝" << endl;
        }
        cout << endl;
}     // print_results
};

#endif //PAIRHMM_FLOAT_HPP
