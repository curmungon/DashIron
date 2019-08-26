# DashIron

PowerShell based tool focused on local web page development, used for interacting with databases via a DataAdapter to serve and receive JSON data.

# Starting the Server

### The server can be launched directly with a shell, from a Shortcut, or from another script.

**With a shell running in the same directory as your websever's script, use one of the command sets below:**

_Run DashIron on the default port and use the current folder as the base directory._

```
powershell.exe -executionpolicy bypass -command ".\DashIron-Webserver.ps1"
```

_The `RunAs32` option will allow a 32 or 64 bit shell. This effects the database connectors you can use. Only 32 bit connectors are available in a 32 bit shell. The same is true for 64 bit connectors._ **_Most MS Office installations are currently 32 bit, which means 32 bit connectors need to be used, the default is to run a 32 bit shell._**

```
powershell.exe -executionpolicy bypass -command ".\DashIron-Webserver.ps1 -runas32 false"
```

_Run DashIron on the default port and use the parent directory's `public` folder as the base directory._

```
powershell.exe -executionpolicy bypass -command ".\DashIron-Webserver.ps1 -basedir '..\public\'"
```

_Run DashIron on the default port and use the current directory's `public` folder as the base directory. Open the default web browser to the `dataentry.html` page from the default host/port._

```
powershell.exe -executionpolicy bypass -command ".\DashIron-Webserver.ps1 -basedir '.\public\' -openbrowser -startpage 'dataentry.html'"
```

_Run DashIron on localhost port 5050 and use the current directory's `public` folder as the base directory. Open the default web browser to the `child` folder's `dataentry.html` page from `localhost:5050`._

```
powershell.exe -executionpolicy bypass -command ".\DashIron-Webserver.ps1 -binding 'http://localhost:5050/' -basedir '.\public\' -openbrowser -startpage 'child/dataentry.html'"
```

Because the server can use a different base directory than its current location, multiple folders can be served from different ports.

The Use-Path function also allows you to temporarily change the path to execute a command, so it could be used with paths relative to the basedir to easily serve pages from diverse folders on one port.

Like this:

```powershell
Register-Route get dataentry.html {
    Use-Path "$basedir\..\public\" { Get-Content .\dataentryexample.html }
}
```

**_This example only works for single files, the relative references inside of the document will not be resolved correctly!_**

# Defining Routes

By default the PowerShell webserver will send back any file that it can find relative to the base directory, this is why relative references in web pages work without having to register each of the files that they use.

To set an action for a specifc route use `Register-Route` with the method (get, post, put, or delete) and the path, and provide an action to be performed. **The action must be wrapped in curly braces: `{<action>}`**

_The server must be restarted for routing changes to take effect_

```powershell
Register-Route get test {
    '<html><title>Test</title><body><div style="margin:40px;">Good Test</div></body></html>'
}
```

Routes with spaces must be wrapped in quotes; however, quotes are optional on methods. Also, both routes and methods are case insensitive (like most things in PowerShell).

```powershell
Register-Route "GET" "test me" {
    '<html><title>Test</title><body><div style="margin:40px;">Good Test Me</div></body></html>'
}
```

# Using a Datasource

## HTTP Request Body to a DashIron-DataAdapter

Send-HttpRequestToScript takes an HTTP request (POST or PUT preferred) and passes the contents of its Body to a script as the parameter `-params`, which contains an object with the elements passed in a JSON formatted body.

The following takes the script `DashIron-DataAdapter-oledb.ps1`, which makes a connection to a database, and passes the request along with it.

_The script path is resolved before passing it in because `Use-Path` changes the path that the relative reference will resolve to._

```powershell
Register-Route POST mydb {
    #get data from database
    $resolvedScriptPath = "$(Resolve-Path .\DashIron-DataAdapter-oledb.ps1)"
    #write $resolvedScriptPath
    Use-Path $basedir { Send-HttpRequestToScript -request $request -scriptPath $resolvedScriptPath }
}
```

To facilitate flexible development, the parameters for connections can be passed into the DashIron-DataAdapter in the HTTP Request body. This allows changes to the database conneciton without having to restart the server.

## DashIron Request Structure

To get data you have to request it, with a simple page served from our PowerShell webserver this can be done fairly easily.

With a POST request, provide the appropriate parameters and data will be returned.

Using the [MDN fetch() POST example]...

```javascript
//relative references in SourceInstance are resolved by DashIron
postData("http://localhost:8080/mydb", {
  SourceInstance: "./",
  SourceDatabase: "TestDB.accdb",
  Provider: "Microsoft.ACE.OLEDB.12.0",
  SQL: "SELECT TOP 100 * From [TestTable]",
  WhereFilter: "1=1"
});

//If SQL isn't passed the default is to SELECT * FROM [<SourceTable>]
postData("http://localhost:8080/mydb", {
  SourceInstance: "./",
  SourceDatabase: "TestDB.accdb",
  SourceTable: "TestTable",
  Provider: "Microsoft.ACE.OLEDB.12.0",
  WhereFilter: "1=1"
});
```

Or, using SQL and a Connection String.

```javascript
// a fully qualified (absolute) path must be used for ConnectionString
postData("http://localhost:8080/mydb", {
  SQL: "SELECT * FROM [TestTable]",
  ConnectionString:
    "Provider=Microsoft.ACE.OLEDB.12.0;Data Source=D:databasesTestDB.accdb"
});

postData("http://localhost:8080/mydb", {
  SQL: { Select: "SELECT * FROM [TestTable]" },
  ConnectionString:
    "Provider=Microsoft.ACE.OLEDB.12.0;Data Source=D:databasesTestDB.accdb"
});
```

SQL can be passed as a string (SELECT only), or an object with a SELECT and other actions (only INSERT, UPDATE, and/or DELETE). Defining the additional actions allows them to use complex SQL expressions if needed.

## Insert/Update

Insert/Update require that a `Value` is submitted. The current effect is basically an implied Upsert (Update/Insert). If the SQL statement returns one (1) record it will be updated. If the SQL statement returns 0 or more than 1 record, it will perform an insert.

```javascript
postData("http://localhost:8080/mydb", {
  SourceInstance: "./",
  SourceDatabase: "TestDB.accdb",
  SourceTable: "TestTable",
  Provider: "Microsoft.ACE.OLEDB.12.0",
  WhereFilter:
    pk === "" || pk === null || pk === undefined ? "1=1" : `ID=${pk}`,
  Value: {
    ID: pk,
    StringField: document.getElementById("value").value,
    WatchbillDate: document.getElementById("wbDate").value,
    bool: true
  }
});
```

## Delete

Deleting items can be done by sending `Action: "delete"`. This will only delete one element at a time. It deletes the first row returned by the query.

```javascript
postData("http://localhost:8080/mydb", {
            SourceInstance: "./",
            SourceDatabase: "TestDB.accdb"
            SourceTable: "TestTable",
            Provider: "Microsoft.ACE.OLEDB.12.0",
            WhereFilter:
            pk === "" || pk === null || pk === undefined ? "1=1" : `ID=${pk}`,
            Action: "delete"
        })
```

## Returned Data

The requested data will be returned as JSON array of objects in `data`.

```json
{
  "data": [
    {
      "ID": 10048,
      "StringField": "Robert",
      "DateField": "/Date(1000212360000)/",
      "BoolField": true
    },
    {
      "ID": 10049,
      "StringField": "Susan",
      "DateField": "/Date(1000213200000)/",
      "BoolField": false
    }
  ]
}
```

[mdn fetch() post example]: https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch#Supplying_request_options
