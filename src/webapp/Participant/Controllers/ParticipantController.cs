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
    public class ParticipantController : Controller
    {
        // GET: /<controller>/
        public async Task<IActionResult> Index()
        {
            AuthenticationResult result = null;
            List<Participant> participantList = new List<Participant>();

            try
            {
                // Because we signed-in already in the WebApp, the userObjectId is known
                string userObjectID = (User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier"))?.Value;

                // Using ADAL.Net, get a bearer token to access the MRSDistComp Web APIs
                AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.CentralRegistryAuthority, new NaiveSessionCache(userObjectID, HttpContext.Session));
                //AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.CentralRegistryAuthority);
                ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.CentralRegistryResourceAppId, credential);
                
                
                // Retrieve the participant list.
                HttpClient client = new HttpClient();                
                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.CentralRegistryBaseAddress + "/api/GetParticipants");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
                
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
                            Participant participant = new Participant();
                            participant.Id = Guid.Parse(column[0].ToString());
                            participant.Name = column[1].ToString();
                            participant.ClientId = Guid.Parse(column[2].ToString());
                            participant.TenantId = column[3].ToString();
                            participant.URL = column[4].ToString();
                            participant.ClientSecret = column[5].ToString();
                            participant.IsEnabled = (Convert.ToInt32(column[6].ToString()) == 1) ? true : false;
                            participant.ValidFrom = DateTime.Parse(column[7].ToString());
                            participant.ValidTo = DateTime.Parse(column[8].ToString());

                            participantList.Add(participant);
                        }
                    }

                    return View(participantList);
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
                        Participant newParticipant = new Participant();
                        newParticipant.Name = "(No participants exist in the system)";
                        participantList.Add(newParticipant);
                        return View(participantList);
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
                
                Participant newParticipant = new Participant();
                newParticipant.Name = "(Sign-in required to view participants.)";
                participantList.Add(newParticipant);
                ViewBag.ErrorMessage = "AuthorizationRequired" + ex.Message;
                return View(participantList);
            }
            //
            // If the call failed for any other reason, show the user an error.
            //
            return View("Error");
        }

        [HttpPost]
        public async Task<ActionResult> Index(string name, string clientid, string clientsecret, string tenantid, string url)
        {
            if (ModelState.IsValid)
            {
                //
                // Retrieve the user's tenantID and access token since 
                // they are parameters used to call the To Do service.
                //
                AuthenticationResult result = null;
                List<Participant> participantList = new List<Participant>();

                try
                {
                    // Local operation
                    string userObjectID = (User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier"))?.Value;
                    AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.Authority, new NaiveSessionCache(userObjectID, HttpContext.Session));
                    ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                    result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.ResourceAppId, credential);

                    // Forms encode participant record, to POST to the MRSDistComp Web API.
                    HttpContent content = new StringContent(JsonConvert.SerializeObject(new { name = name,
                        clientid = clientid,
                        clientsecret = clientsecret,
                        tenantid = tenantid,
                        url = url}), System.Text.Encoding.UTF8, "application/json");

                    //
                    // Register the Central Registry as the participnat in your system.
                    //
                    HttpClient client = new HttpClient();
                    HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.ResourceBaseAddress + "/api/RegisterMaster");
                    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                    request.Content = content;
                    HttpResponseMessage response = await client.SendAsync(request);

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

                            ViewBag.ErrorMessage = "UnexpectedError";
                            Participant newParticipant = new Participant();
                            newParticipant.Name = "(Unauthorized access. You must sign-in again to perform this operation.)";
                            participantList.Add(newParticipant);
                            return View(newParticipant);
                        }
                        else
                        {
                            ViewBag.ErrorMessage = "Application error";
                            Participant newParticipant = new Participant();
                            newParticipant.Name = "(Could not register Central Registry participant in the system. Please contact System Administrator.)";
                            participantList.Add(newParticipant);
                            return View(newParticipant);                            
                        }
                    }
                }
                catch
                {
                    //
                    // The user needs to re-authorize.  Show them a message to that effect.
                    //
                    Participant newParticipant = new Participant();
                    newParticipant.Name = "(No items in list)";
                    participantList.Add(newParticipant);
                    ViewBag.ErrorMessage = "AuthorizationRequired";
                    return View(participantList);
                }                
            }
            return View("Error");
        }
    }
}
