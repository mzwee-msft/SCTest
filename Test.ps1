Param(
  [Parameter(Mandatory=$true)]
  [String] $SourceControlName,

  [Parameter(Mandatory=$true)]
  [Object] $SourceControlInfo
)

$SourceControlRunbookName = "VSTSGit.ps1"
$InformationalLevel = "Informational"
$WarningLevel = "Warning"
$ErrorLevel = "Error"
$SucceededLevel = "Succeeded"
$SourceControlAccountId = "f819de14-a688-45ca-9d82-56f03ea6ec64"
$SourceControlJobId = "f819de14-a688-45ca-9d82-56f03ea6ec65"

function Write-Tracing
{
  Param
  (
    [ValidateNotNullOrEmpty()]
    [string] $Level,
    [ValidateNotNullOrEmpty()]
    [string] $Message 
  )

  if ($Level -eq $InformationalLevel)
  {
    [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookInformational($SourceControlRunbookName, $SourceControlAccountId, $SourceControlJobId, $Message)
  }
  elseif ($Level -eq $WarningLevel)
  {
    [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookWarning($SourceControlRunbookName, $SourceControlAccountId, $SourceControlJobId, $Message)
  }
  elseif ($Level -eq $ErrorLevel)
  {
    [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookError($Using:SourceControlRunbookName, $Using:SourceControlAccountId, $Using:SourceControlJobId, $Message)
  }
  elseif ($Level -eq $SucceededLevel)
  {
    [Orchestrator.Shared.Shared.TraceEventSource]::Log.SourceControlRunbookSucceeded($Using:SourceControlRunbookName, $Using:SourceControlAccountId, $Using:SourceControlJobId)
  }
}

function Get-TFSBasicAuthHeader
{
  Param
  (
    [string]
    $AccessToken,
    [string]
    $Account
  )

  # Set up authentication to be used against the Visual Studio Online account
  $VSAuthCredential = ":" + $AccessToken
  $VSAuth = [System.Text.Encoding]::UTF8.GetBytes($VSAuthCredential)
  $VSAuth = [System.Convert]::ToBase64String($VSAuth)
  $AuthHeader = @{Authorization=("Basic {0}" -f $VSAuth)}

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
  $headers = SetBasicAuthHeader -Username $Connection.Username -Password $Connection.Password -Account $Connection.Account 

  $Result = Invoke-RestMethod -Uri $Uri -headers $headers -Method Get

  # Return array values to make them more PowerShell friendly
  if ($Result.value -ne $null)
  {
    $Result.value
  }
  else 
  {
    $Result
  }
}

function Get-TFSGitFolderItem
{
  param
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
    $Folder,

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

  #$Uri = "https://" + $Connection.Account + ".visualstudio.com/defaultcollection/_apis/git/$Project/repositories/$Repo/items"
  $Project = $RepoConnectionInfo.RepoName
  $Repo = $RepoConnectionInfo.RepoName
  $Uri = "https://" + $RepoConnectionInfo.AccountName + "/defaultcollection/_apis/git/$Project/repositories/$Repo/items"


  Write-Tracing -Level $InformationalLevel -Message "Uri: $Uri"
  Invoke-TFSGetRestMethod -Connection $Connection -Uri $Uri -QueryString "&versionType=Branch&version=$Branch&scopePath=$Folder&recursionLevel=$RecurseLevel"
} 


function Get-TFSGitFile
{
  param
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
    $Path,

    [Parameter(Mandatory=$false)]
    [String]
    $LocalPath
  )

  #$Uri = "https://" + $Connection.Account + ".visualstudio.com/DefaultCollection/_apis/git/repositories/$RepoID/blobs/$BlobObjectID"
  $Uri = "https://" + $RepoConnectionInfo.AccountName + "/DefaultCollection/_apis/git/repositories/$RepoID/blobs/$BlobObjectID"

  Write-Tracing -Level $InformationalLevel -Message "Uri: $Uri"
  $Result = Invoke-TFSGetRestMethod -Connection $Connection -Uri $Uri -QueryString "&scopePath=$Path"

  # If local path is specified, create the file in that directory and return the full path
  if ($LocalPath)
  {
    $FileName = Split-Path $Path -Leaf
    $FilPath = Join-Path $LocalPath $FileName
    $Result | Set-Content -Encoding Default -Path $FilPath -Force
    $FilPath
  }
  else
  {
    $Result
  }
} 

# $RepoUrl = "https://francisco-gamino.visualstudio.com/DefaultCollection/_git/MyGitRepo"
function Get-GitRepoInformation
{
  param
  (
    [Parameter(Mandatory=$true)]
    [String]
    $RepoUrl
  )

  # Process the Url
  $Parts = $RepoUrl -split "/"
  $RepoName = $parts[$parts.Length - 1]
  $AccountName = $Parts[2]

  $RepoInfoValues = @{"AccountName"=$AccountName;"RepoName"=$RepoName}
  return $RepoInfoValues    
}

function Get-TFSGitRepo
{
  [CmdletBinding(DefaultParameterSetName="UseConnectionObject")]
  param
  (

    [Parameter(ParameterSetName="UseConnectionObject", Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [Hashtable]
    $Connection,

    [Parameter(ParameterSetName="UseConnectionObject", Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [Hashtable]
    $RepoConnectionInfo
  )

  try
  {
    Write-Tracing -Level $InformationalLevel -Message "Get the VSTSGit Repo information"
    #$Uri = "https://" + $Connection.Account + ".visualstudio.com/DefaultCollection/$Project/_apis/git/repositories/$Repo"
    $RepoName = $RepoConnectionInfo.RepoName
    $Uri = "https://" + $RepoConnectionInfo.AccountName + "/DefaultCollection/$RepoName/_apis/git/repositories/$RepoName"
    $GitRepo = Invoke-TFSGetRestMethod -Connection $Connection -Uri $Uri
    return $GitRepo
  }
  catch [System.Net.WebException]
  {
    if ($_[0].Exception.Message -match "404")
    {
      # TODO: Do we need to localize the error messages?
      $errorId = "RepoNotFound"
      $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidData
      $errorMessage = "VSTS Git repository {0} not found." -f $Repo
      $exception = [System.InvalidOperationException]::New($errorMessage)
      $errorRecord = [System.Management.Automation.ErrorRecord]::New($exception, $errorId, $errorCategory, $null)
      $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    else 
    { 
      throw 
    }
  }
}

function SetBasicAuthHeader
{
  Param
  (
    [ValidateNotNullOrEmpty()]
    [String] $Password,
    [string] $Username       
  )

  if ([string]::IsNullOrEmpty($Username))
  {
    $VSAuthCredential =  ":" + $Password
  }
  else
  {
    $VSAuthCredential = $Username + ":" + $Password
  }

  # Set up authentication for use against the Visual Studio Online account
  # This needs to be enabled on your account - http://www.visualstudio.com/en-us/integrate/get-started/auth/overview 
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
    $UserName,
    [ValidateNotNullOrEmpty()]
    [string]
    $Password
  )

  $ConnectionValues = @{"UserName"=$UserName;"Password"=$Password}
  return $ConnectionValues
}

# Get the API version to use against Visual Studio Online
function GetAPIVersion
{
  "?api-version=1.0"
}

function ImportRunBook
{
  Param
  (        
    [ValidateNotNullOrEmpty()]
    $Connection,
    [ValidateNotNullOrEmpty()]
    $RepoInformation,
    [ValidateNotNullOrEmpty()]
    [string]
    $GitBranch,
    [ValidateNotNullOrEmpty()]
    $RepoConnectionInfo
  )


  try
  {
    Write-Tracing -Level $InformationalLevel -Message "Importing runbooks to the user automation account"

    # Create temp folder to store VS PowerShell scripts
    $PSFolderPath = Join-Path $env:temp  (new-guid).Guid
    New-Item -ItemType Directory -Path $PSFolderPath | Write-Verbose

    #$ChangedFiles = Get-TFSGitFolderItem -Connection $Connection -Project $VSProject -Folder $Folder -Branch $GitBranch -Repo $GitRepo
    Write-Tracing -Level $InformationalLevel -Message "Get the list of files in the repo path"
    $ChangedFiles = Get-TFSGitFolderItem -Connection $Connection -Folder $Folder -Branch $GitBranch -RepoConnectionInfo $RepoConnectionInfo
    foreach ($File in $ChangedFiles)
    {
      if (-not $File.isFolder)
      {
        if ($File.path -match ".ps1")
        {
          Write-Tracing -Level $InformationalLevel -Message ("File to sync: " + $File.path)

          $PSPath = Get-TFSGitFile -Connection $Connection -RepoConnectionInfo $RepoConnectionInfo -RepoID $RepoInformation.id -BlobObjectID $File.objectID -Path $File.Path -LocalPath $PSFolderPath
          Write-Tracing -Level $InformationalLevel -Message ("Syncing file: " + $File.path)              
          $Definition = Get-Content $PSPath
          $RunbookName = Split-Path $PSPath -Leaf 

          Set-AutomationRunbook -Name $RunbookName -Definition $Definition

          #write-host "Set-AutomationRunbook -Name $RunbookName -Definition $Definition"  -ForegroundColor Yellow
        }
        else
        {
          $Message = "Skipping file " + $File.path
          Write-Tracing -Level $InformationalLevel -Message $Message
        }
      }
    }
  }
  finally
  {
    if (Test-Path $PSFolderPath)
    {
      Remove-Item $PSFolderPath -Recurse -Force -ea SilentlyContinue
    }
  }
}

try
{
  # Setting variables
  Write-Tracing -Level $InformationalLevel -Message "Setting Source Control object properties"
  $RepoUrl = $SourceControlInfo.RepoUrl
  $GitBranch = $SourceControlInfo.Branch
  $Folder = $SourceControlInfo.Path

  Write-Tracing -Level $InformationalLevel -Message "RepoUrl:$RepoUrl, GitBranch:$GitBranch, Folder:$Folder"

  # Get the access token
  Write-Tracing -Level $InformationalLevel -Message "Gettting the AccessToken"

  $cred = Get-AutomationPSCredential -Name $SourceControlName
  $AccessToken = $cred.GetNetworkCredential().Password

  if (!$AccessToken)
  {
    throw "Variable $VSAccessTokenVariableName not found. Create this secure variable that holds your access token"
  }

  # Set the connection variables
  Write-Tracing -Level $InformationalLevel -Message "Setting connection values. Calling Set-ConnectionValues"
  $Connection = Set-ConnectionValues -Password $AccessToken

  Write-Tracing -Level $InformationalLevel -Message "Calling Get-GitRepoInformation"
  $RepoConnectionInfo = Get-GitRepoInformation -RepoUrl $RepoUrl

  # Get the repo infomation
  Write-Tracing -Level $InformationalLevel -Message "Calling Get-TFSGitRepo"
  $RepoInformation = Get-TFSGitRepo -Connection $Connection -RepoConnectionInfo $RepoConnectionInfo

  Write-Tracing -Level $InformationalLevel -Message "Import RunBooks to automation account"
  ImportRunBook -Connection $Connection -RepoInformation $RepoInformation `
            -AutomationAccountName $AutomationAccountName -ResourceGroup $ResourceGroup `
            -GitBranch $GitBranch -RepoConnectionInfo $RepoConnectionInfo
}
catch
{
  throw $_
}
