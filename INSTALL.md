# Installing the BBF report tool

_These instructions should work for all Unix-like systems, including Linux and Mac OS._

You could download just `report.pl` (found in the [Report_Tool]() folder), but it's probably best to clone the entire `cwmp-xml-tools` repository.

Having placed `report.pl` in a local directory, ensure this directory is included in the executable `PATH`.

Now try to execute `report.pl`. If it complains about missing Perl modules (e.g., `Data::Compare` and `String::Tokenizer`), use the `cpan` tool (or other appropriate method) to install the missing modules (you might find [this website](http://www.microhowto.info/howto/install_a_perl_module.html) helpful).

If executing `report.pl --version` outputs the current version and no errors, `report.pl` has been successfully installed.

# Installing BBF data model files

Clone the [cwmp-data-models](https://github.com/BroadbandForum/cwmp-data-models) and/or [usp-data-models](https://github.com/BroadbandForum/usp-data-models) repositories and use the BBF report tool `--include` option to ensure that the appropriate directory is searched.

# Installing the Report GUI on a Windows system

See the `README.txt` instructions in the [ReportGUI]() folder. `ReportGUI` will automatically attempt to set up its own install directory.

# Installing from the BBF Bitbucket private repositories

See the [BUS Data Modeling Bitbucket Repositories](https://wiki.broadband-forum.org/display/BBF/BUS+Data+Modeling+Bitbucket+Repositories) wiki page. This requires members-only login to the BBF Confluence site.
