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

**[Azure Active Directory](https://azure.microsoft.com/en-us/services/active-directory/)** is an Azure service that is used to secure identities, applications on cloud and in hybrid environments. To operationalize `mlsdistcomp` at a site, 2 Azure Active Directory applications are required. 
One that is the identity of the ML Server and the other a *client* AAD application in the same tenant that has
permissions to access the ML Server AAD application. The following steps describe how you can provision these:

* Browse to the **[Azure portal](https://ms.porta.azure.com)** and launch the Cloud Shell (_look for bash prompt icon on the portal toolbar_)
* Execute this command to create the AAD Application for the ML Server: 
```bash
az ad app create --display-name mlsdistcompcentral --homepage "http://localhost:12800" --identifier-uris "http://contoso.onmicrosoft.com/mlsdistcompcentral" --reply-urls "http://localhost:12800"
```





## Configuring Azure Resources for the MLSDistComp network


To operationalize the network (One-Box Configuration) (Linux Ubuntu Data Science VM) simple click the Deploy option below.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>


