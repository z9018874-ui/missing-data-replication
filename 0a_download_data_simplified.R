# 0a_download_data.R (修改版：本地CSV读取与降维)
library(data.table)
library(zoo)
library(dplyr)
source("functions.R")

getFilePaths(signal_list_exists = FALSE)
dir.create(paste0(FILEPATHS$data_path, "raw/"), showWarnings = FALSE, recursive = TRUE)

# ============================================================================== #
# 1. 读取本地 CRSP 数据并降维
# ============================================================================== #
cat("正在读取本地 CRSP CSV...\n")
# 请确保您的本地 CSV 文件命名为 crsp_monthly.csv，并与本脚本在同一目录
crsp_raw <- fread("crsp_monthly.csv")

# 统一列名以匹配截图中的变量名格式
setnames(crsp_raw, tolower(names(crsp_raw)))

crsp_subset <- crsp_raw %>%
  select(permno, yyyymm, hsiccd = siccd, mthret, mthcap, mthprc) %>%
  mutate(
    date = as.Date(paste0(substr(as.character(yyyymm), 1, 4), "-", 
                          substr(as.character(yyyymm), 5, 6), "-01")),
    yyyymm = as.yearmon(date)
  )

cat("正在执行降维：时间截断(2010-2020)及市值Top500筛选...\n")
# 时间降维
crsp_subset <- crsp_subset %>%
  filter(year(date) >= 2010 & year(date) <= 2020)

# 横截面降维：按平均市值(mthcap)筛选前500只股票
top_500_perms <- crsp_subset %>%
  filter(!is.na(mthcap)) %>%
  group_by(permno) %>%
  summarise(avg_me = mean(mthcap, na.rm = TRUE)) %>%
  top_n(500, avg_me) %>%
  pull(permno)

crsp_subset <- crsp_subset %>% filter(permno %in% top_500_perms)

# 构造原代码下游所需的衍生变量
crsp_final <- crsp_subset %>%
  mutate(
    ret = 100 * as.numeric(mthret),                # 转换为百分比收益率
    me = abs(as.numeric(mthcap)),                  # 市值
    price = -1 * log(abs(as.numeric(mthprc))),     # 价格对数变换
    streversal = -1 * ifelse(is.na(ret), 0, ret),  # 短期反转信号
    size = ifelse(me > 0, -1 * log(me), NA)        # 规模信号
  ) %>%
  select(permno, hsiccd, yyyymm, ret, me, price, streversal, size)

fwrite(crsp_final, paste0(FILEPATHS$data_path, "raw/crsp_data.csv"))
cat("CRSP 本地数据处理完毕，已输出至 raw/crsp_data.csv\n")

# ============================================================================== #
# 2. 外部信号数据 (Chen-Zimmermann Data) 处理
# ============================================================================== #
# 注意：原代码需要从 Google Drive 下载 2GB 的信号数据。
# 为了代码能跑通，假设您已经手动将 `signed_predictors_dl_wide.csv` 放在了 raw 文件夹下。
# 如果您没有该文件，下面的合并步骤会报错。

signals <- fread(paste0(FILEPATHS$data_path, "raw/signed_predictors_dl_wide.csv"))
setnames(signals, colnames(signals), tolower(colnames(signals)))
if (class(signals$yyyymm) != "yearmon") {
  signals[, yyyymm := as.yearmon(as.character(yyyymm * 10 + 1), format = "%Y%m%d")]
}

# 仅保留被选中的 Top 500 股票的信号，极大减少文件体积
signals_filt <- merge(signals, crsp_final[, .(permno, yyyymm)], by = c("permno", "yyyymm"))

fwrite(signals_filt, paste0(FILEPATHS$data_path, "raw/signed_predictors_dl_wide_filtered.csv"))
cat("信号数据匹配并缩减完成！\n")