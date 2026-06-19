rm(list=ls())
### install packages and upload libraries ###
library(readxl)
library(dplyr)
library(lubridate)
library(readr)


########## Upload and View Data ##########

setwd("~/Desktop/grad_school/222_project/222_project/rough_accident_data")

sc_accident_data <- read_excel("Santa_Cruz_1_1_14_to_9_30_25.xlsx")
summary(sc_accident_data)

scl_accident_data <- read_excel("Santa_Clara_1_1_14_to_9_30_25.xlsx")
summary(scl_accident_data)

########## clean individual data sets ###########


### drop all variables that are irrelevant ###
sc_crash <- sc_accident_data %>%
  select(-ACCIDENT_YEAR, -PROC_DATE, -JURIS, -OFFICER_ID, -REPORTING_DISTRICT, -CHP_SHIFT,
         -POPULATION, -CNTY_CITY_LOC, -SPECIAL_COND, -BEAT_TYPE, -CHP_BEAT_TYPE,
         -CITY_DIVISION_LAPD, -CHP_BEAT_CLASS, -BEAT_NUMBER, -PRIMARY_RD, -STATE_HWY_IND,
         -CALTRANS_COUNTY, -CALTRANS_DISTRICT, - STATE_ROUTE, -PCF_CODE_OF_VIOL, -PCF_VIOL_CATEGORY,
         -PCF_VIOLATION, -PCF_VIOL_SUBSECTION, -MVIW, -PED_ACTION, -COUNTY, -NOT_PRIVATE_PROPERTY,
         - STWD_VEHTYPE_AT_FAULT, -BICYCLE_ACCIDENT, -PEDESTRIAN_ACCIDENT, -POSTMILE_PREFIX, -CHP_ROAD_TYPE,
         -ROUTE_SUFFIX, -STWD_VEHTYPE_AT_FAULT, -COUNT_BICYCLIST_KILLED, -DISTANCE, -POINT_X, -POINT_Y,
         -CITY, -PRIMARY_RAMP, -SECONDARY_RAMP)

### generate a county variable and assign everyone into the data set into SCL
sc_crash$county <- "SC"

### check if it works ###
summary(sc_crash)

### Drop all variable that are irrelevant ###
scl_crash <- scl_accident_data %>%
  select(-ACCIDENT_YEAR, -PROC_DATE, -JURIS, -OFFICER_ID, -REPORTING_DISTRICT, -CHP_SHIFT,
         -POPULATION, -CNTY_CITY_LOC, -SPECIAL_COND, -BEAT_TYPE, -CHP_BEAT_TYPE,
         -CITY_DIVISION_LAPD, -CHP_BEAT_CLASS, -BEAT_NUMBER, -PRIMARY_RD, -STATE_HWY_IND,
         -CALTRANS_COUNTY, -CALTRANS_DISTRICT, - STATE_ROUTE, -PCF_CODE_OF_VIOL, -PCF_VIOL_CATEGORY,
         -PCF_VIOLATION, -PCF_VIOL_SUBSECTION, -MVIW, -PED_ACTION,-COUNTY, -NOT_PRIVATE_PROPERTY,
         -STWD_VEHTYPE_AT_FAULT, -BICYCLE_ACCIDENT, -PEDESTRIAN_ACCIDENT, -POSTMILE_PREFIX,
         -ROUTE_SUFFIX, -CHP_ROAD_TYPE, -STWD_VEHTYPE_AT_FAULT, -COUNT_BICYCLIST_KILLED, -DISTANCE,
         -POINT_X, -POINT_Y, -CITY, -PRIMARY_RAMP, -SECONDARY_RAMP)

### generate a county variable and assign everyone into the data set into SCL
scl_crash$county <- "SCL"

### check if it works ###
summary(sc_crash)

### merge data sets ###
hw17_crash_rough <- bind_rows(sc_crash, scl_crash)

summary(hw17_crash_rough)

sum(is.na(hw17_crash_rough))

### Thinking about refining the highway 17 mile marker to only include from Lark Avenue to the fish hook.
### I am going to add it here, I think it would be logical to refine Highway 17 for accidents but
### I am not sure how relevant it would be for traffic data, because traffic for commuters in SCL before Lark
### Avenue definitely matters for predicting traffic patterns.

