#!/bin/bash
# submit_jobs.sh - 提交作业到HTCondor
#
# 用法: 
#   ./submit_jobs.sh              # 提交所有作业
#   ./submit_jobs.sh 0 100        # 只提交前100个作业
#   ./submit_jobs.sh resubmit     # 重新提交失败的作业

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 检查必要文件
if [ ! -f "condor_submit.sub" ]; then
    echo "ERROR: condor_submit.sub not found"
    exit 1
fi

if [ ! -f "job_list.txt" ]; then
    echo "Job list not found. Generating..."
    ./generate_job_list.sh
fi

# 检查程序是否已编译
WORK_BASE="$(dirname "${SCRIPT_DIR}")"
if [ ! -f "${WORK_BASE}/pythia_shower/shower_normal" ] || \
   [ ! -f "${WORK_BASE}/pythia_shower/shower_phi" ] || \
   [ ! -f "${WORK_BASE}/pythia_shower/event_mixer_hepmc2" ]; then
    echo "ERROR: Pythia programs not compiled."
    echo "Please run: source setup.sh"
    exit 1
fi

# 确保日志目录存在
mkdir -p logs

# 提交作业
if [ "$1" == "resubmit" ]; then
    # 重新提交失败的作业
    if [ ! -f "resubmit_list.txt" ]; then
        echo "Generating resubmit list..."
        ./check_status.sh resubmit
    fi
    
    if [ -s "resubmit_list.txt" ]; then
        echo "Resubmitting failed jobs..."
        condor_submit condor_submit.sub -a 'queue lhe_block from resubmit_list.txt'
    else
        echo "No jobs to resubmit."
    fi
elif [ -n "$1" ] && [ -n "$2" ]; then
    # 提交指定范围的作业
    START="$1"
    END="$2"
    echo "Submitting jobs ${START} to ${END}..."
    
    # 创建临时作业列表
    sed -n "${START},${END}p" job_list.txt > temp_job_list.txt
    condor_submit condor_submit.sub -a 'queue lhe_block from temp_job_list.txt'
    rm -f temp_job_list.txt
else
    # 提交所有作业
    TOTAL_JOBS=$(wc -l < job_list.txt)
    echo "Submitting all ${TOTAL_JOBS} jobs..."
    read -p "Continue? (y/n) " confirm
    if [ "$confirm" != "y" ]; then
        echo "Aborted."
        exit 0
    fi
    condor_submit condor_submit.sub
fi

echo ""
echo "Jobs submitted. Check status with:"
echo "  condor_q"
echo "  ./check_status.sh"
