Param
(
    [Parameter(Mandatory=$true)]
    [String]
    $SourceControlName,
    
    [Parameter(Mandatory=$true)]
    [Object]
    $SourceControlInfo,
    
    [Parameter(Mandatory=$false)]
	[Switch]
    $TestMode
)

$SourceControlRunbookName = "Sync-SourceControl.ps1"
$InformationalLevel = "Informational"
$WarningLevel = "Warning"
$ErrorLevel = "Error"
$SucceededLevel = "Succeeded"

# TODO: Need to get correct valures for SourceControlAccountId and SourceControlJobId for each job that runs.
$SourceControlAccountId = "f819de14-a688-45ca-9d82-56f03ea6ec64"
$SourceControlJobId = "f819de14-a688-45ca-9d82-56f03ea6ec65"

# This function logs output to the host via Write-Verbose
#
function Write-Log
{
    Param 
    (
        [ValidateNotNullOrEmpty()]
		[String]
        $Message
    )

    $Message = "Sync-VSTSGit: - $Message"
    Write-Verbose $Message -Verbose
}

function Write-Tracing
{
	Param
    (        
        [ValidateSet("Informational", "Warning", "ErrorLevel", "Succeeded", IgnoreCase = $True)]
		[String]
        $Level,
        [ValidateNotNullOrEmpty()]
		[String]
        $Message,
        [Parameter(Mandatory=$false)]
	    [Switch]
        $DisplayMessageToUser
	)

    if (-not $TestMode)
    {
        switch ($Level)
        {
            $InformationalLevel {
                [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookInformational($SourceControlRunbookName, $SourceControlAccountId, $SourceControlJobId, $Message)
            }

            $WarningLevel {
                [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookWarning($SourceControlRunbookName, $SourceControlAccountId, $SourceControlJobId, $Message)
            }

            $ErrorLevel {
                [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookError($SourceControlRunbookName, $SourceControlAccountId, $SourceControlJobId, $Message)
            }

            $SucceededLevel {
                [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookSucceeded($SourceControlRunbookName, $SourceControlAccountId, $SourceControlJobId, $Message)
            }
        }
    }

    if ($DisplayMessageToUser)
    {
        Write-Log -message ("Level: $Level --> " + $Message)
    }
}

function Get-TFSBasicAuthHeader
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $AccessToken,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Account
    )

    # Set up authentication to be used against the Visual Studio Online account
    $VSAuthCredential = ":" + $AccessToken
    $VSAuth = [System.Text.Encoding]::UTF8.GetBytes($VSAuthCredential)
    $VSAuth = [System.Convert]::ToBase64String($VSAuth)
    $AuthHeader = @{
        Authorization = ("Basic {0}" -f $VSAuth)
    }

    return $AuthHeader
}

function Invoke-TFSGetRestMethod
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        $Connection,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Uri,
        
        [Parameter(Mandatory=$false)]
        [string]
        $QueryString
    )

    # Get the API vesion to use for REST calls
    $APIVersion = GetAPIVersion
    $Uri = $Uri + $APIVersion
    $Uri = $Uri + $QueryString
    
    # Set up Basic authentication for use against the Visual Studio Online account
    # This needs to be enabled on your account - http://www.visualstudio.com/en-us/integrate/get-started/auth/overview 
    $headers = SetBasicAuthHeader -Password $Connection.Password

    Write-Tracing -Level $InformationalLevel -Message "Invoke-RestMethod -Uri $Uri"
    $Result = Invoke-RestMethod -Uri $Uri -headers $headers -Method Get

    if ($Result.value -ne $null)
    {
        return $Result.value
    }
    else 
    {
        return $Result
    }
}

function Get-TFSGitFolderItem
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        $Connection,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        $RepoConnectionInfo,

        [Parameter(Mandatory=$true)]
        [String]
        $FolderPath,

        [Parameter(Mandatory=$true)]
        [String]
        $Branch,

        [Parameter(Mandatory=$false)]
        [Switch]
        $Recurse
    )
    
    if ($Recurse.IsPresent)
    {
        $RecurseLevel = "full"
    }
    else
    {
        $RecurseLevel = "onelevel"
    }

    $Project = $RepoConnectionInfo.ProjectName
    $Repo = $RepoConnectionInfo.RepoName
    $Uri = "https://" + $RepoConnectionInfo.AccountName + "/defaultcollection/_apis/git/$Project/repositories/$Repo/items"

    try
    {
        Invoke-TFSGetRestMethod -Connection $Connection -Uri $Uri -QueryString "&versionType=Branch&version=$Branch&scopePath=$FolderPath&recursionLevel=$RecurseLevel"
    }
    catch
    {
        $_
    }
} 
 