### View the descriptive Statistics ###
summary(hw17_crash_rough)
### see if any of the Case ID numbers are duplicated ###
sum(duplicated(hw17_crash_rough))
### now that it worked drop case id
hw17_crash_rough$CASE_ID <- NULL
### see the descriptive statistics for post-mile in Santa Clara County to see if it worked ###
summary(hw17_crash_rough$POSTMILE[hw17_crash_rough$county == "SCL"])
### count the NA's in the total data frame
sum(is.na(hw17_crash_rough))

########## Save Categorical Variables as Factors #########
summary(hw17_crash_rough)

### as numeric ###
hw17_crash_rough$LATITUDE <- as.numeric(hw17_crash_rough$LATITUDE)
hw17_crash_rough$LONGITUDE <- as.numeric(hw17_crash_rough$LONGITUDE)


### as factors ###### as factors ###hw17_crash_rough
hw17_crash_rough$county <- as.factor(hw17_crash_rough$county)
hw17_crash_rough$CHP_VEHTYPE_AT_FAULT <- as.factor(hw17_crash_rough$CHP_VEHTYPE_AT_FAULT)
hw17_crash_rough$ALCOHOL_INVOLVED <- as.factor(hw17_crash_rough$ALCOHOL_INVOLVED)
hw17_crash_rough$TRUCK_ACCIDENT <- as.factor(hw17_crash_rough$TRUCK_ACCIDENT)
hw17_crash_rough$MOTORCYCLE_ACCIDENT <- as.factor(hw17_crash_rough$MOTORCYCLE_ACCIDENT)
hw17_crash_rough$LIGHTING <- as.factor(hw17_crash_rough$LIGHTING)
hw17_crash_rough$ROAD_COND_1 <- as.factor(hw17_crash_rough$ROAD_COND_1)
hw17_crash_rough$ROAD_COND_2 <- as.factor(hw17_crash_rough$ROAD_COND_2)
hw17_crash_rough$ROAD_SURFACE <- as.factor(hw17_crash_rough$ROAD_SURFACE)
hw17_crash_rough$TYPE_OF_COLLISION <- as.factor(hw17_crash_rough$TYPE_OF_COLLISION)
hw17_crash_rough$HIT_AND_RUN <- as.factor(hw17_crash_rough$HIT_AND_RUN)
hw17_crash_rough$PRIMARY_COLL_FACTOR <- as.factor(hw17_crash_rough$PRIMARY_COLL_FACTOR)
hw17_crash_rough$TOW_AWAY <- as.factor(hw17_crash_rough$TOW_AWAY)
hw17_crash_rough$SIDE_OF_HWY <- as.factor(hw17_crash_rough$SIDE_OF_HWY)
hw17_crash_rough$RAMP_INTERSECTION <- as.factor(hw17_crash_rough$RAMP_INTERSECTION)
hw17_crash_rough$LOCATION_TYPE <- as.factor(hw17_crash_rough$LOCATION_TYPE)
hw17_crash_rough$INTERSECTION <- as.factor(hw17_crash_rough$INTERSECTION)
hw17_crash_rough$DIRECTION <- as.factor(hw17_crash_rough$DIRECTION)
hw17_crash_rough$SECONDARY_RD <- as.factor(hw17_crash_rough$SECONDARY_RD)
hw17_crash_rough$DAY_OF_WEEK <- as.factor(hw17_crash_rough$DAY_OF_WEEK)
hw17_crash_rough$CONTROL_DEVICE <- as.factor(hw17_crash_rough$CONTROL_DEVICE)


#### dates ####

hw17_crash_rough$COLLISION_DATE <- as.POSIXct(hw17_crash_rough$COLLISION_DATE)




## numeric variables I am saving as factors because I do not want to have them expressed as linear relationships
## in my analysis
hw17_crash_rough$POSTMILE <- as.factor(hw17_crash_rough$POSTMILE)
hw17_crash_rough$COLLISION_SEVERITY <- as.factor(hw17_crash_rough$COLLISION_SEVERITY)
hw17_crash_rough$PARTY_COUNT <- as.factor(hw17_crash_rough$PARTY_COUNT)


### save the CSV ####
write.csv(hw17_crash_rough, "hw17_accident_merge.csv")

getwd()
View(hw17_crash_rough)

### check to see if it worked ##
summary(hw17_crash_rough)

sum(is.na(hw17_crash_rough))

summary(hw17_crash_rough$county)

rm(sc_accident_data, sc_crash, sc_data, scl_accident_data, scl_crash )


library(dplyr)
library(lubridate)

