<#
.Synopsis
Makes an oledb based connection to a database, returns JSON data.
.Description
Makes an oledb based connection to a database, returns JSON data.
.Example
This script is intended for use with DashIron-Webserver.ps1
.Notes
Author: Nathan Moyer
#>

param (
    <#
     MS Access based construct doesn't support the concept of a "Source Instance" and "Source Database"
     To support an easier SQL Transition the params are seperated but later combined to make a 
     complete "Data Source" pointing to the file, which is used in the Connection String. 
     #>    
    [object] $params,
    [string] $SourceTable = $(if ($params.SourceTable) { $params.SourceTable } else { '[zTestTable0]' }),
    [string] $Sourceinstance = $(if ($params.Sourceinstance) { $params.Sourceinstance } else { '.\' }),
    [string] $Sourcedatabase = $(if ($params.Sourcedatabase) { $params.Sourcedatabase } else { 'TestDB.accdb' }),
    [string] $WhereFilter = $(if ($params.WhereFilter) { $params.WhereFilter } else { '1=1' }),
    [string] $Provider = $(if ($params.Provider) { $params.Provider } else { 'Microsoft.ACE.OLEDB.12.0' }),
    [string] $ConnectionString = $(if ($params.ConnectionString) { $params.ConnectionString } else { $null }),
    $SQL = $(if ($params.SQL) { $params.SQL } else { $null }),
    $Value = $(if ($params.Value) { $params.Value } else { $null })
)
function ErrorMessage {
    param (
        [Parameter(Mandatory = $true)][string] $Message
    )
    return [ordered] @{error = @{message = $Message } } | ConvertTo-Json -Compress -Depth 5
}

try {
    # check the connection string
    if ($ConnectionString) {
        $strConn = $ConnectionString
    }
    elseif ($Provider -and $Sourceinstance -and $Sourcedatabase) {
        #allow relative paths for the datasource
        if ($Sourceinstance.Substring(0, 1) -eq "." -and $MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
            Push-Location $basedir
            $Sourceinstance = "$($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Sourceinstance))\"
            Pop-Location
        }
        $strConn = "Provider=$Provider;Data Source=$Sourceinstance$Sourcedatabase"
    }
    else {
        return ErrorMessage("Invalid conneciton string. `n 
                Either specify a vaild 'ConnectionString' value, 
                or specify values for all of the following: `n 
                'Provider', 'Sourceinstance',  and 'Sourcedatabase'")
    }
    $oConn = New-Object System.Data.OleDb.OleDbConnection($strConn)
    # Populate the SQL string, SELECT is required
    # User input needs to be sanitized! 
    if ($SQL) {
        # Allow a string for quick SELECTs or an object for more control
        # the object will allow optional user defined command statements 
        # with the command builder filling in the non-user-defined statements
        try {
            if ($SQL.GetType().Name -eq "string") {
                $strSql = $SQL
            }
            elseif ($SQL.GetType().Name -like "*object") {
                if ($SQL.Select) {
                    $strSql = "$($SQL.Select)"
                }
                else {
                    return ErrorMessage("SQL must be either a STRING or a valid JSON object with a property named 'Select'. `n`nInvalid SELECT: `n$SQL")
                }
            }
        }
        catch {
            return ErrorMessage("SQL must be either a STRING or a valid JSON object with a property named 'Select'. `n`nInvalid SQL: `n$SQL")
        }
    }
    else {
        if ($WhereFilter -eq "" -or $null -eq $WhereFilter) { 
            $WhereFilter = "" 
        }
        elseif ( $WhereFilter -like "*;*" ) {
            $WhereFilter = ""
        }
        else {
            $WhereFilter = "WHERE $WhereFilter"
        }
        $strSql = "SELECT * FROM $SourceTable $WhereFilter"
    }
    if ( $strSql.Substring(0, 6) -ne "SELECT") {
        Write-Host "$(Get-Date -Format s) Non-SELECT statement passed. `n SQL: $strSql"
        return ErrorMessage("SQL Statement error.`n SQL: $strSql")
    }
    # setup the connection
    $DataAdapter = New-Object System.Data.OleDb.OleDbDataAdapter $oCmd, $oConn
    $DataAdapter.MissingSchemaAction = [System.Data.MissingSchemaAction]::AddWithKey
    $DataAdapter.SelectCommand = New-Object System.Data.OleDb.OleDbCommand("$strSql;", $oConn)
    
    # set additional SQL Handlers
    # Unassigned commands will be filled in by the command builder 
    # The command builder is easy, but is limited to interacting with a single table/stored query
    $strSqlHandler = ""
    try {
        # if the SQL was passed as an object, set the passed commands
        if ($SQL -and $SQL.GetType().Name -like "*object") {
            # Update
            if ($SQL.Update) {
                $strSqlHandler = "$($SQL.Update)"
                if ( $strSqlHandler.Substring(0, 6) -ne "UPDATE") {
                    Write-Host "$(Get-Date -Format s) Non-UPDATE statement passed. `n SQL: $strSqlHandler"
                    return ErrorMessage("SQL 'UPDATE' Statement error.`n SQL: $strSqlHandler")
                }
                #set the update command
                $DataAdapter.UpdateCommand = New-Object System.Data.OleDb.OleDbCommand($strSqlHandler, $oconn)
            }
            # Insert
            if ($SQL.Insert) {
                $strSqlHandler = "$($SQL.Insert)"
                if ( $strSqlHandler.Substring(0, 6) -ne "INSERT") {
                    Write-Host "$(Get-Date -Format s) Non-INSERT statement passed. `n SQL: $strSqlHandler"
                    return ErrorMessage("SQL 'INSERT' Statement error.`n SQL: $strSqlHandler")
                }
                # set the insert command
                $DataAdapter.InsertCommand = New-Object System.Data.OleDb.OleDbCommand($strSqlHandler, $oconn)
                #$newrow = $dataset.tables[0].NewRow()
                #$newrow["StringField"] = "A new row"
                #$dataset.tables[0].Rows.Add($newrow)
                #$DataAdapter.Update($dataset.Tables[0])
            }
            # Delete
            if ($SQL.Delete) {
                $strSqlHandler = "$($SQL.Delete)"
                if ( $strSqlHandler.Substring(0, 6) -ne "DELETE") {
                    Write-Host "$(Get-Date -Format s) Non-DELETE statement passed. `n SQL: $strSqlHandler"
                    return ErrorMessage("SQL 'DELETE' Statement error.`n SQL: $strSqlHandler")
                }
                #set the delete command
                $DataAdapter.DeleteCommand = New-Object System.Data.OleDb.OleDbCommand($strSqlHandler, $oconn)
                #$dataset.tables[0].Rows[1].Delete()
                #$DataAdapter.Update($dataset.Tables[0])
            }
        }
    }
    catch {
        return ErrorMessage("SQL must be either a STRING or a valid JSON object with a property named 'SELECT'. `n`nInvalid SQL: `n$SQL")
    }

    # all unassigned handlers will be populated by the command builder
    $cb = new-object System.Data.OleDb.OleDbCommandBuilder($DataAdapter)
    # show the properties of the commandbuilder's command, including the SQL text
    # $cb.GetDeleteCommand() # or whatever command you want to view
    <#
    https://docs.microsoft.com/en-us/dotnet/api/system.data.oledb.oledbcommandbuilder?view=netframework-4.7.2
    Any additional SQL statements that you do not set are generated by the OleDbCommandBuilder.
    The OleDbCommandBuilder uses the Connection, CommandTimeout, and Transaction 
    properties referenced by the SelectCommand. The user should call RefreshSchema 
    if one or more of these properties are modified, or if the SelectCommand itself 
    is replaced. Otherwise the InsertCommand, UpdateCommand, and DeleteCommand 
    properties retain their previous values.
    #>

    $dataset = New-Object System.Data.Dataset
    # dataset can be filled using a single parameter once a "SelectCommand" has been set on the DataAdapter
    # the second parameter is the table's name within the dataset, access it with "dataset.Tables[<tablename>]"" 
    $DataAdapter.Fill($dataset, $SourceTable) > $Null
    # The table copies are only relevant for getting autonumber values from old versions of MS Access or .mdb (and .mdb family) files
    # further commentary about autonumbers and JET is below
    #$DataAdapter.Fill($dataset, "$SourceTable-Copy") > $Null

    $table = $dataset.Tables[$SourceTable]
    #$tablecopy = $dataset.Tables[$SourceTable].Copy()
    $columNames = $table.Columns.ColumnName
    
    #update from submitted data
    <#
    function OnRowUpdated( [object] $sender, [System.Data.OleDb.OleDbRowUpdatedEventArgs] $e) {
        # Conditionally execute this code block on inserts only.
        Write-Host "Trying update func"
        Write-Host $sender
        Write-Host $e
        try {
            #if ($e.StatementType -eq [System.Data.StatementType]::Insert) {
            Write-Host "in the insert"
            $cmdNewID = New-Object System.Data.OleDb.OleDbCommand("SELECT @@IDENTITY",
                $oConn);
            # Retrieve the Autonumber and store it in the CategoryID column.
            $e.Row["ID"] = $cmdNewID.ExecuteScalar();
            $e.Status = UpdateStatus.SkipCurrentRow;
            #}
            #else {
            #    Write-Host "onrowupdate if failed"
            #}
        }
        catch {
            Write-Host "error in OnRowUpdated"
        }
        Write-Host "out of the insert"
    }
#>
    if ($Value) {
        if ($Value.GetType().Name -notlike "*object") {
            return ErrorMessage("The Value must be valid JSON. `n`nThere was an error processing: `n$Value")
        }

        # this is essentially an INSERT... for now
        # there are multiple records but data was submitted, put the submitted data in a new row
        if ($table.Rows.Count -ne 1) {
            # there is a potential problem with using MS Access and auto numbers
            # this doc provides details for JET, but doesn't mention ACE... 
            # batching seems to be the real root of the issue.
            # https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/retrieving-identity-or-autonumber-values#retrieving-microsoft-access-autonumber-values
            
            $DataAdapter.Update($table) > $null

            $newrow = $table.NewRow()
            $Value | Get-Member -MemberType *Property | ForEach-Object {
                if ($table.PrimaryKey.ColumnName -eq ($_.Name) ) {
                    if ($table.PrimaryKey.AutoIncrement -eq $false ) {
                        $newrow[($_.Name)] = $Value.($_.Name)
                    }
                }
                else {
                    # because the data is going through a DataAdapter $null needs to become DBNull
                    if ($Value.($_.Name) -eq $null) {
                        $newrow[($_.Name)] = [DBNull]::Value
                    }
                    else {
                        $newrow[($_.Name)] = $Value.($_.Name)
                    }
                }
            }
            #$newrow["StringField"] = $Value.StringField
            $table.Rows.Add($newrow)
            #$table | Out-Host
            $dc = $table.GetChanges()
            #$dc | Out-Host
            #$DataAdapter.Update($dc);
            #if ($table.PrimaryKey.AutoIncrement) {
            #    $tablecopy.Merge($dc, $true)
            #    $tablecopy.AcceptChanges()
            #    Write-Host "List All Rows-inline (copy):"
            #    $tablecopy | Out-Host
            #}
            
            # Include an event to fill in the Autonumber value.
            #$DataAdapter.RowUpdated += New-Object System.Data.OleDb.OleDbRowUpdatedEventHandler(OnRowUpdated);
            # Update the database, inserting the new rows. 
            #$DataAdapter.Update($dc);

            $DataAdapter.Update($table) > $null
            # these two are probably pointless, considering that table = dc below
            #$table.Merge($dc)
            #$table.AcceptChanges()
            #$table.Rows = $table.Select("$($table.PrimaryKey.ColumnName)=$($dc.($table.PrimaryKey.ColumnName))")
            
            # setting the table equal to dc ensures that we are only returning the change
            $table = $dc
            #$DataAdapter.Fill($table) > $Null
        }

        # if there is only one row and data is recieved , try an update
        else {
            $Value | Get-Member -MemberType *Property | ForEach-Object {
                if ($table.PrimaryKey.ColumnName -eq ($_.Name) ) {
                    if ($table.PrimaryKey.AutoIncrement -eq $false ) {
                        $table.Rows[0][($_.Name)] = $Value.($_.Name)
                    }
                }
                else {
                    # because the data is going through a DataAdapter $null needs to become DBNull
                    if ($Value.($_.Name) -eq $null) {
                        $table.Rows[0][($_.Name)] = [DBNull]::Value
                    }
                    else {
                        $table.Rows[0][($_.Name)] = $Value.($_.Name)
                    }
                }
            }
            
            #$table.Rows[0]["StringField"] = $Value.StringField
            $DataAdapter.Update($table) > $null
        }
        # show the output from our changes
        #Write-Host "List All Rows:"
        #$table | Out-Host
    }
    
    # roll the data up and return it as JSON
    # The response structure is :
    #                    {data:[{obj1},{obj2},...]}
    # The commented rows here are for returning the table and row information with the object
    # I don't like adding unexpected fields, but may need to depending on what problems come up
    $data = [ordered] @{ data = @() }
    #$i = 0
    foreach ( $row in $table.Rows ) {
        #$rollup = [PSCustomObject] @{ sourcetable = $table.TableName; sourcerow = $i }
        $rollup = [PSCustomObject] @{ }
        #$i++
        foreach ($name in $columNames ) {
            $key = $name
            $val = $row[$name]
            if ($val -match '\S+') {
                $rollup | Add-Member -Name $key -Type NoteProperty -Value $val
            }
        }
        $data.data += , $rollup
    }
    $table.Dispose() > $Null

    $data | ConvertTo-Json -Compress -depth 100
}
catch {
    Write-Error "while opening $Sourceinstance . $Sourcedatabase . $SourceTable : Error'$($_)' in script $($_.InvocationInfo.ScriptName) $($_.InvocationInfo.Line.Trim()) (line $($_.InvocationInfo.ScriptLineNumber)) char $($_.InvocationInfo.OffsetInLine) executing $($_.InvocationInfo.MyCommand) "
    return ErrorMessage("while opening $Sourceinstance . $Sourcedatabase . $SourceTable : Error'$($_)' in script $($_.InvocationInfo.ScriptName) $($_.InvocationInfo.Line.Trim()) (line $($_.InvocationInfo.ScriptLineNumber)) char $($_.InvocationInfo.OffsetInLine) executing $($_.InvocationInfo.MyCommand) ")
}
