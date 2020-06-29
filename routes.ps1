# example route for "" using an HTML template 'here string'
Register-Route GET "" { 
    $localhtml = @"
        <html><body>
            !HEADERLINE
            
            <form method="GET" action="/">
            <b>!PROMPT&nbsp;</b><input type="text" maxlength=255 size=80 name="command" value='!FORMFIELD'>
            <input type="submit" name="button" value="Enter">
            <pre>!RESULT</pre>
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
            $result = ErrorMessage($result)
        }
    }
    # preset form value with command for the caller's convenience
    $localhtml = $localhtml -replace '!FORMFIELD', $formField
    # insert powershell prompt to form
    $prompt = "PS $PWD>"
    $localhtml = $localhtml -replace '!PROMPT', $prompt
    $localhtml -replace '!RESULT', $result
}

Register-Route get test {
    "<html><title>Test</title><body><div style=`"margin:40px;`">Good Test <br><br> Base directory: $basedir </div></body></html>"
}

Register-Route "GET" "test me" {
    "<html><title>Test Me</title><body><div style=`"margin:40px;`">Good Test Me <br><br> Base directory: $basedir </div></body></html>"
}

# need to figure out some way of setting up something similar to express' "static" 
# for properly serving the web page's associated documents

# just passing a static directroy in doesn't work yet
# need to adjust the path/file finding process into a function or something
# .... perhaps a "Use-Static" function that wraps specific calls???
Register-Static "$basedir\dataview"

# ** got the named virtual path method working **
Register-Static "$basedir\dataview" "/static"

Register-Route get dataview.html {
    Use-Path "$basedir\dataview" { Get-Content .\dataview.html }
}

Register-Route get dataentry.html {
    Use-Path "$basedir" { Get-Content .\dataentry.html }
}

# other applications can be called by providing a route for them
# this will return some text from a function executed by nodejs 
# **you must have nodejs on your machine, and it must be in your environment's PATH**
Register-Route get nodetest {
    Use-Path "$basedir" { node .\test.js } #can be pipelined with Out-String, Out-File or other commands
}

Register-Route POST mydb {
    #get data from database
    $resolvedScriptPath = "$(Resolve-Path .\DashIron-DataAdapter-oledb.ps1)"
    #write $resolvedScriptPath
    Use-Path $basedir { Send-HttpRequestToScript -request $request -scriptPath $resolvedScriptPath }
}

Register-Route PUT mydb {
    #get data from database
    $resolvedScriptPath = "$(Resolve-Path .\DashIron-DataAdapter-oledb.ps1)"
    
    Use-Path $basedir { Send-HttpRequestToScript -request $request -scriptPath $resolvedScriptPath }
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

