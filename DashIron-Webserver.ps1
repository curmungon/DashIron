<#
.Synopsis
Starts a powershell webserver
.Description
Starts a webserver as powershell process.
Call to the root page (e.g. http://localhost:8080/) returns a powershell execution web form.
Call to: 
    /log returns the webserver logs, 
    /starttime returns the start time of the webserver, 
    /time returns the current time
    /download downloads a file,
    /upload uploads a file,
    /quit or /exit stops the webserver.
Any other call delivers the static content that fits to the path provided. If the static path is a directory, 
a file index.htm, index.html, default.htm or default.html in this directory is delivered if present.

You may have to configure a firewall exception to allow access to the chosen port, e.g. with:
	netsh advfirewall firewall add rule name="Powershell Webserver" dir=in action=allow protocol=TCP localport=8080

After stopping the webserver you should remove the rule, e.g.:
	netsh advfirewall firewall delete rule name="Powershell Webserver"
.Parameter binding
Binding of the webserver (default: 'http://localhost:8080/')
.Parameter basedir
Base directory for static content (default: the script's directory)
.Parameter openbrowser
Open the webserver's binding in a browser after startup (default: false)
.Parameter startpage
Path to open in the browser (default: the root path, an empty string)
.Parameter RunAs32
Run the session in a 32 bit shell (default: true)
.Inputs
None
.Outputs
None
.Example
DashIron-Webserver.ps1

Starts webserver with binding to http://localhost:8080/
.Example
DashIron-Webserver.ps1 "http://+:8080/"

Starts webserver with binding to all IP addresses of the system.
Administrative rights are necessary.
.Example
DashIron-Webserver.ps1 -openBrowser true -startpage 'mywebpage.html'

Starts webserver and opens the default browser to http://localhost:8080/mywebpage.html
.Example
DashIron-Webserver.ps1 -RunAs32 false

Starts webserver with binding to http://localhost:8080/ and bypasses the default RunAs32 behavior for the entire session
.Example
schtasks.exe /Create /TN "Powershell Webserver" /TR "powershell -file C:\Users\Markus\Documents\Start-WebServer.ps1 http://+:8080/" /SC ONSTART /RU SYSTEM /RL HIGHEST /F

Starts powershell webserver as scheduled task as user local system every time the computer starts (when the
correct path to the file Start-WebServer.ps1 is given).
You can start the webserver task manually with
	schtasks.exe /Run /TN "Powershell Webserver"
Delete the webserver task with
	schtasks.exe /Delete /TN "Powershell Webserver"
Scheduled tasks are always running with low priority, so some functions might be slow.
.Notes
Version 0.1, 17 April 2019
Author: Nathan Moyer
DerivedFrom: Markus Scholtes, Start-Webserver.ps1 v1.1, https://github.com/MScholtes/SysAdminsFriends/blob/master/Module/functions/Start-WebServer.ps1
#>

param(
    [string] $binding = 'http://localhost:8080/', 
    [string] $basedir = ".", 
    [switch] $openbrowser,
    [string] $startpage = "",
    $RunAs32 = $TRUE
)
<#
 a 32 bit shell is required in order to interface with 32 bit drivers. 
 the majority of MS Office installations are currently 32 bit, so the
 sensible default behavior at this time is to start with a 32 bit shell
 
 TODO: add a way to detect what type of shell needs to be run based on the connection being made, probably in the connection script

#>
# ensure $RunAs32 is a Boolean
# $RunAs32 can be changed to a switch in the future, once TRUE a less sensible default
try {
    [System.Convert]::ToBoolean($RunAs32) > $NULL
}
catch [FormatException] {
    Write-Host("$(Get-Date -Format s) Unable to convert RunAs32: $RunAs32 to Boolean. Setting to TRUE.");
    $RunAs32 = $TRUE
}

# ensure we are running in a 32-bit shell if needed
if ( ($env:PROCESSOR_ARCHITECTURE -ne "x86") -and ($RunAs32 -eq $TRUE) ) {
    & "$env:windir\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -noexit -nop -executionpolicy bypass -nologo -windowstyle normal -mta -command ".\DashIron-WebServer.ps1 -binding $binding -basedir $basedir -startpage '$startpage' $(if($openbrowser){'-openbrowser'})"
    exit
}
if ( ([IntPtr]::size -ne 4) -and ($RunAs32 -eq $TRUE) ) {
    Write-Host "$(Get-Date -Format s) Unable to start 32-bit PowerShell... Exiting"
    exit
}

# No adminstrative permissions are required for a binding to "localhost"
# $binding = 'http://localhost:8080/'
# Adminstrative permissions are required for a binding to network names or addresses.
# + takes all requests to the port regardless of name or ip, * only requests that no other listener answers:
# $binding = 'http://+:8080/'

if ($basedir -eq "") {
    # retrieve script path as base path for static content
    if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript")
    { $basedir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition }
    else # compiled with PS2EXE:
    { $basedir = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0]) }
}
# convert to absolute path
$basedir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($basedir)

