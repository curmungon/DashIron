<#
.Synopsis
Helper module to assist DashIron and it's components.
.Description
Helper module to assist DashIron and it's components.
.Example
This script is intended for use within DashIron-Webserver.ps1 and its assoicated scripts.
.Notes
Author: Nathan Moyer
#>

# returns a JSON formatted message containing error information
function ErrorMessage {
    param (
        [Parameter(Mandatory = $true)][string] $Message
    )
    [ordered] @{error = @{message = $Message } } | ConvertTo-Json -Compress -Depth 5
}

# Passes request parameters submitted via "POST" method (JSON only, working on multipart/form-data)
# for execution by the requested PowerShell script (must accept a "params" argument)
# Use-Path 
function Send-HttpRequestToScript {
    param (
        # Parameter help description
        [Parameter(Mandatory)]
        [System.Net.HttpListenerRequest] $request,
        [Parameter(Mandatory)]
        [string] $scriptPath
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
                #[System.Net.Http.Headers.HttpContentHeaders]
                #[System.Net.Http.MultipartContent.MultipartFormDataContent] 
                break
            }
        }
        $body.Close();
        $reader.Close();
        #Write-Host $bodyData
        #$bodyData | Select -ExpandProperty parameter | write
        #Write-Host "End of client data."

        $requestParams = $bodyData
        # splat the params into the script
        #$execute = '& "' + $bodyData.script + '"' + " -params @requestParams"
        $execute = '& "' + "$scriptPath" + '"' + " -params @requestParams"
        try {
            # ... execute script
            # Write-Host "Executing $execute..."
            #$result = Invoke-Expression -ErrorAction SilentlyContinue -Command $execute 2> $NULL | Out-String
            $result = Invoke-Expression -ErrorAction SilentlyContinue -Command $execute 2> $NULL | Out-String
        }
        catch	{ }
        if ($Error.Count -gt 0) {
            # retrieve error message on error
            Write-Host "`nError while executing script $sourceName`n`n"
            Write-Host $Error[0]
            $Error.Clear()
            #no need to return the error here, the script should handle its errors.
        }
    }
    else {
        $result = "No client data received"
    }
    return $result
}

Export-ModuleMember -Function * -Alias *
