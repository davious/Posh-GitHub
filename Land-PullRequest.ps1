[CmdletBinding()] Param(
	[Parameter(Mandatory=$True)]
	[int]$id,

	[Parameter(Mandatory=$False)]
	$done = "",

	[Parameter(Mandatory=$False)]
	[string]$remote = "upstream",

    [switch]$interactive
)

Add-Type -AssemblyName System.Web

$done = ($done -imatch "done")

$user_repo = ""
$tracker = ""
$token = ""

$repo = ""
$checkout = ""
$head_branch = ""
$base_branch = ""
$branch = ""

$n = "`r`n"

function Invoke-Expression2($cmd)
{
	Try
	{
		$result = (Invoke-Expression $cmd) 2>&1
		if ($lastexitcode) {throw $result}
	}
	Catch
	{
		if ($_.FullyQualifiedErrorId -ne "NativeCommandError")
		{
			return $_.FullyQualifiedErrorId
		}
	}
	return $result
}

function GetHead {
	$last_commit_log_results = git log | head -1
	$last_commit_log_results = [string]$last_commit_log_results
	$last_commit_log_results -imatch "commit (.*)"
	return $matches[1]
}

function ResetRepository( $msg ) {
	Write-Error $msg
	Write-Error "Resetting files... "
	git reset --hard ORIG_HEAD
	Write-Host -f green "done."
}

function GetJsonFromGitHub( $path ) {
	$headers = @{
		UserAgent = "Posh-GitHub"
		Authorization = "token $token"
	}
	$response = Invoke-RestMethod "https://api.github.com$path" -Headers $headers
	return $response

	trap [System.Net.WebException] {
		$status = ([System.Net.HttpWebResponse]$_.Exception.Response).StatusCode
		if ($status -eq "NotFound")
		{
			Write-Error "Pull request doesn't exist"
		}
		if ($status -eq "Unauthorized")
		{
			Login
			return
		}
		break
	}
}

function Commit($pull)
{
	$path = "/repos/$user_repo/pulls/$id/commits"

	Write-Host -f blue "Getting author and committing changes... "

	$data = GetJsonFromGitHub $path

	$match = ""
	$msg = "Close GH-" + $id + ": " + $pull.title + "."
	$author = $data[0].commit.author.name
	$base_branch = $pull.base.ref
	$issues = @()
	$urls = @()
	$findBug = "#\d+"

	# Search title and body for issues for issues to link to
	if ( $tracker ) {
		$all_matches = ([regex]::Matches($pull.title + $pull.body, $findBug) | %{$_.value})
		foreach($match in $all_matches) {
			$urls.Add( $tracker + $match.Substring(1) )
		}
	}

	# Search just body for issues to add to the commit message
	$all_matches = ([regex]::Matches($pull.body, $findBug) | %{$_.value})
	foreach($match in $all_matches) {
		$issues.Add( " Fixes #" + $match.Substring(1) )
	}

	# Add issues to the commit message
	$msg += [string]::Join(",", $issues)

	if ( $urls.Count ) {
		$msg += "$n$($n)More Details:"
		foreach($url in $urls) {
			$msg += "$n - $url"
		}
	}

	$commit = "git commit -a --message=""$msg"""

	if ( $interactive ) {
	#	$commit += " -e"
	}

	if ( $author ) {
		$commit += " --author=""$author"""
	}

	$old_commit = GetHead
	$old_commit = $old_commit[1]
	Invoke-Expression2 $commit
	$new_commit = GetHead
	$new_commit = $new_commit[1]
	if ( $old_commit -eq $new_commit ) {
		ResetRepository "No commit, aborting push."
	} else {
		git push $remote $base_branch
		git branch -D $branch
		Write-Host -f green "done."
	}
}

function DoPull($pull) {
	$pull_cmds = @(
		"git pull $repo $head_branch"
		$checkout,
		"git merge --no-commit --squash $branch"
	)

	$squash = [string]::Join("; ", $pull_cmds)
	$squash_results = Invoke-Expression2 $squash
	$squash_results = [string]$squash_results

	if ( $squash_results -imatch "Merge conflict" ) {
		Write-Error "Merge conflict. Please resolve then run: Land-PullRequest $id done"
		return
	} else {
		Write-Host -f green "done"
		Commit $pull
	}

	trap {
		#todo test
		Write-Error "Unable to merge.  Please resolve then retry."
		break
	}
}

