# 3_pcr_forecast_simplified.R
# 功能：使用主成分回归 (PCR) 进行滚动窗口预测

rm(list = ls())
library(data.table)
library(dplyr)
library(zoo)
source("functions.R")

getFilePaths()

cat("读取插补后的特征数据...\n")
signals <- fread(paste0(FILEPATHS$data_path, "bcsignals/bcsignals_simple.csv"))
if(class(signals$yyyymm) != "yearmon") {
  signals[, yyyymm := as.yearmon(yyyymm)]
}

# ================= 新增：将基础收益率(ret)和市值(me)合并回来 ================= 
cat("读取基础收益率与市值数据...\n")
crsp_data <- fread(paste0(FILEPATHS$data_path, "raw/crsp_data.csv"))[, .(permno, yyyymm, ret, me)]
if(class(crsp_data$yyyymm) != "yearmon") {
  crsp_data[, yyyymm := as.yearmon(yyyymm)]
}
# 合并数据
signals <- merge(signals, crsp_data, by = c("permno", "yyyymm"))
# ==============================================================================

# 构造预测目标：未来一个月的收益率 bh1m (即买入并持有1个月的收益)
cat("对齐预测时间窗口 (生成 bh1m)...\n")
signals <- signals[order(permno, yyyymm)]
signals[, bh1m := shift(ret, 1, type = "lead"), by = permno]
signals[, time_avail_m := yyyymm + 1/12] # 信号可用的时间（即预测发生的月份）

# 剔除无法预测的尾部数据
signals <- signals[!is.na(bh1m)]

# 提取用于降维的特征列
impute_vec <- unpackSignalList(FILEPATHS$signal_list)
signals_keep <- intersect(colnames(signals), impute_vec)

# 定义滚动预测参数
n_yrs <- 3 # 使用过去3年(36个月)的数据作为训练集
n_pcs <- 10 # 提取前10个主成分进行回归

# 获取所有可以进行预测的月份 (从第37个月开始，以保证有足够的训练数据)
all_months <- sort(unique(signals$time_avail_m))
forecast_months <- all_months[all_months >= (min(all_months) + n_yrs)]

cat(sprintf("准备进行滚动外推预测，共 %d 个月份...\n", length(forecast_months)))

pcr_predictions <- list()

# 滚动窗口循环预测
for (pred_mon in forecast_months) {
  # 划分训练集和测试集
  train_data <- signals[time_avail_m < pred_mon & time_avail_m >= (pred_mon - n_yrs)]
  test_data <- signals[time_avail_m == pred_mon]
  
  if(nrow(train_data) < 100 || nrow(test_data) < 10) next
  
  # ================= 关键修复：动态剔除方差为 0 的列 =================
  # 计算训练集中各特征的方差
  col_vars <- sapply(train_data[, ..signals_keep], function(x) var(x, na.rm = TRUE))
  # 只保留方差大于 0 的特征列
  valid_signals <- signals_keep[col_vars > 0 & !is.na(col_vars)]
  
  # 动态调整：如果剩下的有效信号数量少于设定的主成分数量，则调小主成分提取量
  current_n_pcs <- min(n_pcs, length(valid_signals))
  if(current_n_pcs < 1) next
  # ====================================================================
  
  # 在训练集上提取主成分 (PCA)
  pc <- prcomp(train_data[, ..valid_signals], center = TRUE, scale = TRUE)
  
  # 构建训练集回归数据 (drop = FALSE 防止列数变成1时转为向量)
  train_pc <- data.table(bh1m = train_data$bh1m, pc$x[, 1:current_n_pcs, drop = FALSE])
  
  # 拟合 PCR 模型
  form <- paste0("bh1m ~ ", paste(paste0("PC", 1:current_n_pcs), collapse = "+"))
  mod_ew <- lm(form, data = train_pc)
  
  # 对测试集应用相同的 PCA 旋转矩阵
  test_scaled <- scale(test_data[, ..valid_signals], center = pc$center, scale = pc$scale)
  # 极少数情况下测试集可能产生 NA，稳妥起见将其替换为 0（代表截面均值）
  test_scaled[is.na(test_scaled)] <- 0
  
  test_pc <- data.table(test_scaled %*% pc$rotation[, 1:current_n_pcs, drop = FALSE])
  
  # 预测测试集收益率
  preds <- predict(mod_ew, test_pc)
  
  # 保存预测结果
  pcr_predictions[[as.character(pred_mon)]] <- data.table(
    permno = test_data$permno,
    yyyymm = pred_mon,
    Ebh1m = preds,         # 预期收益率
    bh1m = test_data$bh1m, # 实际收益率
    me = test_data$me      # 市值(用于加权)
  )
}

# 合并所有预测结果
final_forecasts <- rbindlist(pcr_predictions)

dir.create(paste0(FILEPATHS$out_path, "forecast/"), showWarnings = FALSE, recursive = TRUE)
fwrite(final_forecasts, paste0(FILEPATHS$out_path, "forecast/pcr_forecast_simple.csv"))
cat("滚动窗口 PCR 预测完成！结果已输出至 forecast/pcr_forecast_simple.csv\n")