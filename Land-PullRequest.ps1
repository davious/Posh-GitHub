[CmdletBinding()] Param(
  [Parameter(Mandatory=$True,Position=1)]
  [int]$id,

  [Parameter(Mandatory=$False,Position=2)]
  [string]$remote = "upstream",

  [Parameter(Mandatory=$False,Position=3)]
  [bool]$done = $False
)

Add-Type -AssemblyName System.Web

$user_repo = ""
$tracker = ""
$token = ""

function CallAPI( $path, $callback ) {
    $headers = @{
        UserAgent = "Posh-GitHub"
        Authorization = "token $token"
      }
    $response = Invoke-RestMethod "https://api.github.com$path" -Headers $headers
    &$callback $response

    trap [System.Net.WebException] {
        $status = ([System.Net.HttpWebResponse]$_.Exception.Response).StatusCode
        if ($status -eq "NotFound")
        {
            Write-Host -f red "Pull request doesn't exist"
            return
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
    Write-Host "Commit $pull"
}

function MergePull($pull)
{
    Write-Host "Merge $pull"
}

function GetPullData {

	$path = "/repos/$user_repo/pulls/$id"

	Write-Host -f Blue "Getting pull request details... "

    $callback = {
        param($pull)
	    if( $done ) {
            Commit $pull
        } else {
            MergePull $pull
        }
    }
    CallAPI $path $callback

    trap {
	    Write-Host -f red "Error retrieving pull request from Github."
	    break
	}
}

function GetStatus
{
    $status = Invoke-Expression "git status"
    if(([string]$status) -imatch "Changes to be committed") {
	    if ( $done ) {
		    GetPullData
	    } else {
		    Write-Host -f Red "Please commit changed files before attemping a pull/merge."
            return
	    }
    } elseif(([string]$status) -imatch "Changes not staged for commit") {
	    if ( $done ) {
            Write-Host -f Red "Please add files that you wish to commit."
            return
	    } else {
		    Write-Host -f Red "Please stash files before attempting a pull/merge."
            return
	    }
    } else {
	    if ( $done ) {
		    Write-Host -f Red "It looks like you've broken your merge attempt."
            return
	    } else {
		    GetPullData
	    }
    }
}

function Init
{
    $show = Invoke-Expression "git remote -v show $remote"
    ([string]$show) -match "(?m)^.*?URL:.*?([\w\-]+\/[\w\-]+)\.git.*?$" > $null
    $user_repo = $matches[1]
    if ( $user_repo ) {
		GetStatus
	} else {
		Write-Host -f Red "External repository not found for $remote"
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
	    Invoke-Expression "git config --global --add pulley.token $token"
        Init
    }
    else
    {
        $message = $GITHUB_API_OUTPUT | Select -ExpandProperty Message
		Write-Host -f Red "$message. $ Try again... "
		Login
    }

    trap [System.Net.WebException]
    {
        continue
    }
}

Write-Host -f Blue "Initializing... "

$token = Invoke-Expression "git config --global --get pulley.token"
$token.Trim() > $null
if($token)
{
    Init
}
else
{
    Login
}
<#




	function mergePull( pull ) {
		var repo = pull.head.repo.ssh_url,
			head_branch = pull.head.ref,
			base_branch = pull.base.ref,
			branch = "pull-" + id,
			checkout = "git checkout " + base_branch,
			checkout_cmds = [
				checkout,
				"git pull " + config.remote + " " + base_branch,
				"git submodule update --init",
				"git checkout -b " + branch
			];

		process.stdout.write( "Pulling and merging results... ".blue );

		if ( pull.state === "closed" ) {
			exit("Can not merge closed Pull Requests.");
		}

		if ( pull.merged ) {
			exit("This Pull Request has already been merged.");
		}

		// TODO: give user the option to resolve the merge by themselves
		if ( !pull.mergeable ) {
			exit("This Pull Request is not automatically mergeable.");
		}

		exec( checkout_cmds.join( " && " ), function( error, stdout, stderr ) {
			if ( /toplevel/i.test( stderr ) ) {
				exit("Please call pulley from the toplevel directory of this repo.");
			} else if ( /fatal/i.test( stderr ) ) {
				exec( "git branch -D " + branch + " && " + checkout, doPull );
			} else {
				doPull();
			}
		});

		function doPull( error, stdout, stderr ) {
			var pull_cmds = [
				"git pull " + repo + " " + head_branch,
				checkout,
				"git merge --no-commit --squash " + branch
			];

			exec( pull_cmds.join( " && " ), function( error, stdout, stderr ) {
				if ( /Merge conflict/i.test( stdout ) ) {
					exit("Merge conflict. Please resolve then run: " +
						process.argv.join(" ") + " done");
				} else if ( /error/.test( stderr ) ) {
					exit("Unable to merge.  Please resolve then retry:\n" + stderr);
				} else {
					console.log( "done.".green );
					commit( pull );
				}
			});
		}
	}

	function commit( pull ) {
		var path = "/repos/" + user_repo + "/pulls/" + id + "/commits";

		process.stdout.write( "Getting author and committing changes... ".blue );

		callAPI( path, function( data ) {
			var match,
				msg = "Close GH-" + id + ": " + pull.title + ".",
				author = JSON.parse( data )[ 0 ].commit.author.name,
				base_branch = pull.base.ref,
				issues = [],
				urls = [],
				findBug = /#(\d+)/g;

			// Search title and body for issues for issues to link to
			if ( tracker ) {
				while ( ( match = findBug.exec( pull.title + pull.body ) ) ) {
					urls.push( tracker + match[ 1 ] );
				}
			}

			// Search just body for issues to add to the commit message
			while ( ( match = findBug.exec( pull.body ) ) ) {
				issues.push( " Fixes #" + match[ 1 ] );
			}

			// Add issues to the commit message
			msg += issues.join(",");

			if ( urls.length ) {
				msg += "\n\nMore Details:" + urls.map(function( url ) {
					return "\n - " + url;
				}).join("");
			}

			var commit = [ "commit", "-a", "--message=" + msg ];

			if ( config.interactive ) {
				commit.push("-e");
			}

			if ( author ) {
				commit.push( "--author=" + author );
			}

			getHEAD(function( oldCommit ) {
				// Thanks to: https://gist.github.com/927052
				spawn( "git", commit, {
					customFds: [ process.stdin, process.stdout, process.stderr ]
				}).on( "exit", function() {
					getHEAD(function( newCommit ) {
						if ( oldCommit === newCommit ) {
							reset("No commit, aborting push.");
						} else {
							exec( "git push " + config.remote + " " + base_branch, function( error, stdout, stderr ) {
								console.log( "done.".green );
								exit();
							});
						}
					});
				});
			});
		});
	}

	function callAPI( path, callback ) {
		request.get( "https://api.github.com" + path, {
			headers: {
				Authorization: "token " + token,
				"User-Agent": "Pulley " + pkg.version
			}
		}, function( err, res, body ) {
			var statusCode = res.socket._httpMessage.res.statusCode;

			if ( err ) {
				exit( err );
			}

			if ( statusCode === 404 ) {
				exit("Pull request doesn't exist");
			}

			if ( statusCode === 401 ) {
				login();
				return;
			}

			callback( body );
		});
	}

	function getHEAD( fn ) {
		exec( "git log | head -1", function( error, stdout, stderr ) {
			var commit = ( /commit (.*)/.exec( stdout ) || [] )[ 1 ];

			fn( commit );
		});
	}

	function reset( msg ) {
		console.error( ( "\n" + msg ).red );
		process.stderr.write( "Resetting files... ".red );

		exec( "git reset --hard ORIG_HEAD", function() {
			console.log( "done.".green );
			exit();
		});
	}

	function exit( msg ) {
		if ( msg ) {
			console.error( ( "\nError: " + msg ).red );
		}

		process.exit( 1 );
	}

})();
#>
