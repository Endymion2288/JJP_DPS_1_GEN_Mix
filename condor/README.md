# JJP DPS MC Production - HTCondor批量生产指南

## 概述

本目录包含在HTCondor集群上批量生产 J/ψ + J/ψ + φ DPS 蒙特卡洛事例的完整脚本。

**关键特点：**
- Normal和Phi shower使用**不同的LHE文件**，避免事例相关性
- Phi shower要求 φ介子 **pT > 3 GeV**，最多重试1000次hadronization
- 只保存最终的 **MiniAOD** 文件到EOS，中间文件不保存

**工作流程：**
```
LHE (Normal)                    LHE (Phi)
    ↓                              ↓
shower_normal                  shower_phi (pT>3)
    ↓                              ↓
HepMC3 (所有事例)              HepMC3 (仅含高pT φ事例)
    └──────────┬───────────────────┘
               ↓
       event_mixer_hepmc2  ← 以phi事例数为准进行1:1混合
               ↓
         HepMC2 文件 (DPS事例)
               ↓
      hepmc_to_GENSIM.py  ← CMSSW: GEN + SIM
               ↓
           GEN-SIM ROOT
               ↓
         DIGI-RAW-HLT  ← 包含pileup
               ↓
             RECO
               ↓
           MiniAOD  ← 最终输出 (保存到EOS)
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
- 生成作业列表（LHE文件配对）
- 创建输出目录

### 2. 本地测试

建议先运行本地测试确保流程正确：

```bash
# 使用两个不同的LHE文件测试，处理20个事例
./test_local.sh 00010 03270 20
```

参数说明：
- 第1个参数：Normal shower使用的LHE block编号
- 第2个参数：Phi shower使用的LHE block编号
- 第3个参数：处理的事例数（可选，默认全部）

### 3. 提交作业

```bash
# 提交所有326个作业
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

# 分析效率统计
./analyze_efficiency.sh
```

### 5. 重新提交失败作业

```bash
./submit_jobs.sh resubmit
```

## 文件说明

| 文件 | 描述 |
|------|------|
| `condor_job.sh` | 主执行脚本，接受3个参数: `<job_id> <lhe_block_normal> <lhe_block_phi>` |
| `condor_submit.sub` | HTCondor提交配置 |
| `generate_job_list.sh` | 生成LHE块配对列表 |
| `job_list.txt` | LHE块配对列表（格式：`normal_block phi_block`） |
| `setup.sh` | 初始化脚本 |
| `submit_jobs.sh` | 作业提交脚本 |
| `check_status.sh` | 状态检查脚本 |
| `test_local.sh` | 本地测试脚本 |
| `analyze_efficiency.sh` | 效率统计分析脚本 |

## 输入输出

**输入：**
- LHE文件: `/eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks/MC_Jpsi_block_XXXXX.lhe`
- 共652个文件 (block 00010 ~ 06520)
- 配对方式：前半部分(00010-03260)用于Normal，后半部分(03270-06520)用于Phi
- 共326个作业

**输出：**
- `/eos/user/x/xcheng/learn_MC/JJP_DPS_MC_output/MINIAOD/`
  - 文件命名: `JJP_DPS_N{normal_block}_P{phi_block}_MINIAOD.root`
  - 例如: `JJP_DPS_N00010_P03270_MINIAOD.root`

**注意：** 中间文件（HepMC、GENSIM、RAW、AOD）不保存，只保留最终MiniAOD。

## 效率统计

运行 `./analyze_efficiency.sh` 可以获取：
- 各步骤成功/失败统计
- Phi shower效率（pT>3筛选通过率，约85%）
- DPS混合事例数
- 预估总产量

## 资源需求

每个作业请求：
- CPU: 4核
- 内存: 8GB
- 磁盘: 20GB
- 预计运行时间: 2-6小时

## 注意事项

1. **首次运行前**必须执行 `source setup.sh` 编译程序

2. **Normal和Phi使用不同LHE文件**，确保DPS事例的两个SPS分量相互独立

3. Phi shower的筛选条件：φ介子 pT > 3 GeV，最多重试1000次hadronization

4. 混合时**以phi事例数为准**（因为phi筛选后事例较少）

5. HTCondor使用共享文件系统，不传输文件

6. 作业自动跳过已存在的输出文件

7. 如遇问题，检查 `logs/` 目录下的日志文件

## 故障排查

**作业失败：**
```bash
# 查看失败日志
./check_status.sh failed

# 查看特定作业日志
cat logs/job_CLUSTER_PROCESS.stderr

# 效率分析（包含失败作业列表）
./analyze_efficiency.sh
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
- Phi筛选: pT > 3 GeV, maxRetry = 1000
