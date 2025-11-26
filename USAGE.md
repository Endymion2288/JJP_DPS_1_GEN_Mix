# JJP DPS 1 GEN Mix HTCondor Production

本目录包含用于批量提交 Jpsi DPS 蒙特卡洛模拟的 HTCondor 脚本。

## 目录结构

```
JJP_DPS_1_GEN_Mix/
├── README.md           # 项目说明
├── USAGE.md           # 使用说明 (本文档)
├── condor/
│   └── submit.sub      # HTCondor 提交描述文件
├── config/
│   ├── lhe_jobs.txt         # 完整 LHE 任务清单 (652 jobs)
│   ├── lhe_jobs_sample.txt  # 示例任务清单 (10 jobs)
│   └── lhe_jobs_test.txt    # 测试任务清单 (2 jobs)
└── scripts/
    ├── job_wrapper.sh      # Worker 节点执行脚本
    ├── submit_jobs.sh      # 一键提交脚本
    ├── prepare_jobs.py     # 任务清单生成工具
    └── aggregate_logs.py   # 日志汇总工具
```

## 重要配置说明

### CMSSW 版本兼容性
- CMSSW_12_4_14_patch3 使用 **el8_amd64_gcc10** 架构
- Condor 提交文件已配置为使用 el8 Singularity 容器
- 无需在 el9 节点上手动处理容器

### 路径配置
- **CMSSW 目录**: `/eos/user/x/xcheng/learn_MC/project_gg_JJg_JJP/pythia_run/CMSSW_12_4_14_patch3`
- **LHE 文件**: `root://eosuser.cern.ch//eos/user/x/xcheng/learn_MC/SPS-Jpsi_blocks/MC_Jpsi_block_XXXXX.lhe`
- **输出目录**: `root://eosuser.cern.ch//eos/user/x/xcheng/learn_MC/JJP_DPS_MINIAOD`

## 快速开始

### 1. 提交测试作业 (2 个 jobs)

```bash
cd /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix_Condor

# Dry-run 先检查配置
bash /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix/scripts/submit_jobs.sh \
    --manifest /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix/config/lhe_jobs_test.txt \
    --dry-run

# 实际提交
bash /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix/scripts/submit_jobs.sh \
    --manifest /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix/config/lhe_jobs_test.txt
```

### 2. 提交完整生产 (652 个 jobs)

```bash
bash /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix/scripts/submit_jobs.sh
```

### 3. 查看提交选项

```bash
bash /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix/scripts/submit_jobs.sh --help
```

## 配置选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `--manifest` | `config/lhe_jobs.txt` | LHE 任务清单文件 |
| `--cmssw-base` | `/eos/.../CMSSW_12_4_14_patch3` | CMSSW 安装目录 |
| `--eos-output` | `root://eosuser.cern.ch//eos/user/x/xcheng/learn_MC/JJP_DPS_MINIAOD` | MINIAOD 输出目录 |
| `--log-output` | `/afs/.../JJP_DPS_1_GEN_Mix_Condor/logs` | 作业日志目录 |
| `--condor-log` | `/afs/.../JJP_DPS_1_GEN_Mix_Condor/condor_logs` | Condor 系统日志 |
| `--copy-intermediate` | 否 | 是否保存中间 ROOT 文件 |
| `--debug` | 否 | 启用详细日志 |

## 监控与日志

### 查看作业状态

```bash
condor_q
condor_q -analyze <JOB_ID>
```

### 查看日志

```bash
# Condor 标准输出/错误
cat /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix_Condor/condor_logs/block_00010.out
cat /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix_Condor/condor_logs/block_00010.err

# 详细作业日志
cat /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix_Condor/logs/job_block_00010_summary.log
```

### 日志文件说明

每个作业产生两个日志文件：
- `job_<label>_full.log`: 完整执行日志
- `job_<label>_summary.log`: 摘要日志，包含每步状态、运行时间和效率

## 处理流程

每个 Condor 作业执行以下步骤：

1. **GEN_STANDARD**: 从 LHE 文件进行标准 Pythia8 shower
2. **GEN_PHI**: 从同一 LHE 文件进行 phi 增强 shower
3. **DPS_MIX**: 将 standard 和 phi 样本混合为 DPS 事例
4. **SIM**: 探测器模拟
5. **DIGI**: 数字化和 HLT
6. **RECO**: 重建
7. **MINIAOD**: 生成最终 MINIAOD 文件

## 输出文件

- **MINIAOD 文件**: `<EOS_OUTPUT_BASE>/<block_label>/MINIAOD_<block_label>.root`
- **日志摘要**: `<EOS_OUTPUT_BASE>/<block_label>/<block_label>_summary.log`

## 故障排除

### 常见问题

1. **SCRAM_ARCH 不匹配**: 
   - 已通过 Singularity 容器解决
   - 作业会自动在 el8 容器中运行

2. **临时目录创建失败**:
   - 脚本会自动回退到工作目录
   - 检查 TMPDIR 环境变量

3. **xrdcp 失败**:
   - 检查 EOS 服务状态
   - 确保有有效的代理证书 (`voms-proxy-init`)

### 重新提交失败作业

```bash
# 找出失败的作业
grep -l "status=[^0]" /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix_Condor/logs/*_summary.log

# 创建失败作业的新 manifest
# 然后重新提交
```

## 资源需求

单个作业预估：
- CPU: 8 核
- 内存: 16 GB
- 磁盘: 30 GB
- 时间: ~6-12 小时 (取决于事例数)

## 联系

如有问题，请联系 xcheng@cern.ch
