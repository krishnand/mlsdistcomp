# MLSDistComp - Distributed computing with `DistComp` on the Azure Platform

Distcomp is a cloud-based distributed computing platform for clinics, community practices, and research hospitals that benefit from pooling data to create statistical models from large datasets,
but are restricted by privacy concerns from revealing their data. It offers an alternative by creating a "virtual" data registry for clinical data modeling that does not require sharing patient data, but uses a distributed inference algorithm that just shares statistics to create pooled statistical models equivalent to the model possible from the entire dataset.
The cloud version wraps the original **[distcomp](https://cran.r-project.org/web/packages/distcomp/index.html)** version in R, from which  scenarios scenarios and architecture were derived.

This document describes how to setup a distributed network among sites on Azure. You can set up a distributed network by running the scripts in this repository at each site. 

## Architecture

A distributed network forms a star consisting of one _central_ site that communicates with each _remote_ site.  To create the distributed network each site installs a _solution_ made up of a collection of Azure resources under their Azure subscription. We assume each site has it's own subscription, and runs
in it's own tenant. The full set of Azure resources is visualized here

<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

Each solution consists of a data-base maintaining the site's persistent state, web-services written in _R_ to manage the state and run the distributed computation, a web server front-end for the pages of the user interface, and some other assorted cloud resources.  Each site installs the same _solution_, configured with different pages for central and remote sites.  Authentication
for web-services at each site is maintained by secrets shared between the central site and each remote site. Each site's web-service communicates only with other site's web-services.

[This video talk](https://vimeo.com/244731393) explains the architecture in more detail.

## Security

Access between central and remote and sites builds on Active Directory OAuth-style distributed authentication so that each site runs under
local control, as a separate tenant. This installation process generates the secrets that you will need to share manually as part of the process to allow 
access between each remote participant site and the central site.

In addition to confidentiality by authenticated services, and privacy from not sharing data, we believe that security vulnerabilities can be minimized with current technology, specifically with the security features available with Microsoft’s Azure Cloud.  This implementation in Azure has full transparency to allow local sites concerned with privacy protections to validate the safety of the method.  

## Getting Started

First you'll need to go to your [Azure Portal webpage ](http://portal.azure.com) to manually set 
up authentication identities that will be used to connect sites. Then you will copy them into the template that creates the solution resources spawned by running the "Deploy to Azure" buttons below. 

**[Azure Active Directory](https://azure.microsoft.com/en-us/services/active-directory/)** is an Azure service that is used to secure identities on cloud and in hybrid environments. To operationalize `mlsdistcomp` at a site, a pair of Azure Active Directory (AAD) applications are required. An _AAD application_ refers to an entry in the Active Directory of which there are a  _client AAD application_ and a _resource AAD application_ at each site. 

### 1. Create Active Directory authentications

Follow the instructions in **[this document](docs/README_AAD.md)** to provision the AAD applications and create the application IDs and secrets required. This is a necessary step before you run the scripts on this site. **Note**: These "applications" do not become part of the resource group for the solution. 

### 2. Create the Solution's Azure Resources

To start the installation, click the `Deploy to Azure` option below. Follow the instructions on the template deployment screen it brings you to in the Azure Portal to start your deployment.

* To provision the `Central Registry` in a network click

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeploycentral.json" target="_blank">
    <img src="https://github.com/krishnand/mlsdistcomp/blob/master/images/deploycentral.svg" />
</a>

* Or click to provision participant sites: `Deploy Participant to Azure`  

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkrishnand%2Fmlsdistcomp%2Fmaster%2Fazuredeployparticipant.json" target="_blank">
    <img src="https://github.com/krishnand/mlsdistcomp/blob/master/images/deployparticipant.svg" />
</a>

On the template screen:

1. Check the subscription that is defaulted is the one you want to use. 

2. If creating a central site, enter the same App ID you generated above for both "AAD App local resource" and "AAD app central resource."  If you are setting up a remote site, you will need the AAD central app ID for the "AAD app central resource."

3. For either central or remote sites, the client app ID and secret are the one you generated for that site.  The secret is the client app secret. 

4. There's a default password given for the (mls Admin) system account on the linux VM where the mls server runs. You should change this.  Similarly set a secure SQL password. 

5. Central Registry Tenant ID & API Endpoint. This is only needed for participant sites. 

6. Set your tenant name that you used for the AAS config. 

7. Once you purchase the azure solution at the bottom of the template page, the solution will be created.  This takes a few minutes. Go to the website url  for the appservice. 
It will have a name like 

**Note**: You can monitor the progress of your deployment on the Azure portal. Notifications about the deployment will inform you if the deployment was successful or not. Once deployment completes, click on the notification message and go to the resource group to view and inspect all provisioned resources. The web application is the resource of type `App Service` in your resource group. Click to view this resource and copy the `URL` property value; this is the `MLSDistComp` web application endpoint for your site.
 
