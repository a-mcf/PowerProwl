# PowerProwl

Send Prowl notifications natively from PowerShell.

Prowl enables you to send push notifications to iOS devices. More information is available on the Prowl [home page](https://www.prowlapp.com/).

Notifications are sent to Prowl's servers and are subsequently delivered via Apple's Push Notification Service (APNS). The app is $2.99 US (as of this writing) but notifications beyond that are free, making it a very inexpensive alternative to SMS for automated alerting. It's also possible to attach a URL to the notification, which can open a link in a web browser or launch a specific application.

**Note**: PowerProwl hasn't been updated in several years, but the good news is that the API also seems to be relatively unchanged. As far as I know, everything still works. I'll do my best to fix things if they break, but my I'm no longer an iOS user. PR's are accepted.

## Use

The star of the show is the "Send-ProwlNotification" function (or script if using the standalone version).

Here is a simple example:
```powershell
Send-ProwlNotification -ApiKey <40 digit api key> -Description "This is my notification"
```

This example would send a notification to the device linked to the 40 digit api key specified in the command line above. Many more options are available. For full help, from a PowerShell prompt run:
help Send-ProwlNotification -Full

PowerProwl will look for a $ProwlApkiKey variable defined in the global scope. I set this in my powershell profile, so I can send myself quick alerts like this:

```powershell
Send-ProwlNotification "This is the notification text"
```

Starting with PowerProwl v1.2, there are three additional functions, which would be primarily used by service providers:
Test-ProwlApikey - Tests the validity of an API key.
Get-ProwlRegistration - Used by a service provider to get an registration token and URL, used to register users for push notifications.
Get-ProwlApiKey - Retrieves the API key of an end user once they have validated the URL returned by Get-ProwlRegistration.

## Allowing PowerShell to run scripts

To use either the Module or Script flavor, your PowerShell execution policy must be set to "RemoteSigned" or "Unrestricted", as by default, PowerShell will not run unsigned scripts.

To change your execution policy start PowerShell as an elevated user and run one of the following commands

Set-ExecutionPolicy "Unsigned"

or

Set-ExecutionPolicy "RemoteSigned"

I normally prefer the latter. For more information about setting the execution policy, check this link:
http://technet.microsoft.com/en-us/library/dd347628.aspx

If you choose the "RemoteSigned" option, you'll have to "unblock" the zip file. There is a great article on the "Hey Scripting Guy!" blog about just that:
http://blogs.technet.com/b/heyscriptingguy/archive/2011/04/02/scripting-wife-learns-about-unblocking-files-in-powershell.aspx
