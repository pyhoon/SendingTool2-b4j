﻿B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=5.51
@EndOfDesignText@
'version: 2.10
#Event: AccessTokenAvailable (Success As Boolean, Token As String)
Sub Class_Globals
	#if B4A
	Private LastIntent As Intent
	#end if
	Private mTarget As Object
	Private mEventName As String
	Private mClientId As String
	Private mScope As String
	Type TokenInformation (AccessToken As String, RefreshToken As String, AccessExpiry As Long, Valid As Boolean)
	Private ti As TokenInformation
	Private Const TokenFile As String = "oauth2token.dat"
	Private TokenFolder As String
	Private packageName As String 'ignore
	Private mClientSecret As String
#if B4J
	Private server As ServerSocket
	Private fx As JFX
	Private port As Int = 51067
	Private astream As AsyncStreams
#End if
End Sub

#If B4J
Public Sub Initialize (Target As Object, EventName As String, ClientId As String, Scope As String, ClientSecret As String, DataFolder As String)
#Else
Public Sub Initialize (Target As Object, EventName As String, ClientId As String, Scope As String)
#End If
	mTarget = Target
	mEventName = EventName
	mClientId = ClientId
	mScope = Scope
	#if B4A
		packageName = Application.PackageName
		TokenFolder = File.DirInternal
	#Else If B4i
		TokenFolder = File.DirLibrary
		packageName = GetPackageName
	#Else If B4J
		TokenFolder = DataFolder
		mClientSecret = ClientSecret
	#End If
	If File.Exists(TokenFolder, TokenFile) Then
		Dim raf As RandomAccessFile
		raf.Initialize(TokenFolder, TokenFile, True)
		ti = raf.ReadB4XObject(raf.CurrentPosition)
		raf.Close
	End If
End Sub

Private Sub SaveToken
	Dim raf As RandomAccessFile
	raf.Initialize(TokenFolder, TokenFile, False)
	raf.WriteB4XObject(ti, raf.CurrentPosition)
	raf.Close
End Sub

Public Sub ResetToken
	Log("Token reset!!!")
	ti.Valid = False
	SaveToken
End Sub

Public Sub GetAccessToken
	If ti.Valid = False Then
		Authenticate
	Else If ti.AccessExpiry < DateTime.Now Then
		GetTokenFromRefresh
	Else
		RaiseEvent(True)
	End If
End Sub

Private Sub GetRedirectUri As String
	#if B4J
	Return "http://127.0.0.1:" & port
	'Return "http://localhost:" & port
	'Return "http://localhost"
	'Return "https://fire-push-24359.firebaseapp.com"
	'Return "https://fire-push-24359.firebaseapp.com/__/auth/handler"
	#Else
		Return packageName & ":/oath"
	#End If
End Sub

Private Sub Authenticate
#if B4J
	PrepareServer
#End If
'	Dim link As String = BuildLink("https://accounts.google.com/o/oauth2/v2/auth", _
'		 CreateMap("client_id": mClientId, _
'		"redirect_uri": GetRedirectUri, _
'		"response_type": "code", "scope": mScope))
	Dim link As String = BuildLink("https://accounts.google.com/o/oauth2/auth", _
		 CreateMap("client_id": mClientId, _
		"redirect_uri": GetRedirectUri, _
		"response_type": "code", "scope": mScope))
#if B4A
	Dim pi As PhoneIntents
	StartActivity(pi.OpenBrowser(link))
#else if B4i
	Main.App.OpenURL(link)
#else if B4J
	fx.ShowExternalDocument(link)
#end if
End Sub

#if B4J
Private Sub PrepareServer
	If server.IsInitialized Then server.Close
	If astream.IsInitialized Then astream.Close
	Do While True
		Try
			server.Initialize(port, "server")
			server.Listen
			Exit
		Catch
			port = port + 1
			Log(LastException)
		End Try
	Loop
	Wait For server_NewConnection (Successful As Boolean, NewSocket As Socket)
	If Successful Then
		astream.Initialize(NewSocket.InputStream, NewSocket.OutputStream, "astream")
		Dim Response As StringBuilder
		Response.Initialize
		Do While Response.ToString.Contains("Host:") = False
			Wait For AStream_NewData (Buffer() As Byte)
			Response.Append(BytesToString(Buffer, 0, Buffer.Length, "UTF8"))
		Loop
		astream.Write(("HTTP/1.0 200" & Chr(13) & Chr(10)).GetBytes("UTF8"))
		Sleep(50)
		astream.Close
		server.Close
		ParseBrowserUrl(Regex.Split2("$",Regex.MULTILINE, Response.ToString)(0))
	End If
	
