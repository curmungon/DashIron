
function ErrorMessage {
    param (
        [Parameter(Mandatory = $true)][string] $Message
    )
    [ordered] @{error = @{message = $Message } } | ConvertTo-Json -Compress -Depth 5
}


Export-ModuleMember -Function * -Alias *
