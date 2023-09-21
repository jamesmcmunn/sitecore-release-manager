<%@ Page Language="C#" AutoEventWireup="true" %>
<%@ Import Namespace="System" %>
<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Globalization" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="ICSharpCode.SharpZipLib.Core" %>
<%@ Import Namespace="ICSharpCode.SharpZipLib.Zip" %>
<%@ Import Namespace="Sitecore" %>
<%@ Import Namespace="Sitecore.Data" %>
<%@ Import Namespace="Sitecore.Data.Engines" %>
<%@ Import Namespace="Sitecore.Exceptions" %>
<%@ Import Namespace="Sitecore.SecurityModel" %>
<%@ Import Namespace="Newtonsoft.Json" %>
<%@ Import Namespace="Sitecore.Data.Items" %>

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
    <head>
                

        <script runat="server" src="Release.aspx.cs">
        </script>
        <script runat="server">
            
            public const string WARNING = "warning text-dark";
            public const string SUCCESS = "success";

            public enum ActionTypeEnum
            {
                None,
                Install,
                Publish,
                Save,
                DeletePackage,
                DeletePublish,
                AddPackage,
                AddPublish,
                AddRelease,
                DeleteRelease
            }

            public enum MessageTypeEnum {
                Info,
                Success,
                Warning, 
                Danger, 
                Secondary
            }

            public class Message {
                

                public string Content {get;set;}
                public MessageTypeEnum MessageType {get;set;}

                public string MessageTypeString {
                    get{
                        return MessageType.ToString().ToLower();
                    }
                }
                public Message(string content, MessageTypeEnum messageType = MessageTypeEnum.Info){
                        Content = content;
                        MessageType = messageType;
                }
            }
            public class ReleaseManager
            {
                private Page Page { get; set; }
                public IList<Message> Messages = new List<Message>();
                public string ReleasesPath;
                public string PackagesPath;
                private IList<FileInfo> ReleasesInfo;
                private IList<FileInfo> PackagesInfo;
                public IList<PackageModel> PackagesAvailable;
                public IList<ReleaseModel> Releases { get; set; }

                public ReleaseManager(Page page)
                {
                    Page = page;
                    ReleasesPath = Sitecore.Configuration.Settings.GetSetting("Release.ReleasesPath");
                    PackagesPath = Sitecore.Configuration.Settings.GetSetting("Release.PackagesPath");

                    if (string.IsNullOrEmpty(ReleasesPath))
                    {
                        ReleasesPath = page.Server.MapPath("Releases");
                        AddMessage(string.Format("ReleasesPath set to '{0}' - can be overridden using Setting 'Release.ReleasesPath'", ReleasesPath), MessageTypeEnum.Secondary);
                    }
                    else
                    {
                        AddMessage(string.Format("ReleasesPath overridden to '{0}'", ReleasesPath), MessageTypeEnum.Secondary );
                    }

                    if (string.IsNullOrEmpty(PackagesPath))
                    {
                        PackagesPath = page.Server.MapPath("../../app_data/packages");
                        AddMessage(string.Format("PackagesPath set to '{0}' - can be overridden using Setting 'Release.PackagesPath'", PackagesPath), MessageTypeEnum.Secondary);
                    }
                    else
                    {
                        AddMessage(string.Format("PackagesPath overridden to '{0}'", PackagesPath), MessageTypeEnum.Secondary);
                    }

                }

                public void CreateReleases()
                {
                    Releases = new List<ReleaseModel>();

                    ReleasesInfo = new DirectoryInfo(ReleasesPath).EnumerateFiles("*.json").ToList();
                    PackagesInfo = new DirectoryInfo(PackagesPath).EnumerateFiles("*.zip").ToList();

                    PackagesAvailable = PackagesInfo
                        .Select(s => CreatePackage(s.Name.Replace(".zip", "")))
                        .ToList();

                    foreach (var file in ReleasesInfo)
                    {
                        var content = File.ReadAllText(file.FullName, Encoding.UTF8);
                        var release = (ReleaseModel)JsonConvert.DeserializeObject(content, typeof(ReleaseModel));
                        release.Index = ReleasesInfo.IndexOf(file);
                        release.Name = file.Name.Replace(".json", "");
                        release.PackageModels = new List<PackageModel>();

                        foreach (var releasePackage in release.Packages)
                        {
                            var package = PackagesAvailable.FirstOrDefault(f => f.Name == releasePackage);
                            if (package == null)
                            {
                                package = new PackageModel
                                {
                                    Exists = false,
                                    Name = releasePackage
                                };
                            }
                            ValidatePackageForRelease(package, release);
                            
                            release.PackageModels.Add(
                                package
                            );
                        }

                        foreach (var publish in release.Publishing)
                        {
                            ValidatePublish(publish, release);
                        }

                        Releases.Add(release);
                    }
                }

                private PackageModel CreatePackage(string releasePackage, ReleaseModel release = null)
                {
                    var package = new PackageModel();

                    package.Name = releasePackage;

                    ParsePackage(package);
                    ValidatePackage(package);
                    if (release != null)
                    {
                        ValidatePackageForRelease(package, release);
                    }

                    return package;
                }

                private void ValidatePublish(PublishModel publish, ReleaseModel release)
                {
                    publish.Warnings = new List<string>();
                    var master = Sitecore.Configuration.Factory.GetDatabase("master");
                    var item = master.GetItem(publish.Path);
                    if (item == null)
                    {
                        publish.Warnings.Add("Unable to locate item at path '" + publish.Path + "'");
                    }
                }   

                private void ValidatePackage(PackageModel package)
                {
                    package.Warnings = new List<string>();
                    
                    if (string.IsNullOrWhiteSpace(package.PackageName))
                    {
                        package.Warnings.Add("Package name missing");
                    }
                    
                    if (string.IsNullOrWhiteSpace(package.PackageAuthor))
                    {
                        package.Warnings.Add("Package author missing");
                    }
                    
                    if (string.IsNullOrWhiteSpace(package.PackageVersion))
                    {
                        package.Warnings.Add("Package version missing");
                    }
                }

                private void ValidatePackageForRelease(PackageModel package, ReleaseModel release)
                {
                    package.Used = true;
                    foreach(var item in package.Items){
                        if (!release.Publishing.Any(a => 
                            (a.SubItems == true && item.StartsWith("/master" + a.Path))
                            || item.StartsWith("/master" + a.Path + "/{")
                            ))
                        {
                            package.Warnings.Add(string.Format("Item {0} potentially not published", item.Replace("/master", "")));
                        }
                    }
                }

                private void ParsePackage(PackageModel package)
                {
                    
                    var packageFile = PackagesInfo.FirstOrDefault(a => a.Name == package.Name + ".zip");
                    if (packageFile == null)
                    {
                        return;
                    }
                    
                    package.Exists = true;
                    package.Path = packageFile.FullName;

                    try
                    {
                        var zip = new ZipFile(package.Path);

                        foreach (ZipEntry entry in zip)
                        {

                            using (var stream = zip.GetInputStream(entry))
                            {

                                // Analyze file in memory using MemoryStream.
                                using (MemoryStream ms = new MemoryStream())
                                {
                                    var buf = new byte[4096];
                                    StreamUtils.Copy(stream, ms, buf);
                                    var packageZip = new ZipFile(ms);
                                    foreach (ZipEntry packageEntry in packageZip)
                                    {

                                        if (package.Properties.Keys.Contains(packageEntry.Name))
                                        {
                                            using (var fileStream = packageZip.GetInputStream(packageEntry))
                                            {
                                                using (var memoryStream = new MemoryStream())
                                                {
                                                    var buffer = new byte[4096];
                                                    StreamUtils.Copy(fileStream, memoryStream, buffer);
                                                    package.Properties[packageEntry.Name] = Encoding.UTF8.GetString(buffer)
                                                        .TrimEnd((char)0);
                                                }
                                            }
                                        }
                                        else if (packageEntry.Name.StartsWith("items"))
                                        {
                                            package.Items.Add(packageEntry.Name.Replace("items", ""));
                                        }
                                        else
                                        {
                                            package.Entries.Add(packageEntry.Name);
                                        }

                                    }
                                }

                            }

                        }
                    }
                    catch (Exception e)
                    {
                        AddMessage("Cannot open zip file " + packageFile.FullName + " :" + e);
                        package.Corrupt = true;
                        return;
                    }

                    var matched = InstallationHistory.FirstOrDefault(a => a.Name == package.Name);
                    if (matched == null)
                    {
                        matched = InstallationHistory.FirstOrDefault(a => package.Name.Contains(a.Name));
                    }

                    if (matched == null)
                    {
                        return;
                    }

                    package.MatchedName = matched.Name;
                    var children = matched
                        .GetChildren().ToList();

                    if (children.Count == 0)
                    {
                        AddMessage(string.Format("No children for package {0}", package.Name) );
                        return;
                    }

                    var matchedChild = children
                        .FirstOrDefault(w => 
                            w["Package version"].Equals(package.PackageVersion, StringComparison.InvariantCultureIgnoreCase)
                            && w["Package author"].Equals(package.PackageAuthor, StringComparison.InvariantCultureIgnoreCase)
                            );

                    if (matchedChild == null)
                    {
                        AddMessage(string.Format("No matched children for package {0}", package.Name) );
                        return;
                    }

                    DateTime? date = null;
                    date = DateTime.ParseExact(matchedChild.Name, "yyyyMMddTHHmmssZ", new DateTimeFormatInfo());
                    package.InstalledDate = date;
                }

                public string GetAction(ActionTypeEnum action, ReleaseModel release, PackageModel package = null, int publishIndex = 0)
                {
                    return string.Format("{0}|{1}|{2}|{3}", action.ToString(), release == null ? "" : release.Name, package == null ? "" : package.Name, publishIndex);
                }

                public void ParseAction(string actionString, out ActionTypeEnum action, out string releaseName, out string packageName, out int publishIndex)
                {
                    var sections = actionString.Split("|".ToCharArray());
                    Enum.TryParse(sections[0], out action);
                    releaseName = sections[1];
                    packageName = sections[2];
                    if (!int.TryParse(sections[3], out publishIndex))
                    {
                        publishIndex = -1;
                    }
                }

                public void Process()
                {
                    var action = Page.Request.Form["action"];
                    ActionTypeEnum actionType;
                    string releaseName;
                    string packageName;
                    int publishIndex;

                    if (string.IsNullOrEmpty(action))
                    {
                        return;
                    }
                    

                    ParseAction(action, out actionType, out releaseName, out packageName, out publishIndex);
                    if (actionType == ActionTypeEnum.None)
                    {
                        return;
                    }

                    ReleaseModel release;

                    if (actionType == ActionTypeEnum.AddRelease)
                    {
                        release = new ReleaseModel
                        {
                            Name = Page.Request.Form["NewRelease"]
                        };

                        if (string.IsNullOrEmpty(release.Name))
                        {
                            AddMessage("Release with empty name is invalid!", MessageTypeEnum.Danger);
                            return;
                        }

                        if (Releases.Any(a => a.Name == release.Name))
                        {
                            AddMessage(string.Format("Release '{0}' already exists!", release.Name), MessageTypeEnum.Danger);
                            return;
                        }

                        if (release.Name.IndexOfAny(Path.GetInvalidFileNameChars()) > 0)
                        {
                            AddMessage(string.Format("Release '{0}' is an invalid filename!", release.Name), MessageTypeEnum.Danger);
                            return;
                        }

                        Releases.Add(release);
                        SaveRelease(release);
                        return;
                    }

                    release = Releases.FirstOrDefault(f => f.Name == releaseName);

                    if (release == null)
                    {
                        AddMessage("Release '" + releaseName + "' not found");
                        return;
                    }

                    if (actionType == ActionTypeEnum.DeleteRelease)
                    {
                        Releases.Remove(release);
                        var releaseFile = ReleasesInfo.FirstOrDefault(f => f.Name == release.Name + ".json");
                        if (releaseFile == null)
                        {
                            AddMessage("Release file '" + release.Name + "' not found", MessageTypeEnum.Warning);
                            return;
                        }

                        AddMessage("Deleting '" + releaseFile.FullName + "'");
                        File.Delete(releaseFile.FullName);
                        return;
                    }

                    release.Active = true;

                    var package = release.PackageModels.FirstOrDefault(f => f.Name == packageName);

                    if (actionType == ActionTypeEnum.Install)
                    {
                        
                        if (package == null)
                        {
                            AddMessage("Package '" + packageName + "' does not exist - cannot install");
                            return;
                        }

                        InstallPackage(package);

                        // refresh the package after installation - should now have history
                        release.PackageModels[release.PackageModels.IndexOf(package)] = CreatePackage(package.Name, release);
                        
                        return;
                    }
                    
                    if (actionType == ActionTypeEnum.AddPackage)
                    {
                        AddMessage(string.Format("Adding package for release '{1}'", package, release.Name));
                        
                        // refresh the package after installation - should now have history
                        var releasePackage = Page.Request.Form["NewPackage_" + release.Index];
                        if (string.IsNullOrEmpty(releasePackage))
                        {
                            AddMessage(string.Format("Empty new package name for release '{0}'", release.Name));
                            return;
                        }
                        var newPackage = PackagesAvailable.FirstOrDefault(f => f.Name == releasePackage);
                        if (newPackage == null)
                        {
                            AddMessage(string.Format("No package available on server for '{0}'", release.Name), MessageTypeEnum.Warning);
                            return;
                        }

                        release.Packages.Add(releasePackage);
                        ValidatePackageForRelease(newPackage, release);
                        release.PackageModels.Add(newPackage);
                        SaveRelease(release);
                    }

                    if (actionType == ActionTypeEnum.DeletePackage)
                    {
                        if (package == null)
                        {
                            AddMessage("Package '" + packageName + "' does not exist - cannot remove");
                            return;
                        }

                        AddMessage(string.Format("Deleting package {0} for release '{1}'", package, release.Name));
                        release.Packages.Remove(package.Name);
                        release.PackageModels.Remove(package);
                        SaveRelease(release);
                    }

                    if (actionType == ActionTypeEnum.Publish)
                    {
                        Publish(release);
                    }
                    
                    if (actionType == ActionTypeEnum.AddPublish)
                    {
                        release.Publishing.Add(
                            new PublishModel
                            {
                                Path = Page.Request.Form["NewPublishPath_" + release.Index],
                                SubItems = Page.Request.Form["NewPublishSub_" + release.Index] == "true"
                            });
                        SaveRelease(release);
                    }
                    
                    if (actionType == ActionTypeEnum.DeletePublish)
                    {
                        if (publishIndex < 0 || publishIndex > release.Publishing.Count - 1)
                        {
                            AddMessage("Publish index incorrect - aborting remove!");
                            return;
                        }
                        AddMessage("Removing publishing item '" + release.Publishing[publishIndex].Path + "'");
                        release.Publishing.RemoveAt(publishIndex);
                        SaveRelease(release);
                    }
                    
                    foreach (var item in release.PackageModels)
                    {
                        ValidatePackage(item);
                        ValidatePackageForRelease(item, release);
                    }

                    foreach (var item in release.Publishing)
                    {
                        ValidatePublish(item, release);
                    }
                }

                private void SaveRelease(ReleaseModel release)
                {
                    var content = JsonConvert.SerializeObject(release, Formatting.Indented);
                    var releaseFile = ReleasesInfo.FirstOrDefault(f => f.Name == release.Name + ".json");

                    if (releaseFile == null)
                    {
                        AddMessage("Creating file for release '" + release.Name + "'");
                        File.WriteAllText(ReleasesPath + "\\" + release.Name + ".json", content);
                        return;
                    }

                    AddMessage(string.Format("Saving file for release '{0}' at {1}", release.Name, releaseFile.FullName));
                    File.WriteAllText(releaseFile.FullName, content);
                }

                public void AddMessage(string message, MessageTypeEnum messageType = MessageTypeEnum.Info)
                {
                    Messages.Add(new Message(message, messageType));
                }

                public void InstallPackage(PackageModel package)
                {
                    AddMessage("Installing package " + package.Path);
                    var path = package.Path;
                    var pkgFile = new FileInfo(package.Path);

                    if (!pkgFile.Exists)
                        throw new ClientAlertException(string.Format("Cannot access path '{0}'. Please check path setting.", path));

                    Sitecore.Context.SetActiveSite("shell");
                    using (new SecurityDisabler())
                    {
                        using (new SyncOperationContext())
                        {
                            var context = new Sitecore.Install.Framework.SimpleProcessingContext(); // 
                            var events =
                                new Sitecore.Install.Items.DefaultItemInstallerEvents(
                                    new Sitecore.Install.Utils.BehaviourOptions(
                                        Sitecore.Install.Utils.InstallMode.Overwrite,
                                        Sitecore.Install.Utils.MergeMode.Undefined
                                    )
                                );

                            context.AddAspect(events);
                            var events1 = new Sitecore.Install.Files.DefaultFileInstallerEvents(true);
                            context.AddAspect(events1);
                            try
                            {
                                var inst = new Sitecore.Install.Installer();
                                inst.InstallPackage(MainUtil.MapPath(path), context);
                            }
                            catch (Exception e)
                            {
                                AddMessage(string.Format("Couldn't install package {0}: {1}", path, e));
                            }
                        }
                    }

                    // force re-lookup of installation history
                    _installationHistory = null;

                }

                public void Publish(ReleaseModel release)
                {
                    AddMessage("Publishing for release " + release.Name);

                    var web = Sitecore.Configuration.Factory.GetDatabase("web");
                    var master = Sitecore.Configuration.Factory.GetDatabase("master");
                    var databases = new Database[1] { web };

                    foreach (var publishItem in release.Publishing)
                    {
                        var item = master.GetItem(publishItem.Path);
                        if (item == null)
                        {
                            AddMessage("Unable to locate item " + publishItem.Path);
                            continue;
                        }

                        AddMessage("Publishing item " + publishItem.Path);
                        Sitecore.Publishing.PublishManager.PublishItem(item, databases, web.Languages, publishItem.SubItems, false);
                    }
                }

                private IList<Item> _installationHistory;
                public IList<Item> InstallationHistory
                {
                    get
                    {
                        if (_installationHistory == null)
                        {
                            var core = Sitecore.Configuration.Factory.GetDatabase("core");

                            _installationHistory = core.GetItem("/sitecore/system/packages/installation history").GetChildren().ToList();
                        }
                        
                        return _installationHistory;
                    }
                }


            }
                        
            public class ReleaseModel
            {
                public IList<PublishModel> Publishing { get; set; }
                public IList<string> Packages { get; set; }
                
                [JsonIgnore]
                public bool Active { get; set; }

                [JsonIgnore]
                public IList<PackageModel> PackageModels { get; set; }

                [JsonIgnore]
                public string Name { get; set; }
                
                [JsonIgnore]
                public int Index { get; set; }

                public ReleaseModel()
                {
                    Publishing = new List<PublishModel>();
                    Packages = new List<string>();
                    PackageModels = new List<PackageModel>();
                }

            }

            public class PublishModel
            {
                public string Path { get; set; }
                public bool SubItems { get; set; }

                [JsonIgnore]
                public IList<string> Warnings { get; set; }

                [JsonIgnore]
                public string Status
                {
                    get
                    {
                        if (Warnings.Any())
                        {
                            return WARNING;
                        }

                        return SUCCESS;
                    }
                }

                public PublishModel()
                {
                    Warnings = new List<string>();
                }
            }

            public class PackageModel
            {
                public string Name { get; set; }
                public string Path { get; set; }

                public IList<string> Warnings { get; set; }

                public string SafeName
                {
                    get {

                        if (Name == null)
                        {
                            return "";
                        }

                        return Name
                        .Replace(" ", "_")
                        .Replace(".", "_");
                    }
                    
                }

                public string Status
                {
                    get
                    {
                        if (Warnings.Any())
                        {
                            return WARNING;
                        }

                        return SUCCESS;
                    }
                }

                public string MatchedName { get; set; }

                public bool Exists { get; set; }

                public bool Corrupt { get; set; }

                public bool Used { get; set; }

                public DateTime? InstalledDate { get; set; }

                public IDictionary<string, string> Properties { get; set; }

                public IList<string> Entries { get; set; }

                public IList<string> Items { get; set; }

                public const string PACKAGE = "metadata/sc_name.txt";
                public const string PACKAGEAUTHOR = "metadata/sc_author.txt";
                public const string PACKAGEVERSION = "metadata/sc_version.txt";

                public string PackageName
                {
                    get
                    {
                        return Property(PACKAGE);
                    }
                }

                public string PackageVersion
                {
                    get
                    {
                        return Property(PACKAGEVERSION);
                    }
                }

                public string PackageAuthor
                {
                    get
                    {
                        return Property(PACKAGEAUTHOR);
                    }
                } 

                private string Property(string key)
                {
                    if(Properties.Keys.Contains(key))
                    {
                        return Properties[key];
                    }

                    return null;
                }

                public PackageModel()
                {
                    Properties = new Dictionary<string, string>
                    {
                        { "installer/version", "" },
                        { "installer/project", "" },
                        { PACKAGEAUTHOR, "" },
                        { "metadata/sc_comment.txt", "" },
                        { "metadata/sc_license.txt", "" },
                        { PACKAGE, "" },
                        { "metadata/sc_packageid.txt", "" },
                        { "metadata/sc_poststep.txt", "" },
                        { "metadata/sc_publisher.txt", "" },
                        { "metadata/sc_readme.txt", "" },
                        { "metadata/sc_revision.txt", "" },
                        { PACKAGEVERSION, "" }
                    };

                    Items = new List<string>();
                    Entries = new List<string>();
                    Warnings = new List<string>();
                }

            }
        </script>

        <meta charset="utf-8" />
        <title>Sitecore Release Manager</title>
        <link href="bootstrap-5.3.1.css" rel="stylesheet" >
    </head>
    
    <body>
        <h1 class="text-bg-secondary p-3">Release manager</h1>
        
        <% if (Sitecore.Context.User.IsAdministrator)
           {
               var releaseManager = new ReleaseManager(Page);

               releaseManager.CreateReleases();

               releaseManager.Process();

               var row = "class=\"row w-100 mb-2 \"";

                %>
                   
                <% foreach(var message in releaseManager.Messages) { %>
                    <div class="alert alert-<% = message.MessageTypeString%>" role="alert">
                        <%= message.Content %>
                    </div>                
                <% } %>            
                <br/>
                
                <form method="POST">

        
                <div class="accordion" id="releases">
                <%
                    var releaseNumber = -1;
                    foreach (var release in releaseManager.Releases.OrderByDescending(o => o.Name))
                    {
                        releaseNumber += 1;

                %>
                        <div class="accordion-item">
                            <h2 class="accordion-header ">
                                <button class="accordion-button" type="button" data-bs-toggle="collapse" data-bs-target="#<%= releaseNumber %>" 
                                    aria-expanded="true"     
                                    aria-controls="<%= releaseNumber %>">
                                    <h2><% = release.Name %></h2>
                                </button>
                            </h2>
                            <div id="<% = releaseNumber %>" class="accordion-collapse collapse <% = release.Active ? "show" : "" %>" data-bs-parent="#releases">
                                <div class="accordion-body">
                                    <div class="card">   
                                        <div class="card-body">
                                            <h3>Packages</h3>

                                        <table class="w-100 m-0">
                                            <tr>
                                                <td></td>
                                                <td>File Name</td>
                                                <td>Package Name</td>
                                                <td>Package Author</td>
                                                <td>Package Version</td>
                                                <td>Exists?</td>
                                                <td>Corrupt?</td>
                                                <td>InstalledDate</td>
                                            </tr>
                                            <% foreach (var package in release.PackageModels)
                                               { %>
                                        

                                                <tr>
                                                    <td>
                                                        <button type="button" onclick="toggleExpand('tr-<%= package.SafeName %>');" class="btn btn-secondary">Expand</button>

                                                    </td>
                                                    <td>
                                                        <span class="badge bg-<%= package.Status %> txt-">
                                                            <%= package.Name %>
                                                        </span>
                                                    </td>
                                                    <td><%= package.PackageName %></td>
                                                    <td><%= package.PackageAuthor %></td>
                                                    <td><%= package.PackageVersion %></td>
                                                    <td><%= package.Exists %></td>
                                                    <td><%= package.Corrupt %></td>
                                                    <td><%= package.InstalledDate %></td>
                                                    <td>
                                                        <button name="action" class="btn btn-danger mr-2" type="submit" 
                                                                value="<% = releaseManager.GetAction(ActionTypeEnum.DeletePackage, release, package) %>"
                                                            >Delete</button>

                                                        <% if (package.Exists)
                                                           { %>                                                                    
                                                            <button name="action" class="btn btn-success mr-2" type="submit" 
                                                                    value="<% = releaseManager.GetAction(ActionTypeEnum.Install, release, package) %>"
                                                                    >Install</button>
                                                        <% } %>
                                                    </td>
                                                </tr>
                                                <tr id="tr-<%= package.SafeName %>" style="display:none;">
                                                    
                                                        <td colspan="10" class="fw-bold">
                                                            <div class="mb-2 p-3">
                                                                <h4>Warnings </h4>
                                                                <% foreach (var key in package.Warnings)
                                                                   { %>
                                                                    <span class="badge bg-<% = WARNING %>"><%= key %></span><br/>
                                                                <% } %>
                                                                <br/>
                                                                <h4>Items</h4>
                                                                <% foreach (var key in package.Items.OrderBy(o => o))
                                                                   { %>
                                                                    <%= key %><br/>
                                                                <% } %>
                                                            </div>
                                                        </td>
                                                </tr>
                                            <% } %>
                                            <tr>
                                                <td>
                                                    
                                                </td>
                                                <td>
                                                    <select name="NewPackage_<% = release.Index %>" class="form-select" aria-label="Default select example" onchange="NewPackageButton_<% = release.Index %>.disabled = this.value === ''">
                                                        <option value=""><strong>Please select a package to add to this release:</strong></option>
                                                        <% foreach (var item in releaseManager.PackagesAvailable.Where(w => !w.Used).OrderBy(o => o.Name)) { %>
                                                            <option ><% = item.Name %></option>
                                                        <% } %>
                                                        <option value=""></option>
                                                        <option value=""><strong>Packages already used in other releases:</strong></option>
                                                        <% foreach (var item in releaseManager.PackagesAvailable.Where(w => w.Used).OrderBy(o => o.Name)) { %>
                                                            <option ><% = item.Name %></option>
                                                        <% } %>
                                                    </select>
                                                </td>
                                                <td></td>
                                                <td></td>
                                                <td></td>
                                                <td></td>
                                                <td></td>
                                                <td></td>
                                                <td>
                                                    <button id="NewPackageButton_<%= release.Index %>" name="action" class="btn btn-success mr-2" type="submit" 
                                                            value="<% = releaseManager.GetAction(ActionTypeEnum.AddPackage, release) %>"
                                                            disabled
                                                            >Add</button>
                                                </td>
                                            </tr>
                                        </table>
                                        <br/>

                                        <h3>Publishing</h3>
                                        
                                            <div class="w-100 m-0 mb-3">
                                                <div <%= row %>>
                                                    <div class="col">
                                                        &nbsp;
                                                    </div>
                                                    <div class="col-9">
                                                        Folder
                                                    </div>
                                                    <div class="col">
                                                        Sub Items?
                                                    </div>
                                                    <div class="col">&nbsp;</div>
                                                </div>
                                                <% foreach(var publish in release.Publishing.OrderBy(o => o.Path)) { %>
                                                    <div <%= row %>>
                                                        <div class="col">
                                                            <button type="button" onclick="toggleExpand('row-<% = release.Index %>-<%= release.Publishing.IndexOf(publish) %>');" class="btn btn-secondary">Expand</button>
                                                        </div>
                                                        <div class="col-9">
                                                            
                                                            <span class="badge bg-<%= publish.Status %>">
                                                                <%=publish.Path %>
                                                            </span>
                                                        </div>
                                                        <div class="col">
                                                            <input 
                                                                   disabled=""
                                                                   class="form-check-input" 
                                                                   type="checkbox" 
                                                                   value="true" 
                                                                    <% = publish.SubItems ? "checked" : "" %>>
                                                        </div>
                                                        <div class="col">
                                                            <button  name="action" class="btn btn-danger mr-2" type="submit" 
                                                                    value="<% = releaseManager.GetAction(ActionTypeEnum.DeletePublish, release, null, release.Publishing.IndexOf(publish)) %>"
                                                            >Delete</button>
                                                        </div>
                                                    </div>
                                                    <div <%= row %> id="row-<%= release.Index %>-<%=release.Publishing.IndexOf(publish) %>" style="display: none;">
                                                        <div class="col-12">
                                                            <div class="mb-2 p-3">
                                                                <h4>Warnings </h4>
                                                                <% foreach (var key in publish.Warnings)
                                                                   { %>
                                                                    <span class="badge bg-<% = WARNING %>"><%= key %></span><br/>
                                                                <% } %>
                                                            </div>
                                                        </div>
                                                        
                                                    </div>
                                                <% } %>
                                                <div <%= row %>>
                                                    <div class="col">&nbsp;</div>
                                                    <div class="col-9">
                                                        <input name="NewPublishPath_<% = release.Index %>" 
                                                               class="form-control" onchange="NewPublisButton_<% = release.Index %>.disabled = this.value === ''">
                                                        </input>
                                                    </div>
                                                    <div class="col">
                                                        <div class="form-check">
                                                            <input name="NewPublishSub_<% = release.Index %>" 
                                                                   class="form-check-input" 
                                                                   type="checkbox" 
                                                                   value="true" id="NewPublish_<% = release.Index %>">
                                                        </div>
                                                    </div>
                                                    <div class="col">
                                                        <button id="NewPublisButton_<%= release.Index %>" name="action" class="btn btn-success mr-2" type="submit" 
                                                                value="<% = releaseManager.GetAction(ActionTypeEnum.AddPublish, release) %>"
                                                                disabled
                                                        >Add</button>
                                                    </div>
                                                </div>
                                            </div>   
                                            <div class="d-flex flex-row justify-content-between">
                                                <button name="action" class="btn btn-danger" type="submit" 
                                                        value="<% = releaseManager.GetAction(ActionTypeEnum.DeleteRelease, release) %>"
                                                >Delete</button>
                                                <button name="action" class="btn btn-success" type="submit" 
                                                        value="<% = releaseManager.GetAction(ActionTypeEnum.Publish, release) %>"
                                                >Publish</button>
                                            </div>
                                            
                                        </div>
                                        
                                    </div>
                                </div>
                            </div>
                        </div>

                          
                    <%
                   }
               %>
                
                    <div class="accordion-item">
                        <h2 class="accordion-header ">
                            <div class="row accordion-header">
                                <div class="col-11">
                                    <input name="NewRelease" 
                                           type="text"
                                           class="form-control" 
                                           onchange="NewReleaseButton.disabled = this.value === ''">
                                    </input>
                                </div>
                                <div class="col">
                                    <button type="submit" disabled="disabled"
                                            id="NewReleaseButton"
                                            name="action"
                                            class="btn btn-success"
                                            value="<% = releaseManager.GetAction(ActionTypeEnum.AddRelease, null) %>"
                                                >
                                        Add Release
                                    </button>
                                </div>
                            </div>
                            

                            
                        </h2>
                    </div>
                </div>
                </form>
               
        <% } %>
        <% else { %>
            Sorry this page is only accessible by administrators
        <% } %>
    
        <script src="bootstrap-5.3.1.js"></script>

        <script >                        
            function toggleExpand(elementName) {
                var element = document.getElementById(elementName);
                if (!element) {
                    return;
                }

                if (element.style.display == '') {
                    element.style.display = 'none';
                    return;
                }

                element.style.display = '';
            }
        </script>
    </body>
</html>