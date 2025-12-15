#!/bin/bash
# condor_job.sh - HTCondor worker节点执行脚本
# 完整工作流程：LHE -> 两种Shower -> 混合 -> CMSSW处理 -> MiniAOD
#
# 用法: ./condor_job.sh <job_id> <lhe_block_num>
# 例如: ./condor_job.sh 1 00010

set -e

# ============== 参数解析 ==============
JOB_ID="${1}"
LHE_BLOCK="${2}"

if [ -z "$JOB_ID" ] || [ -z "$LHE_BLOCK" ]; then
    echo "Usage: $0 <job_id> <lhe_block_num>"
    echo "Example: $0 1 00010"
    exit 1
fi

echo "=========================================="
echo "HTCondor Job Starting"
echo "Job ID: ${JOB_ID}"
echo "LHE Block: ${LHE_BLOCK}"
echo "Start time: $(date)"
echo "Hostname: $(hostname)"
echo "=========================================="

# ============== 路径配置 ==============
# 源目录（只读）
LHE_DIR="/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks"
WORK_BASE="/afs/cern.ch/user/x/xcheng/condor/CMSSW_12_4_14_patch3/src/JJP_DPS_1_GEN_Mix"
CMSSW_BASE="/afs/cern.ch/user/x/xcheng/condor/CMSSW_12_4_14_patch3"

# 输出目录（EOS）
OUTPUT_BASE="/eos/user/x/xcheng/learn_MC/JJP_DPS_MC_output"
OUTPUT_HEPMC="${OUTPUT_BASE}/hepmc"
OUTPUT_GENSIM="${OUTPUT_BASE}/GENSIM"
OUTPUT_RAW="${OUTPUT_BASE}/RAW"
OUTPUT_AOD="${OUTPUT_BASE}/AOD"
OUTPUT_MINIAOD="${OUTPUT_BASE}/MINIAOD"

# 工具路径
PYTHIA_SHOWER_DIR="${WORK_BASE}/pythia_shower"
CMSSW_CONFIG_DIR="${WORK_BASE}/cmssw_configs"

# HepMC库路径 (使用CMSSW自带的版本)
PYTHIA8_BASE="/cvmfs/cms.cern.ch/el8_amd64_gcc10/external/pythia8/306-494ded5c626b685d055d5b022e918c0c"
HEPMC3_BASE="/cvmfs/cms.cern.ch/el8_amd64_gcc10/external/hepmc3/3.2.5-c3cd50aeecf06b194814f1a75bf7872e"
HEPMC2_BASE="/cvmfs/cms.cern.ch/el8_amd64_gcc10/external/hepmc/2.06.10-46867a6dcc6e5712b7953fe57085fcbd"

# ============== 本地工作目录 ==============
# 使用condor的scratch目录
if [ -n "$_CONDOR_SCRATCH_DIR" ]; then
    WORK_DIR="${_CONDOR_SCRATCH_DIR}"
else
    WORK_DIR="/tmp/condor_job_${USER}_${JOB_ID}_${LHE_BLOCK}"
    mkdir -p "${WORK_DIR}"
fi

cd "${WORK_DIR}"
echo "Working directory: ${WORK_DIR}"

# ============== 创建输出目录 ==============
mkdir -p "${OUTPUT_HEPMC}" "${OUTPUT_GENSIM}" "${OUTPUT_RAW}" "${OUTPUT_AOD}" "${OUTPUT_MINIAOD}"

# ============== 定义文件名 ==============
LHE_FILE="${LHE_DIR}/MC_Jpsi_block_${LHE_BLOCK}.lhe"
BASENAME="JJP_DPS_block_${LHE_BLOCK}"

# 中间文件（本地）
HEPMC_NORMAL="${WORK_DIR}/${BASENAME}_normal.hepmc"
HEPMC_PHI="${WORK_DIR}/${BASENAME}_phi.hepmc"
HEPMC_MIXED="${WORK_DIR}/${BASENAME}_mixed.hepmc"
GENSIM_FILE="${WORK_DIR}/${BASENAME}_GENSIM.root"
RAW_FILE="${WORK_DIR}/${BASENAME}_RAW.root"
AOD_FILE="${WORK_DIR}/${BASENAME}_AOD.root"
MINIAOD_FILE="${WORK_DIR}/${BASENAME}_MINIAOD.root"

# 最终输出文件（EOS）
FINAL_HEPMC="${OUTPUT_HEPMC}/${BASENAME}_mixed.hepmc"
FINAL_GENSIM="${OUTPUT_GENSIM}/${BASENAME}_GENSIM.root"
FINAL_RAW="${OUTPUT_RAW}/${BASENAME}_RAW.root"
FINAL_AOD="${OUTPUT_AOD}/${BASENAME}_AOD.root"
FINAL_MINIAOD="${OUTPUT_MINIAOD}/${BASENAME}_MINIAOD.root"

# ============== 检查输入文件 ==============
if [ ! -f "${LHE_FILE}" ]; then
    echo "ERROR: LHE file not found: ${LHE_FILE}"
    exit 1
fi
echo "Input LHE file: ${LHE_FILE}"

# ============== 检查是否已完成 ==============
if [ -f "${FINAL_MINIAOD}" ]; then
    echo "Output already exists: ${FINAL_MINIAOD}"
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

"${PYTHIA_SHOWER_DIR}/shower_normal" "${LHE_FILE}" "${HEPMC_NORMAL}"

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
# minPhiPt=0 表示不做pT cut (只要有phi即可)
# maxRetry=100 每个事例最多重试100次hadronization
"${PYTHIA_SHOWER_DIR}/shower_phi" "${LHE_FILE}" "${HEPMC_PHI}" -1 0.0 100

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

# 保存混合后的HepMC文件到EOS
cp "${HEPMC_MIXED}" "${FINAL_HEPMC}"
echo "HepMC file saved to: ${FINAL_HEPMC}"

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

# 保存到EOS
cp "${GENSIM_FILE}" "${FINAL_GENSIM}"
echo "GENSIM file saved to: ${FINAL_GENSIM}"

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

# 保存到EOS
cp "${RAW_FILE}" "${FINAL_RAW}"
echo "RAW file saved to: ${FINAL_RAW}"

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

# 保存到EOS
cp "${AOD_FILE}" "${FINAL_AOD}"
echo "AOD file saved to: ${FINAL_AOD}"

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

# 保存到EOS
cp "${MINIAOD_FILE}" "${FINAL_MINIAOD}"
echo "MiniAOD file saved to: ${FINAL_MINIAOD}"

# ============== 清理 ==============
echo ""
echo "=========================================="
echo "Cleaning up..."
echo "=========================================="

rm -f "${AOD_FILE}" "${MINIAOD_FILE}"
rm -f "${WORK_DIR}"/*.py
rm -f "${WORK_DIR}"/*.pyc

# ============== 完成 ==============
echo ""
echo "=========================================="
echo "Job Completed Successfully!"
echo "=========================================="
echo "Job ID: ${JOB_ID}"
echo "LHE Block: ${LHE_BLOCK}"
echo "End time: $(date)"
echo ""
echo "Output files:"
echo "  HepMC:   ${FINAL_HEPMC}"
echo "  GENSIM:  ${FINAL_GENSIM}"
echo "  RAW:     ${FINAL_RAW}"
echo "  AOD:     ${FINAL_AOD}"
echo "  MiniAOD: ${FINAL_MINIAOD}"
echo "=========================================="

exit 0
