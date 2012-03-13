![Logo](https://github.com/EastPoint/CroMagVersion/raw/master/logo-128.png)

# CroMagVersion

CroMag helps to version all of the projects within a solution via a single file convention, and will bump build and version numbers of your project automatically during the build based on a date and version number scheme AND a build number variable that can originate from a build server like [Jenkins](http://jenkins-ci.org/).  Furthermore, DVCS changeset hashes also make their way into built assemblies.  

## Requirements

* Nuget
* Package restore via [PepitaGet](http://code.google.com/p/pepita/) (or Nuget) highly recommended
* MSBuild 4 or higher (uses static property functions)
* To have the current short SHA1 hash added to AssemblyConfiguration, you must be using Mercurial or Git


## What does it do?

CroMagVersion allows projects to share the following assembly attributes:

* [AssemblyCompany](http://msdn.microsoft.com/en-us/library/system.reflection.assemblycompanyattribute.aspx) - Uses $(VersionCompany) and $(VersionCompanyUrl) from ```version.props```
* [AssemblyCopyright](http://msdn.microsoft.com/en-us/library/system.reflection.assemblycopyrightattribute.aspx) - Copyright $(Year) $(VersionCompany) from ```version.props```
* [AssemblyConfiguration](http://msdn.microsoft.com/en-us/library/system.reflection.assemblyconfigurationattribute.aspx) - Annotated with build Configuration (i.e. Debug, Release) and the SHA1 hash of the current source version

* [AssemblyVersion](http://msdn.microsoft.com/en-us/library/system.reflection.assemblyversionattribute.aspx) - Calculates date convention based version
* [AssemblyFileVersion](http://msdn.microsoft.com/en-us/library/system.reflection.assemblyfileversionattribute.aspx) - Calculates date convention based version by default, but the layout can be customized (see below)
* [AssemblyInformationalVersion](http://msdn.microsoft.com/en-us/library/system.reflection.assemblyinformationalversionattribute.aspx) - Calculates date convention based version, but the layout can be customized (see below)

## How does it work?

* During the package installation ```SharedAssemblyInfo.cs``` is added to the project file as a **linked file**.  This file will be shared amongst all projects that install the package, and not actually copied into any projects.

* A new msbuild file called ```version.props``` is copied to the solution folder if it doesn't exist - this is where user modifications such as major and minor version should be made.  These values are configurable and should always be modified by hand as needed.  If following semantic guidelines, there's no easy way to identify what things are breaking changes - this requires a human of at least average intelligence.

```xml
<MajorVersion>0</MajorVersion>
<MinorVersion>1</MinorVersion>
<VersionCompany></VersionCompany>
<VersionCompanyUrl></VersionCompanyUrl>
<!-- Typically this value will be supplied by a build server like Jenkins -->
<!-- 
<BUILD_NUMBER>0</BUILD_NUMBER>
-->
```


* A ```CroMagVersion.targets``` file is injected into the project as an [Import](http://msdn.microsoft.com/en-us/library/92x05xfs.aspx) that contains the version update code

* Before the build goes down, ```SharedAssemblyInfo.cs``` file is updated with the major / minor version from ```version.props``` and has date based version information added in the following format:
$(MajorVersion).$(MinorVersion).$(YearMonth).$(DayNumber)$(Build)

    * ```YearMonth``` is a 2 digit year, 2 digit month - for instance 1203
    * ```DayNumber``` is a 2 digit day - for instance 03 or 31
    * ```$(Build)``` is 0 by default, or ```BUILD_NUMBER``` environment variable as supplied by Jenkins or via an override in ```version.props```.  Only the last 3 digits of this number can be used, as each fragment of the build number has a maximum of 65536.


Is this the best way to date tag a build?  Not necessarily, but it's a pretty reasonable solution that results in something human readable after the fact.

## Customizing The Layout

```AssemblyFileVersion``` and ```AssemblyInformationalVersion``` can have customized layouts by enabling ```AssemblyFileVersionLayout``` or ```AssemblyInformationalVersionLayout``` in ```version.props``` .  This may be necessary to deal with wacky installers (like MSI) that don't consider a bump to the 3rd number significant enough to upgrade an existing product install.  Sigh...

The following is pretty self-explanatory:

```xml
<!-- Available variables for a custom layout are:
	$(MajorVersion) - from this file
	$(MinorVersion) - from this file
	$(BUILD_NUMBER) - original number from build server / environment variable if available, otherwise 0, unless overriden in this file
	$(Build) - BUILD_NUMBER truncated to last 3 digits
	$(YearMonth) - yyMM
	$(DayNumber) - dd
	$(Year) - yyyy

	$(BuildVersion) - $(YearMonth)
	$(RevisionVersion) - $(DayNumber)$(Build)

	$(VersionNumber) - $(MajorVersion).$(MinorVersion).$(BuildVersion).$(RevisionVersion)

	Note that these are NOT proper MSBuild variables, and therefore
	arbitrary variables will not resolve.  Only these whitelisted
	variables will do anything.  All other strings, valid or not,
	will be treated as plaintext.
-->

<!--
<AssemblyFileVersionLayout>$(MajorVersion).$(MinorVersion).$(BuildVersion).$(RevisionVersion)</AssemblyFileVersionLayout>
<AssemblyInformationalVersionLayout>$(MajorVersion).$(MinorVersion).$(BuildVersion).$(RevisionVersion)</AssemblyInformationalVersionLayout>
-->
```

## A note about naming conventions

This project follows the standard .NET style naming convention specified by [System.Version](http://msdn.microsoft.com/en-us/library/system.version.aspx) of Major.Minor.Build.Revision, where the 3rd and 4th numbers are Build and Revision.

Other systems tend to use different schemes:
* Major.Minor.Revision.Build - common many places, including, Java
* Major.Minor.Patch - for instance [SemVer](http://semver.org/)
* Major.Minor.Build, for instance MSI [ProductVersion](http://msdn.microsoft.com/en-us/library/windows/desktop/aa370859\(v=vs.85\).aspx).

The names for the slots aren't important so much as the semantics.

## Similar Projects

* [SemVerHarvester](https://github.com/jennings/SemVerHarvester) - MSBuild task library that harvests version numbers from tags in source control versions.  It appears to work with both Git and Mercurial.

## Future Improvements

* Ensure Mono works properly

## Contributing

Fork the code, and submit a pull request!  

Any useful changes are welcomed.  If you have an idea you'd like to see implemented that strays far from the simple spirit of the application, ping us first so that we're on the same page.

## Credits

* [MSBuild.Mercurial](http://msbuildhg.codeplex.com/) - tasks for retrieving info from a hg repo
* [Git-Last-Commit Gist](https://gist.github.com/966148) - inline msbuild task for grabbing Git command line output
* [StackOverlow - How can I auto increment the C# assembly version via our CI platform (Hudson)?](http://stackoverflow.com/questions/1126880/how-can-i-auto-increment-the-c-assembly-version-via-our-ci-platform-hudson)
* [Mercurial Revision No to Version your AssemblyInfo - MsBuild Series](http://markkemper1.blogspot.com/2010/10/mercurial-revision-no-to-version-your.html)
* The logo is from the [Dino Icon Pack](http://www.fasticon.com/freeware/dino-icons/) produced by FastIcon.