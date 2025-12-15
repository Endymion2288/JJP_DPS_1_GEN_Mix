# JJP DPS MC Production - HTCondor批量生产指南

## 概述

本目录包含在HTCondor集群上批量生产 J/ψ + J/ψ + φ DPS 蒙特卡洛事例的完整脚本。

**工作流程：**
```
LHE (gg → J/ψ + g)
    ↓
┌─────────────────┬─────────────────┐
│  shower_normal  │   shower_phi    │  ← 两种并行Shower
│  (普通hadron化)  │  (富集φ介子)     │
└────────┬────────┴────────┬────────┘
         │                 │
         └────────┬────────┘
                  ↓
          event_mixer_hepmc2  ← 1:1混合产生DPS事例
                  ↓
            HepMC2 文件
                  ↓
       hepmc_to_GENSIM.py  ← CMSSW: GEN + SIM
                  ↓
            GEN-SIM ROOT
                  ↓
            DIGI-RAW-HLT  ← 包含pileup
                  ↓
               RECO
                  ↓
             MiniAOD
```

## 快速开始

### 1. 初始化设置

```bash
cd /afs/cern.ch/user/x/xcheng/condor/CMSSW_12_4_14_patch3/src/JJP_DPS_1_GEN_Mix/condor
source setup.sh
```

这将：
- 设置CMSSW环境
- 编译Pythia8程序
- 生成作业列表
- 创建输出目录

### 2. 本地测试

建议先运行本地测试确保流程正确：

```bash
./test_local.sh 00010 5
```

这将处理block 00010的前5个事例，生成到 `test_output/` 目录。

### 3. 提交作业

```bash
# 提交所有652个作业
./submit_jobs.sh

# 或只提交前10个作业进行测试
./submit_jobs.sh 1 10
```

### 4. 检查状态

```bash
# 查看作业状态
condor_q

# 综合状态检查
./check_status.sh all

# 只看输出文件
./check_status.sh output
```

### 5. 重新提交失败作业

```bash
./submit_jobs.sh resubmit
```

## 文件说明

| 文件 | 描述 |
|------|------|
| `condor_job.sh` | 主执行脚本，在worker节点运行 |
| `condor_submit.sub` | HTCondor提交配置 |
| `generate_job_list.sh` | 生成LHE块编号列表 |
| `job_list.txt` | LHE块编号列表（自动生成） |
| `setup.sh` | 初始化脚本 |
| `submit_jobs.sh` | 作业提交脚本 |
| `check_status.sh` | 状态检查脚本 |
| `test_local.sh` | 本地测试脚本 |

## 输入输出

**输入：**
- LHE文件: `/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks/MC_Jpsi_block_XXXXX.lhe`
- 共652个文件 (block 00010 ~ 06520)

**输出：**
- `/eos/user/x/xcheng/learn_MC/JJP_DPS_MC_output/`
  - `hepmc/` - 混合后的HepMC2文件
  - `GENSIM/` - GEN-SIM ROOT文件
  - `RAW/` - RAW ROOT文件
  - `AOD/` - AOD ROOT文件
  - `MINIAOD/` - 最终MiniAOD文件

## 资源需求

每个作业请求：
- CPU: 4核
- 内存: 8GB
- 磁盘: 20GB
- 预计运行时间: 2-6小时

## 注意事项

1. **首次运行前**必须执行 `source setup.sh` 编译程序

2. HTCondor使用共享文件系统，不传输文件

3. 作业自动跳过已存在的输出文件

4. 如遇问题，检查 `logs/` 目录下的日志文件

5. φ介子filter使用多次hadronization重试机制(最多100次)

## 故障排查

**作业失败：**
```bash
# 查看失败日志
./check_status.sh failed

# 查看特定作业日志
cat logs/job_CLUSTER_PROCESS.stderr
```

**重新提交失败作业：**
```bash
./check_status.sh resubmit  # 生成resubmit_list.txt
./submit_jobs.sh resubmit    # 重新提交
```

## 技术细节

- CMSSW版本: `CMSSW_12_4_14_patch3`
- Global Tag: `124X_mcRun3_2022_realistic_v12`
- 对撞能量: 13.6 TeV (Run3 2022)
- Pythia8调优: CP5 tune
- Pileup: Run3Summer22DRPremix premix文件
