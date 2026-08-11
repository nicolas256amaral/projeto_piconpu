#ifndef NPU_TEST_H
#define NPU_TEST_H

#include <stdint.h>

extern volatile uint32_t tl_out_words[4];
extern volatile int32_t  tl_score_red;
extern volatile int32_t  tl_score_green;
extern volatile uint32_t tl_predicted_label;
extern volatile uint32_t tl_model_initialized;

void tl_init_model(void);
void tl_run_features(const uint8_t features[]);

#endif