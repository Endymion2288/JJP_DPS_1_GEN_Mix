#!/bin/bash
# check_status.sh - 检查HTCondor作业状态和输出文件
#
# 用法: ./check_status.sh [option]
# 选项:
#   jobs    - 显示HTCondor作业状态
#   output  - 检查输出文件
#   failed  - 列出失败的作业
#   missing - 列出缺失的输出文件
#   all     - 显示所有信息 (默认)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_BASE="/eos/user/x/xcheng/learn_MC/JJP_DPS_MC_output"
LHE_DIR="/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks"
JOB_LIST="${SCRIPT_DIR}/job_list.txt"

option="${1:-all}"

show_jobs() {
    echo "=========================================="
    echo "HTCondor Job Status"
    echo "=========================================="
    condor_q -nobatch 2>/dev/null || echo "No jobs in queue or condor_q not available"
    echo ""
    
    # 统计
    echo "Job summary:"
    condor_q 2>/dev/null | tail -5
}

show_output() {
    echo "=========================================="
    echo "Output Files Status"
    echo "=========================================="
    
    echo ""
    echo "HepMC files: $(ls -1 "${OUTPUT_BASE}/hepmc/"*.hepmc 2>/dev/null | wc -l)"
    echo "GEN files:   $(ls -1 "${OUTPUT_BASE}/GEN/"*.root 2>/dev/null | wc -l)"
    echo "GENSIM files:$(ls -1 "${OUTPUT_BASE}/GENSIM/"*.root 2>/dev/null | wc -l)"
    echo "RAW files:   $(ls -1 "${OUTPUT_BASE}/RAW/"*.root 2>/dev/null | wc -l)"
    echo "AOD files:   $(ls -1 "${OUTPUT_BASE}/AOD/"*.root 2>/dev/null | wc -l)"
    echo "MiniAOD files: $(ls -1 "${OUTPUT_BASE}/MINIAOD/"*.root 2>/dev/null | wc -l)"
    
    echo ""
    echo "Total LHE files: $(ls -1 "${LHE_DIR}/"*.lhe 2>/dev/null | wc -l)"
    
    # 显示最近的输出文件
    echo ""
    echo "Latest MiniAOD files:"
    ls -lt "${OUTPUT_BASE}/MINIAOD/"*.root 2>/dev/null | head -5
}

show_failed() {
    echo "=========================================="
    echo "Failed Jobs"
    echo "=========================================="
    
    # 检查日志文件中的错误
    echo "Recent errors in log files:"
    grep -l "ERROR\|Error\|error\|FAILED\|failed" "${SCRIPT_DIR}/logs/"*.stderr 2>/dev/null | head -10
    
    echo ""
    echo "Jobs that exited with non-zero status:"
    grep -l "return value [1-9]" "${SCRIPT_DIR}/logs/"*.log 2>/dev/null | head -10
}

show_missing() {
    echo "=========================================="
    echo "Missing Output Files"
    echo "=========================================="
    
    if [ ! -f "${JOB_LIST}" ]; then
        echo "Job list not found: ${JOB_LIST}"
        echo "Run ./generate_job_list.sh first"
        return
    fi
    
    echo ""
    echo "Blocks without MiniAOD output:"
    missing_count=0
    while read block; do
        output_file="${OUTPUT_BASE}/MINIAOD/JJP_DPS_block_${block}_MINIAOD.root"
        if [ ! -f "${output_file}" ]; then
            echo "  ${block}"
            ((missing_count++))
        fi
    done < "${JOB_LIST}"
    
    echo ""
    echo "Total missing: ${missing_count}"
}

generate_resubmit() {
    echo "=========================================="
    echo "Generating Resubmit List"
    echo "=========================================="
    
    RESUBMIT_LIST="${SCRIPT_DIR}/resubmit_list.txt"
    > "${RESUBMIT_LIST}"
    
    count=0
    while read block; do
        output_file="${OUTPUT_BASE}/MINIAOD/JJP_DPS_block_${block}_MINIAOD.root"
        if [ ! -f "${output_file}" ]; then
            echo "${block}" >> "${RESUBMIT_LIST}"
            ((count++))
        fi
    done < "${JOB_LIST}"
    
    echo "Generated resubmit list with ${count} jobs: ${RESUBMIT_LIST}"
    echo ""
    echo "To resubmit failed jobs:"
    echo "  condor_submit condor_submit.sub -a 'queue lhe_block from resubmit_list.txt'"
}

case "$option" in
    jobs)
        show_jobs
        ;;
    output)
        show_output
        ;;
    failed)
        show_failed
        ;;
    missing)
        show_missing
        ;;
    resubmit)
        generate_resubmit
        ;;
    all)
        show_jobs
        echo ""
        show_output
        echo ""
        show_failed
        echo ""
        show_missing
        ;;
    *)
        echo "Usage: $0 [jobs|output|failed|missing|resubmit|all]"
        exit 1
        ;;
esac
