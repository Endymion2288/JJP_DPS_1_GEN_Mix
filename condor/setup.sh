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

# EOS输出目录 - 只保存最终MINIAOD
OUTPUT_BASE="/eos/user/x/xcheng/learn_MC/JJP_DPS_MC_output"
mkdir -p "${OUTPUT_BASE}/MINIAOD"

echo "Output directories created at: ${OUTPUT_BASE}"

# ============== 初始化VOMS代理 ==============
echo ""
echo "Setting up VOMS proxy for CMS grid access..."
echo "This is required for accessing pileup files from remote XRootD servers."
echo ""

# 检查是否已有有效的代理
if voms-proxy-info --exists --valid 24:00 2>/dev/null; then
    echo "Valid VOMS proxy found:"
    voms-proxy-info
else
    echo "No valid proxy found or proxy expires in less than 24 hours."
    echo "Initializing new VOMS proxy..."
    voms-proxy-init -voms cms -valid 192:00
    
    if [ $? -ne 0 ]; then
        echo "WARNING: voms-proxy-init failed!"
        echo "You need a valid CMS VOMS proxy to access pileup files."
        echo "Please run: voms-proxy-init -voms cms -valid 192:00"
    else
        echo "VOMS proxy created successfully:"
        voms-proxy-info
    fi
fi

export X509_USER_PROXY=$(voms-proxy-info -path)

# 复制proxy到AFS共享目录（HTCondor提交节点需要访问）
AFS_PROXY_PATH="/afs/cern.ch/user/x/xcheng/.globus/x509_proxy"
mkdir -p "$(dirname "${AFS_PROXY_PATH}")"
cp "${X509_USER_PROXY}" "${AFS_PROXY_PATH}"
chmod 600 "${AFS_PROXY_PATH}"
echo "Proxy copied to AFS: ${AFS_PROXY_PATH}"
echo "(This is needed for HTCondor job submission)"

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
echo "  1. Ensure VOMS proxy is valid (8 days):"
echo "     voms-proxy-info"
echo ""
echo "  2. Test a single job locally:"
echo "     ./test_local.sh 00010 03270 20"
echo ""
echo "  3. Submit all jobs to HTCondor:"
echo "     condor_submit condor_submit.sub"
echo ""
echo "  4. Check job status:"
echo "     condor_q"
echo ""
echo "  5. Check output files:"
echo "     ls ${OUTPUT_BASE}/MINIAOD/"
echo "=========================================="
