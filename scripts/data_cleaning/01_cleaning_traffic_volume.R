rm(list=ls())
library(R.utils)
library(data.table)

setwd("~/Desktop/grad_school/222_project/222_project/raw merged data")
### pull all of the files from a folder ###
pems_files <- list.files("~/Desktop/grad_school/222_project/222_project/Road_Volume",
                         pattern = "*.gz", 
                         full.names = TRUE)

### aggregate files and refine it only to the mainline of highway 17 ###
pems <- rbindlist(lapply(pems_files, function(f) { 
  df <- fread(f, header = FALSE)
  df <- df[V4 == 17 & V6 == "ML"]
  return(df)
}))

unique(pems$V4)

unique(pems$V6)

head(pems, 1)

write.csv(pems, "pems_rough.csv")

write.csv(hw17_crash_rough, "hw17_accident.csv")

write.csv(weather_sc, "weather_sc.csv")

write.csv(weather_scl, "weather_scl.csv")

write.csv(weather_sum, "weather_summit.csv")



getwd()

save.csv

