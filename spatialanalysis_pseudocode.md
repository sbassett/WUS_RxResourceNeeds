
## Other Questions
Which firesheds experience burn days at the same time? (and compete for Rx resources)
    Rivalry or Competition Between Firesheds or SubFiresheds can be resolved through prioritization including a scarcity of burn days metric. [is this burn day synchrony?]
How predicable are burn day patterns in each fireshed? Maybe probability of burn days in each week of the year? (like exceedance probability of 1,2,3,4,5,6 burn days)

Compare to known fire events (wildcad etc.) are burns happening during predicted (based on observed data) burn windows?


Burn windows (for a place) are rival or non-rival through space and time. Time is the biggest determination of if we need more people or not. If burn windows are not synced up then we need fewer people. If burn windows happen only once every 5 years (in a given fireshed) then that changes how many acres need to burn in that "good fire" year.

"Burn window synchrony between firesheds/project areas will be something we need to track in our analysis. If all our burn windows happen at the same time in NM then we need more people than if our burn windows roll sequentially from south to north (or in other sequential manner). There's also the inter-annual variability that we probably need to track, and plan to have sufficient personnel on-hand for good years, but also balance so we don't have people/engines standing around that we don't need in too many years."


## Data Sources
Burn Days (Swain et al 2023)
Daily GridMET https://www.climatologylab.org/gridmet.html


## Burn Day Model

##### START WORKING HERE on the BURN DAYS
### Burn Day Thresholds 
Following Swain et al 2023, create a burn window definition with high and low bounds for 
    mid-flame wind speed
    relative humidity
    air temperature

    
### Burn Day Classification For Each GridMet Pixel
Following Swain et al 2023, use daily gridmet data, augmented with more fuels metrics calculated following "Cohen, J. D. & Deeming, J. E. The national fire-danger rating system: basic equations. (U.S. Department of Agriculture, Forest Service, Pacific Southwest Forest and Range Experiment Station, 1985)." Maybe do bias correction too following Swain which cites Barros et al 2021.

Classify every pixel for every day as in or out of prescription.



# Fireshed project level resource needs by week/bi-week/month/season/year [see what's feasible for timescale]
    Function of:
        Burn Day Target (assume all resources and acres are interchanble)
            Annual Rx Target / Burn days
                Annual RX target is MFRI/acres of need [or priority acres]
                Burn days from Swain et al (2023?)
        Resource intensity for the fireshed-project units
            Chains Per Hour of Line Production Needed
                Expected Fire Behavior in Project Area under X percentile conditions
                    Fuel Model(s), Weather, Terrain
            Resource Mix [accross three phases? firing, holding, contingency]
                Unit Complexity [function of(terrain, unit homogeneity, adjacent fuels, values at risk)]
                Firing Type [function of annual burn area and or unit size]


## Burn Unit Size and Complexity Model
Model unit complexity distribution  (modeled at the fireshed project level, from sub-fireshed-project-level patches)
        Unit Complexity [function of(terrain, unit homogeneity, adjacent fuels, values at risk)]


Pull out contiguous patches (combinations of landowner, flame length bin under prescription conditions, WUI-context, treatable flag (not burned = dense development, non-forested, non-dry forest {spruce-fir, wetlands, PJ, etc.}))

For each patch, extract the:
 - expected fire rate of spread (under braketing scenarios, one on the hot side of teh prescription and on eon teh cool side of teh prescription).
 - slope (greater slope = grater complexity, might not need since slope is baked into the rate of spread)
 - try looking at homogeneity of aspects? (like neighborhood dissimilary of terrain)
 - distance to road (greater distance = greater complexity)
 - fuel-type homogeneity (like neighborhood dissimilary of fuels)
 - wui map (see Community Wildfire Risk Reduction Zones in https://wildfirerisk.org/download/)

[maybe for adjacent fuels, use overall fireshed project area summary of area that will burn at too hot intensities under prescriptin conditions, so burnign in a dense fireshed project area is risker than burning in a less dense  project area]



From the spatial complexity map (, low, medium, high complexity), summarize the total acres of each complexity class by [landowner (coarse bins like federal/non-fed), and expected fire behavior in chains per hour (ok to bin )]




For each fireshed, model the distribution of burn unit sizes.
For non-wui the maximum size is 2,000 acres and the minimum is 441 acres (based on USFS burn plan reporting, Jason found it.) In WUI (and maybe other higher-complexity areas), the maximum fire size is 441 acres.


Heavy fuels make units smaller.
Absence of fuels make unit smaller.
Hazards like powerlines, structures.

Water availability might make units or acres per day smaller.
Introducing mosaics through seasonality and rotation in burn blocks (treating burn blocks in phases, or burned and unburned).

Output should be in bins: 50-100, 101-200, 201-400, 401-800, 801-1200,1201-1600, 1601-2000.

Also should be binned by unit complexity, low, medium, high. 

## Firing method model
                Firing Type [function of annual burn area and or unit size]
    Output: Create a table with same matrix of burn unit size by burn unit complexity, and specify which fire size/compleity classes are ignited by hand, drone, or helicopter.

        burns over 1000 acres benefit from heli ignitions, and the time required is halved
    
        Drones increase opportunity for aerial ignitions.

        Wouldn't use drones where fuels are high.
        Resources are a limiting factor, when they can they use the drones.



## Chains Per Hour of Line Production Needed
                Expected Fire Behavior in Project Area under X percentile conditions
                    Fuel Model(s), Weather, Terrain
            Resource Mix [accross three phases? firing, holding, contingency]


## Resources Required SUmmarized at the State Level [NM as pilot]
# THis takes fireshed-project-level summaries and aggregates to
    # quals/people needed capacity/resource that can be activated, readiness
    # engines/equipment needed
    # average need during peak burning season [eventually look at resources needed per week through the year so resource competition can be accounted for across the western US, to allow ]
        ## how to account for seasonality?
        ## evntually replicate the regional model with the same seaonl/weekly/biweekly estimates to allow them to be summed for total non-competing resource needs 