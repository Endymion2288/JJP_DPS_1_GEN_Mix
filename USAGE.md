# JJP DPS 1 GEN Mix HTCondor Production

本目录包含用于批量提交 Jpsi DPS 蒙特卡洛模拟的 HTCondor 脚本。

## 目录结构

```
JJP_DPS_1_GEN_Mix_Condor/
├── README.md           # 本文档
├── condor/
│   └── submit.sub      # HTCondor 提交描述文件
├── config/
│   ├── lhe_jobs.txt         # 完整 LHE 任务清单 (652 jobs)
│   └── lhe_jobs_sample.txt  # 示例任务清单 (10 jobs)
└── scripts/
    ├── job_wrapper.sh      # Worker 节点执行脚本
    ├── submit_jobs.sh      # 一键提交脚本
    ├── prepare_jobs.py     # 任务清单生成工具
    └── aggregate_logs.py   # 日志汇总工具
```

## 快速开始

### 1. 提交完整生产 (652 个 LHE blocks)

```bash
cd /afs/cern.ch/user/x/xcheng/cernbox/learn_MC/project_gg_JJg_JJP/pythia_run/CMSSW_12_4_14_patch3/src/JJP_DPS_1_GEN_Mix_Condor

./scripts/submit_jobs.sh
```

### 2. 提交测试作业 (10 个 LHE blocks)

```bash
./scripts/submit_jobs.sh --manifest config/lhe_jobs_sample.txt
```

### 3. 查看提交选项

```bash
./scripts/submit_jobs.sh --help
```

### 4. Dry-run 模式 (不实际提交)

```bash
./scripts/submit_jobs.sh --dry-run
```

## 配置选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `--manifest` | `config/lhe_jobs.txt` | LHE 任务清单文件 |
| `--cmssw-base` | `/afs/.../CMSSW_12_4_14_patch3` | CMSSW 安装目录 |
| `--eos-output` | `root://eosuser.cern.ch//eos/user/x/xcheng/learn_MC/JJP_DPS_MINIAOD` | MINIAOD 输出目录 |
| `--log-output` | `/afs/.../condor/JJP_DPS_1_GEN_Mix_Condor/logs` | 作业日志目录 |
| `--condor-log` | `/afs/.../condor/JJP_DPS_1_GEN_Mix_Condor/condor_logs` | Condor 系统日志 |
| `--copy-intermediate` | 否 | 是否保存中间 ROOT 文件 |
| `--debug` | 否 | 启用详细日志 |

## 生成自定义任务清单

### 从数值范围生成

```bash
# 生成 block 00010 到 01000，步长 10
python3 scripts/prepare_jobs.py from-range 10 1000 --step 10 --output config/my_jobs.txt
```

### 从文件列表生成

```bash
# 准备一个包含 LHE 文件路径的列表
python3 scripts/prepare_jobs.py from-list my_lhe_list.txt --output config/my_jobs.txt
```

## 监控与日志

### 查看作业状态

```bash
condor_q
condor_q -analyze <JOB_ID>
```

### 汇总作业日志

```bash
python3 scripts/aggregate_logs.py /afs/cern.ch/user/x/xcheng/condor/JJP_DPS_1_GEN_Mix_Condor/logs
```

### 日志文件说明

每个作业产生两个日志文件：
- `job_<label>_full.log`: 完整执行日志
- `job_<label>_summary.log`: 摘要日志，包含每步状态和效率

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

### 作业失败

1. 查看 Condor 日志: `condor_logs/<job_label>.err`
2. 查看作业摘要: `logs/job_<job_label>_summary.log`
3. 重新提交失败作业:
   ```bash
   # 筛选失败的作业
   grep -l "status=[^0]" logs/*_summary.log | sed 's/.*job_\(.*\)_summary.*/\1/' > failed_jobs.txt
   ```

### 常见问题

- **xrdcp 超时**: 检查 EOS 服务状态或增加重试次数
- **内存不足**: 调整 `request_memory` 参数
- **磁盘空间不足**: 调整 `request_disk` 参数

## 资源需求

单个作业预估：
- CPU: 8 核
- 内存: 16 GB
- 磁盘: 30 GB
- 时间: ~6-12 小时 (取决于事例数)

## 联系

如有问题，请联系 xcheng@cern.ch
