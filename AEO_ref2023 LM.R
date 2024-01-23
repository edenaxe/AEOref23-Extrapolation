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


# 5. Grid projection calc function ####

get_gridEF <- function(region) {
  
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
      Renewable_Share = `Renewable Sources 14/`/`Total Generation`,
      Grid_lb_MWh = round((`Carbon Dioxide (million short tons)`*2000*1e+06)/(`Total Generation`*1e+09/1000), digits = 2)
    )
  
  
  # Extrapolate out to 2085 to cover the 60 year lifespan of the building
  gridEF <- gridEF %>%
    select("Year" = Param, Grid_lb_MWh, Renewable_Share) %>%
    rbind.data.frame(
      cbind.data.frame(
        Year = 2051:2085,
        Grid_lb_MWh = rep(NA, 35), 
        Renewable_Share = rep(NA, 35))) %>%
    mutate(
      Year = lubridate::ymd(Year, truncated = 2L),
      # Extrapolate the renewable energy percentage, cap at 100%
      Renewable_Share = coalesce(Renewable_Share, predict(lm(Renewable_Share ~ Year), across(Year))),
      Renewable_Share = ifelse(Renewable_Share < 1, Renewable_Share, 1),
      Region_Id = region
    ) 
  
  
  # Create 2 scenarios, 1 if renewable energy reaches 100% and another if it doesn't
  if (max(gridEF$Renewable_Share) >= 1) {
    
    # Find the year/index at which the region reaches 100% renewable energy
    index_NZ <- which(gridEF$Renewable_Share == 1, arr.ind = TRUE)[1]
    
    # Create a sequence going down from the expected 2051 value to 0 by the above year ^
    extrap_seq <- seq(from = gridEF[28, 2], to = 0, length.out = index_NZ-27)[2:(index_NZ-27)]
    
    # Add these extrapolated grid factors to the Grid_lb_MWh column and replace remaining NA with 0
    gridEF$Grid_lb_MWh[29:index_NZ] = extrap_seq
    gridEF[is.na(gridEF)] <- 0
    
  } else if (max(gridEF$Renewable_Share) < 1) {
    
    gridEF <- gridEF %>%
      mutate(
        # Extrapolate the grid emission factor based on year and renewable share, cap at 0
        # Extrapolate but only using 2030+ to predict future grid improvements...
        Grid_lb_MWh = coalesce(Grid_lb_MWh, predict(lm(Grid_lb_MWh ~ Year + Renewable_Share), across(Year))),
        Grid_lb_MWh = ifelse(Grid_lb_MWh > 0, Grid_lb_MWh, 0),
      )
    
  }
  
  return(gridEF)
  
}


# 6. Combine all regions #### 
AEOref23_Extrap <- map(
  .x = Region_Id$Region_Id,
  .f = get_gridEF) %>%
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
  labs(title = "AEO Reference Pathways + LM Extrapolation",
       x = "", y = "Grid Emission Factor [lb/MWh]",
       color = "ISO/NERC Group")