function Get-TFSGitFile
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        $Connection,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        $RepoConnectionInfo,

        [Parameter(Mandatory=$true)]
        [String]
        $RepoID,

        [Parameter(Mandatory=$true)]
        [String]
        $BlobObjectID,

        [Parameter(Mandatory=$true)]
        [String]
        $Path
    )

    $Uri = "https://" + $RepoConnectionInfo.AccountName + "/DefaultCollection/_apis/git/repositories/$RepoID/blobs/$BlobObjectID"
    $Result = Invoke-TFSGetRestMethod -Connection $Connection -Uri $Uri -QueryString "&scopePath=$Path"

    return $Result
} 

<#
    Parses the given RepoUrl to get the account, project and repro names. A URL will be of the form

    1) https://[youraccount].visualstudio.com/DefaultCollection/_git/[gitRepoName]
    2) https://[YourAccount].visualstudio.com/_git/[gitRepoName]
    3) https://[YourAccount].visualstudio.com/DefaultCollection/[projectName]/_git/[gitRepoName]
    4) https://[YourAccount].visualstudio.com/[projectName]/_git/[gitRepoName]

    Returns:
    Name                           Value                                                                                                                                            
    ----                           -----                                                                                                                                            
    AccountName                    MySite.visualstudio.com                                                                                                                                               
    AccountName                    MyGitRepo
    RepoName                       MyGitRepo
#>
function Get-RepoConnectionInformation
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $RepoUrl
    )

    $Uri = [Uri]::new($RepoUrl)
    $AccountName = $Uri.Host
    $ProjectName =  $Uri.Segments[-3].Replace("/", "")
    $RepoName = $Uri.Segments[-1]

    if (-not $ProjectName -or ($ProjectName -eq "DefaultCollection"))
    {
        # The Uri is of the form https://[youraccount].visualstudio.com/_git/[gitRepoName], 
        # or of the form         https://[youraccount].visualstudio.com/DefaultCollection/_git/[gitRepoName]
        # so the ProjectName is the same as the RepoName for the API calls.
        $ProjectName = $RepoName
    }

    $RepoInfoValues = @{
        "AccountName" = $AccountName
        "RepoName" = $RepoName
        "ProjectName" = $ProjectName
    }
    
    return $RepoInfoValues
}

function Get-TFSGitRepo
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        $Connection,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        $RepoConnectionInfo
    )

    try
    {
        $RepoName = $RepoConnectionInfo.RepoName
        $ProjectName = $RepoConnectionInfo.ProjectName
        $Uri = "https://" + $RepoConnectionInfo.AccountName + "/DefaultCollection/$ProjectName/_apis/git/repositories/$RepoName"
        $GitRepo = Invoke-TFSGetRestMethod -Connection $Connection -Uri $Uri

        return $GitRepo
    }
    catch [System.Net.WebException]
	{
		if ($_[0].Exception.Message -match "404")
		{
            # TODO: Do we need to localize the error messages?
            $ErrorId = "RepoNotFound"
            $ErrorCategory = [System.Management.Automation.ErrorCategory]::InvalidArgument
            $ErrorMessage = "VSTS Git repository {0} not found." -f $RepoName
            $ThrowCustomException = $true
		}
        elseif ($_[0].Exception.Message -match "401")
		{
            # TODO: Do we need to localize the error messages?
            $ErrorId = "Unauthorized"
            $ErrorCategory = [System.Management.Automation.ErrorCategory]::AuthenticationError
            $ErrorMessage = "Unauthorized, access is denied."
            $ThrowCustomException = $true
		}
        elseif ($_[0].Exception.Message -match "403")
		{
            $ErrorId = "Unauthorized"
            $ErrorCategory = [System.Management.Automation.ErrorCategory]::InvalidOperation
            $ErrorMessage = "You do not have permission to access this resource."
            $ThrowCustomException = $true
            
		}

        if ($ThrowCustomException)
        {
            $exception = [System.InvalidOperationException]::New($ErrorMessage)
            $errorRecord = [System.Management.Automation.ErrorRecord]::New($exception, $ErrorId, $ErrorCategory, $null)
            $PSCmdlet.ThrowTerminatingError($errorRecord)                
        }
        else
        { 
			throw
        }
	}
}

# Set up authentication for use against the Visual Studio Online account
# This needs to be enabled on your account - http://www.visualstudio.com/en-us/integrate/get-started/auth/overview
function SetBasicAuthHeader
{
    Param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Password      
    )

    $VSAuthCredential =  ":" + $Password    
    $VSAuth = [System.Text.Encoding]::UTF8.GetBytes($VSAuthCredential)
    $VSAuth = [System.Convert]::ToBase64String($VSAuth)
    $BasicAuthHeader = @{Authorization=("Basic {0}" -f $VSAuth)}

    return $BasicAuthHeader
}

function Set-ConnectionValues
{
    Param
    (
        [ValidateNotNullOrEmpty()]
        [string]
        $Password
    )
    
    $ConnectionValues = @{ "Password"=$Password }

    return $ConnectionValues
}

