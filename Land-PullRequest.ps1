[CmdletBinding()] Param(
  [Parameter(Mandatory=$True,Position=1)]
  [int]$id,

  [Parameter(Mandatory=$False,Position=2)]
  [string]$remote = "upstream"
)

$user_repo = ""

<#
#!/usr/bin/env node
/*
 * Pulley: Easy Github Pull Request Lander
 * Copyright 2011 John Resig
 * MIT Licensed
 */
(function() {
	"use strict";

	var child = require("child_process"),
		http = require("https"),
		fs = require("fs"),
		prompt = require("prompt"),
		request = require("request"),
		colors = require("colors"),
		pkg = require("./package"),

		// Process references
		exec = child.exec,
		spawn = child.spawn,

		// Process arguments
		id = process.argv[ 2 ],
		done = process.argv[ 3 ],

		// Localized application references
		user_repo = "",
		tracker = "",
		token = "",

		// Initialize config file
		config = JSON.parse( fs.readFileSync( __dirname + "/config.json" ) );

	// We don't want the default prompt message
	prompt.message = "";
#>

Add-Type -AssemblyName System.Web

function GetStatus
{
    $user_repo
}

function Init()
{
    $show = Invoke-Expression "git remote -v show $remote"
    ([string]$show) -match "(?m)^.*?URL:.*?([\w\-]+\/[\w\-]+)\.git.*?$" > $null
    $user_repo = $matches[1]
    if ( $user_repo ) {
		GetStatus
	} else {
		Write-Host -F "Red" "External repository not found for $remote"
	}
}

function Login()
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
      Uri = 'https://api.github.com/authorizations';
      Method = 'POST';
      Headers = @{
        UserAgent = "Posh-GitHub"
        Authorization = 'Basic ' + [Convert]::ToBase64String(
          [Text.Encoding]::ASCII.GetBytes("$($username):$($password)"));
      }
      ContentType = 'application/json';
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
		Write-Host -F "Red" "$message. $ Try again... "
		Login
    }

    trap [System.Net.WebException]
    {
        continue
    }
}

Write-Host -F "Blue" "Initializing... "

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


	function init() {
		if ( !id ) {
			exit("No pull request ID specified, please provide one.");
		}

		exec( "git remote -v show " + config.remote, function( error, stdout, stderr ) {
		    user_repo = ( /URL:.*?([\w\-]+\/[\w\-]+)\.git/m.exec( stdout ) || [] )[ 1 ];
			tracker = config.repos[ user_repo ];

			if ( user_repo ) {
				getStatus();
			} else {
				exit("External repository not found.");
			}
		});
	}

	function getStatus() {
		exec( "git status", function( error, stdout, stderr ) {
			if ( /Changes to be committed/i.test( stdout ) ) {
				if ( done ) {
					getPullData();
				} else {
					exit("Please commit changed files before attemping a pull/merge.");
				}
			} else if ( /Changes not staged for commit/i.test( stdout ) ) {
				if ( done ) {
					exit("Please add files that you wish to commit.");

				} else {
					exit("Please stash files before attempting a pull/merge.");
				}
			} else {
				if ( done ) {
					exit("It looks like you've broken your merge attempt.");
				} else {
					getPullData();
				}
			}
		});
	}

	function getPullData() {
		var path = "/repos/" + user_repo + "/pulls/" + id;

		console.log( "done.".green );
		process.stdout.write( "Getting pull request details... ".blue );

		callAPI( path, function( data ) {
			try {
				var pull = JSON.parse( data );

				console.log( "done.".green );

				if ( done ) {
					commit( pull );
				} else {
					mergePull( pull );
				}
			} catch( e ) {
				exit("Error retrieving pull request from Github.");
			}
		});
	}

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
