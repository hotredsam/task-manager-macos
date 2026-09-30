#include "SystemBridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
static double mono(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
int main(int n,char**v){if(n<2)return 1;int pid=atoi(v[1]);TMProcess a,b;if(!tm_read_process(pid,&a))return 2;double t=mono();printf("[\n");for(int i=0;i<20;i++){sleep(1);double now=mono();if(!tm_read_process(pid,&b))return 3;printf("%s{\"cpu_one_core_percent\":%.5f,\"rss_mib\":%.3f}",i?",\n":"",(b.cpu_ns-a.cpu_ns)/(now-t)/1e9*100.,b.memory/1048576.);a=b;t=now;}printf("\n]\n");}
