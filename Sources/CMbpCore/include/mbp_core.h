#ifndef MBP_CORE_H
#define MBP_CORE_H
#include <stdint.h>
#include <stddef.h>
typedef struct { double alpha, smoothed; uint32_t state; int32_t candidate; uint32_t candidate_count, has_smoothed; } MbpMachine;
typedef struct { double usage, smoothed; uint32_t state; } MbpSnapshot;
typedef struct { double x, y, width, height; } MbpRect;
typedef struct { double wheel_angle, front, rear, intensity, body_offset, breathing, overlay_pulse; MbpRect bounds; } MbpHamsterFrame;
typedef struct {
    double front, rear, bounce, breathing, scale_x, scale_y, lean, tail, shadow_scale, shadow_opacity, overlay_pulse;
    MbpRect overlay, bounds;
    uint32_t has_overlay;
} MbpShibaFrame;
MbpMachine mbp_machine_new(double alpha);
MbpSnapshot mbp_machine_ingest(MbpMachine *machine, double raw, uint32_t sensitivity);
uint32_t mbp_classify(double usage, double a, double b, double c, double d);
double mbp_phase(double phase);
double mbp_cycle_duration(double cpu);
double mbp_fps(uint32_t state, double cpu, int64_t frame_count);
int64_t mbp_frame_index(double phase, int64_t frame_count);
double mbp_amplitude(uint32_t state);
double mbp_wheel_cycle(double cpu);
double mbp_wheel_increment(double elapsed, double cpu);
double mbp_wheel_angle(uint32_t state, double phase);
double mbp_bounce(double phase);
MbpRect mbp_scaled_body_extent(uint32_t state);
MbpHamsterFrame mbp_hamster_frame(uint32_t state, double phase, double wheel_phase, uint32_t reduce_motion);
MbpShibaFrame mbp_shiba_frame(uint32_t state, double phase, uint32_t reduce_motion);
typedef struct { uint8_t *data; size_t len, capacity; } MbpBuffer;
MbpBuffer mbp_usage_parse(const uint8_t *data, size_t len, uint32_t kind);
MbpBuffer mbp_read_tail(const uint8_t *path, size_t len, size_t max_bytes);
void mbp_buffer_free(MbpBuffer buffer);
double mbp_effective_used(double used, double resets, double now);
uint32_t mbp_limit_is_fresh(double observed, double now);
typedef struct { uint32_t ticks[4], initialized; } MbpCpuSampler;
typedef struct { double received, sent; } MbpNetworkSample;
typedef struct MbpNetworkSampler MbpNetworkSampler;
double mbp_cpu_sample(MbpCpuSampler *sampler);
uint32_t mbp_memory_usage(void);
MbpNetworkSampler *mbp_network_new(void);
MbpNetworkSample mbp_network_sample(MbpNetworkSampler *sampler, double now);
void mbp_network_free(MbpNetworkSampler *sampler);
#endif
