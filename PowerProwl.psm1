#Send Prowl alerts natively using PowerShell

function Invoke-ProwlApi
{
	# This function is what is called by the expored 'Advanced Functions'
	# to actually talk to the Prowl Api.
	[CmdletBinding()]
	param(
		[System.Collections.Specialized.NameValueCollection] $ProwlPayload,
		[String] $ProwlApiUrl,
		[String] $Method
	)
	
	# create a new web client object
	$WebClient = New-Object Net.Webclient
	
	foreach ($Key in $ProwlPayload) {
			Write-Verbose "$Key = $($ProwlPayload[$Key])"
		}
	
	# send the data to Prowl's API
	try 
	{
		if ($Method -eq "Post")
		{
			Write-Verbose "Attempting to send notification to $ProwlApiUrl"
			$Response = $WebClient.UploadValues($ProwlApiUrl,$ProwlPayload)
		}
		elseif ($Method -eq "Get")
		{
			# make sure ProwlApimarams are empty
			$ProwlApiParams =""
			
			# convert the dictionary object into url parameters
			foreach ($Key in $ProwlPayload) 
			{
				Write-Verbose "$Key = $($ProwlPayload[$Key])"
				if ($ProwlApiParams)
				{
					$ProwlApiParams = "$ProwlApiParams&$Key=$($ProwlPayload[$Key])"
				}
				else
				{
					$ProwlApiParams = "$Key=$($ProwlPayload[$Key])"	
				}
			}
			Write-Verbose "Connecting to $($ProwlApiUrl)?$ProwlApiParams"
			$Response = $WebClient.DownloadData("$($ProwlApiUrl)?$ProwlApiParams")
		}
		
		if ($Response)
		{
			Write-Verbose "HTTP $Method successful"
			$StatusCode = $Response.StatusCode -as [int]
			$PostSuccess = $true
		}
		else
		{
			$PostSucces = $false
		} 
	} 
	catch 
	{
		#throw "Error sending notification" 
		Write-Verbose "HTTP $Method failed"
		Write-Verbose $_.Exception.Message
		$PostSuccess = $false
		$StatusCode = $_.Exception.InnerException.Response.StatusCode -as [Int]
	}

	if ($PostSuccess)
	{
		# webclient returns binary data, so
		# it must be converted to UTF-8
		$Encode = New-Object System.Text.UTF8Encoding
		[xml]$XmlReturn = $Encode.GetString($Response)

		# parse the XML returned from Prowl
		if ($XmlReturn.Prowl.Success) 
		{
			Write-Verbose "Successfuly submitted request to the Prowl Server"
			$StatusCode = $XmlReturn.Prowl.Success.Code
			$Remaining = $XmlReturn.Prowl.Success.Remaining
			$UnixDate = [Int] $XmlReturn.Prowl.Success.ResetDate
			$ResetDate = [Timezone]::CurrentTimeZone.ToLocalTime(([Datetime]'1/1/1970').AddSeconds($UnixDate)) 
			$Success = $true
			$RetrievedToken = $false
			$RetrievedUrl = $false
			$RetrievedApiKey = $false
			
			# check to see if prowl returned a registration token
			if ($XmlReturn.Prowl.Retrieve.Token)
			{
				Write-Verbose "Prowl returned a registration token"
				$RetrievedToken = $XmlReturn.Prowl.Retrieve.Token
				$RetrievedUrl = $XmlReturn.Prowl.Retrieve.Url
			}
			# check to see if prowl returned an API key
			elseif ($XmlReturn.Prowl.Retrieve.ApiKey)
			{
				Write-Verbose "Prowl returned an APIKey"
				$RetrievedApiKey = $XmlReturn.Prowl.Retrieve.ApiKey
			}
		}

		# this section will probably never be called, but is left for the sake
		# of completeness.
		elseif ($XmlReturn.Prowl.Error) 
		{
			Write-Verbose "Errorcode: $XmlReturn.Prowl.Error.Code"
			Write-Verbose "Error Message: $XmlReturn.Prowl.Error.Get_InnerText()"
			$StatusCode = $XmlReturn.Prowl.Error.Code
			$StatusMessage = $XmlReturn.Prowl.Error.Get_InnerText()
			$Success = $false
		} 
	}
	else
	{
		# set static values in the event of an error
		$Remaining = 0
		$ResetDate = [DateTime] "1/1/1970"
		$Success = $false
	}
	
	# associate text with the error codes.  
	switch ($StatusCode) 
	{
		200 { $StatusMessage = "Success." }
		400 { $StatusMessage = "Bad request. Invalid parameters." }
		401 { $StatusMessage = "Not authorized. Invalid API key." }
		406 { $StatusMessage = "API limit exceeded." }
		409 { $StatusMessage = "Not approved." }
		500 { $StatusMessage = "Internal server error." }
		default { $StatusMessage = "Unknown status or connection failure." }
	} 
        
	# return an error if sending the notification failed.
	# return code can be silent by setting the error action preference.
	if (-not $Success)
	{
        Write-Error $StatusMessage
	}
		
	# create a custom object to hold return values.
	$ProwlStatus = New-Object -TypeName PSObject -Property @{
		Details = $StatusMessage
		Success = $Success
		# APIKey = $ApiKey -split ","
		# moving to external function
		Remaining = $Remaining
		ResetDate = $ResetDate
		RetrievedApiKey = $RetrievedApiKey
		RetrievedToken = $RetrievedToken
		RetrievedUrl = $RetrievedUrl
	}
	
	# output object to the pipeline
	Write-Output $ProwlStatus 
} # function Invoke-ProwlApi