accidents <- accidents %>%
  # Step 1: Parse time and round to nearest hour
  mutate(
    # Extract hours and minutes from HHMM integer
    hour_part   = COLLISION_TIME %/% 100,
    minute_part = COLLISION_TIME %% 100,
    # Round up if >= 30 minutes, down if < 30
    hour_rounded = ifelse(minute_part >= 30, hour_part + 1, hour_part),
    # Handle midnight rollover (hour 24 -> 0)
    hour_rounded = hour_rounded %% 24,

    # Step 2: Format date and combine with rounded hour into Timestamp
    COLLISION_DATE = as.Date(COLLISION_DATE, format = "%Y-%m-%d"),
    Timestamp = as.POSIXct(
      paste(COLLISION_DATE, sprintf("%02d:00:00", hour_rounded)),
      tz = "America/Los_Angeles"
    )
  ) %>%
  select(-hour_part, -minute_part, -hour_rounded)

# Step 3: Expand to full hourly sequence
accidents_wide <- full_hours %>%
  left_join(accidents, by = "Timestamp")

nrow(accidents_wide)

accidents_wide %>%
  count(Timestamp) %>%
  filter(n > 1) %>%
  arrange(desc(n))

accidents_agg <- accidents %>%
  group_by(Timestamp) %>%
  summarise(accident_count = n(), .groups = "drop")

accidents_wide <- full_hours %>%
  left_join(accidents_agg, by = "Timestamp") %>%
  mutate(accident_count = replace_na(accident_count, 0))

nrow(accidents_wide)


################# Collision Severity Plot #######################
library(ggplot2)

ggplot(hw17_crash_rough, aes(x = factor(COLLISION_SEVERITY,
                                 levels = c(1, 2, 3, 4, 0),
                                 labels = c("Fatal",
                                            "Serious or Severe Injury",
                                            "Minor or Visible Injury",
                                            "Complaint of Pain",
                                            "PDO")))) +
  geom_bar(fill = "steelblue", color = "black") +
  labs(x = "Collision Severity",
       y = "Count",
       title = "Collision Severity Distribution") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))


library(dplyr)
library(ggplot2)

hw17_crash_rough %>%
  filter(COLLISION_DATE >= as.Date("2021-01-01")) %>%
  ggplot(aes(x = factor(COLLISION_SEVERITY,
                        levels = 1:4,
                        labels = c("Fatal",
                                   "Suspected Serious",
                                   "Suspected Minor",
                                   "Complaint of Pain")))) +
  geom_bar(fill = "steelblue", color = "black") +
  labs(x = "Collision Severity",
       y = "Count",
       title = "Highway 17 Collision Severity, 2021-Present",
       caption = "Source: TIMS/SWITRS. PDO crashes excluded per TIMS data convention.") +
  theme_minimal()


library(dplyr)

test_start <- as.Date("2021-01-01")
test_end   <- max(hw17_crash_rough$COLLISION_DATE, na.rm = TRUE)
years_in_period <- as.numeric(difftime(test_end, test_start, units = "days")) / 365.25

kabco_values <- c("1" = 13700000,
                  "2" = 1302300,
                  "3" = 256300,
                  "4" = 122400)

severity_labels <- c("1" = "Fatal (K)",
                     "2" = "Suspected Serious (A)",
                     "3" = "Suspected Minor (B)",
                     "4" = "Complaint of Pain (C)")

test_table <- hw17_crash_rough %>%
  filter(COLLISION_DATE >= test_start, COLLISION_DATE <= test_end) %>%
  count(COLLISION_SEVERITY) %>%
  mutate(
    Severity    = severity_labels[as.character(COLLISION_SEVERITY)],
    Pct         = round(100 * n / sum(n), 1),
    Annual_Rate = round(n / years_in_period, 2),
    Unit_Value  = kabco_values[as.character(COLLISION_SEVERITY)],
    Annual_Cost = round(Annual_Rate * Unit_Value, 0)
  ) %>%
  select(Severity, Count = n, Pct, Annual_Rate, Unit_Value, Annual_Cost) %>%
  arrange(match(Severity, severity_labels))

# Add a totals row
totals <- tibble(
  Severity    = "Total",
  Count       = sum(test_table$Count),
  Pct         = 100,
  Annual_Rate = sum(test_table$Annual_Rate),
  Unit_Value  = NA,
  Annual_Cost = sum(test_table$Annual_Cost)
)

test_table <- bind_rows(test_table, totals)

print(test_table)

cat("\nPeriod:", format(test_start), "to", format(test_end),
    "(", round(years_in_period, 2), "years )\n")
