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
        [string] $path
    )
    
}

function Use-Script {
    param (
        [ValidateNotNullOrEmpty()]
        [string] $path
    )
    
}


Export-ModuleMember -Function * -Alias * -Variable routeRegister
