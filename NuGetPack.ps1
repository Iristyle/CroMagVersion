param(
  [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
  [string]
  $apiKey,
  [Parameter(Mandatory = $false)]
  [string]
  $source = ''
)

function Get-CurrentDirectory
{
  $thisName = $MyInvocation.MyCommand.Name
  [IO.Path]::GetDirectoryName((Get-Content function:$thisName).File)
}

function Get-NugetPath
{
  Write-Host "Executing Get-NugetPath"
  Get-ChildItem -Path (Get-CurrentDirectory) -Include 'nuget.exe' -Recurse |
    Select -ExpandProperty FullName -First 1
}

function Restore-Nuget
{
  Write-Host "Executing Restore-Nuget"
  $nuget = Get-NugetPath

  if ($nuget -ne $null)
  {
      return $nuget
  }

  #$msbuild = "c:\windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
  Start-Process 'msbuild' -ArgumentList "NugetRestore.proj" `
    -WorkingDirectory (Join-Path (Get-CurrentDirectory) '.nuget') -NoNewWindow -Wait
  Get-NugetPath
}

function Pack-And-Push
{
  $currentDirectory = Get-CurrentDirectory
  Write-Host "Running against $currentDirectory"

  $nuget = Restore-Nuget

  Get-ChildItem -Path $currentDirectory -Filter *.nuspec -Recurse |
    ? { $_.FullName -inotmatch 'packages' } |
    % {
      $csproj = Join-Path $_.DirectoryName ($_.BaseName + '.csproj')
      $cmdLine = if (Test-Path $csproj)
      {
        "pack $csproj -Prop Configuration=Release -Exclude '**\*.CodeAnalysisLog.xml'"
      }
      else { "pack $_"}

      Start-Process $nuget -ArgumentList $cmdLine -NoNewWindow -Wait
    }

  Get-ChildItem *.nupkg |
    % {
      Write-Host "Value of source -> $source"
      if ($source -eq '') { &$nuget push $_ $apiKey }
      else { &$nuget push $_ $apiKey -s $source }
    }
}

del *.nupkg
Pack-And-Push
del *.nupkg