# 1: output directory
echo `nproc` > $1/.job_nproc
echo $(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024))) > $1/.job_memory
date > $1/.job_start
df $1 > $1/.job_start_df
