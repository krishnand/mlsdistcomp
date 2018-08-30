using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Clients.ActiveDirectory;
using Newtonsoft.Json;
using MRSDistCompWebApp.Models;
using System.Text;
using Newtonsoft.Json.Linq;

// For more information on enabling MVC for empty projects, 
// visit http://go.microsoft.com/fwlink/?LinkID=397860

namespace MRSDistCompWebApp.Controllers
{
    [Authorize]
    public class ComputationInfoController : Controller
    {
        // GET: /<controller>/
        public async Task<IActionResult> Index()
        {
            AuthenticationResult result = null;
            List<ComputationInfo> computationProjectsList = new List<ComputationInfo>();

            try
            {
                // Because we signed-in already in the WebApp, the userObjectId is known
                string userObjectID = (User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier"))?.Value;

                // Using ADAL.Net, get a bearer token to access the MRSDistComp Web APIs
                AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.Authority, new NaiveSessionCache(userObjectID, HttpContext.Session));                
                ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.CentralRegistryResourceAppId, credential);                
                
                // Retrieve the participant list.
                HttpClient client = new HttpClient();                
                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.CentralRegistryBaseAddress + "/api/GetComputationProjects");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                request.Content = new StringContent(JsonConvert.SerializeObject(new { projectname = ""}), Encoding.UTF8, "application/json");
                
                HttpResponseMessage response = await client.SendAsync(request);

