# MLSDistComp - Distributed computing with `DistComp` on the Azure Platform

Distcomp meets the needs of clinics, community practices, and research hospitals that would benefit from pooling data to create large datasets,
but are restricted by privacy concerns from revealing their data. It offers an alternative by creating a "virtual" data registry
for clinical data modeling that does not require sharing patient data, but uses a distributed inference algorithm that just shares statistics to create pooled statistical models equivalent to the model
possible from the entire dataset.
    The original **[distcomp](https://cran.r-project.org/web/packages/distcomp/index.html)** work in R, discusses all of the scenarios and the underlying research work.
This document below describes how one can setup this network in a very easy manner on Azure.

## Configure Azure Active Directory applications

**[Azure Active Directory](https://azure.microsoft.com/en-us/services/active-directory/)** is an Azure service that is used to secure identities, applications on cloud and in hybrid environments. To operationalize `mlsdistcomp` at a site, 2 Azure Active Directory applications are required. 
Follow the instructions in **[this document](docs/README_AAD.md)** to provision the AAD applications required.
This is a pre-requisite to start your deployment.

## Configure Azure Resources

To operationalize your site with the Linux Ubuntu Data Science VM, click the `Deploy to Azure` option below.
Follow instructions on the template deployment screen in the Azure portal to start your deployment.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

**NOTE**: You can monitor the progress of your deployment on the Azure portal. Notifications about the deployment will inform whether the deployment
was successful or not. Once deployment completes, click on the notification message and go to the resource group to view and inspect all 
provisioned resources. The web application is the resource of type `App Service` in your resource group. Click to view this resource and copy the
`URL` property value; this is the `MLSDistComp` web application endpoint for your site.
 