# MIME hash table for static content
$mimehash = @{".avi" = "video/x-msvideo"; ".crt" = "application/x-x509-ca-cert"; ".css" = "text/css"; ".der" = "application/x-x509-ca-cert"; ".flv" = "video/x-flv"; ".gif" = "image/gif"; ".htm" = "text/html"; ".html" = "text/html"; ".ico" = "image/x-icon"; ".jar" = "application/java-archive"; ".jardiff" = "application/x-java-archive-diff"; ".jpeg" = "image/jpeg"; ".jpg" = "image/jpeg"; ".js" = "application/x-javascript"; ".mov" = "video/quicktime"; ".mp3" = "audio/mpeg"; ".mpeg" = "video/mpeg"; ".mpg" = "video/mpeg"; ".pdf" = "application/pdf"; ".pem" = "application/x-x509-ca-cert"; ".pl" = "application/x-perl"; ".png" = "image/png"; ".rss" = "text/xml"; ".shtml" = "text/html"; ".swf" = "application/x-shockwave-flash"; ".txt" = "text/plain"; ".war" = "application/java-archive"; ".wmv" = "video/x-ms-wmv"; ".xml" = "text/xml" }

$routeRegister = @{ }

# HTML answer templates for specific calls, placeholders !RESULT, !FORMFIELD, !PROMPT are allowed
$htmlResponseContents = @{
    'GET /asdf' = @"
<html><body>
	!HEADERLINE
	<pre>!RESULT</pre>
    <form method="GET" action="/">
    <!-- !!!THIS WILL ALLOW DIRECT EXECUTION WITH YOUR SHELL!!!
	<b>!PROMPT&nbsp;</b><input type="text" maxlength=255 size=80 name="command" value='!FORMFIELD'>
    <input type="submit" name="button" value="Enter">
    -->
	</form>
</body></html>
"@

}

# Set navigation header line for all web pages
$headerline = "<p><a href='/'>Command execution</a> <a href='/download'>Download file</a> <a href='/upload'>Upload file</a> <a href='/log'>Web logs</a> <a href='/starttime'>Webserver start time</a> <a href='/time'>Current time</a> <a href='/quit'>Stop webserver</a></p>"

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

function Submit-FetchData {
    param (
        # Parameter help description
        [Parameter(Mandatory)]
        [System.Net.HttpListenerRequest] $request,
        [string] $result
    )
    # upload and execute script
    # only if there is body data in the request
    if ($request.HasEntityBody) {
        #Write-Host $request.ContentType
        $contentType = $request.ContentType
        [System.IO.Stream] $body = $request.InputStream;
        [System.Text.Encoding] $encoding = $request.ContentEncoding;
        [System.IO.StreamReader] $reader = New-Object System.IO.StreamReader($body, $encoding);
        switch ($contentType) {
            'application/json' {
                [System.Object] $bodyData = $reader.ReadToEnd() | ConvertFrom-Json
                break
            }
            { $_ -like "multipart/form-data*" } { 
                Write-Host "Got Multipart Form"
                [System.Object] $bodyData = $reader.ReadToEnd()
                #[System.Net.Http.MultipartContent.MultipartFormDataContent] 
                break
            }
        }
        $body.Close();
        $reader.Close();
        #Write-Host $bodyData
        #$bodyData | Select -ExpandProperty parameter | write
        #Write-Host "End of client data."

        $requestParams = $bodyData.parameters
        # splat the params into the script
        $execute = '& "' + $bodyData.script + '"' + " -params @requestParams"
        try {
            # ... execute script
            #Write-Host "Executing $execute..."
            $result = Invoke-Expression -ErrorAction SilentlyContinue -Command $execute 2> $NULL | Out-String
        }
        catch	{ }
        if ($Error.Count -gt 0) {
            # retrieve error message on error
            $result += "`nError while executing script $sourceName`n`n"
            $result += $Error[0]
            $Error.Clear()
        }
    }
    else {
        $result = "No client data received"
    }
    return $result
}


