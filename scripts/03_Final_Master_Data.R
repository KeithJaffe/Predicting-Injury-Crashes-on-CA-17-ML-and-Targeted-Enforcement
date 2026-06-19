rm(list = ls())
setwd("~/Desktop/grad_school/222_project/222_project/raw merged data")

library(dplyr)
library(lubridate)
library(tidyr)
library(readr)

################### Full Hourly Spine ###################
### Build hours spline ###
full_hours <- tibble(
  Timestamp = seq(
    from = as.POSIXct("2014-01-01 00:00:00", tz = "America/Los_Angeles"),
    to = as.POSIXct("2025-09-30 23:00:00", tz = "America/Los_Angeles"),
    by = "hour"
  )
)

### Check: should be 102983 ###
nrow(full_hours)

################### Traffic Volume Sensor Data ############################################################################################################
pems_rough <- read.csv("pems_rough.csv")

### select which variable to keep ###
pems_rough <- pems_rough %>%
  select(V1, V2, V5, V10, V11, V12)

### label variables name ###
colnames(pems_rough) <- c("Timestamp", "Station", "Direction", "Total.Flow", "AVG.Occupancy", "AVG.Speed")

### save the date in the same format ###
pems_rough$Timestamp <- floor_date(as.POSIXct(pems_rough$Timestamp,
                                               format = "%m/%d/%Y %H:%M:%S",
                                               tz = "America/Los_Angeles"),
                                    unit = "hour")
pems_rough$Station  <- as.factor(pems_rough$Station)
pems_rough$Direction  <- as.factor(pems_rough$Direction)

### Split to station CSVs ###
station_folder <- "~/Desktop/grad_school/222_project/222_project/station_data"
dir.create(station_folder, recursive = TRUE, showWarnings = FALSE)


pems_rough %>%
  group_by(Station) %>%
  group_walk(~ write_csv(.x, file.path(station_folder, paste0("station_", .y$Station, ".csv"))))

### Reload and pivot to wide ###
files <- list.files(station_folder, pattern = "*.csv", full.names = TRUE)

#### create a function that updates the individual files ####
pems_wide <- files %>%
  lapply(function(f) {
    station_id <- gsub("station_|\\.csv", "", basename(f))
    read_csv(f, show_col_types = FALSE) %>% mutate(Station = station_id)
  }) %>%
  bind_rows() %>%
  pivot_wider(
    id_cols = Timestamp,
    names_from = Station,
    values_from = c(Total.Flow, AVG.Occupancy, AVG.Speed),
    names_glue = "{Station}_{.value}"
  )

### Fix timezone ###
pems_wide$Timestamp <- with_tz(pems_wide$Timestamp, tzone = "America/Los_Angeles")

### Trim to study period ###
pems_wide <- pems_wide %>%
  filter(Timestamp <= as.POSIXct("2025-09-30 23:00:00", tz = "America/Los_Angeles"))

## Remove all rows that have duplicates ####
pems_wide <- pems_wide %>%
  distinct(Timestamp, .keep_all = TRUE)

### Join onto full spine (fills gaps with NA) ###
pems_final <- full_hours %>%
  left_join(pems_wide, by = "Timestamp")

#### Should be 102983 ####
nrow(pems_final)

rm(pems_rough, pems_wide, files, station_folder)

################### Weather Data #################################################################################################################
weather_sc <- read.csv("weather_sc.csv")
weather_scl <- read.csv("weather_scl.csv")
weather_summit <- read.csv("weather_summit.csv")