function MergePull($pull)
{
	Write-Host -f blue "Pulling and merging results... "

	if ( $pull.state -eq "closed" ) {
		Write-Error "Cannot merge closed Pull Requests."
		return
	}

	if ( $pull.merged ) {
		Write-Error "This Pull Request has already been merged."
		return
	}

	# TODO: give user the option to resolve the merge by themselves
	if ( !$pull.mergeable ) {
		Write-Error "This Pull Request is not automatically mergeable."
		return
	}

	$repo = $pull.head.repo.clone_url
	$head_branch = $pull.head.ref
	$base_branch = $pull.base.ref
	$branch = "pull-$id"
	$checkout = "git checkout $base_branch"
	$checkout_cmds = @(
		$checkout,
		"git pull $remote $base_branch"
		"git submodule update --init",
		"git checkout -b $branch"
	)

	$create_merge_branch = [string]::Join("; ", $checkout_cmds)
	$create_merge_branch_results = Invoke-Expression2 $create_merge_branch
	$create_merge_branch_results = [string]$create_merge_branch_results

	if ($create_merge_branch_results -imatch "toplevel")
	{
		Write-Error "Please call pulley from the toplevel directory of this repo."
		return
	} elseif ($create_merge_branch_results -imatch "fatal" ) {
		Write-Host -f yellow (git branch -D $branch)
		MergePull $pull
	} else {
		DoPull $pull
	}
}

function GetPullData {

	$path = "/repos/$user_repo/pulls/$id"

	Write-Host -f Blue "Getting pull request details... "

	$pull = GetJsonFromGitHub $path

	if( $done ) {
		Commit $pull
	} else {
		MergePull $pull
	}

	trap {
		Write-Error "Error retrieving pull request from Github."
		return
	}
}

function GetStatus
{
	$status = git status
	if(([string]$status) -imatch "Changes to be committed") {
		if ( $done ) {
			GetPullData
		} else {
			Write-Error "Please commit changed files before attemping a pull/merge."
			return
		}
	} elseif(([string]$status) -imatch "Changes not staged for commit") {
		if ( $done ) {
			Write-Error "Please add files that you wish to commit."
			return
		} else {
			Write-Error "Please stash files before attempting a pull/merge."
			return
		}
	} else {
		if ( $done ) {
			Write-Error "It looks like you've broken your merge attempt."
			return
		} else {
			GetPullData
		}
	}
}

function Init
{
	$show = Invoke-Expression2 "git remote -v show $remote"
	([string]$show) -match "(?m)^.*?URL:.*?([\w\-]+\/[\w\-]+)\.git.*?$" > $null
	if($matches) {
		$user_repo = $matches[1]
		#$tracker = $repos[ $user_repo ];
		GetStatus
	} else {
		if($remote -eq "upstream") {
			Write-Host -f yellow "External repository not found for upstream. Failing back to origin."
			$remote = "origin"
			Init
		} else {
			Write-Error "External repository not found for $remote"
		}
	}
}

function Login
{
	Write-Host "Please login with your GitHub credentials."
	Write-Host "Your credentials are only needed this one time to get a token from GitHub."
	$username = Read-Host -p "Username"
	$passwordSecure = Read-Host -p "Password" -AsSecureString
	$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
				[Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure))
	$username = [System.Web.HttpUtility]::UrlEncode($username)
	$password = [System.Web.HttpUtility]::UrlEncode($password)
	$postData = @{
		scopes = @('repo')
		note = "Pulley"
		note_url = "https://github.com/iristyle/Posh-GitHub"
	}
	$params = @{
		Uri = 'https://api.github.com/authorizations'
		Method = 'POST'
		Headers = @{
		UserAgent = "Posh-GitHub"
		Authorization = 'Basic ' + [Convert]::ToBase64String(
			[Text.Encoding]::ASCII.GetBytes("$($username):$($password)"))
		}
		ContentType = 'application/json'
		Body = (ConvertTo-Json $postData -Compress)
	}

	$global:GITHUB_API_OUTPUT = Invoke-RestMethod @params
	Write-Verbose $global:GITHUB_API_OUTPUT

	$token = $GITHUB_API_OUTPUT | Select -ExpandProperty Token
	if($token)
	{
		git config --global --add pulley.token $token
		Init
	}
	else
	{
		$message = $GITHUB_API_OUTPUT | Select -ExpandProperty Message
		Write-Error "$message. Try again... "
		Login
	}

	trap [System.Net.WebException]
	{
		continue
	}
}

Write-Host -f Blue "Initializing... "

$token = git config --global --get pulley.token
$token.Trim() > $null
if($token)
{
	Init
}
else
{
	Login
}

