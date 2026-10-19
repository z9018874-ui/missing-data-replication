# 5a_miss_plot_simplified.R
# 功能：分析并绘制特征缺失率分布图 (对应原论文 Figure 1 的探讨)

rm(list = ls())
library(data.table)
library(dplyr)
library(tidyr)
library(ggplot2)
source("functions.R")
getFilePaths()

cat("读取未插补的原始信号数据...\n")
# 读取我们在第 1 步处理好的未插补数据
dat <- fread(paste0(FILEPATHS$data_path, "bcsignals/bcsignals_none.csv"))

# 计算每个信号的整体缺失率
cat("计算缺失率...\n")
miss_summary <- dat %>%
  summarise(across(-c(permno, yyyymm), ~mean(is.na(.)))) %>%
  pivot_longer(everything(), names_to = "signal", values_to = "miss_rate") %>%
  arrange(desc(miss_rate))

dir.create(paste0(FILEPATHS$out_path, "plots/"), showWarnings = FALSE, recursive = TRUE)

# 1. 绘制缺失率排名前 30 的特征条形图
png(paste0(FILEPATHS$out_path, "plots/missing_rates_top30.png"), width = 800, height = 600, res = 100)
p1 <- ggplot(miss_summary[1:30, ], aes(x = reorder(signal, miss_rate), y = miss_rate)) +
  geom_bar(stat = "identity", fill = "steelblue") +
  coord_flip() + # 横向显示
  scale_y_continuous(labels = scales::percent) +
  theme_bw() +
  labs(title = "Top 30 Signals with Highest Missing Rates",
       x = "Signal Name", y = "Missing Rate") +
  theme(text = element_text(size = 14))
print(p1)
dev.off()

# 2. 绘制所有信号缺失率的整体分布直方图
png(paste0(FILEPATHS$out_path, "plots/missing_rates_distribution.png"), width = 800, height = 500, res = 100)
p2 <- ggplot(miss_summary, aes(x = miss_rate)) +
  geom_histogram(bins = 30, fill = "darkred", color = "black", alpha = 0.7) +
  scale_x_continuous(labels = scales::percent) +
  theme_bw() +
  labs(title = "Distribution of Missing Rates Across All Signals",
       x = "Missing Rate", y = "Count of Signals") +
  theme(text = element_text(size = 14))
print(p2)
dev.off()

cat("缺失值图表生成完毕！已保存在 output_cm/plots/ 目录下。\n")