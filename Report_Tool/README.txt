Usage:
    report.pl [--allbibrefs] [--autobase] [--autodatatype]
    [--bibrefdocfirst] [--canonical] [--catalog=c]... [--compare]
    [--components] [--debugpath=pattern("")] [--deletedeprecated]
    [--dtprofile=s]... [--dtspec[=s]] [--help] [--ignore=pattern("")]
    [--importsuffix=string("")] [--include=d]... [--info] [--lastonly]
    [--marktemplates] [--noautomodel] [--nocomments] [--nohyphenate]
    [--nolinks] [--nomodels] [--noobjects] [--noparameters] [--noprofiles]
    [--notemplates] [--nowarnredef] [--nowarnprofbadref]
    [--objpat=pattern("")] [--outfile=s] [--pedantic[=i(1)]] [--quiet]
    [--report=html|(null)|tab|text|xls|xml|xml2|xsd] [--showdiffs]
    [--showreadonly] [--showspec] [--showsyntax] [--special=<option>]
    [--thisonly] [--tr106=s(TR-106)] [--ugly] [--upnpdm] [--verbose[=i(1)]]
    [--warnbibref[=i(1)]] [--writonly] DM-instance...

    *   the most common options are --include, --pedantic and --report=html

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

    --autodatatype
        causes the {{datatype}} template to be automatically prefixed for
        parameters with named data types

        this is deprecated because it is enabled by default

    --bibrefdocfirst
        causes the {{bibref}} template to be expanded with the document
        first, i.e. [DOC] Section n rather than the default of Section
        n/[DOC]

    --canonical
        affects only the xml2 report; causes descriptions to be processed
        into a canonical form that eases comparison with the original
        Microsoft Word descriptions

    --catalog=s...
        can be specified multiple times; XML catalogs
        (http://en.wikipedia.org/wiki/XML_Catalog); the current directory
        and any directories specified via --include are searched when
        locating XML catalogs

        XML catalogs are used only when validating DM instances as described
        under --pedantic; it is not necessary to use XML catalogs in order
        to validate DM instances

    --compare
        compares the two files that were specified on the command line,
        showing the changes made by the second one

        note that this is identical to setting --autobase and --showdiffs;
        it also affects the behavior of --lastonly

    --components
        affects only the xml2 report; generates a component for each object;
        if --noobjects is also specified, the component omits the object
        definition and consists only of parameter definitions

    --debugpath=pattern("")
        outputs debug information for parameters and objects whose path
        names match the specified pattern

    --deletedeprecated
        mark all deprecated or obsoleted items as deleted

    --dtprofile=s...
        affects only the xml2 report; can be specified multiple times;
        defines names of profiles to be used to generate an example DT
        instance

    --dtspec=s
        affects only the xml2 report; has an affect only when --dtprofile is
        also present; specifies the value of the top-level spec attribute in
        the generated DT instance; if not specified, the spec defaults to
        urn:example-com:device-1-0-0

    --help
        requests output of usage information

    --ignore
        specifies a pattern; data models whose names begin with the pattern
        will be ignored

    --importsuffix=string("")
        specifies a suffix which, if specified, will be appended (preceded
        by a hyphen) to the name part of any imported files in b<xml>
        reports

    --include=d...
        can be specified multiple times; specifies directories to search for
        files specified on the command line or included from other files;
        the current directory is always searched first

        no search is performed for files that already include directory
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

    --marktemplates
        mark selected template expansions with &&&& followed by
        template-related information, a colon and a space

        for example, the reference template is marked by a string such as
        &&&&pathRef-strong:, &&&&pathRef-weak:, &&&&instanceRef-strong:,
        &&&&instanceRef-strong-list: or enumerationRef:

        and the list template is marked by a string such as
        &&&&list-unsisgnedInt: or &&&&list-IPAddress:

    --noautomodel
        disables the auto-generation, if no model element was encountered,
        of a Components model that references each component

    --nocomments
        disables generation of XML comments showing what changed etc
        (--verbose always switches it off)

    --nohyphenate
        prevents automatic insertion of soft hyphens

    --nolinks
        affects only the html report; disables generation of hyperlinks
        (which makes it easier to import HTML into Word documents)

    --nomodels
        specifies that model definitions should not be reported

    --noobjects
        affects only the xml2 report when --components is specified; omits
        objects from component definitions

    --noparameters
        affects only the xml2 report when --components is specified; omits
        parameters from component definitions

        NOT YET IMPLEMENTED

    --noprofiles
        specifies that profile definitions should not be reported

    --notemplates
        suppresses template expansion (currently affects only html reports

    --nowarnredef
        disables parameter and object redefinition warnings (these warnings
        are also output if --verbose is specified)

        there are some circumstances under which parameter or object
        redefinition is not worthy of comment

    --nowarnprofbadref
        disables warnings when a profile references an invalid object or
        parameter

        there are some circumstances under which it's useful to use an
        existing profile definition where some objects or parameters that it
        references have been (deliberately) deleted

        this is deprecated because it is no longer needed (use
        status="deleted" as appropriate to suppress such errors)

    --objpat=pattern
        specifies an object name pattern (a regular expression); objects
        that do not match this pattern will be ignored (the default of ""
        matches all objects)

    --outfile=s
        specifies the output file; if not specified, output will be sent to
        *stdout*

        if the file already exists, it will be quietly overwritten

        the only reason to use this option (rather than using shell output
        redirection) is that it allows the tool to know the name of the
        output file and therefore to include it in the report

    --pedantic=[i(1)]
        enables output of warnings to *stderr* when logical inconsistencies
        in the XML are detected; if the option is specified without a value,
        the value defaults to 1

        also enables XML schema validation of DM instances; XML schemas are
        located using the schemaLocation attribute:

        *   if it specifies an absolute path, no search is performed

        *   if it specifies a relative path, the directories specified via
            --include are searched

        *   URLs are treated specially: if no XML catalogs were supplied via
            --catalog, the directory part is ignored and the schema is
            located as for a relative path (above); if XML catalogs were
            supplied via --catalog, the catalogs govern how (and whether)
            the URLs are processed

    --quiet
        suppresses informational messages

    --report=html|(null)|tab|text|xls|xml|xml2|xsd
        specifies the report format; one of the following:

        html
            HTML document; see also --nolinks and --notemplates

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
            use --dtprofile, optionally with --dtspec, to generate DT XML
            for the specified profiles; use --canonical to generate
            canonical and more easily compared descriptions; use
            --components (perhaps with --noobjects or --noparameters) to
            generate component definitions

        xml2
            same as the xml report with --lastonly not specified; deprecated
            (use xml instead)

        xsd W3C schema

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
        shows read-only enumeration and pattern values as READONLY
        (experimental)

    --showspec
        currently affects only the html report; generates a Spec rather than
        a Version column

    --showsyntax
        adds an extra column containing a summary of the parameter syntax;
        is like the Type column for simple types, but includes additional
        details for lists

    --special=deprecated|key|nonascii|normative|notify|obsoleted|profile|ref
    |rfc
        performs special checks, most of which assume that several versions
        of the same data model have been supplied on the command line, and
        many of which operate only on the highest version of the data model

        deprecated, obsoleted
            for each profile item (object or parameter) report if it is
            deprecated or obsoleted

        key for each table with a functional key, report access, path and
            the key

        nonascii
            check which model, object, parameter or profile descriptions
            contain characters other than ASCII 9-10 or 32-126; the output
            is the full path names of all such items, together with the
            offending descriptions with the invalid characters surrounded by
            pairs of asterisks

        normative
            check which model, object, parameter or profile descriptions
            contain inappropriate use of normative language, i.e. lower-case
            normative words, or MAY NOT; the output is the full path names
            of all such items, together with the offending descriptions with
            the normative words surrounded by pairs of asterisks

        notify
            check which parameters in the highest version of the data model
            are not in the "can deny active notify request" table; the
            output is the full path names of all such parameters, one per
            line

        profile
            check which parameters defined in the highest version of the
            data model are not in profiles; the output is the full path
            names of all such parameters, one per line

        rfc check which model, object, parameter or profile descriptions
            mention RFCs without giving references; the output is the full
            path names of all such items, together with the offending
            descriptions with the normative words surrounded by pairs of
            asterisks

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

    --warnbibref[=i(1)]
        enables bibliographic reference warnings (these warnings are also
        output if --verbose is specified); the higher the level the more
        warnings

        previously known as --warndupbibref, which is now deprecated (and
        will be removed in a future release) because it covers more than
        just duplicate bibliographic references

    --writonly
        reports only on writable parameters (should, but does not, suppress
        reports of read-only objects that contain no writable parameters)

