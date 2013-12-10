param($installPath, $toolsPath, $package, $project)
    # This is the MSBuild targets file to add
    $targetsFile = [System.IO.Path]::Combine([System.IO.Path]::Combine($toolsPath, "..\"), $package.Id + '.targets')
 
    # Need to load MSBuild assembly if it's not loaded yet.
    Add-Type -AssemblyName 'Microsoft.Build, Version=3.5.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'

    # Grab the loaded MSBuild project for the project
    $msbuild = [Microsoft.Build.Evaluation.ProjectCollection]::GlobalProjectCollection.GetLoadedProjects($project.FullName) | Select-Object -First 1
 
    # Make the path to the targets file relative.
    $projectUri = new-object Uri($project.FullName, [System.UriKind]::Absolute)
    $targetUri = new-object Uri($targetsFile, [System.UriKind]::Absolute)
    $relativePath = [System.Uri]::UnescapeDataString($projectUri.MakeRelativeUri($targetUri).ToString()).Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)
 
    # Add the import with a condition, to allow the project to load without the targets present.
    $import = $msbuild.Xml.AddImport($relativePath)
    $import.Condition = "Exists('$relativePath')"

    #copy version.props to same directory as solution
    $solution = Get-Interface $dte.Solution ([EnvDTE80.Solution2])
    $solutionPath = [IO.Path]::GetDirectoryName($solution.FileName)
    $versionProps = Join-Path $solutionPath 'version.props'
    Write-Host "Looking for $versionProps"

    if (!(Test-Path $versionProps))
    {
        $sourceVersionProps = (Join-Path $toolsPath '/../version.props')
        Write-Host "Copying $sourceVersionProps to $versionProps"
        Copy-Item $sourceVersionProps $versionProps
    }

    #then add Build solution folder and a ref to the file
    $buildFolder = $solution.Projects | ? { $_.Name -ieq 'Build' } | Select-Object -First 1
    if ($buildFolder -eq $null) 
    { 
        $buildFolder = $solution.AddSolutionFolder('Build') 
    }

    #properties folder for project
    propertiesFolder = $project | ? { $_.Name -ieq 'Properties' } | Select-Object -First 1

    $versionPropsExists = ($buildFolder.ProjectItems | ? { $_.Name -ieq 'version.props' } | Measure-Object | Select -ExpandProperty Count) -gt 0

    if (!($versionPropsExists))
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
        (Get-Content $existingAssemblyInfoPath) -ireplace $attribRegex, '//$1' | Out-File $existingAssemblyInfoPath -Encoding UTF8
        Write-Host "Commented relevant sections of $existingAssemblyInfoPath."
    }

    #Set the correct properties for imported files
    $propertiesFolder = $project.ProjectItems.Item("Properties")

    $versionProps = $propertiesFolder.ProjectItems.Item("version.props")
    $versionProps.Properties.Item("BuildAction").Value = [int]0
    
    $croMagVersion = $propertiesFolder.ProjectItems.Item("CroMagVersion.tt")
    $croMagVersion.Properties.Item("BuildAction").Value = [int]0
    $croMagVersion.Properties.Item("Generator").Value = "TextTemplatingFileGenerator"
    $croMagVersion.Properties.Item("LastGenOutput").Value = "CroMagVersion.cs"
    
    $sharedAssemblyInfo = $propertiesFolder.ProjectItems.Item("CroMagVersion.cs")
    $sharedAssemblyInfo.Properties.Item("BuildAction").Value = [int]1
    $sharedAssemblyInfo.Properties.Item("AutoGen").Value = "True"
    $sharedAssemblyInfo.Properties.Item("DesignTime").Value = "True"
    $sharedAssemblyInfo.Properties.Item("DependentUpon").Value = "CroMagVersion.tt"

    $project.Save()