Register-Route GET "" { 
    $localhtml = @"
        <html><body>
            !HEADERLINE
            <pre>!RESULT</pre>
            <form method="GET" action="/">
            <b>!PROMPT&nbsp;</b><input type="text" maxlength=255 size=80 name="command" value='!FORMFIELD'>
            <input type="submit" name="button" value="Enter">
            
            </form>
        </body></html>
"@
    # execute command
    # retrieve GET query string
    $formField = ''
    $formField = [uri]::UnescapeDataString(($request.Url.Query -replace "\+", " "))
    # remove fixed form fields out of query string
    $formField = $formField -replace "\?command=", "" -replace "\?button=enter", "" -replace "&command=", "" -replace "&button=enter", ""
    # when command is given...
    if (![string]::IsNullOrEmpty($formField)) {
        try {
            # ... execute command
            $result = Invoke-Expression -ErrorAction SilentlyContinue $formField 2> $NULL | Out-String
        }
        catch	{ }
        if ($Error.Count -gt 0) {
            # retrieve error message on error
            $result += "`nError while executing '$formField'`n`n"
            $result += $Error[0]
            $Error.Clear()
        }
    }
    # preset form value with command for the caller's convenience
    $localhtml = $localhtml -replace '!FORMFIELD', $formField
    # insert powershell prompt to form
    $prompt = "PS $PWD>"
    $localhtml -replace '!PROMPT', $prompt
}

Register-Route get test { try {
        $result = '<html><title>Test</title><body><div style="margin:40px;">Good Test</div></body></html>'
    }
    catch	{ }
    if ($Error.Count -gt 0) {
        # retrieve error message on error
        $result += "`nError while executing `n`n"
        $result += $Error[0]
        $Error.Clear()
    }
    $result
}

Register-Route POST mydb {
    #get data from database
    Submit-FetchData -request $request -result $result
}

Register-Route PUT mydb {
    #get data from database
    Submit-FetchData -request $request -result $result
}
 
Register-Route GET mydb-multi {
    @"
    <html><body>
        $headerline
        <form method="PUT" enctype="multipart/form-data" action="/mydb">
        <p><b>Field to Update:</b><input type="text" name="field"></p>
        <p><b>New Value:</b><input type="text" maxlength=255 size=30 name="value"></p>
        <p><b>For PK:</b><input type="text" maxlength=255 size=30 name="pk"></p>
        <input type="submit" name="button" value="Execute">
        </form>
    </body></html>
"@
}

Register-Route 'GET' '/log' { "<html><body>$headerline Log of powershell webserver:<br /><pre>$webserverLog</pre></body></html>" }
Register-Route 'GET' '/starttime' { "<html><body>$headerline Powershell webserver started at $serverStartTime</body></html>" }
Register-Route 'GET' '/time' { "<html><body>$headerline Current time: $(Get-Date -Format s)</body></html>" }
# routes for stopping the server
Register-Route 'GET' '/exit' { "<html><body>Stopped powershell webserver</body></html>" }
Register-Route 'GET' '/quit' { "<html><body>Stopped powershell webserver</body></html>" }

# Starting the powershell webserver
"$(Get-Date -Format s) Starting powershell webserver..."
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($binding)
$listener.Start()
$Error.Clear()

