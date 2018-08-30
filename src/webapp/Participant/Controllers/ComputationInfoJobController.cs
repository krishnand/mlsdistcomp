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
    public class ComputationInfoJobController : Controller
    {
        // GET: /<controller>/
        public async Task<IActionResult> Index(string projectname = null)
        {
            AuthenticationResult result = null;
            List<ComputationInfoJob> computationJobsList = new List<ComputationInfoJob>();

            try
            {
                // Because we signed-in already in the WebApp, the userObjectId is known
                string userObjectID = (User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier"))?.Value;

                // Using ADAL.Net, get a bearer token to access the MRSDistComp Web APIs
                AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.CentralRegistryAuthority, new NaiveSessionCache(userObjectID, HttpContext.Session));                
                ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.CentralRegistryResourceAppId, credential);                
                
                // Retrieve the participant list.
                HttpClient client = new HttpClient();                
                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.CentralRegistryBaseAddress + "/api/GetProjectJobs");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                if (string.IsNullOrEmpty(projectname))
                    projectname = string.Empty;
                    
                request.Content = new StringContent(JsonConvert.SerializeObject(new { projectname = projectname}), Encoding.UTF8, "application/json");                
                HttpResponseMessage response = await client.SendAsync(request);

                // Return the computation project jobs' in the view.
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
                            ComputationInfoJob computationJob = new ComputationInfoJob();
                            computationJob.Id = column[0].ToString();
                            computationJob.ComputationInfo = column[1].ToString();
                            computationJob.Operation = column[2].ToString();
                            computationJob.Result = column[3].ToString();
                            computationJob.Summary = column[4].ToString();
                            computationJob.LogTxt = column[5].ToString();
                            computationJob.Status = column[6].ToString();
                            computationJob.StartDateTime = DateTime.Parse(column[7].ToString());
                            computationJob.EndDateTime = DateTime.Parse(column[8].ToString());
                            computationJobsList.Add(computationJob);
                        }
                    }

                    return View(computationJobsList);
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
                        ComputationInfoJob newComputationJob = new ComputationInfoJob();
                        newComputationJob.Id = "(No computation projects exist in the system)";
                        computationJobsList.Add(newComputationJob);
                        return View(computationJobsList);
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
                ComputationInfoJob newComputationJob = new ComputationInfoJob();
                newComputationJob.Id = "(Sign-in required to view computation projects.)";
                computationJobsList.Add(newComputationJob);
                ViewBag.ErrorMessage = "AuthorizationRequired" + ex.Message;
                return View(computationJobsList);                
            }
            //
            // If the call failed for any other reason, show the user an error.
            //
            return View("Error");
        }

        [HttpPost]
        public async Task<ActionResult> Index(string projectname, 
                                              string jobid)
        {
            if (string.IsNullOrEmpty(projectname))
                throw new ArgumentNullException("projectname");

            Guid jobidguid;
            if (string.IsNullOrEmpty(jobid) || !Guid.TryParse(jobid, out jobidguid))
                jobidguid = Guid.NewGuid();

            if (ModelState.IsValid)
            {
                //
                // Retrieve the user's tenantID and access token since 
                // they are parameters used to call the To Do service.
                //
                AuthenticationResult result = null;
                List<ComputationInfoJob> computationJobsList = new List<ComputationInfoJob>();

                try
                {
                    string userObjectID = (User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier"))?.Value;
                    AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.CentralRegistryAuthority, new NaiveSessionCache(userObjectID, HttpContext.Session));
                    ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                    result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.CentralRegistryResourceAppId, credential);
                    
                    // Forms encode participant record, to POST to the MRSDistComp Web API.
                    HttpContent content = new StringContent(JsonConvert.SerializeObject(new { projectname = projectname,
                        jobid = jobidguid.ToString()}), 
                        System.Text.Encoding.UTF8, 
                        "application/json");

                    //
                    // Create new job.
                    //
                    HttpClient client = new HttpClient();
                    HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.CentralRegistryBaseAddress + "/api/TriggerJob");
                    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                    request.Content = content;
                    HttpResponseMessage response = await client.SendAsync(request);

                    //
                    // Return the job in the view.
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
                            ComputationInfoJob newComputationJob = new ComputationInfoJob();
                            newComputationJob.Id = "(Sign-in required to view computation projects.)";
                            computationJobsList.Add(newComputationJob);
                            ViewBag.ErrorMessage = "UnexpectedError";
                            return View(computationJobsList);
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
                    ComputationInfoJob newComputationJob = new ComputationInfoJob();
                    newComputationJob.Id = "(Sign-in required to view computation projects.)";
                    computationJobsList.Add(newComputationJob);
                    ViewBag.ErrorMessage = "AuthorizationRequired";
                    return View(computationJobsList);                    
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