                // Return the participants' in the view.
                if (response.IsSuccessStatusCode)
                {
                    List<Dictionary<String, String>> responseElements = new List<Dictionary<String, String>>();
                    JsonSerializerSettings settings = new JsonSerializerSettings();
                    String responseString = await response.Content.ReadAsStringAsync();
                    JObject responseJObject = JObject.Parse(responseString);

                    // This is based on the Web API JSON. List of lists of the Result.
                    IList<JToken> rows = responseJObject["outputParameters"]["Result"].Children().ToList();

                    // serialize JSON results into .NET objects            
                    foreach (JToken row in rows)
                    {
                        foreach (JToken column in row)
                        {
                            ComputationInfo computationProject = new ComputationInfo();
                            computationProject.Id = Guid.Parse(column[0].ToString());
                            computationProject.ProjectName = column[1].ToString();
                            computationProject.ProjectDesc = column[2].ToString();
                            computationProject.Formula = column[3].ToString();
                            computationProject.DataCatalog = column[4].ToString();
                            computationProject.ComputationType = column[5].ToString();
                            computationProject.IsEnabled = (Convert.ToInt32(column[6].ToString()) == 1) ? true : false;
                            computationProject.ValidFrom = DateTime.Parse(column[7].ToString());
                            computationProject.ValidTo = DateTime.Parse(column[8].ToString());
                            computationProject.Broadcast = true;
                            computationProjectsList.Add(computationProject);
                        }
                    }

                    return View(computationProjectsList);
                }
                else
                {
                    //
                    // If the call failed with access denied, then drop the current access token from the cache, 
                    //     and show the user an error indicating they might need to sign-in again.
                    //
                    if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
                    {
                        var cachedTokens = authContext.TokenCache.ReadItems().Where(a => a.Resource == AzureAdOptions.Settings.CentralRegistryResourceAppId);
                        foreach (TokenCacheItem tci in cachedTokens)
                            authContext.TokenCache.DeleteItem(tci);

                        ViewBag.ErrorMessage = "UnexpectedError";
                        ComputationInfo newComputationProject = new ComputationInfo();
                        newComputationProject.ProjectName = "(No computation projects exist in the system)";
                        computationProjectsList.Add(newComputationProject);
                        return View(computationProjectsList);
                    }
                }
            }
            catch(Exception ex)
            {
                if (HttpContext.Request.Query["reauth"] == "True")
                {
                    //
                    // Send an OpenID Connect sign-in request to get a new set of tokens.
                    // If the user still has a valid session with Azure AD, they will not be prompted for their credentials.
                    // The OpenID Connect middleware will return to this controller after the sign-in response has been handled.
                    //
                    return new ChallengeResult(OpenIdConnectDefaults.AuthenticationScheme);
                }

                //
                // The user needs to re-authorize.  Show them a message to that effect.
                //
                ComputationInfo newComputationProject = new ComputationInfo();
                newComputationProject.ProjectName = "(Sign-in required to view computation projects.)";
                computationProjectsList.Add(newComputationProject);
                ViewBag.ErrorMessage = "AuthorizationRequired" + ex.Message;
                return View(computationProjectsList);                
            }
            //
            // If the call failed for any other reason, show the user an error.
            //
            return View("Error");
        }

        [HttpPost]
        public async Task<ActionResult> Index(string projectname, 
                                              string projectdesc, 
                                              string schemaname, 
                                              string computationtype, 
                                              string formula,
                                              string submitbutton)
        {
            if (ModelState.IsValid)
            {
                //
                // Retrieve the user's tenantID and access token since 
                // they are parameters used to call the To Do service.
                //
                AuthenticationResult result = null;
                List<ComputationInfo> computationProjectsList = new List<ComputationInfo>();

                try
                {
                    string userObjectID = (User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier"))?.Value;
                    AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.Authority, new NaiveSessionCache(userObjectID, HttpContext.Session));
                    ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                    result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.CentralRegistryResourceAppId, credential);

                    HttpClient client = new HttpClient();
                    HttpContent content = null;
                    HttpRequestMessage request = null;

                    // If "Propose" button is clicked
                    if (submitbutton == "Propose")
                    {
                        // Request content for Project proposal
                        content = new StringContent(JsonConvert.SerializeObject(new
                        {
                            projectname = projectname,
                            projectdesc = projectdesc,
                            schemaname = schemaname,
                            computationtype = computationtype,
                            formula = formula,
                            broadcast = true
                        }), System.Text.Encoding.UTF8, "application/json");                        
                        
                        request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.CentralRegistryBaseAddress + "/api/ProposeComputation");
                        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                        request.Content = content;
                    }
                    // Register computation types in the distcomp package
                    else if(submitbutton == "Register")
                    {
                        // Request content for computation type registration
                        content = new StringContent("{}", Encoding.UTF8, "application/json");
                        request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.CentralRegistryBaseAddress + "/api/RegisterComputations");
                        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                        request.Content = content;
                    }
                    else
                    {
                        // No-op for other actions
                        return RedirectToAction("Index");
                    }
                    HttpResponseMessage response = await client.SendAsync(request);

                    //
                    // Return the To Do List in the view.
                    //
                    if (response.IsSuccessStatusCode)
                    {
                        return RedirectToAction("Index");
                    }
                    else
                    {
                        //
                        // If the call failed with access denied, then drop the current access token from the cache, 
                        //     and show the user an error indicating they might need to sign-in again.
                        //
                        if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
                        {
                            var cachedTokens = authContext.TokenCache.ReadItems().Where(a => a.Resource == AzureAdOptions.Settings.CentralRegistryResourceAppId);
                            foreach (TokenCacheItem tci in cachedTokens)
                                authContext.TokenCache.DeleteItem(tci);

                            //
                            // The user needs to re-authorize.  Show them a message to that effect.
                            //
                            ComputationInfo newComputationProject = new ComputationInfo();
                            newComputationProject.ProjectName = "(Sign-in required to view computation projects.)";
                            computationProjectsList.Add(newComputationProject);
                            ViewBag.ErrorMessage = "UnexpectedError";
                            return View(computationProjectsList);
                        }
                    }
                }
                catch
                {
                    //
                    // The user needs to re-authorize.  Show them a message to that effect.
                    //
                    //
                    // The user needs to re-authorize.  Show them a message to that effect.
                    //
                    ComputationInfo newComputationProject = new ComputationInfo();
                    newComputationProject.ProjectName = "(Sign-in required to view computation projects.)";
                    computationProjectsList.Add(newComputationProject);
                    ViewBag.ErrorMessage = "AuthorizationRequired";
                    return View(computationProjectsList);                    
                }
                //
                // If the call failed for any other reason, show the user an error.
                //
                return View("Error");
            }
            return View("Error");
        }
    }
}
