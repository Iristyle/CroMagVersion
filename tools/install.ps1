param($installPath, $toolsPath, $package, $project)

#recursive search project for a given file name and return its project relative path
function Get-RelativeFilePath
{
  param($projectItems, $fileName)

  $match = $projectItems | ? { $_.Name -eq $fileName } |
      Select -First 1

  if ($null -ne $match) { return $match.Name }

  $projectItems | ? { $_.Kind -eq '{6BB5F8EF-4483-11D3-8BCF-00C04F8EC28C}' } |
    % {
        $match = Get-RelativeFilePath $_.ProjectItems $fileName
        if ($null -ne $match)
        {
            return (Join-Path $_.Name $match)
        }
    }
}

function AddOrGetItem($xml, $type, $path)
{
  $include = $xml.Items |
      ? { $_.Include -ieq $path } |
      Select-Object -First 1

  if ($include -ne $null) { return $include }

  Write-Host "Adding item of type $type to $path."
  return $xml.AddItem($type, $path)
}

function AddOrGetTask($target, $name)
{
  $task = $target.Tasks |
    ? { $_.Name -ieq $name } |
    Select-Object -First 1

  if ($task -ne $null) { return $task }

  Write-Host "Adding task $name."
  return $target.AddTask($name)
}

function AddOrGetTarget($xml, $name)
{
  $target = $xml.Targets |
    ? { $_.Name -ieq $name } |
      Select-Object -First 1

  if ($target -ne $null) { return $target }

  Write-Host "Adding inline $name target."
  return $xml.AddTarget($name)
}

function SetItemMetadata($item, $name, $value)
{
  $match = $item.Metadata |
    ? { $_.Name -ieq $name } |
    Select-Object -First 1

  if ($match -eq $null)
  {
    [Void]$item.AddMetadata($name, $value)
    Write-Host "Added metadata $name"
  }
  else { $match.Value = $value }
}

function SetProperty($xml, $name, $value)
{
  $property = $xml.Properties |
    ? { $_.Name -ieq $name } |
    Select-Object -First 1

  if ($property -eq $null)
  {
    [Void]$xml.AddProperty($name, $value)
    Write-Host "Added property $name"
  }
  else { $property.Value = $value }
}

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
$buildFolder = $solution.Projects | ? { $_.Name -ieq 'Build' } |
    Select-Object -First 1
if ($buildFolder -eq $null) { $buildFolder = $solution.AddSolutionFolder('Build') }
$versionPropsExists = ($buildFolder.ProjectItems |
    ? { $_.Name -ieq 'version.props' } |
    Measure-Object | Select -ExpandProperty Count) -gt 0
if (! ($versionPropsExists))
{
    $buildFolder.ProjectItems.AddFromFile($versionProps)
    Write-Host "Added $versionProps to solution folder."
    $dte.ItemOperations.OpenFile($versionProps)
}

#comment stuff we'll share out of existing AssemblyInfo.cs
$projectPath = ([IO.Path]::GetDirectoryName($project.FullName))
$existingAssemblyInfoPath = Join-Path $projectPath (Get-RelativeFilePath $project.ProjectItems 'AssemblyInfo.cs')
if (($existingAssemblyInfoPath -imatch 'AssemblyInfo.cs') -and (Test-Path $existingAssemblyInfoPath))
{
    $attribRegex = '^([^//].*(AssemblyCompany|AssemblyCopyright|AssemblyConfiguration|AssemblyVersion|AssemblyFileVersion|AssemblyInformationalVersion).*)$'
    (Get-Content $existingAssemblyInfoPath) -ireplace $attribRegex, '//$1' |
      Out-File $existingAssemblyInfoPath -Encoding UTF8
    Write-Host "Commented relevant sections of $existingAssemblyInfoPath."
}

Add-Type -AssemblyName 'Microsoft.Build, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'

#http://msdn.microsoft.com/en-us/library/microsoft.build.evaluation.project
#http://msdn.microsoft.com/en-us/library/microsoft.build.construction.projectrootelement
#http://msdn.microsoft.com/en-us/library/microsoft.build.construction.projectitemelement
$msbuild = [Microsoft.Build.Evaluation.ProjectCollection]::GlobalProjectCollection.GetLoadedProjects($project.FullName) | Select-Object -First 1

#Add the CROMAG property to any constants that aren't defined DEBUG
$msbuild.Xml.Properties |
  ? { ($_.Name -ieq 'DefineConstants') -and ($_.Value -inotmatch 'DEBUG') `
    -and ($_.Value -inotmatch 'CROMAG') } |
  % { $_.Value += ';CROMAG' }

# trash old import target if it exists
$targetsPath = "`$($($package.Id))\$($package.Id).targets"
$msbuild.Xml.Imports |
    ? { $_.Project -ieq $targetsPath } |
    % {
        $_.Parent.RemoveChild($_)
        Write-Host "Removed import of $targetsPath."
    }

# Make the path to the targets file relative.
$projectUri = New-Object Uri("file://$($project.FullName)")
$targetUri = New-Object Uri("file://$($toolsPath)")
$relativePath = $projectUri.MakeRelativeUri($targetUri).ToString() `
  -replace [IO.Path]::AltDirectorySeparatorChar, [IO.Path]::DirectorySeparatorChar

#update CroMagVersion path based on version
SetProperty $msbuild.Xml $package.Id $relativePath

# add the inline target if necessary
#TODO: must occur after import of Microsoft.CSharp.targets
$target = AddOrGetTarget $msbuild.Xml 'CroMagVersion'
$target.Condition = '$(DefineConstants.Contains(''CROMAG''))'
$target.BeforeTargets = 'CoreCompile'

$exec = AddOrGetTask $target 'Exec'
#HACK: trailing space from quoted -a params is critically necessary
#Mono.Options will treat a \" as a C# escaped string, so eats the \
$exec.SetParameter('Command',
  '$(CroMagVersion)\TextTransform.exe -o="$(CroMagVersion)\SharedAssemblyInfo.cs" -a="Configuration!$(Configuration) " -a="SolutionDir!$(SolutionDir) " "$(CroMagVersion)\CroMagVersion.tt"')
$exec.SetParameter('WorkingDirectory', '$(MSBuildThisFileDirectory)')
$exec.SetParameter('CustomErrorRegularExpression', '.*: ERROR .*')

#link in sharedAssemblyInfo to the project
$sharedAssemblyInfo = Join-Path $toolsPath 'SharedAssemblyInfo.cs'
'' | Out-File $sharedAssemblyInfo

$sharedAssemblyInfoPath = "`$($($package.Id))\SharedAssemblyInfo.cs"
$item = AddOrGetItem $msbuild.Xml 'Compile' $sharedAssemblyInfoPath
SetItemMetadata $item 'Link' 'Properties\SharedAssemblyInfo.cs'
SetItemMetadata $item 'AutoGen' 'True'
SetItemMetadata $item 'DesignTime' 'True'
SetItemMetadata $item 'DependentUpon' 'CroMagVersion.tt'

$templatePath = "`$($($package.Id))\CroMagVersion.tt"
$item = AddOrGetItem $msbuild.Xml 'None' $templatePath
SetItemMetadata $item 'Link' 'Properties\CroMagVersion.tt'
SetItemMetadata $item 'Generator' 'TextTemplatingFileGenerator'
SetItemMetadata $item 'LastGenOutput' 'SharedAssemblyInfo.cs'

$project.Save($project.FullName)