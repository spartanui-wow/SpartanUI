param([switch]$AssetsOnly, [switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'Cards.cs') -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives,System.Private.Windows.Core,System.Private.Windows.GdiPlus,System.Runtime,System.Runtime.InteropServices,System.Collections,System.Linq,System.Console
$repo = Split-Path (Split-Path $PSScriptRoot)
if ($VerifyOnly) { [Cards]::Verify($repo) }
elseif ($AssetsOnly) { [Cards]::AssetSheet($repo) }
else { [Cards]::Build($repo); [Cards]::Verify($repo) }

