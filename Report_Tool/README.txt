Usage:
    report.pl [--allbibrefs] [--autobase] [--autodatatype] [--automodel]
    [--bibrefdocfirst] [--canonical] [--catalog=c]... [--compare]
    [--components] [--configfile=s("")] [--cwmpindex=s(..)]
    [--cwmppath=s(cwmp)] [--debugpath=p("")] [--deletedeprecated] [--diffs]
    [--diffsext=s(diffs)]... [--dtprofile=s]... [--dtspec[=s]]
    [--dtuuid[=s]] [--exitcode] [--help] [--ignore=p("")]
    [--importsuffix=s("")] [--include=d]... [--info] [--lastonly]
    [--loglevel=tn(i)] [--marktemplates] [--maxchardiffs=i(5)]
    [--maxworddiffs=i(10)] [--noautomodel] [--nocomments] [--nohyphenate]
    [--nolinks] [--nologprefix] [--nomodels] [--noobjects] [--noparameters]
    [--noprofiles] [--noshowreadonly] [--notemplates] [--nowarnredef]
    [--nowarnbibref] [--nowarnenableparameter] [--nowarnnumentries]
    [--nowarnreport] [--nowarnprofbadref] [--nowarnuniquekeys]
    [--nowarnwtref] [--objpat=p("")] [--option=n=v]... [--outfile=s]
    [--pedantic[=i(1)]] [--plugin=s]... [--quiet]
    [--report=html|htmlbbf|(null)|tab|text|xls|xml|xsd|other...]
    [--showdiffs] [--showreadonly] [--showspec] [--showsyntax] [--showunion]
    [--sortobjects] [--special=s] [--thisonly] [--tr106=s(TR-106)]
    [--trpage=s(http://www.broadband-forum.org/technical/download)]
    [--ucprofile=s]... [--ugly] [--upnpdm] [--verbose[=i(1)]]
    [--warnbibref[=i(1)]] [--writonly] DM-instance...

    *   the most common options are --include, --loglevel and --report=html

    *   use --compare to compare files and --showdiffs to show differences

    *   cannot specify both --report and --special

Options:
    --allbibrefs
        usually only bibliographic references that are referenced from
        within the data model definition are listed in the report; this
        isn't much help when generating a list of bibliographic references
        without a data model! that's what this option is for; currently it
        affects only html reports

    --autobase
        causes automatic addition of base attributes when models, parameters
        and objects are re-defined, and suppression of redefinition warnings
        (useful when processing auto-generated data model definitions)

        is implied by --compare

    --automodel
        enables the auto-generation, if no model element was encountered, of
        an auto-generated model that references each non-internal component,
        i.e. each component whose name doesn't begin with an underscore

        this is preferable to the (deprecated) --noautomodel because it
        allows various error messages to be suppressed

    --autodatatype
        causes the {{datatype}} template to be automatically prefixed for
        parameters with named data types

        this is deprecated because it is enabled by default

    --bibrefdocfirst
        causes the {{bibref}} template to be expanded with the document
        first, i.e. [DOC] Section n rather than the default of Section
        n/[DOC]

    --canonical
        new behavior: omits text that would cause lots of differences
        between nominally similar reports; is particularly aimed at allowing
        direct comparison of HTML generated from normative XML and from the
        "flattened" XML of the xml report

        old behavior: affected only the xml report; caused descriptions to
        be processed into a canonical form that eased comparison with the
        original Microsoft Word descriptions

    --catalog=s...
        can be specified multiple times; XML catalogs
        (http://en.wikipedia.org/wiki/XML_Catalog); the current directory
        and any directories specified via --include are searched when
        locating XML catalogs

        XML catalogs are used only when processing URL-valued schemaLocation
        attributes during DM instance validation; it is not necessary to use
        XML catalogs in order to validate DM instances; see --loglevel

    --compare
        compares the two files that were specified on the command line,
        showing the changes made by the second one

        note that this is identical to setting --autobase and --showdiffs;
        it also affects the behavior of --lastonly

    --components
        affects only the xml report; generates a component for each object;
        if --noobjects is also specified, the component omits the object
        definition and consists only of parameter definitions

    --configfile=s("")
        the name of the configuration file; the configuration file format
        and usage are specific to the report type; not all report types use
        configuration files

        the configuration file name can also be specified via --option
        configfile=s but this usage is deprecated

        defaults to report.ini where report is the report type, e.g.
        htmlbbf.ini for the htmlbbf report

    --cwmpindex=s(..)
        affects only the html report; specifies the location of the BBF CWMP
        index page, i.e. the page generated using the htmlbbf report; is
        used to generate a link back to the appropriate location within the
        index page

        defaults to ../cwmp (parent directory), which will work for the BBF
        web site but will not necessarily work in other locations; the
        generated link will be cwmpindex#xmlfile, e.g.
        ../cwmp#tr-069-1-0-0.xml

    --cwmppath=s(cwmp)
        affects only the htmlbbf report; specifies the location of the XML
        and HTML files relative to the BBF CWMP index page

        defaults to cwmp (sub-directory), which will work for the BBF web
        site; can be set to http://www.broadband-forum.org/cwmp to generate
        a local BBF CWMP index page that references published content

    --debugpath=p("")
        outputs debug information for parameters and objects whose path
        names match the specified pattern

    --deletedeprecated
        mark all deprecated or obsoleted items as deleted

    --diffs
        has the same affect as specifying both --lastonly (reports only
        items that were defined or last modified in the last XML file on the
        command line) and --showdiffs (visually indicates the differences)

    --diffsext=s(diffs)
        how diffs files referenced by the htmlbbf report are named; for DM
        Instance foo.xml, the diffs file name is foo-diffsext.html; the
        default is diffs, i.e. the default file name is foo-diffs.html

        note: as an advanced feature, if this option is specified twice, the
        first value should be last and will be used for files known to be
        named foo-last.html on the BBF CWMP page, and the second value
        (typically diffs) will be used for all other files

    --dtprofile=s...
        affects only the xml report; can be specified multiple times;
        defines profiles to be used to generate an example DT instance

        for example, specify Baseline to select the latest version of the
        Baseline pofile, or Baseline:1 to select the Baseline:1 profile

        base and extends attributes are honored, so (for example),
        Baseline:2 will automatically include Baseline:1 requirements

    --dtspec=s
        affects only the xml report; has an affect only when --dtprofile is
        also present; specifies the value of the top-level spec attribute in
        the generated DT instance; if not specified, the spec defaults to
        urn:example-com:device-1-0-0

    --dtuuid=s
        affects only the xml report; has an affect only when --dtprofile is
        also present; specifies the value of the top-level uuid attribute in
        the generated DT instance (there is no "uuid:" prefix); if not
        specified, the UUID defaults to 00000000-0000-0000-0000-000000000000

    --exitcode
        if specified, the exit code is minus the number of reported errors,
        which will typically be masked to 8 bits, e.g. 2 errors would result
        in an exit code of -2, which might become 254

        if not specified, the exit code is zero regardless of the number of
        errors

    --help
        requests output of usage information

    --ignore
        specifies a pattern; data models whose names begin with the pattern
        will be ignored

    --importsuffix=s("")
        specifies a suffix which, if specified, will be appended (preceded
        by a hyphen) to the name part of any imported files in b<xml>
        reports

    --include=d...
        can be specified multiple times; specifies directories to search for
        files specified on the command line or imported by other files

        *   for files specified on the command line, the current directory
            is always searched first

        *   for files imported by other files, the directory containing the
            first file is always searched first; this behavior has changed;
            previously the current directory was always searched

        *   no search is performed for files that already include directory
            names

    --info
        output details of author, date, version etc

    --lastonly
        reports only on items that were defined or last modified in the
        specification corresponding to the last XML file on the command line
        (as determined by the last XML file's spec attribute)

        if --compare is also specified, the "last only" criterion uses the
        file name rather than the spec (so the changes shown will always be
        those from the second file on the command line even if both files
        have the same spec)

    --loglevel=tn(i)
        sets the log level; this consists of a type and a sublevel (0-9);
        all messages up and including this sublevel will be output to
        stderr; the default type and sublevel are warning and 0, which means
        that by default only error, informational and sublevel 0 warning
        messages will be output

        by default, messages are output with a prefix consisting of the
        upper-case first letter of the log level type in parentheses,
        followed by a space; for example, "(E) " indicates an error message;
        the message prefix can be suppressed using --nologprefix

        the possible log level types, which can be abbreviated to a single
        character, are:

        fatal
            only fatal messages will be output; the sublevel is ignored

        error
            only fatal and error messages will be output; the sublevel is
            ignored

        info
            only fatal, error and informational messages will be output; the
            sublevel is ignored

        warning
            only fatal, error, informational and warning messages will be
            output; the sublevel distinguishes different levels of warning
            messages

            currently only warning messages with sublevels 0, 1 and 2 are
            distinguished, but all values in the range 0-9 are valid

        debug
            fatal, error, informational, warning and debug messages will be
            output; the sublevel distinguishes different levels of debug
            messages

            currently only debug messages with sublevels 0, 1 and 2 are
            distinguished, but all values in the range 0-9 are valid

        for example, a value of d1 will cause fatal, error, informational,
        all warning, and sublevel 0 and 1 debug messages to be output

        the log level feature is used to implement the functionality of
        --quiet, --pedantic and --verbose (all of which are still
        supported); these options are processed in the order (loglevel,
        quiet, pedantic, verbose), so (for example) --loglevel=d --pedantic
        is the same as --loglevel=w

        a log level of warning or debug also enables XML schema validation
        of DM instances; XML schemas are located using the schemaLocation
        attribute:

        *   if it specifies an absolute path, no search is performed

        *   if it specifies a relative path, the directories specified via
            --include are searched

        *   URLs are treated specially; if XML catalogs were supplied (see
            --catalog) then they govern the behavior; otherwise, the
            directory part is ignored and the schema is located as for a
            relative path (above)

    --marktemplates
        mark selected template expansions with &&&& followed by
        template-related information, a colon and a space

        for example, the reference template is marked by a string such as
        &&&&pathRef-strong:, &&&&pathRef-weak:, &&&&instanceRef-strong:,
        &&&&instanceRef-strong-list: or enumerationRef:

        and the list template is marked by a string such as
        &&&&list-unsignedInt: or &&&&list-IPAddress:

    --maxchardiffs=i(5), --maxworddiffs=i(10)
        these control how differences are shown in descriptions; each
        paragraph is handled separately

        *   if the number of inserted and/or deleted characters in the
            paragraph is less than or equal to maxchardiffs, changes are
            shown at the character level

        *   otherwise, if the number of inserted and/or deleted words in the
            paragraph is less than or equal to maxworddiffs, changes are
            shown at the word level

        *   otherwise, the entire paragraph is shown as a single change

    --noautomodel
        disables the auto-generation, if no model element was encountered,
        of an auto-generated model that references each non-internal
        component, i.e. each component whose name doesn't begin with an
        underscore

        this is deprecated in favor of --automodel and will be removed in a
        future version (at which point the default behavior will be changed
        so an automatic model is not created)

        it is better to use --automodel because it allows various error
        messages to be suppressed

    --nocomments
        disables generation of XML comments showing what changed etc
        (--verbose always switches it off)

    --nohyphenate
        prevents automatic insertion of soft hyphens

    --nolinks
        affects only the html report; disables generation of hyperlinks
        (which makes it easier to import HTML into Word documents)

    --nologprefix
        suppresses log message prefixes, i.e. the strings such as "E: " or
        "W: " that indicate errors, warnings etc

    --nomodels
        specifies that model definitions should not be reported

    --noobjects
        affects only the xml report when --components is specified; omits
        objects from component definitions

    --noparameters
        affects only the xml report when --components is specified; omits
        parameters from component definitions

        NOT YET IMPLEMENTED

    --noprofiles
        specifies that profile definitions should not be reported

    --noshowreadonly
        disables showing read-only enumeration and pattern values as
        READONLY

    --notemplates
        suppresses template expansion (currently affects only html reports

    --nowarnbibref
        disables bibliographic reference warnings

        see also --warnbibref

    --nowarnnableparameter
        disables warnings when a writable table has no enable parameter

    --nowarnnumentries
        disables warnings (and/or errors) when a multi-instance object has
        no associated NumberOfEntries parameter

        this is always an error so disabling these warnings isn't such a
        good idea

    --nowarnredef
        disables parameter and object redefinition warnings (these warnings
        are also output if --verbose is specified)

        there are some circumstances under which parameter or object
        redefinition is not worthy of comment

    --nowarnreport
        disables the inclusion of error and warning messages in reports
        (currently only in HTML reports)

    --nowarnprofbadref
        disables warnings when a profile references an invalid object or
        parameter

        there are some circumstances under which it's useful to use an
        existing profile definition where some objects or parameters that it
        references have been (deliberately) deleted

        this is deprecated because it is no longer needed (use
        status="deleted" as appropriate to suppress such errors)

    --nowarnuniquekeys
        disables warnings when a multi-instance object has no unique keys

    --nowarnwtref
        disables "referenced file's spec indicates that it's still a WT"
        warnings

    --objpat=p
        specifies an object name pattern (a regular expression); objects
        that do not match this pattern will be ignored (the default of ""
        matches all objects)

    --option=n=v...
        can be specified multiple times; defines options that can be
        accessed and used when generating the report; useful when used with
        reports implemented in plugins

    --outfile=s
        specifies the output file; if not specified, output will be sent to
        *stdout*

        if the file already exists, it will be quietly overwritten

        the only reason to use this option (rather than using shell output
        redirection) is that it allows the tool to know the name of the
        output file and therefore to include it in the generated XML, HTML
        report etc

    --pedantic=[i(1)]
        enables output of warnings to *stderr* when logical inconsistencies
        in the XML are detected; if the option is specified without a value,
        the value defaults to 1

        this has the same effect as setting --loglevel to "w" (warning)
        followed by the pedantic value minus one, e.g. "w1" for --pedantic=2

    --plugin=s...
        can be specified multiple times; defines external plugins that can
        define additional report types

        *   currently each plugin must correspond to a file of the same name
            but with a .pm (Perl Module) extension; for example,
            --plugin=foo must correspond to a file called foo.pm; the
            directories specified via the Perl include path (including the
            current directory) and via --include are searched

        *   each plugin must define a package of the same name and can
            define one of more routines with names of the form rrr_node; rrr
            becomes an additional report type; if only one such routine is
            defined then by convention rrr should be the same as the plugin
            name; for example, foo.pm will always define the foo package and
            will usually define a foo_node routine

        *   the file can optionally also define routines with names of the
            form rrr_init, rrr_begin, rrr_postpar, rrr_post and rrr_end

        *   rrr_init is called after processing command line arguments but
            before reading any of the DM files; it can be used for
            initializing the plugin, e.g. parsing configuration files

        *   each of the other routines is called with three arguments; the
            first is the node on which it is to report; the second is the
            indentation level (0 means the initial call, for which the node
            is the root node, i.e. the parent of any model nodes); the third
            is a reference to an option hash

        *   the begin routine is called at the beginning; the node routine
            is called for each node; the postpar routine (if defined) is
            called after parameter node routines have been called; the post
            routine (if defined) is called after child node node routines
            have been called; the end routine is called at the end; these
            routines are not themselves responsible for traversing child
            nodes

        *   the node object is a reference to a hash that contains keys such
            as path and name; it is not currently documented

        *   it is safe to store information on the node; any new names
            should begin rrr_ in order to avoid name clashes

        *   these instructions are not expected to be sufficient to write a
            plugin; it will be necessary to consult the main report tool
            source code; the plugin interface may change in the future, in
            which case plugins may need to be adjusted

        *   the following illustrates just about the simplest possible valid
            plugin; it would be placed in a file called foo.pm and would be
            used by specifying --plugin=foo --report=foo

             package foo;
 
             sub foo_node
             {
                 my ($node) = @_;
                 print "$node->{path}\n";
             }
 
             1;

    --quiet
        suppresses informational messages

        this used to have the same effect as setting --loglevel to "e"
        (error) but now it simply suppresses such messages

    --report=html|htmlbbf|(null)|tab|text|xls|xml|xsd|other...
        specifies the report format; one of the following:

        html
            HTML document; see also --nolinks and --notemplates

        htmlbbf
            HTML document containing the information in the BBF CWMP index
            page; when generating this report, all the XSD and XML files are
            specified on the command line

            the htmlbbf report reads a configuration file whose name can be
            specified using --configfile

            see OD-290 and OD-148 for more details

        null
            no output; errors go to *stdout* rather than *stderr* (default)

        tab tab-separated list, one object or parameter per line

        text
            indented text

        xls Excel XML spreadsheet

        xml if --lastonly is specified, DM XML containing only the changes
            made by the final file on the command line; see also --autobase

            if --lastonly is not specified, DM XML with all imports resolved
            (apart from bibliographic references and data type definitions);
            use --dtprofile, optionally with --dtspec and --dtuuid, to
            generate DT XML for the specified profiles; use --canonical to
            omit transient information, e.g. dates and times, that makes it
            harder to compare reports; use --components (perhaps with
            --noobjects or --noparameters) to generate component definitions

        xml2
            same as the xml report with --lastonly not specified; deprecated
            (use xml instead)

        xsd W3C schema

        other...
            other report types can be supported via --plugin

    --showdiffs
        currently affects only the text and html reports; visually indicates
        the differences resulting from the last XML file on the command line

        for the html report, insertions are shown in blue and deletions are
        shown in red strikeout; in order to enhance readability, hyperlinks
        are not shown in a special color (but are still underlined); note
        that this hyperlink behavior uses color=inherit, which apparently
        isn't supported by Internet Explorer

        is implied by --compare

    --showreadonly
        shows read-only enumeration and pattern values as READONLY; this is
        enabled by default but can be disabled using --noshowreadonly

        this is deprecated because it is enabled by default and therefore
        has no effect

    --showspec
        currently affects only the html report; generates a Spec rather than
        a Version column

    --showsyntax
        adds an extra column containing a summary of the parameter syntax;
        is like the Type column for simple types, but includes additional
        details for lists

    --showunion
        adds "This object is a member of a union" text to objects that have
        "1 of n" or "union" semantics; such objects are identified by having
        minEntries=0 and maxEntries=1

    --sortobjects
        currently affects only the html report; reports objects (and
        profiles) in alphabetical order rather than in the order that they
        are defined in the XML

    --special=deprecated|imports|key|nonascii|normative|notify|obsoleted|pat
    href|profile|ref|rfc
        performs special checks, most of which assume that several versions
        of the same data model have been supplied on the command line, and
        many of which operate only on the highest version of the data model

        deprecated, obsoleted
            for each profile item (object or parameter) report if it is
            deprecated or obsoleted

        imports, imports:element, imports:element:name
            lists the components, data types and models that are defined in
            all the files that were read by the tool

            element is component, dataType or model and can be abbreviated,
            so it is usual to specify just the first letter

            name is the first part of the element name (it can be the full
            element name but this is not necessary); element names which
            start with an underscore will also be listed

            the output format is illustrated by these examples:

             report.pl --special=imports:m:Device:2 tr-181-2-3-0.xml
             model {tr-181-2-3-0}Device:2.3
             model {tr-181-2-3-0}Device:2.2 = {tr-181-2-2-0}Device:2.2
             model {tr-181-2-2-0}Device:2.2
             model {tr-181-2-2-0}Device:2.1 = {tr-181-2-1-0}Device:2.1
             model {tr-181-2-1-0}Device:2.1
             model {tr-181-2-1-0}Device:2.0 = {tr-181-2-0-1}Device:2.0
             model {tr-181-2-0-1}Device:2.0

             report.pl --special=imports:c:UPnP tr-181-2-3-0.xml
             component {tr-157-1-3-0}UPnP = {tr-157-1-2-0}UPnP
             component {tr-157-1-2-0}UPnPDiffs
             component {tr-157-1-2-0}UPnP
             component {tr-157-1-2-0}_UPnP = {tr-157-1-1-0}UPnP {tr-157-1-0-0}
             component {tr-157-1-1-0}UPnP = {tr-157-1-0-0}UPnP
             component {tr-157-1-0-0}UPnP
             component {tr-181-2-0-1}UPnP = {tr-157-1-2-0}UPnP
             component {tr-157-1-4-0}UPnP = {tr-157-1-3-0}UPnP {tr-157-1-2-0}

            each line starts with the element name, followed by the element
            in the form {file}name; then, if the element is imported from
            another file (possibly using a different name), that is
            indicated after an equals sign; finally if the actual definition
            is in a different file, that is indicated in the form {file}

            for example, the following line indicates that the tr-157-1-2-0
            _UPnP component is imported from the tr-157-1-1-0 UPnP
            component, which is actually defined in tr-157-1-0-0

             component {tr-157-1-2-0}_UPnP = {tr-157-1-1-0}UPnP {tr-157-1-0-0}

        key for each table with a functional key, report access, path and
            the key

        nonascii
            check which model, object, parameter or profile descriptions
            contain characters other than ASCII 9-10 or 32-126; the output
            is the full path names of all such items, together with the
            offending descriptions with the invalid characters surrounded by
            pairs of asterisks

            the above list is followed by a list of the invalid characters
            and how often each one occurred

        normative
            check which model, object, parameter or profile descriptions
            contain inappropriate use of normative language, i.e. lower-case
            normative words, or MAY NOT; the output is the full path names
            of all such items, together with the offending descriptions with
            the normative words surrounded by pairs of asterisks

            the above list is followed by a list of the invalid terms and
            how often each one occurred

        notify
            check which parameters in the highest version of the data model
            are not in the "can deny active notify request" table; the
            output is the full path names of all such parameters, one per
            line

        pathref
            for each pathRef parameter, report cases where a "CPE-managed,
            non-fixed" object references another "CPE-managed, non-fixed"
            object; these are candidate cases for objects that should have
            the same lifetime

        profile
            check which parameters defined in the highest version of the
            data model are not in profiles; the output is the full path
            names of all such parameters, one per line

        rfc check which model, object, parameter or profile descriptions
            mention RFCs without giving references; the output is the full
            path names of all such items, together with the offending
            descriptions with the normative words surrounded by pairs of
            asterisks

            this doesn't work very well and isn't particularly useful

        ref for each reference parameter, report access, reference type and
            path

    --thisonly
        outputs only definitions defined in the files on the command line,
        not those from imported files

    --tr106=s(TR-106)
        indicates the TR-106 version (i.e. the bibref name) to be referenced
        in any automatically generated description text

        the default value is the latest version of TR-106 that is referenced
        elsewhere in the data model (or TR-106 if it is not referenced
        elsewhere)

    --trpage=s(http://www.broadband-forum.org/technical/download/)
        indicates the location of the PDF versions of BBF standards; is
        concatenated with the filename (trailing slash is added if
        necessary)

    --ucprofile=s...
        affects only the xml report; can be specified multiple times;
        defines use case profiles whose requirements will be checked against
        the --dtprofile profiles

    --upnpdm
        transforms output (currently HTML only) so it looks like a UPnP DM
        (Device Management) data model definition

    --ugly
        disables some prettifications, e.g. inserting spaces to encourage
        line breaks

        this is deprecated because it has been replaced with the more
        specific --nohyphenate and --showsyntax

    --verbose[=i(1)]
        enables verbose output; the higher the level the more the output

        this has the same effect as setting --loglevel to "d" (debug)
        followed by the verbose value minus one, e.g. "d2" for --verbose=3

    --warnbibref[=i(1)]
        enables bibliographic reference warnings (these warnings are also
        output if --verbose is specified); the higher the level the more
        warnings

        setting it to -1 is the same as setting --nowarnbibref and
        suppresses various bibref-related errors that would normally be
        output

        previously known as --warndupbibref, which is now deprecated (and
        will be removed in a future release) because it covers more than
        just duplicate bibliographic references

    --writonly
        reports only on writable parameters (should, but does not, suppress
        reports of read-only objects that contain no writable parameters)

