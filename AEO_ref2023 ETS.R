###############################################################
#### EIA Annual Energy Outlook - Grid Emission Forecasting ####
###############################################################

#### 1. Notes ####
# Source, AEO Scenarios: https://www.eia.gov/outlooks/aeo/tables_ref.php
# Source, EMM Regions: https://www.eia.gov/outlooks/aeo/pdf/nerc_map.pdf


# 2. Load Libraries ####
library(forecast)
library(tidyverse)
library(readxl)
library(lubridate)


# 3. Define Parameters ####

# Required Id Columns
Param_List <- c(
  "la_RenewableSour", "la_TotalGenerati",
  "ta_TotalCarbon(m", "ta_CarbonDioxide"
)

# Regions + Ids + State level data
Region_Id <- read_excel("Data/AEO Ref Tables.xlsx", sheet = "EMM Regions")
States_CBECS <- read_excel("Data/AEO Ref Tables.xlsx", sheet = "States")


# 4. Load and clean up files ####
AEO_ref2023 <- read_excel("Data/sup_elec.xlsx",
                          skip = 102) %>%
  drop_na(1) %>%
  separate(1, into = c("Region_Id", "Param_Id"), sep = ":") %>%
  filter(Param_Id %in% Param_List) %>%
  rename(Param = `Electricity Supply and Demand`, `2050` = `2050...31`) %>%
  left_join(Region_Id, by = "Region_Id") %>%
  select(Region_Id, Region, Param_Id, Param, everything(), -`2022`, -`2050...32`)


# 5. Grid projection calc function, ETS version ####
get_gridEF_ets <- function(region) {
  
  # Filter to desired region and transpose data frame
  gridEF <- AEO_ref2023 %>%
    filter(Region_Id == region) %>%
    select(-Region_Id, -Region, -Param_Id, -ISO_Group) %>%
    t() %>%
    as.data.frame() %>% 
    rownames_to_column(var = "Year") 
  
  colnames(gridEF) <- gridEF[1, ]
  
  gridEF <- gridEF %>%
    slice(-1) %>%
    mutate_at(2:5, as.numeric)
  
  # Calculate share of renewable energy and grid emissions (lb/MWh)
  gridEF <- gridEF %>%
    mutate(
      Year = ymd(Param, truncated = 2L),
      Renewable_Share = `Renewable Sources 14/`/`Total Generation`,
      Grid_lb_MWh = round((`Carbon Dioxide (million short tons)`*2000*1e+06)/(`Total Generation`*1e+09/1000), digits = 2)) %>%
    select(Year, Grid_lb_MWh, Renewable_Share) 
  
  
  # Forecasting with limits 
  # Source: https://robjhyndman.com/hyndsight/forecasting-within-limits/
  ts_df <- ts(gridEF)[,"Grid_lb_MWh"]
  
  ets_fit <- ets(ts_df, lambda = 0)
  ets_fcst <- forecast(ets_fit, h = 35) 
  ets_fcst_adj <- cbind.data.frame(
    "ets_mean" = as.vector(ets_fcst$mean),
    "ets_lower80" = as.vector(ets_fcst$lower[,1])) %>%
    mutate(ets_adj = (ets_mean+ets_lower80)/2)
  
  gridEF <- gridEF %>%
    rbind.data.frame(
      cbind.data.frame(
        Year = ymd(2051:2085, truncated = 2L),
        # A few options based on how conservative we want to be
        # ETS mean, lower 80% CI, or the average of the two... going with average for now
        Grid_lb_MWh = ets_fcst_adj$ets_adj, 
        Renewable_Share = rep(NA, 35))) %>%
    mutate(Region_Id = region) 
  
}


# 6. Combine all regions #### 
AEOref23_Extrap <- map(
  .x = Region_Id$Region_Id,
  .f = get_gridEF_ets) %>%
  bind_rows() %>%
  left_join(Region_Id, by = "Region_Id")


# 7. Write the table to a csv file
write.csv(AEOref23_Extrap, file = "Data/AEOref23_Extrap.csv", row.names = FALSE)


# Optional: Visualize the result by ISO Group
AEOref23_Extrap %>%
  filter(ISO_Group != "USA") %>%
  ggplot(aes(x = Year, y = Grid_lb_MWh, group = Region_Id, color = ISO_Group)) +
  geom_path() +
  geom_vline(xintercept = as.Date("2050-01-01"), linetype = "dashed") +
  facet_wrap(~ISO_Group, ncol = 2) +
  labs(title = "AEO Reference Pathways + ETS Extrapolation",
       subtitle = "[Using adjusted value, average of mean and lower 80% CI]",
       x = "", y = "Grid Emission Factor [lb/MWh]",
       color = "ISO/NERC Group")