End Sub
#else if B4A
Public Sub CallFromResume(Intent As Intent)
	If IsNewOAuth2Intent(Intent) Then
		LastIntent = Intent
		ParseBrowserUrl(Intent.GetData)
	End If
End Sub

Private Sub IsNewOAuth2Intent(Intent As Intent) As Boolean
	Return Intent.IsInitialized And Intent <> LastIntent And Intent.Action = Intent.ACTION_VIEW And _
		Intent.GetData <> Null And Intent.GetData.StartsWith(Application.PackageName)
End Sub
#else if B4I
Public Sub CallFromOpenUrl (url As String)
	If url.StartsWith(packageName & ":/oath") Then
		ParseBrowserUrl(url)
	End If
End Sub

Private Sub GetPackageName As String
	Dim no As NativeObject
	no = no.Initialize("NSBundle").RunMethod("mainBundle", Null)
	Dim name As Object = no.RunMethod("objectForInfoDictionaryKey:", Array("CFBundleIdentifier"))
	Return name
End Sub

#end if

Private Sub ParseBrowserUrl(Response As String)
	Dim m As Matcher = Regex.Matcher("code=([^&\s]+)", Response)
	If m.Find Then
		Dim code As String = m.Group(1)
		GetTokenFromAuthorizationCode(code)
	Else
		Log("Error parsing server response: " & Response)
		ResetToken
		RaiseEvent(False)
	End If
End Sub

Private Sub RaiseEvent(Success As Boolean)
	CallSubDelayed3(mTarget, mEventName & "_AccessTokenAvailable", Success, ti.AccessToken)
End Sub


Private Sub GetTokenFromAuthorizationCode (Code As String)
	Log("Getting access token from authorization code...")
	Dim j As HttpJob
	j.Initialize("", Me)
	Dim postString As String = $"code=${Code}&client_id=${mClientId}&grant_type=authorization_code&redirect_uri=${GetRedirectUri}"$
	postString = AddClientSecret(postString)
	j.PostString("https://www.googleapis.com/oauth2/v4/token", postString)
		
	Wait For (j) JobDone(j As HttpJob)
	If j.Success Then
		TokenInformationFromResponse(j.GetString)
	Else
		ResetToken
		RaiseEvent(False)
	End If
	j.Release
End Sub

Private Sub GetTokenFromRefresh
	Log("Getting access token from refresh token...")
	Dim j As HttpJob
	j.Initialize("", Me)
	Dim postString As String = $"refresh_token=${ti.RefreshToken}&client_id=${mClientId}&grant_type=refresh_token&redirect_uri=${GetRedirectUri}"$
	postString = AddClientSecret(postString)
	j.PostString("https://www.googleapis.com/oauth2/v4/token", postString)
	Wait For (j) JobDone(j As HttpJob)
	If j.Success Then
		TokenInformationFromResponse(j.GetString)
	Else
		RaiseEvent(False)
	End If
	j.Release
End Sub

Private Sub AddClientSecret (s As String) As String
	If mClientSecret <> "" Then 
		s = s & "&client_secret=" & mClientSecret
	End If
	Return s
End Sub

Private Sub TokenInformationFromResponse (s As String)
	Dim jp As JSONParser
	jp.Initialize(s)
	Dim m As Map = jp.NextObject
	ti.AccessExpiry = DateTime.Now + m.Get("expires_in") * 1000 - 5 * 60 * 1000
	ti.AccessToken = m.Get("access_token")
	If m.ContainsKey("refresh_token") Then ti.RefreshToken = m.Get("refresh_token")
	ti.Valid = True
	Log($"Token received. Expires: $DateTime{ti.AccessExpiry}"$)
	SaveToken
	RaiseEvent(True)
End Sub



Private Sub BuildLink(Url As String, Params As Map) As String
	Dim su As StringUtils
	Dim sb As StringBuilder
	sb.Initialize
	sb.Append(Url)
	If Params.Size > 0 Then
		sb.Append("?")
		For Each k As String In Params.Keys
			sb.Append(su.EncodeUrl(k, "utf8")).Append("=").Append(su.EncodeUrl(Params.Get(k), "utf8"))
			sb.Append("&")
		Next
		sb.Remove(sb.Length - 1, sb.Length)
	End If
	Return sb.ToString
End Sub