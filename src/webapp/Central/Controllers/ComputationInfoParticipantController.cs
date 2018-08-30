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
    public class ComputationInfoParticipantController : Controller
    {
        // GET: /<controller>/
        public async Task<IActionResult> Index(string projectname)
        {

            AuthenticationResult result = null;
            List<ComputationInfoParticipant> projectParticipantsList = new List<ComputationInfoParticipant>();

            if (string.IsNullOrEmpty(projectname))
                projectname = string.Empty;

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
                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.CentralRegistryBaseAddress + "/api/GetProjectParticipants");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                request.Content = new StringContent(JsonConvert.SerializeObject(new { projectname = projectname}), Encoding.UTF8, "application/json");
                
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
                            ComputationInfoParticipant projectParticipant = new ComputationInfoParticipant();
                            projectParticipant.Id = column[0].ToString();
                            projectParticipant.ComputationInfoName = column[1].ToString();
                            projectParticipant.ParticipantName = column[2].ToString();
                            projectParticipant.IsEnabled = column[3].ToString(); 
                            projectParticipantsList.Add(projectParticipant);
                        }
                    }

                    return View(projectParticipantsList);
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
                        ComputationInfoParticipant newProjectParticipant = new ComputationInfoParticipant();
                        newProjectParticipant.Id = "(No participants have enrolled in a project)";
                        projectParticipantsList.Add(newProjectParticipant);
                        return View(projectParticipantsList);
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
                ComputationInfoParticipant newProjectParticipant = new ComputationInfoParticipant();
                newProjectParticipant.Id = "(Sign-in required to view project particpants.)";
                projectParticipantsList.Add(newProjectParticipant);
                ViewBag.ErrorMessage = "AuthorizationRequired" + ex.Message;
                return View(projectParticipantsList);                
            }
            //
            // If the call failed for any other reason, show the user an error.
            //
            return View("Error");
        }

        [HttpPost]
        public async Task<ActionResult> Index(string projectname, 
                                              string participantname,
                                              string submitbutton)
        {
            if (ModelState.IsValid)
            {
                //
                // Retrieve the user's tenantID and access token since 
                // they are parameters used to call the To Do service.
                //
                AuthenticationResult result = null;
                List<ComputationInfoParticipant> projectParticipantsList = new List<ComputationInfoParticipant>();

                try
                {
                    string userObjectID = (User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier"))?.Value;
                    AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.Authority, new NaiveSessionCache(userObjectID, HttpContext.Session));
                    ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                    result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.CentralRegistryResourceAppId, credential);

                    // Forms encode participant record, to POST to the MRSDistComp Web API.
                    HttpContent content = new StringContent(JsonConvert.SerializeObject(new
                    {
                        projectname = projectname,
                        participantname = participantname,
                        operation = submitbutton
                    }), System.Text.Encoding.UTF8, "application/json");

                    //
                    // Add new project participant.
                    //
                    HttpClient client = new HttpClient();
                    HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.CentralRegistryBaseAddress + "/api/EnrollInProject");                    
                    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                    request.Content = content;
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
                            ComputationInfoParticipant newProjectParticipant = new ComputationInfoParticipant();
                            newProjectParticipant.Id = "(Sign-in required to view project participants.)";
                            projectParticipantsList.Add(newProjectParticipant);
                            ViewBag.ErrorMessage = "UnexpectedError";
                            return View(projectParticipantsList);
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
                    ComputationInfoParticipant newProjectParticipant = new ComputationInfoParticipant();
                    newProjectParticipant.Id = "(Sign-in required to view project participants.)";
                    projectParticipantsList.Add(newProjectParticipant);
                    ViewBag.ErrorMessage = "AuthorizationRequired";
                    return View(projectParticipantsList);                    
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
