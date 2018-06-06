# MLSDistComp - Distributed computing with `DistComp` on the Azure Platform

Distcomp meets the needs of clinics, community practices, and research hospitals that would benefit from pooling data to create large datasets,
but are restricted by privacy concerns from revealing their data. It offers an alternative by creating a "virtual" data registry
for clinical data modeling that does not require sharing patient data, but uses a distributed inference algorithm that just shares statistics to create pooled statistical models equivalent to the model
possible from the entire dataset.
    The original **[distcomp](https://cran.r-project.org/web/packages/distcomp/index.html)** work in R, discusses all of the scenarios and the underlying research work.
This document below describes how one can setup this network in a very easy manner on Azure.

# Prerequisites

This operationalization experience sets up all that is required for the `Distcomp` network on Azure.
NOTE: While all resource provisioning is automated, users will have to create two `Azure Active Directory`
application for each site in the network.

## Configure Azure Active Directory Applications


## Configuring Azure Resources for the MLSDistComp network


To operationalize the network (One-Box Configuration) (Linux Ubuntu Data Science VM) simple click the Deploy option below.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>


