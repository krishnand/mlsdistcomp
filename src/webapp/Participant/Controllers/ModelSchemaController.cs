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
    public class ModelSchemaController : Controller
    {
        // GET: /<controller>/
        public async Task<IActionResult> Index()
        {
            AuthenticationResult result = null;
            List<ModelSchema> schemaList = new List<ModelSchema>();

            try
            {
                // Because we signed-in already in the WebApp, the userObjectId is known
                string userObjectID = (User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier"))?.Value;

                // Using ADAL.Net, get a bearer token to access the MRSDistComp Web APIs
                AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.CentralRegistryAuthority, new NaiveSessionCache(userObjectID, HttpContext.Session));                
                ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.CentralRegistryResourceAppId, credential);
                
                
                // Retrieve the schemas list.
                HttpClient client = new HttpClient();                
                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.CentralRegistryBaseAddress + "/api/GetSchemas");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                HttpContent content = new StringContent(JsonConvert.SerializeObject(new { schemaname = string.Empty }),
                                                            System.Text.Encoding.UTF8,
                                                            "application/json");
                request.Content = content;
                
                HttpResponseMessage response = await client.SendAsync(request);

                // Return the schemas' in the view.
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
                            ModelSchema schema = new ModelSchema();
                            schema.Name = column[1].ToString();
                            schema.Description = column[2].ToString();
                            schema.Version = column[3].ToString();
                            schema.SchemaJSON = column[4].ToString();
                            schemaList.Add(schema);
                        }
                    }

                    return View(schemaList);
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
                        ModelSchema newModelSchema = new ModelSchema();
                        newModelSchema.Name = "(No data schemas exist in the system)";
                        schemaList.Add(newModelSchema);
                        return View(schemaList);
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
                
                ModelSchema newModelSchema = new ModelSchema();
                newModelSchema.Name = "(Sign-in required to view data schemas.)";
                schemaList.Add(newModelSchema);
                ViewBag.ErrorMessage = "AuthorizationRequired" + ex.Message;
                return View(schemaList);
            }
            //
            // If the call failed for any other reason, show the user an error.
            //
            return View("Error");
        }

        [HttpPost]
        public async Task<ActionResult> Index(string name, string description, string schemajson)
        {
            if (ModelState.IsValid)
            {
                //
                // Retrieve the user's tenantID and access token
                //
                AuthenticationResult result = null;
                List<ModelSchema> schemaList = new List<ModelSchema>();

                try
                {
                    string userObjectID = (User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier"))?.Value;
                    AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.CentralRegistryAuthority, new NaiveSessionCache(userObjectID, HttpContext.Session));
                    ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                    result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.CentralRegistryResourceAppId, credential);

                    if (string.IsNullOrEmpty(description))
                        description = name;

                    // Forms encode schema record, to POST to the MRSDistComp Web API.
                    HttpContent content = new StringContent(JsonConvert.SerializeObject(new { schemaname = name, schemadesc = description, schema = schemajson, broadcast=true}), 
                                                            System.Text.Encoding.UTF8, 
                                                            "application/json");

                    //
                    // Add new data schema to the data catalog.
                    //
                    HttpClient client = new HttpClient();
                    HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.CentralRegistryBaseAddress + "/api/RegisterSchema");
                    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                    request.Content = content;
                    HttpResponseMessage response = await client.SendAsync(request);

                    //
                    // Return the view.
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

                            ViewBag.ErrorMessage = "UnexpectedError";
                            ModelSchema newModelSchema = new ModelSchema();
                            newModelSchema.Name = "(Sign-in required to view data catalog.)";
                            schemaList.Add(newModelSchema);
                            return View(newModelSchema);
                        }
                    }
                }
                catch
                {
                    //
                    // The user needs to re-authorize.  Show them a message to that effect.
                    //
                    ModelSchema newModelSchema = new ModelSchema();
                    newModelSchema.Name = "(No schemas exist in the data catalog)";
                    schemaList.Add(newModelSchema);
                    ViewBag.ErrorMessage = "AuthorizationRequired";
                    return View(schemaList);
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
