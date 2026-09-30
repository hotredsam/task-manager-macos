#include <mach/mach.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
static atomic_int running=1;
static void *worker(void *p){pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED,0);volatile double x=1;while(atomic_load(&running)){for(int i=0;i<10000;i++) x=x*1.000000001+0.0000001;}return NULL;}
static unsigned sample(uint32_t v[256][CPU_STATE_MAX]){processor_info_array_t p;mach_msg_type_number_t n;natural_t cpus;mach_port_t h=mach_host_self();if(host_processor_info(h,PROCESSOR_CPU_LOAD_INFO,&cpus,&p,&n)!=KERN_SUCCESS)return 0;for(unsigned i=0;i<cpus;i++)for(int j=0;j<CPU_STATE_MAX;j++)v[i][j]=(uint32_t)p[i*CPU_STATE_MAX+j];vm_deallocate(mach_task_self(),(vm_address_t)p,n*sizeof(integer_t));mach_port_deallocate(mach_task_self(),h);return cpus;}
static void measure(const char *phase){uint32_t a[256][CPU_STATE_MAX],b[256][CPU_STATE_MAX];unsigned n=sample(a);sleep(4);sample(b);printf("%s\n",phase);for(unsigned i=0;i<n;i++){uint64_t total=0,idle=0;for(int j=0;j<CPU_STATE_MAX;j++){uint32_t d=b[i][j]-a[i][j];total+=d;if(j==CPU_STATE_IDLE)idle=d;}printf("CPU %2u: %5.1f%% busy, %llu idle / %llu total ticks\n",i,total?100.0*(total-idle)/total:0,idle,total);}fflush(stdout);}
int main(){measure("Normal workload");pthread_t threads[18];for(int i=0;i<18;i++)pthread_create(&threads[i],NULL,worker,NULL);measure("18 bounded CPU workers (4 seconds)");atomic_store(&running,0);for(int i=0;i<18;i++)pthread_join(threads[i],NULL);return 0;}
