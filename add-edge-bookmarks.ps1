$path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

New-Item -Path $path -Force | Out-Null

$managedFavorites = @'
[
  {
    "toplevel_name": "FortiWeb Labs"
  },
  {
    "name": "XPERTS Hands-on-Labs",
    "url": "https://canada.amerintlxperts.com/hands-on-labs.html"
  },
  {
    "name": "FortiWeb Admin",
    "url": "http://fwb-xperts.labsec.ca:8080"
  },
  {
    "name": "Demo Tool",
    "url": "http://demotool-xperts.labsec.ca:8080"
  },
  {
    "name": "DVWA",
    "url": "http://dvwa-xperts.labsec.ca"
  },
  {
    "name": "Banking Application",
    "url": "http://bank-xperts.labsec.ca"
  },
  {
    "name": "MCP Server",
    "url": "http://mcp-xperts.labsec.ca"
  },
  {
    "name": "Juiceshop",
    "url": "http://juiceshop-xperts.labsec.ca"
  },
  {
    "name": "Petstore",
    "url": "http://petstore3-xperts.labsec.ca"
  },
  {
    "name": "Speedtest",
    "url": "http://speedtest-xperts.labsec.ca"
  },
  {
    "name": "CSP Server",
    "url": "http://csp-xperts.labsec.ca"
  }
]
'@

Set-ItemProperty `
  -Path $path `
  -Name "ManagedFavorites" `
  -Value $managedFavorites `
  -Type String
