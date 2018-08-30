using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Clients.ActiveDirectory;
using Microsoft.WindowsAzure.Storage;
using Microsoft.WindowsAzure.Storage.Blob;
using Microsoft.WindowsAzure.Storage.DataMovement;
using MRSDistCompWebApp.Models;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;

// For more information on enabling MVC for empty projects, 
// visit http://go.microsoft.com/fwlink/?LinkID=397860

namespace MRSDistCompWebApp.Controllers
{
    [Authorize]
    public class DataSourceController : Controller
    {
        // GET: /<controller>/
        public async Task<IActionResult> Index()
        {
            AuthenticationResult result = null;
            List<DataSource> datasourceList = new List<DataSource>();

            try
            {
                // Because we signed-in already in the WebApp, the userObjectId is known
                string userObjectID = (User.FindFirst("http://datasources.microsoft.com/identity/claims/objectidentifier"))?.Value;

                // Using ADAL.Net, get a bearer token to access the MRSDistComp Web APIs
                AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.Authority, new NaiveSessionCache(userObjectID, HttpContext.Session));                
                ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.ResourceAppId, credential);
                
                
                // Retrieve the datasources list.
                HttpClient client = new HttpClient();                
                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.ResourceBaseAddress + "/api/GetDataSources");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
                
                HttpResponseMessage response = await client.SendAsync(request);

