# 2_imputations_simplified.R (修改版：替代繁重的EM算法，使用快速截面插补)
rm(list = ls())
library(data.table)
library(dplyr)
library(zoo)
source("functions.R")

getFilePaths()
impute_vec <- unpackSignalList(FILEPATHS$signal_list)

cat("读取转换后的特征数据...\n")
signals <- fread(paste0(FILEPATHS$data_path, "bcsignals/bcsignals_none.csv"))
if(class(signals$yyyymm) != "yearmon") {
  signals[, yyyymm := as.yearmon(yyyymm)]
}

# 按照原流程，插补前需要加入 CRSP 的市值(me)等特征[cite: 6]
crsp_data <- fread(paste0(FILEPATHS$data_path, "raw/crsp_data.csv"))[, .(permno, yyyymm, hsiccd, me)]
if(class(crsp_data$yyyymm) != "yearmon") crsp_data[, yyyymm := as.yearmon(yyyymm)]

# 提取 SIC 前三位作为行业代码[cite: 6]
crsp_data <- crsp_data %>%
  mutate(sic3 = substr(ifelse(hsiccd < 1000, paste0("0", hsiccd), as.character(hsiccd)), 1, 3))

signals <- merge(signals, crsp_data, by = c("permno", "yyyymm"))

cat("正在执行快速横截面缺失值插补(截面均值)...\n")
cols_to_impute <- intersect(colnames(signals), impute_vec)

# 按月份进行均值插补（调用 functions.R 中的 imputeVec）
signals_imputed <- signals %>%
  group_by(yyyymm) %>%
  mutate(across(all_of(cols_to_impute), ~imputeVec(., na.rm = TRUE))) %>%
  ungroup() %>%
  as.data.table()

# 对于极端情况（如某个月该特征全为空导致均值依然是NA），整体填0（因为标准化后的整体均值为0）
for (j in cols_to_impute) {
  set(signals_imputed, which(is.na(signals_imputed[[j]])), j, 0)
}

# 保存插补后的数据。命名为 _simple 代表简单插补
fwrite(signals_imputed, paste0(FILEPATHS$data_path, "bcsignals/bcsignals_simple.csv"))
cat("缺失值插补完成！结果已输出至 bcsignals/bcsignals_simple.csv\n")