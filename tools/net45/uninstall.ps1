param($installPath, $toolsPath, $package, $project)
 
  # Need to load MSBuild assembly if it's not loaded yet.
  Add-Type -AssemblyName 'Microsoft.Build, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'

  # Grab the loaded MSBuild project for the project
  $msbuild = [Microsoft.Build.Evaluation.ProjectCollection]::GlobalProjectCollection.GetLoadedProjects($project.FullName) | Select-Object -First 1

  # Find all the imports and targets added by this package.
  $itemsToRemove = @()

  # Allow many in case a past package was incorrectly uninstalled
  $itemsToRemove += $msbuild.Xml.Imports | Where-Object { $_.Project.EndsWith($package.Id + '.targets') }
  
  # Remove the elements and save the project
  if ($itemsToRemove -and $itemsToRemove.length)
  {
     foreach ($itemToRemove in $itemsToRemove)
     {
         $msbuild.Xml.RemoveChild($itemToRemove) | out-null
     }     
  }

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

  $project.Save()