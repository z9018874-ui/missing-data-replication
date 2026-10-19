# 0b_select_signals.R (修改版：适配 2010-2020 降维数据)
# 功能：统计各信号的缺失情况，剔除缺失严重的信号，并生成要在后续插补中使用的“优质信号列表”

rm(list = ls())
library(data.table)
library(zoo)
library(tidyverse)
library(xtable) 
source("functions.R")

# ============================================================================== #
# 1. 硬编码设置 (匹配降维后的时间跨度)
# ============================================================================== #
date_start <- as.yearmon("Jan 2010")
date_end <- as.yearmon("Dec 2020")
base_year <- 2015 # 使用2015年作为基准年筛选观测值最多的信号

getFilePaths(signal_list_exists = FALSE) 

# ============================================================================== #
# 2. 读取数据与信号字典
# ============================================================================== #
cat("正在读取合并后的信号数据...\n")
signals <- fread(paste0(FILEPATHS$data_path, "raw/signed_predictors_dl_wide_filtered.csv")) 
setnames(signals, colnames(signals), tolower(colnames(signals)))
if(class(signals$yyyymm) != "yearmon") {
  signals[, yyyymm := as.yearmon(yyyymm)]
}

crsp_data <- fread(paste0(FILEPATHS$data_path, "raw/crsp_data.csv"))[, .SD, .SDcols = !c("ret", "me")]
if(class(crsp_data$yyyymm) != "yearmon") {
  crsp_data[, yyyymm := as.yearmon(yyyymm)]
}
signals <- merge(signals, crsp_data, by = c("permno", "yyyymm"))

# 读取信号说明文档
signaldoc <- fread(paste0(FILEPATHS$data_path, 'raw/SignalDoc.csv')) %>%
  mutate(signalname = Acronym) %>%
  select(signalname, Authors, Year, starts_with('Cat.'), starts_with('Sample'), LongDescription) %>%
  mutate(signalname = tolower(signalname)) %>%
  filter(Cat.Signal == 'Predictor') %>%
  mutate(Cat.Data = if_else(signalname == 'earningssurprise', 'Accounting', Cat.Data))

# 创建观测值指示矩阵 (1表示有数据，0表示缺失)
obs <- signals %>%
  mutate_at(vars(-c('yyyymm')), function (x) as.numeric(!is.na(x))) %>%
  filter(streversal == 1)

# ============================================================================== #
# 3. 筛选信号 (剔除离散信号和有大段断层的信号)
# ============================================================================== #
cat("正在剔除缺失严重的信号...\n")
list_cts <- signaldoc %>% filter(Cat.Form == 'continuous') %>% pull(signalname)
obs <- obs %>% select(yyyymm, permno, any_of(list_cts))

# 找出在样本期内出现“整个月所有股票都缺失”的信号并剔除
obs_by_date <- obs[, by = yyyymm, lapply(.SD, sum), .SDcols = !c('permno','yyyymm')] %>%
  pivot_longer(cols = -c('yyyymm'), names_to = 'signalname', values_to = 'obs') %>%
  group_by(signalname)

gaps_all <- obs_by_date %>%
  filter(yyyymm >= date_start, yyyymm <= date_end, obs < 2) %>%
  arrange(signalname, yyyymm)

list_gap <- gaps_all %>% distinct(signalname, .keep_all = TRUE) %>% pull(signalname)
obs <- obs %>% select(-any_of(list_gap))
gc()

# ============================================================================== #
# 4. 根据基准年 (2015年) 的观测值覆盖率进行排序
# ============================================================================== #
cat("正在按 2015 年覆盖率对信号进行排序...\n")
mostobs2015 <- obs[floor(yyyymm) == base_year] %>%
  group_by(yyyymm) %>%
  summarize_all(sum) %>%
  pivot_longer(cols = -c(yyyymm,permno), names_to = 'signalname', values_to = 'nobs') %>%
  mutate(pct_obs = nobs/permno*100) %>%
  group_by(signalname) %>%
  summarize(mean_pct_obs = mean(pct_obs)) %>%
  arrange(-mean_pct_obs) %>%
  mutate(rank = row_number()) %>%
  setDT()

obs <- obs %>% select(permno, yyyymm, all_of(mostobs2015$signalname))

# ============================================================================== #
# 5. 输出最终信号列表
# ============================================================================== #
signaldoc2 <- signaldoc %>%
  inner_join(mostobs2015 %>% transmute(signalname, pct_obs_2015 = mean_pct_obs, rank2015 = rank), by="signalname") %>%
  arrange(rank2015)

# 写入 txt 文件，供下游插补脚本读取
writeLines(signaldoc2 %>% filter(rank2015 <= 125) %>% pull(signalname), paste0(FILEPATHS$data_path, 'signals_best125_2015.txt'))
writeLines(signaldoc2 %>% filter(rank2015 <= 150) %>% pull(signalname), paste0(FILEPATHS$data_path, 'signals_best150_2015.txt'))
writeLines(signaldoc2 %>% pull(signalname), paste0(FILEPATHS$data_path, 'signals_all_2015.txt'))
cat("信号列表已输出至 data 目录。\n")

# ============================================================================== #
# 6. 生成 CSV 汇总表格 (修复版：自动匹配存在的日期并兼容新版 dplyr)
# ============================================================================== #
dir.create(paste0(FILEPATHS$out_path, "tables/"), showWarnings = FALSE, recursive = TRUE)

cat("正在生成数据覆盖率统计表格...\n")

# 自动从您的数据中选取3个真实存在的日期（开头、中间、结尾），避免硬编码导致0行报错
available_dates <- sort(unique(obs$yyyymm))
# 如果日期少于3个，就全取；如果足够，就取前、中、后三个时间点
if(length(available_dates) >= 3) {
  datelist <- available_dates[c(1, floor(length(available_dates)/2), length(available_dates))]
} else {
  datelist <- available_dates
}

small <- obs %>% filter(yyyymm %in% datelist)
ptile <- c(5, 25, 50, 75, 95)

# 计算每个信号在这些月份的可用数量
nobs_by_signal <- small %>%
  group_by(yyyymm) %>%
  summarise(across(everything(), sum, na.rm = TRUE)) %>% 
  pivot_longer(cols = -c(yyyymm, permno), names_to = 'signalname', values_to = 'nobs') %>%
  mutate(pct_obs = nobs/permno*100)

# 使用 reframe 替代 summarize，完美兼容新版 dplyr 包
pct_obs_one_signal_ptile <- nobs_by_signal %>%
  group_by(yyyymm) %>%
  reframe(ptile = ptile, pct_obs = quantile(pct_obs, ptile/100, na.rm=TRUE)) %>%
  pivot_wider(names_from = ptile, values_from = pct_obs) %>%
  t()

write.csv(pct_obs_one_signal_ptile, paste0(FILEPATHS$out_path, 'tables/pct_obs_one_signal_ptile.csv'))
cat("信号筛选全部完成！表格已保存在 output_cm/tables 目录。\n")