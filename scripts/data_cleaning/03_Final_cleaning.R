rm(list=ls())
setwd("~/Desktop/grad_school/222_project/222_project/raw merged data")
library(dplyr)
library(lubridate)
### upload data sets ###

################### Traffic Volume Censor Data ###################
pems_rough <- read.csv("pems_rough.csv")

### drop the first column of Pems ###
pems_rough <- pems_rough %>% select(c(
  V1, V2, V5, V10, V11, V12))

### relabel all of the columns ###
colnames(pems_rough) <- c("Timestamp", "Station", "Direction", "Total.Flow", "AVG.Occupancy", "AVG.Speed")

### save the time stamp as a time and drop the minute and second observations ###
pems_rough$Timestamp <- floor_date(as.POSIXct(pems_rough$Timestamp, 
                                              format = "%m/%d/%Y %H:%M:%S"), 
                                   unit = "hour")

### save station and direction as categorical variables ###
pems_rough$Station <- as.factor(pems_rough$Station)
pems_rough$Direction <- as.factor(pems_rough$Direction)

library(readr)

### split each station into a separate csv ###
station_folder <- "~/Desktop/grad_school/222_project/222_project/station_data"
dir.create(station_folder, recursive = TRUE, showWarnings = FALSE)

pems_rough %>%
  group_by(Station) %>%
  group_walk(~ write_csv(.x, file.path(station_folder, paste0("station_", .y$Station, ".csv"))))

### upload the individual csv and bind them by columns ###

library(dplyr)
library(tidyr)
library(readr)

### Load and combine all station CSVs by columns ###

files <- list.files("~/Desktop/grad_school/222_project/222_project/station_data", pattern = "*.csv", full.names = TRUE)

pems_wide <- files %>%
  lapply(function(f) {
    station_id <- gsub("station_|\\.csv", "", basename(f))
    read_csv(f) %>% mutate(Station = station_id)
  }) %>%
  bind_rows() %>%
  pivot_wider(
    id_cols = Timestamp,
    names_from = Station,
    values_from = c(Total.Flow, AVG.Occupancy, AVG.Speed),
    names_glue = "{Station}_{.value}"
  )


##### Switch it to pacific time #####

library(lubridate)

pems_wide$Timestamp <- with_tz(pems_wide$Timestamp, tzone = "America/Los_Angeles")

pems_wide <- pems_wide %>%
  filter(Timestamp <= as.POSIXct("2025-09-30 23:00:00", tz = "America/Los_Angeles"))



## Check for any gaps in the hourly sequence ###
time_diffs <- diff(pems_wide$Timestamp)
table(time_diffs)
pems_wide$Timestamp[which(time_diffs != 1)]

missing_hours <- tibble(
  Timestamp = as.POSIXct(c(
    "2014-05-27 16:00:00",
    "2015-02-28 10:00:00",
    "2019-12-31 13:00:00",
    "2023-08-31 23:00:00"
  ), tz = "America/Los_Angeles")
)

##
pems_wide <- bind_rows(pems_wide, missing_hours) %>%
  arrange(Timestamp)

pems_wide <- pems_wide %>% distinct(Timestamp, .keep_all = TRUE)

time_diffs <- diff(pems_wide$Timestamp)
pems_wide$Timestamp[which(time_diffs > 7200)]


full_hours <- tibble(
  Timestamp = seq(
    from = as.POSIXct("2014-01-01 00:00:00", tz = "America/Los_Angeles"),
    to   = as.POSIXct("2025-09-30 23:00:00", tz = "America/Los_Angeles"),
    by   = "hour"
  )
)

pems_wide <- full_hours %>%
  left_join(pems_wide, by = "Timestamp")

nrow(pems_wide)


### save the data as a final merged data set ###
pems_final <- pems_wide

### delete the rough data sets from the environment ###
rm(full_hours, missing_hours, pems_rough, pems_wide, rpems_rough)

################### Weather Data ###################
weather_sc <- read.csv("weather_sc.csv")
weather_scl <- read.csv("weather_scl.csv")
weather_summit <- read.csv("weather_summit.csv")

### check to see if there are any full rows of NAs
colSums(is.na(weather_sc)) == nrow(weather_sc)
colSums(is.na(weather_scl)) == nrow(weather_scl)
colSums(is.na(weather_summit)) == nrow(weather_summit)


#### sc variable cleaning ###
weather_sc$sc_preciptype <- as.factor(weather_sc$sc_preciptype)
weather_sc$sc_conditions <- as.factor(weather_sc$sc_conditions)
weather_sc$sc_icon <- as.factor(weather_sc$sc_icon)
weather_sc <- weather_sc %>% select(-sc_name, -sc_snowdepth, -X)
summary(weather_sc)

