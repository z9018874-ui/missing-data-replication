contributors:

* Andrew Chen

* Jack McCoy

* (Simplified for Local PC Execution)
  title: Replication Documentation for "Missing Values Handling For Machine Learning Portfolios" (Simplified Version)

## 概述 (Overview)

本代码库是对原学术论文 "Missing Values Handling For Machine Learning Portfolios" 的**轻量级本地复现版**。原始代码依赖于服务器集群、底层 Fortran 编译的高性能算法以及庞大的全市场数十年数据，无法在普通个人电脑上运行。

为了满足课堂演示与单机复现的需求，本项目在保留量价特征处理与机器学习预测核心框架的前提下，进行了以下核心简化：

* **数据来源**：移除了 WRDS 在线数据库依赖，改为直接读取本地 CSV 文件。

* **数据降维**：将样本范围截断至 **2010年-2020年**，并仅保留平均市值排名前 **500** 的股票（模拟标准普尔500指数环境）。

* **插补算法**：移除了耗时数天的多元正态期望最大化 (EM) 算法及相关的 Fortran 依赖，使用高效的**截面均值/中位数插补**作为合理替代方案。

* **模型预测**：将集群并行计算的 PCR（主成分回归）重写为单机滚动的 36 个月窗口预测。

本项目可以完成以下任务：

1. 读取本地 CRSP 收益率与 Chen-Zimmerman 因子数据。

2. 生成数据缺失率分布统计（对应论文 Section 2）。

3. 对信号执行横截面去极值与 Z-score 标准化（平替原论文 3.1 节的 Box-Cox）。

4. 快速填补特征缺失值。

5. 提取主成分并预测次月收益率，构建多空（Long-Short）投资组合。

6. 输出策略表现的统计图表（净值曲线与夏普比率变化趋势）。

## 数据说明 (Data Availability)

本简化版项目需要您在本地准备以下两个原始数据文件（请放置在设定的 `data_cm/raw/` 目录下或与脚本同级目录）：

1. **`signed_predictors_dl_wide.csv`**: 包含数百个连续型股票预测因子的宽表。来源于 [Open Source Asset Pricing website](https://www.openassetpricing.com/)。

2. **`crsp_monthly.csv`** (原始项目为 `crsp_data.csv`): 包含 `PERMNO` (股票代码)、`YYYYMM` (年月)、`MthRet` (月度收益率)、`MthCap` (月度市值) 等基础量价数据的本地文件。

## 运行环境与计算要求 (Computational Requirements)

### 软件环境

* **R 语言版本**: R (>= 4.0.0)

* **所需 R 包**: `data.table`, `dplyr`, `tidyr`, `zoo`, `ggplot2`, `pls`。

* **移除的依赖**: 原项目的 `RPostgres`（数据库连接）和 Fortran 编译器不再需要。

### 硬件要求

* **内存与算力**: 普通笔记本电脑即可（8GB RAM 及以上）。原项目需 72 小时及近百核心并行，简化版**通常在 30 分钟内即可跑完全部流程**。

* **存储空间**: 约 3GB 存储空间（原项目产生的中间文件超过 250GB）。

## 文件说明与代码结构 (Description of Programs)

项目代码按执行顺序使用数字前缀命名。请依次运行：

* **`FILEPATHS.R`**: 全局路径配置文件。定义了 `data_path`（数据存放路径）和 `out_path`（图表输出路径）。

* **`functions.R`**: 全局工具函数库。包含路径验证、读取信号、均值插补 (`imputeVec`)、去极值 (`winsorize`) 等精简版核心函数。

* **`0a_download_data_simplified.R`**: 数据加载与降维。读取本地 CSV，过滤 2010-2020 年 Top 500 股票，并构造滞后收益率特征。

* **`0b_select_signals_simplified.R`**: 信号筛选。统计特征的缺失情况，剔除无效信号，生成基准年（2015年）覆盖率高的优质信号列表（`signals_all_2015.txt`）。

* **`1_box_cox_transform_simplified.R`**: 特征工程。对信号执行横截面去极值 (Winsorize, 0.5%) 与标准化 (Scale)，生成 `bcsignals_none.csv`。

* **`2_imputations_simplified.R`**: 缺失值插补。使用快速截面中位数/均值插补，输出包含完整特征矩阵的 `bcsignals_simple.csv`。

* **`3_pcr_simplified.R`**: 核心预测模型。以 3 年数据为滚动训练窗口，动态剔除零方差特征，提取主成分（PCA）并拟合线性回归模型预测次月收益。

* **`4_portfolio_evaluation_simplified.R`**: 策略回测。基于预测收益提取十分位多空组合，计算等权（EW）和市值加权（VW）累计收益并绘制净值曲线。

* **`5a_miss_plot_simplified.R`**: 图表生成。绘制特征整体缺失率分布与 Top 30 缺失特征柱状图。

* **`5e_pcr_plots_simplified.R`**: 图表生成。循环评估保留 1 到 10 个主成分时策略的夏普比率变化，揭示机器学习中的过拟合与维数灾难。

## 复现指南 (Instructions to Replicators)

1. **环境准备**: 确保 R 环境已安装上述依赖包。

2. **配置路径**: 打开 `FILEPATHS.R`，将 `data_path` 和 `out_path` 修改为本地相对或绝对路径，并确认 `signal_list` 指向 2015 年的 txt 文件。

3. **放入数据**: 确保 `crsp_monthly.csv` 和 `signed_predictors_dl_wide.csv` 在工作目录下准备就绪。

4. **按序执行**: 在 RStudio 或终端中，按 `0a` -> `0b` -> `1` -> `2` -> `3` -> `4` -> `5a` -> `5e` 的顺序依次 source 这些脚本文件。

5. **查看结果**: 执行完毕后，可在设定的 `out_path/plots/` 文件夹下查看生成的策略表现与数据分析图表。

## 核心输出图表 (List of Outputs)

本简化代码成功复现并适配了原论文的以下核心图表逻辑：

| 图表名称 | 生成脚本 | 说明 | 
| ----- | ----- | ----- | 
| `missing_rates_distribution.png` | `5a_miss_plot_simplified.R` | 对应论文图1：展示所有信号特征的整体缺失率分布直方图。 | 
| `missing_rates_top30.png` | `5a_miss_plot_simplified.R` | 展示缺失度最高的 30 个信号，凸显数据插补环节在实证中的必要性。 | 
| `sharpe_vs_pcs.png` | `5e_pcr_plots_simplified.R` | 对应论文图2：展示保留不同主成分数量（1-10 PCs）与组合年化夏普比率的关系，揭示维数灾难。 | 
| `portfolio_performance.png` | `4_portfolio_evaluation_simplified.R` | 展示等权 (EW) 与市值加权 (VW) 多空策略组合的累计净值曲线，并能直观反映底层数据断层对策略的破坏性。 | 
