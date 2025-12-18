#!/bin/bash
# condor_job.sh - HTCondor worker节点执行脚本
# 完整工作流程：LHE -> 两种Shower -> 混合 -> CMSSW处理 -> MiniAOD
#
# 注意: normal和phi shower使用不同的LHE文件，避免事例相关性
#
# 用法: ./condor_job.sh <job_id> <lhe_block_normal> <lhe_block_phi>
# 例如: ./condor_job.sh 1 00010 00020

set -e

# ============== 清理函数 ==============
# 确保在任何情况下（包括失败）都清理中间文件
# 这样避免HTCondor尝试传输大文件
cleanup() {
    echo ""
    echo "=========================================="
    echo "Cleaning up intermediate files..."
    echo "=========================================="
    
    # 清理所有可能存在的中间文件
    if [ -n "${WORK_DIR}" ] && [ -d "${WORK_DIR}" ]; then
        rm -f "${WORK_DIR}"/*.hepmc 2>/dev/null || true
        rm -f "${WORK_DIR}"/*_GENSIM.root 2>/dev/null || true
        rm -f "${WORK_DIR}"/*_RAW.root 2>/dev/null || true
        rm -f "${WORK_DIR}"/*_AOD.root 2>/dev/null || true
        rm -f "${WORK_DIR}"/*_MINIAOD.root 2>/dev/null || true
        rm -f "${WORK_DIR}"/*.py 2>/dev/null || true
        rm -f "${WORK_DIR}"/*.pyc 2>/dev/null || true
        
        # 如果使用的是手动创建的临时目录，删除整个目录
        if [ -z "${_CONDOR_SCRATCH_DIR}" ]; then
            rm -rf "${WORK_DIR}" 2>/dev/null || true
        fi
    fi
    
    echo "Cleanup completed"
}

# 设置trap，确保退出时清理
trap cleanup EXIT

# ============== 参数解析 ==============
JOB_ID="${1}"
LHE_BLOCK_NORMAL="${2}"
LHE_BLOCK_PHI="${3}"

if [ -z "$JOB_ID" ] || [ -z "$LHE_BLOCK_NORMAL" ] || [ -z "$LHE_BLOCK_PHI" ]; then
    echo "Usage: $0 <job_id> <lhe_block_normal> <lhe_block_phi>"
    echo "Example: $0 1 00010 00020"
    echo ""
    echo "Note: normal and phi showers use DIFFERENT LHE files to avoid correlation"
    exit 1
fi

echo "=========================================="
echo "HTCondor Job Starting"
echo "Job ID: ${JOB_ID}"
echo "LHE Block (Normal): ${LHE_BLOCK_NORMAL}"
echo "LHE Block (Phi):    ${LHE_BLOCK_PHI}"
echo "Start time: $(date)"
echo "Hostname: $(hostname)"
echo "=========================================="

# ============== 路径配置 ==============
# 源目录（只读）
LHE_DIR="/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks"
WORK_BASE="/afs/cern.ch/user/x/xcheng/condor/CMSSW_12_4_14_patch3/src/JJP_DPS_1_GEN_Mix"
CMSSW_BASE="/afs/cern.ch/user/x/xcheng/condor/CMSSW_12_4_14_patch3"

# 输出目录（EOS）- 只保存最终的MINIAOD
OUTPUT_BASE="/eos/user/x/xcheng/learn_MC/JJP_DPS_MC_output"
OUTPUT_MINIAOD="${OUTPUT_BASE}/MINIAOD"

# 工具路径
PYTHIA_SHOWER_DIR="${WORK_BASE}/pythia_shower"
CMSSW_CONFIG_DIR="${WORK_BASE}/cmssw_configs"

# HepMC库路径 (使用CMSSW自带的版本)
PYTHIA8_BASE="/cvmfs/cms.cern.ch/el8_amd64_gcc10/external/pythia8/306-494ded5c626b685d055d5b022e918c0c"
HEPMC3_BASE="/cvmfs/cms.cern.ch/el8_amd64_gcc10/external/hepmc3/3.2.5-c3cd50aeecf06b194814f1a75bf7872e"
HEPMC2_BASE="/cvmfs/cms.cern.ch/el8_amd64_gcc10/external/hepmc/2.06.10-46867a6dcc6e5712b7953fe57085fcbd"

# ============== 本地工作目录 ==============
# 使用condor的scratch目录存储所有中间文件
# 这样避免占用AFS空间，且性能更好
if [ -n "$_CONDOR_SCRATCH_DIR" ]; then
    WORK_DIR="${_CONDOR_SCRATCH_DIR}"
else
    # 本地测试时使用/tmp
    WORK_DIR="/tmp/condor_job_${USER}_${JOB_ID}_${LHE_BLOCK_NORMAL}_${LHE_BLOCK_PHI}"
    mkdir -p "${WORK_DIR}"
fi

cd "${WORK_DIR}"
echo "Working directory: ${WORK_DIR}"

# ============== 创建输出目录 ==============
mkdir -p "${OUTPUT_MINIAOD}"

# ============== 定义文件名 ==============
LHE_FILE_NORMAL="${LHE_DIR}/MC_Jpsi_block_${LHE_BLOCK_NORMAL}.lhe"
LHE_FILE_PHI="${LHE_DIR}/MC_Jpsi_block_${LHE_BLOCK_PHI}.lhe"
BASENAME="JJP_DPS_N${LHE_BLOCK_NORMAL}_P${LHE_BLOCK_PHI}"

# 中间文件（本地）
HEPMC_NORMAL="${WORK_DIR}/${BASENAME}_normal.hepmc"
HEPMC_PHI="${WORK_DIR}/${BASENAME}_phi.hepmc"
HEPMC_MIXED="${WORK_DIR}/${BASENAME}_mixed.hepmc"
GENSIM_FILE="${WORK_DIR}/${BASENAME}_GENSIM.root"
RAW_FILE="${WORK_DIR}/${BASENAME}_RAW.root"
AOD_FILE="${WORK_DIR}/${BASENAME}_AOD.root"
MINIAOD_FILE="${WORK_DIR}/${BASENAME}_MINIAOD.root"

# 最终输出文件（EOS）- 只保存MINIAOD
FINAL_MINIAOD="${OUTPUT_MINIAOD}/${BASENAME}_MINIAOD.root"

# ============== 检查输入文件 ==============
if [ ! -f "${LHE_FILE_NORMAL}" ]; then
    echo "ERROR: LHE file (normal) not found: ${LHE_FILE_NORMAL}"
    exit 1
fi
if [ ! -f "${LHE_FILE_PHI}" ]; then
    echo "ERROR: LHE file (phi) not found: ${LHE_FILE_PHI}"
    exit 1
fi
echo "Input LHE file (normal): ${LHE_FILE_NORMAL}"
echo "Input LHE file (phi):    ${LHE_FILE_PHI}"

# ============== 检查是否已完成 ==============
# 使用xrdfs检查EOS上是否已有输出文件
if xrdfs eosuser.cern.ch stat "${FINAL_MINIAOD}" &>/dev/null; then
    echo "Output already exists on EOS: ${FINAL_MINIAOD}"
    echo "Skipping this job."
    exit 0
fi

# ============== 设置环境 ==============
echo ""
echo "=========================================="
echo "Setting up environment..."
echo "=========================================="

# 设置库路径 (使用CMSSW版本)
export LD_LIBRARY_PATH="${PYTHIA8_BASE}/lib:${HEPMC3_BASE}/lib64:${HEPMC2_BASE}/lib:${LD_LIBRARY_PATH}"
export PYTHIA8DATA="${PYTHIA8_BASE}/share/Pythia8/xmldoc"

# ============== 检查VOMS代理 ==============
# VOMS代理用于访问远程pileup文件
echo ""
echo "Checking VOMS proxy..."
if [ -n "$X509_USER_PROXY" ] && [ -f "$X509_USER_PROXY" ]; then
    echo "Using X509_USER_PROXY: $X509_USER_PROXY"
elif [ -f "/tmp/x509up_u$(id -u)" ]; then
    export X509_USER_PROXY="/tmp/x509up_u$(id -u)"
    echo "Using default proxy: $X509_USER_PROXY"
fi

if voms-proxy-info --exists 2>/dev/null; then
    echo "VOMS proxy is valid:"
    voms-proxy-info --timeleft 2>/dev/null || true
else
    echo "WARNING: No valid VOMS proxy found!"
    echo "This may cause failures when accessing remote pileup files."
    echo "Please run: voms-proxy-init -voms cms -valid 192:00"
fi
# 设置CMSSW环境
source /cvmfs/cms.cern.ch/cmsset_default.sh
cd "${CMSSW_BASE}/src"
eval $(scramv1 runtime -sh)
cd "${WORK_DIR}"

echo "CMSSW_VERSION: ${CMSSW_VERSION}"
echo "CMSSW_BASE: ${CMSSW_BASE}"

# ============== 步骤1: Normal Shower ==============
echo ""
echo "=========================================="
echo "Step 1: Running Normal Shower"
echo "=========================================="

if [ ! -f "${PYTHIA_SHOWER_DIR}/shower_normal" ]; then
    echo "ERROR: shower_normal not found. Please compile first."
    exit 1
fi

"${PYTHIA_SHOWER_DIR}/shower_normal" "${LHE_FILE_NORMAL}" "${HEPMC_NORMAL}"

if [ ! -f "${HEPMC_NORMAL}" ]; then
    echo "ERROR: Normal shower failed to produce output"
    exit 1
fi
echo "Normal shower completed: ${HEPMC_NORMAL}"
ls -lh "${HEPMC_NORMAL}"

# ============== 步骤2: Phi-enriched Shower ==============
echo ""
echo "=========================================="
echo "Step 2: Running Phi-enriched Shower"
echo "=========================================="

if [ ! -f "${PYTHIA_SHOWER_DIR}/shower_phi" ]; then
    echo "ERROR: shower_phi not found. Please compile first."
    exit 1
fi

# 参数: input.lhe output.hepmc [nEvents] [minPhiPt] [maxRetry]
# minPhiPt=3.0 表示phi的pT必须大于3 GeV
# maxRetry=1000 每个事例最多重试1000次hadronization
"${PYTHIA_SHOWER_DIR}/shower_phi" "${LHE_FILE_PHI}" "${HEPMC_PHI}" -1 3.0 1000

if [ ! -f "${HEPMC_PHI}" ]; then
    echo "ERROR: Phi shower failed to produce output"
    exit 1
fi
echo "Phi-enriched shower completed: ${HEPMC_PHI}"
ls -lh "${HEPMC_PHI}"

# ============== 步骤3: 混合两种事例 ==============
echo ""
echo "=========================================="
echo "Step 3: Mixing SPS Events to DPS"
echo "=========================================="

if [ ! -f "${PYTHIA_SHOWER_DIR}/event_mixer_hepmc2" ]; then
    echo "ERROR: event_mixer_hepmc2 not found. Please compile first."
    exit 1
fi

"${PYTHIA_SHOWER_DIR}/event_mixer_hepmc2" "${HEPMC_NORMAL}" "${HEPMC_PHI}" "${HEPMC_MIXED}"

if [ ! -f "${HEPMC_MIXED}" ]; then
    echo "ERROR: Event mixing failed"
    exit 1
fi
echo "Event mixing completed: ${HEPMC_MIXED}"
ls -lh "${HEPMC_MIXED}"

# 清理中间HepMC文件以节省空间
rm -f "${HEPMC_NORMAL}" "${HEPMC_PHI}"

# ============== 步骤4: HepMC -> GEN-SIM ==============
# 注意: hepmc_to_GENSIM.py 同时执行 GEN 和 SIM 步骤
echo ""
echo "=========================================="
echo "Step 4: Converting HepMC to GEN-SIM"
echo "=========================================="

cmsRun "${CMSSW_CONFIG_DIR}/hepmc_to_GENSIM.py" \
    inputFiles="file:${HEPMC_MIXED}" \
    outputFile="file:${GENSIM_FILE}" \
    maxEvents=-1

if [ ! -f "${GENSIM_FILE}" ]; then
    echo "ERROR: GEN-SIM step failed"
    exit 1
fi
echo "GEN-SIM step completed: ${GENSIM_FILE}"
ls -lh "${GENSIM_FILE}"

# 清理HepMC
rm -f "${HEPMC_MIXED}"

# ============== 步骤5: GEN-SIM -> RAW ==============
echo ""
echo "=========================================="
echo "Step 5: Running DIGI-RAW (with pileup)"
echo "=========================================="

RAW_CFG="${WORK_DIR}/raw_cfg.py"
cmsDriver.py step2 \
    --mc --no_exec \
    --python_filename "${RAW_CFG}" \
    --eventcontent PREMIXRAW \
    --step DIGI,DATAMIX,L1,DIGI2RAW,HLT:2022v12 \
    --procModifiers premix_stage2,siPixelQualityRawToDigi \
    --datamix PreMix \
    --datatier GEN-SIM-RAW \
    --conditions 124X_mcRun3_2022_realistic_v12 \
    --beamspot Realistic25ns13p6TeVEarly2022Collision \
    --era Run3 \
    --geometry DB:Extended \
    -n -1 \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --nThreads 1 --nStreams 1 \
    --pileup_input "filelist:/cvmfs/cms.cern.ch/offcomp-prod/premixPUlist/PREMIX-Run3Summer22DRPremix.txt" \
    --filein "file:${GENSIM_FILE}" \
    --fileout "file:${RAW_FILE}"

cmsRun "${RAW_CFG}"

if [ ! -f "${RAW_FILE}" ]; then
    echo "ERROR: RAW step failed"
    exit 1
fi
echo "RAW step completed: ${RAW_FILE}"
ls -lh "${RAW_FILE}"

# 清理GENSIM
rm -f "${GENSIM_FILE}"

# ============== 步骤6: RAW -> AOD ==============
echo ""
echo "=========================================="
echo "Step 6: Running RECO (RAW -> AOD)"
echo "=========================================="

RECO_CFG="${WORK_DIR}/reco_cfg.py"
cmsDriver.py step3 \
    --mc --no_exec \
    --python_filename "${RECO_CFG}" \
    --eventcontent AODSIM \
    --step RAW2DIGI,L1Reco,RECO,RECOSIM \
    --procModifiers siPixelQualityRawToDigi \
    --datatier AODSIM \
    --conditions 124X_mcRun3_2022_realistic_v12 \
    --beamspot Realistic25ns13p6TeVEarly2022Collision \
    --era Run3 \
    --geometry DB:Extended \
    -n -1 \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --nThreads 1 --nStreams 1 \
    --filein "file:${RAW_FILE}" \
    --fileout "file:${AOD_FILE}"

cmsRun "${RECO_CFG}"

if [ ! -f "${AOD_FILE}" ]; then
    echo "ERROR: RECO step failed"
    exit 1
fi
echo "RECO step completed: ${AOD_FILE}"
ls -lh "${AOD_FILE}"

# 清理RAW
rm -f "${RAW_FILE}"

# ============== 步骤7: AOD -> MiniAOD ==============
echo ""
echo "=========================================="
echo "Step 7: Running MiniAOD"
echo "=========================================="

MINIAOD_CFG="${WORK_DIR}/miniaod_cfg.py"
cmsDriver.py step4 \
    --mc --no_exec \
    --python_filename "${MINIAOD_CFG}" \
    --eventcontent MINIAODSIM \
    --step PAT \
    --datatier MINIAODSIM \
    --conditions 124X_mcRun3_2022_realistic_v12 \
    --era Run3 \
    --geometry DB:Extended \
    -n -1 \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --nThreads 1 --nStreams 1 \
    --filein "file:${AOD_FILE}" \
    --fileout "file:${MINIAOD_FILE}"

cmsRun "${MINIAOD_CFG}"

if [ ! -f "${MINIAOD_FILE}" ]; then
    echo "ERROR: MiniAOD step failed"
    exit 1
fi
echo "MiniAOD step completed: ${MINIAOD_FILE}"
ls -lh "${MINIAOD_FILE}"

# 保存到EOS (使用xrdcp避免HTCondor文件传输限制)
echo "Copying MiniAOD to EOS using xrdcp..."
xrdcp -f "${MINIAOD_FILE}" "root://eosuser.cern.ch/${FINAL_MINIAOD}"
if [ $? -eq 0 ]; then
    echo "MiniAOD file saved to: ${FINAL_MINIAOD}"
else
    echo "ERROR: xrdcp failed, trying cp as fallback..."
    cp "${MINIAOD_FILE}" "${FINAL_MINIAOD}"
fi

# 清理由trap自动处理

# ============== 完成 ==============
echo ""
echo "=========================================="
echo "Job Completed Successfully!"
echo "=========================================="
echo "Job ID: ${JOB_ID}"
echo "LHE Block (Normal): ${LHE_BLOCK_NORMAL}"
echo "LHE Block (Phi):    ${LHE_BLOCK_PHI}"
echo "End time: $(date)"
echo ""
echo "Output file:"
echo "  MiniAOD: ${FINAL_MINIAOD}"
echo "=========================================="

exit 0
