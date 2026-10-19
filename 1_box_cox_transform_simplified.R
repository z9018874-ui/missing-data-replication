# 1a_box_cox_transform.R (修改版：适配笔记本的快速特征转换)
rm(list = ls())
library(data.table)
library(dplyr)
library(zoo)
source("functions.R")

getFilePaths()

cat("读取 0b 筛选出的信号列表...\n")
impute_vec <- unpackSignalList(FILEPATHS$signal_list)

cat("读取数据...\n")
signals <- fread(paste0(FILEPATHS$data_path, "raw/signed_predictors_dl_wide_filtered.csv"))
setnames(signals, colnames(signals), tolower(colnames(signals)))
if(class(signals$yyyymm) != "yearmon") {
  signals[, yyyymm := as.yearmon(yyyymm)]
}

crsp_data <- fread(paste0(FILEPATHS$data_path, "raw/crsp_data.csv"))
if(class(crsp_data$yyyymm) != "yearmon") {
  crsp_data[, yyyymm := as.yearmon(yyyymm)]
}

# 将外部信号与 CRSP 基础数据合并[cite: 6]
signals <- merge(signals, crsp_data, by = c("permno", "yyyymm"))

# 只保留我们在 0b 中选出的高质量信号列
cols_to_keep <- intersect(colnames(signals), c("permno", "yyyymm", impute_vec))
signals <- signals[, ..cols_to_keep]

cat("正在执行特征去极值(Winsorize)与标准化(Scaling)...\n")
# 简化版：对每个信号在每个月进行截面去极值和Z-score标准化
signals_transformed <- signals %>%
  group_by(yyyymm) %>%
  mutate(across(-permno, ~ {
    # 确保该月至少有2个非缺失值才进行计算
    if(sum(!is.na(.)) > 2) {
      x <- winsorize(., tail = 0.005) # 去掉上下 0.5% 的极值
      as.numeric(scale(x))            # 标准化 (均值为0，方差为1)
    } else {
      .
    }
  })) %>%
  ungroup() %>%
  as.data.table()

# 创建保存转换后信号的文件夹[cite: 6]
dir.create(paste0(FILEPATHS$data_path, "bcsignals/"), showWarnings = FALSE, recursive = TRUE)
fwrite(signals_transformed, paste0(FILEPATHS$data_path, "bcsignals/bcsignals_none.csv"))
cat("特征转换完成！数据已输出至 bcsignals/bcsignals_none.csv\n")