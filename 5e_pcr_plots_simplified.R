# 5e_pcr_plots_simplified.R
# 功能：绘制不同主成分数量(PCs)下的多空组合夏普比率 (对应原论文 Figure 2)

rm(list = ls())
library(data.table)
library(dplyr)
library(zoo)
library(ggplot2)
source("functions.R")
getFilePaths()

cat("读取数据准备进行多次 PCR 回归...\n")
signals <- fread(paste0(FILEPATHS$data_path, "bcsignals/bcsignals_simple.csv"))

# =========== 关键修复：只合并 ret，不合并 me，防止重名变成 me.x 和 me.y ===========
crsp_data <- fread(paste0(FILEPATHS$data_path, "raw/crsp_data.csv"))[, .(permno, yyyymm, ret)]
signals <- merge(signals, crsp_data, by = c("permno", "yyyymm"))
# =================================================================================

signals <- signals[order(permno, yyyymm)]
signals[, bh1m := shift(ret, 1, type = "lead"), by = permno]
signals[, time_avail_m := yyyymm + 1/12]
signals <- signals[!is.na(bh1m)]

impute_vec <- unpackSignalList(FILEPATHS$signal_list)
signals_keep <- intersect(colnames(signals), impute_vec)

n_yrs <- 3
all_months <- sort(unique(signals$time_avail_m))
forecast_months <- all_months[all_months >= (min(all_months) + n_yrs)]

# 我们要测试的主成分数量序列 (从 1 个主成分到 10 个主成分)
pc_seq <- 1:10
results_list <- list()

cat("开始计算不同 PC 数量下的策略表现 (可能需要1-2分钟)...\n")

for (n_pcs in pc_seq) {
  cat("正在评估保留", n_pcs, "个主成分的表现...\n")
  pcr_preds <- list()
  
  for (pred_mon in forecast_months) {
    train_data <- signals[time_avail_m < pred_mon & time_avail_m >= (pred_mon - n_yrs)]
    test_data <- signals[time_avail_m == pred_mon]
    if(nrow(train_data) < 100 || nrow(test_data) < 10) next
    
    col_vars <- sapply(train_data[, ..signals_keep], function(x) var(x, na.rm = TRUE))
    valid_signals <- signals_keep[col_vars > 0 & !is.na(col_vars)]
    current_n_pcs <- min(n_pcs, length(valid_signals))
    if(current_n_pcs < 1) next
    
    pc <- prcomp(train_data[, ..valid_signals], center = TRUE, scale = TRUE)
    train_pc <- data.table(bh1m = train_data$bh1m, pc$x[, 1:current_n_pcs, drop = FALSE])
    
    form <- paste0("bh1m ~ ", paste(paste0("PC", 1:current_n_pcs), collapse = "+"))
    mod_ew <- lm(form, data = train_pc)
    
    test_scaled <- scale(test_data[, ..valid_signals], center = pc$center, scale = pc$scale)
    test_scaled[is.na(test_scaled)] <- 0
    test_pc <- data.table(test_scaled %*% pc$rotation[, 1:current_n_pcs, drop = FALSE])
    
    pcr_preds[[as.character(pred_mon)]] <- data.table(
      permno = test_data$permno,
      yyyymm = pred_mon, 
      Ebh1m = predict(mod_ew, test_pc),
      bh1m = test_data$bh1m, 
      me = test_data$me
    )
  }
  
  fcasts <- rbindlist(pcr_preds)
  
  # 计算十分位组合
  fcasts[, `:=`(pctile10 = quantile(Ebh1m, 0.1, na.rm=TRUE), pctile90 = quantile(Ebh1m, 0.9, na.rm=TRUE)), by = yyyymm]
  fcasts[, decile := case_when(Ebh1m <= pctile10 ~ 1, Ebh1m >= pctile90 ~ 10, TRUE ~ NA_real_)]
  
  # 计算多空组合收益
  ls_ports <- fcasts[!is.na(decile), .(
    vw_ret = weighted.mean(ifelse(decile == 1, -1, 1) * bh1m, w = me, na.rm = TRUE)
  ), by = .(yyyymm)]
  
  # 计算夏普比率 (年化)
  sharpe <- (mean(ls_ports$vw_ret, na.rm = TRUE) / sd(ls_ports$vw_ret, na.rm = TRUE)) * sqrt(12)
  
  results_list[[n_pcs]] <- data.table(PCs = n_pcs, Sharpe = sharpe)
}

final_results <- rbindlist(results_list)

# 绘制折线图
png(paste0(FILEPATHS$out_path, "plots/sharpe_vs_pcs.png"), width = 800, height = 500, res = 120)
p_sharpe <- ggplot(final_results, aes(x = PCs, y = Sharpe)) +
  geom_line(color = "darkred", size = 1.2) +
  geom_point(color = "darkred", size = 3) +
  theme_bw() +
  scale_x_continuous(breaks = pc_seq) +
  labs(title = "Strategy Sharpe Ratio vs. Number of Principal Components",
       subtitle = "Value-Weighted Long-Short Portfolio",
       x = "Number of PCs included in Regression",
       y = "Annualized Sharpe Ratio") +
  theme(text = element_text(size = 14))
print(p_sharpe)
dev.off()

cat("图表生成完毕！已保存在 output_cm/plots/sharpe_vs_pcs.png \n")