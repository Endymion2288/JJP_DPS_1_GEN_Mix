#!/bin/bash
# setup.sh - 初始化脚本
# 创建必要的目录结构并编译所有程序
#
# 用法: source setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_BASE="$(dirname "${SCRIPT_DIR}")"
CMSSW_BASE="$(dirname "$(dirname "${WORK_BASE}")")"

echo "=========================================="
echo "JJP DPS MC Production Setup"
echo "=========================================="
echo "Script directory: ${SCRIPT_DIR}"
echo "Work base: ${WORK_BASE}"
echo "CMSSW base: ${CMSSW_BASE}"
echo ""

# ============== 创建目录 ==============
echo "Creating directories..."

# Condor日志目录
mkdir -p "${SCRIPT_DIR}/logs"

# EOS输出目录
OUTPUT_BASE="/eos/user/x/xcheng/learn_MC/JJP_DPS_MC_output"
mkdir -p "${OUTPUT_BASE}/hepmc"
mkdir -p "${OUTPUT_BASE}/GEN"
mkdir -p "${OUTPUT_BASE}/GENSIM"
mkdir -p "${OUTPUT_BASE}/RAW"
mkdir -p "${OUTPUT_BASE}/AOD"
mkdir -p "${OUTPUT_BASE}/MINIAOD"

echo "Output directories created at: ${OUTPUT_BASE}"

# ============== 设置CMSSW环境 ==============
echo ""
echo "Setting up CMSSW environment..."
cd "${CMSSW_BASE}/src"
source /cvmfs/cms.cern.ch/cmsset_default.sh
eval $(scramv1 runtime -sh)
echo "CMSSW_VERSION: ${CMSSW_VERSION}"
cd "${SCRIPT_DIR}"

# ============== 编译Pythia程序 ==============
echo ""
echo "Compiling Pythia8 programs..."
cd "${WORK_BASE}/pythia_shower"

# 使用CMSSW自带的库 (已通过Makefile配置)
echo "Using CMSSW libraries from cvmfs"

# 编译
make clean
make all

echo ""
echo "Compiled programs:"
ls -la shower_normal shower_phi event_mixer_hepmc2 2>/dev/null || echo "Some programs may not have compiled"

cd "${SCRIPT_DIR}"

# ============== 生成作业列表 ==============
echo ""
echo "Generating job list..."
chmod +x generate_job_list.sh
./generate_job_list.sh

# ============== 设置执行权限 ==============
echo ""
echo "Setting permissions..."
chmod +x condor_job.sh
chmod +x test_local.sh 2>/dev/null || true
chmod +x submit_jobs.sh 2>/dev/null || true
chmod +x check_status.sh 2>/dev/null || true

# ============== 完成 ==============
echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Test a single job locally:"
echo "     ./test_local.sh 00010"
echo ""
echo "  2. Submit all jobs to HTCondor:"
echo "     condor_submit condor_submit.sub"
echo ""
echo "  3. Check job status:"
echo "     condor_q"
echo ""
echo "  4. Check output files:"
echo "     ls ${OUTPUT_BASE}/MINIAOD/"
echo "=========================================="
