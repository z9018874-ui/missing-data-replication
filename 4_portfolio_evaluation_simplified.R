# 4_portfolio_evaluation.R
# 功能：根据模型预测结果构建多空投资组合 (Long-Short Portfolio) 并可视化表现

rm(list = ls())
library(data.table)
library(dplyr)
library(zoo)

source("functions.R")
getFilePaths()

cat("读取模型预测结果...\n")
fcasts <- fread(paste0(FILEPATHS$out_path, "forecast/pcr_forecast_simple.csv"))
if(class(fcasts$yyyymm) != "yearmon") fcasts[, yyyymm := as.yearmon(yyyymm)]

# ================= 关键修复：把纯净的市值数据重新合并进来 ================= 
cat("读取市值数据用于加权...\n")
crsp_data <- fread(paste0(FILEPATHS$data_path, "raw/crsp_data.csv"))[, .(permno, yyyymm, me)]
if(class(crsp_data$yyyymm) != "yearmon") {
  crsp_data[, yyyymm := as.yearmon(yyyymm)]
}
# 通过 permno 和 yyyymm 对齐并合并市值
fcasts <- merge(fcasts, crsp_data, by = c("permno", "yyyymm"), all.x = TRUE)
# =========================================================================

cat("构建十分位多空投资组合...\n")
# 根据预测收益率 (Ebh1m) 划分十分位 (Deciles)
fcasts[, `:=`(
  pctile10 = quantile(Ebh1m, 0.1, na.rm = TRUE),
  pctile90 = quantile(Ebh1m, 0.9, na.rm = TRUE)
), by = .(yyyymm)]

fcasts[, decile := case_when(
  Ebh1m <= pctile10 ~ 1,  # 预测表现最差的 10% (做空)
  Ebh1m >= pctile90 ~ 10, # 预测表现最好的 10% (做多)
  TRUE ~ NA_real_
)]

# 计算多空组合(Long-Short)在每个月的实际平均收益率
# 做多第10组(权重为1)，做空第1组(权重为-1)
ls_ports <- fcasts[!is.na(decile), .(
  # 等权收益率 (Equal-weighted)
  ew_ret = mean(ifelse(decile == 1, -1, 1) * bh1m, na.rm = TRUE),
  # 市值加权收益率 (Value-weighted)
  vw_ret = weighted.mean(ifelse(decile == 1, -1, 1) * bh1m, w = me, na.rm = TRUE)
), by = .(yyyymm)]

ls_ports <- ls_ports[order(yyyymm)]

# 计算累积收益率 (Cumulative Returns)
ls_ports[, cumret_ew := cumprod(1 + ew_ret / 100) - 1]
ls_ports[, cumret_vw := cumprod(1 + vw_ret / 100) - 1]

# 输出组合表现摘要
cat("\n--- 策略年化表现摘要 ---\n")
annual_factor <- 12
summary_stats <- ls_ports[, .(
  EW_Mean_Return = mean(ew_ret, na.rm = TRUE) * annual_factor,
  VW_Mean_Return = mean(vw_ret, na.rm = TRUE) * annual_factor,
  EW_Sharpe = (mean(ew_ret, na.rm = TRUE) / sd(ew_ret, na.rm = TRUE)) * sqrt(annual_factor),
  VW_Sharpe = (mean(vw_ret, na.rm = TRUE) / sd(vw_ret, na.rm = TRUE)) * sqrt(annual_factor)
)]
print(summary_stats)

cat("正在生成累积收益率图表...\n")
dir.create(paste0(FILEPATHS$out_path, "plots/"), showWarnings = FALSE, recursive = TRUE)
plot_file <- paste0(FILEPATHS$out_path, "plots/portfolio_performance.png")
png(plot_file, width = 800, height = 500, res = 120)

# 绘制折线图
plot(ls_ports$yyyymm, ls_ports$cumret_ew * 100, type = "l", col = "steelblue", lwd = 2,
     main = "PCR Model: Long-Short Portfolio Cumulative Return",
     xlab = "Date", ylab = "Cumulative Return (%)",
     ylim = range(c(ls_ports$cumret_ew * 100, ls_ports$cumret_vw * 100), na.rm = TRUE))
lines(ls_ports$yyyymm, ls_ports$cumret_vw * 100, col = "darkred", lwd = 2, lty = 2)

# 添加图例与水平零线
legend("topleft", legend = c("Equal-Weighted (EW)", "Value-Weighted (VW)"),
       col = c("steelblue", "darkred"), lty = c(1, 2), lwd = 2, bty = "n")
abline(h = 0, col = "gray50", lty = 3)

dev.off()
cat(sprintf("图表已保存至 %s，大功告成！\n", plot_file))