### reformat the date and time ###
weather_sc <- weather_sc %>%
  mutate(datetime = as.POSIXct(datetime, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Los_Angeles"))
weather_sc <- weather_sc %>% rename(Timestamp = datetime)


#### scl variable cleaning ###
weather_scl$scl_preciptype <- as.factor(weather_scl$scl_preciptype)
weather_scl$scl_conditions <- as.factor(weather_scl$scl_conditions)
weather_scl$scl_icon <- as.factor(weather_scl$scl_icon)
weather_scl <- weather_scl %>% select(-scl_name, -scl_snowdepth, -X)
summary(weather_scl)

### reformat the time variable ###
weather_scl <- weather_scl %>%
  mutate(datetime = as.POSIXct(datetime, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Los_Angeles"))
weather_scl <- weather_scl %>% rename(Timestamp = datetime)


#### summit variable cleaning ###
weather_summit$sum_preciptype <- as.factor(weather_summit$sum_preciptype)
weather_summit$sum_conditions <- as.factor(weather_summit$sum_conditions)
weather_summit$sum_icon <- as.factor(weather_summit$sum_icon)
summary(weather_summit)

weather_summit <- weather_summit %>% select(-sum_source, -sum_name, -sum_latitude, -sum_longitude, -X)

### reformat the time variable ###
weather_summit<- weather_summit %>%
  mutate(datetime = as.POSIXct(datetime, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Los_Angeles"))
weather_summit <- weather_summit %>% rename(Timestamp = datetime)

##### Add code to work around daylight savings time ####
# REPLACED: dedup now runs AFTER force_tz for all three datasets
weather_sc$Timestamp     <- force_tz(weather_sc$Timestamp,     tzone = "America/Los_Angeles")
weather_summit$Timestamp <- force_tz(weather_summit$Timestamp, tzone = "America/Los_Angeles")
weather_scl$Timestamp    <- force_tz(weather_scl$Timestamp,    tzone = "America/Los_Angeles")

#weather_sc <- weather_sc %>%
  ##group_by(Timestamp) %>% slice(1) %>% ungroup()

#weather_summit <- weather_summit %>%
  #group_by(Timestamp) %>% slice(1) %>% ungroup()

#weather_scl <- weather_scl %>%
  #group_by(Timestamp) %>% slice(1) %>% ungroup()

# Verify no duplicates survive before joining
#stopifnot(nrow(weather_sc)     == n_distinct(weather_sc$Timestamp))
#stopifnot(nrow(weather_summit) == n_distinct(weather_summit$Timestamp))
#stopifnot(nrow(weather_scl)    == n_distinct(weather_scl$Timestamp))

### create a full hours variable to join the weather on ####
#full_hours <- tibble(
  #Timestamp = seq(
    #from = as.POSIXct("2014-01-01 00:00:00", tz = "America/Los_Angeles"),
    #to   = as.POSIXct("2025-09-30 23:00:00", tz = "America/Los_Angeles"),
   # by   = "hour"
 # )
)
### combine all the individual spreadsheets ###
#weather_final <- full_hours %>%
  #left_join(weather_sc, by = "Timestamp") %>%
  #left_join(weather_summit, by = "Timestamp") %>%
  #left_join(weather_scl, by = "Timestamp")

#colSums(is.na(weather_final))

#nrow(weather_final)
#n_distinct(weather_final$Timestamp)


# Recheck
#time_diffs <- diff(weather_final$Timestamp)
#table(time_diffs)

#weather_final[!complete.cases(weather_final), "Timestamp"]

#head(weather_sc$Timestamp)
#head(weather_summit$Timestamp)
#head(weather_scl$Timestamp)

################### Accident Data ###################
accident_rough <- read.csv("hw17_accident_merge.csv")
View(accident_rough)

library(dplyr)
library(lubridate)

accidents <- accident_rough %>%
  mutate(
    hour_part   = COLLISION_TIME %/% 100,
    minute_part = COLLISION_TIME %% 100,
    COLLISION_DATE = as.Date(COLLISION_DATE, format = "%Y-%m-%d"),
    dt_raw = as.POSIXct(
      paste(COLLISION_DATE, sprintf("%02d:%02d:00", hour_part, minute_part)),
      tz = "America/Los_Angeles"
    ),
    Timestamp = round_date(dt_raw, unit = "hour")
  ) %>%
  select(-hour_part, -minute_part, -dt_raw)

# REPLACED: bare left_join with hourly aggregation first — fixes inflated row count
accidents_hourly <- accidents %>%
  group_by(Timestamp) %>%
  summarise(
    accident_count = n(),
    .groups = "drop"
  )

accidents <- full_hours %>%
  left_join(accidents_hourly, by = "Timestamp") %>%
  mutate(accident_count = replace_na(accident_count, 0))

n_distinct(accidents$Timestamp)

################### Aggregate Everything ###################
master_data <- accidents %>%
  left_join(pems_final, by = "Timestamp") %>%
  left_join(weather_sc, by = "Timestamp")%>%
  left_join(weather_scl, by = "Timestamp") %>%
  left_join(weather_summit by ="Timestampl")


master_data <- master_data %>%
  filter(!if_all(-Timestamp, is.na))

# Should be 102,983 before and 102,972 after
nrow(master_data)

# Confirm no fully-empty rows remain
master_data %>%
  filter(if_all(-Timestamp, is.na)) %>%
  nrow()

