# sitecore-release-manager
A quick and dirty release manager for Sitecore.

Designed to be 1-page drop in (with some CSS / JS from bootstrap to give it a bit of style) that lets you build and deploy Sitecore releases containing multiple packages, and allowing you to quickly define Sitecore paths that should be published to go along with these packages.

Intended to be used firstly by developers to source control packages that are part of their work flow, and define which relases they should be deployed in. It's designed to be deployed within the sitecore admin folder, and the contents of the <Sitecore Website Path>\sitecore\admin\releases folder should then be source-controlled. On top of this - I'd reccomend source-controlling <Sitecore Website Path>\App_Data\packages - and adding packages to be deployed here. The release manager then allows you to group these packages based on when they should be installed, and ensure that for each release that hits QA and then PROD, the same packages get installed, and the same paths are then published. 

This is *not* intended as a replacement for great tools like Unicorn, but lets you deploy content and confirm that that content has been deployed and then published correctly. If you aren't yet using source control for things like templates - then please look into Unicorn / Sitecore Content Serialization as a first port of call. As a stop gap - this tool may work as a temporary replacement tool and allow developers to install each others packages and publish the correct Sitecore nodes during a development and release work flow. 

Feel free to ping me with suggestions - I built thiis for a project after realising the need for a quick solution for a client.

Quick screen grab 

![image](https://github.com/jamesmcmunn/sitecore-release-manager/assets/61057954/d01a9311-f3b4-4bf7-ab2f-d309a8bf661c)
