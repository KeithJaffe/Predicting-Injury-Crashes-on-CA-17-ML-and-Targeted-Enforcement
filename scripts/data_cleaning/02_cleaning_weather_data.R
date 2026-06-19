rm(list=ls())

#### downloading weather data for the summit ####
folder_path <- "~/Desktop/grad_school/222_project/222_project/summit_weather"

# Get a list of all CSV files in the folder
csv_filessum <- list.files(path = folder_path, pattern = "\\.csv$", full.names = TRUE)

# Create an empty list to store each data frame
summit_data <- list()

# Loop through each file and read it in
for (i in seq_along(csv_filessum)) {
  summit_data[[i]] <- read.csv(csv_filessum[i])
}

aggregated_summit_weather <- do.call(rbind, summit_data)

weather_sum <- aggregated_summit_weather %>% 
  rename_with(~paste0("sum_", .), -datetime)

weather_sum$sum_stations <- NULL

summary(weather_sum)

weather_sum$sum_preciptype <- as.factor(weather_sum$sum_preciptype)

#########################################################################################################################
#### downloading weather data for the Santa Cruz side ####

folder_pathsc <- "~/Desktop/grad_school/222_project/222_project/sc_weather"

###  make a list of all csv files in the folder
csv_filessc <- list.files(path = folder_pathsc, pattern = "\\.csv$", full.names = TRUE)

### create an empty list to store each data frame ###
sc_data <- list()

### loop through each file and read it in ###
for (i in seq_along(csv_filessc)) {
  sc_data[[i]] <- read.csv(csv_filessc[i])
}

### combine the data set ###
aggregated_sc_weather <- do.call(rbind, sc_data)

### check the length ###
nrow(aggregated_sc_weather)

### rename every variable to specify SC
weather_sc <- aggregated_sc_weather %>% 
  rename_with(~paste0("sc_", .), -datetime)

## drop the weather stations variables 
weather_sc$sc_stations <- NULL


###############################################################################################################################
#### downloading weather data for the Santa Cruz side ####

folder_pathscl <- "~/Desktop/grad_school/222_project/222_project/scl_weather"

###  make a list of all csv files in the folder ###
csv_filesscl <- list.files(path = folder_pathscl, pattern = "\\.csv$", full.names = TRUE)

### Create an empty list to store each data frame ###
scl_data <- list()

### loop through each file and read it in ###
for (i in seq_along(csv_filesscl)) {
  scl_data[[i]] <- read.csv(csv_filesscl[i])
}

### combine the data set ###
aggregated_scl_weather <- do.call(rbind, scl_data)
### check the length ###
nrow(aggregated_scl_weather)

### rename every variable to specify SC
weather_scl <- aggregated_scl_weather %>% 
  rename_with(~paste0("scl_", .), -datetime)

## drop the weather stations variables 
weather_scl$scl_stations <- NULL
