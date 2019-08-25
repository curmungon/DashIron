# registered routes will be added to routeRegister
# the method and route ,together, are the key the callback is the value
$routeRegister = @{ }

function Register-Route {
    param (
        [# route's HTTP method
        Parameter(Position = 0)]
        [ValidateSet('get', 'post', 'put')]
        [string] $method,
        [# route's route
        Parameter(Position = 1)]
        [ValidateNotNull()]
        [string] $route,
        [# route's action
        Parameter(Position = 2)]
        [ValidateNotNull()]
        [scriptblock] $callback

    )
    switch ($route) {
        "" { 
            $route = "/"
            break
        }
        { $route.Substring(0, 1) -ne "/" } { 
            $route = "/$route"
            break
        }

        Default { $route = $route }
    }
    
    # if ( $routeRegister.Contains("$method $route") )... 
    # duplicate entries will cause an error, allow the default error behavior
    $routeRegister.Add("$method $route", $callback)
}


function Use-Path {
    param (
        [ValidateNotNullOrEmpty()]
        [string] $path,
        [ValidateNotNullOrEmpty()]
        [scriptblock] $command        
    )
    try {
        if (Test-Path $path -PathType Container) {
            Push-Location $path
            try {
                Invoke-Command -ScriptBlock $command
            }
            catch {
                if ($Error.Count -gt 0) {
                    # retrieve error message on error
                    Write-Host $Error[0]
                    $Error.Clear()
                }
            }
            Pop-Location
        }
        else {
            throw "Invald Folder Path. Path must resolve to a vaild folder. `nPath:`n$path"
        }
    }
    catch {
        if ($Error.Count -gt 0) {
            # retrieve error message on error
            Write-Host $Error[0]
            $Error.Clear()
        }
    }

}

function Use-Script {
    param (
        # path to script file
        [Parameter(ParameterSetName = "stringPath")]
        [ValidateNotNullOrEmpty()]
        [string] $scriptpath,
        # scriptblock to use
        [Parameter(ParameterSetName = "scriptBlock")]
        [scriptblock]
        $script
    )
    if ($scriptpath) {
        try {
            # verify the path is a valid leaf and a ps1f file
            if (Test-Path -path $scriptpath -PathType Leaf -and $($scriptpath).endswith(".ps1")) {
                
            }
        }
        catch { }
    }
    elseif ($script) {
        
    }
}


Export-ModuleMember -Function * -Alias * -Variable routeRegister
