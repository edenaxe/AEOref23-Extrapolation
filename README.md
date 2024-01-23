# AEOref23-Extrapolation

**> Summary**  
Using ETS forecasting to extrapolate EIA's AEO 2023 reference scenarios for grid emissions


**> Process**  
EIA currently provides reference scenarios in their Annual Energy Outlook (AEO) for each electricity market module region. These regions are based on NERC/ISO subregions and the 25 regions can be seen on the map here. Each reference scenario includes pertinent information used for this extrapolated grid projection. One table is the "Generation by Fuel Type in the Electric Power Sector" which can tell us what the percentage of power generated comes from renewable sources. The next table is "Emissions from the Electric Power Sector" which provides total estimated volume of carbon dioxide emissions. 

Both tables include projections out to 2050. However, we need to model lifetime emissions of each project (60 years) which extend from 2023 out to 2083 and beyond. One of the crux issues in confidently modeling emissions in latter half of that timeline, where projections are scarce and uncertainty is high. 

This script includes a couple of main steps that allow us to extrapolate grid emissions for each region out to 2083. They are:
	1. Use both total generation of electricity and total carbon dioxide emissions to find emissions in pounds per MWh
	2. Use existing projection data from 2023 to 2050 for grid emissions and renewable share to generated a forecast. The forecast of choice for this project is exponential smoothing (ETS), where I utilize an average of the mean value and lower 80% confidence interval range. 

  
**> Limitations and Notes**   
- LM vs ETS: A simple linear model is a poor representation of trend for some regions due to non-linear trends in early years. Several regions have steep drop-offs in emissions up to 2030 but then resume a gradual decline out to 2050. For this reason, an ETS forecast was utilized. However, the ETS forecast may not do the best job of representing future innovations or improvements. Hence it is a conservative forecast even using the "adjusted" mean. 
- Historical data: No historical data was found by electricity market module, so the forecast is based on a forecast. This may reduce the overall confidence in the results. 

  
Figure1. A visualization of the final pathways
<img src="AEO ETS Plot.PNG" width="90%" height="90%">
