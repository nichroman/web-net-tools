' ==========================================================================
'  Web_NetTools v0.0.2 - fallback\start-check-nodes.vbs
'  Reserve launcher for "Check nodes" (WEB_check_nodes, port 3000).
'  Use it when PowerShell scripts are blocked by policy or antivirus.
'
'  Shortcut target example (Run: minimized):
'     wscript.exe "C:\Tools\WebNetTools\launcher\fallback\start-check-nodes.vbs"
'
'  Optional argument: /nobrowser - do not open the browser.
'
'  Messages are intentionally ASCII-only: Windows Script Host reads Cyrillic
'  text incorrectly for scripts saved in UTF-8 without a BOM.
' ==========================================================================
Option Explicit

Const APP_TITLE   = "Web_NetTools"
Const APP_MARKER  = "WEB_check_nodes"
Const APP_DIRNAME = "check-nodes"
Const APP_PORT    = 3000
Const LOG_NAME    = "check-nodes.log"

Dim fso, shell, launcherDir, root, appDir, logDir, logFile, openBrowser, i
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

launcherDir = fso.GetParentFolderName(WScript.ScriptFullName)
root = fso.GetParentFolderName(launcherDir)
If LCase(fso.GetFileName(launcherDir)) = "fallback" Then root = fso.GetParentFolderName(root)
appDir = fso.BuildPath(root, APP_DIRNAME)
logDir = fso.BuildPath(root, "logs")
logFile = fso.BuildPath(logDir, LOG_NAME)

openBrowser = True
For i = 0 To WScript.Arguments.Count - 1
    If LCase(WScript.Arguments(i)) = "/nobrowser" Then openBrowser = False
Next

If Not fso.FileExists(fso.BuildPath(appDir, "server.js")) Then
    MsgBox "Application not found:" & vbCrLf & appDir & vbCrLf & vbCrLf & _
           "Run install.bat from the Web_NetTools_v0.0.2 project first.", 16, APP_TITLE
    WScript.Quit 1
End If

If Not fso.FolderExists(logDir) Then fso.CreateFolder logDir

' Canonical (long) path: the launch command and log use the same path form
appDir = fso.GetFolder(appDir).Path
root = fso.GetParentFolderName(appDir)
logDir = fso.BuildPath(root, "logs")
logFile = fso.BuildPath(logDir, LOG_NAME)

If AppIsRunning() Then
    Log "server is already running, browser is opened"
    If openBrowser Then OpenApp
    WScript.Quit 0
End If

Dim nodeExe
nodeExe = FindNode()
If nodeExe = "" Then
    MsgBox "Node.js 14 or newer was not found." & vbCrLf & vbCrLf & _
           "Install Node.js from https://nodejs.org" & vbCrLf & _
           "(Windows 7 x86: node-v14.21.3-x86.msi)", 16, APP_TITLE
    WScript.Quit 1
End If

Log "starting server: " & nodeExe
RunHidden nodeExe

If WaitForApp(20000) Then
    Log "server is ready on port " & APP_PORT
    If openBrowser Then OpenApp
    WScript.Quit 0
Else
    Log "server did not answer in time, browser is opened anyway"
    If openBrowser Then OpenApp
    WScript.Quit 2
End If

Sub Log(text)
    On Error Resume Next
    Dim stream
    If fso.FileExists(logFile) Then
        If fso.GetFile(logFile).Size > 1048576 Then fso.DeleteFile logFile, True
    End If
    Set stream = fso.OpenTextFile(logFile, 8, True)
    stream.WriteLine "[" & Now & "] [" & shell.ExpandEnvironmentStrings("%USERNAME%") & "] " & text
    stream.Close
    On Error Goto 0
End Sub

Function AppIsRunning()
    Dim text
    text = HttpGet("http://127.0.0.1:" & APP_PORT & "/api/health", 1500)
    If text = "" Then
        AppIsRunning = False
    Else
        AppIsRunning = (InStr(text, APP_MARKER) > 0)
    End If
End Function

Function HttpGet(url, timeoutMs)
    Dim http
    HttpGet = ""
    On Error Resume Next
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    If Err.Number <> 0 Then
        Err.Clear
        Set http = CreateObject("MSXML2.XMLHTTP.6.0")
    End If
    If Err.Number <> 0 Then
        Err.Clear
        HttpGet = ""
        Exit Function
    End If
    http.setTimeouts timeoutMs, timeoutMs, timeoutMs, timeoutMs
    http.open "GET", url, False
    http.send
    If Err.Number = 0 Then HttpGet = http.responseText
    Err.Clear
    On Error Goto 0
End Function

Function WaitForApp(timeoutMs)
    Dim started
    started = Timer
    Do
        If AppIsRunning() Then
            WaitForApp = True
            Exit Function
        End If
        WScript.Sleep 400
    Loop While (Timer - started) < (timeoutMs / 1000)
    WaitForApp = False
End Function

Function FindNode()
    Dim candidates, index, path
    candidates = Array( _
        shell.ExpandEnvironmentStrings("%ProgramFiles%\nodejs\node.exe"), _
        shell.ExpandEnvironmentStrings("%ProgramFiles(x86)%\nodejs\node.exe"), _
        shell.ExpandEnvironmentStrings("%SystemDrive%\nodejs\node.exe") )

    For index = 0 To UBound(candidates)
        path = candidates(index)
        If InStr(path, "%") = 0 Then
            If fso.FileExists(path) Then
                FindNode = path
                Exit Function
            End If
        End If
    Next

    FindNode = "node.exe"
End Function

Sub RunHidden(exe)
    On Error Resume Next
    Dim command
    command = """" & exe & """ """ & fso.BuildPath(appDir, "server.js") & """"
    shell.CurrentDirectory = appDir
    shell.Run command, 0, False
    On Error Goto 0
End Sub

Sub OpenApp()
    On Error Resume Next
    shell.Run "http://localhost:" & APP_PORT, 1, False
    On Error Goto 0
End Sub
