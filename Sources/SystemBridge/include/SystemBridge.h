#ifndef SystemBridge_h
#define SystemBridge_h
#include <stdint.h>
typedef struct {
 int32_t pid, ppid, uid, state, threads, nice_value, arch, metrics_valid, io_valid;
 uint64_t cpu_ns, memory, read_bytes, write_bytes, start_sec, start_usec;
 char name[256], path[4096], user[256];
} TMProcess;
typedef struct {
 uint64_t cpu_user, cpu_system, cpu_idle, cpu_nice;
 uint64_t ram, active, inactive, wired, compressed, free_bytes, purgeable, speculative, swap_used, swap_total;
 uint64_t disk_read, disk_write, net_in, net_out, disk_capacity, disk_free;
 int disk_valid, pressure, logical, physical, performance, efficiency;
 double uptime, load1, load5, load15;
 char cpu_brand[256], filesystem[64], mount[256], device[256], interfaces[2048];
} TMSystem;
typedef struct { uint32_t user, system, idle, nice; } TMCPU;
int tm_cpu_load(TMCPU **out);
int tm_processes(TMProcess **out);
void tm_free(void *p);
uint64_t tm_ticks_to_ns(uint64_t ticks);
int tm_read_process(int pid, TMProcess *p);
void tm_system(TMSystem *s);
int tm_arguments(int pid, char *buffer, int capacity);
int tm_open_files(int pid);
int tm_sessions(char *buffer, int capacity);
#endif
