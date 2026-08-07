#ifndef NPU_TEST_H
#define NPU_TEST_H

#include <stdint.h>

extern volatile uint32_t tl_out_words[4];
extern volatile int32_t  tl_score_red;
extern volatile int32_t  tl_score_green;
extern volatile uint32_t tl_predicted_label;
extern volatile uint32_t tl_expected_label_last;
extern volatile uint32_t tl_last_sample_index;

void tl_run_features(const uint8_t features[]);
void tl_run_sample(uint32_t sample_idx);
void tl_run_test_suite(void);

#endif