try {
    $serverStartTime = Get-Date -Format s
    "$serverStartTime powershell webserver listening at $binding"
    $webserverLog = "$serverStartTime powershell webserver listening at $binding.`n"
    
    if ($openbrowser -eq $TRUE) {
        Write-Host "$(Get-Date -Format s) opening $binding$startpage"
        explorer.exe "$binding$startpage"
    }
    while ($listener.IsListening) {
        # analyze incoming request
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $responseWritten = $FALSE

        # log to console
        "$(Get-Date -Format s) $($request.RemoteEndPoint.Address.ToString()) $($request.httpMethod) $($request.Url.PathAndQuery)"
        # and in log variable
        $webserverLog += "$(Get-Date -Format s) $($request.RemoteEndPoint.Address.ToString()) $($request.httpMethod) $($request.Url.PathAndQuery)`n"

        # is there a fixed coding for the request?
        $received = '{0} {1}' -f $request.httpMethod, $request.Url.LocalPath
        $htmlResponse = $htmlResponseContents[$received]
        $result = ''

        if ($routeRegister.Contains($received) ) {
            $htmlResponse = Invoke-Command -ScriptBlock $routeRegister.$received | Out-String
        }
        else {
            
            # check for known commands
            switch ($received) {
                "GET /asdf" {
                    # execute command
                    # retrieve GET query string
                    $formField = ''
                    $formField = [uri]::UnescapeDataString(($request.Url.Query -replace "\+", " "))
                    # remove fixed form fields out of query string
                    $formField = $formField -replace "\?command=", "" -replace "\?button=enter", "" -replace "&command=", "" -replace "&button=enter", ""
                    # when command is given...
                    if (![string]::IsNullOrEmpty($formField)) {
                        try {
                            # ... execute command
                            $result = Invoke-Expression -ErrorAction SilentlyContinue $formField 2> $NULL | Out-String
                        }
                        catch	{ }
                        if ($Error.Count -gt 0) {
                            # retrieve error message on error
                            $result += "`nError while executing '$formField'`n`n"
                            $result += $Error[0]
                            $Error.Clear()
                        }
                    }
                    # preset form value with command for the caller's convenience
                    $htmlResponse = $htmlResponse -replace '!FORMFIELD', $formField
                    # insert powershell prompt to form
                    $prompt = "PS $PWD>"
                    $htmlResponse = $htmlResponse -replace '!PROMPT', $prompt
                    break
                }

                default {
                    # unknown command, check if path to fil
                    # create physical path based upon the base dir and url
                    $checkDir = $basedir.TrimEnd("/\") + $request.Url.LocalPath
                    $checkFile = ""
                    if (Test-Path $checkDir -PathType Container) {
                        # physical path is a directory 
                        $indexList = "/index.htm", "/index.html", "/default.htm", "/default.html"
                        foreach ($indexName in $indexList) {
                            # check if an index file is present
                            $checkFile = $checkDir.TrimEnd("/\") + $indexName
                            if (Test-Path $checkFile -PathType Leaf) {
                                # index file found, path now in $checkFile
                                break
                            }
                            $checkFile = ""
                        }
                    }
                    else {
                        # no directory, check for file
                        if (Test-Path $checkDir -PathType Leaf) {
                            # file found, path now in $checkFile
                            $checkFile = $checkDir
                        }
                    }

                    if ($checkFile -ne "") {
                        # static content available
                        try {
                            # ... serve static content
                            $buffer = [System.IO.File]::ReadAllBytes($checkFile)
                            $response.ContentLength64 = $buffer.Length
                            $response.SendChunked = $FALSE
                            $extension = [IO.Path]::GetExtension($checkFile)
                            if ($mimehash.ContainsKey($extension)) {
                                # known mime type for this file's extension available
                                $response.ContentType = $mimehash.Item($extension)
                            }
                            else {
                                # no, serve as binary download
                                $response.ContentType = "application/octet-stream"
                                $filename = Split-Path -Leaf $checkFile
                                $response.AddHeader("Content-Disposition", "attachment; filename=$filename")
                            }
                            $response.AddHeader("Last-Modified", [IO.File]::GetLastWriteTime($checkFile).ToString('r'))
                            $response.AddHeader("Server", "Powershell Webserver/1.1 on ")
                            $response.OutputStream.Write($buffer, 0, $buffer.Length)
                            # mark response as already given
                            $responseWritten = $TRUE
                        }
                        catch	{ }
                        if ($Error.Count -gt 0) {
                            # retrieve error message on error
                            $result += "`nError while downloading '$checkFile'`n`n"
                            $result += $Error[0]
                            $Error.Clear()
                        }
                    }
                    else {
                        # no file to serve found, return error
                        $response.StatusCode = 404
                        $htmlResponse = '<html><body>Page not found</body></html>'
                    }
                }

            }
        }
        # only send response if not already done
        if (!$responseWritten) {
            # insert header line string into HTML template
            $htmlResponse = $htmlResponse -replace '!HEADERLINE', $headerline

            # insert result string into HTML template
            $htmlResponse = $htmlResponse -replace '!RESULT', $result

            # return HTML answer to caller
            $buffer = [Text.Encoding]::UTF8.GetBytes($htmlResponse)
            $response.ContentLength64 = $buffer.Length
            $response.AddHeader("Last-Modified", [DATETIME]::Now.ToString('r'))
            $response.AddHeader("Server", "Powershell Webserver/1.1 on ")
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }

        # and finish answer to client
        $response.Close()

        # received command to stop webserver?
        if ($received -eq 'GET /exit' -or $received -eq 'GET /quit') {
            # then break out of while loop
            "$(Get-Date -Format s) Stopping powershell webserver..."
            break;
        }
    }
}
finally {
    # Stop powershell webserver
    $listener.Stop()
    $listener.Close()
    "$(Get-Date -Format s) Powershell webserver stopped."
}