# Get the API version to use against Visual Studio Online
function GetAPIVersion
{
    "?api-version=1.0"
}

try
{
    Write-Tracing -Level $InformationalLevel -message "VSTS-Git Sync started."

    # Setting variables
    Write-Tracing -Level $InformationalLevel -Message "Setting Source Control object properties." -DisplayMessageToUser
    $RepoUrl = $SourceControlInfo.RepoUrl
    $GitBranch = $SourceControlInfo.Branch
    $FolderPath = $SourceControlInfo.FolderPath

    Write-Tracing -Level $InformationalLevel -Message "[RepoUrl = $RepoUrl] [GitBranch  = $GitBranch] [FolderPath = $FolderPath]" -DisplayMessageToUser

    # Get the access token
    Write-Tracing -Level $InformationalLevel -Message "Retrieving SecurityToken." -DisplayMessageToUser

    if ($TestMode)
    {
        $SecurityToken = "erbqh33rcw6cvv7bahf3asx2pauopixa6w5vefciwe747qqshqka"
    }
    else
    {
        $cred = Get-AutomationPSCredential -Name $SourceControlName
        $SecurityToken = $cred.GetNetworkCredential().Password
    }

    if (-not $SecurityToken)
    {
        $errorId = "UnableToRetrieveSecurityToken"
        $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidOperation
        $errorMessage = "Unable to retrieve security token"
        $exception = [System.InvalidOperationException]::New($errorMessage)
        $errorRecord = [System.Management.Automation.ErrorRecord]::New($exception, $errorId, $errorCategory, $null)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Write-Tracing -Level $InformationalLevel -Message "SecurityToken retrieved." -DisplayMessageToUser

    # Set the connection variables
    Write-Tracing -Level $InformationalLevel -Message "Setting connection values."
    $Connection = Set-ConnectionValues -Password $SecurityToken

    # Parse the repo Url to get the account, project and repo name.
    Write-Tracing -Level $InformationalLevel -Message "Parse the repo url: $RepoUrl" -DisplayMessageToUser
    $RepoConnectionInfo = Get-RepoConnectionInformation -RepoUrl $RepoUrl
    $AccountName = $RepoConnectionInfo.AccountName
    $RepoName = $RepoConnectionInfo.RepoName
    $ProjectName = $RepoConnectionInfo.ProjectName
    Write-Tracing -Level $InformationalLevel -Message "RepoInfoValues: [AccountName = $AccountName] [RepoName = $RepoName] [ProjectName = $ProjectName]" -DisplayMessageToUser

    Write-Tracing -Level $InformationalLevel -Message "Validate that the VSO Git Repro exist." -DisplayMessageToUser
    $RepoInformation = Get-TFSGitRepo -Connection $Connection -RepoConnectionInfo $RepoConnectionInfo
    Write-Tracing -Level $InformationalLevel -Message "VSOGitRepo retrieved" -DisplayMessageToUser

    Write-Tracing -Level $InformationalLevel -Message "Get the list of files in the folder to sync." -DisplayMessageToUser
    $FilesChanged = @(Get-TFSGitFolderItem -Connection $Connection -FolderPath $FolderPath -Branch $GitBranch -RepoConnectionInfo $RepoConnectionInfo)

    Write-Tracing -Level $InformationalLevel -Message ("Syncing *.ps1 files...") -DisplayMessageToUser
    $NumberOfFilesSynced = 0
    foreach ($File in $FilesChanged)
    {
        if (-not $File.isFolder)
        {
            # Remove the file extension and any special character from the file name.
            $FileInfo = [IO.FileInfo]::new($File.Path)
            $FileName = $FileInfo.BaseName

            $Message = "File " + $FileInfo.Name
            if ($File.path -match ".ps1")
            {
                $Content = Get-TFSGitFile -Connection $Connection -RepoConnectionInfo $RepoConnectionInfo -RepoID $RepoInformation.id -BlobObjectID $File.objectID -Path $File.Path
                                
                if (-not $TestMode)
                {
                    Write-Tracing -Level $InformationalLevel -Message ("Calling Set-AutomationRunbook " + $FileName)
                    Set-AutomationRunbook -Name $FileName -Definition $Content
                    Write-Tracing -Level $InformationalLevel -Message ("Set-AutomationRunbook " + $FileName + " completed")
                }
                $Message += " synced"
                $NumberOfFilesSynced++
            }
            else
            {
                $Message += " skipped"
            }
            Write-Tracing -Level $InformationalLevel -Message $Message -DisplayMessageToUser
        }
    }
    Write-Tracing -Level $InformationalLevel -Message ("Total files synced: " + $NumberOfFilesSynced) -DisplayMessageToUser
}
catch 
{
    throw $_
}

Write-Tracing -Level $InformationalLevel -Message "Script execution completed." -DisplayMessageToUser
