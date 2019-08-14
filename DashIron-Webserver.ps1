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

# HTML answer templates for specific calls, placeholders !RESULT, !FORMFIELD, !PROMPT are allowed
$htmlResponseContents = @{
    'GET /'           = @"
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
    'GET /test'       = @"
!RESULT
"@
 
    'GET /mydb-multi' = @"
    <html><body>
	!HEADERLINE
	<form method="PUT" enctype="multipart/form-data" action="/mydb">
	<p><b>Field to Update:</b><input type="text" name="field"></p>
    <p><b>New Value:</b><input type="text" maxlength=255 size=30 name="value"></p>
    <p><b>For PK:</b><input type="text" maxlength=255 size=30 name="pk"></p>
	<input type="submit" name="button" value="Execute">
	</form>
	</body></html>
"@
    'PUT /mydb'       = @"
	!RESULT 
"@
    'POST /mydb'      = @"
	!RESULT 
"@

    <#
    'GET /download'        = @"
<html><body>
	!HEADERLINE
	<pre>!RESULT</pre>
	<form method="POST" action="/download">
	<b>Path to file:</b><input type="text" maxlength=255 size=80 name="filepath" value='!FORMFIELD'>
	<input type="submit" name="button" value="Download">
	</form>
</body></html>
"@
    'POST /download'       = @"
<html><body>
	!HEADERLINE
	<pre>!RESULT</pre>
	<form method="POST" action="/download">
	<b>Path to file:</b><input type="text" maxlength=255 size=80 name="filepath" value='!FORMFIELD'>
	<input type="submit" name="button" value="Download">
	</form>
</body></html>
"@
#>
    <#
    'GET /upload'          = @"
<html><body>
	!HEADERLINE
	<form method="POST" enctype="multipart/form-data" action="/upload">
	<p><b>File to upload:</b><input type="file" name="filedata"></p>
	<b>Path to store on webserver:</b><input type="text" maxlength=255 size=80 name="filepath">
	<input type="submit" name="button" value="Upload">
	</form>
</body></html>
"@
#>
    #    'POST /script'         = "<html><body>!HEADERLINE<pre>!RESULT</pre></body></html>"
    #    'POST /upload'         = "<html><body>!HEADERLINE<pre>!RESULT</pre></body></html>"
    'GET /exit'       = "<html><body>Stopped powershell webserver</body></html>"
    'GET /quit'       = "<html><body>Stopped powershell webserver</body></html>"
    #    'GET /log'             = "<html><body>!HEADERLINELog of powershell webserver:<br /><pre>!RESULT</pre></body></html>"
    'GET /starttime'  = "<html><body>!HEADERLINEPowershell webserver started at $(Get-Date -Format s)</body></html>"
    'GET /time'       = "<html><body>!HEADERLINECurrent time: !RESULT</body></html>"
    #    'GET /beep'            = "<html><body>!HEADERLINEBEEP...</body></html>"
}