                // Return the datasources' in the view.
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
                            DataSource datasource = new DataSource();
                            datasource.Name = column[1].ToString();
                            datasource.Description = column[2].ToString();
                            datasource.Type = column[3].ToString();
                            datasource.ModelSchema = column[4].ToString();
                            datasource.AccessInfo = column[5].ToString();
                            datasourceList.Add(datasource);
                        }
                    }

                    return View(datasourceList);
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
                        DataSource newDataSource = new DataSource();
                        newDataSource.Name = "(No data datasources exist in the system)";
                        datasourceList.Add(newDataSource);
                        return View(datasourceList);
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
                
                DataSource newDataSource = new DataSource();
                newDataSource.Name = "(Sign-in required to view data datasources.)";
                datasourceList.Add(newDataSource);
                ViewBag.ErrorMessage = "AuthorizationRequired" + ex.Message;
                return View(datasourceList);
            }
            //
            // If the call failed for any other reason, show the user an error.
            //
            return View("Error");
        }

        [HttpPost]
        public async Task<ActionResult> Index(string name, string description, string type, string modelschema, IFormFile datafile)
        {
            if (ModelState.IsValid)
            {
                //
                // Retrieve the user's tenantID and access token
                //
                AuthenticationResult result = null;
                List<DataSource> datasourceList = new List<DataSource>();

                try
                {
                    string userObjectID = (User.FindFirst("http://datasources.microsoft.com/identity/claims/objectidentifier"))?.Value;

                    AuthenticationContext authContext = new AuthenticationContext(AzureAdOptions.Settings.Authority, new NaiveSessionCache(userObjectID, HttpContext.Session));
                    ClientCredential credential = new ClientCredential(AzureAdOptions.Settings.ClientId, AzureAdOptions.Settings.ClientSecret);
                    result = await authContext.AcquireTokenAsync(AzureAdOptions.Settings.ResourceAppId, credential);
                    HttpContent content = null;
                    HttpClient client = null;
                    HttpRequestMessage request = null;
                    HttpResponseMessage response = null;

                    if (string.IsNullOrEmpty(type) || type.ToLower().Trim() != "csv")
                    {
                        ViewBag.ErrorMessage = "Unsupported data source type.";
                        return View();                       
                    }

                    // Step 1: Upload the file file to Azure blob storage (this storage is part of the
                    // storage account created as part of this deployment. Plus we create a SAS URI with
                    // a read-only permission on the blob fror 24 hours. Once uploaded, we immediately download this
                    // onto the R server to the "/var/lib/mlsdistcomp/data" - directory
                    Tuple<bool, string> uploadFileOp = UploadFileToAzureBlob(name, datafile);
                    string localdsfilename = name + Path.GetExtension(datafile.FileName);
                    if (!uploadFileOp.Item1)
                    {
                        ViewBag.ErrorMessage = "Error uploading file to Azure blob. Please contact the Administrator before proceeding.";
                        return View();
                    }
                    else
                    {
                        content = new StringContent(JsonConvert.SerializeObject(
                        new
                        {
                            downloaduri = uploadFileOp.Item2,
                            localfilename = localdsfilename
                        }), Encoding.UTF8, "application/json");


                        // Add new data datasource to the data catalog.
                        client = new HttpClient();
                        request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.ResourceBaseAddress + "/api/DownloadDataSourceFile");
                        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                        request.Content = content;
                        response = await client.SendAsync(request);
                    }                    

                    // Step 2: Now finish completing the datasource record with the correct "accessinfo" filepath
                    // location. AccessInfo is primarily the file path of the file. We simply point to the 
                    // local file.
                    if (string.IsNullOrEmpty(description)) description = name;
                        content = new StringContent(JsonConvert.SerializeObject(
                            new { datasourcename = name,
                                datasourcedesc = description,
                                schemaname = modelschema,
                                datasourcelocation = "/var/lib/mlsdistcomp/data/" + localdsfilename}),  Encoding.UTF8, "application/json");


                    // Add new data datasource to the data catalog.
                    client = new HttpClient();
                    request = new HttpRequestMessage(HttpMethod.Post, AzureAdOptions.Settings.ResourceBaseAddress + "/api/CreateCSVDataSource");
                    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
                    request.Content = content;
                    response = await client.SendAsync(request);

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
                            DataSource newDataSource = new DataSource();
                            newDataSource.Name = "(Sign-in required to view data catalog.)";
                            datasourceList.Add(newDataSource);
                            return View(newDataSource);
                        }
                    }
                }
                catch
                {
                    //
                    // The user needs to re-authorize.  Show them a message to that effect.
                    //
                    DataSource newDataSource = new DataSource();
                    newDataSource.Name = "(No datasources exist in the data catalog)";
                    datasourceList.Add(newDataSource);
                    ViewBag.ErrorMessage = "AuthorizationRequired";
                    return View(datasourceList);
                }
                //
                // If the call failed for any other reason, show the user an error.
                //
                return View("Error");
            }
            return View("Error");
        }

        private Tuple<bool, string> UploadFileToAzureBlob(string name, IFormFile file)
        {
            Tuple<bool, string> retVal = new Tuple<bool, string>(false, null);

            try
            {
                CloudStorageAccount account = CloudStorageAccount.Parse(AzureAdOptions.Settings.StorageAccountConnectionString);
                if (account == null)
                    return retVal;

                CloudBlobClient blobClient = account.CreateCloudBlobClient();
                if (blobClient == null)
                    return retVal;

                CloudBlobContainer blobContainer = blobClient.GetContainerReference("data");
                if (blobContainer == null)
                    return retVal;
                blobContainer.CreateIfNotExistsAsync();

                CloudBlockBlob fileBlob = blobContainer.GetBlockBlobReference(name + Path.GetExtension(file.FileName));
                if (fileBlob == null)
                    return retVal;

                //string sourcePath = "path\\to\\test.txt";
                TransferManager.Configurations.ParallelOperations = 16;

                // Setup the transfer context and track the upoload progress
                SingleTransferContext context = new SingleTransferContext();

                // Upload a local blob
                using (Stream s1 = file.OpenReadStream())
                {
                    var task = TransferManager.UploadAsync(s1, fileBlob);
                    task.Wait();                    
                }

                // Create Shared Accees Policy. 
                SharedAccessBlobPolicy sasConstraints = new SharedAccessBlobPolicy();
                sasConstraints.SharedAccessStartTime = DateTimeOffset.UtcNow.AddMinutes(-5);
                sasConstraints.SharedAccessExpiryTime = DateTimeOffset.UtcNow.AddHours(24);
                sasConstraints.Permissions = SharedAccessBlobPermissions.Read;

                //Generate the shared access signature on the blob, setting the constraints directly on the signature.
                string sasBlobToken = fileBlob.GetSharedAccessSignature(sasConstraints);

                retVal = new Tuple<bool, string>(true, fileBlob.Uri + sasBlobToken);                

            }
            catch
            {
                return retVal;
            }

            return retVal;
        }

        static string GetBlobSasUri(CloudBlockBlob fileBlob)
        {
            //Get a reference to a blob within the container.
            // CloudBlockBlob blob = container.GetBlockBlobReference("sasblob.txt");

            //Upload text to the blob. If the blob does not yet exist, it will be created.
            //If the blob does exist, its existing content will be overwritten.
            // string blobContent = "This blob will be accessible to clients via a shared access signature (SAS).";
            // blob.UploadText(blobContent);

            //Set the expiry time and permissions for the blob.
            //In this case, the start time is specified as a few minutes in the past, to mitigate clock skew.
            //The shared access signature will be valid immediately.
            SharedAccessBlobPolicy sasConstraints = new SharedAccessBlobPolicy();
            sasConstraints.SharedAccessStartTime = DateTimeOffset.UtcNow.AddMinutes(-5);
            sasConstraints.SharedAccessExpiryTime = DateTimeOffset.UtcNow.AddHours(24);
            sasConstraints.Permissions = SharedAccessBlobPermissions.Read;

            //Generate the shared access signature on the blob, setting the constraints directly on the signature.
            string sasBlobToken = fileBlob.GetSharedAccessSignature(sasConstraints);

            //Return the URI string for the container, including the SAS token.
            return fileBlob.Uri + sasBlobToken;
        }
    }

}
