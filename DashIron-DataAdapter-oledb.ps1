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
    [ValidateSet("select", "insert", "update", "upsert", "delete", $null)]
    [string] $Action = $(if ($params.Action) { $params.Action } else { $null }),
    [string] $SourceTable = $(if ($params.SourceTable) { $params.SourceTable } else { '[TestTable]' }),
    [string] $SourceInstance = $(if ($params.Sourceinstance) { $params.Sourceinstance } else { '.\' }),
    [string] $SourceDatabase = $(if ($params.Sourcedatabase) { $params.Sourcedatabase } else { 'TestDB.accdb' }),
    [string] $WhereFilter = $(if ($params.WhereFilter) { $params.WhereFilter } else { '' }),
    [string] $Provider = $(if ($params.Provider) { $params.Provider } else { 'Microsoft.ACE.OLEDB.12.0' }),
    [string] $ConnectionString = $(if ($params.ConnectionString) { $params.ConnectionString } else { $null }),
    $SQL = $(if ($params.SQL) { $params.SQL } else { $null }),
    $Value = $(if ($params.Value) { $params.Value } else { $null })
)

function New-Record {
    param (
    )
    if ($Value.GetType().Name -notlike "*object") {
        return ErrorMessage("The Value must be valid JSON. `n`nThere was an error processing: `n$Value")
    }

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
    # add the new row
    $table.Rows.Add($newrow)
    # store only the new row
    $dc = $table.GetChanges()
    
    #$newRowRollup = @{ }
    #$newRowRollup.Add("row", @() )
    
    # Update the database, inserting the new rows.
    # Capture the number of affected items
    $effect.inserted = $DataAdapter.Update($dc)

    <# 
    # return the inserted rows as a seperate object
    foreach ($row in $dc.Rows) {
        $temp = @{ };
        $columNames.foreach( { $temp.add($_, $row[$_]) } )
        $newRowRollup.row += , $temp
    }
    $temp = $null;
    $effect.add('newRows', $newRowRollup )
    #>

    # $DataAdapter.Update($dc) > $null
    # $DataAdapter.Update($table) > $null

    # these two are pointless if table = dc below
    #$table.Merge($dc)
    #$table.AcceptChanges()

    # setting the table equal to dc ensures that we are only returning the change
    # This will only return the changed entry regardless of what the query was
    $table = $dc
}

function Update-Record {
    param (
    )
    if ($Value.GetType().Name -notlike "*object") {
        return ErrorMessage("The Value must be valid JSON. `n`nThere was an error processing: `n$Value")
    }

    $Value | Get-Member -MemberType *Property | ForEach-Object {
        if ($table.PrimaryKey.ColumnName -eq ($_.Name) ) {
            if ($table.PrimaryKey.AutoIncrement -eq $false ) {
                $table.Rows[0][($_.Name)] = $Value.($_.Name)
            }
        }
        else {
            # because the data is going through a DataAdapter $null needs to become DBNull
            if ($null -eq $Value.($_.Name)) {
                $table.Rows[0][($_.Name)] = [DBNull]::Value
            }
            else {
                $table.Rows[0][($_.Name)] = $Value.($_.Name)
            }
        }
    }
    $effect.updated = $DataAdapter.Update($table)
}

try {
    # check the connection string
    if ($ConnectionString) {
        $strConn = $ConnectionString
    }
    elseif ($Provider -and $Sourceinstance -and $Sourcedatabase) {
        #allow relative paths for the datasource
        if ($Sourceinstance.Substring(0, 1) -eq "." -and $MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
            $Sourceinstance = "$($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Sourceinstance))\"
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

    # process the Where statement so it can be used in any SELECT scenario
    if ($WhereFilter -eq "" -or $null -eq $WhereFilter) { 
        $WhereFilter = "" 
    }
    elseif ( $WhereFilter -like "*;*" ) {
        $WhereFilter = ""
    }
    else {
        $WhereFilter = "WHERE $WhereFilter"
    }

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
            # if the SELECT is missing a WHERE clause and a valid $WhereFilter was passed seperately add it here
            if (!$strSql.Contains("WHERE") -and $WhereFilter.Length -gt 5 -and $WhereFilter.Substring(0, 5) -eq "WHERE") {
                $strSql += " $WhereFilter"
            }
        }
        catch {
            return ErrorMessage("SQL must be either a STRING or a valid JSON object with a property named 'Select'. `n`nInvalid SQL: `n$SQL")
        }
    }
    else {
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
    
    [System.Data.DataTable] $table = $dataset.Tables[$SourceTable]
    $columNames = $table.Columns.ColumnName
    
    # provision our data hash table
    $data = [ordered] @{ }
    # effect will be used to capture and send back the number of changes
    $effect = @{ }
    $effect.add('updated', 0)
    $effect.add('inserted', 0)
    $effect.add('deleted', 0)

    #update from submitted data

    # when attempting to update a non-existant record, which is interpereted as an insert for now, 
    # the WHERE clause of the SQL statement keeps the new record's auto generated PK from showing up in the results
    # Obviously this needs to be resolved... upsert or some similar concept would be preferable
    
    Switch ( $Action ) {
        "delete" {
            # only allow single record deletes to help avoid accidental deletion
            if ($table.Rows.Count -eq 1) {
                $table.Rows[0].Delete()
                $effect.deleted = $DataAdapter.Update($table)
            }
            break
        }
        "insert" {
            New-Record
            break
        }
        "update" {
            Update-Record
            break
        }
        "upsert" {
            # there isn't a specific record to work with but data was submitted, put the submitted data in a new row
            if ($table.Rows.Count -ne 1 -or $WhereFilter -eq "") {
                New-Record
            }
            # if there is only one row and data is recieved, execute an update
            else {
                Update-Record
            }
            break
        }
        default {
            # if there's no Value it's likely a SELECT, don't do anything
            # also the null value will cause errors in the other functions
            if ($Value) {
                # if no specific action is sent in, perform an "Upsert" operation...
                # i.e. insert if ambiguous, update if a specific record is found
                if ($table.Rows.Count -ne 1 -or $WhereFilter -eq "") {
                    New-Record
                }
                else {
                    Update-Record
                }
            }
            break
        }
    }

    # if there were any effects from the process above, add them to the results
    if ($effect.Count) {
        $data | Add-Member -Name 'result' -Type NoteProperty -Value $effect
    }

    # roll the data up and return it as JSON
    # The response structure is :
    #                    {data:[{obj1},{obj2},...]}

    $data | Add-Member -Name 'data' -Type NoteProperty -Value @()
    foreach ( $row in $table.Rows ) {
        $rollup = [PSCustomObject] @{ }
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
    return ErrorMessage("while opening $strConn : Error '$($_)' in script $($_.InvocationInfo.ScriptName) $($_.InvocationInfo.Line.Trim()) (line $($_.InvocationInfo.ScriptLineNumber)) char $($_.InvocationInfo.OffsetInLine) executing $($_.InvocationInfo.MyCommand) ")
}
