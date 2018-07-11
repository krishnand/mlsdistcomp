# MLSDistComp - Distributed computing with `DistComp` on the Azure Platform

Distcomp is a cloud-based distributed computing platform mor clinics, community practices, and research hospitals that benefit from pooling data to create statistical models from large datasets,
but are restricted by privacy concerns from revealing their data. It offers an alternative by creating a "virtual" data registry for clinical data modeling that does not require sharing patient data, but uses a distributed inference algorithm that just shares statistics to create pooled statistical models equivalent to the model possible from the entire dataset.
The cloud version wraps the original **[distcomp](https://cran.r-project.org/web/packages/distcomp/index.html)** version in R, from which  scenarios scenarios and architecture were derived

This document describes how to setup a distributed network among sites on Azure. You can set up a distributed network by running the scripts in this repository at each site. 

## Architecture

A distributed network forms a star consisting of one _central_ site that communicates with each _remote_ site.  
To create the distributed network each site installs a _solution_ made up of a collection of Azure resources under their Azure subscription. We assume each site has it's own subscription, and runs
in it's own tenant.

The full set of Azure resources is visualized here:
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

Each solution consists of a data-base maintaining the site's persistent state, web-services written in _R_ to manage the state and run the distributed computation, and a web server front-end for the pages of the user interface, and some other assorted cloud resources.  Each site installs the same _solution_, configured with different pages for central and remote sites.  Authentication
for web-services at each site is maintained by secrets shared between the central site and each remote site. Each site's web-service communicates only with other site's web-services.

[This video talk](https://vimeo.com/244731393) explains the architecture in more detail.

 
## Security

Access between central and remote and sites builds on Active Directory OAuth-style distributed authentication so that each site runs under
local control, as a separate tenant. This installation process generates the secrets that you will need to share manually as part of the process to allow 
access between each remote participant site and the central site.

In addition to confidentiality by authenticated services, and privacy from not sharing data, we believe that security vulnerabilities can be minimized with current technology, specifically with the security features available with Microsoft’s Azure Cloud.   
This implementation in Azure has full transparency to allow local sites concerned with privacy protections to validate the safety of the method.  

## Getting Started: Configure Azure Active Directory applications

**[Azure Active Directory](https://azure.microsoft.com/en-us/services/active-directory/)** is an Azure service that is used to secure identities on cloud and in hybrid environments. To operationalize `mlsdistcomp` at a site, a pair of Azure Active Directory (AAD) applications are required. An _AAD application_ refers to an entry in the Active Directory of which there are a  _client AAD application_ and a _resource AAD application_ at each site.  
Follow the instructions in **[this document](docs/README_AAD.md)** to provision the AAD applications required.
This is a necessary step before you run the scripts on this site. 

## Configure Azure Resources

To start the installation, click the `Deploy to Azure` option below.
Follow the instructions on the template deployment screen it brings you to in the Azure Portal to start your deployment.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>


**NOTE**: You can monitor the progress of your deployment on the Azure portal. Notifications about the deployment will inform whether the deployment
was successful or not. Once deployment completes, click on the notification message and go to the resource group to view and inspect all 
provisioned resources. The web application is the resource of type `App Service` in your resource group. Click to view this resource and copy the
`URL` property value; this is the `MLSDistComp` web application endpoint for your site.
 