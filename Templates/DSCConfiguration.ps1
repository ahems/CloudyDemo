
Configuration CloudyApplication {

    Import-DscResource -ModuleName xWebAdministration, xWebsite, xPSDesiredStateConfiguration, cChoco
 
     Node "Webserver" {
     
	cChocoInstaller installChoco 
	{ 
		InstallDir = "C:\choco" 
        }

        # Install the IIS role 
        WindowsFeature IIS  
        {  
            Ensure          = "Present"  
            Name            = "Web-Server"  
        }  
  
        # Install the ASP .NET 4.5 role 
        WindowsFeature AspNet45  
        {  
            Ensure          = "Present"  
            Name            = "Web-Asp-Net45"
        }
        cChocoPackageInstaller CloudyWeb 
	{            
		Name = "trivialweb" 
		Version = "1.0.0" 
		Source = “MY-NUGET-V2-SERVER-ADDRESS” 
		DependsOn = "[cChocoInstaller]installChoco", 
		"[WindowsFeature]installIIS" 
        }
        xFirewall HTTP
	{
		Name = 'WebServer-HTTP-In-TCP'
		Group = 'Web Server'
		Ensure = 'Present'
		Action = 'Allow'
		Enabled = 'True'
		Profile = 'Any'
		Direction = 'Inbound'
		Protocol = 'TCP'
		LocalPort = 80
		DependsOn = '[WindowsFeature]webServer'
	}
        Environment EnvironmentExample
        {
            Ensure = "Present"
            Name = "TestEnvironmentVariable"
            Value = "TestValue"
        }
        Registry RegistryExample
        {
            Ensure = "Present" # You can also set Ensure to "Absent"
            Key = "HKEY_LOCAL_MACHINE\SOFTWARE\ExampleKey"
            ValueName ="TestValue"
            ValueData ="TestData"
        }
        Service ServiceExample
        {
            Name = "TermService"
            StartupType = "Automatic"
        }
    }
}
