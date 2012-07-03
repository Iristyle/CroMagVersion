param($installPath, $toolsPath, $package, $project)

Add-Type -AssemblyName 'Microsoft.Build, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'
$msbuild = [Microsoft.Build.Evaluation.ProjectCollection]::GlobalProjectCollection.GetLoadedProjects($project.FullName) | Select-Object -First 1
$solution = Get-Interface $dte.Solution ([EnvDTE80.Solution2])

#see if there are any other projects in the solution using version.props?
#we can't delete from disk since there may be 'sibling' solutions using the file, but we can delete the version.props
#reference from 'Build' folder
$projectsWithRefs = Get-Project -All |
  % { [Microsoft.Build.Evaluation.ProjectCollection]::GlobalProjectCollection.GetLoadedProjects($_.FullName) } |
  ? { ($_.Xml.Properties | ? { $_.Name -ieq $package.Id } | Measure-Object | Select -ExpandProperty Count) -gt 0 }
$projectsWithRefsCount = ($projectsWithRefs | Measure-Object | Select -ExpandProperty Count)
Write-Host "Found $projectsWithRefsCount projects using CroMagVersion."

#find Build solution folder and the ref to version.props
$buildFolder = $solution.Projects | ? { $_.Name -ieq 'Build' } | Select-Object -First 1
if (($projectsWithRefsCount -eq 1) -and ($buildFolder -ne $null))
{
  #delete the ref IFF we're the last project using it
  $buildFolder.ProjectItems | ? { $_.Name -ieq 'version.props' } |
    % {
      $_.Remove()
      Write-Host "Remove $versionProps from solution folder."
    }

  if ($buildFolder.ProjectItems.Count -eq 0)
  {
    $buildFolder.Delete()
    Write-Host "Remove empty Build solution folder."
  }
}

#if other projects are using SharedAssemblyInfo.cs, it gets recreated next build ...
#but if we're last man standing, we must do this to allow packages folder to be deleted
$sharedAssemblyInfo = Join-Path $toolsPath 'SharedAssemblyInfo.cs'

del $sharedAssemblyInfo -ErrorAction SilentlyContinue
Write-Host "Deleted $sharedAssemblyInfo"

#Remove CROMAG property from build constants
$msbuild.Xml.Properties |
  ? { ($_.Name -ieq 'DefineConstants') -and ($_.Value -imatch '\bCROMAG\b') } |
  % { $_.Value = $_.Value -ireplace '\bCROMAG\b', '' }

#remove targets path property
$msbuild.Xml.Properties | ? { $_.Name -ieq $package.Id } |
  % {
    $_.Parent.RemoveChild($_)
    Write-Host "Removed property $($package.Id) from project file"
  }

# and target if necessary
$targetsPath = "`$($($package.Id))\$($package.Id).targets"
$msbuild.Xml.Imports |
  ? { $_.Project -ieq $targetsPath } |
  % {
    $_.Parent.RemoveChild($_)
    Write-Host "Removed import of $targetsPath."
  }

$msbuild.Xml.Targets |
  ? { $_.Name -ieq $package.Id } |
  % {
    $_.Parent.RemoveChild($_)
    Write-Host "Removed $($package.Id) Target."
  }

$paths = @("`$($($package.Id))\SharedAssemblyInfo.cs",
    "`$($($package.Id))\CroMagVersion.tt")
$sharedAssemblyInfoPath =
$msbuild.Xml.Items |
  ? { $paths -icontains $_.Include } |
  % {
    $_.Parent.RemoveChild($_)
    Write-Host "Removed link to $($_.Include)"
  }

$project.Save($project.FullName)