# Set navigation header line for all web pages
$headerline = "<p><a href='/'>Command execution</a> <a href='/download'>Download file</a> <a href='/upload'>Upload file</a> <a href='/log'>Web logs</a> <a href='/starttime'>Webserver start time</a> <a href='/time'>Current time</a> <a href='/quit'>Stop webserver</a></p>"

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

        #$execute = "function Powershell-WebServer-Func {`n" + '"' + $bodyData.parameter + '"' + "`n}`nPowershell-WebServer-Func"
        $requestParams = $bodyData.parameters
        #$execute = '& "' + $bodyData.script + '"' + " -SourceTable " + $bodyData.parameters.SourceTable + " -WhereFilter " + $bodyData.parameters.WhereFilter
        # splat the params into the script
        $execute = '& "' + $bodyData.script + '"' + " -params @requestParams"
        try {
            # ... execute script
            #Write-Host "Executing $execute..."
            $result = Invoke-Expression -ErrorAction SilentlyContinue -Command $execute 2> $NULL | Out-String
            # jobs can enable multithreading.. with additoinal work
            # jobs also enable the -RunAs32 option, making forced launch of a 32-bit shell unnecessary
            # https://thesurlyadmin.com/2013/03/04/multithreading-revisited-using-jobs/
            # $execute = { Invoke-Expression '& "' + $bodyData.script + '"' + " -SourceTable " + $bodyData.parameters.SourceTable + " -WhereFilter " + $bodyData.parameters.WhereFilter }
            #$result = Start-Job -ScriptBlock $execute -RunAs32 $TRUE | Out-String
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

# Starting the powershell webserver
"$(Get-Date -Format s) Starting powershell webserver..."
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($binding)
$listener.Start()
$Error.Clear()

try {
    "$(Get-Date -Format s) powershell webserver listening at $binding"
    $webserverLog = "$(Get-Date -Format s) powershell webserver listening at $binding.`n"
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

        # check for known commands
        switch ($received) {
            "GET /" {
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
            
            "GET /test" {	
                try {
                    $result = '<html><title>Test</title><body><div style="margin:40px;">Good Test</div></body></html>'
                }
                catch	{ }
                if ($Error.Count -gt 0) {
                    # retrieve error message on error
                    $result += "`nError while executing `n`n"
                    $result += $Error[0]
                    $Error.Clear()
                }
                break
            }
            
            'PUT /mydb' {
                #submit new data
                Write-Host "PUT Request for data..."
                $result = Submit-FetchData -request $request -result $result
                break
            }

            "POST /mydb" {
                #get data from database
                $result = Submit-FetchData -request $request -result $result
                break
            }

            <#
            "GET /mydb" {
                # execute command
                # retrieve GET query string
                #$formField = ''
                #$formField = [uri]::UnescapeDataString(($request.Url.Query -replace "\+"," "))
                # remove fixed form fields out of query string
                #$formField = $formField -replace "\?command=","" -replace "\?button=enter","" -replace "&command=","" -replace "&button=enter",""
                # when command is given...
                #if (![string]::IsNullOrEmpty($formField))
                #{
                try {
                    # ... execute command
                    $result = Invoke-Expression -ErrorAction SilentlyContinue ".\webQueryTest.ps1" 2> $NULL | Out-String
                }
                catch	{ }
                if ($Error.Count -gt 0) {
                    # retrieve error message on error
                    $result += "`nError while executing `n`n"
                    $result += $Error[0]
                    $Error.Clear()
                }
                #}
                # preset form value with command for the caller's convenience
                $htmlResponse = $htmlResponse -replace '!FORMFIELD', $formField
                # insert powershell prompt to form
                $prompt = "PS $PWD>"
                $htmlResponse = $htmlResponse -replace '!PROMPT', $prompt
                break
            }
            #>

            <#
            "GET /script" {
                # present upload form, nothing to do here
                break
            }
            #>
            
            <#
            "POST /script" {
                # upload and execute script

                # only if there is body data in the request
                if ($request.HasEntityBody) {
                    # set default message to error message (since we just stop processing on error)
                    $result = "Received corrupt or incomplete form data"

                    # check content type
                    if ($request.ContentType) {
                        # retrieve boundary marker for header separation
                        $boundary = $NULL
                        if ($request.ContentType -match "boundary=(.*);")
                        {	$boundary = "--" + $matches[1] }
                        else {
                            # marker might be at the end of the line
                            if ($request.ContentType -match "boundary=(.*)$")
                            { $boundary = "--" + $matches[1] }
                        }

                        if ($boundary) {
                            # only if header separator was found

                            # read complete header (inkl. file data) into string
                            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                            $data = $reader.ReadToEnd()
                            $reader.Close()
                            $request.InputStream.Close()

                            $parameters = ""
                            $sourceName = ""

                            # separate headers by boundary string
                            $data -replace "$boundary--\r\n", "$boundary`r`n--" -split "$boundary\r\n" | ForEach-Object {
                                # omit leading empty header and end marker header
                                if (($_ -ne "") -and ($_ -ne "--")) {
                                    # only if well defined header (separation between meta data and data)
                                    if ($_.IndexOf("`r`n`r`n") -gt 0) {
                                        # header data before two CRs is meta data
                                        # first look for the file in header "filedata"
                                        if ($_.Substring(0, $_.IndexOf("`r`n`r`n")) -match "Content-Disposition: form-data; name=(.*);") {
                                            $headerName = $matches[1] -replace '\"'
                                            # headername "filedata"?
                                            if ($headerName -eq "filedata") {
                                                # yes, look for source filename
                                                if ($_.Substring(0, $_.IndexOf("`r`n`r`n")) -match "filename=(.*)") {
                                                    # source filename found
                                                    $sourceName = $matches[1] -replace "`r`n$" -replace "`r$" -replace '\"'
                                                    # store content of file in variable
                                                    $filedata = $_.Substring($_.IndexOf("`r`n`r`n") + 4) -replace "`r`n$"
                                                }
                                            }
                                        }
                                        else {
                                            # look for other headers (we need "parameter")
                                            if ($_.Substring(0, $_.IndexOf("`r`n`r`n")) -match "Content-Disposition: form-data; name=(.*)") {
                                                # header found
                                                $headerName = $matches[1] -replace '\"'
                                                # headername "parameter"?
                                                if ($headerName -eq "parameter") {
                                                    # yes, look for paramaters
                                                    $parameters = $_.Substring($_.IndexOf("`r`n`r`n") + 4) -replace "`r`n$" -replace "`r$"
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            if ($sourceName -ne "") {
                                # execute only if a source file exists

                                $execute = "function Powershell-WebServer-Func {`n" + $filedata + "`n}`nPowershell-WebServer-Func " + $parameters
                                try {
                                    # ... execute script
                                    $result = Invoke-Expression -ErrorAction SilentlyContinue $execute 2> $NULL | Out-String
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
                                $result = "No file data received"
                            }
                        }
                    }
                }
                else {
                    $result = "No client data received"
                }
                break
            }
            #>

            <#
            { $_ -like "* /download" } {
                # GET or POST method are allowed for download page
                # download file

                # is POST data in the request?
                if ($request.HasEntityBody) {
                    # POST request
                    # read complete header into string
                    $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $data = $reader.ReadToEnd()
                    $reader.Close()
                    $request.InputStream.Close()

                    # get headers into hash table
                    $header = @{ }
                    $data.Split('&') | ForEach-Object { $header.Add([uri]::UnescapeDataString(($_.Split('=')[0] -replace "\+", " ")), [uri]::UnescapeDataString(($_.Split('=')[1] -replace "\+", " "))) }

                    # read header 'filepath'
                    $formField = $header.Item('filepath')
                    # remove leading and trailing double quotes since Test-Path does not like them
                    $formField = $formField -replace "^`"", "" -replace "`"$", ""
                }
                else {
                    # GET request

                    # retrieve GET query string
                    $formField = ''
                    $formField = [uri]::UnescapeDataString(($request.Url.Query -replace "\+", " "))
                    # remove fixed form fields out of query string
                    $formField = $formField -replace "\?filepath=", "" -replace "\?button=download", "" -replace "&filepath=", "" -replace "&button=download", ""
                    # remove leading and trailing double quotes since Test-Path does not like them
                    $formField = $formField -replace "^`"", "" -replace "`"$", ""
                }

                # when path is given...
                if (![string]::IsNullOrEmpty($formField)) {
                    # check if file exists
                    if (Test-Path $formField -PathType Leaf) {
                        try {
                            # ... download file
                            $buffer = [System.IO.File]::ReadAllBytes($formField)
                            $response.ContentLength64 = $buffer.Length
                            $response.SendChunked = $FALSE
                            $response.ContentType = "application/octet-stream"
                            $filename = Split-Path -Leaf $formField
                            $response.AddHeader("Content-Disposition", "attachment; filename=$filename")
                            $response.AddHeader("Last-Modified", [IO.File]::GetLastWriteTime($formField).ToString('r'))
                            $response.AddHeader("Server", "Powershell Webserver/1.1 on ")
                            $response.OutputStream.Write($buffer, 0, $buffer.Length)
                            # mark response as already given
                            $responseWritten = $TRUE
                        }
                        catch	{ }
                        if ($Error.Count -gt 0) {
                            # retrieve error message on error
                            $result += "`nError while downloading '$formField'`n`n"
                            $result += $Error[0]
                            $Error.Clear()
                        }
                    }
                    else {
                        # ... file not found
                        $result = "File $formField not found"
                    }
                }
                # preset form value with file path for the caller's convenience
                $htmlResponse = $htmlResponse -replace '!FORMFIELD', $formField
                break
            }
            #>

            <#
            "GET /upload" {
                # present upload form, nothing to do here
                break
            }
            #>

            <#
            "POST /upload" {
                # upload file

                # only if there is body data in the request
                if ($request.HasEntityBody) {
                    # set default message to error message (since we just stop processing on error)
                    $result = "Received corrupt or incomplete form data"

                    # check content type
                    if ($request.ContentType) {
                        # retrieve boundary marker for header separation
                        $boundary = $NULL
                        if ($request.ContentType -match "boundary=(.*);")
                        {	$boundary = "--" + $matches[1] }
                        else {
                            # marker might be at the end of the line
                            if ($request.ContentType -match "boundary=(.*)$")
                            { $boundary = "--" + $matches[1] }
                        }

                        if ($boundary) {
                            # only if header separator was found

                            # read complete header (inkl. file data) into string
                            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                            $data = $reader.ReadToEnd()
                            $reader.Close()
                            $request.InputStream.Close()

                            # variables for filenames
                            $filename = ""
                            $sourceName = ""

                            # separate headers by boundary string
                            $data -replace "$boundary--\r\n", "$boundary`r`n--" -split "$boundary\r\n" | ForEach-Object {
                                # omit leading empty header and end marker header
                                if (($_ -ne "") -and ($_ -ne "--")) {
                                    # only if well defined header (seperation between meta data and data)
                                    if ($_.IndexOf("`r`n`r`n") -gt 0) {
                                        # header data before two CRs is meta data
                                        # first look for the file in header "filedata"
                                        if ($_.Substring(0, $_.IndexOf("`r`n`r`n")) -match "Content-Disposition: form-data; name=(.*);") {
                                            $headerName = $matches[1] -replace '\"'
                                            # headername "filedata"?
                                            if ($headerName -eq "filedata") {
                                                # yes, look for source filename
                                                if ($_.Substring(0, $_.IndexOf("`r`n`r`n")) -match "filename=(.*)") {
                                                    # source filename found
                                                    $sourceName = $matches[1] -replace "`r`n$" -replace "`r$" -replace '\"'
                                                    # store content of file in variable
                                                    $filedata = $_.Substring($_.IndexOf("`r`n`r`n") + 4) -replace "`r`n$"
                                                }
                                            }
                                        }
                                        else {
                                            # look for other headers (we need "filepath" to know where to store the file)
                                            if ($_.Substring(0, $_.IndexOf("`r`n`r`n")) -match "Content-Disposition: form-data; name=(.*)") {
                                                # header found
                                                $headerName = $matches[1] -replace '\"'
                                                # headername "filepath"?
                                                if ($headerName -eq "filepath") {
                                                    # yes, look for target filename
                                                    $filename = $_.Substring($_.IndexOf("`r`n`r`n") + 4) -replace "`r`n$" -replace "`r$" -replace '\"'
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            if ($filename -ne "") {
                                # upload only if a targetname is given
                                if ($sourceName -ne "") {
                                    # only upload if source file exists

                                    # check or construct a valid filename to store
                                    $targetName = ""
                                    # if filename is a container name, add source filename to it
                                    if (Test-Path $filename -PathType Container) {
                                        $targetName = Join-Path $filename -ChildPath $(Split-Path $sourceName -Leaf)
                                    }
                                    else {
                                        # try name in the header
                                        $targetName = $filename
                                    }

                                    try {
                                        # ... save file with the same encoding as received
                                        [IO.File]::WriteAllText($targetName, $filedata, $request.ContentEncoding)
                                    }
                                    catch	{ }
                                    if ($Error.Count -gt 0) {
                                        # retrieve error message on error
                                        $result += "`nError saving '$targetName'`n`n"
                                        $result += $Error[0]
                                        $Error.Clear()
                                    }
                                    else {
                                        # success
                                        $result = "File $sourceName successfully uploaded as $targetName"
                                    }
                                }
                                else {
                                    $result = "No file data received"
                                }
                            }
                            else {
                                $result = "Missing target file name"
                            }
                        }
                    }
                }
                else {
                    $result = "No client data received"
                }
                break
            }
            #>

            <#
            "GET /log" {
                # return the webserver log (stored in log variable)
                $result = $webserverLog
                break
            }
            #>
            "GET /time" {
                # return current time
                $result = Get-Date -Format s
                break
            }

            "GET /starttime" {
                # return start time of the powershell webserver (already contained in $htmlResponse, nothing to do here)
                break
            }

            <#
            "GET /beep" {
                # Beep
                [CONSOLE]::beep(800, 300) # or "`a" or [char]7
                break
            }
            #>

            "GET /quit" {
                # stop powershell webserver, nothing to do here
                break
            }

            "GET /exit" {
                # stop powershell webserver, nothing to do here
                break
            }

            default {
                # unknown command, check if path to file

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