function Send-ProwlNotification 
{
	<#
        .Synopsis
            Sends a Prowl notification.  Prowl is a service that provides mobile 
			notifications.
        .Description
            Sends a Prowl Notification using one or multiple API Keys. Syntacticly 
			close to the official perl script, but does things in a more 
			"PowerShell way", accepting pipeline input and returning objects.
        .Parameter Apikey
            API Key, or an array of keys associated with one or multiple Prowl 
			accounts.  If omitted, will look for the key in a variable called 
			$ProwlApiKey in the global scope.
        .Parameter ApikeyFile
            File containing API keys, one per line.  Lines starting with a hash 
			mark '#' are considered comments and ignored. Helpful if you want to
			have a predefined list of APIKeys that will receive a given set of
			alerts.
		.Parameter ProviderKey
			Your provider API key. Only necessary if you have been whitelisted.
        .Parameter Priority
            Urgency of the alert. Valid values are -2 (least urgent) to 2 (most 
			urgent).
        .Parameter Url
            URL to attach to the notification.  Can be used to send a link to a
			web page, or can cause an application redirect on an iOS device.
        .Parameter Application
            The name of your application or the application generating the event.
        .Parameter Event
            The name of the event or subject of the notification.
        .Parameter Description
            A description of the event, generally terse. Can also be called with 
			-Notification to retain syntax compatibility with the official perl 
			script.
        .Example
            Send-ProwlNotification "This is my notification"
            
            Sends "This is my notification" to API key specified in the global 
			variable $ProwlApiKey, normally specified in the users powershell 
			profile ($Profile).
        .Example
            Send-ProwlNotification -apikey <40 digit api key> -description "This is my notification"
			
			Sends a Prowl notification "This is my notification" with normal priority.
        .Example
            if (-not Test-Connection 192.168.1.10 -quiet) { Send-ProwlNotification "System offline" }
            
            Uses test connection to see if an IP is online.  If it fails the connectivity test,
            an alert is pushed to the API Key specified in $ProwlApiKey.
        .Example
            Send-ProwlNotification -Apikeyfile "c:\users\joeuser\apikeyfile.txt" `
            -Description "this is the notification description" `
            -Priority 2 -Event "Test"
            
			Sends a high priority/emergency alert containing the text "this is
			the notification description" to every API Key in apikeyfile.txt
            
        .Notes
            VERSION:   1.2
            AUTHOR:    Alex McFarland
            LASTEDIT:  10/30/2011		
		.Link
			http://powerprowl.codeplex.com
			http://www.prowlapp.com
            
    #Requires -Version 2.0
    #>
	[CmdletBinding(DefaultParameterSetName = "Key")]
	param(
        [Parameter(
            ParameterSetName = "Key",
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "API Key to which notifications are sent. Each is a 40-byte hexadecimal string.")]
        [ValidateLength(40,40)]
        [String[]] $ApiKey = $ProwlApiKey,
    
        [Parameter(
            ParameterSetName = "KeyFile",
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "File Containing Prowl API keys")]
        [ValidateScript({ Test-Path $_ })] 
        [System.IO.FileInfo] $ApiKeyFile, 
		
		[Parameter(
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Provider Key.")]
        [ValidateLength(40,40)]
        [String] $ProviderKey,
    
        [Parameter(
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "An integer value ranging [-2, 2]. -2 is low, 2 is an emergency")]
        [ValidateRange(-2,2)]
        [Int] $Priority = 0,
    
        [Parameter(
            ValueFromPipelineByPropertyName=$true,
            HelpMessage = "The URL which should be attached to the notification.")]
        [String] $Url,
    
        [Parameter(
            ValueFromPipelineByPropertyName=$true,
            HelpMessage = "The name of your application or the application generating the event.")]
        [String] $Application = "PowerProwl",
    
        [Parameter(
            ValueFromPipelineByPropertyName=$true,
            HelpMessage = "The name of the event or subject of the notification.")]
        [String] $Event = "PowerShell Notification",
    
        [Parameter(
            ValueFromPipelineByPropertyName = $true,
            Position = 0,
            Mandatory = $true, 
            HelpMessage = "A description of the event, generally terse.")]
        [Alias("Notification")]
        [String] $Description = "PowerShell Notification"
    )
        
    Begin
    {
        # Configure Location of Prowl's API
        $ProwlApiUrl = "https://api.prowlapp.com/publicapi/add"

        # set $OFS to make it easy to turn an array of strings 
        # to a comma seperated list.
        $OFS = "," 
        Write-Verbose "Using paramter set: $($PsCmdlet.ParameterSetName)" 
	}

	Process 
	{
		if ($PsCmdlet.ParameterSetName -eq "None")
		{
			# in the event that no API Key was provided
			# on the command line, check for a global variable
			if ($Global:ProwlApiKey)
			{
				$ApiKey = $Global:ProwlApiKey
			}
			else
			{
				throw "No API Key supplied, and global `$ProwlApiKey global variable not defined."
			}
		}
		if ($ApiKeyFile) 
		{
			# if an ApiKeyFile was defined, read in all keys as 
			# comma seperated list.  This works because $OFS = ","
			# as the data is read in, it's filtered using where-object
			# so that lines tarted with a #mark are ignored.
			[String] $ApiKey = Get-Content $ApiKeyfile | 
			    Where-Object { 
					($_ -notmatch "^#" ) -and ( $_ -match "\w" ) 
				}
		}
		else
		{
			# if no ApiKeyfile was defined, convert the ApiKey String array
			# to a variable with comma seperated values.
			# works because $OFS = ","
			[String] $ApiKey = $ApiKey
		}

		# create an empty NameValueCollection to hold the postdata.
		$ProwlApiRequest = new-object System.Collections.Specialized.NameValueCollection

		# Add paramers to the NameValueCollection
		$ProwlApiRequest.Add('apikey',$ApiKey)
		$ProwlApiRequest.Add('priority',$Priority)
		$ProwlApiRequest.Add('application',$Application)
		$ProwlApiRequest.Add('event',$Event)
		$ProwlApiRequest.Add('description',$Description)

		if ($ProviderKey) 
		{
			$ProwlApiRequest.Add('providerkey',$ProviderKey)
		}
		
		if ($Url) 
		{
			$ProwlApiRequest.Add('url',$Url)
		} 

		Write-Verbose "Preparing to send the following payload to Prowl: "
		foreach ($Key in $ProwlApiRequest) {
			Write-Verbose "$Key = $($ProwlApiRequest[$Key])"
		}

		# call the prowl api
		$ProwlApiReturn = Invoke-ProwlApi -ProwlApiUrl $ProwlApiUrl -Method "Post" -ProwlPayLoad $ProwlApiRequest
		
		$ProwlNotificationStatus = New-Object -TypeName PSObject -Property @{
			APIKey = $ApiKey -split ","
			Success = $ProwlApiReturn.Success
			Details = $ProwlApiReturn.Details
			ResetDate = $ProwlApiReturn.ResetDate
			Remaining = $ProwlApiReturn.Remaining
		}
		
		# name the custom object type
		$ProwlNotificationStatus.PSObject.TypeNames.Insert(0,'Prowl.Notification.Status')

		# output the status to the pipeline
		$ProwlNotificationStatus
	}
} # function Send-ProwlNotification

function Test-ProwlApiKey 
{
	<#
        .Synopsis
            Tests the validity of a Prowl API key.
        .Description
            Tests the validity of a Prowl API key by querying Prowl's API.
        .Parameter Apikey
            API Key, or an array of keys associated with one or multiple Prowl 
			accounts.  If omitted, will look for the key in a variable called 
			$ProwlApiKey in the global scope.
        .Parameter ApikeyFile
            File containing API keys, one per line.  Lines starting with a hash 
			mark '#' are considered comments and ignored. Helpful if you want to
			have a predefined list of APIKeys that will receive a given set of
			alerts.
		.Parameter ProviderKey
			Your provider API key. Only necessary if you have been whitelisted.
        .Example
            Test-ProwlApiKey -Apikey XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
            
            Tests the validity of ApiKey "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"    
        .Notes
            NAME:      Test-ProwlApiKey
            VERSION:   1.2
            AUTHOR:    Alex McFarland
            LASTEDIT:  10/30/2011
		.Link
			http://powerprowl.codeplex.com/
			http://www.prowlapp.com/
            
    #Requires -Version 2.0
    #>
	[CmdletBinding(DefaultParameterSetName = "Key")]
	param(
        [Parameter(
            ParameterSetName = "Key",
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "API Key to which notifications are sent. Each is a 40-byte hexadecimal string.")]
        [ValidateLength(40,40)]
        [String[]] $ApiKey = $ProwlApiKey,
    
        [Parameter(
            ParameterSetName = "KeyFile",
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "File Containing Prowl API keys")]
        [ValidateScript({ Test-Path $_ })] 
        [System.IO.FileInfo] $ApiKeyFile,
		
		[Parameter(
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Provider Key.")]
        [ValidateLength(40,40)]
        [String] $ProviderKey
    )
        
    Begin
    {
        # Configure Location of Prowl's API
        $ProwlApiUrl = "https://api.prowlapp.com/publicapi/verify"

        # set $OFS to make it easy to turn an array of strings 
        # to a comma seperated list.
        $OFS = "," 
        Write-Verbose "Using paramter set: $($PsCmdlet.ParameterSetName)" 
	}
	
	Process 
	{
		if ($PsCmdlet.ParameterSetName -eq "None")
		{
			# in the event that no API Key was provided
			# on the command line, check for a global variable
			if ($Global:ProwlApiKey)
			{
				$ApiKey = $Global:ProwlApiKey
			}
			else
			{
				throw "No API Key supplied, and global `$ProwlApiKey global variable not defined."
			}
		}
		if ($ApiKeyFile) 
		{
			# if an ApiKeyFile was defined, read in all keys as 
			# comma seperated list.  This works because $OFS = ","
			# as the data is read in, it's filtered using where-object
			# so that lines tarted with a #mark are ignored.
			[String] $ApiKey = Get-Content $ApiKeyfile | 
			    Where-Object { 
					($_ -notmatch "^#" ) -and ( $_ -match "\w" ) 
				}
		}
		else
		{
			# if no ApiKeyfile was defined, convert the ApiKey String array
			# to a variable with comma seperated values.
			# works because $OFS = ","
			[String] $ApiKey = $ApiKey
		}

		# create an empty NameValueCollection to hold the postdata.
		$Payload = new-object System.Collections.Specialized.NameValueCollection

		# Add paramers to the NameValueCollection
		$Payload.Add('apikey',$ApiKey)
		
		if ($ProviderKey) 
		{
			$Payload.Add('providerkey',$ProviderKey)
		} 

		$ProwlApiReturn = Invoke-ProwlApi -ProwlApiUrl $ProwlApiUrl -Method "Get" -ProwlPayload $Payload

		$ProwlApiKeyStatus = New-Object -TypeName PSObject -Property @{
			APIKey = $ApiKey -split ","
			Success = $ProwlApiReturn.Success
			Details = $ProwlApiReturn.Details
			ResetDate = $ProwlApiReturn.ResetDate
			Remaining = $ProwlApiReturn.Remaining
		}
		
		# name the custom object type
		$ProwlApiKeyStatus.PSObject.TypeNames.Insert(0,'Prowl.ApiKey.Status')

		# output the status to the pipeline
		Write-Output $ProwlApiKeyStatus
	}
} # function Test-ProwlApiKey

function Get-ProwlRegistration 
{
	<#
        .Synopsis
            Gets a registration token and URL from Prowl.
        .Description
            Allows a service provider to get a registration token and URL from Prowl.  
			After a user visits the URL and approves the request, Prowl will add a new 
			ApiKey to the users Prowl account.  This ApiKey can be retrieved by the
			service provider by using Get-ProwlApiKey.
        .Parameter ProviderKey
            Your provider Key.  Required.
        .Example
            Get-ProwlRegistration -ProviderKey "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
            
            Gets a registration token and URL from Prowl.
        .Notes
            NAME:      Get-ProwlRegistration
            VERSION:   1.2
            AUTHOR:    Alex McFarland
            LASTEDIT:  10/30/2011
		.Link
			http://powerprowl.codeplex.com/
			http://www.prowlapp.com/
            
    #Requires -Version 2.0
    #>
	[CmdletBinding()]
	param(
       	[Parameter(
			ValueFromPipelineByPropertyName = $true,
			Mandatory = $true,
            HelpMessage = "Provider Key.")]
        [ValidateLength(40,40)]
        [String] $ProviderKey
    )
        
    Begin
    {
        # Configure Location of Prowl's API
        $ProwlApiUrl = "https://api.prowlapp.com/publicapi/retrieve/token"
	}

	Process 
	{
		# create an empty NameValueCollection to hold the postdata.
		$Payload = new-object System.Collections.Specialized.NameValueCollection

		# Add paramers to the NameValueCollection
		$Payload.Add('providerkey',$ProviderKey) 

		$ProwlApiReturn = Invoke-ProwlApi -ProwlApiUrl $ProwlApiUrl -Method "Get" -ProwlPayload $Payload

		$ProwlRegistrationStatus = New-Object -TypeName PSObject -Property @{
			ProviderKey = $ProviderKey
			Token = $ProwlApiReturn.RetrievedToken
			Url = $ProwlApiReturn.RetrievedUrl
			Success = $ProwlApiReturn.Success
			Details = $ProwlApiReturn.Details
			ResetDate = $ProwlApiReturn.ResetDate
			Remaining = $ProwlApiReturn.Remaining
		}
		
		# name the custom object type
		$ProwlRegistrationStatus.PSObject.TypeNames.Insert(0,'Prowl.Registration.Status')

		# output the status to the pipeline
		Write-Output $ProwlRegistrationStatus
	}
} # function Get-ProwlRegistration

function Get-ProwlApiKey
{
		<#
        .Synopsis
            Completes a Prowl registration request by retriving an API key.
        .Description
            Completes a push notification registration request. Sends a
			token (previously recieved from Prowl using Get-ProwlRegistration)
			to Prowl and retrievies an end user's API key.  Requires that the 
			user approve the request prior to API key retrieval.
        .Parameter ProviderKey
            Your provider Key.  Required.
		.Parameter Token
            Token recieved from a previous registration request.
        .Example
            Get-ProwlRegistration -ProviderKey <Provider Key> -Token <Token>
        .Notes
            NAME:      Get-ProwlApiKey
            VERSION:   1.2
            AUTHOR:    Alex McFarland
            LASTEDIT:  10/30/2011
		.Link
			http://powerprowl.codeplex.com/
			http://www.prowlapp.com/
            
    #Requires -Version 2.0
    #>
	[CmdletBinding()]
	param(
       	[Parameter(
			ValueFromPipelineByPropertyName = $true,
			Mandatory = $true,
            HelpMessage = "Provider Key.")]
        [ValidateLength(40,40)]
        [String] $ProviderKey,
		
		[Parameter(
			ValueFromPipelineByPropertyName = $true,
			Mandatory = $true,
            HelpMessage = "Provider Key.")]
        [ValidateLength(40,40)]
        [String] $Token
		
    )
        
    Begin
    {
        # Configure Location of Prowl's API
        $ProwlApiUrl = "https://api.prowlapp.com/publicapi/retrieve/apikey"
	}

	Process 
	{
		# create an empty NameValueCollection to hold the postdata.
		$Payload = new-object System.Collections.Specialized.NameValueCollection

		# Add paramers to the NameValueCollection
		$Payload.Add('providerkey',$ProviderKey) 
		$Payload.Add('token',$Token)
		
		$ProwlApiReturn = Invoke-ProwlApi -ProwlApiUrl $ProwlApiUrl -Method "Get" -ProwlPayload $Payload

		$ProwlApiKeyStatus = New-Object -TypeName PSObject -Property @{
			ApiKey = $ProwlApiReturn.RetrievedApiKey
			Success = $ProwlApiReturn.Success
			Details = $ProwlApiReturn.Details
			ResetDate = $ProwlApiReturn.ResetDate
			Remaining = $ProwlApiReturn.Remaining
		}
		
		# name the custom object type
		$ProwlApiKeyStatus.PSObject.TypeNames.Insert(0,'Prowl.ApiKey.Status')

		# output the status to the pipeline
		Write-Output $ProwlApiKeyStatus
	}
} # function Get-ProwlApiKey

Export-ModuleMember -Function Send-ProwlNotification
Export-Modulemember -Function Test-ProwlApikey 
Export-ModuleMember -Function Get-ProwlRegistration
Export-ModuleMember -Function Get-ProwlApiKey