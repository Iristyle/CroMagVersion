param($installPath, $toolsPath, $package, $project)

$targetsFileName = 'CroMagVersion.targets'

#copy version.props to same directory as solution
$solution = Get-Interface $dte.Solution ([EnvDTE80.Solution2])
$solutionPath = [IO.Path]::GetDirectoryName($solution.FileName)
$versionProps = Join-Path $solutionPath 'version.props'
Write-Host "Looking for $versionProps"

if (! (Test-Path $versionProps))
{
    $sourceVersionProps = (Join-Path $toolsPath 'version.props')
    Write-Host "Copying $sourceVersionProps to $versionProps"
    Copy-Item $sourceVersionProps $versionProps    
}

#then add Build solution folder and a ref to the file
$buildFolder = $solution.Projects | ? { $_.Name -ieq 'Build' } | Select-Object -First 1
if ($buildFolder -eq $null) { $buildFolder = $solution.AddSolutionFolder('Build') }
$versionPropsExists = ($buildFolder.ProjectItems | ? { $_.Name -ieq 'version.props' } | 
    Measure-Object | Select -ExpandProperty Count) -gt 0
if (! ($versionPropsExists))
{
    $buildFolder.ProjectItems.AddFromFile($versionProps)  
    Write-Host "Added $versionProps to solution folder."  
}

#link in sharedAssemblyInfo to the project
$sharedAssemblyInfo = Join-Path $toolsPath 'SharedAssemblyInfo.cs'
'' | Out-File $sharedAssemblyInfo
$propertiesFolder = $project.ProjectItems.Item('Properties')
$sharedExists = ($propertiesFolder.ProjectItems | ? { $_.Name -ieq 'SharedAssemblyInfo.cs' } | 
    Measure-Object | Select -ExpandProperty Count) -gt 0

if (! ($sharedExists))
{    
    $propertiesFolder.ProjectItems.AddFromFile($sharedAssemblyInfo)
    Write-Host "Added link to SharedAssemblyInfo.cs."
}

#comment stuff we'll share out of existing AssemblyInfo.cs
$existingAssemblyInfo = $propertiesFolder.ProjectItems.Item('AssemblyInfo.cs')
$existingAssemblyInfoPath = Join-Path ([IO.Path]::GetDirectoryName($project.FullName)) 'Properties\AssemblyInfo.cs'
$attribRegex = '^([^//].*(AssemblyCompany|AssemblyCopyright|AssemblyConfiguration|AssemblyVersion|AssemblyFileVersion|AssemblyInformationalVersion).*)$'
(Get-Content $existingAssemblyInfoPath) -ireplace $attribRegex, '//$1' | Out-File $existingAssemblyInfoPath -Encoding UTF8
Write-Host "Commented relevant sections of $existingAssemblyInfoPath."

$project.Save($project.FullName)

Add-Type -AssemblyName 'Microsoft.Build, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'

$msbuild = [Microsoft.Build.Evaluation.ProjectCollection]::GlobalProjectCollection.GetLoadedProjects($project.FullName) | Select-Object -First 1

$targetsFile = Join-Path $toolsPath $targetsFileName

# Make the path to the targets file relative.
$projectUri = New-Object Uri("file://$($project.FullName)")
$targetUri = New-Object Uri("file://$($targetsFile)")
$relativePath = $projectUri.MakeRelativeUri($targetUri).ToString() -replace [IO.Path]::AltDirectorySeparatorChar, [IO.Path]::DirectorySeparatorChar

#update targets path
$msbuild.Xml.Properties | ? { $_.Name -ieq $package.Id } | % { $_.Parent.RemoveChild($_) }
$msbuild.Xml.AddProperty($package.Id, $relativePath ) | Out-Null
Write-Host "Added property $($package.Id)"

# add the target if necessary
$importExists = ($msbuild.Xml.Imports | 
? { $_.Project -ieq "`$($($package.Id))" } |
Measure-Object | Select -ExpandProperty Count) -gt 0

if (! ($importExists))
{
    $import = $msbuild.Xml.AddImport("`$($($package.Id))")
    $import.Condition = "Exists(`$($($package.Id)))"
    Write-Host "Added import of '$($relativePath)'."
}