#### sc ####
#### upload data set and correctly format time and categorical variables ####
weather_sc <- weather_sc %>%
  select(-sc_name, -sc_snowdepth, -X) %>%
  mutate(
    Timestamp = as.POSIXct(datetime, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Los_Angeles"),
    sc_preciptype = as.factor(sc_preciptype),
    sc_conditions = as.factor(sc_conditions),
    sc_icon = as.factor(sc_icon)
  ) %>%
  select(-datetime)

### save the time variable in the ###
weather_sc$Timestamp <- force_tz(weather_sc$Timestamp, tzone = "America/Los_Angeles")

weather_sc <- weather_sc %>%
  group_by(Timestamp) %>%
  slice(1) %>%
  ungroup()

#### scl ####
weather_scl <- weather_scl %>%
  select(-scl_name, -scl_snowdepth, -X) %>%
  mutate(
    Timestamp = as.POSIXct(datetime, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Los_Angeles"),
    scl_preciptype = as.factor(scl_preciptype),
    scl_conditions = as.factor(scl_conditions),
    scl_icon = as.factor(scl_icon)
  ) %>%
  select(-datetime)

weather_scl$Timestamp <- force_tz(weather_scl$Timestamp, tzone = "America/Los_Angeles")

weather_scl <- weather_scl %>%
  group_by(Timestamp) %>%
  slice(1) %>%
  ungroup()

#### summit ####
weather_summit <- weather_summit %>%
  select(-sum_source, -sum_name, -sum_latitude, -sum_longitude, -X) %>%
  mutate(
    Timestamp = as.POSIXct(datetime, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Los_Angeles"),
    sum_preciptype = as.factor(sum_preciptype),
    sum_conditions = as.factor(sum_conditions),
    sum_icon = as.factor(sum_icon)
  ) %>%
  select(-datetime)

weather_summit$Timestamp <- force_tz(weather_summit$Timestamp, tzone = "America/Los_Angeles")

weather_summit <- weather_summit %>%
  group_by(Timestamp) %>%
  slice(1) %>%
  ungroup()


################### Accident Data ###################
accident_rough <- read.csv("hw17_accident_merge.csv")
library(lubridate)
# 1. PROCESS ACCIDENTS (Keep the Hour!)
accidents_clean <- accident_rough %>%
  mutate(
    COLLISION_TIME = ifelse(COLLISION_TIME == 2500, 0, COLLISION_TIME),  # fix bad entry
    hour_val = COLLISION_TIME %/% 100,
    min_val  = COLLISION_TIME %% 100,
    dt_string = paste(COLLISION_DATE, sprintf("%02d:%02d:00", hour_val, min_val)),
    Timestamp = floor_date(ymd_hms(dt_string, tz = "America/Los_Angeles"), unit = "hour")
  )

# 2. GROUP BY THE FULL DATETIME
accidents_hourly <- accidents_clean %>%
  group_by(Timestamp) %>%
  summarise(accident_count = n(), .groups = "drop")

# 3. VERIFY
print(max(accidents_hourly$accident_count))

# 4. JOIN TO FULL HOURS
accidents <- full_hours %>%
  left_join(accidents_hourly, by = "Timestamp") %>%
  mutate(accident_count = replace_na(accident_count, 0))

################### Build Master Dataset #########################################################################################################
master_data <- accidents %>%
  left_join(pems_final,  by = "Timestamp") %>%
  left_join(weather_sc,  by = "Timestamp") %>%
  left_join(weather_scl, by = "Timestamp") %>%
  left_join(weather_summit, by = "Timestamp")

#### Drop the 11 spring-forward hours where no data exists from any source ####
master_data <- master_data %>%
  filter(!if_all(-Timestamp, is.na))

##################### Checking the data set #####################
### check the number of rows: should be 102983 #####
nrow(master_data)
n_distinct(master_data$Timestamp) # should equal nrow

#### Confirm no fully-empty rows remain ####
master_data %>%
  filter(if_all(-Timestamp, is.na)) %>%
  nrow() # should be 0


### check to see if it the time variable is continuous throughout the data set ###
time_diffs <- diff(master_data$Timestamp)
table(time_diffs)

### counts rows with no NAs ###
sum(complete.cases(master_data))


### see what columns have the most NAs ###
colSums(is.na(master_data)) %>% sort(decreasing = TRUE) %>% head(20)


### show NA count and coverage % for every PeMS column ###
pems_na <- colSums(is.na(master_data %>% select(contains("Total.Flow"))))
data.frame(
  station = names(pems_na),
  na_count = pems_na,
  pct_missing = round(pems_na / nrow(master_data) * 100, 1)
) %>% arrange(pct_missing)

##### select all the stations with over 80% missing observations ######
bad_stations <- c("404363", "404364", "404366", "404367", "404368", "404369",
                  "404372", "404373", "404374", "404375", "404376", "404377",
                  "429394", "429395", "429398", "429399", "429403", "429404",
                  "429785", "429786", "429788", "429396", "429397", "429400",
                  "429401", "429402", "429405")

### drop the bad stations ####
master_data <- master_data %>%
  select(!matches(paste(bad_stations, collapse = "|")))

### Check: How many observations are still missing 
ncol(master_data)
sum(!complete.cases(master_data))

colSums(is.na(master_data)) %>% sort(decreasing = TRUE) %>% head(100)

### drop the severe risk variables ######
master_data <- master_data %>%
  select(-sc_severerisk, -scl_severerisk, -sum_severerisk)
sum(!complete.cases(master_data))


######################## Creating Variables for the master data set #####################################################################################

####### create hour, day, month, year fixed effects ######

### master data set used for random forest design ####
master_data <- master_data %>%
  mutate(
    hour = hour(Timestamp),
    day_of_week = wday(Timestamp, label = FALSE),
    month = month(Timestamp),
    year = year(Timestamp)
  )

#### Save the categorical variables as a factor ####
master_data <- master_data %>%
  mutate(
    hour = as.factor(hour),
    day_of_week = as.factor(day_of_week),
    month = as.factor(month),
    year  = as.factor(year)
  )

### Confirm the fixed effects exist with expected ranges ###
summary(master_data[, c("hour", "day_of_week", "month", "year")])

### check if the day of the week was correct, 1/1/14 is a Wednseday.9/30/25 is a tuesday ####
head(master_data$day_of_week)

tail(master_data$day_of_week)

### check if the month is correct ###
head(master_data$month)
tail(master_data$month)

### check if the year is correct ### 
head(master_data$year)
tail(master_data$year)


########################## Indicator Variables for holidays ################################
library(dplyr)
library(lubridate)

years <- 2014:2025

#### nth weekday of a month (weekday: 1=Sun, 2=Mon, ..., 7=Sat) ####
nth_wday_of_month <- function(year, month, weekday, n) {
  d <- as.Date(paste(year, sprintf("%02d", month), "01", sep = "-"))
  diff <- (weekday - wday(d)) %% 7
  d + diff + (n - 1) * 7
}

#### Last weekday of a month function ####
last_wday_of_month <- function(year, month, weekday) {
  last_d <- as.Date(paste(year, sprintf("%02d", month),
                          days_in_month(as.Date(paste(year, month, "01", sep = "-"))),
                          sep = "-"))
  diff <- (wday(last_d) - weekday) %% 7
  last_d - diff
}

### Expand holiday date to Fri-Mon window ###
####thursday = TRUE: use following Fri-Mon (for Thanksgiving) ###
to_weekend <- function(dates, thursday = FALSE) {
  result <- c()
  for (d in as.Date(dates)) {
    d <- as.Date(d, origin = "1970-01-01")
    dow <- wday(d)
    if (thursday) {
      fri <- d + 1
    } else {
      fri <- d - (dow - 6) %% 7
    }
    mon <- fri + 3
    result <- c(result, seq(fri, mon, by = "day"))
  }
  unique(as.Date(result, origin = "1970-01-01"))
}

## holidays ###
new_years  <- as.Date(paste(years, "01-01", sep = "-"))
mlk <- do.call(c, lapply(years, function(y) nth_wday_of_month(y, 1, 2, 3)))
presidents <- do.call(c, lapply(years, function(y) nth_wday_of_month(y, 2, 2, 3)))
memorial <- do.call(c, lapply(years, function(y) last_wday_of_month(y, 5, 2)))
juneteenth <- as.Date(paste(years, "06-19", sep = "-"))
independence <- as.Date(paste(years, "07-04", sep = "-"))
labor <- do.call(c, lapply(years, function(y) nth_wday_of_month(y, 9, 2, 1)))
columbus <- do.call(c, lapply(years, function(y) nth_wday_of_month(y, 10, 2, 2)))
veterans <- as.Date(paste(years, "11-11", sep = "-"))
thanksgiving <- do.call(c, lapply(years, function(y) nth_wday_of_month(y, 11, 5, 4)))
christmas <- as.Date(paste(years, "12-25", sep = "-"))

### Easter####
easter <- as.Date(c(
  "2014-04-20", "2015-04-05", "2016-03-27", "2017-04-16",
  "2018-04-01", "2019-04-21", "2020-04-12", "2021-04-04",
  "2022-04-17", "2023-04-09", "2024-03-31", "2025-04-20"
))


### Thanksgiving break ###
thanksgiving_break <- c()
for (d in thanksgiving) {
  thanksgiving_break <- c(thanksgiving_break,
                          seq(as.Date(d) - 1, as.Date(d) + 3, by = "day"))
}
thanksgiving_break <- unique(as.Date(thanksgiving_break))


### SJSU gradautions ###
sjsu_grad <- as.Date(c(
  "2014-05-24", "2015-05-23", "2016-05-21", "2017-05-27",
  "2018-05-26", "2019-05-25", "2020-05-16", "2021-05-22",
  "2022-05-21", "2023-05-27", "2024-05-18", "2025-05-17"
))

### UCSC graduations ###
ucsc_grad <- as.Date(c(
  "2014-06-14", "2015-06-13", "2016-06-11", "2017-06-17",
  "2018-06-16", "2019-06-15", "2020-06-13", "2021-06-12",
  "2022-06-11", "2023-06-10", "2024-06-15", "2025-06-14"
))

### San Jose high school graduations: typically 1st Saturday of June ###
sj_hs_grad <- as.Date(c(
  "2014-06-07", "2015-06-06", "2016-06-04", "2017-06-10",
  "2018-06-09", "2019-06-08", "2020-06-06", "2021-06-05",
  "2022-06-04", "2023-06-10", "2024-06-08", "2025-06-07"
))

# ---- Add indicator columns to master_data_rm ----

master_data <- master_data %>%
  mutate(
    date = as.Date(Timestamp),
    
    ### Federal holiday weekends (Fri-Mon) ###
    ind_new_years = as.integer(date %in% to_weekend(new_years)),
    ind_mlk  = as.integer(date %in% to_weekend(mlk)),
    ind_presidents = as.integer(date %in% to_weekend(presidents)),
    ind_memorial = as.integer(date %in% to_weekend(memorial)),
    ind_juneteenth = as.integer(date %in% to_weekend(juneteenth)),
    ind_independence = as.integer(date %in% to_weekend(independence)),
    ind_labor = as.integer(date %in% to_weekend(labor)),
    ind_columbus = as.integer(date %in% to_weekend(columbus)),
    ind_veterans = as.integer(date %in% to_weekend(veterans)),
    ind_thanksgiving = as.integer(date %in% to_weekend(thanksgiving, thursday = TRUE)),
    ind_christmas = as.integer(date %in% to_weekend(christmas)),
    ind_easter = as.integer(date %in% to_weekend(easter)),
    
    ### School breaks ###
    ind_thanksgiving_break = as.integer(date %in% thanksgiving_break),
    
    
    ### Graduation weekends (Fri-Mon) ###
    ind_sjsu_grad = as.integer(date %in% to_weekend(sjsu_grad)),
    ind_ucsc_grad = as.integer(date %in% to_weekend(ucsc_grad)),
    ind_sj_hs_grad = as.integer(date %in% to_weekend(sj_hs_grad))
  ) %>%
  select(-date)

### Generate covid vairables ###
master_data <- master_data %>%
  mutate(
    date = as.Date(Timestamp),
    
    ind_covid_lockdown1 = as.integer(date >= as.Date("2020-03-19") &
                                          date <= as.Date("2020-06-12")),
    ind_covid_partial = as.integer(date >= as.Date("2020-06-13") &
                                          date <= as.Date("2020-12-03")),
    ind_covid_lockdown2 = as.integer(date >= as.Date("2020-12-04") &
                                          date <= as.Date("2021-01-25")),
    ind_covid_gradual = as.integer(date >= as.Date("2021-01-26") &
                                          date <= as.Date("2021-06-14")),
    ind_covid_reopen = as.integer(date >= as.Date("2021-06-15") &
                                          date <= as.Date("2021-12-31"))
  ) %>%
  select(-date)

### verify
master_data %>%
  select(starts_with("ind_")) %>%
  summarise(across(everything(), sum))

master_data %>%
  select(starts_with("ind_covid")) %>%
  summarise(across(everything(), sum))


sapply(master_data, class)


###### create a rolling median for the the data set to deal with NAs and impute the rest for the supervised learning algorithm ###########################################

### Use a rolling median for missing values ####
library(zoo)

### Same-hour average of day before and day after ###
master_data <- master_data %>%
  mutate(across(where(is.numeric), ~ ifelse(
    is.na(.),
    (lag(., 24) + lead(., 24)) / 2,
    .
  )))

### Hourly median fallback for remaining NAs ###
master_data <- master_data %>%
  group_by(hour) %>%
  mutate(across(where(is.numeric), ~ ifelse(is.na(.), median(., na.rm = TRUE), .))) %>%
  ungroup()

### Snow to 0, then drop (always zero on Highway 17 — no variance) ###
master_data <- master_data %>%
  mutate(across(c(sc_snow, scl_snow, sum_snow), ~ ifelse(is.na(.), 0, .))) %>%
  select(-sc_snow, -scl_snow, -sum_snow)

### Forward fill categorical weather variables ###
master_data <- master_data %>%
  fill(sc_preciptype, sc_conditions, sc_icon,
       scl_preciptype, scl_conditions, scl_icon,
       sum_preciptype, sum_conditions, sum_icon,
       .direction = "downup")

### Final checks ###
sum(!complete.cases(master_data))
colSums(is.na(master_data)) %>% sort(decreasing = TRUE) %>% head(10)



######### Add LAGS for traffic patterns ####
master_data <- master_data %>%
  mutate(across(contains("Total.Flow") | contains("AVG.Occupancy") | contains("AVG.Speed"),
                list(lag1 = ~ lag(., 1),
                     lag2 = ~ lag(., 2),
                     lag3 = ~ lag(., 3)),
                .names = "{.col}_{.fn}"))


#### Add lags for weather data ###
weather_cols <- names(master_data)[grepl("^sc_|^scl_|^sum_", names(master_data))]

master_data <- master_data %>%
  mutate(across(all_of(weather_cols),
                list(lag24 = ~ lag(., 24)),
                .names = "{.col}_{.fn}"))

##### delete the lags on categorical variables ######
master_data <- master_data %>%
  select(-matches("sc_preciptype_lag|sc_conditions_lag|sc_icon_lag|scl_preciptype_lag|scl_conditions_lag|
                  scl_icon_lag|scl_preciptype_lag24|sum_preciptype_lag|
                  sum_conditions_lag|sum_icon_lag|sum_preciptype_lag24"))



### the lags have 0 values ####
### Drop the first 24 observations of the data set ####
master_data2 <- master_data %>%
  slice(-(1:24)) # drops first 24 rows (covers all lag windows)

### drop the unlagged traffic varibles ###
master_data2 <- master_data2 %>%
  select(-((contains("Total.Flow") | contains("AVG.Occupancy") | contains("AVG.Speed")) & 
             !contains("lag")))

### Check the data set ###
names(master_data2)[grepl("preciptype_lag|conditions_lag|icon_lag", names(master_data))]
summary(master_data2)

class(master_data2$hour)

### Save the dataframe ###
saveRDS(master_data2, file = "final_master_data_cleaned.rds")

