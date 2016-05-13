Configuration CloudyApplication {

      Node "webserver" {           

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