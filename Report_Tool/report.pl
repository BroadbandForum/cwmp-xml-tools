#!/usr/bin/perl -w
#
# Example data model report script.  Parses, validates and reports on TR-069
# DM (data model definition) instance documents.
#
# See full documentation at the end of the file.

# XXX want better format that can be directly imported into excel (and of
#     course want better export from excel, but that's a separate issue)

# XXX need to process all top-level objects (report needs to be capable of
#     containing ALL information in the input file)

# XXX don't necessarily want to expand components; needs to be controllable;
#     e.g for excel might just want a "header" worksheet with global attributes
#     and imports, then a worksheet for each component, model and
#     profile (format wants to mirror XSD very closely, and to be easily
#     extensible, e.g. first rows can contain attributes)

# XXX need to change style so just puts everything in the node tree (don't want
#     to have to be aware of all attributes and elements, only ones that need
#     special treatment; probably want to start afresh; use proper Perl
#     objects)

# XXX need an "xml" output option that just expands all components and outputs
#     canonical cwmp-datamodel xml (c.f. C pre-processor); note: there is now
#     am "xml" output option but it does something different

# XXX should separate into "expand" and "report" tools (would require keeping
#     things like spec at a much more granular level)

# XXX should check that parameters and objects referenced by the notify and
#     profile tables actually exist (this is now done); also could have a go
#     at checking that object references in descriptions are valid (now that
#     we have {{param}} and {{object}} templates, this could be done)

# XXX 'auto' handling is a mess; wants doing consistently, e.g. auto objects
#     are ignored only for some report types

# XXX name/base/ref handling is incomplete; base/ref requires a copy to be made
#     (actually is sort of working now, but only where model name, excluding
#     version, is the same, not where a copy is needed)

# XXX "hidden" node logic is working well, but need a third value to mean
#     that definitions in command-line files are not hidden by subsequent
#     import (import logic should detect it's already been read?)

# XXX autobase is covering three different things; should be split so one of
#     the usages is the logic for the re-use of models (shouldn't really need
#     it if handle imported and command-line models properly), another is
#     hiding of imported definitions, and the third is what the name implies

# XXX the import of TR-106-Amendment-1.xml is dangerous, because it doesn't
#     import the model, which means that the model is ignored even if there is
#     then an explicit import

# XXX could re-badge autobase as diff, since it's very close to that...

# XXX some report formats are somewhat broken at the moment, with the move to
#     centralised report_node traversal

# XXX need to re-think the report_node concept (the price of simplicity is
#     (in some cases) additional complexity

# XXX have to parse dataType specifications, so can output them in XML
#     reports (an issue only for TR-106 currently); ditto component
#     definitions

# XXX need once and for all to decide what spec is used for; mostly file is
#     used since it's guaranteed to be unique

# XXX have added some DT hacks, but need better control, e.g. determine whether
#     a given file is DT from its namespace

# XXX should use LWP::mirror to support URLs and cache files locally; also
#     support search path (including base URLs); finding highest corrigendum
#     complicates this (would need to fetch files matching a pattern) unless
#     assume that the HTTP server handles this (which it should do)

# XXX $upnpdm is a hack; need a more clear distinction between path syntax
#     used internally and path syntax used for presentation

# XXX $components is a hack (need full xml2 report support in order to carry
#     over unique keys, references etc)

# XXX why does this happen?
# % report.pl tr-098-1-1-0.xml tr-098-1-2-0.xml
#InternetGatewayDevice.DownloadDiagnostics.: object not found (auto-creating)
#InternetGatewayDevice.DownloadDiagnostics.DownloadURL: parameter not found
#    (auto-creating)
#InternetGatewayDevice.DownloadDiagnostics.DownloadURL: untyped parameter
#InternetGatewayDevice.UploadDiagnostics.: object not found (auto-creating)
#InternetGatewayDevice.UploadDiagnostics.UploadURL: parameter not found
#    (auto-creating)
#InternetGatewayDevice.UploadDiagnostics.UploadURL: untyped parameter
#urn:broadband-forum-org:tr-069-1-0-0: 522
#urn:broadband-forum-org:tr-098-1-0-0: 215
#urn:broadband-forum-org:tr-098-1-1-0: 18
#urn:broadband-forum-org:tr-098-1-2-0: 421
#
# but
#
# % report.pl tr-098-1-2-0.xml 
# urn:broadband-forum-org:tr-069-1-0-0: 522
# urn:broadband-forum-org:tr-098-1-0-0: 215
# urn:broadband-forum-org:tr-098-1-1-0: 18
# urn:broadband-forum-org:tr-098-1-2-0: 417
# urn:broadband-forum-org:tr-143-1-0-1: 49

use strict;
no strict "refs";

use Algorithm::Diff;
use Clone qw{clone};
use Data::Dumper;
use File::Spec;
use Getopt::Long;
use Pod::Usage;
use Text::Balanced qw{extract_bracketed};
use URI::Escape;
use XML::LibXML;

# XXX these have to match the current version of the DT schema
my $dtver = qq{1-0};
my $dturn = qq{urn:broadband-forum-org:cwmp:devicetype-${dtver}};
my $dtloc = qq{cwmp-devicetype-${dtver}.xsd};

#print STDERR File::Spec->tmpdir() . "\n";

# XXX this prevents warnings about wide characters, but still not handling
#     them properly (see tr2dm.pl, which now does a better job)
binmode STDOUT, ":utf8";

# Command-line options
my $autobase = 0;
my $autodatatype = 0;
my $canonical = 0;
my $components = 0;
my $debugpath = '';
my $deletedeprecated = 0;
my $dtprofiles = [];
my $dtspec = 'urn:example-com:device-1-0-0';
my $help = 0;
my $nohyphenate = 0;
my $ignore = '';
my $importsuffix = '';
my $includes = [];
my $info;
my $lastonly = 0;
my $marktemplates;
my $noautomodel = 0;
my $nocomments = 0;
my $nolinks = 0;
my $nomodels = 0;
my $noobjects = 0;
my $noparameters = 0;
my $noprofiles = 0;
my $notemplates = 0;
my $nowarnredef = 0;
my $nowarnprofbadref;
my $objpat = '';
my $pedantic;
my $quiet = 0;
my $report = '';
my $showspec = 0;
my $showsyntax = 0;
my $special = '';
my $thisonly = 0;
my $ugly = 0;
my $upnpdm = 0;
my $verbose;
my $warnbibref = 0;
my $warndupbibref = 0;
my $writonly = 0;
GetOptions('autobase' => \$autobase,
           'autodatatype' => \$autodatatype,
           'canonical' => \$canonical,
           'components' => \$components,
           'debugpath:s' => \$debugpath,
           'deletedeprecated' => \$deletedeprecated,
           'dtprofile:s@' => \$dtprofiles,
           'dtspec:s' => \$dtspec,
	   'help' => \$help,
           'ignore:s' => \$ignore,
           'importsuffix:s' => \$importsuffix,
           'include:s@' => \$includes,
	   'info' => \$info,
           'lastonly' => \$lastonly,
	   'marktemplates' => \$marktemplates,
	   'noautomodel' => \$noautomodel,
	   'nocomments' => \$nocomments,
	   'nohyphenate' => \$nohyphenate,
	   'nolinks' => \$nolinks,
	   'nomodels' => \$nomodels,
	   'noobjects' => \$noobjects,
	   'noparameters' => \$noparameters,
	   'noprofiles' => \$noprofiles,
	   'notemplates' => \$notemplates,
           'nowarnredef' => \$nowarnredef,
           'nowarnprofbadref' => \$nowarnprofbadref,
	   'objpat:s' => \$objpat,
	   'pedantic:i' => \$pedantic,
	   'quiet' => \$quiet,
	   'report:s' => \$report,
           'showspec' => \$showspec,
           'showsyntax' => \$showsyntax,
           'special:s' => \$special,
	   'thisonly' => \$thisonly,
           'upnpdm' => \$upnpdm,
           'ugly' => \$ugly,
	   'verbose:i' => \$verbose,
           'warnbibref:i' => \$warnbibref,
           'warndupbibref' => \$warndupbibref,
	   'writonly' => \$writonly) or pod2usage(2);
pod2usage(2) if $report && $special;
pod2usage(1) if $help;

$report = 'special' if $special;
$report = 'null' unless $report;

unless (defined &{"${report}_node"}) {
    print STDERR "unsupported report format: $report\n";
    pod2usage(2);
}

if ($noparameters) {
    print STDERR "--noparameters not yet implemented\n";
    pod2usage(2);
}

if ($info) {
    print STDERR q{$Author: wlupton $
$Date: 2010/01/20 $
$Id: //depot/users/wlupton/cwmp-datamodel/report.pl#150 $
};
    exit(1);
}

# XXX as part of getting rid of xml2, require the xml report also to specify
#     --lastonly (need to check this doesn't break the xml report)
if ($report eq 'xml2') {
    print STDERR "the xml2 report is deprecated; use the xml report without ".
        "--lastonly to get the same effect\n";
}
if ($report eq 'xml' && !$lastonly) {
    $report = 'xml2';
}

if ($ugly) {
    print STDERR "--ugly is deprecated; use --nohyphenate and/or ".
        "--showsyntax\n";
    $nohyphenate = 1;
    $showsyntax = 1;
}

if ($warndupbibref) {
    print STDERR "--warndupbibref is deprecated; use --warnbibref\n";
    $warnbibref = 1;
}

if ($nowarnprofbadref) {
    print STDERR "--nowarnprofbadref is deprecated; it's no longer necessary\n";
}

*STDERR = *STDOUT if $report eq 'null';

$marktemplates = '&&&&' if defined($marktemplates);

$warnbibref = 1 if defined($warnbibref) and !$warnbibref;
$warnbibref = 0 unless defined($warnbibref);

$pedantic = 1 if defined($pedantic) and !$pedantic;
$pedantic = 0 unless defined($pedantic);

$verbose = 1 if defined($verbose) and !$verbose;
$verbose = 0 unless defined($verbose);

$nocomments = 0 if $verbose;

# XXX upnpdm profiles are broken...
$noprofiles = 1 if $components || $upnpdm || @$dtprofiles;

# Globals.
my $allfiles = [];
my $specs = [];
# XXX for DT, lfile and lspec should be last processed DM file
#     (current workaround is to use same spec for DT and this DM)
my $lfile = ''; # last command-line-specified file
my $lspec = ''; # spec from last command-line-specified file
my $files = {};
my $imports = {}; # XXX not a good name, because it includes main file defns
my $imports_i = 0;
my $bibrefs = {};
my $objects = {};
my $parameters = {};
my $profiles = {};
my $root = {spec => '', path => '', name => '', type => '',
            status => 'current', dynamic => 0};
my $highestMajor = 0;
my $highestMinor = 0;
my $previouspath = '';

# Parse and expand a data model definition file.
# XXX also does minimal expansion of schema files
sub expand_toplevel
{
    my ($file)= @_;

    (my $dir, $file) = find_file($file);

    # parse file
    my $toplevel = parse_file($dir, $file);

    # for XSD files, just track the target namespace then return
    my $spec;
    if ($file =~ /\.xsd$/) {
        my $targetNamespace = $toplevel->findvalue('@targetNamespace');
        push @$allfiles, {name => $file, spec => $targetNamespace,
                          schema => 1};
        return;
    }
    else {
        $spec = $toplevel->findvalue('@spec');
        my @models = $toplevel->findnodes('model');
        push @$allfiles, {name => $file, spec => $spec, models => \@models};
    }

    # XXX this is using file name to check against multiple inclusion, but
    #     would spec be better? maybe, but would require 1-1 correspondence
    #     between spec and file, and would force spec to be used properly
    #     (using file is probably better)
    # XXX might not be quite the right test (will expand_toplevel and
    #     expand_import both have done all that the other needs?)
    $file =~ s/\.xml//;
    return if $files->{$file};
    $files->{$file} = 1;

    $lfile = $file;
    $lspec = $spec;

    $root->{spec} = $spec;
    push @$specs, $spec unless grep {$_ eq $spec} @$specs;

    # pick up description
    # XXX hmm... putting this stuff on root isn't right is it?
    $root->{description} = $toplevel->findvalue('description');
    $root->{descact} = $toplevel->findvalue('description/@action');

    # collect top-level item declarations (treat as though they were imported
    # from an external file; this avoids special cases)
    # XXX need to keep track of context in which the import was performed,
    #     so can reproduce import statements when generating XML
    foreach my $item ($toplevel->findnodes('dataType|component|model')) {
        my $element = $item->findvalue('local-name()');
        my $name = $item->findvalue('@name');

        if ($element eq 'model' && $ignore && $name =~ /^$ignore/) {
            print STDERR "ignored model $name\n" if $verbose;
            next;
        }

        update_imports($file, $spec, $file, $spec, $element, $name, $name,
                       $item);
    }

    # expand nested items (context is a stack of nested component context)
    # XXX should be: description, import, dataType, bibliography, component,
    #     model
    my $context = [{file => $file, spec => $spec, path => '', name => ''}];
    foreach my $item
	($toplevel->findnodes('import|dataType|bibliography|model')) {
	my $element = $item->findvalue('local-name()');
        my $name = $item->findvalue('@name');

        if ($element eq 'model' && $ignore && $name =~ /^$ignore/) {
            print STDERR "ignored model $name\n" if $verbose;
            next;
        }

	"expand_$element"->($context, $root, $item);
    }

    # if saw components but no model, auto-generate a model that references
    # each component once at the top level
    # XXX this duplicates some logic from expand_model_component
    # XXX model name is spec, and so will probably be invalid
    my @comps =
        grep {$_->{element} eq 'component'} @{$imports->{$file}->{imports}};
    my @models =
        grep {$_->{element} eq 'model'} @{$imports->{$file}->{imports}};
    if (!$noautomodel && !@models && @comps) {
        my $mname = $spec;
        print STDERR "auto-generating model: $mname\n" if $verbose;
        my $nnode = add_model($context, $root, $mname);
        foreach my $comp (@comps) {
            my $name = $comp->{name};
            my $component = $comp->{item};

            print STDERR "referencing component: $name\n" if $verbose;
            foreach my $item ($component->findnodes('component|object|'.
                                                    'parameter')) {
                my $element = $item->findvalue('local-name()');
                "expand_model_$element"->($context, $nnode, $nnode, $item);
            }
        }
    }
}

# Expand a top-level import.
# XXX there must be scope for more code share with expand_toplevel
# XXX yes, in both cases should import all top-level items (dataType,
#     component, model) into the "main" namespace, unless there is a
#     conflict; explicitly imported symbols can be renamed locally
# XXX importing something should add it to the current namespace and allow
#     it to be imported from elsewhere, e.g. import Time in 143 (even though
#     it doesn't use it) should allow Time to be imported from 143
sub expand_import
{
    my ($context, $pnode, $import) = @_;

    my $cfile = $context->[0]->{file};
    my $cspec = $context->[0]->{spec};

    my $file = $import->findvalue('@file');
    my $spec = $import->findvalue('@spec');

    (my $dir, $file) = find_file($file);

    print STDERR "expand_import file=$file spec=$spec\n" if $verbose > 1;

    my $tfile = $file;
    $file =~ s/\.xml//;

    # if already read file, add the imports to the current namespace
    if ($files->{$file}) {
        foreach my $item ($import->findnodes('dataType|component|model')) {
            my $element = $item->findvalue('local-name()');
            my $name = $item->findvalue('@name');
            my $ref = $item->findvalue('@ref');
            $ref = $name unless $ref;

            my ($import) = grep {$_->{element} eq $element && $_->{name} eq
                                  $ref} @{$imports->{$file}->{imports}};
            update_imports($cfile, $cspec, $file, $imports->{$file}->{spec},
                           $element, $name, $ref, $import->{item});
        }
        return;
    }
    $files->{$file} = 1;

    return if $thisonly;

    # parse imported file
    my $toplevel = parse_file($dir, $tfile);
    my $fspec = $toplevel->findvalue('@spec');
    push @$specs, $fspec unless grep {$_ eq $fspec} @$specs;

    # check spec (if supplied)
    $spec = $fspec unless $spec;
    print STDERR "import $file: spec is $fspec (expected $spec)\n"
        unless specs_match($spec, $fspec);

    # collect top-level item declarations
    foreach my $item ($toplevel->findnodes('dataType|component|model')) {
        my $element = $item->findvalue('local-name()');
        my $name = $item->findvalue('@name');
        my $ref = $item->findvalue('@base');
        # DO NOT default ref to name here; empty ref indicates an initial
        # definition of something!
        
        update_imports($file, $fspec, $file, $fspec, $element, $name, $ref,
                       $item);
    }

    unshift @$context, {file => $file, spec => $fspec, path => '', name => ''};

    # expand imports in the imported file
    foreach my $item ($toplevel->findnodes('import')) {
	expand_import($context, $root, $item);
    }

    # expand data types in the imported file
    # XXX this is experimental (it's so reports can include data types)
    foreach my $item ($toplevel->findnodes('dataType')) {
	expand_dataType($context, $root, $item);
    }

    # expand bibliogaphy in the imported file
    my ($bibliography) = $toplevel->findnodes('bibliography');
    expand_bibliography($context, $root, $bibliography) if $bibliography;

    # find imported items in the imported file
    foreach my $item ($import->findnodes('dataType|component|model')) {
        my $element = $item->findvalue('local-name()');
	my $name = $item->findvalue('@name');
	my $ref = $item->findvalue('@ref');
        $ref = $name unless $ref;

        if ($element eq 'model' && $ignore && $name =~ /^$ignore/) {
            print STDERR "ignored model $name\n" if $verbose;
            next;
        }

        # XXX this logic is from expand_model_component
        my ($elem) = grep {$_->{element} eq $element && $_->{name} eq $ref}
        @{$imports->{$file}->{imports}};
        if (!$elem) {
            print STDERR "{$file}$ref: $element not found\n";
            next;
        }
        my $dfile = $elem->{file};

        # find the actual element (first check whether we have already seen it)
        my ($delem) = grep {$_->{element} eq $element && $_->{name} eq $ref}
        @{$imports->{$dfile}->{imports}};
        my $fitem = $delem ? $delem->{item} : undef;
        if ($fitem) {
            print STDERR "{$file}$ref: $element already found in $dfile\n"
                if $verbose;
        } elsif ($dfile eq $file) {
            ($fitem) = $toplevel->findnodes(qq{$element\[\@name="$ref"\]});
        } else {
            (my $ddir, $dfile) = find_file($dfile.'.xml');
            my $dtoplevel = parse_file($ddir, $dfile);
            ($fitem) = $dtoplevel->findnodes(qq{$element\[\@name="$ref"\]});
        }
        print STDERR "{$file}$ref: $element not found in $dfile\n"
            unless $fitem;

        # XXX update regardless; will get another error if try to use it
        update_imports($cfile, $cspec, $file, $fspec, $element, $name, $ref,
                       $fitem);
    }
    shift @$context;
}

# Update the global list of imported items.
sub update_imports
{
    my ($file, $spec, $dfile, $dspec, $element, $name, $ref, $item) = @_;

    $imports->{$file}->{i} = $imports_i++ unless exists $imports->{$file};
    $imports->{$file}->{spec} = $spec;
    push(@{$imports->{$file}->{imports}},
         {file => $dfile, spec => $dspec, element => $element, name => $name,
          ref => $ref, item => $item});

    my $alias = $dfile ne $file ? qq{ = {$dfile}$ref} : qq{};
    print STDERR "update_imports: added $element {$file}$name$alias\n"
        if $verbose;
}

# Expand a dataType definition.
# XXX does the minimum to support TR-106; both it and syntax should use the
#     schema structures to avoid duplication.
sub expand_dataType
{    
    my ($context, $pnode, $dataType) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};

    my $name = $dataType->findvalue('@name');
    my $base = $dataType->findvalue('@base');
    my $status = $dataType->findvalue('@status');
    my $description = $dataType->findvalue('description');
    my $descact = $dataType->findvalue('description/@action');
    my $minLength = $dataType->findvalue('string/size/@minLength');
    my $maxLength = $dataType->findvalue('string/size/@maxLength');
    my $patterns = $dataType->findnodes('string/pattern');

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $spec);

    print STDERR "expand_dataType name=$name base=$base\n" if $verbose > 1;

    my $node = {name => $name, base => $base, spec => $spec,
                status => $status, description => $description,
                descact => $descact, minLength => $minLength,
                maxLength => $maxLength, patterns => []};

    foreach my $pattern (@$patterns) {
        my $value = $pattern->findvalue('@value');
        my $description = $pattern->findvalue('description');
        my $descact = $pattern->findvalue('description/@action');

        update_bibrefs($description, $spec);

        push @{$node->{patterns}}, {value => $value, description =>
                                        $description, descact => $descact};
    }

    push @{$pnode->{dataTypes}}, $node;
}

# Expand a bibliography definition.
sub expand_bibliography
{
    my ($context, $pnode, $bibliography) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};

    # will report if $verbose > $vlevel
    my $vlevel = 1;

    my $description = $bibliography->findvalue('description');
    my $descact = $bibliography->findvalue('description/@action');

    update_bibrefs($description, $spec);

    print STDERR "expand_bibliography\n" if $verbose > $vlevel;

    if ($pnode->{bibliography}) {
        # XXX not obvious what should be done with the description here; for
        #     now, just replace it quietly.
        $pnode->{bibliography}->{description} = $description;
        $pnode->{bibliography}->{descact} = $descact;
    } else {
        $pnode->{bibliography} = {description => $description,
                                  descact => $descact, references => []};
    }

    # XXX this should really be in a separate routine
    foreach my $reference ($bibliography->findnodes('reference')) {
        my $id = $reference->findvalue('@id');
        my $name = $reference->findvalue('name');

        my ($dupref) =
            grep {$_->{id} eq $id} @{$pnode->{bibliography}->{references}};
        if ($dupref) {
            if ($dupref->{spec} eq $spec) {
                # this isn't necessarily a problem; it can happen if two files
                # with the same spec are processed
                print STDERR "$id: duplicate bibref: {$file}$name\n"
                    if $verbose || $warnbibref;
            } elsif ($dupref->{name} ne $name) {
                print STDERR "$id: ambiguous bibref: ".
                    "{$dupref->{file}}$dupref->{name}, {$file}$name\n";
            } else {
                print STDERR "$id: duplicate bibref: ".
                    "{$dupref->{file}}$dupref->{name}, {$file}$name\n"
                    if $verbose || $warnbibref;
            }
        }

        print STDERR "expand_bibliography_reference id=$id name=$name\n" if
            $verbose > $vlevel;

        my $hash = {id => $id, name => $name, file => $file};
        foreach my $element (qw{title organization category date hyperlink}) {
            my $value = $reference->findvalue($element);
            $hash->{$element} = $value ? $value : '';
        }

        # XXX check for non-standard organization / category
        my $bbf = 'Broadband Forum';
        my $tr = 'Technical Report';
        if ($hash->{organization} =~ /BBF|The\s+Broadband\s+Forum/i) {
            print STDERR "$id: $file: replaced organization ".
                "\"$hash->{organization}\" with \"$bbf\"\n"
                if $warnbibref > 1 || $verbose;
            $hash->{organization} = $bbf;
        }
        if ($hash->{category} =~ /TR/i) {
            print STDERR "$id: $file: replaced category ".
                "\"$hash->{category}\" with \"$tr\"\n"
                if $warnbibref > 1 || $verbose;
            $hash->{category} = $tr;
        }

        # XXX check for missing category
        if ($hash->{organization} eq $bbf && !$hash->{category}) {
             print STDERR "$id: $file: missing $bbf category (\"$tr\" ".
                 "assumed)\n" if $warnbibref > 1 || $verbose;
            $hash->{category} = $tr;
        }
        if ($hash->{organization} eq 'IETF' && !$hash->{category}) {
             print STDERR "$id: $file: missing IETF category (\"RFC\" ".
                 "assumed)\n" if $warnbibref > 1 || $verbose;
            $hash->{category} = 'RFC';
        }

        # XXX could also check for missing date (etc)...

        # for TRs, don't want hyperlink, so can auto-generate the correct
        # hyperlink according to BBF conventions
        if ($hash->{organization} eq $bbf && $hash->{category} eq $tr) {
            if ($hash->{hyperlink}) {
                print STDERR "$id: $file: replaced deprecated $bbf $tr ".
                    "hyperlink\n" if $warnbibref > 1 || $verbose;
            }
            my $h = qq{http://www.broadband-forum.org/technical/download/};
            my $trname = $id;
            $trname =~ s/i(\d+)/_Issue-$1/;
            $trname =~ s/a(\d+)/_Amendment-$1/;
            $trname =~ s/c(\d+)/_Corrigendum-$1/;
            $h .= $trname;
            $h .= qq{.pdf};
            $hash->{hyperlink} = $h;
        }

        # for RFCs, don't want hyperlink, so can auto-generate the correct
        # hyperlink according to IETF conventions
        if ($hash->{organization} eq 'IETF' && $hash->{category} eq 'RFC') {
            if ($hash->{hyperlink}) {
                print STDERR "$id: $file: replaced deprecated IETF RFC ".
                    "hyperlink\n" if $warnbibref > 1 || $verbose;
            }
            my $h = qq{http://tools.ietf.org/html/};
            $h .= lc $id;
            $hash->{hyperlink} = $h;
        }

        # XXX could also replace the hyperlinks for other organisations?

        if ($dupref) {
            my $changed = 0;
            foreach my $key (keys %$hash) {
                # XXX note, only replace if new value is non-blank
                if ($hash->{$key} && $hash->{$key} ne $dupref->{$key}) {
                    print STDERR "$id: $key: $dupref->{$key} -> ".
                        "$hash->{$key}\n" if $verbose;
                    $dupref->{$key} = $hash->{$key};
                    $changed = 1;
                }
            }
            $dupref->{spec} = $spec if $changed;
        } else {
            $hash->{spec} = $spec;
            push @{$pnode->{bibliography}->{references}}, $hash;
        }
    }
    print STDERR Dumper($pnode->{bibliography}) if $verbose > $vlevel;
}

# Expand a data model definition.
sub expand_model
{
    my ($context, $pnode, $model) = @_;

    my $spec = $context->[0]->{spec};

    my $name = $model->findvalue('@name');
    my $ref = $model->findvalue('@ref');
    $ref = $model->findvalue('@base') unless $ref;
    my $status = $model->findvalue('@status');
    my $isService = boolean($model->findvalue('@isService'));
    my $description = $model->findvalue('description');
    my $descact = $model->findvalue('description/@action');

    # XXX fudge it if in a DT instance (ref but no name or base)
    $name = $ref if $ref && !$name;

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $spec);

    print STDERR "expand_model name=$name ref=$ref\n" if $verbose > 1;

    # if automatically generating references to existing models, set ref
    if ($autobase  && !$ref) {
        my @match = grep {
            my ($a) = ($name =~ /([^:]*)/);
            my ($b) = ($_->{name} =~ /([^:]*)/);
            $_->{type} eq 'model' && $a eq $b;
        } @{$pnode->{nodes}};
        if (@match) {
            # XXX logic duplicated immediately below (use routine for this)
            my $hmaj = 0;
            my $hmin = 0;
            for my $model (@match) {
                my $name = $model->{name};
                my ($maj, $min) = ($name =~ /:(\d+)\.(\d+)/);
                if (($maj > $hmaj) || ($maj == $hmaj && $min > $hmin)) {
                    $hmaj = $maj;
                    $hmin = $min;
                    $ref = $name;
                }
            }
            # XXX hack for modifying existing models
            $ref = '_' . $ref if $ref eq $name;
            print STDERR "converted to name=$name ref=$ref\n" if $verbose;
        }
    }

    # XXX for now, still handle versions as before
    my ($majorVersion, $minorVersion) = ($name =~ /:(\d+)\.(\d+)/);
    if (($majorVersion > $highestMajor) ||
        ($majorVersion == $highestMajor && $minorVersion > $highestMinor)) {
        $highestMajor = $majorVersion;
        $highestMinor = $minorVersion;
    }

    my $nnode = add_model($context, $pnode, $name, $ref, $isService, $status,
                          $description, $descact, $majorVersion,
                          $minorVersion);

    # expand nested components, objects, parameters and profiles
    foreach my $item ($model->findnodes('component|parameter|object|'.
                                        'profile')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_$element"->($context, $nnode, $nnode, $item);
    }
}

# Expand a data model component reference.
sub expand_model_component
{
    my ($context, $mnode, $pnode, $component) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};
    my $Path = $context->[0]->{path};

    my $path = $component->findvalue('@path');
    my $name = $component->findvalue('@ref');

    $Path .= $path;

    # XXX a kludge... will apply to the first items only (really want a way
    #     of passing arguments)
    my $hash = dmr_previous($component, 1);
    $hash->{previousObject} = $path . $hash->{previousObject} if
        $hash->{previousObject};

    print STDERR "expand_model_component path=$path ref=$name\n"
        if $verbose > 1;

    # find component
    my ($comp) = grep {$_->{element} eq 'component' && $_->{name} eq $name}
    @{$imports->{$file}->{imports}};

    # check component is known
    if (!$comp) {
	print STDERR "{$file}$name: component not found\n"
            unless $thisonly;
	return;
    }
    $component = $comp->{item};
    if (!$component) {
	print STDERR "{$file}$name: component not found in $comp->{file}\n"
            unless $thisonly;
	return;
    }

    # from now on, file and spec relate to the component
    # XXX this is ugly (want clean namespace handling)
    $file = $comp->{file};
    $spec = $comp->{spec};

    # check for recursive invocation
    if (grep {$_->{file} eq $file && $_->{name} eq $name} @$context) {
        my $active =
            join ', ', map {qq{{$_->{file}}$_->{name}}} reverse @$context;
        print STDERR "$name: recursive component reference: $active\n";
        return;
    }

    # the path may consist of multiple components; create any intervening
    # objects, returning the new parent and the last component of the name
    # XXX may want control over auto-creation logic; sometimes it's useful, but
    #     it can be error-prone too (one reason to auto-create is to force a
    #     parameter to be the first in an object, so could provide an alter-
    #     native mechanism for this?)
    # XXX this is a problem for profiles, because it creates the profile nodes
    #     as children of the result of add_path; this has been avoided by a
    #     hack in expand_model_profile; an alternative would be to look at the
    #     component contents before expanding it?
    ($pnode, $path) = add_path($context, $mnode, $pnode, $path, 0);

    # pass information from caller to the new component context
    unshift @$context, {file => $file, spec => $spec, path => $Path,
                        name => $name,
                        previousParameter => $hash->{previousParameter},
                        previousObject => $hash->{previousObject},
                        previousProfile => $hash->{previousProfile}};

    # expand component's nested components, parameters, objects and profiles
    foreach my $item ($component->findnodes('component|parameter|object|'.
                                            'profile')) {
	my $element = $item->findvalue('local-name()');
        "expand_model_$element"->($context, $mnode, $pnode, $item);
    }

    # pop context from the beginning of the active component list
    shift @$context;
}

# Expand a data model object
sub expand_model_object
{
    my ($context, $mnode, $pnode, $object) = @_;

    my $spec = $context->[0]->{spec};

    my $name = $object->findvalue('@name');
    my $ref = $object->findvalue('@ref');
    $ref = $object->findvalue('@base') unless $ref;
    my $access = $object->findvalue('@access');
    my $minEntries = $object->findvalue('@minEntries');
    my $maxEntries = $object->findvalue('@maxEntries');
    my $numEntriesParameter = $object->findvalue('@numEntriesParameter');
    my $enableParameter = $object->findvalue('@enableParameter');
    my $status = $object->findvalue('@status');
    my $description = $object->findvalue('description');
    my $descact = $object->findvalue('description/@action');

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $spec);

    $minEntries = 1 unless defined $minEntries && $minEntries ne '';
    $maxEntries = 1 unless defined $maxEntries && $maxEntries ne '';

    # XXX majorVersion and minorVersion are no longer in the schema
    #my $majorVersion = $object->findvalue('@majorVersion');
    #my $minorVersion = $object->findvalue('@minorVersion');
    my ($majorVersion, $minorVersion) = dmr_version($object);

    my $fixedObject = dmr_fixedObject($object);
    my $noUniqueKeys = dmr_noUniqueKeys($object);

    # XXX this is incomplete name / ref handling
    # XXX WFL2 my $tname = $name ? $name : $ref;
    my $oname = $name;
    my $oref = $ref;
    my $tname = $ref ? $ref : $name;
    my $path = $pnode->{path}.$tname;

    print STDERR "expand_model_object name=$name ref=$ref\n" if $verbose > 1;

    # ignore if doesn't match object name pattern
    if ($objpat ne '' && $path !~ /$objpat/) {
	print STDERR "\tdoesn't match object name pattern\n" if $verbose > 1;
	return;
    }

    # the name may consist of multiple components; create any intervening
    # objects, returning the new parent and the last component of the name
    ($pnode, $name) = add_path($context, $mnode, $pnode, $tname, 1);
    # XXX this is more of the incomplete name / ref handling
    if ($ref) {
        $ref = $name;
        # XXX WFL2 $name = '';
        # XXX this will fail if $oname has multiple components (which it
        #     shouldn't have)
        $name = ($oname && $oref) ? $oname : '';
    }

    # if this is a variable-size table, check that there is a
    # numEntriesParameter attribute and that the referenced parameter exists
    # XXX numEntriesParameter is checked only when object is defined; this
    #     means that no check is made when processing DT instances
    # XXX no longer the case... can we get rid of the check here?
    # XXX I think so
    #if ($name && ($maxEntries eq 'unbounded' || 
    #              ($maxEntries > 1 && $maxEntries > $minEntries))) {
    #	if (!$numEntriesParameter) {
    #         print STDERR "$path: missing numEntriesParameter\n" if $pedantic;
    #   } else {
    #	    unless (grep {$_->{name} =~ /$numEntriesParameter/}
    #		    @{$pnode->{nodes}}) {
    #           if ($pedantic > 2) {
    #               print STDERR "$path: missing NumberOfEntries parameter " .
    #                   "($numEntriesParameter)\n";
    #               print STDERR "\t" .
    #                   join(", ", map {$_->{name}} @{$pnode->{nodes}}) . "\n";
    #           }
    #       }
    #	}
    #}

    # determine name of previous sibling (if any) as a hint for where to
    # create the new node
    # XXX can i assume that there's ALWAYS a text node between each
    #     object node?
    my $previous = dmr_previous($object);
    my $prevnode = $object->previousSibling()->previousSibling();
    if (!defined $previous &&
        $prevnode && $prevnode->findvalue('local-name()') eq 'object') {
        $previous = $prevnode->findvalue('@name');
        $previous = $prevnode->findvalue('@ref') unless $previous;
        $previous = $prevnode->findvalue('@base') unless $previous;
        # previous node could be at a lower level than this node, e.g.
        # it might be A.B.C but we are A.D, so adjust to be the previous
        # node at this level
        $previous = adjust_level($previous,
                                 $pnode->{path} . ($ref ? $ref : $name));
        $previous = undef if $previous eq '';
    }
    # XXX this isn't working in a component (need to prefix component path)
    #print STDERR "$previous\n" if $previous;

    # create the new object
    my $nnode = add_object($context, $mnode, $pnode, $name, $ref, 0, $access,
			   $status, $description, $descact, $majorVersion,
			   $minorVersion, $previous);

    # XXX add some other stuff (really should be handled by add_object)
    # XXX should detect attempt to change (need to use routine for this)
    check_and_update($path, $nnode, 'minEntries', $minEntries);
    check_and_update($path, $nnode, 'maxEntries', $maxEntries);
    check_and_update($path, $nnode,
                     'numEntriesParameter', $numEntriesParameter);
    check_and_update($path, $nnode, 'enableParameter', $enableParameter);

    # XXX these are slightly different (just take first definition seen)
    $nnode->{noUniqueKeys} = $noUniqueKeys unless
        $nnode->{noUniqueKeys};
    $nnode->{fixedObject} = $fixedObject unless
        $nnode->{fixedObject};

    # note previous uniqueKeys
    my $uniqueKeys = $nnode->{uniqueKeys};
    $nnode->{uniqueKeys} = [];

    # expand nested components, parameters and objects
    foreach my $item ($object->findnodes('component|uniqueKey|parameter|'.
                                         'object')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_$element"->($context, $mnode, $nnode, $item);
    }

    # XXX for unique keys take the latest
    if ($uniqueKeys && @$uniqueKeys) {
        if (!@{$nnode->{uniqueKeys}}) {
            $nnode->{uniqueKeys} = $uniqueKeys;
        } else {
            printf STDERR "$path: uniqueKeys changed (new ones used)\n"
                if $verbose;
        }
    }
}

# XXX experimental (should add the full "changed" logic)
sub check_and_update
{
    my ($path, $node, $item, $value) = @_;

    if (defined $node->{$item}) {
        # XXX message is only if new value is non-empty (not the best; should
        #     warn if pedantic > 1 because this means that something has been
        #     specified and then is changed later)
        print STDERR "$path: $item: $node->{$item} -> $value\n"
            if $value ne '' && $value ne $node->{$item} && $verbose;
    }
    $node->{$item} = $value if $value ne '';
}

# Get "fixed object" from @dmr:fixedObject, if present
# XXX there's scope for a more general utility here!
sub dmr_fixedObject
{
    my ($element) = @_;

    my $fixedObject = '';

    my $dmr = $element->lookupNamespaceURI('dmr');
    $fixedObject = $element->findvalue('@dmr:fixedObject') if $dmr;

    return $fixedObject;
}

# Get "no unique keys" from @dmr:noUniqueKeys, if present
sub dmr_noUniqueKeys
{
    my ($element) = @_;

    my $noUniqueKeys = '';

    my $dmr = $element->lookupNamespaceURI('dmr');
    $noUniqueKeys = $element->findvalue('@dmr:noUniqueKeys') if $dmr;

    return $noUniqueKeys;
}

# Get major and minor version from @dmr:version, if present
sub dmr_version
{
    my ($element) = @_;

    my $version = '';

    my $dmr = $element->lookupNamespaceURI('dmr');
    $version = $element->findvalue('@dmr:version') if $dmr;

    return $version =~ /(\d+)\.(\d+)/;
}

# Get previous items from dmr:previous*, if present
sub dmr_previous
{
    my ($element, $wanthash) = @_;

    my $dmr = $element->lookupNamespaceURI('dmr');
    my @previous;
    @previous = $element->findnodes('@dmr:previousParameter|'.
                                    '@dmr:previousObject|'.
                                    '@dmr:previousProfile') if $dmr;
    
    return @previous ? $previous[0]->findvalue('.') : undef unless $wanthash;

    my $hash = {};
    foreach my $attr (@previous) {
        my $name = $attr->findvalue('local-name()');
        $attr = $attr ? $attr->findvalue('.') : undef;
        $hash->{$name} = $attr;
    }
    return $hash;
}

# Adjust and return first node name to be at the same level as the second
sub adjust_level
{
    my ($first, $second) = @_;

    $first =~ s/\.\{/\{/g;
    $second =~ s/\.\{/\{/g;

    my @fcomps = split /\./, $first;
    my @scomps = split /\./, $second;

    $first =~ s/\{/\.\{/g;

    return $first if $#scomps >= $#fcomps;

    my $temp = (join '.', @fcomps[0..$#scomps]) . '.';
    $temp =~ s/\{/\.\{/g;

    return $temp;
}

# Expand a data model object unique key
# XXX this is more like mib2dm.pl; need to handle attempts to change unique
#     keys when modifying data models
sub expand_model_uniqueKey
{
    my ($context, $mnode, $pnode, $uniqueKey) = @_;

    # expand nested parameter references
    my $parameters = [];
    foreach my $parameter ($uniqueKey->findnodes('parameter')) {
        my $ref = $parameter->findvalue('@ref');
        push @$parameters, $ref;
    }
    # XXX would prefer the caller to do this
    push @{$pnode->{uniqueKeys}}, $parameters;
}

# Expand a data model parameter.
sub expand_model_parameter
{
    my ($context, $mnode, $pnode, $parameter) = @_;

    my $spec = $context->[0]->{spec};

    my $name = $parameter->findvalue('@name');
    my $ref = $parameter->findvalue('@ref');
    $ref = $parameter->findvalue('@base') unless $ref;
    my $access = $parameter->findvalue('@access');
    my $status = $parameter->findvalue('@status');
    my $activeNotify = $parameter->findvalue('@activeNotify');
    my $forcedInform = $parameter->findvalue('@forcedInform');
    # XXX lots of hackery here...
    my @types = $parameter->findnodes('syntax/*');
    my $type = !@types ? undef : $types[0]->findvalue('local-name()') eq 'list' ? $types[1] : $types[0];
    my $values = $parameter->findnodes('syntax/enumeration/value');
    $values = $parameter->findnodes('syntax/string/enumeration')
        unless $values;
    # XXX should note whether values are enumerations or patterns
    $values = $parameter->findnodes('syntax/string/pattern')
        unless $values;
    my $units = $parameter->findvalue('syntax/*/units/@value');
    my $description = $parameter->findvalue('description');
    my $descact = $parameter->findvalue('description/@action');
    my $default = $parameter->findvalue('syntax/default/@type') ?
        $parameter->findvalue('syntax/default/@value') : undef;
    my $deftype = $parameter->findvalue('syntax/default/@type');
    my $defstat = $parameter->findvalue('syntax/default/@status');

    # XXX majorVersion and minorVersion are no longer in the schema
    #my $majorVersion = $parameter->findvalue('@majorVersion');
    #my $minorVersion = $parameter->findvalue('@minorVersion');
    my ($majorVersion, $minorVersion) = dmr_version($parameter);

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $spec);

    # XXX I have a feeling that I need to be more rigorous re the distinction
    #     between nodes being absent and nodes having blank values (see the
    #     descdef handling here)

    my $syntax;
    if (defined($type)) {
	foreach my $attr (('@ref', '@base', '@maxLength',
                           'instanceRef/@refType', 'instanceRef/@targetParent',
                           'instanceRef/@targetParentScope',
                           'pathRef/@refType','pathRef/@targetParent',
                           'pathRef/@targetParentScope', 'pathRef/@targetType',
                           'pathRef/@targetDataType',
                           'enumerationRef/@targetParam',
                           'enumerationRef/@targetParamScope')) {
	    my $val = $type->findvalue($attr);
            my $tattr = $attr;
            $tattr =~ s/.*@//;
            # XXX very limited handling for status="deleted"; can tell by
            #     defined but empty attribute value
            if ($attr =~ /\//) {
                my $sattr = $attr;
                $sattr =~ s/@.*/\@status/;
                my $vst = $type->findvalue($sattr);
                if (defined $vst && $vst eq 'deleted') {
                    $syntax->{$tattr} = '';
                } else {
                    $syntax->{$tattr} = $val if $val ne '';
                }
            } else {
                $syntax->{$tattr} = $val if $val ne '';
            }
	}
        # XXX special case for nullValue; need to distinguish undef and empty
        my $nullValue = ($type->findnodes('enumerationRef/@nullValue'))[0];
        $syntax->{nullValue} = $nullValue->findvalue('.') if $nullValue;

        # handle multiple sizes
        foreach my $size ($type->findnodes('size')) {
            my $minLength = $size->findvalue('@minLength');
            my $maxLength = $size->findvalue('@maxLength');
            my $status = $size->findvalue('@status');

            # XXX this is brain dead handling of status="deleted"; should
            #     check for a matching entry
            if ($status && $status eq 'deleted') {
                $syntax->{sizes} = [];
                next;
            }

            $minLength = undef if $minLength eq '';
            $maxLength = undef if $maxLength eq '';
            if (defined $minLength || defined $maxLength) {
                push @{$syntax->{sizes}}, {minLength => $minLength,
                                           maxLength => $maxLength};
            }
        }

        # handle multiple ranges 
        # XXX no support for status="deleted"
        foreach my $range ($type->findnodes('range')) {
            my $minInclusive = $range->findvalue('@minInclusive');
            my $maxInclusive = $range->findvalue('@maxInclusive');
            my $step = $range->findvalue('@step');
            my $status = $range->findvalue('@status');

            # XXX this is brain dead handling of status="deleted"; should
            #     check for a matching entry
            if ($status && $status eq 'deleted') {
                $syntax->{ranges} = [];
                next;
            }

            $minInclusive = undef if $minInclusive eq '';
            $maxInclusive = undef if $maxInclusive eq '';
            $step = undef if $step eq '';
            if (defined $minInclusive || defined $maxInclusive ||
                defined $step) {
                push @{$syntax->{ranges}}, {minInclusive => $minInclusive,
                                            maxInclusive => $maxInclusive,
                                            step => $step};
            }
        }
    }
    $syntax->{hidden} = defined(($parameter->findnodes('syntax/@hidden'))[0]);
    $syntax->{list} = defined(($parameter->findnodes('syntax/list'))[0]);
    if ($syntax->{list}) {
        my $minItems = $parameter->findvalue('syntax/list/@minItems');
        my $maxItems = $parameter->findvalue('syntax/list/@maxItems');
        $minItems = undef if $minItems eq '';
        $maxItems = undef if $maxItems eq '';
        if (defined $minItems || defined $maxItems) {
            push @{$syntax->{listRanges}}, {minInclusive => $minItems,
                                            maxInclusive => $maxItems};
        }
        my $minLength = $parameter->findvalue('syntax/list/size/@minLength');
        my $maxLength = $parameter->findvalue('syntax/list/size/@maxLength');
        $minLength = undef if $minLength eq '';
        $maxLength = undef if $maxLength eq '';
        if (defined $minLength || defined $maxLength) {
            push @{$syntax->{listSizes}}, {minLength => $minLength,
                                           maxLength => $maxLength};
        }
    }

    if (defined($type)) {
        foreach my $facet (('instanceRef', 'pathRef', 'enumerationRef')) {
            $syntax->{reference} = $facet if $type->findnodes($facet);
        }
    }

    #print STDERR Dumper($syntax) if $syntax->{reference};

    $type = defined($type) ? $type->findvalue('local-name()') : '';

    my $tvalues = {};
    my $i = 0;
    foreach my $value (@$values) {
        my $facet = $value->findvalue('local-name()');
        my $access = $value->findvalue('@access');
        my $status = $value->findvalue('@status');
        my $optional = $value->findvalue('@optional');
        my $description = $value->findvalue('description');
        my $descact = $value->findvalue('description/@action');
        my $descdef = $value->findnodes('description')->size();
        $value = $value->findvalue('@value');
        
        $status = util_maybe_deleted($status);
        update_bibrefs($description, $spec);

        # XXX where should such defaults be applied? here is better
        $access = 'readOnly' unless $access;
        $status = 'current' unless $status;
        # don't default descact, so can tell whether it was specified
        
        $tvalues->{$value} = {access => $access, status => $status,
                              optional => $optional,
                              description => $description,
                              descact => $descact, descdef => $descdef,
                              facet => $facet,
                              i => $i++};
    }
    $values = $tvalues;
    #print STDERR Dumper($values);
    
    print STDERR "expand_model_parameter name=$name ref=$ref\n" if
        $verbose > 1;

    # ignore if doesn't match write-only criterion
    if ($writonly && $access eq 'readOnly') {
	print STDERR "\tdoesn't match write-only criterion\n" if $verbose > 1;
	return;
    }

    # XXX this is incomplete name / ref handling
    # XXX WFL2 my $tname = $name ? $name : $ref;
    my $oname = $name;
    my $oref = $ref;
    my $tname = $ref ? $ref : $name;
    my $path = $pnode->{path}.$tname;

    # the name may consist of multiple components; create any intervening
    # objects, returning the new parent and the last component of the name
    ($pnode, $name) = add_path($context, $mnode, $pnode, $tname, 1);
    # XXX this is more of the incomplete name / ref handling
    if ($ref) {
        $ref = $name;
        # XXX WFL2 $name = '';
        # XXX this will fail if $oname has multiple components (which it
        #     shouldn't have)
        $name = ($oname && $oref) ? $oname : '';
    }

    # determine name of previous sibling (if any) as a hint for where to
    # create the new node
    # XXX can i assume that there's ALWAYS a text node between each
    #     parameter node?
    my $previous = dmr_previous($parameter);
    my $prevnode = $parameter->previousSibling()->previousSibling();
    if (!defined $previous &&
        $prevnode && $prevnode->findvalue('local-name()') eq 'parameter') {
        $previous = $prevnode->findvalue('@name');
        $previous = $prevnode->findvalue('@base') unless $previous;
        $previous = undef if $previous eq '';
    }

    add_parameter($context, $mnode, $pnode, $name, $ref, $type, $syntax,
                  $access, $status, $description, $descact, $values, $default,
                  $deftype, $defstat, $majorVersion, $minorVersion,
                  $activeNotify, $forcedInform, $units, $previous);
}

# Expand a data model profile.
sub expand_model_profile
{
    my ($context, $mnode, $pnode, $profile) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};

    my $name = $profile->findvalue('@name');
    my $base = $profile->findvalue('@base');
    my $extends = $profile->findvalue('@extends');
    # XXX model no longer used
    my $model = $profile->findvalue('@model');
    my $status = $profile->findvalue('@status');
    my $description = $profile->findvalue('description');
    # XXX descact too

    $status = util_maybe_deleted($status);
    update_bibrefs($description, $spec);

    $name = $base unless $name;

    # XXX want to do this consistently; really want to get defaults from
    #     somewhere (not hard-coded)
    $status = 'current' unless $status;

    print STDERR "expand_model_profile name=$name base=$base ".
        "extends=$extends\n" if $verbose > 1;

    # XXX are there any valid circumstances under which would specify both
    #     base and extends?  I don't think it's invalid to do so.

    # determine name of previous sibling (if any) as a hint for where to
    # create the new node
    # XXX can i assume that there's ALWAYS a text node between each
    #     profile node?
    # XXX yes maybe, but it might not be a profile node, so would be best to
    #     avoid previousSibling() and just keep track of previous profile
    my $previous = dmr_previous($profile);
    my $prevnode = $profile->previousSibling()->previousSibling();
    if (!defined $previous &&
        $prevnode && $prevnode->findvalue('local-name()') eq 'profile') {
        $previous = $prevnode->findvalue('@name');
        $previous = undef if $previous eq '';
    }

    # if the context contains "previousProfile", it's from a component
    # reference, and applies only to the first profile
    if ($context->[0]->{previousProfile}) {
        $previous = $context->[0]->{previousProfile};
        undef $context->[0]->{previousProfile};
    }

    # XXX use mnode rather than pnode, because of problems when expanding
    #     profile components with paths (need to explain this!)

    # XXX also, there are problems if mix objects and profiles at the top level
    #     (never a problem in real data models); should ensure that all
    #     profiles come after all objects (or else handle this in the tree
    #     traversal; the latter is better; already do this for parameters)

    # check whether profile already exists
    my ($nnode) = grep {
        $_->{type} eq 'profile' && $_->{name} eq $name; } @{$mnode->{nodes}};
    if ($nnode) {
        # XXX don't automatically report this until have sorted out profile
        #     re-definition
        print STDERR "$name: profile already defined\n" if
            $pedantic && !$autobase && $base && $name ne $base;
        # XXX profiles can never change, so just give up; BUT this means that
        #     we won't detect corrections, deprecations etc, so is not good
        #     enough
        #return;
    } else {
        # if base specified, find base profile
        my $baseprof;
        if ($base) {
            ($baseprof) = grep {
                $_->{type} eq 'profile' && $_->{name} eq $base;
            } @{$mnode->{nodes}};
            print STDERR "{$file}$base: profile not found (ignoring)\n" unless
                $baseprof;
        }

        # otherwise check anyway for previous version (this allows later
        # versions to be defined both using base and standalone)
        else {
            # improve this; handle redef of prof / obj / par; add version...
            # make generated xml2 valid (need types)
            # XXX currently only copes with one previous version
            ($baseprof) = grep {
                my ($a) = ($name =~ /([^:]*)/);
                my ($b) = ($_->{name} =~ /([^:]*)/);
                $_->{type} eq 'profile' && $a eq $b;
            } @{$mnode->{nodes}};
            $base = $baseprof->{name} if $baseprof;
        }

        # if extends specified, find profiles that are being extended
        my $extendsprofs;
        if ($extends) {
            foreach my $extend (split /\s+/, $extends) {
                my ($extprof) = grep {
                    $_->{type} eq 'profile' && $_->{name} eq $extend;
                } @{$mnode->{nodes}};
                print STDERR "{$file}$extend: profile not found (ignoring)\n"
                    unless $extprof;
                push @$extendsprofs, $extprof if $extprof;
            }
        }

        my ($mname_only, $mversion_major, $mversion_minor) =
            ($mnode->{name} =~ /([^:]*):(\d+)\.(\d+)/);

        $nnode = {pnode => $mnode, path => $name, name => $name, base => $base,
                  extends => $extends, spec => $spec, type => 'profile',
                  access => '', status => $status, description => $description,
                  model => $model, nodes => [],
                  baseprof => $baseprof, extendsprofs => $extendsprofs,
                  majorVersion => $mversion_major,
                  minorVersion => $mversion_minor,
                  errors => {}};
        # determine where to insert the new node; after base profile first;
        # then after extends profiles; after previous node otherwise
        my $index = @{$mnode->{nodes}};
        if ($base) {
            for (0..$index-1) {
                if (@{$mnode->{nodes}}[$_]->{name} eq $base) {
                    $index = $_+1;
                    last;
                }
            }
        } elsif ($extends) {
            EXTEND: foreach my $extend (split /\s+/, $extends) {
                for (0..$index-1) {
                    if (@{$mnode->{nodes}}[$_]->{name} eq $extend) {
                        $index = $_+1;
                        last EXTEND;
                    }
                }
            }
        } elsif (defined $previous && $previous eq '') {
            $index = 0;
        } elsif ($previous) {
            for (0..$index-1) {
                if (@{$mnode->{nodes}}[$_]->{name} eq $previous) {
                    $index = $_+1;
                    last;
                }
            }
        }
        splice @{$mnode->{nodes}}, $index, 0, $nnode;

        # defmodel is the model in which the profile was first defined
        # (usually this is the current model, but not if this XML was
        # flattened by the xml2 report, in which case it is indicated
        # by dmr:version
        my ($majorVersion, $minorVersion) = dmr_version($profile);
        my $version = defined $majorVersion && defined $minorVersion ?
            qq{$majorVersion.$minorVersion} : undef;
        my $defmodel = $version ? qq{$mname_only:$version} : $mnode->{name};
        $profiles->{$name}->{defmodel} = $defmodel;
    }

    # expand nested parameters and objects
    foreach my $item ($profile->findnodes('parameter|object')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_profile_$element"->($context, $nnode, $nnode, $item);
    }
}

# Expand a data model profile object.
sub expand_model_profile_object
{
    my ($context, $Pnode, $pnode, $object) = @_;

    # this is the path attribute from component reference
    my $Path = $context->[0]->{path};

    my $name = $object->findvalue('@ref');
    my $access = $object->findvalue('@requirement');
    my $status = $object->findvalue('@status');
    # XXX description and descact too

    $status = 'current' unless $status;
    $status = util_maybe_deleted($status);

    print STDERR "expand_model_profile_object path=$Path ref=$name\n" if
        $verbose > 1;

    $name = $Path . $name if $Path;

    # these errors are reported by sanity_node
    unless ($objects->{$name} && %{$objects->{$name}}) {
        if ($noprofiles) {
        } elsif (!defined $Pnode->{errors}->{$name}) {
            $Pnode->{errors}->{$name} = {status => $status};
        } else {
            $Pnode->{errors}->{$name}->{status} = $status;
        }
        delete $Pnode->{errors}->{$name} if $status eq 'deleted';
        return;
    }

    # XXX need bad hyperlink to be visually apparent
    # XXX should check that access matches the referenced object's access

    # if requirement is not greater than that of the base profile or one of
    # the extends profiles, reduce it to 'notSpecified'
    my $can_ignore = 0;
    my $poa = {notSpecified => 0, present => 1, create => 2, delete => 3,
               createDelete => 4};
    my $baseprof = $Pnode->{baseprof};
    my $baseobj;
    if ($baseprof) {
        ($baseobj) = grep {$_->{name} eq $name} @{$baseprof->{nodes}};
        if ($baseobj && $poa->{$access} <= $poa->{$baseobj->{access}}) {
            $can_ignore = 1;
            print STDERR "profile $Pnode->{name} can ignore object $name\n" if
                $verbose;
        }
    }
    # XXX this logic isn't implemented for extends profiles (it is less
    #     necessary but can be added if need be)

    my $push_needed = 1;
    my $push_deferred = 0;
    my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
    my $nnode;
    if (@match) {
	$nnode = $match[0];
        $push_needed = 0;
    } else {
	$nnode = {pnode => $pnode, path => $name, name => $name,
                  type => 'objectRef', access => $access, status => $status,
                  nodes => [], baseobj => $baseobj};
        $push_deferred = 1;
    }

    # expand nested parameters and objects
    # XXX schema doesn't support nested objects
    # XXX this isn't quite right; should use profile equivalent of add_path()
    #     to create intervening nodes; currently top-level parameters are in
    #     the wrong place in the hierarchy
    foreach my $item ($object->findnodes('parameter|object')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_profile_$element"->($context, $Pnode, $nnode, $item);
    }

    # suppress push if possible
    # XXX not supporting previousObject in profiles
    if ($can_ignore && $push_deferred && !@{$nnode->{nodes}}) {
        print STDERR "profile $Pnode->{name} will ignore object $name\n" if
            $verbose;
    } elsif ($push_needed) {
        push(@{$pnode->{nodes}}, $nnode);
        $profiles->{$Pnode->{name}}->{$name} = $access;
    }
}

# Expand a data model profile parameter.
sub expand_model_profile_parameter
{
    my ($context, $Pnode, $pnode, $parameter) = @_;

    # this is the path attribute from component reference
    my $Path = $context->[0]->{path};

    my $name = $parameter->findvalue('@ref');
    my $access = $parameter->findvalue('@requirement');
    my $status = $parameter->findvalue('@status');
    # XXX description and descact too

    $status = 'current' unless $status;
    $status = util_maybe_deleted($status);

    print STDERR "expand_model_profile_parameter path=$Path ref=$name\n" if
        $verbose > 1;

    my $path = $pnode->{type} eq 'profile' ? $name : $pnode->{name}.$name;
    # special case for parameter at top level of a profile
    $path = $Path . $path if $Path && $Pnode == $pnode;

    # these errors are reported by sanity_node
    unless ($parameters->{$path} && %{$parameters->{$path}}) {
        if ($noprofiles) {
        } elsif (!defined $Pnode->{errors}->{$path}) {
            $Pnode->{errors}->{$path} = {status => $status};
        } else {
            $Pnode->{errors}->{$path}->{status} = $status;
        }
        delete $Pnode->{errors}->{$path} if $status eq 'deleted';
        return;
    } elsif ($access ne 'readOnly' &&
             $parameters->{$path}->{access} eq 'readOnly') {
	print STDERR "profile $Pnode->{name} has invalid requirement ".
            "($access) for $path ($parameters->{$path}->{access})\n";
    }

    # XXX need bad hyperlink to be visually apparent

    # if requirement is not greater than that of the base profile, reduce
    # it to 'notSpecified'
    my $ppa = {readOnly => 0, readWrite => 1};
    my $baseobj = $pnode->{baseobj};
    if ($baseobj) {
        my ($basepar) = grep {$_->{name} eq $name} @{$baseobj->{nodes}};
        if ($basepar && $ppa->{$access} <= $ppa->{$basepar->{access}}) {
            print STDERR "profile $Pnode->{name} ignoring parameter $path\n" if
                $verbose;
            return;
        }
    }

    # determine name of previous sibling (if any) as a hint for where to
    # create the new node
    # XXX can i assume that there's ALWAYS a text node between each
    #     parameter node?
    my $previous = dmr_previous($parameter);
    my $prevnode = $parameter->previousSibling()->previousSibling();
    if (!defined $previous &&
        $prevnode && $prevnode->findvalue('local-name()') eq 'parameter') {
        $previous = $prevnode->findvalue('@ref');
        $previous = undef if $previous eq '';
    }    

    my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
    my $nnode;
    if (@match) {
	$nnode = $match[0];
    } else {
        $nnode = {pnode => $pnode, name => $name, type => 'parameterRef',
                  access => $access, status => $status, nodes => []};

        # if previous is defined, it's a hint to insert this node after the
        # node of this name, if it exists
        my $index = @{$pnode->{nodes}};
        if (defined $previous && $previous eq '') {
            $index = 0;
        } elsif ($previous) {
            for (0..$index-1) {
                if (@{$pnode->{nodes}}[$_]->{name} eq $previous) {
                    $index = $_+1;
                    last;
                }
            }
        }
        splice @{$pnode->{nodes}}, $index, 0, $nnode;
        $profiles->{$Pnode->{name}}->{$path} = $access;
    }
}

# Helper to add a data model if it doesn't already exist (if it does exist then
# nothing in the new data model can conflict with anything in the old)
sub add_model
{
    my ($context, $pnode, $name, $ref, $isService, $status, $description,
        $descact, $majorVersion, $minorVersion) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};

    $ref = '' unless $ref;
    $isService = 0 unless $isService;
    $status = 'current' unless $status;
    $description = '' unless $description;
    # don't default descact, so can tell whether it was specified
    $majorVersion = 0 unless $majorVersion;
    $minorVersion = 0 unless $minorVersion;

    print STDERR "add_model name=$name ref=$ref isService=$isService\n" if
        $verbose > 1;

    # XXX monumental hack to allow vendor models to be derived from standard
    #     ones; assume that PrefixModel:a.b is derived from Model:c.d
    my ($tname, $tnamever) = $name =~ /([^:]*):(.*)/;
    my ($tref, $trefver) = $ref =~ /([^:]*):(.*)/;
    if ($tref && $tref ne $tname && $tname =~ /$tref$/) {
        print STDERR "hacked so model $name is derived from $ref\n"
            if $verbose;
        $tname = qq{$tref:$tnamever};
    }

    # if ref, find the referenced model
    my $nnode;
    if ($ref) {
        my @match = grep {
            my ($a) = ($tname =~ /([^:]*)/);
            my ($b) = ($_->{name} =~ /([^:]*)/);
            $_->{type} eq 'model' && $a eq $b;
        } @{$root->{nodes}};
        # there can't be more than one match
        if (@match) {
            $nnode = $match[0];
            print STDERR "reusing node $nnode->{name}\n" if $verbose > 1;
        } elsif (load_model($context, $file, $spec, $ref)) {
            @match = grep {
                my ($a) = ($tname =~ /([^:]*)/);
                my ($b) = ($_->{name} =~ /([^:]*)/);
                $_->{type} eq 'model' && $a eq $b;
            } @{$root->{nodes}};
            $nnode = $match[0];
            print STDERR "{$file}$ref: model loaded\n" if $verbose;
        } else {
            # XXX if not found, for now auto-create it
            print STDERR "{$file}$ref: model not found (auto-creating)\n";
        }
    }

    if ($nnode) {
        # cache current node contents
        my $cnode = util_copy($nnode, ['history', 'nodes']);

        # indicate that model was previously known (report might need to
        # use this info)
        $nnode->{history} = [] unless defined $nnode->{history};

        # XXX want similar "changed" logic to objects and parameters?

	$nnode->{name} = $name;

        # XXX this is still how we're handling the version number...
	$nnode->{majorVersion} = $majorVersion;
	$nnode->{minorVersion} = $minorVersion;

	# XXX spec should perhaps be an array and would therefore list all
	#     the specs that contributed to the data model definition
        # XXX unlike objects and parameters, we change it here, because this
        #     is defining a new model version (this is a problem when changing
        #     a model without changing the version, which is why we need a list
        #     of specs, then tools can use the first, last, or all of them
        # XXX the same goes for file
        # XXX also, should support lspec consistently for models?
	$nnode->{file} = $file;
	$nnode->{spec} = $spec;

        # XXX need cleverer comparison
        if ($description && $description ne $nnode->{description}) {
            print STDERR "$name: description: changed\n" if $verbose;
            $nnode->{description} = $description;
        }
        # XXX need cleverer comparison
        if ($descact && $descact ne $nnode->{descact}) {
            print STDERR "$name: descact: $nnode->{descact} -> $descact\n"
                if $verbose > 1;
            $nnode->{descact} = $descact;
        }

        # sub-tree is hidden (i.e. not reported) unless nodes within it are
        # referenced, at which point they and their parents are un-hidden
        # XXX suppress until sort out the fact that models defined in files
        #     specified on the command line should not be hidden
        # XXX this conditional restore is for DT and relies on the fact that
        #     name and ref will be same for DT (owing to hack in the caller)
        hide_subtree($nnode) if $name eq $ref;
        unhide_node($nnode);

        # retain info from previous versions
        unshift @{$nnode->{history}}, $cnode;
    } else {
        print STDERR "unnamed model (after $previouspath)\n" unless $name;
        my $dynamic = $pnode->{dynamic};
        # XXX experimental; may break stuff? YEP!
        #my $path = $isService ? '.' : '';
        my $path = '';
	$nnode = {name => $name, path => $path, file => $file, spec => $spec,
                  type => 'model', access => '',
                  isService => $isService, status => $status,
                  description => $description, descact => $descact,
                  default => undef, dynamic => $dynamic,
                  majorVersion => $majorVersion, minorVersion => $minorVersion,
                  nodes => [], history => undef};
        push @{$pnode->{nodes}}, $nnode;
        $previouspath = $path;
    }

    return $nnode;
}

# Load a deferred model.
sub load_model
{
    my ($context, $file, $spec, $ref) = @_;

    my $models = [];

    while (my ($model) = grep {$_->{element} eq 'model' && $_->{name} eq $ref}
           @{$imports->{$file}->{imports}}) {
        # XXX need better way of distinguishing defining and importing entry
        unshift @$models, $model if
            !@$models || $model->{file} ne $models->[0]->{file};
        last unless $model->{ref};
        $file = $model->{file};
        $ref  = $model->{ref};
    }

    foreach my $model (@$models) {
        my $file = $model->{file};
        my $spec = $model->{spec};
        my $item = $model->{item};
        unshift @$context, {file => $file, spec => $spec, path => '',
                            name => ''};
        expand_model($context, $root, $item);
        shift @$context;
    }

    # XXX need to check proper failure criteria
    return 1;
}

# Hide a sub-tree.
sub hide_subtree
{
    my ($node, $ponly) = @_;

    #print STDERR "hide_subtree: $node->{path}\n" if
    #    $node->{path} =~ /\.$/ && $verbose;

    unless ($node->{hidden}) {
        print STDERR "hiding $node->{type} $node->{name}\n" if $verbose > 1;
        $node->{hidden} = 1;
    }

    foreach my $child (@{$node->{nodes}}) {
        my $type = $child->{type};
        hide_subtree($child) unless $ponly &&
            $type =~ /^(model|object|profile|parameterRef|objectRef)$/;
    }
}

# Un-hide a node and its ancestors.
sub unhide_node
{
    my ($node) = @_;

    if ($node->{hidden}) {
        print STDERR "un-hiding $node->{type} $node->{name}\n" if $verbose > 1;
        $node->{hidden} = 0;
    }

    unhide_node($node->{pnode}) if $node->{pnode};
}

# Helper that, given a path, creates any intervening objects (if $return_last
# is true, doesn't create last component, but instead returns it)
# XXX want an indication that an object was created via add_path, so that all
#     values when it is next encountered will be used, e.g. "access"
sub add_path
{
    my ($context, $mnode, $pnode, $name, $return_last) = @_;

    print STDERR "add_path name=$pnode->{path}$name\n" if $verbose > 1;

    my $tname = $name;
    $tname =~ s/\.\{/\{/g;

    my $object = ($tname =~ /\.$/);
    my @comps = split /\./, $tname;

    my $last = '';
    if (@comps) {
        if ($return_last) {
            $last = pop(@comps);
	    $last =~ s/\{/\.\{/;
	    $last =~ s/$/\./ if $object;
        }
	for (my $i = 0; $i < @comps; $i++) {
	    $comps[$i] =~ s/\{/\.\{/;
	    $comps[$i] =~ s/$/\./;
	    $pnode = add_object($context, $mnode, $pnode, '', $comps[$i], 1);
	}
    }

    return ($pnode, $last);
}

# Helper to add an object if it doesn't already exist (if it does exist then
# nothing in the new object can conflict with anything in the old)
sub add_object
{
    my ($context, $mnode, $pnode, $name, $ref, $auto, $access, $status,
        $description, $descact, $majorVersion, $minorVersion, $previous) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};

    # if the context contains "previousObject", it's from a component
    # reference, and applies only to the first object
    if ($context->[0]->{previousObject}) {
        $previous = $context->[0]->{previousObject};
        undef $context->[0]->{previousObject};
    }

    $ref = '' unless $ref;
    $auto = 0 unless $auto;
    $access = 'readOnly' unless $access;
    $status = 'current' unless $status;
    $description = '' unless $description;
    # don't default descact, so can tell whether it was specified
    # don't touch version, since undefined is significant

    my $path = $pnode->{path} . ($ref ? $ref : $name);

    print STDERR "add_object name=$name ref=$ref auto=$auto\n" if
        $verbose > 1 || ($debugpath && $path =~ /$debugpath/);

    # if ref, find the referenced object
    my $nnode;
    if ($ref) {
        my @match = grep {$_->{name} eq $ref} @{$pnode->{nodes}};
        if (@match) {
            $nnode = $match[0];
            unhide_node($nnode);
        } else {
            # XXX if not found, for now auto-create it
            print STDERR "$path: object not found (auto-creating)\n";
            $name = $ref;
            $auto = 1;
        }
    } elsif ($name) {
        my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
        # XXX should this be unconditional?
        # XXX sometimes don't want report (need finer reporting control)
        if (@match && !$autobase) {
            print STDERR "$path: object already defined (new one ignored)\n"
                if $verbose || !$nowarnredef;
            return $match[0];
        }
	$nnode = $match[0];
    }

    if ($nnode) {
	# if auto, nothing more to be done (covers the case where are
        # traversing down the path of an existing object)
        # XXX it's important to do this before setting the history
        # XXX recent change to move before undefine "changed"
	return $nnode if $auto;

        # XXX hack for DT; doing it unconditionally, although there is
        #     probably a reason why this isn't normally done!
        $nnode->{changed} = undef;

        # cache current node contents
        my $cnode = util_copy($nnode, ['history', 'nodes', 'pnode']);

        # indicate that object was previously known (report might need to
        # use this info)
        $nnode->{history} = [] unless defined $nnode->{history};

        # XXX if both name and ref are defined, this is a rename operation
        # XXX what if the new-named object already exists?
        # XXX what are the implications for history?
        # XXX should this be marked as a change? yes
        if ($name && $ref) {
            $objects->{$path} = undef;
            $path = $pnode->{path} . $name;
            $nnode->{path} = $path;
            $nnode->{name} = $name;
            $objects->{$path} = $nnode;
            # XXX this does only half the job; should build the objects and
            #     parameters hashes after the tree has been built
            # XXX should also avoid nodes knowing their path names
            foreach my $tnode (@{$nnode->{nodes}}) {
                if ($tnode->{type} ne 'object') {
                    my $opath = $tnode->{path};
                    my $tpath = $path . $tnode->{name};
                    $tnode->{path} = $tpath;
                    $parameters->{$opath} = undef;
                    $parameters->{$tpath} = $tnode;
                }
            }
            print STDERR "$path: renamed from $ref\n" if $verbose;
        }

        # when an object is modified, its last spec (lspec) is updated
        my $changed = {};
 
        # XXX should use a utility routine for this change checking
        if ($access ne $nnode->{access}) {
            print STDERR "$path: access: $nnode->{access} -> $access\n"
                if $verbose;
            $nnode->{access} = $access;
            $changed->{access} = 1;
        }
        if ($status ne $nnode->{status}) {
            print STDERR "$path: status: $nnode->{status} -> $status\n"
                if $verbose;
            $nnode->{status} = $status;
            $changed->{status} = 1;
        }
        if ($description) {
            if ($description eq $nnode->{description}) {
                print STDERR "$path: description: same as previous\n"
                    unless $autobase;
            } else {
                # XXX not if descact is append?
                my $diffs = util_diffs($nnode->{description}, $description);
                print STDERR "$path: description: changed\n" if $verbose;
                print STDERR $diffs if $verbose > 1;
                $nnode->{description} = $description;
                $changed->{description} = $diffs;
            }
        }
        # XXX need cleverer comparison
        if ($descact && $descact ne $nnode->{descact}) {
            print STDERR "$path: descact: $nnode->{descact} -> $descact\n"
                if $verbose > 1;
            $nnode->{descact} = $descact;
        }
        if (($pnode->{dynamic} || $nnode->{access} ne 'readOnly') !=
            $nnode->{dynamic}) {
            print STDERR "$path: dynamic: $nnode->{dynamic} -> ".
                "$pnode->{dynamic}\n" if $verbose;
            $nnode->{dynamic} = $pnode->{dynamic} || $access ne 'readOnly';
            $changed->{dynamic} = 1;
        }        

        # XXX more to copy...

        # if not changed, retain info from previous versions
        # XXX have to be careful about tests in references, e.g. here
        #     if ($changed) doesn't work because it refers to the reference,
        #     not to the hash
        if (keys %$changed) {
            unshift @{$nnode->{history}}, $cnode;
            $nnode->{changed} = $changed;
            $nnode->{lspec} = $spec;
            mark_changed($pnode, $spec);
            # XXX experimental (absent description is like appending nothing)
            if (!$description) {
                $nnode->{description} = '';
                $nnode->{descact} = 'append';
            }
        }
    } else {
        print STDERR "unnamed object (after $previouspath)\n" unless $name;

        # XXX this is still how we're handling the version number...
	$majorVersion = $mnode->{majorVersion} unless defined $majorVersion;
	$minorVersion = $mnode->{minorVersion} unless defined $minorVersion;

        print STDERR "$path: added\n" if
            $verbose && $mnode->{history} && @{$mnode->{history}} && !$auto;

        mark_changed($pnode, $spec);
        
        my $dynamic = $pnode->{dynamic} || $access ne 'readOnly';

	$nnode = {pnode => $pnode, name => $name, path => $path, file => $file,
                  spec => $spec, lspec => $spec, type => 'object',
                  auto => $auto, access => $access, status => $status,
                  description => $description, descact => $descact,
                  default => undef, dynamic => $dynamic,
                  majorVersion => $majorVersion, minorVersion => $minorVersion,
                  nodes => [], history => undef};
        $previouspath = $path;
        # XXX ensure minEntries and maxEntries are defined (will be overridden
        #     by the caller if necessary; all this logic should be here)
        # XXX no, bad idea! but yes, all this logic should be here
        #$nnode->{minEntries} = 1;
        #$nnode->{maxEntries} = 1;
        # if previous is defined, it's a hint to insert this node after the
        # node of this name, if it exists
        my $index = @{$pnode->{nodes}};
        if (defined $previous && $previous eq '') {
            $index = 0;
        } elsif ($previous) {
            # XXX special case; if previous is the parent, insert as first
            #     child
            if ($previous eq $pnode->{path}) {
                $index = 0;
            } else {
                for (0..$index-1) {
                    if (@{$pnode->{nodes}}[$_]->{path} eq $previous) {
                        $index = $_+1;
                        last;
                    }
                }
            }
        }
        splice @{$pnode->{nodes}}, $index, 0, $nnode;
	$objects->{$path} = $nnode;
    }

    print STDERR Dumper(util_copy($nnode, ['pnode', 'nodes'])) if
        $debugpath && $path =~ /$debugpath/;

    return $nnode;
}

# Helper to mark a node's ancestors as having been changed
sub mark_changed
{
    my ($node, $spec) = @_;

    while ($node && $node->{type} eq 'object') {
        $node->{lspec} = $spec;
        $node = $node->{pnode};
    }
}

# Helper to add a parameter if it doesn't already exist (if it does exist then
# nothing in the new parameter can conflict with anything in the old)
sub add_parameter
{
    my ($context, $mnode, $pnode, $name, $ref, $type, $syntax, $access,
        $status, $description, $descact, $values, $default, $deftype, $defstat,
        $majorVersion, $minorVersion, $activeNotify, $forcedInform, $units,
        $previous)
        = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};

    # if the context contains "previousParameter", it's from a component
    # reference, and applies only to the first parameter
    if ($context->[0]->{previousParameter}) {
        $previous = $context->[0]->{previousParameter};
        undef $context->[0]->{previousParameter};
    }

    $ref = '' unless $ref;
    # don't default data type
    # assume that syntax defaulting has already been handled
    $access = 'readOnly' unless $access;
    $status = 'current' unless $status;
    $description = '' unless $description;
    # don't default descact, so can tell whether it was specified
    # assume that values defaulting has already been handled
    # don't touch default, since undefined is significant
    $deftype = 'object' unless $deftype;
    $defstat = 'current' unless $defstat;
    # don't touch version, since undefined is significant
    $activeNotify = 'normal' unless $activeNotify;
    # forcedInform is boolean

    my $path = $pnode->{path} . ($ref ? $ref : $name);
    my $auto = 0;

    print STDERR "add_parameter name=$name ref=$ref\n" if
        $verbose > 1 || ($debugpath && $path =~ /$debugpath/);

    # if ref, find the referenced parameter
    my $nnode;
    if ($ref) {
        my @match = grep {$_->{name} eq $ref} @{$pnode->{nodes}};
        if (@match) {
            $nnode = $match[0];
            unhide_node($nnode);
        } else {
            # XXX if not found, for now auto-create it
            print STDERR "$path: parameter not found (auto-creating)\n";
            $name = $ref;
            $auto = 1;
        }
    } elsif ($name) {
        my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
        # XXX should this be unconditional?
        # XXX sometimes don't want report (need finer reporting control)
        if (@match && !$autobase) {
            print STDERR "$path: parameter already defined (new one ignored)\n"
                if $verbose || !$nowarnredef;
            return;
        }
	$nnode = $match[0];
    }

    # XXX should maybe allow name to include an object spec; could call
    #     add_path on it (would like to know if any object in the path didn't
    #     already exist)

    if ($nnode) {
        # XXX hack for DT; doing it unconditionally, although there is
        #     probably a reason why this isn't normally done!
        $nnode->{changed} = undef;

        # cache current node contents
        my $cnode = util_copy($nnode, ['history', 'pnode', 'nodes']);

        # indicate that parameter was previously known (report might need to
        # use this info)
        $nnode->{history} = [] unless defined $nnode->{history};

        # XXX if both name and ref are defined, this is a rename operation
        # XXX what if the new-named parameter already exists?
        # XXX what are the implications for history?
        # XXX should this be marked as a change? yes
        if ($name && $ref) {
            $parameters->{$path} = undef;
            $path = $pnode->{path} . $name;
            $nnode->{path} = $path;
            $nnode->{name} = $name;
            $parameters->{$path} = $nnode;
            print STDERR "$path: renamed from $ref\n" if $verbose;
        }

        # XXX this isn't quite right... there is no inheritance except for
        #     the description (also, it's incomplete)

        # when a parameter is modified, its and its parent's last spec
        # (lspec) is updated
        my $changed = {};

        if ($access ne $nnode->{access}) {
            print STDERR "$path: access: $nnode->{access} -> $access\n"
                if $verbose;
            $nnode->{access} = $access;
            $changed->{access} = 1;
        }
        if ($status ne $nnode->{status}) {
            print STDERR "$path: status: $nnode->{status} -> $status\n"
                if $verbose;
            $nnode->{status} = $status;
            $changed->{status} = 1;
        }
        my $tactiveNotify = $activeNotify;
        $tactiveNotify =~ s/will/can/;
        if ($tactiveNotify ne $nnode->{activeNotify}) {
            print STDERR "$path: activeNotify: $nnode->{activeNotify} -> " .
                "$activeNotify\n" if $verbose;
            $nnode->{activeNotify} = $activeNotify;
            $changed->{activeNotify} = 1;
        }
        if ($forcedInform &&
            boolean($forcedInform) ne boolean($nnode->{forcedInform})) {
            print STDERR "$path: forcedInform: $nnode->{forcedInform} -> " .
                "$forcedInform\n" if $verbose;
            $nnode->{forcedInform} = $forcedInform;
            $changed->{forcedInform} = 1;
        }
        if ($description) {
            if ($description eq $nnode->{description}) {
                print STDERR "$path: description: same as previous\n"
                    unless $autobase;
            } else {
                # XXX not if descact is append?
                my $diffs = util_diffs($nnode->{description}, $description);
                print STDERR "$path: description: changed\n" if $verbose;
                print STDERR $diffs if $verbose > 1;
                $nnode->{description} = $description;
                $changed->{description} = $diffs;
            }
        }
        # XXX need cleverer comparison
        if ($descact && $descact ne $nnode->{descact}) {
            print STDERR "$path: descact: $nnode->{descact} -> $descact\n"
                if $verbose > 1;
            $nnode->{descact} = $descact;
        }
        if ($type && $type ne $nnode->{type}) {
            # XXX changed type is usually an error, but not necessarily if the
            #     new type is 'dataType' (need to check hierarchy)
            print STDERR "$path: type: $nnode->{type} -> $type\n"
                if $verbose && $type ne 'dataType';
            # XXX special case: if type changed to string, discard ranges
            #     (could take this further... but this case arose!)
            if ($type eq 'string' && $nnode->{syntax}->{ranges}) {
                print STDERR "$path: discarding existing ranges\n" if $verbose;
                $nnode->{syntax}->{ranges} = undef;
            }
            # XXX special case: if type changed to dataType, discard sizes and
            #     ranges
            if ($type eq 'dataType' && $nnode->{syntax}->{sizes}) {
                print STDERR "$path: discarding existing sizes\n" if $verbose;
                $nnode->{syntax}->{sizes} = undef;
            }
            if ($type eq 'dataType' && $nnode->{syntax}->{ranges}) {
                print STDERR "$path: discarding existing ranges\n" if $verbose;
                $nnode->{syntax}->{ranges} = undef;
            }
            $nnode->{type} = $type;
            $changed->{type} = 1;
        }
        my $cvalues = $nnode->{values};
        my $i = -1;
        foreach my $value (keys %$cvalues) {
            $i = $cvalues->{$value}->{i} if $cvalues->{$value}->{i} > $i;
        }
        $i++;
        foreach my $value (sort {$values->{$a}->{i} <=>
                                     $values->{$b}->{i}} keys %$values) {
            my $cvalue = $cvalues->{$value};
            my $nvalue = $values->{$value};

            if (!defined $cvalue) {
                print STDERR "$path: $value added\n" if $verbose;
                $cvalues->{$value} = $nvalue;
                $cvalues->{$value}->{i} = $i++;
                $changed->{values}->{$value} = 1;
                next;
            }

            # XXX need the more sophisticated logic that is used for
            #     parameters here
            # XXX need to take the order from the latest definition (currently
            #     are appending new values, and losing the order)
            # XXX also, not detecting deleted enumerations (relevant for DT)
            unshift @{$cvalues->{$value}->{history}}, util_copy($cvalue,
                                                                ['history']);
            
            if ($nvalue->{access} ne $cvalue->{access}) {
                print STDERR "$path: $value access: $cvalue->{access} -> ".
                    "$nvalue->{access}\n" if $verbose;
                $cvalues->{$value}->{access} = $nvalue->{access};
                $changed->{values}->{$value}->{access} = 1;
            }
            if ($nvalue->{status} ne $cvalue->{status}) {
                print STDERR "$path: $value status: $cvalue->{status} -> ".
                    "$nvalue->{status}\n" if $verbose;
                $cvalues->{$value}->{status} = $nvalue->{status};
                $changed->{values}->{$value}->{status} = 1;
            }
            if (boolean($nvalue->{optional}) ne boolean($cvalue->{optional})) {
                print STDERR "$path: $value optional: $cvalue->{optional} -> ".
                    "$nvalue->{optional}\n" if $verbose;
                $cvalues->{$value}->{optional} = $nvalue->{optional};
                $changed->{values}->{$value}->{optional} = 1;
            }
            # XXX should check for present and identical (see parameter
            #     description handling)
            if ($nvalue->{description} ne $cvalue->{description}) {
                # XXX for now, change only if new one is defined; want to
                #     handle this properly via get_description
                if ($nvalue->{descdef}) {
                    print STDERR "$path: $value description: ".
                        "$cvalue->{description} -> $nvalue->{description}\n"
                        if $verbose;
                    $cvalues->{$value}->{description} = $nvalue->{description};
                    $changed->{values}->{$value}->{description} = 1;
                }
            }
            if ($nvalue->{descact} &&
                $nvalue->{descact} ne $cvalue->{descact}) {
                print STDERR "$path: $value descact: $cvalue->{descact} -> ".
                    "$nvalue->{descact}\n" if $verbose;
                $cvalues->{$value}->{descact} = $nvalue->{descact};
                $changed->{values}->{$value}->{descact} = 1;
            }
        }
        #print STDERR Dumper($nnode->{values});
        # XXX this isn't perfect; some things are getting defined as '' when
        #     they should be left undefined? e.g. have seen list = ''
        # XXX for now, don't allow re-definition with empty string...
        # XXX stop press: empty string means "undefine" for some attributes
        #     (have to be careful, e.g. not mentioning <list/> doesn't mean
        #     it isn't a list
	while (my ($key, $value) = each %$syntax) {
            my $old = defined $nnode->{syntax}->{$key} ?
                $nnode->{syntax}->{$key} : '<none>';
            if ($value && (!defined $nnode->{syntax}->{$key} ||
                           $value ne $nnode->{syntax}->{$key})) {
                print STDERR "$path: $key: $old -> $value\n" if $verbose;
                $nnode->{syntax}->{$key} = $value;
                $changed->{syntax}->{$key} = 1;
            }
            # XXX this won't work now multiple sizes are supported; also
            #     ranges presumably weren't working before and still aren't
            if ($key =~ /(minLength|maxLength)/ && !$value &&
                defined $nnode->{syntax}->{$key}) {
                print STDERR "$path: $key: $old -> <deleted>\n" if $verbose;
                undef $nnode->{syntax}->{$key};
                $changed->{syntax}->{$key} = 1;                
            }
	}
        if (defined $default &&
            (!defined $nnode->{default} || $default ne $nnode->{default})) {
            my $old = defined $nnode->{default} ? $nnode->{default} : '<none>';
            my $new = defined $default ? $default : '<none>';
            print STDERR "$path: default: $old -> $new\n" if $verbose;
            $nnode->{default} = $default;
            $changed->{default} = 1;
        }
        if (defined $default && $deftype ne $nnode->{deftype}) {
            print STDERR "$path: deftype: $nnode->{deftype} -> $deftype\n"
                if $verbose;
            $nnode->{deftype} = $deftype;
            # note that this marks default, not deftype, as changed
            $changed->{default} = 1;
        }
        # to remove a default, status (defstat) is set to "deleted" (default
        # will always be defined, because the value attribute is mandatory
        if (defined $default && $defstat ne $nnode->{defstat}) {
            print STDERR "$path: defstat: $nnode->{defstat} -> $defstat\n"
                if $verbose;
            $nnode->{defstat} = $defstat;
            # note that this marks default, not defstat, as changed
            $changed->{default} = 1;
        }
        if ($pnode->{dynamic} != $nnode->{dynamic}) {
            print STDERR "$path: dynamic: $nnode->{dynamic} -> ".
                "$pnode->{dynamic}\n" if $verbose;
            $nnode->{dynamic} = $pnode->{dynamic};
            $changed->{dynamic} = 1;
        }
        
        # if changed, retain info from previous versions
        if (keys %$changed) {
            unshift @{$nnode->{history}}, $cnode;
            $nnode->{changed} = $changed;
            $nnode->{lspec} = $spec;
            mark_changed($pnode, $spec);
            # XXX experimental (absent description is like appending nothing)
            if (!$description) {
                $nnode->{description} = '';
                $nnode->{descact} = 'append';
            }
        }
    } else {
        print STDERR "$path: unnamed parameter\n" unless $name;
        print STDERR "$path: untyped parameter\n" unless $type;

        # XXX this is still how we're handling the version number...
	$majorVersion = $mnode->{majorVersion} unless defined $majorVersion;
	$minorVersion = $mnode->{minorVersion} unless defined $minorVersion;

        print STDERR "$path: added\n" if
            $verbose && $mnode->{history} && @{$mnode->{history}} && !$auto;

        my $dynamic = $pnode->{dynamic};

        mark_changed($pnode, $spec);

        # XXX I think this is to with components and auto-removing defaults
        #     from them if they are used in a static environment
        # XXX but it breaks perfectly normal defaults, since it applies not
        #     only to components but to imported models :( (need a more direct
        #     test)
        # XXX why should it break anything; restore with debug message...
        #$default = undef if !$dynamic && @$context > 1;
        if (defined $default && $deftype eq 'object' && !$dynamic) {
            $default = undef;
            print STDERR "$path: removing default value\n" if $verbose;
        }

	$nnode = {pnode => $pnode, name => $name, path => $path, file => $file,
		  spec => $spec, lspec => $spec, type => $type,
                  syntax => $syntax, access => $access, status => $status,
		  description => $description, descact => $descact,
                  values => $values, default => $default, deftype => $deftype,
                  defstat => $defstat, dynamic => $dynamic,
                  majorVersion => $majorVersion, minorVersion => $minorVersion,
                  activeNotify => $activeNotify, forcedInform => $forcedInform,
                  units => $units, nodes => [], history => undef};
        # if previous is defined, it's a hint to insert this node after the
        # node of this name, if it exists
        my $index = @{$pnode->{nodes}};
        if (defined $previous && $previous eq '') {
            $index = 0;
        } elsif ($previous) {
            for (0..$index-1) {
                if (@{$pnode->{nodes}}[$_]->{name} eq $previous) {
                    $index = $_+1;
                    last;
                }
            }
        }
        splice @{$pnode->{nodes}}, $index, 0, $nnode;
        $pnode->{lspec} = $spec;
	$parameters->{$path} = $nnode;
    }

    print STDERR Dumper(util_copy($nnode, ['pnode', 'nodes'])) if
        $debugpath && $path =~ /$debugpath/;
}

# Update list of bibrefs that are actually used (each entry is an array of the
# specs that use the bibref)
sub update_bibrefs
{
    my ($value, $spec) = @_;

    my @ids = ($value =~ /\{\{bibref\|([^\|\}]+)/g);
    foreach my $id (@ids) {
        print STDERR "marking bibref $id used (spec=$spec)\n" if $verbose > 1;
        push @{$bibrefs->{$id}}, $spec unless
            grep {$_ eq $spec} @{$bibrefs->{$id}};
    }
}

# Determine whether a description contains invalid bibrefs
# XXX or could do during template expansion
sub invalid_bibrefs
{
    my ($value) = @_;

    my @ids = ($value =~ /\{\{bibref\|([^\|\}]+)/g);
    my $bad = [];
    foreach my $id (@ids) {
        push @$bad, $id unless
            grep {$_->{id} eq $id} @{$root->{bibliography}->{references}};
    }
    return $bad;
}

# Determine whether a maximum length is appropriate for this parameter
sub maxlength_appropriate
{
    my ($path, $name, $type) = @_;

    return 0 if $type !~ /string|base64|hexBinary/;

    return 0 if $path =~ /Previous|Current/;

    return 0 if $name =~ /(dest|destination|group|host|ip|mac|max|min|source|src|server|subnet).*(addr|address|ip|mask)$/i;
    return 0 if $name =~ /(bssid|chaddr|chaddrmask|defaultgateway|host|yiaddr)$/i;

    return 1;
}

# Determine whether a parameter is list-valued
sub is_list
{
    my ($syntax) = @_;

    return $syntax->{list};
}

# Determine whether enumerated values are appropriate for this parameter
sub values_appropriate
{
    my ($name, $type) = @_;

    return $type eq 'string';
}

# Determine whether a parameter has enumerated values
sub has_values
{
    my ($values) = @_;

    return (defined $values && %$values) ? 1 : 0;
}

# Determine whether a parameter supports a specific enumerated value
sub has_value
{
    my ($values, $search) = @_;

    return (grep { $_ eq $search } keys %$values) ? 1 : 0;
}

# Get formatted enumerated values
# XXX format is currently report-dependent
sub get_values
{
    my ($values, $anchor) = @_;

    return '' unless $values;

    my $list = '';
    foreach my $value (sort {$values->{$a}->{i} <=>
                                 $values->{$b}->{i}} keys %$values) {
        my $cvalue = $values->{$value};

	my $description = $cvalue->{description};
	my $optional = boolean($cvalue->{optional});
	my $deprecated = $cvalue->{status} eq 'deprecated';
	my $obsoleted = $cvalue->{status} eq 'obsoleted';
	my $deleted = $cvalue->{status} eq 'deleted';

        next if $deleted;

        # don't mark optional if deprecated or obsoleted
        $optional = 0 if $deprecated || $obsoleted;

	#my $quote = $report ne 'xls' && $value !~ /^</;
	my $quote = $cvalue !~ /^</;

        # XXX this assumes HTML really
        if ($value eq '') {
            $value = '<Empty>';
            $description = '{{empty}}' unless $description;
        }

        # remove any leading or trailing whitespace
        $description =~ s/^\s*//;
        $description =~ s/\s*$//;

        # avoid leading upper-case in value description unless an acronym
        # XXX better than it was (it was unconditional) but is it OK?
        $description = lcfirst $description
            if ($description =~ /^[A-Z][a-z]/ &&
                $description !~ /^\S+\s+[A-Z]/);
        $description =~ s/\.$//;

	my $any = $description || $optional || $deprecated || $obsoleted;

	#$list .= '* ' unless $report eq 'xls';
	$list .= '* ';
	#$list .= '"' if $quote;
	$list .= "''";
        if (!$anchor) {
            $list .= $value;
        } else {
            # XXX remove backslashes (needs doing properly)
            my $tvalue = $value;
            $tvalue =~ s/\\//g;

            $list .= qq{%%$value%%$tvalue%%};
        }
	#$list .= '"' if $quote;
	$list .= "''";
	$list .= ' (' if $any;
	$list .= $description . ', ' if $description;
	$list .= 'OPTIONAL, ' if $optional;
	$list .= 'DEPRECATED, ' if $deprecated;
	$list .= 'OBSOLETED, ' if $obsoleted;
	chop $list if $any;
	chop $list if $any;
	$list .= ')' if $any;
	$list .= "\n";
    }
    chop $list;
    return $list;
}

# Get description, accounting for the possibility that it hasn't changed from
# the previous version.  History, if supplied, is an array of nodes from
# previous versions, most recent first, so $history->[0]->{description} is
# the description from the previous version.
sub get_description
{
    my ($new, $descact, $history, $resolve) = @_;

    # XXX there are still problems with "resolve"; can get duplicate
    #     descriptions :(

    # XXX this isn't quite good enough; if description is unaltered in
    #     latest version, this returns the value from the previous version,
    #     whereas it should return an empty string
    # XXX or perhaps this is OK, but need better "changed" logic in the caller?

    # get old description if any
    # XXX this isn't clever enough to detect that "A", "B" (append) and "AB"
    #     in successive versions is not a change
    my $old = get_old_description($history);

    # XXX do this here because the two pieces of description may have different
    #     whitespace conventions (need to rename routine)
    $old = html_whitespace($old);
    $new = html_whitespace($new);

    # if no descact it defaults to replace / create
    $descact = defined $old ? 'replace' : 'create' unless $descact;
    $old = '' unless defined $old;

    # adjust if new description is the old one with text appended (but only if
    # the additional text begins with a newline)
    if ($descact eq 'replace' && length($new) > length($old) && 
        substr($new, 0, length($old)) eq $old &&
        substr($new, length($old), 1) eq "\n") {
        $new = substr($new, length($old));
        $new =~ s/^\s+//;
        $descact = 'append';
    }

    if ($descact eq 'replace') {
        $new = '' if $new eq $old && !$resolve;
    } elsif ($descact eq 'append') {
        # XXX fudge: if new begins with template, no newline (allows templates
        #     such as {{enum}} where preceding newline is significant to work
        # XXX the above fails for (e.g.) {{param}}!
        my $sep = $new =~ /^[ \t]*\{\{/ ? "  " : "\n";
        # XXX I don't trust this logic; need to make more transparently correct
        # XXX need to check whether has changed in latest version; if not, can
        #     end up with appending twice
        $new = $old . (($old ne '' && $new ne '') ? $sep : "") . $new
            if $resolve;
    }
    return ($new, $descact);
}

# Get old description from history (complicated by the fact that there can be
# several stages of history)
# XXX duplicates some of the logic of get_description
sub get_old_description
{
    my ($history) = @_;

    # XXX old version that doesn't handle more than one stage of history
    #return $history && @$history ? $history->[0]->{description} : undef;

    return undef unless $history && @$history;

    my $old = '';
    foreach my $item (reverse @$history) {
        my $descact = $item->{descact};
        my $new = $item->{description};
        if ($descact eq 'append') {
            # XXX same fudge as in get_description
            my $sep = $new =~ /^[ \t]*\{\{/ ? "  " : "\n";
            $old .= (($old ne '' && $new ne '') ? $sep : "") . $new;
        } else {
            $old = $new;
        }
    }

    return $old;
}

# Add formatted enumerated values, if any, to the description
# XXX should be phased out in favor of template expansion
sub add_values
{
    my ($description, $values) = @_;

    if (!$description) {
	;
    } elsif (!$values) {
	$description = remove_values($description);
    } elsif ($description =~ /{{enum}}/) {
	$description =~ s/[ \t]*{{enum}}/$values/;
    } else {
	$description .= "\n" . $values;
    }

    return $description;
}

# Remove "values" indicator, returning the result
# XXX should be phased out in favor of template expansion
sub remove_values
{
    my ($description) = @_;

    $description =~ s/[ \t]*{{enum}}\n?//;

    return $description;
}

# Remove '{{append}}' or '{{replace}}' indicator, returning whether either was
# found, and the result
# XXX should be phased out (currently used only by XLS report?)
sub remove_descact
{
    my ($description, $descact) = @_;

    if ($description =~ /{{(append|replace)}}/) {
	$descact = $1;
	$description =~ s/{{$descact}}\n?//;
    }

    return ($description, $descact);
}

# Form a "type" string (as close as possible to the strings in existing "Type"
# columns)
sub type_string
{
    my ($type, $syntax) = @_;

    my $typeinfo = get_typeinfo($type, $syntax);
    my ($value, $dataType) = ($typeinfo->{value}, $typeinfo->{dataType});

    # XXX if named data type, should traverse data type hierarchy to determine
    #     base type but at the time of writing, data types are used only for
    #     IPAddress and MACAddress
    if (!$dataType) {
    } elsif ($value =~ /^(IP(v4|v6)?|MAC)(Address|Prefix)$/) {
        $value = 'string';
    } else {
        print STDERR "$value: named data types other than IPAddress and ".
            "MACAddress not supported\n" if $verbose;
    }

    # lists are always strings at the CWMP level
    if ($syntax->{list}) {
        $value = 'string';
        $value .= add_size($syntax, {list => 1});
    } else {
        $value .= add_size($syntax);
        $value .= add_range($syntax);
    }

    return $value;
}

# Form a "type", "string(maxLength)" or "int[minInclusive:maxInclusive]" syntax
# string (multiple sizes and ranges are supported)
sub syntax_string
{
    my ($type, $syntax, $human) = @_;

    my $list = $syntax->{list};

    my $typeinfo = get_typeinfo($type, $syntax, {human => $human});
    my ($value, $unsigned) = ($typeinfo->{value}, $typeinfo->{unsigned});

    $value .= add_size($syntax, {human => $human, item => 1});
    $value .= add_range($syntax, {human => $human, unsigned => $unsigned});

    if ($list) {
        $value = 'list' .
            add_size($syntax, {human => $human, list => 1}) .
            add_range($syntax, {human => $human, unsigned => $unsigned,
                                list => 1}) . ' of ' . $value;
    }

    return $value;
}

# Get data type and associated information
sub get_typeinfo
{
    my ($type, $syntax, $opts) = @_;

    my $value = $type;
    my $dataType = ($value eq 'dataType');
    my $unsigned = ($value =~ /^unsigned/);

    if ($syntax->{ref}) {
        $value = $syntax->{ref};
    } elsif ($syntax->{base}) {
        $value = $syntax->{base};
    }

    if ($opts->{human}) {
        $value =~ s/^base64$/BASE64 string/;
        $value =~ s/^hexBinary$/Hex binary string/;
        $value =~ s/^int$/integer/;
        $value =~ s/^unsignedInt$/unsigned integer/;
        $value =~ s/^unsignedLong$/unsigned long/;
        # XXX could try to split multi-word type names, e.g. IPAddress?
        # XXX this is heuristic (it works for IPAddress etc)
        if ($syntax->{list}) {
            $value .= 'e' if $value =~ /s$/;
            $value .= 's';
        }
    }

    return {value => $value, dataType => $dataType, unsigned => $unsigned};
}

# Add size or list size to type / value string
# XXX need better wording for case where a single maximum is specified?
# XXX should check for overlapping sizes
sub add_size
{
    my ($syntax, $opts) = @_;

    my $sizes = $opts->{list} ? 'listSizes' : 'sizes';
    return '' unless defined $syntax->{$sizes} && @{$syntax->{$sizes}};

    my $value = '';

    # all sizes guarantee to have a defined minlen or maxlen (or both)

    # XXX in general, not using "defined"

    $value .= ' ' if $opts->{human};
    $value .= '(';

    # special case where there is only a single size and no minLength (mostly
    # to avoid changing what people are already used to)
    if (@{$syntax->{$sizes}} == 1 &&
        !$syntax->{$sizes}->[0]->{minLength} &&
        $syntax->{$sizes}->[0]->{maxLength}) {
        $value .= 'maximum length ' if $opts->{human};
        $value .= $syntax->{$sizes}->[0]->{maxLength};
        $value .= ')';
        return $value;
    }

    $value .= 'item ' if $opts->{human} && $opts->{item};
    $value .= 'length ' if $opts->{human};

    my $first = 1;
    foreach my $size (@{$syntax->{$sizes}}) {
        my $minlen = $size->{minLength};
        my $maxlen = $size->{maxLength};

        $value .= ', ' unless $first;

        if (!$opts->{human}) {
            $value .= $minlen . ':' if $minlen;
            $value .= $maxlen if $maxlen;
        } elsif ($minlen && !$maxlen) {
            $value .= 'at least ' . $minlen;
        } elsif (!$minlen && $maxlen) {
            $value .= 'up to ' . $maxlen;
        } elsif ($minlen == $maxlen) {
            $value .= $minlen;
        } else {
            $value .= $minlen . ' to ' . $maxlen;
        }

        $first = 0;
    }    

    $value =~ s/(.*,)/$1 or/ if $opts->{human};

    $value .= ')';

    return $value;
}

# Add ranges or list ranges to type / value string
# XXX should check for overlapping ranges
sub add_range
{
    my ($syntax, $opts) = @_;

    my $ranges = $opts->{list} ? 'listRanges' : 'ranges';
    return '' unless defined $syntax->{$ranges} && @{$syntax->{$ranges}};

    my $value = '';

    # all ranges guarantee to have a defined minval or maxval (or both)

    $value .= ' ' if $opts->{human};
    $value .= $opts->{human} ? '(' : '[';
    $value .= 'value ' if $opts->{human} && !$opts->{list};

    my $first = 1;
    foreach my $range (@{$syntax->{$ranges}}) {
        my $minval = $range->{minInclusive};
        my $maxval = $range->{maxInclusive};
        my $step = $range->{step};

        $step = 1 unless defined $step;

        $value .= ', ' unless $first;

        if (!$opts->{human}) {
            if (defined $minval && defined $maxval && $minval == $maxval) {
                $value .= $minval if defined $minval;
            } else {
                $value .= $minval if defined $minval;
                $value .= ':';
                $value .= $maxval if defined $maxval;
                $value .= ':' . $step if $step != 1;
            }
        } else {
            my $add_step = 0;
            # XXX default minimum to 0 for unsigned types
            $minval = 0 if $opts->{unsigned} && !defined $minval;
            if (defined $minval && defined $maxval && $minval != $maxval) {
                $value .= $minval . ' to ' . $maxval;
                $add_step = 1;
            } elsif (defined $minval && defined $maxval && $minval == $maxval) {
                $value .= $minval;
            } elsif (defined $minval) {
                $value .= 'at least ' . $minval;
                $add_step = 1;
            } elsif (defined $maxval) {
                $value .= 'up to ' . $maxval;
                $add_step = 1;
            }
            $value .= ' stepping by ' . $step if $add_step && $step != 1;
            $value .= ' items' if $opts->{list};
        }
        $first = 0;
    }

    $value =~ s/(.*,)/$1 or/ if $opts->{human};

    $value .= $opts->{human} ? ')' : ']';

    return $value;
}

# Return 0/1 given string representation of boolean
sub boolean
{
    my ($value) = @_;
    return ($value =~ /1|t|true/i) ? 1 : 0;
}

# Form a "m.n" version string from major and minor versions
sub version
{
    my ($majorVersion, $minorVersion) = @_;

    my $value = "";
    $value .= defined($majorVersion) ? $majorVersion : "";
    $value .= defined($minorVersion) ? ".$minorVersion" : "";
    return $value;
}

# Parse a data model definition file.
sub parse_file
{
    my ($dir, $file)= @_;

    # XXX only use dir of non-blank ('' can be interpreted as '/')
    my $tfile = $dir ? File::Spec->catfile($dir, $file) : $file;

    print STDERR "parse_file: parsing $tfile\n" if $verbose;

    # parse file
    my $parser = XML::LibXML->new();
    my $tree = $parser->parse_file($tfile);
    my $toplevel = $tree->getDocumentElement;

    # for XSD files, pick up target namespace and return
    return $toplevel if $tfile =~ /\.xsd$/;

    # XXX expect these all to be the same if processing multiple documents,
    #     but should check; really should keep separate for each document
    my $tns = 
    my $xsi = 'xsi';
    my @nslist = $toplevel->getNamespaces();
    for my $ns (@nslist) {
        my $declaredURI = $ns->declaredURI();
        my $declaredPrefix = $ns->declaredPrefix();

        if ($declaredURI =~ /cwmp:datamodel-[0-9]/) {
            $root->{dm} = $declaredURI;
        } elsif ($declaredURI =~ /cwmp:datamodel-report-/) {
            $root->{dmr} = $declaredURI;
        } elsif ($declaredURI =~ /XMLSchema-instance/) {
            $root->{xsi} = $declaredURI;
            $xsi = $declaredPrefix;
        }
    }

    # XXX should parse it properly, but for now just check that we keep the
    #     one that defines the dmr location (it will define the dm location
    #     too)
    $root->{schemaLocation} = $toplevel->findvalue("\@$xsi:schemaLocation")
        unless $root->{schemaLocation} &&
        $root->{schemaLocation} =~ /cwmp:datamodel-report-/;
    $root->{schemaLocation} =~ s/\s+/ /g;

    # XXX if no dmr, use default
    $root->{dmr} = "urn:broadband-forum-org:cwmp:datamodel-report-0-1"
        unless $root->{dmr};

    return $toplevel;
}

# Find file by searching for the highest corrigendum number (if omitted)
# XXX should also support proper search path and shouldn't assume ".xml"
# XXX note that it works if supplied file includes directory, but only by
#     chance and not by design
sub find_file
{
    my ($file) = @_;
    
    # search path
    my $dirs = [];

    # if file includes directory, it overrides the search path for this call
    # XXX is it safe to ignore the volume?
    (my $vol, my $dir, $file) = File::Spec->splitpath($file);
    if ($dir) {
        push @$dirs, $dir;
    } else

    # always prepend "." to the list of includes
    {
        push @$dirs, File::Spec->curdir();
        push @$dirs, @$includes;
    }

    my $ffile = $file;
    my $fdir = '';

    # support names of form name-i-a[-c][label].xml where name is of the form
    # "xx-nnn", i, a and c are numeric and label can't begin with a digit
    my ($name, $i, $a, $c, $label) =
        $file =~ /^([^-]+-\d+)-(\d+)-(\d+)(?:-(\d+))?(-\D.*)?\.xml$/;

    # if name, issue (i) and amendment (a) are defined but corrigendum number
    # (c) is undefined, search for the highest corrigendum number
    if (defined $name && defined $i && defined $a && !defined $c) {
        $label = '' unless defined $label;
        foreach my $dir (@$dirs) {
            my @files = glob(File::Spec->catfile($dir,
                                                 qq{$name-$i-$a-*$label.xml}));
            foreach my $file (@files) {
                # remove directory part
                (my $tvol, my $tdir, $file) = File::Spec->splitpath($file);
                # XXX assumes no special RE chars anywhere...
                my ($n) = $file =~ /^$name-$i-$a-(\d+)$label\.xml$/;
                if (defined $n && (!defined $c || $n > $c)) {
                    $c = $n;
                    $fdir = $dir;
                }
            }
        }
        $c = defined($c) ? ('-' . $c) : '';
        $ffile = qq{$name-$i-$a$c$label.xml};
    }

    # otherwise no need to look for highest corrigendum number, either because
    # file name doesn't match pattern, e.g. it's unversioned, or because
    # corrigendum number is defined; still need to search directories though
    else {
        foreach my $dir (@$dirs) {
            if (-r File::Spec->catfile($dir, $ffile)) {
                $fdir = $dir;
                last;
            }
        }
    }

    print STDERR "fdir $fdir ffile $ffile\n" if $verbose;
    return ($fdir, $ffile);
}

# Check whether specs match
sub specs_match
{
    my ($spec, $fspec) = @_;

    # spec is spec from import and fspec is spec from file; if spec omits the
    # corrigendum number it matches all corrigendum numbers

    # support specs that end name-i-a[-c] where name is of the form "xx-nnn",
    # and i, a and c are numeric
    my ($c) = $spec =~ /[^-]+-\d+-\d+-\d+(?:-(\d+))?$/;

    # if corrigendum number is defined, require exact match
    return ($fspec eq $spec) if defined $c;

    # if corrigendum number is undefined in spec, remove it from fspec (if
    # present) before comparing
    ($c) = $fspec =~ /[^-]+-\d+-\d+-\d+(?:-(\d+))?$/;
    $fspec =~ s/-\d+$// if defined $c;
    return ($fspec eq $spec);
}

# Null report of node.
# XXX it's a bit inefficient to do it this way
sub null_node {}

# Text report of node.
sub text_node
{
    my ($node, $indent) = @_;

    if (!$indent) {
        print "$node->{spec}\n";
    } else {
        my $type = type_string($node->{type}, $node->{syntax});
        my $base = $node->{history}->[0]->{name};
        print "  "x$indent . "$type $node->{name}" .
            ($base && $base ne $node->{name} ? ('(' . $base . ')') : '') .
            ($node->{access} ne 'readOnly' ? ' (W)' : '') .
            ((defined $node->{default}) ? (' [' . $node->{default} . ']'):'') .
            ($node->{model} ? (' ' . $node->{model}) : '') .
            (($node->{status} ne 'current') ? (' ' . $node->{status}) : '') .
            ($node->{changed} ?
             (' #changed: ' . xml_changed($node->{changed})) : '') . "\n";
    }
}

# TAB report of node.
sub tab_node
{
    my ($node, $indent) = @_;

    # use indent as a first-time flag
    if (!$indent) {
	print "Name\tType\tWrite\tDescription\tObject Default\tVersion\tSpec\n";
    } else {
	my $attr = $node->{type} eq 'object' ? 'path' : 'name';
	my $name = tab_escape($node->{$attr});
	my $spec = tab_escape($node->{spec});
	my $type = tab_escape($node->{type});
	my $access = tab_escape($node->{access});
	my $description = tab_escape($node->{description});
	my $default = tab_escape($node->{default});
	my $version =
	    tab_escape(version($node->{majorVersion}, $node->{minorVersion}));
	print("$name\t$type\t$access\t$description\t$default\t$version\t$spec\n");
    }
}

# Escape a value suitably for import as tab-separated items into Excel.
sub tab_escape {
    my ($value) = @_;

    $value = util_default($value);

    # just in case...
    $value =~ s/\t/ /g;

    $value =~ s/\n/\&#10;\&#10;/g;

    # escape quotes
    $value =~ s/\"/\"\"/g;

    # quote the result
    $value = '"' . $value . '"';

    return $value;
}

# DM Schema XML report of node.
# XXX does not handle everything (is aimed at processing input documents that
#     have been derived from existing Word tables)

# have to work harder to avoid nesting objects :(
my $xml_objact = 0;

sub xml_node
{
    my ($node, $indent) = @_;

    $indent = 0 unless $indent;

    # generic node properties
    my $changed = $node->{changed};
    my $history = $node->{history};
    my $name = $node->{name};
    my $path = $node->{path};
    my $file = $node->{file};
    my $spec = $node->{spec};
    my $type = $node->{type};
    my $access = $node->{access};
    my $status = $node->{status};
    my $description = $node->{description};
    my $descact = $node->{descact};

    # on creation, history is undef; on re-encounter it's []; on modification,
    # it's non-empty
    my $basename = ref($history) ? 'base' : 'name';

    my $schanged = xml_changed($changed);

    ($description, $descact) = get_description($description, $descact,
                                               $history);
    $description = xml_escape($description);

    $status = $status ne 'current' ? qq{ status="$status"} : qq{};
    $descact = $descact ne 'create' ? qq{ action="$descact"} : qq{};

    # use node to maintain state (assumes that there will be only a single
    # XML report of a given node)
    $node->{xml} = {action => 'close', element => $type};

    # lspec is the spec from the last command-line-specified file
    # XXX temporarily suppress spec test... need to re-evaluate...
    #return unless $node->{spec} eq $lspec;

    my $i = "  " x $indent;

    # zero indent is root element
    if (!$indent) {
        my $dm = $node->{dm};
        my $xsi = $node->{xsi};
        my $schemaLocation = $node->{schemaLocation};
        my $dataTypes = $node->{dataTypes};
        my $bibliography = $node->{bibliography};

        print qq{$i<?xml version="1.0" encoding="UTF-8"?>
$i<!-- \$Id\$ -->
$i<!-- note: this is an automatically generated XML report -->
$i<dm:document xmlns:dm="$dm"
$i             xmlns:xsi="$xsi"
$i             xsi:schemaLocation="$schemaLocation"
$i             spec="$lspec">
};
        print qq{$i  <description$descact>$description</description>\n} if
            $description;

        # XXX need to be cleverer... this will include both explicit and
        #     implicit imports
        my $imported = {};
        foreach my $file (sort {$imports->{$a}->{i} <=>
                                    $imports->{$b}->{i}} keys %{$imports}) {
            my $spec = $imports->{$file}->{spec};
            
            # don't want to import our own definitions
            # XXX really should use file rather than spec for this, because
            #     nothing guarantees that the spec is unique
            # XXX or perhaps not... if the spec is the same in more than one
            #     file, then those files are associated with the same spec!
            # XXX hack to ensure import types into TR-106 (is exactly this
            #     issue)
            next if $spec eq $lspec && $spec !~ /tr-106$/;

            # XXX special case, don't change "TR-106t.xml"
            my $ifile = $file;
            $ifile = $file . '-' . $importsuffix
                if $importsuffix && $file !~ /TR-106t$/;
            $ifile .= '.xml';
            print qq{$i  <import file="$ifile" spec="$spec">\n};
            foreach my $import (@{$imports->{$file}->{imports}}) {
                my $element = $import->{element};
                my $name = $import->{name};
                my $ref = $import->{ref};
                my $iref = $ref;

                # XXX this mis-fires for imported data types so, rather than
                #     fixing it, avoid the problem
                $name = '_' . $name if $element ne 'dataType' &&
                    grep {$_->{element} eq $element && $_->{name} eq $name}
                @{$imports->{$lfile}->{imports}};

                $ref = $ref ne $name ? qq{ ref="$ref"} : qq{};

                print qq{$i    <$element name="$name"$ref/>\n} unless
                    $imported->{$element}->{$iref};
                $imported->{$element}->{$iref} = 1;
            }
            print qq{$i  </import>\n};
        }

        if ($dataTypes) {
            foreach my $dataType (@$dataTypes) {
                my $name = $dataType->{name};
                my $base = $dataType->{base};
                my $spec = $dataType->{spec};
                # XXX nothing is done with status
                my $status = $dataType->{status};
                my $description = $dataType->{description};
                my $descact = $dataType->{descact} || 'create';
                my $minLength = $dataType->{minLength};
                my $maxLength = $dataType->{maxLength};
                my $patterns = $dataType->{patterns};

                # XXX special case here to avoid re-defining IPAddress (could
                #     be avoided by accounting for file as well as spec)
                if ($spec ne $lspec || $spec =~ /tr-106$/) {
                    print STDERR "dataType $name defined in {$file}\n" if
                        $verbose > 1;
                    next;
                }

                $description = xml_escape($description);

                $base = $base ? qq{ base="$base"} : qq{};
                $descact = $descact ne 'create' ?
                    qq{ action="$descact"} : qq{};
                $minLength = $minLength ? qq{ minLength="$minLength"} : qq{};
                $maxLength = $maxLength ? qq{ maxLength="$maxLength"} : qq{};

                print qq{$i  <dataType name="$name"$base>\n};
                print qq{$i    <description$descact>$description</description>\n} if $description;
                if ($patterns) {
                    print qq{$i    <string>\n};
                    print qq{$i      <size$minLength$maxLength/>\n} if
                        $minLength || $maxLength;
                    foreach my $pattern (@$patterns) {
                        my $value = $pattern->{value};
                        my $description = $pattern->{description};
                        my $descact = $pattern->{descact} || 'create';
                        
                        $description = xml_escape($description);

                        $descact = $descact ne 'create' ?
                            qq{ action="$descact"} : qq{};
                        
                        my $end_element = $description ? '' : '/';
                        
                        print qq{$i      <pattern value="$value"$end_element>\n};
                        print qq{$i        <description$descact>$description</description>\n} if $description;
                        print qq{$i      </pattern>\n} unless $end_element;
                    }
                    print qq{$i    </string>\n};
                }
                print qq{$i  </dataType>\n};
            }
        }

        if ($bibliography && %$bibliography) {
            xml_bibliography($bibliography, $indent, {usespec => $lspec});
        }

        $node->{xml}->{element} = 'dm:document';
    }

    # model (always at level 1)
    # XXX don't output model (or children) if its spec doesn't match of the
    #     last file on the command line
    elsif ($type eq 'model') {
        if ($spec ne $lspec) {
            print STDERR "hiding $type $path $spec $lspec\n" if $verbose > 1;
            hide_subtree($node);
            $node->{xml}->{action} = 'none';
            return;
        }

        my $base = $history && @$history ? $history->[0]->{name} : '';
        my $isService = $node->{isService};

        # XXX hackery
        $base = '_' . $base if defined $base && $base eq $name;

        $base = $base ? qq{ base="$base"} : qq{};
        $isService = $isService ? qq{ isService="true"} : qq{};

        print qq{$i<model name="$name"$base$isService$status>\n};
        print qq{$i  <description$descact>$description</description>\n} if
            $description;
    }

    # model object
    # XXX don't output object (or children) if the spec at which it last
    #     changed doesn't match that of the last file on the command line
    elsif ($type eq 'object') {
        my $ospec = $node->{lspec};
        if ($ospec ne $lspec) {
            print STDERR "hiding $type $path $ospec $lspec\n" if $verbose > 1;
            hide_subtree($node, 1); # only parameter children
            $node->{xml}->{action} = 'none' unless $indent == 2;
            return;
        }

        my $minEntries = $node->{minEntries};
        my $maxEntries = $node->{maxEntries};
        my $numEntriesParameter = $node->{numEntriesParameter};
        my $enableParameter = $node->{enableParameter};
        my $uniqueKeys = $node->{uniqueKeys};

        $numEntriesParameter = $numEntriesParameter ? qq{ numEntriesParameter="$numEntriesParameter"} : qq{};
        $enableParameter = $enableParameter ? qq{ enableParameter="$enableParameter"} : qq{};

        # always at level 2; ignore indent
        $i = '    ';

        # close object if active
        print qq{$i</object>\n} if $xml_objact;

        print qq{$i<object $basename="$path" access="$access" minEntries="$minEntries" maxEntries="$maxEntries"$numEntriesParameter$enableParameter$status>\n};
        unless ($nocomments || $node->{descact} eq 'append') {
            print qq{$i  <!-- changed: $schanged -->\n} if $schanged;
            if ($changed->{description}) {
                print qq{$i  <!--\n};
                foreach my $line (split "\n",
                                  xml_escape($changed->{description})) {
                    print qq{$i  $line\n};
                }
                print qq{$i  -->\n};
            }
        }
        print qq{$i  <description$descact>$description</description>\n} if
            ($basename eq 'name' && $description) || $changed->{description};
        # only output unique keys on first definition
        # XXX should drive this by more general "created" logic
        if ($uniqueKeys && $basename eq 'name') {
            for my $uniqueKey (@$uniqueKeys) {
                print qq{$i  <uniqueKey>\n};
                for my $parameter (@$uniqueKey) {
                    print qq{$i    <parameter ref="$parameter"/>\n};
                }
                print qq{$i  </uniqueKey>\n};
            }
        }

        $node->{xml}->{action} = 'none' unless $indent == 2;
        $xml_objact = 1;
    }

    # profile
    elsif ($type eq 'profile') {
        if ($spec ne $lspec) {
            print STDERR "hiding $type $path $spec $lspec\n" if $verbose > 1;
            hide_subtree($node);
            $node->{xml}->{action} = 'none';
            return;
        }
        print qq{$i<profile name="$name">\n};
        print qq{$i  <description$descact>$description</description>\n} if
            $description;
    }

    # profile object
    elsif ($type eq 'objectRef') {
        print qq{$i<object ref="$name" requirement="$access">\n};
        print qq{$i  <description$descact>$description</description>\n} if
            $description;
        $node->{xml}->{element} = 'object';
    }

    # profile parameter
    elsif ($type eq 'parameterRef') {
        my $ended = $description ? '' : '/';
        print qq{$i<parameter ref="$name" requirement="$access"$ended>\n};
        print qq{$i  <description$descact>$description</description>\n} unless
            $ended;
        print qq{$i</parameter>\n} unless $ended;
        $node->{xml}->{action} = 'none';
    }

    # model parameter
    else {
        my $ospec = $node->{lspec};
        if ($ospec ne $lspec) {
            print STDERR "ignoring $type $path $ospec $lspec\n" if
                $verbose > 1;
            $node->{xml}->{action} = 'none';
            return;
        }

        my $activeNotify = $node->{activeNotify};
        my $forcedInform = $node->{forcedInform};
        my $syntax = $node->{syntax};

        $activeNotify = $activeNotify ne 'normal' ? qq{ activeNotify="$activeNotify"} : qq{};
        $forcedInform = $forcedInform ? qq{ forcedInform="true"} : qq{};

        # always at level 2 or 3; ignore indent
        $i = $xml_objact ? '      ' : '    ';

        print qq{$i<parameter $basename="$name" access="$access"$status$activeNotify$forcedInform>\n};
        unless ($nocomments || $node->{descact} eq 'append') {
            print qq{$i  <!-- changed: $schanged -->\n} if $schanged;
            if ($changed->{description}) {
                print qq{$i  <!--\n};
                foreach my $line (split "\n",
                                  xml_escape($changed->{description})) {
                    print qq{$i  $line\n};
                }
                print qq{$i  -->\n};
            }
        }
        print qq{$i  <description$descact>$description</description>\n} if
            ($basename eq 'name' && $description) || $changed->{description};
        # XXX need more sophisticated "changed" processing (need it at the
        #     facet level)
        if ($syntax && ($basename eq 'name' || $changed->{syntax} ||
                        $changed->{values} || $changed->{default})) {
            my $hidden = $syntax->{hidden};
            my $base = $syntax->{base};
            my $ref = $syntax->{ref};
            my $list = $syntax->{list};
            # XXX notsupport ing multiple sizes
            my $minLength = $syntax->{sizes}->[0]->{minLength};
            my $maxLength = $syntax->{sizes}->[0]->{maxLength};
            # XXX not supporting multiple ranges
            my $minInclusive = $syntax->{ranges}->[0]->{minInclusive};
            my $maxInclusive = $syntax->{ranges}->[0]->{maxInclusive};
            my $step = $syntax->{ranges}->[0]->{step};
            my $values = $node->{values};
            my $default = $node->{default};
            my $deftype = $node->{deftype};
            my $defstat = $node->{defstat};

            $base = $base ? qq{ base="$base"} : qq{};
            $ref = $ref ? qq{ ref="$ref"} : qq{};
            $hidden = $hidden ? qq{ hidden="true"} : qq{};
            $minLength = defined $minLength && $minLength ne '' ?
                qq{ minLength="$minLength"} : qq{};
            $maxLength = defined $maxLength && $maxLength ne '' ?
                qq{ maxLength="$maxLength"} : qq{};
            $minInclusive = defined $minInclusive && $minInclusive ne '' ?
                qq{ minInclusive="$minInclusive"} : qq{};
            $maxInclusive = defined $maxInclusive && $maxInclusive ne '' ?
                qq{ maxInclusive="$maxInclusive"} : qq{};
            $step = defined $step && $step ne '' ? qq{ step="$step"} : qq{};
            $defstat = $defstat ne 'current' ? qq{ status="$defstat"} : qq{};

            print qq{$i  <syntax$hidden>\n};
            if ($list) {
                my $ended = ($minLength || $maxLength) ? '' : '/';
                print qq{$i    <list$ended>\n};
                print qq{$i      <size$minLength$maxLength/>\n} unless $ended;
                print qq{$i    </list>\n} unless $ended;
                $minLength = $maxLength = undef;
            }
            my $ended = ($minLength || $maxLength || $minInclusive ||
                         $maxInclusive || $step || %$values) ? '' : '/';
            print qq{$i    <$type$ref$base$ended>\n};
            print qq{$i      <size$minLength$maxLength/>\n} if
                $minLength || $maxLength;
            print qq{$i      <range$minInclusive$maxInclusive$step/>\n} if
                $minInclusive || $maxInclusive || $step;
            foreach my $value (sort {$values->{$a}->{i} <=>
                                     $values->{$b}->{i}} keys %$values) {
                my $evalue = xml_escape($value);
                my $cvalue = $values->{$value};

                my $history = $cvalue->{history};
                my $access = $cvalue->{access};
                my $status = $cvalue->{status};
                my $optional = boolean($cvalue->{optional});
                my $description = $cvalue->{description};
                my $descact = $cvalue->{descact};

                # XXX have no history on values (values should be nodes?)
                ($description, $descact) = get_description($description,
                                                           $descact, $history);
                $description = xml_escape($description);

                $optional = $optional ? qq{ optional="true"} : qq{};
                $access = $access ne 'readOnly' ? qq{ access="$access"} : qq{};
                $status = $status ne 'current' ? qq{ status="$status"} : qq{};
                $descact = $descact ne 'create' ? qq{ action="$descact"} : qq{};
                my $ended = $description ? '' : '/';

                print qq{$i      <enumeration value="$evalue"$access$status$optional$ended>\n};
                print qq{$i        <description$descact>$description</description>\n} if $description;
                print qq{$i      </enumeration>\n} unless $ended;
            }
            print qq{$i    </$type>\n} unless $ended;
            print qq{$i    <default type="$deftype" value="$default"$defstat/>\n}
            if defined $default && ($basename eq 'name' ||
                                    $changed->{default});
            print qq{$i  </syntax>\n};
        }
        print qq{$i</parameter>\n};
        $node->{xml}->{action} = 'none';
    }
}

sub xml_bibliography
{
    my ($bibliography, $indent, $opts) = @_;

    $indent = 0 unless $indent;
    my $i = "  " x $indent;

    my $usespec = $opts->{usespec};
    my $ignspec = $opts->{ignspec};

    my $description = $bibliography->{description};
    my $descact = $bibliography->{descact} || 'create';
    my $references = $bibliography->{references};
    
    $descact = $descact ne 'create' ? qq{ action="$descact"} : qq{};
    
    print qq{$i  <bibliography>\n};
    print qq{$i    <description$descact>$description</description>\n}
    if $description;
    
    foreach my $reference (sort {$a->{id} cmp $b->{id}} @$references) {
        my $id = $reference->{id};
        my $file = $reference->{file};
        my $spec = $reference->{spec};
        
        # ignore if outputting entries from specified spec (usespec) but this
        # comes from another spec
        if ($usespec && $spec ne $usespec) {
            print STDERR "$file: ignoring {$spec}$id\n" if $verbose > 1;
            next;
        }

        # ignore if ignoring entries from specified spec (ignspec) and this
        # comes from that spec
        if ($ignspec && $spec eq $ignspec) {
            print STDERR "$file: ignoring {$spec}$id\n" if $verbose > 1;
            next;
        }
        
        # XXX this can include unused references (I think because these 
        #     are bibrefs for all read data models, not for reported data
        #     models
        if (!$bibrefs->{$id}) {
            # XXX dangerous to omit it since it might be defined here
            #     in order to make it available to later versions
            # XXX for now, have hard-list of things not to omit
            # XXX hack to remove exceptions for xml2 report
            my $omit = ($id !~ /TR-069|TR-106/);
            $omit = 0 if $report eq 'xml2';
            if ($omit) {
                print STDERR "reference $id not used (omitted)\n";
                next;
            }
        }
        
        print qq{$i    <reference id="$id">\n};
        foreach my $element (qw{name title organization category
                                            date hyperlink}) {
            my $value = xml_escape($reference->{$element});
            print qq{$i      <$element>$value</$element>\n} if $value;
        }
        print qq{$i    </reference>\n};
    }
    print qq{$i  </bibliography>\n};
}

# XXX could use postpar as is done for the xml2 report
sub xml_post
{
    my ($node, $indent) = @_;

    my $i = "  " x $indent;

    my $xml = $node->{xml};
    my $action = $xml->{action};
    my $element = $xml->{element};
    
    if ($action eq 'close') {
        print qq{$i</$element>\n};
        $xml_objact = 0 if $element eq 'object';
    }
}

# Escape a value suitably for exporting as XML.
sub xml_escape {
    my ($value) = @_;

    $value = util_default($value, '', '');

    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    return $value;
}

# Form a string indicating what has changed
sub xml_changed
{
    my ($changed) = @_;

    return '' unless $changed;

    my $value = '';
    foreach my $key (sort keys %$changed) {
        $value .= ', ' if $value;
        $value .= $key;
        if (ref $changed->{$key}) {
            $value .= '(' . xml_changed($changed->{$key}) . ')';
        }
    }

    return $value;
}

# XML report of node (alternative form that generates something that should
# be similar to, and can be compared with, XML generated from an old-style
# Word table, e.g. from TR-098 Amendment 2)
#
# XXX doesn't do a complete job
# XXX this COULD be merged with the other XML report... I suppose...
# XXX better now, but: (a) need header comment, (b) need any undefined
#     bibrefs, (c) various other little things showed up by the 181 XML

sub xml2_node
{
    my ($node, $indent) = @_;

    $indent = 0 unless $indent;

    my $type = $node->{type};
    my $element = $type;
    $node->{xml2}->{element} = $element;

    my $i = "  " x $indent;

    # use indent as a first-time flag
    if (!$indent) {
        my $dm = $node->{dm};
        my $dmr = $node->{dmr};
        my $dmspec = $lspec;
        my $xsi = $node->{xsi};
        my $schemaLocation = $node->{schemaLocation};
        my $specattr = 'spec';

        my $history = $node->{history};
        my $description = $node->{description};
        my $descact = $node->{descact};
        ($description, $descact) = get_description($description, $descact,
                                                   $history, 1);
        $description = clean_description($description, $node->{name})
            if $canonical;
        $description = xml_escape($description);        

        # XXX have to hard-code DT stuff (can't get this from input files)
        my $d = @$dtprofiles ? qq{dt} : qq{dm};
        if ($d eq 'dt') {
            $dm = $dturn;
            $dmspec = $dtspec;
            $schemaLocation =~
                s/urn:broadband-forum-org:cwmp:datamodel.*?\.xsd ?//;
            $schemaLocation = qq{$dturn $dtloc $schemaLocation};
            $specattr = 'deviceType';
        }

        $element = qq{$d:document};
        $node->{xml2}->{element} = $element;
        print qq{$i<?xml version="1.0" encoding="UTF-8"?>
$i<!-- \$Id\$ -->
$i<!-- note: this is an automatically generated XML report -->
$i<$d:document xmlns:$d="$dm"
$i             xmlns:dmr="$dmr"
$i             xmlns:xsi="$xsi"
$i             xsi:schemaLocation="$schemaLocation"
$i             $specattr="$dmspec">
};
        print qq{$i  <description>$description</description>\n} if $description;
        # XXX for now hard-code bibliography and data type imports for DM
        if (!@$dtprofiles) {
            print qq{$i  <import file="tr-069-biblio.xml" spec="urn:broadband-forum-org:tr-069-biblio"/>
$i  <import file="tr-106-1-0-types.xml" spec="urn:broadband-forum-org:tr-106-1-0">
$i    <dataType name="IPAddress"/>
$i    <dataType name="MACAddress"/>
$i  </import>
};

            my $bibliography = $node->{bibliography};
            if ($bibliography && %$bibliography) {
                xml_bibliography(
                    $bibliography, $indent,
                    {ignspec => 'urn:broadband-forum-org:tr-069-biblio'});
            }
        } else {
            my $temp = util_list($dtprofiles);
            print qq{$i  <annotation>Auto-generated from $temp profiles.</annotation>\n};
            # XXX special case code from xml_node (could generalize)
            my $limports = $imports->{$lfile};
            print qq{$i  <import file="$lfile.xml" spec="$lspec">\n};        
            foreach my $import (@{$limports->{imports}}) {
                my $element = $import->{element};
                my $name = $import->{name};
                my $file = $import->{file};
                
                print qq{$i    <$element name="$name"/>\n} if
                    $file eq $lfile && $element eq 'model' && $name !~ /^_/;
            }
            print qq{$i  </import>\n};
        }
    }

    if ($indent) {
        my $history = $node->{history};
        my $path = $node->{path};
        my $name = $type eq 'object' ? $path : $node->{name};
        my $base = $node->{base};
        my $ref = $node->{ref};
        my $access = $node->{access};
        my $numEntriesParameter = $node->{numEntriesParameter};
        my $enableParameter = $node->{enableParameter};
        my $status = $node->{status};
        my $activeNotify = $node->{activeNotify};
        my $forcedInform = $node->{forcedInform};
        my $minEntries = $node->{minEntries};
        my $maxEntries = $node->{maxEntries};
        my $description = $node->{description};
        my $descact = $node->{descact};
        my $uniqueKeys = $node->{uniqueKeys};
        my $syntax = $node->{syntax};
        my $majorVersion = $node->{majorVersion};
        my $minorVersion = $node->{minorVersion};
        my $extends = $node->{extends};

        my $requirement = '';
        my $version = version($majorVersion, $minorVersion);

        if ($element eq 'model') {
            $version = '';
            if (@$dtprofiles) {
                $ref = $name;
                $name = '';
            }
            return if $components;
        } elsif ($element eq 'object') {
            $i = '    ';
            if ($components) {
                my $cname = $name;
                $cname =~ s/\{i\}/i/g;
                $cname =~ s/\./_/g;
                $cname =~ s/_$//;
                $cname =~ s/$/_params/ if $noobjects;
                $name =~ s/\.\{i\}/\{i\}/g;
                $name =~ s/.*\.([^\.]+\.)$/$1/;
                $name =~ s/\{i\}/\.\{i\}/g;
                print qq{  <component name="$cname">\n};
            }
            if (@$dtprofiles) {
                $access = object_requirement($dtprofiles, $path);
                # XXX this is risky because it assumes that there will be
                #     no parameters; mark the element empty so it won't be
                #     closed (also see below for parameter check)
                if (!$access) {
                    $node->{xml2}->{element} = '';
                    return;
                }
                $ref = $name;
                $name = '';
                $numEntriesParameter = undef;
                $enableParameter = undef;
                $description = '';
                $descact = 'replace';
            }
        } elsif ($syntax) {
            $i = $node->{pnode}->{type} eq 'object' ? '      ' : '    ';
            $element = 'parameter';
            $node->{xml2}->{element} = $element;
            if (@$dtprofiles) {
                $access = parameter_requirement($dtprofiles, $path);
                # XXX see above for how element can be empty
                if ($node->{pnode}->{xml2}->{element} eq '') {
                    print STDERR "$path: ignoring because parent not in ".
                        "profile\n" if $verbose > 1;
                    return;
                }
                if (!$access) {
                    return;
                }
                $ref = $name;
                $name = '';
                # XXX proposal:
                $activeNotify =
                    $activeNotify eq 'canDeny' ? 'willDeny' : 'normal';
                $status = 'current';
                $forcedInform = 0;
                $description = '';
                $descact = 'replace';
                $syntax = undef;
            }
        } elsif ($element =~ /(\w+)Ref/) {
            $ref = $name;
            $name = '';
            $requirement = $access;
            $access = '';
            $element = $1; # parameter or object
            $node->{xml2}->{element} = ($element eq 'object') ? $element : '';
        }

        $name = $name ? qq{ name="$name"} : qq{};
        $base = $base ? qq{ base="$base"} : qq{};
        $ref = $ref ? qq{ ref="$ref"} : qq{};
        $access = $access ? qq{ access="$access"} : qq{};
        $numEntriesParameter = $numEntriesParameter ? qq{ numEntriesParameter="$numEntriesParameter"} : qq{};
        $enableParameter = $enableParameter ? qq{ enableParameter="$enableParameter"} : qq{};
        $status = $status ne 'current' ? qq{ status="$status"} : qq{};
        $activeNotify = (defined $activeNotify && $activeNotify ne 'normal') ?
            qq{ activeNotify="$activeNotify"} : qq{};
        $forcedInform = $forcedInform ? qq{ forcedInform="true"} : qq{};
        $requirement = $requirement ? qq{ requirement="$requirement"} : qq{};
        $minEntries = defined $minEntries ?
            qq{ minEntries="$minEntries"} : qq{};
        $maxEntries = defined $maxEntries ?
            qq{ maxEntries="$maxEntries"} : qq{};
        $base = $extends ? qq{ extends="$extends"} : qq{};

        $version = $version ? qq{ dmr:version="$version"} : qq{};

        ($description, $descact) = get_description($description, $descact,
                                                   $history, 1);
        $description = clean_description($description, $node->{name})
            if $canonical;
        $description = xml_escape($description);

        my $end_element = (@{$node->{nodes}} || $description || $syntax) ? '' : '/';
        print qq{$i<!--\n} if $element eq 'object' && $noobjects;
        print qq{$i<$element$name$base$ref$access$numEntriesParameter$enableParameter$status$activeNotify$forcedInform$requirement$minEntries$maxEntries$version$end_element>\n};
        $node->{xml2}->{element} = '' if $end_element;
        print qq{$i  <description>$description</description>\n} if
            $description;
        if ($uniqueKeys && !@$dtprofiles) {
            foreach my $uniqueKey (@$uniqueKeys) {
                print qq{$i  <uniqueKey>\n};
                foreach my $parameter (@$uniqueKey) {
                    print qq{$i    <parameter ref="$parameter"/>\n};
                }
                print qq{$i  </uniqueKey>\n};
            }
        }
        print qq{$i-->\n} if $element eq 'object' && $noobjects;

        # XXX this is almost verbatim from xml_node
        if ($syntax) {
            my $hidden = $syntax->{hidden};
            my $base = $syntax->{base};
            my $ref = $syntax->{ref};
            my $list = $syntax->{list};
            # XXX not supporting multiple sizes
            my $minListLength = $syntax->{listSizes}->[0]->{minLength};
            my $maxListLength = $syntax->{listSizes}->[0]->{maxLength};
            my $minLength = $syntax->{sizes}->[0]->{minLength};
            my $maxLength = $syntax->{sizes}->[0]->{maxLength};
            # XXX not supporting multiple ranges
            my $minListItems = $syntax->{listRanges}->[0]->{minInclusive};
            my $maxListItems = $syntax->{listRanges}->[0]->{maxInclusive};
            my $minInclusive = $syntax->{ranges}->[0]->{minInclusive};
            my $maxInclusive = $syntax->{ranges}->[0]->{maxInclusive};
            my $step = $syntax->{ranges}->[0]->{step};
            my $values = $node->{values};
            my $units = $node->{units};
            my $default = $node->{default};
            my $deftype = $node->{deftype};
            my $defstat = $node->{defstat};

            # XXX a bit of a kludge...
            $type = 'dataType' if $ref;

            $base = $base ? qq{ base="$base"} : qq{};
            $ref = $ref ? qq{ ref="$ref"} : qq{};
            $hidden = $hidden ? qq{ hidden="true"} : qq{};
            $minListLength = defined $minListLength && $minListLength ne '' ?
                qq{ minLength="$minListLength"} : qq{};
            $maxListLength = defined $maxListLength && $maxListLength ne '' ?
                qq{ maxLength="$maxListLength"} : qq{};
            $minLength = defined $minLength && $minLength ne '' ?
                qq{ minLength="$minLength"} : qq{};
            $maxLength = defined $maxLength && $maxLength ne '' ?
                qq{ maxLength="$maxLength"} : qq{};
            $minListItems = defined $minListItems && $minListItems ne '' ?
                qq{ minItems="$minListItems"} : qq{};
            $maxListItems = defined $maxListItems && $maxListItems ne '' ?
                qq{ maxItems="$maxListItems"} : qq{};
            $minInclusive = defined $minInclusive && $minInclusive ne '' ?
                qq{ minInclusive="$minInclusive"} : qq{};
            $maxInclusive = defined $maxInclusive && $maxInclusive ne '' ?
                qq{ maxInclusive="$maxInclusive"} : qq{};
            $step = defined $step && $step ne '' ? qq{ step="$step"} : qq{};
            $defstat = $defstat ne 'current' ? qq{ status="$defstat"} : qq{};

            my $reference = $syntax->{reference};

            # pathRef and instanceRef
            my $refType = $syntax->{refType};
            my $targetParent = $syntax->{targetParent};
            my $targetParentScope = $syntax->{targetParentScope};

            # instanceRef
            my $targetType = $syntax->{targetType};
            my $targetDataType = $syntax->{targetDataType};

            # enumerationRef
            my $targetParam = $syntax->{targetParam};
            my $targetParamScope = $syntax->{targetParamScope};
            my $nullValue = $syntax->{nullValue};

            $refType = $refType ? qq{ refType="$refType"} : qq{};
            $targetParent = $targetParent ?
                qq{ targetParent="$targetParent"} : qq{};
            $targetParentScope = $targetParentScope ?
                qq{ targetParentScope="$targetParentScope"} : qq{};
            $targetType = $targetType ? qq{ targetType="$targetType"} : qq{};
            $targetDataType = $targetDataType ?
                qq{ targetDataType="$targetDataType"} : qq{};
            $targetParam = $targetParam ?
                qq{ targetParam="$targetParam"} : qq{};
            $targetParamScope = $targetParamScope ?
                qq{ targetParamScope="$targetParamScope"} : qq{};            
            $nullValue = defined $nullValue ?
                qq{ nullValue="$nullValue"} : qq{};

            print qq{$i  <syntax$hidden>\n};
            if ($list) {
                my $ended = ($minListLength || $maxListLength ||
                             $minListItems || $maxListItems) ? '' : '/';
                print qq{$i    <list$minListItems$maxListItems$ended>\n};
                print qq{$i      <size$minListLength$maxListLength/>\n} unless
                    $ended;
                print qq{$i    </list>\n} unless $ended;
            }
            my $ended = ($minLength || $maxLength || $minInclusive ||
                         $maxInclusive || $step || $reference || %$values ||
                         $units) ? '' : '/';
            print qq{$i    <$type$ref$base$ended>\n};
            print qq{$i      <size$minLength$maxLength/>\n} if
                $minLength || $maxLength;
            print qq{$i      <range$minInclusive$maxInclusive$step/>\n} if
                $minInclusive || $maxInclusive || $step;
            print qq{$i      <$reference$refType$targetParam$targetParent$targetParamScope$targetParentScope$targetType$targetDataType$nullValue/>\n} if $reference;
            foreach my $value (sort {$values->{$a}->{i} <=>
                                     $values->{$b}->{i}} keys %$values) {
                my $evalue = xml_escape($value);
                my $cvalue = $values->{$value};

                my $facet = $cvalue->{facet};
                my $history = $cvalue->{history};
                my $access = $cvalue->{access};
                my $status = $cvalue->{status};
                my $optional = boolean($cvalue->{optional});
                my $description = $cvalue->{description};
                my $descact = $cvalue->{descact};

                # XXX have no history on values (values should be nodes?)
                ($description, $descact) =
                    get_description($description, $descact, $history, 1);
                $description = clean_description($description, $node->{name})
                    if $canonical;
                $description = xml_escape($description);

                $optional = $optional ? qq{ optional="true"} : qq{};
                $access = $access ne 'readOnly' ? qq{ access="$access"} : qq{};
                $status = $status ne 'current' ? qq{ status="$status"} : qq{};
                my $ended = $description ? '' : '/';

                print qq{$i      <$facet value="$evalue"$access$status$optional$ended>\n};
                print qq{$i        <description>$description</description>\n} if $description;
                print qq{$i      </$facet>\n} unless $ended;
            }
            print qq{$i      <units value="$units"/>\n} if $units;
            print qq{$i    </$type>\n} unless $ended;
            print qq{$i    <default type="$deftype" value="$default"$defstat/>\n}
            if defined $default;
            print qq{$i  </syntax>\n};
            print qq{$i</parameter>\n};
            $node->{xml2}->{element} = '';
        }
    }
}

# this is called (for objects and objectRefs only) after all parameters
sub xml2_postpar
{
    my ($node) = @_;

    my $element = $node->{xml2}->{element};
    return if !$element;

    # XXX wrong for profiles?
    my $i = $node->{type} eq 'object' ? '    ' : '      ';;

    print qq{$i<!--\n} if $noobjects;
    print qq{$i</object>\n};
    print qq{$i-->\n} if $noobjects;
    if ($components) {
        print qq{  </component>\n};
    }
}

# this is used only to close elements other than object and objectRef (unless
# already closed)
sub xml2_post
{
    my ($node, $indent) = @_;

    my $element = $node->{xml2}->{element};
    return if !$element || $element eq 'object';

    $indent = 0 unless $indent;
    return if $node->{name} eq 'object';

    # XXX this is a hack (I hate this logic)
    return if @$dtprofiles && $element eq 'parameter';
    
    # XXX this catches model
    return if $components && $indent > 0;

    my $i = "  " x $indent;
    print qq{$i</$element>\n};
}

# Determine maximum requirement for a given object across a set of profiles
sub object_requirement
{
    my ($dtprofiles, $path) = @_;

    my $maxreq = 0;
    foreach my $dtprofile (@$dtprofiles) {
        my $req = $profiles->{$dtprofile}->{$path};
        next unless $req;

        $req = {notSpecified => 1, present => 2, create => 3, delete => 4,
                createDelete => 5}->{$req};
        $maxreq = $req if $req > $maxreq;
    }

    # XXX special case, force "present" for "Device." and
    #     "InternetGatewayDevice."
    $maxreq = 2 if !$maxreq && $path =~ /^(InternetGateway)?Device\.$/;

    # XXX treat "notSpecified" as readOnly, since a profile definition can
    #     say "notSpecified" for an object and then reference its parameters
    $maxreq = {0 => '', 1 => 'readOnly', 2 => 'readOnly', 3 => 'create',
               4 => 'delete', 5 => 'createDelete'}->{$maxreq};

    return $maxreq;
}

# Determine maximum requirement for a given parameter across a set of profiles
sub parameter_requirement
{
    my ($dtprofiles, $path) = @_;

    my $maxreq = 0;
    foreach my $dtprofile (@$dtprofiles) {
        my $req = $profiles->{$dtprofile}->{$path};
        next unless $req;

        $req = {readOnly => 1, readWrite => 2}->{$req};
        $maxreq = $req if $req > $maxreq;
    }

    $maxreq = {0 => '', 1 => 'readOnly', 2 => 'readWrite'}->{$maxreq};

    return $maxreq;
}

# Heuristic changes to description to get rid of formatting etc and increase
# chances that description strings will compare as equal.
# XXX some of these things should be done on initial Word conversion...
sub clean_description
{
    my ($description, $name) = @_;

    return '' unless $description;

    $description =~ s/\{i\}/\[\[i\]\]/g;
    $description =~ s/\s*Comma-separated list of the following enumeration://;
    $description =~ s/\s*Comma separated list of the following enumeration://;
    $description =~ s/\s*Each element of the list is an enumeration of://;
    $description =~ s/\s*Each element in the list is one of://;
    $description =~ s/\s*Each entry in the list is an enumeration of://;
    $description =~ s/\s*Each item in the list is an enumeration of://;
    $description =~ s/\s*Each item is an enumeration of://;
    $description =~ s/\s*Enumeration of://;
    $description =~ s/\s*One of://;
    $description =~ s/\ban empty string\b/\{\{empty\}\}/ig;
    $description =~ s/\ban empty value\b/\{\{empty\}\}/ig;
    $description =~ s/\bnon-empty\b/not \{\{empty\}\}/ig;
    $description =~ s/\bnon empty\b/not \{\{empty\}\}/ig;
    $description =~ s/\bleft empty\b/\{\{empty\}\}/ig;
    $description =~ s/\bempty\b/\{\{empty\}\}/ig;
    $description =~ s/\bfalse\b/\{\{false\}\}/ig;
    $description =~ s/\btrue\b/\{\{true\}\}/ig;
    $description =~ s/\n[:\#\*] /\n/g;
    $description =~ s/\n\d+[:\.] /\n/g;
    $description =~
        s/\{\{(enum|pattern|object|param)\|([^\|\}]*)[^\}]*\}\}/$2/g;
    $description =~ s/\{\{(param|object)\}\}/$name/g;
    $description =~ s/ *\n({{enum|pattern}})/  $1/;
    $description =~ s/[\`\'\"]//g;
    $description =~ s/\{\{\{\{/\{\{/g;
    $description =~ s/\}\}\}\}/\}\}/g;
    $description =~ s/\[\[i\]\]/\{i\}/g;

    return $description;
}

# compare by bibid (designed to be used with sort)
sub bibid_cmp
{
    # try to split into string prefix, numeric middle, and string suffix;
    # sort alphabetically on the prefix, numerically on the middle, and
    # alphabetically on the suffic (gives correct ordering in many common
    # cases, e.g. "RFC1234" -> {RFC, 1234,} and TR-069a2 -> {TR-, 069, a2}.

    my ($ap, $am, $as) = ($a->{id} =~ /(.*?)(\d*)([iac]?\d*)$/);
    my ($bp, $bm, $bs) = ($b->{id} =~ /(.*?)(\d*)([iac]?\d*)$/);

    # XXX does an empty string compare as numeric zero?  if not, need to
    #     check for this case

    #print STDERR "a: $a->{id} $ap $am $as\n";
    #print STDERR "b: $b->{id} $bp $bm $bs\n";

    if ($ap ne $bp) {
        return ($ap cmp $bp);
    } elsif ($am != $bm) {
        return ($am <=> $bm);
    } else {
        return ($as cmp $bs);
    }
}

# HTML report of node.
# XXX using the "here" strings makes this very hard to read, and throws off
#     emacs indentation; best avoided...
# XXX need to ensure that targets are unique within the document, so often
#     need to include the data model name (also need to clean the strings)
my $html_buffer = '';
my $html_parameters = [];
my $html_profile_active = 0;

sub html_node
{
    my ($node, $indent) = @_;

    # table options
    #my $tabopts = qq{border="1" cellpadding="2" cellspacing="2"};
    my $tabopts = qq{border="1" cellpadding="2" cellspacing="0"};

    # styles
    my $table = qq{text-align: left;};
    my $row = qq{vertical-align: top;};
    my $center = qq{text-align: center;};

    # font
    my $h1font = qq{font-family: helvetica,arial,sans-serif; font-size: 14pt;};
    my $h2font = qq{font-family: helvetica,arial,sans-serif; font-size: 12pt;};
    my $h3font = qq{font-family: helvetica,arial,sans-serif; font-size: 10pt;};
    my $font = qq{font-family: helvetica,arial,sans-serif; font-size: 8pt;};

    # others
    my $object_bg = qq{background-color: rgb(255, 255, 153);};
    my $theader_bg = qq{background-color: rgb(153, 153, 153);};

    # foo_oc (open comment) and foo_cc (close comment) control generation of
    # optional columns, e.g. the syntax column when generating ugly output
    my $synt_oc =  $showsyntax ? '' : '<!-- ';
    my $synt_cc =  $showsyntax ? '' : ' -->';
    my $vers_oc = !$showspec   ? '' : '<!-- ';
    my $vers_cc = !$showspec   ? '' : ' -->';
    my $spec_oc =  $showspec   ? '' : '<!-- ';
    my $spec_cc =  $showspec   ? '' : ' -->';

    # common processing for all nodes
    my $model = ($node->{type} =~ /model/);
    my $object = ($node->{type} =~ /object/);
    my $profile = ($node->{type} =~ /profile/);
    my $parameter = $node->{syntax}; # pretty safe? not profile params...

    my $history = $node->{history};
    my $description = $node->{description};
    my $descact = $node->{descact};
    ($description, $descact) = get_description($description, $descact,
                                               $history, 1);
    # XXX pass these through html_escape so as get UPnP DM translations
    my $path = html_escape($node->{path}, {empty => ''});
    my $name = html_escape($node->{name}, {empty => ''});
    my $ppath = html_escape($node->{pnode}->{path}, {empty => ''});
    my $pname = html_escape($node->{pnode}->{name}, {empty => ''});
    # XXX don't need to pass hidden, list, reference etc (are in syntax)
    #     but does no harm (now passing node too!) :(
    my $factory = ($node->{deftype} && $node->{deftype} eq 'factory') ?
        html_escape(util_default($node->{default})) : undef;
    $description =
        html_escape($description,
                    {default => '', empty => '',
                     node => $node,
                     path => $path,
                     model => $profile ? $node->{pnode}->{name} : '',
                     param => $parameter ? $name : '',
                     object => $parameter ? $ppath : $object ? $path : undef,
                     profile => $profile ? $name : '',
                     access => $node->{access},
                     type => $node->{type},
                     syntax => $node->{syntax},
                     list => $node->{syntax}->{list},
                     hidden => $node->{syntax}->{hidden},
                     factory => $factory,
                     reference => $node->{syntax}->{reference},
                     uniqueKeys => $node->{uniqueKeys},
                     enableParameter => $node->{enableParameter},
                     values => $node->{values},
                     units => $node->{units},
                     nbsp => $object || $parameter});

    # use indent as a first-time flag
    if (!$indent) {
	my $title = "$node->{spec}";
	$title .= " ($objpat)" if $objpat ne '';
	print <<END;
<html>
  <head>
    <meta content="text/html; charset=UTF-8" http-equiv="content-type">
    <title>$title</title>
    <style type="text/css">
      p, li, body { $font }
      h1 { $h1font }
      h2 { $h2font }
      h3 { $h3font }
      table { $table }
      th { $row $font }
      th.c { $row $font $center }
      th.g { $row $font $theader_bg }
      th.gc { $row $font $theader_bg $center }
      td.o { $row $font $object_bg }
      td, td.p { $row $font }
      td.oc { $row $font $object_bg $center }
      td.pc { $row $font $center }
    </style>
  </head>
  <body>
END
        if ($description) {
            print <<END;
    <h1>Summary</h1>
    $description
END
        }
        print <<END;
    <h1>Table of Contents</h1>
    <ul> <!-- Table of Contents -->
END
        $html_buffer .= <<END;
    </ul> <!-- Table of Contents -->
END
        my $datatypes = $node->{dataTypes};
        if ($autodatatype && $datatypes && @$datatypes) {
            #print STDERR Dumper($datatypes);
            print <<END;
      <li><a href="#DataTypes">Data Types</a></li>
END
            $html_buffer .= <<END;
    <h1><a name="DataTypes">Data Types</a></li>
    <table border="0"> <!-- Data Types -->
END
            foreach my $datatype (sort {$a->{name} cmp $b->{name}}
                                  @$datatypes) {
                my $name = $datatype->{name};
                my $description = $datatype->{description};
                my $descact = $datatype->{descact};

                $name = qq{<a name="$name">$name</a>};

                # XXX this needs a generic utility that will escape any
                #     description with full template expansion
                # XXX more generally, a data type report should be quite like
                #     a parameter report (c.f. UPnP relatedStateVariable)
                $description = html_escape($description);

                $html_buffer .= <<END;
      <tr>
        <td>$name</td>
        <td>$description</td>
      </tr>
END
            }
            $html_buffer .= <<END;
    </table> <!-- Data Types -->
END
        }
        my $bibliography = $node->{bibliography};
        if ($bibliography && %$bibliography) {
            print <<END;
      <li><a href="#References">References</a></li>
END
            $html_buffer .= <<END;
    <h1><a name="References">References</a></h1>
    <table border="0"> <!-- References -->
END
            my $references = $bibliography->{references};
            foreach my $reference (sort bibid_cmp @$references) {
                my $id = $reference->{id};
                next unless $bibrefs->{$id};
                # XXX this works for lastonly but doesn't work when hiding
                #     sub-trees (would like hide_subtree and unhide_subtree
                #     to auto-hide and show relevant references)
                next if $lastonly && !grep {$_ eq $lspec} @{$bibrefs->{$id}};
                
                my $name = xml_escape($reference->{name});
                my $title = xml_escape($reference->{title});
                my $organization = xml_escape($reference->{organization});
                my $category = xml_escape($reference->{category});
                my $date = xml_escape($reference->{date});
                my $hyperlink = xml_escape($reference->{hyperlink});

                my $hid = $hyperlink ? qq{<a href="$hyperlink">$id</a>} : $id;
                $id = qq{<a name="$id">[$hid]</a>};
                
                $title = $title ? qq{, <em>$title</em>} : qq{};
                $organization = $organization ? qq{, $organization} : qq{};
                # XXX category is no longer used
                $category = $category ? qq{ $category} : qq{};
                $date = $date ? qq{, $date} : qq{};
                $hyperlink = $hyperlink ?
                    qq{, <a href="$hyperlink">$hyperlink</a>} : qq{};
                
                $html_buffer .= <<END;
      <tr>
        <td>$id</td>
        <td>$name$title$organization$date.</td>
      </tr>
END
            }
            $html_buffer .= <<END;
    </table> <!-- References -->
END
        }
    }

    if ($indent) {
        if ($upnpdm && !$object && $node->{pnode}->{type} &&
            $node->{pnode}->{type} eq 'model') {
            print STDERR "$path: ignoring top-level parameter\n" if $verbose;
            return;
        }

        # XXX want an option to show them in strikeout
        # XXX this is inefficient; should do to the tree after parsing all
        #     files and before generating the report (c.f. hide_subtree)
        if (util_is_deleted($node)) {
            print STDERR "$path: ignoring because deleted\n" if $verbose;
            return;
        }

        # XXX there's some double escaping going on here...
	my $name = html_escape($object ? $path : $node->{name},
                               {empty => '', fudge => 1});
        my $base = html_escape($node->{base}, {default => '', empty => ''});
	my $type = html_escape(type_string($node->{type}, $node->{syntax}),
			       {fudge => 1});
	my $syntax = html_escape(syntax_string($node->{type}, $node->{syntax}),
                                 {fudge => 1});
        # XXX need to handle access / requirement more generally
        my $access = html_escape($node->{access});
	my $write =
            $access eq 'readWrite' ? 'W' :
            $access eq 'present' ? 'P' :
            $access eq 'create' ? 'A' :
            $access eq 'delete' ? 'D' :
            $access eq 'createDelete' ? 'C' : '-';

        my $default = $node->{default};
        undef $default
            if defined $node->{deftype} && $node->{deftype} ne 'object';
        undef $default
            if defined $node->{defstat} && $node->{defstat} eq 'deleted';
	$default = html_escape($default,
                               {quote => scalar($type =~ /^string/),
                                hyphenate => 1});
        # XXX just version isn't sufficient; might need also to show model
        #     name, since "1.0" could be "Device:1.0" or "X_EXAMPLE_Device:1.0"
	my $version =
	    html_escape(version($node->{majorVersion}, $node->{minorVersion}));

        # XXX the above is addressed by $showspec and the use of a cleaned-up
        #     version of the spec
        # XXX doing this for every item is inefficient...
        my $lspecs = util_history_values($node, 'lspec');
        my $specs = '';
        # XXX specs will be wrong if this XML was generated by the xml2 report
        #     (it will just be the last spec); however, it isn't output by
        #     default, so don't worry about this at the moment
        foreach my $lspec (@$lspecs) {
            $specs .= ' ' if $specs;
            $specs .= util_doc_name($lspec) if defined $lspec;
        }

	my $class = ($model | $object | $profile) ? 'o' : 'p';

        if ($model) {
            my $title = qq{$name Data Model};
            print <<END;
      <li><a href="#$title">$title</a></li>
      <ul> <!-- $title -->
        <li><a href="#$title">Data Model Definition</a></li>
        <ul> <!-- Data Model Definition -->
END
            my $boiler_plate = '';
            $boiler_plate = <<END if $node->{minorVersion};
For a given implementation of this data model, the CPE MUST indicate
support for the highest version number of any object or parameter that
it supports.  For example, even if the CPE supports only a single
parameter that was introduced in version $version, then it will indicate
support for version $version.  The version number associated with each object
and parameter is shown in the <b>Version</b> column.<p>
END
            $html_buffer .= <<END;
    <h1><a name="$title">$title</a></h1>
    $description<p>$boiler_plate
    <table width="100%" $tabopts> <!-- Data Model Definition -->
      <tbody>
        <tr>
          <th width="10%">Name</th>
          <th width="10%">Type</th>
          $synt_oc<th>Syntax</th>$synt_cc
          <th width="10%" class="c">Write</th>
          <th width="50%">Description</th>
          <th width="10%" class="c">Object Default</th>
          $vers_oc<th width="10%" class="c">Version</th>$vers_cc
          $spec_oc<th class="c">Spec</th>$spec_cc
	</tr>
END
            $html_parameters = [];
            $html_profile_active = 0;
        }

        if ($parameter) {
            push @$html_parameters, $node;
        }

        # XXX so only outputting these tables if there are profiles... BAD!
        if ($profile) {
            if (!$html_profile_active) {
                print <<END;
        </ul> <!-- Data Model Definition -->
        <li><a href="#Inform and Notification Requirements">Inform and Notification Requirements</a></li>
        <ul> <!-- Inform and Notification Requirements -->
END
                $html_buffer .= <<END;
      </tbody>
    </table> <!-- Data Model Definition -->
    <h2><a name="Inform and Notification Requirements">Inform and Notification Requirements</a></h2>
END
                $html_buffer .=
                html_param_table(qq{Forced Inform Parameters},
                                 {tabopts => $tabopts},
                                 grep {$_->{forcedInform}} @$html_parameters) .
                html_param_table(qq{Forced Active Notification Parameters},
                                 {tabopts => $tabopts},
                                 grep {$_->{activeNotify} eq 'forceEnabled'}
                                 @$html_parameters) .
                html_param_table(qq{Default Active Notification Parameters},
                                 {tabopts => $tabopts},
                                 grep {$_->{activeNotify} eq
                                           'forceDefaultEnabled'}
                                 @$html_parameters) .
                html_param_table(qq{Parameters for which Active Notification }.
                                 qq{MAY be Denied},
                                 {tabopts => $tabopts, sepobj => 1},
                                 grep {$_->{activeNotify} eq 'canDeny'}
                                 @$html_parameters);
                my $title = qq{Profile Definitions};
                print <<END;
        </ul> <!-- Inform and Notification Requirements -->
        <li><a href="#$title">$title</a></li>
        <ul> <!-- $title -->
END
                $html_buffer .= <<END;
    <h2><a name="$title">$title</a></h2>
END
                $html_profile_active = 1;
            }
            my $title = qq{$name Profile};
            print <<END;
          <li><a href="#$name">$title</a></li>
END
            $html_buffer .= <<END;
    <h3><a name="$name">$title</a></h3>
    $description<p>
    <table width="60%" $tabopts> <!-- $title -->
      <tbody>
        <tr>
          <th width="80%" class="g">Name</th>
          <th width="20%" class="gc">Requirement</th>
        </tr>
END
        }

        if ($model || $profile) {
        } elsif (!$html_profile_active) {
            # note that the second anchor does NOT have a trailing dot;
            # this is to allow use of (for example) {{object|table}}
            # XXX should verify that all links have defined anchors
            $name = qq{<a name="$path">$name</a>} unless $nolinks;
            my $anchor2 = qq{};
            if (!$nolinks) {
                my $tpath = $path;
                $tpath =~ s/(\.\{i\})?\.$//;
                $anchor2 = qq{<a name="$tpath"/>} if $tpath ne $path;
            }
            print <<END if $object && !$nolinks;
          <li><a href="#$path">$path</a></li>
END
            $html_buffer .= <<END;
        <tr>
          <td class="${class}">$anchor2$name</td>
          <td class="${class}">$type</td>
          $synt_oc<td class="${class}">$syntax</td>$synt_cc
          <td class="${class}c">$write</td>
          <td class="${class}">$description</td>
          <td class="${class}c">$default</td>
          $vers_oc<td class="${class}c">$version</td>$vers_cc
          $spec_oc<td class="${class}c">$specs</td>$spec_cc
	</tr>
END
        } else {
            $path = $pname . $name unless $object;
            $name = qq{<a href="#$path">$name</a>} unless $nolinks;
            $write = 'R' if $access eq 'readOnly';
            $html_buffer .= <<END;
        <tr>
          <td class="${class}">$name</td>
          <td class="${class}c">$write</td>
	</tr>
END
        }
    }
}

sub html_post
{
    my ($node, $indent) = @_;

    my $name = $node->{name};
    my $model = ($node->{type} =~ /model/);
    my $profile = ($node->{type} =~ /profile/);

    if (($model && !$html_profile_active) || $profile || !$indent) {
        # XXX this can close too many tables (not a bad problem?)
	$html_buffer .= <<END;
      </tbody>
    </table> <!-- $name -->
END
        # XXX this is heuristic (but usually correct)
        if (!$indent) {
            print <<END;
        </ul>
      </ul>
END
            $html_buffer .= <<END;
  </body>
</html>
END
            print $html_buffer;
        }
    }
}

# Output an HTML parameter table, optionally with separate object rows
sub html_param_table
{
    my ($title, $hash, @parameters) = @_;

    my $tabopts = $hash->{tabopts};
    my $sepobj = $hash->{sepobj};

    my $html_buffer = qq{};

    print <<END;
    <li><a href="#$title">$title</a></li>
END

    $html_buffer .= <<END;
    <h3><a name="$title">$title</a></h3>
END

    $html_buffer .= <<END;
    <table width="60%" $tabopts> <!-- $title -->
      <tbody>
        <tr>
          <th class="g">Parameter</th>
        </tr>
END

    my $curobj = '';
    foreach my $parameter (@parameters) {
        # don't html_escape until after have parsed path (assumes dots)
        my $path = $parameter->{path};
        my $param = $path;
        if ($sepobj) {
            (my $object, $param) = $path =~ /^(.*\.)([^\.]*)$/;
            $object = html_escape($object, {empty => ''});
            if ($object && $object ne $curobj) {
                $curobj = $object;
                $object = qq{<a href="#$object">$object</a>} unless $nolinks;
                $html_buffer .= <<END;
        <tr>
          <td class="o">$object</td>
        </tr>
END
            }
        }
        $path = html_escape($path, {empty => ''});
        $param = html_escape($param, {empty => ''});
        $param = qq{<a href="#$path">$param</a>} unless $nolinks;
        $html_buffer .= <<END;
        <tr>
          <td>$param</td>
        </tr>
END
    }

    $html_buffer .= <<END;
      </tbody>
    </table> <!-- $title -->
END
    return $html_buffer;
}

# Escape a value suitably for exporting as HTML.
# XXX is mostly aimed at descriptions, but probably does no harm to anything
#     else
sub html_escape {
    my ($value, $opts) = @_;

    $value = util_default($value, $opts->{default}, $opts->{empty});

    # this is intended for string defaults
    $value = '"' . $value . '"' if $opts->{quote} && $value !~ /^[<-]/;

    # escape special characters
    # XXX do this is part of markup processing?
    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    # apply UPnP DM rules
    # XXX be simple-minded and do this unconditionally to begin with...
    #     (for technical reasons, rules not applied in the same order as
    #     defined in the doc; still some false positives)
    if ($upnpdm) {
        my $before = $value;
        # " .A" -> " A" (also as template arg and at start)
        $value =~ s/^\.([A-Z])/$1/g;
        $value =~ s/([\s\|])\.([A-Z])/$1$2/g;

        # ".{i}" -> ".#"
        $value =~ s/\.\{i\}/\.#/g;

        # "Name.(Name|#)." -> "Name/(Name|#)/"
        $value =~ s/([A-Z]\w*)\.((?:[A-Z]\w*|#))\./$1\/$2\//g;

        # "Name.Name" -> "Name/Name"
        $value =~ s/([A-Z]\w*)\.((?:[A-Z]\w*|#))/$1\/$2/g;

        # "Name(/(Name|#))+." -> ".../"
        $value =~ s/([A-Z]\w*)((?:\/(?:[A-Z]\w*|#))+)\./$1$2\//g;

        # Remove BBF-specific root-ish objects
        $value =~ s/(?:InternetGateway)?Device\/([A-Z])/$1/g;
        $value =~ s/Services\/([A-Z])/$1/g;
        $value =~ s/\w+Service\/#\/([A-Z])/$1/g;

        # Final hack to get rid BBF-specific root-ish objects
        $value = '' if $value =~ /^(?:InternetGateway)?Device\.$/;
        $value = '' if $value =~ /^Services\/$/;

        # XXX this doesn't quite work because leaves empty top-level
        #     Service object and any top-level parameters, e.g. Enable
        $value = '' if $value =~ /^\w+Service\/#\/$/;

        print STDERR "$before -> $value\n" if
                                     $verbose > 1 && $value ne $before;
    }

    # process markup
    # XXX whitespace and template processing is generic; shouldn't be done
    #     here
    unless ($opts->{nomarkup}) {
        $value = html_whitespace($value);
        $value = html_template($value, $opts) unless $notemplates;
        # XXX here is the place to escape HTML-special characters
        $value = html_verbatim($value);
        $value = html_list($value);
        # XXX also (but shouldn't) does "%%" anchor expansion (which will
        #     generate an anchor with the name of the current object or
        #     parameter path, then a dot, then the text between the %%s
        $value = html_font($value, $opts);
        $value = html_paragraph($value);
        $value = html_hyperlink($value);
    }

    # XXX fudge wrap of very long names and types (firefox 3 supports &shy;)
    $value =~ s/([^\d]\.)/$1&shy;/g if $opts->{fudge} && !$nohyphenate;
    $value =~ s/&shy;$// if $opts->{fudge} && !$nohyphenate;
    $value =~ s/\(/&shy;\(/g if $opts->{fudge} && !$nohyphenate;
    $value =~ s/\[/&shy;\[/g if $opts->{fudge} && !$nohyphenate;

    # XXX try to hyphenate long words (firefox 3 supports &shy;)
    $value =~ s/([a-z_])([A-Z])/$1&shy;$2/g if
        $opts->{hyphenate} && !$nohyphenate;

    $value = '&nbsp;' if $opts->{nbsp} && $value eq '';

    return $value;
}

# Process whitespace
sub html_whitespace
{
    my ($inval) = @_;

    return $inval unless $inval;

    # remove any leading whitespace up to and including the first line break
    $inval =~ s/^[ \t]*\n//;

    # remove any trailing whitespace (necessary to avoid polluting the prefix
    # length)
    $inval =~ s/\s*$//;

    # determine longest common whitespace prefix
    my $len = undef;
    my @lines = split /\n/, $inval;
    foreach my $line (@lines) {
        my ($pre) = $line =~ /^(\s*)/;
        $len = length($pre) if !defined($len) || length($pre) < $len;
        if ($line =~ /\t/) {
            my $tline = $line;
            $tline =~ s/\t/\\t/g;
            print STDERR "replace tab(s) in \"$tline\" with spaces!\n";
        }
    }
    $len = 0 unless defined $len;

    # remove it
    my $outval = '';
    foreach my $line (@lines) {
        $line = substr($line, $len);
        $outval .= $line . "\n";
    }

    # remove trailing newline
    chomp $outval;
    return $outval;
}

# Process templates
sub html_template
{
    my ($inval, $p) = @_;

    # auto-prefix {{reference}} if the parameter is a reference (put after
    # {{list}} if already there)
    if ($p->{reference} && $inval !~ /\{\{reference/ &&
        $inval !~ /\{\{noreference\}\}/) {
        my $sep = !$inval ? "" : "  ";
        if ($inval =~ /\{\{list\}\}/) {
            $inval =~ s/(\{\{list\}\})/$1$sep\{\{reference\}\}/;
        } else {
            $inval = "{{reference}}" . $sep . $inval;
        }
    }

    # auto-prefix {{list}} if the parameter is list-valued
    if ($p->{list} && $inval !~ /\{\{list/ &&
        $inval !~ /\{\{nolist\}\}/) {
        my $sep = !$inval ? "" : "  ";
        $inval = "{{list}}" . $sep . $inval;
    }

    # auto-prefix {{datatype}} if autodatatype is set and the parameter has
    # a named data type
    if ($p->{type} && $p->{type} eq 'dataType' && $autodatatype &&
        $inval !~ /\{\{nodatatype\}\}/) {
        my $sep = !$inval ? "" : "  ";
        $inval = "{{datatype}}" . $sep . $inval;
    }

    # auto-prefix {{profdesc}} if it's a profile
    if ($p->{profile} && $inval !~ /\{\{noprofdesc\}\}/) {
        my $sep = !$inval ? "" : "  ";
        $inval = "{{profdesc}}" . $sep . $inval;
    }

    # auto-append {{enum}} or {{pattern}} if there are values and it's not
    # already there (put it on the same line if the value is empty or ends
    # with a sentence terminator, allowing single quote formatting chars)
    # "{{}}" is an empty template reference that will be removed; it prevents
    # special "after newline" template expansion behavior
    if ($p->{values} && %{$p->{values}}) {
        my ($key) = keys %{$p->{values}};
        my $facet = $p->{values}->{$key}->{facet};
        my $sep = !$inval ? "" : $inval =~ /[\.\?\!]\'*$/ ? "  " : "\n{{}}";
        $inval .= $sep . "{{enum}}" if $facet eq 'enumeration' &&
            $inval !~ /\{\{enum\}\}/ && $inval !~ /\{\{noenum\}\}/;
        $inval .= $sep . "{{pattern}}" if $facet eq 'pattern' &&
            $inval !~ /\{\{pattern\}\}/ && $inval !~ /\{\{nopattern\}\}/;
    }

    # similarly auto-append {{hidden}}, {{factory}} and {{keys}} if
    # appropriate
    if ($p->{hidden} && $inval !~ /\{\{hidden/ &&
        $inval !~ /\{\{nohidden\}\}/) {
        my $sep = !$inval ? "" : "\n";
        $inval .= $sep . "{{hidden}}";
    }
    if ($p->{factory} && $inval !~ /\{\{factory/ &&
        $inval !~ /\{\{nofactory\}\}/) {
        my $sep = !$inval ? "" : "\n";
        $inval .= $sep . "{{factory}}";
    }
    if ($p->{uniqueKeys} && @{$p->{uniqueKeys}}&&
        $inval !~ /\{\{keys/ && $inval !~ /\{\{nokeys\}\}/) {
        my $sep = !$inval ? "" : "\n";
        $inval .= $sep . "{{keys}}";
    }

    # in template expansions, the @a array is arguments and the %p hash is
    # parameters (options)
    my $templates =
        [
         {name => 'bibref',
          text1 => \&html_template_bibref,
          text2 => \&html_template_bibref},
         {name => 'section', text => q{}},
         {name => 'param',
          text0 => q{''$p->{param}''},
          text1 => \&html_template_paramref,
          text2 => \&html_template_paramref},
         {name => 'object',
          text0 => q{''$p->{object}''},
          text1 => \&html_template_objectref,
          text2 => \&html_template_objectref},
         {name => 'profile',
          text0 => q{''$p->{profile}''},
          text1 => q{<a href="#$a[0]">''$a[0]''</a>}},
         {name => 'keys',
          text0 => \&html_template_keys},
         {name => 'nokeys',
          text0 => q{}},
         {name => 'list',
          text0 => \&html_template_list,
          text1 => \&html_template_list},
         {name => 'nolist',
          text0 => q{}},
         {name => 'datatype',
          text0 => \&html_template_datatype,
          text1 => \&html_template_datatype},
         {name => 'nodatatype',
          text0 => q{}},
         {name => 'profdesc',
          text0 => \&html_template_profdesc},
         {name => 'noprofdesc',
          text0 => q{}},
         {name => 'hidden',
          text0 => q{{{mark|hidden}}When read, this parameter returns {{null}}, regardless of the actual value.},
          text1 => q{{{mark|hidden}}When read, this parameter returns ''$a[0]'', regardless of the actual value.}},
         {name => 'nohidden',
          text0 => q{}},
         {name => 'factory',
          text0 => q{{{mark|factory}}The factory default value MUST be ''$p->{factory}''.}},
         {name => 'nofactory',
          text0 => q{}},
         {name => 'null',
          text0 => \&html_template_null},
         {name => 'enum',
          text0 => \&html_template_enum,
          text1 => \&html_template_valueref,
          text2 => \&html_template_valueref,
          text3 => \&html_template_valueref},
         {name => 'noenum',
          text0 => q{}},
         {name => 'pattern',
          text0 => \&html_template_pattern,
          text1 => \&html_template_valueref,
          text2 => \&html_template_valueref,
          text3 => \&html_template_valueref},
         {name => 'nopattern',
          text0 => q{}},
         {name => 'reference',
          text0 => \&html_template_reference,
          text1 => \&html_template_reference},
         {name => 'noreference',
          text0 => q{}},
         {name => 'units',
          text0 => \&html_template_units},
         {name => 'empty', text0 => q{an empty string}, ucfirst => 1},
         {name => 'false', text0 => q{''false''}},
         {name => 'true', text0 => q{''true''}},
         {name => 'mark',
          text1 => \&html_template_mark},
         {name => 'issue',
          text1 => \&html_template_issue}
         ];

    # XXX expand {{XXX}} expansion to track open issues

    # XXX need some protection against infinite loops here...
    # XXX do we want to allow template references to span newlines?
    while (my ($newline, $period, $temp) =
           $inval =~ /(\n?)[ \t]*([\.\?\!]?)[ \t]*(\{\{.*)/) {
        # pattern returns rest of string in temp (owing to difficulty of
        # handling nested braces), so match braces to find end
        my $tref = extract_bracketed($temp, '{}');
        if (!defined($tref)) {
            print STDERR "$p->{path}: invalid template reference: $temp\n";
            $inval =~ s/\{\{/\[\[/;
            next;
        }
        my ($name, $args) = $tref =~ /^\{\{([^\|\}]*)(?:\|(.*))?\}\}$/;
        # XXX atstart is possibly useful for descriptions that consist only of
        #     {{enum}} or {{pattern}}?  I think not...
        if (!defined($name)) {
            print STDERR "$p->{path}: invalid template reference: $tref\n";
            $inval =~ s/\{\{/\[\[/;
            next;
        }
        my $atstart = $inval =~ /^\{\{$name[\|\}]/;
        $p->{atstart} = $atstart;
        $p->{newline} = $newline;
        $p->{period} = $period;
        #my @a = split /\|/, $args;
        my @a = ();
        if (defined $args) {
            my $a = '';
            my $i = 0;
            foreach my $c (split //, $args) {
                $i++ if $c eq '{';
                $i-- if $c eq '}';
                if (!$i && $c eq '|') {
                    push @a, $a;
                    $a = '';
                } else {
                    $a .= $c;
                }
            }
            push @a, $a;
        }
        my $n = @a;
        my $template = (grep {$_->{name} eq $name} @$templates)[0];
        my $text = $tref;
        $text =~ s/^../\[\[/;
        $text =~ s/..$/\]\]/;
        my $cmd;
        if ($template) {
            $cmd = defined $template->{'text'.$n} ? $template->{'text'.$n} :
                $template->{text};
            if (ref($cmd)) {
                $text = &$cmd($p, @a);
            } elsif (defined $cmd) {
                print STDERR "$text: $cmd\n" if $verbose > 2;
                my $ttext = eval "qq{$cmd}";
                if ($@) {
                    warn $@;
                } else {
                    $text = $ttext;
                    $text = ucfirst $text if
                        $template->{ucfirst} && ($newline || $period);
                }
            }
        }
        if ($name && $text =~ /^\[\[/) {
            print STDERR "$p->{path}: invalid template reference: $tref\n";
            #print STDERR "$name: n=$n cmd=<$cmd> text=<$text>\n";
            #foreach my $a (@a) {
            #    print STDERR "  $a\n";
            #}
        }
        # process tref to avoid problems with RE special characters
        $tref =~ s/[^\{\}]/\./g;
        $inval =~ s/$tref/$text/;
    }

    # remove null template references (which are used as separators)
    $inval =~ s/\[\[\]\]//g;

    # restore unexpanded templates
    $inval =~ s/\[\[([^\]]*)/\{\{$1/g;
    $inval =~ s/\]\]/\}\}/g;

    return $inval;
}

# insert a mark, e.g. for a template expansion
sub html_template_mark
{
    my ($opts, $arg) = @_;

    return $marktemplates ? qq{$marktemplates$arg:} : qq{};
}

# used by the {{issue}} template
my $issue_counter = 0;

# report and track an issue
sub html_template_issue
{
    my ($opts, $arg) = @_;

    $issue_counter++;
    return qq{\n'''XXX $issue_counter: $arg'''};
}

# insert appropriate null value
# XXX currently rather simple-minded and no support for named data types
sub html_template_null
{
    my ($opts) = @_;

    my $type= $opts->{type};

    return '{{empty}}' if $type =~ /^(string|base64|hexBinary)/;
    return '{{false}}' if $type eq 'boolean';
    return '0';
}

# insert units string
sub html_template_units
{
    my ($opts) = @_;

    my $path = $opts->{path};
    my $units = $opts->{units};

    if (!$units) {
        print STDERR "$path: empty units string\n";
        return qq{[[units]]};
    } else {
        return qq{''$units''};
    }
}

# XXX want to be able to control level of generated info?
sub html_template_list
{
    my ($opts, $arg) = @_;

    my $type = $opts->{type};
    my $syntax = $opts->{syntax};

    my $text = '{{mark|list}}Comma-separated ' . syntax_string($type, $syntax, 1);
    if ($arg) {
        $text .= ', ' . $arg;
    }
    $text .= '.';

    return $text;
}

# XXX want to be able to control level of generated info?
sub html_template_datatype
{
    my ($opts, $arg) = @_;

    my $type = $opts->{type};
    my $syntax = $opts->{syntax};

    my $typeinfo = get_typeinfo($type, $syntax);

    my $dtname = $typeinfo->{value};
    my ($dtdef) = grep {$_->{name} eq $dtname} @{$root->{dataTypes}};

    # XXX should check for valid data type? (should always be)

    # XXX previously included the description...
    #my $text = $dtdef->{description};
    #$text .= '.' unless $text =~ /\.$/;

    # XXX now just return "[datatype] "
    my $text = $nolinks ?
        qq{[''$dtname''] } :
        qq{[''<a href="#$dtname">$dtname</a>''] };

    return $text;
}

sub html_template_profdesc
{
    my ($opts, $arg) = @_;

    my $node = $opts->{node};
    my $name = $node->{name};
    my $base = $node->{base};
    my $extends = $node->{extends};

    # model in which profile was first defined
    my $defmodel = $profiles->{$name}->{defmodel};

    # same model but excluding minor version number
    my $defmodelmaj = $defmodel;
    $defmodelmaj =~ s/\.\d+$//;

    my $baseprofs = $base;
    my $plural = '';
    if ($extends) {
        $plural = 's' if $baseprofs || $extends =~ / /;
        $baseprofs .= ' ' if $baseprofs;
        $baseprofs .= $extends;
    }
    if ($baseprofs) {
        $baseprofs =~ s/(\w+:\d+)/{{profile|$1}}/g;
        $baseprofs =~ s/ /, /g;
        $baseprofs =~ s/, ([^,]+$)/ and $1/;
    }

    my $text = $baseprofs ? qq{The} : qq{This table defines the};
    $text .= qq{ {{profile}} profile for the ''$defmodelmaj'' object};
    $text .= qq{ is defined as the union of the $baseprofs profile$plural }.
        qq{and the additional requirements defined in this table} if $baseprofs;
    $text .= qq{.  The minimum REQUIRED version for this profile is }.
        qq{''$defmodel''.};

    return $text;
}

sub html_template_keys
{
    my ($opts) = @_;

    my $object = $opts->{object};
    my $access = $opts->{access};
    my $uniqueKeys = $opts->{uniqueKeys};
    my $enableParameter = $opts->{enableParameter};

    my $text = qq{{{mark|keys}}};

    my $enabled = $enableParameter ? qq{ enabled} : qq{};
    $text .= qq{At most one$enabled entry in this table } .
        qq{can exist with };
    my $i = 0;
    foreach my $uniqueKey (@$uniqueKeys) {
        $text .= qq{, or with } if $i > 0;
        $text .= qq{all } if @$uniqueKey > 2;
        $text .= @$uniqueKey > 1 ? qq{the same values } : qq{a given value };
        $text .= qq{for };
        # XXX use util_list($uniqueKey, qq{{{param|\$1}}})
        my $j = 0;
        foreach my $parameter (@$uniqueKey) {
            $text .= (($j < @$uniqueKey - 1) ? ', ' : ' and ') if $j > 0;
            $text .= qq{{{param|$parameter}}};
            $j++;
        }
        $i++;
    }
    $text .= qq{.};

    # XXX the next bit is needed only if one or more of the unique key
    #     parameters is writable; currently we don't have access to this
    #     information here
    # XXX it's not quite the same but this criterion is almost certainly the
    #     same as whether the object is writable
    if ($access ne 'readOnly') {
        # XXX have suppressed this boiler plate (it should be stated once)
        $text .= qq{  If the ACS attempts to set the parameters of an } .
            qq{existing entry such that this requirement would be violated, } .
            qq{the CPE MUST reject the request. In this case, the } .
            qq{SetParameterValues response MUST include a } .
            qq{SetParameterValuesFault element for each parameter in the } .
            qq{corresponding request whose modification would have resulted } .
            qq{in such a violation.} if 0;
        if (!$enableParameter) {
            my $i;
            my @params = ();
            foreach my $uniqueKey (@$uniqueKeys) {
                foreach my $parameter (@$uniqueKey) {
                    my $path = $object . $parameter;
                    my $defaulted = defined $parameters->{$path}->{default} &&
                        $parameters->{$path}->{deftype} eq 'object' &&
                        $parameters->{$path}->{defstat} ne 'deleted';
                    push @params, $parameter unless $defaulted;
                    $i++;
                }
            }
            if ($i && !@params) {
                print STDERR "$object: all unique key parameters are " .
                    "defaulted; need enableParameter\n";
            }
            if (@params) {
                $text .= qq{  On creation of a new table entry, the CPE } .
                    qq{MUST choose };
                $text .= qq{an } if @params == 1;
                $text .= qq{initial value};
                $text .= qq{s} if @params > 1;
                $text .= qq{ for };
                # XXX use util_list(\$params, qq{{{param|\$1}}})
                my $i = 0;
                foreach my $param (@params) {
                    $text .= (($i < @params - 1) ? ', ' : ' and ') if $i > 0;
                    $text .= qq{{{param|$param}}};
                    $i++;
                }
                $text .= qq{ such that the new entry does not conflict with } .
                    qq{any existing entries.};
            }
        }
    }

    return $text;
}

sub html_template_enum
{
    my ($opts) = @_;
    # XXX not using atstart (was "atstart or newline")
    my $pref = ($opts->{newline}) ? "" : $opts->{list} ?
        "Each list item is an enumeration of:\n" : "Enumeration of:\n";
    return $pref . xml_escape(get_values($opts->{values}, !$nolinks));
}

sub html_template_pattern
{
    my ($opts) = @_;
    # XXX not using atstart (was "atstart or newline")
    my $pref = ($opts->{newline}) ? "" : $opts->{list} ?
        "Each list item matches one of:\n" :
        "Possible patterns:\n";
    return $pref . xml_escape(get_values($opts->{values}, !$nolinks));
}


# generates reference to bibliographic reference: arguments are bibref name
# and optional section
sub html_template_bibref
{
    my ($opts, $bibref, $section) = @_;

    my $text = qq{\[};
    $text .= qq{<a href="#$bibref">} unless $nolinks;
    $text .= qq{$bibref};
    $text .= qq{</a>} unless $nolinks;
    $text .= qq{\]};
    $text .= qq{ $section} if $section;

    return $text;
}

# generates reference to parameter: arguments are parameter name and optional
# scope
sub html_template_paramref
{
    my ($opts, $name, $scope) = @_;

    my $object = $opts->{object};
    my $param = $opts->{param};

    print STDERR "$object$param: {{param}} argument unnecessary when ".
        "referring to current parameter\n" if $pedantic && $name eq $param;

    (my $path, $name) = relative_path($object, $name, $scope);

    my $invalid = ($parameters->{$path} && %{$parameters->{$path}}) ? '' : '?';
    # XXX don't warn of invalid references for UPnP DM (need to fix!)
    $invalid = '' if $upnpdm;
    # XXX don't warn further if this item has been deleted
    if (!util_is_deleted($opts->{node})) {
        print STDERR "$object$param: reference to invalid parameter $path\n"
            if $invalid;
        # XXX make this nicer (not sure why test of status is needed here but
        #     upnpdm triggers "undefined" errors otherwise
        if (!$invalid && $parameters->{$path}->{status} &&
            $parameters->{$path}->{status} eq 'deleted') {
            print STDERR "$object$param: reference to deleted parameter ".
                "$path\n";
            $invalid = '!';
        }
    }

    my $text = qq{};
    $text .= qq{<a href="#$path">} unless $nolinks;
    $text .= qq{''$name$invalid''};
    $text .= qq{</a>} unless $nolinks;

    return $text;
}

# generates reference to object: arguments are object name and optional
# scope
sub html_template_objectref
{
    my ($opts, $name, $scope) = @_;

    my $object = $opts->{object};
    my $param = $opts->{param};

    # XXX this probably needs to be cleverer
    print STDERR "$object$param: {{object}} argument unnecessary when ".
        "referring to current object\n" if $pedantic && $name eq $object;

    (my $path, $name) = relative_path($object, $name, $scope);
    my $path1 = $path;
    $path1 .= '.' if $path1 !~ /\.$/;

    # we allow reference to table X via "X" or "X.{i}"...
    my $path2 = $path1;
    $path2 .= '{i}.' if $path2 !~ /\{i\}\.$/;

    # XXX horrible
    $path = $path1 if $objects->{$path1} && %{$objects->{$path1}};
    $path = $path2 if $objects->{$path2} && %{$objects->{$path2}};

    my $invalid = ($objects->{$path} && %{$objects->{$path}}) ? '' : '?';
    # XXX don't warn of invalid references for UPnP DM (need to fix!)
    $invalid = '' if $upnpdm;
    # XXX don't warn further if this item has been deleted
    if (!util_is_deleted($opts->{node})) {
        print STDERR "$object$param: reference to invalid object $path\n"
            if $invalid;
        # XXX make this nicer (not sure why test of status is needed here but
        #     upnpdm triggers "undefined" errors otherwise
        if (!$invalid && $objects->{$path}->{status} &&
            $objects->{$path}->{status} eq 'deleted') {
            print STDERR "$object$param: reference to deleted object $path\n";
            $invalid = '!';
        }
    }
   
    my $text = qq{};
    $text .= qq{<a href="#$path">} unless $nolinks;
    $text .= qq{''$name$invalid''};
    $text .= qq{</a>} unless $nolinks;

    return $text;
}

# generates reference to enumeration or pattern: arguments are value, optional
# parameter name (if omitted, is this parameter), and optional scope
sub html_template_valueref
{
    my ($opts, $value, $name, $scope) = @_;

    my $object = $opts->{object};
    my $param = $opts->{param};

    my $this = $name ? 0 : 1;
    $name = $param unless $name;

    (my $path, $name) = relative_path($object, $name, $scope);

    my $invalid = '';
    # XXX don't warn of invalid references for UPnP DM (need to fix!)
    if (!$parameters->{$path} || !%{$parameters->{$path}}) {
        $invalid = '?';
        $invalid = '' if $upnpdm;
        # XXX don't warn further if this item has been deleted
        if (!util_is_deleted($opts->{node})) {
            print STDERR "$object$param: reference to invalid parameter ".
                "$path\n" if $invalid;
            # XXX make this nicer (not sure why test of status is needed here
            #     but upnpdm triggers "undefined" errors otherwise
            if (!$invalid && $parameters->{$path}->{status} &&
                $parameters->{$path}->{status} eq 'deleted') {
                print STDERR "$object$param: reference to deleted parameter ".
                    "$path\n";
                $invalid = '!';
            }
        }
    } else {
        my $node = $parameters->{$path};
        # XXX experimental: try to follow enumerationRefs
        my $syntax = $node->{syntax};
        if ($syntax->{reference} && $syntax->{reference} eq 'enumerationRef') {
            my $targetParam = $syntax->{targetParam};
            my $targetParamScope = $syntax->{targetParamScope};
            my ($targetPath) = relative_path($node->{pnode}->{path},
                                             $targetParam, $targetParamScope);
            if (!$parameters->{$targetPath} ||
                !%{$parameters->{$targetPath}}) {
                print STDERR "$path: enumerationRef references non-existent ".
                    "parameter $targetPath: ignored\n";
            } else {
                $path = $targetPath;
                $node = $parameters->{$path};
            }
        }
        my $values = $node->{values};
        $invalid = (has_values($values) && has_value($values, $value)) ?
            '' : '?';
        $invalid = '' if $upnpdm;
        # XXX don't warn further if this item has been deleted
        if (!util_is_deleted($opts->{node})) {
            print STDERR "$object$param: reference to invalid value $value\n"
                if $invalid;
            if (!$invalid && $values->{$value}->{status} eq 'deleted') {
                print STDERR "$object$param: reference to deleted value $value\n";
                $invalid = '!';
            }
        }
    }

    my $text = qq{};
    if ($this) {
        $text .= qq{''$value$invalid''};
    } else {
        # XXX remove backslashes (needs done properly)
        my $tvalue = $value;
        $tvalue =~ s/\\//g;

        my $sep = $upnpdm ? '/' : '.';
        $text .= qq{<a href="#$path$sep$tvalue">} unless $nolinks;
        $text .= qq{''$value$invalid''};
        $text .= qq{</a>} unless $nolinks;
    }
   
    return $text;
}

sub html_template_reference
{
    my ($opts, $arg) = @_;

    my $object = $opts->{object};
    my $path = $opts->{path};
    my $type = $opts->{type};
    my $list = $opts->{list};
    my $reference = $opts->{reference};
    my $syntax = $opts->{syntax};

    my $text = qq{};

    if (!defined $reference) {
        print STDERR "$path: {{reference}} used on non-reference parameter\n";
        return qq{[[reference]]};
    }

    $text .= qq{{{mark|reference}}};

    # XXX it is assumed that this text will be generated after the {{list}}
    #     expansion (if a list)
    $text .= $list ?
        qq{Each list item } :
        qq{The value };

    if ($reference eq 'pathRef') {
        my $refType = $syntax->{refType};
        my $targetParent = $syntax->{targetParent};
        my $targetParentScope = $syntax->{targetParentScope};
        my $targetType = $syntax->{targetType};
        my $targetDataType = $syntax->{targetDataType};

        $targetType = 'any' unless $targetType;

        # XXX this logic currently for pathRef only, but also applies
        #     to instanceRef (for which targetParent cannot be a list, and
        #     targetType is always "row")
        my $targetParentReadOnly = 1;
        if ($targetParent) {
            foreach my $tp (split ' ', $targetParent) {
                my ($tpp) = relative_path($object, $tp, $targetParentScope);
                $tpp .= '{i}.' if $targetType eq 'row';
                my $tpn = $objects->{$tpp};
                $targetParentReadOnly = 0
                    if $tpn && $tpn->{access} eq 'readWrite';
            }
        }

        $targetParent = object_references($targetParent,
                                          $targetParentScope);

        # XXX was "full path name"; removed "full" to allow support of TR-106
        #     relative path name syntax
        $text .= qq{MUST be the path name of };

        if ($targetType eq 'row') {
            if ($arg) {
                $text .= $arg;
            } else {
                my $s = $targetParent =~ / / ? 's' : '';
                $text .= $targetParent ?
                    qq{a row in the $targetParent table$s} :
                    qq{a table row};
            }
        } else {
            $targetType =~ s/single/single-instance object/;
            $targetType =~ s/any/parameter or object/;
            if ($arg) {
                $text .= $arg;
            } else {
                if ($targetDataType && $targetDataType ne 'any') {
                    $text .= ($targetDataType =~ /^[aeiou]/ ? qq{an} : qq{a});
                    $text .= qq{ $targetDataType};
                } else {
                    $text .= ($targetType =~ /^[aeiou]/ ? qq{an} : qq{a});
                }
                $text .= qq{ $targetType};
            }
            $text .= $targetParent ?
                qq{, which MUST be a child of $targetParent} :
                qq{};
        }
        if ($refType ne 'strong') {
            $text .= qq{.};
        } else {
            $targetType =~ s/row/object/;
            $targetType =~ s/single.*/object/;
            $targetType =~ s/parameter or object/item/;
            # XXX disabling this text may have been correct in some cases, but
            #     not always, e.g. not for interface stack LowerLayer and
            #     HigherLayer
            if (0 && $targetParentReadOnly) {
                $text .= $list ?
                    qq{.} :
                    qq{, or {{empty}}.};
            } else {
                $text .= qq{.};
                $text .= qq{  If the referenced $targetType is deleted, the };
                $text .= $list ?
                    qq{corresponding item MUST be removed from the list.} :
                    qq{parameter value MUST be set to {{empty}}.};
            }
        }

    } elsif ($reference eq 'instanceRef') {
        my $refType = $syntax->{refType};
        my $targetParent = $syntax->{targetParent};
        my $targetParentScope = $syntax->{targetParentScope};

        $targetParent = object_references($targetParent,
                                          $targetParentScope);

        my $nullValue =
            (get_typeinfo($type, $syntax)->{value} =~ /^unsigned/) ? 0 : -1;

        my $s = $targetParent =~ / / ? 's' : '';
        $text .= qq{MUST be the instance number of a row in the }.
            qq{$targetParent table$s};
        $text .= qq{, or else be $nullValue if no row is currently } .
            qq{referenced} unless $list;
        $text .= qq{.};
        if ($refType eq 'strong') {
            $text .= qq{  If the referenced row is deleted, the };
            $text .= $list ?
                qq{corresponding item MUST be removed from the list.} :
                qq{parameter value MUST be set to $nullValue.};
        }

    } elsif ($reference eq 'enumerationRef') {
        my $targetParam = $syntax->{targetParam};
        my $targetParamScope = $syntax->{targetParamScope};
        my $nullValue = $syntax->{nullValue};

        $nullValue = ($nullValue ne '' ? qq{''$nullValue''} : qq{{{empty}}}) if
            defined $nullValue;

        # XXX need to use targetParamScope here
        $text .= qq{MUST be a member of the list reported by the } .
            qq{{{param|$targetParam}} parameter};
        $text .= qq{, or else be $nullValue} if defined $nullValue;
        $text .= qq{.};

    } else {
        # XXX should warn about this (can't happen)
        $text = '';
    }

    return $text;
}

# Generate relative path given...
# 
# XXX note that DM instances can't really make use of the proposed "^" syntax
#     because it implies a reference to a different data model, so it is not
#     yet supported
sub relative_path
{
    my ($parent, $name, $scope) = @_;

    $parent = '' unless $parent;
    $scope = 'normal' unless $scope;

    my $path;

    # XXX $parp (parent pattern) won't work for UPnP DM

    my $sep = $upnpdm ? q{#} : q{.};
    my $sepp = $upnpdm ? q{\#} : q{\.};
    my $par = $upnpdm ? q{!} : q{#};
    my $parp = $upnpdm ? q{\!} : q{\#};
    my $instp = $upnpdm ? q{\#} : q{\{};

    if ($scope eq 'normal' && $name =~ /^(Device|InternetGatewayDevice)\./) {
        $path = $name;
    } elsif (($scope eq 'normal' && $name =~ /^$sepp/) || $scope eq 'model') {
        my ($root, $next) = split /$sepp/, $parent;
        $next = ($next =~ /^$instp/) ? ($sep . $next) : '';
        my $sep = ($name =~ /^$sepp/) ? '' : $sep;
        $path = $root . $next . $sep . $name;
    } else {
        if ($scope eq 'normal' && $name =~ /^$parp/) {
            my ($nlev) = ($name =~ /^($parp*)/);
            $nlev = length $nlev;
            # XXX need a utility for this!
            my $tparent = $parent;
            $parent =~ s/\.\{/\{/g;
            #print STDERR "$parent $name $nlev\n";
            my @comps = split /$sepp/, $parent;
            splice @comps, -$nlev;
            $parent = join $sep, @comps;
            $parent =~ s/\{/\.\{/g;
            $parent .= '.' if $parent;
            print STDERR "$tparent: $name has too many $par characters\n"
                unless $parent;
            $name =~ s/^$parp*\.?//;
            #print STDERR "$parent $name\n";
        }
        $path = $parent . $name;
    }

    return ($path, $name);
}

# Generate appropriate {{object}} references from an XML list
sub object_references
{
    my ($list, $scope) = @_;

    $scope = $scope ? ('|' . $scope) : '';

    my $value = '';

    if ($list) {
        my $i = 0;
        my @refs = split /\s+/, $list;
        foreach my $ref (@refs) {
            $ref =~ s/\.$//;
            $value .= (($i < @refs - 1) ? ', ' : ' or ') if $i > 0;
            $value .= qq{{{object|$ref$scope}}};
            $i++;
        }
    }

    return $value;
}

# Process verbatim sections
sub html_verbatim
{
    my ($inval) = @_;

    my @lines = split /\n/, $inval;
    my $pre;
    my $outval = '';
    foreach my $line (@lines) {
        if (!$pre && $line =~ /^\s/) {
            $outval .= "<pre>\n";
            $pre = 1;
        } elsif ($pre && $line !~ /^\s/) {
            $outval .= "</pre>\n";
            $pre = 0;
        }
        $outval .= $line . "\n";
    }
    if ($pre) {
        $outval .= "</pre>\n";
    }
    chomp $outval;
    return $outval;
}

# Process list markup
sub html_list
{
    my ($inval) = @_;

    my $typemap = {'*' => 'ul', '#' => 'ol', ':' => 'dl'};
    my $itemmap = {'*' => 'li', '#' => 'li', ':' => 'dd'};

    my $outval = '';
    my $depth = 0;
    my $prev = '';
    my $lact = 1;
    my @lines = split /\n/, $inval;
    foreach my $line (@lines) {
	my $curr = '';
	my $rest = $line;
	if ($line =~ /^([\*\#:]+)\s*(.*)/) {
	    $curr = $1;
	    $rest = $2;
	}
        # special case for continuation at inner level
        my $cont = 0;
        if (substr($prev, $depth-1, 1) eq ':') {
        } elsif ($depth > 0 && $curr eq ($prev . ':')) {
            $cont = 1;
            $curr = $prev;
            $outval .= '  ' x $depth . "<br>$rest\n";
            next;
        }
        # special case for other continuations, e.g. "**:" -> "*:"
        elsif ($curr =~ /:$/) {
            $curr =~ s/(.*).:/$1:/;
        }
	my $newdepth = length $curr;
        while ($depth > $newdepth || ($depth > 0 && substr($curr, $depth-1, 1)
                                      ne substr($prev, $depth-1, 1))) {
            $depth--;
            my $type = $typemap->{substr($prev, $depth, 1)};
            $outval .= '  ' x $depth . "</$type><p>\n";
        }
	while ($newdepth > $depth) {
            my $type = $typemap->{substr($curr, $depth, 1)};
            $outval .= '  ' x $depth . "<$type>\n";
            $depth++;
        }
        my $item = $depth ? $itemmap->{substr($curr, $depth-1, 1)} : '';
	$outval .= '  ' x $depth . "<$item>" if $depth;
	$outval .= $rest;
        # XXX not currently terminating list items
	#$outval .= "</$item>" if $depth;
	$outval .= "\n";
        $prev = $curr;
    }
    while ($depth > 0) {
        $depth--;
        my $type = $typemap->{substr($prev, $depth, 1)};
	$outval .= '  ' x $depth . "</$type><p>\n";
    }
    chomp $outval;
    return $outval;
}

# Process hyperlinks
sub html_hyperlink
{
    my ($inval) = @_;

    # XXX need a better set of URL characters
    my $last = q{\w\d\:\/\?\&\=\-};
    my $notlast = $last . q{\.};
#   $inval =~ s|([a-z]+://[\w\d\.\:\/\?\&\=-]+)|<a href="$1">$1</a>|g;
    $inval =~ s|([a-z]+://[$notlast]*[$last])|<a href="$1">$1</a>|g;

    return $inval;
}

# Process font markup
sub html_font
{
    my ($inval, $opts) = @_;

    # XXX can't cope with things like '''bold ''bold italics'' bold'''
    #$inval =~ s|'''([^']*)'''|<b>$1</b>|g;
    #$inval =~ s|''([^']*)''|<i>$1</i>|g;

    # XXX experimental alternative; is better but won't cope with things like
    #     '''bold ''bold italics''''' (will mismatch the <b> and <i>... some
    #     browsers accept this... can always use an empty template - {{}} - to
    #     avoid such problems)
    # XXX could be kind and auto-terminate if necessary, e.g. for '''b ''i
    #     convert to '''b ''i''{{}}'''
    $inval =~ s|'''(.*?)'''|<b>$1</b>|g;
    $inval =~ s|''(.*?)''|<i>$1</i>|g;

    # XXX "%%" anchor expansion should be elsewhere (hyperlink?)
    # XXX need to escape special characters out of anchors and references
    if ($opts->{param}) {
        my $object = $opts->{object} ? $opts->{object} : '';
        my $path = $object . $opts->{param};
        $inval =~ s|%%([^%]*)%%([^%]*)%%|<a name="$path.$2">$1</a>|g;
    }

    return $inval;
}

# Process paragraph breaks
# XXX this assumes that leading spaces are left on verbatim lines
# XXX it behaves badly with lines that start with <b> or <i> (fudged)
sub html_paragraph
{
    my ($inval) = @_;

    my $outval = '';
    my @lines = split /\n/, $inval;
    foreach my $line (@lines) {
        $line =~ s/$/<p>/ if $line =~ /^<[b|i]>/ || $line !~ /^(\s|\s*<)/;

        $outval .= "$line\n";
    }

    $outval =~ s/(<p>)?\n$//;
    return $outval;
}

# Excel XML report of node.
# XXX is far too hard-coded; want to be able to select which columns are
#     hidden for example
# XXX would also want to create a worksheet for each profile
sub xls_begin
{
    my ($root) = @_;

    # Borders
    my $border_atts = 'ss:LineStyle="Continuous" ss:Weight="1"';
    my $borders = 
	"<Borders>" .
	"<Border ss:Position=\"Bottom\" $border_atts/>" .
	"<Border ss:Position=\"Left\" $border_atts/>" .
	"<Border ss:Position=\"Right\" $border_atts/>" .
	"<Border ss:Position=\"Top\" $border_atts/>" .
	"</Borders>";

    # Alignment
    my $top = 'ss:Vertical="Top"';
    my $center = 'ss:Horizontal="Center"';
    my $wrap =  'ss:WrapText="1"';
    my $align_default = "<Alignment $top $wrap/>";
    my $align_center = "<Alignment $top $center $wrap/>";

    # Font
    my $family = 'x:Family="Swiss"';
    my $bold = 'ss:Bold="1"';
    my $size = 'ss:Size="8"';
    my $font = "<Font $family $size/>";
    my $font_bold = "<Font $family $size $bold/>";

    # Interior (fill)
    my $color_header = 'ss:Color="#D0D0D0"';
    my $color_object = 'ss:Color="#FFFF99"';
    my $pattern = 'ss:Pattern="Solid"';
    my $interior_header = "<Interior $color_header $pattern/>";
    my $interior_object = "<Interior $color_object $pattern/>";

    # root attributes
    my $spec = $root->{spec};

    print <<END;
<?xml version="1.0"?>
<Workbook xsi:schemaLocation="urn:schemas-microsoft-com:office:spreadsheet
 C:\\PROGRA~1\\MI5A53~1\\MICROS~1\\SPREAD~1\\excelss.xsd"
 xmlns="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:x="urn:schemas-microsoft-com:office:excel"
 xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:html="http://www.w3.org/TR/REC-html40"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
 <Styles>
  <Style ss:ID="Default" ss:Name="Normal">$align_default$borders$font</Style>
  <Style ss:ID="DefaultCenter">$align_center$borders$font</Style>
  <Style ss:ID="Header">$align_default$borders$font_bold$interior_header</Style>
  <Style ss:ID="HeaderCenter">$align_center$borders$font_bold$interior_header</Style>
  <Style ss:ID="Object">$align_default$borders$font$interior_object</Style>
  <Style ss:ID="ObjectCenter">$align_center$borders$font$interior_object</Style>
 </Styles>
 <!--
 <Worksheet ss:Name="Introduction">
  <Table>
    <Column ss:Width="120"/>
    <Column ss:Width="120"/>
    <Row>
     <Cell ss:StyleID="Header"><Data ss:Type="String">Spec</Data></Cell>
     <Cell ss:StyleID="Default"><Data ss:Type="String">$spec</Data></Cell>
    </Row>
  </Table>
 </Worksheet>
 -->
END
}

# HTML "BBF" report of node.
#
# Similar output to that on CWMP web page at http://www.broadband-forum.org/
# cwmp.php.  Used to pass requirements to AMS.  Will hopefull evolve to be
# more like the "PD-148" report.

# implementation concepts are similar to those for the "PD-148" report.

# Comments with informal template expansion:
# - {{name}} => model name: name:m.n or "and"-separated list
# - {{type}} => model type: "Root Object" or "Service Object"
# - {{def}} => "definition" or "definitions" (depends on number of models)
# - {{err}} => "errata and clarifications"
# - {{ver}} => "vm.n"
my $htmlbbf_comments = {
    rpcs => 'TR-069 RPCs',
    dm => 'TR-069 Data Model Definition Schema (DM Schema) {{ver}}',
    dmr => 'TR-069 Data Model Report Schema (DMR Schema)',
    dt => 'TR-069 Device Type Schema (DT Schema) {{ver}}',
    dtf => 'TR-069 DT (Device Type) Features Schema (DTF Schema)',
    bibref => 'TR-069 data model bibliographic references',
    types => 'TR-069 Data Model Data Types',
    objdef => 'TR-069 {{name}} {{type}} {{def}}',
    objerr => 'TR-069 {{name}} {{type}} {{err}}',
    compdef => 'Component objects for CWMP: TR-069 {{name}} {{type}} {{def}}',
    comperr => 'Component objects for CWMP: TR-069 {{name}} {{type}} {{err}}'
};

# File info (could read this from a config file) that overrides information
# inferred from the files themselves (shouldn't be needed for DM Instances).
my $htmlbbf_info = {
    'cwmp-1-0.xsd' => {
        comment => 'rpcs', trname => 'tr-069-1-1', date => '2006-12'},
    'cwmp-1-1.xsd' => {
        comment => 'rpcs', trname => 'tr-069-1-2', date => '2007-12'},
    'cwmp-datamodel-1-0.xsd' => {
        comment => 'dm', trname => 'tr-106-1-2', date => '2008-11'},
    'cwmp-datamodel-1-1.xsd' => {
        comment => 'dm', trname => 'tr-106-1-3', date => '2009-09'},
    'cwmp-datamodel-report.xsd' => {
        comment => 'dmr', date => '2009-09'},
    'cwmp-devicetype-1-0.xsd' => {
        comment => 'dt', trname => 'tr-106-1-3', date => '2009-09'},
    'cwmp-devicetype-features.xsd' => {
        comment => 'dtf', date => '2009-09'},
    'tr-069-biblio.xml' => {
        comment => 'bibref', support => 1},
    'tr-106-1-0-0-types.xml' => {
        comment => 'types', support => 1}
};

my $htmlbbf = [];

# XXX this is effectively copied from html_node; not all styles are used
sub htmlbbf_begin
{
    # styles
    my $table = qq{text-align: left;};
    my $row = qq{vertical-align: top;};
    my $center = qq{text-align: center;};

    # font
    my $h1font = qq{font-family: helvetica,arial,sans-serif; font-size: 14pt;};
    my $h2font = qq{font-family: helvetica,arial,sans-serif; font-size: 12pt;};
    my $h3font = qq{font-family: helvetica,arial,sans-serif; font-size: 10pt;};
    my $font = qq{font-family: helvetica,arial,sans-serif; font-size: 8pt;};

    # others
    my $theader_bg = qq{background-color: rgb(153, 153, 153);};

    print <<END;
<html>
  <head>
    <meta content="text/html; charset=UTF-8" http-equiv="content-type">
    <title>Broadband Forum - CWMP</title>
    <style type="text/css">
      p, li, body { $font }
      h1 { $h1font }
      h2 { $h2font }
      h3 { $h3font }
      table { $table }
      th { $row $font }
      th.g { $row $font $theader_bg }
      td, td.p { $row $font }
      td.pc { $row $font $center }
    </style>
  </head>
  <body>
    <h1>CPE WAN Management Protocol (CWMP)</h1>

    <h1>XML Schemas and Data Model Definitions</h1>

    <div align="center">
      [<a href="#Schema">Schema Files</a>]
      [<a href="#DMS">DM Support</a>]
      [<a href="#DMD">DM Definitions</a>]
      [<a href="cwmp.zip">Directory Contents</a>]
    </div>

    <p/>
    <p>The available XML Schemas and data model definitions for the TR-069
       suite of documents are listed below.</p>
    <p/>
    <p>Note: all the files below are directly reachable via:
       http://www.broadband-forum.org/cwmp/&lt;filename&gt;.</p>

    <a name="Schema"/>
    <h1>Schema Files</h1>
END
    htmlbbf_file('', {header => 1});
    foreach my $file (@$allfiles) {
        htmlbbf_file($file, {schema => 1});
    }
    htmlbbf_file('', {footer => 1});

    print <<END;
    <a name="DMS"/>
    <h1>Data Model Support Files</h1>
END
    htmlbbf_file('', {header => 1});
    foreach my $file (@$allfiles) {
        htmlbbf_file($file, {support => 1});
    }
    htmlbbf_file('', {footer => 1});

    print <<END;
    <a name="DMD"/>
    <h1>Data Model Definitions</h1>
END
    htmlbbf_file('', {header => 1});
    foreach my $file (@$allfiles) {
        htmlbbf_file($file);
    }
    htmlbbf_file('', {footer => 1});

    print <<END;
    </table>
  </body>
</html>
END
}

# dummy (needed in order to indicate that report type is valid)
sub htmlbbf_node
{
}

my $htmlbbf_mnames = {};

sub htmlbbf_file
{
    my ($file, $opts) = @_;

    # table options
    my $tabopts = qq{border="1" cellpadding="2" cellspacing="0"};

    if ($opts->{header}) {
        print <<END;
    <table width="100%" $tabopts>
      <tr>
        <th width="15%">Filename</th>
        <th width="60%">Comment</th>
        <th width="12%">Publication Date</th>
        <th width="13%">Technical Report</th>
      </tr>
END
        return;

    } elsif ($opts->{footer}) {
        print <<END;
    </table>
END
        return;
    }

    my $name = $file->{name};
    my $spec = $file->{spec};
    my $schema = $file->{schema};
    my $models = $file->{models};

    return if  $opts->{schema} && !$schema;
    return if !$opts->{schema} &&  $schema;

    my $info = $htmlbbf_info->{$name};
    my $comment = $info->{comment};
    my $support = $info->{support};
    my $trname = $info->{trname};
    my $date = $info->{date};

    return if  $opts->{support} && !$support;
    return if !$opts->{support} &&  $support;

    my $seen = 0;
    my $mult = 0;
    my $type = 'Root Object';
    my $mnames = '';
    if ($models) {
        foreach my $model (@$models) {
            my $mname = $model->findvalue('@name');
            my $isService = $model->findvalue('@isService');

            $seen = 1 if $htmlbbf_mnames->{$mname};
            $htmlbbf_mnames->{$mname} = 1;

            $mult = 1 if $mnames;

            # XXX assumes that all models in file are Root or Service
            $type = 'Service Object' if $isService;

            $mnames .= ' and ' if $mult;
            $mnames .= $mname;
        }   
    }

    my $def = 'definition' . ($mult ? 's' : '');
    my $err = 'errata and clarifications';

    my ($maj, $min) = $name =~ /-(\d+)-(\d+)\.xsd$/;
    $maj = '?' unless defined $maj;
    $min = '?' unless defined $min;
    my $ver = qq{v${maj}.${min}};

    if (!$comment && !$opts->{schema} && !$opts->{support}) {
        $comment .= $mult ? 'comp' : 'obj';
        $comment .= $seen ? 'err'  : 'def';
    }

    $comment = $comment ? $htmlbbf_comments->{$comment} : 'TBD';
    $comment =~ s/{{name}}/$mnames/;
    $comment =~ s/{{type}}/$type/;
    $comment =~ s/{{def}}/$def/;
    $comment =~ s/{{err}}/$err/;
    $comment =~ s/{{ver}}/$ver/;

    $trname = $spec unless $trname;
    $trname = util_doc_name($trname, {verbose => 1});
    $trname = '&nbsp;' unless $trname;
    
    # XXX not clear where to get the date info from
    if (!$date) {
        $date = 'TBD';
    } else {
        my $months = ['NotAMonth', 'January', 'February', 'March', 'April',
                      'May', 'June', 'July', 'August', 'September', 'October',
                      'November', 'December'];
        my ($year, $month) = $date =~ /(\d+)-(\d+)/;
        $date = qq{$months->[$month] $year};
    }
    
    my $xmllink = qq{cwmp/$name};

    # this is believed to follow the new BBF TR URL standard
    my $trlink = qq{technical/download/${trname}.pdf};
    $trlink =~ s/ (Issue|Amendment|Corrigendum)/_$1/;
    $trlink =~ s/ /-/g;

    # no TR link for support files or if TR name doesn't begin TR (catches
    # unversioned schemas)
    $trlink = qq{<a href="$trlink">$trname</a>};
    $trlink = '&nbsp;' if $support || $trname !~ /^TR/;

    print <<END;
      <tr>
        <td><a href="$xmllink">$name</a></td>
        <td>$comment</td>
        <td>$date</td>
        <td>$trlink</td>
      </tr>
END
}

# HTML "PD-148" report of node.
#
# Similar output to that of PD-148 sections 2 and 3; pass each data model
# on the command line (duplication doesn't matter because no file is ever
# read more than once).

# array containing all info to be reported, in the form:
#
# [{name => model_name,
#   spec => model_spec,
#   profiles => [{name => profile_name,
#                 spec => profile_spec}, ...], ...]
my $html148 = [];

# XXX this is effectively copied from html_node; not all styles are used
sub html148_begin
{
    # styles
    my $table = qq{text-align: left;};
    my $row = qq{vertical-align: top;};
    my $center = qq{text-align: center;};

    # font
    my $h1font = qq{font-family: helvetica,arial,sans-serif; font-size: 14pt;};
    my $h2font = qq{font-family: helvetica,arial,sans-serif; font-size: 12pt;};
    my $h3font = qq{font-family: helvetica,arial,sans-serif; font-size: 10pt;};
    my $font = qq{font-family: helvetica,arial,sans-serif; font-size: 8pt;};

    # others
    my $theader_bg = qq{background-color: rgb(153, 153, 153);};

    # file header and beginning of TOC
    print <<END;
<html>
  <head>
    <meta content="text/html; charset=UTF-8" http-equiv="content-type">
    <title>TR-069 Data Model and Profile Registry</title>
    <style type="text/css">
      p, li, body { $font }
      h1 { $h1font }
      h2 { $h2font }
      h3 { $h3font }
      table { $table }
      th { $row $font }
      th.g { $row $font $theader_bg }
      td, td.p { $row $font }
      td.pc { $row $font $center }
    </style>
  </head>
  <body>
    <h1>Table of Contents</h1>
    <ul>
END
}

sub html148_node
{
    my ($node) = @_;

    my $model = $node->{type} eq 'model';
    return unless $model;

    my $history = $node->{history};
    if ($history && @$history) {
        foreach my $past (reverse @$history) {
            html148_model($node, $past);
        }
    }
    html148_model($node);
}

sub html148_model
{
    my ($node, $past) = @_;

    # node to use for name and spec is $past if defined, else $node
    my $anode = $past ? $past : $node;
    my $name = $anode->{name};
    my $file = $anode->{file};
    my $spec = $anode->{spec};

    # node to use for other attributes is always $node
    my $isService = $node->{isService};
    my $profs = [];
    foreach my $prof (grep {$_->{type} eq 'profile' && 
                      $_->{spec} eq $spec} @{$node->{nodes}}) {
        my $name = $prof->{name};
        my $spec = $prof->{spec};

        push @$profs, {name => $name, spec => $spec};
    }

    push @$html148, {name => $name, file => $file, spec => $spec,
                     isService => $isService, profs => $profs};    
}

sub html148_end
{
    # table options
    my $tabopts = qq{border="1" cellpadding="2" cellspacing="0"};

    # TOC is generated directly; all other output is buffered and output
    # at the bottom
    my $text = '';

    # introductory sections and summary table header
    # XXX can you just put the class on <tr>?
    # XXX not filling in dependencies yet; are they useful?
    print <<END;
      <li><a href="#Overview">Overview</a></li>
      <li><a href="#Data Models">Data Models</a></li>
END
    $text .= <<END;
    <h1><a name="Overview">Overview</a></h1>
    <p>This document is a registry of Broadband Forum standardized TR-069 data models and profiles.  This document is intended to catalog all versions of data models and profiles defined in Broadband Forum Technical Reports.</p>
    <h1><a name="Data Models">Data Models</a></h1>
    <p>The following table lists all data model versions defined in Broadband Forum Technical Reports.</p>
    <table width="100%" $tabopts>
      <tbody>
        <tr>
          <th class="g">Object Name</th>
          <th class="g">Object Type</th>
          <th class="g">Version</th>
          <th class="g">Version Update</th>
          <th class="g">Update Type</th>
          <th class="g">Technical Report</th>
          <!-- <th class="g">Dependencies</th> -->
        </tr>
END

    # summary table rows
    my $rows = [];
    my $mrows = {};
    foreach my $model (@$html148) {
        my $name = $model->{name};
        my $file = $model->{file};
        my $spec = $model->{spec};
        my $rootserv = $model->{isService} ? 'Service' : 'Root'; 

        my ($name_only, $version) = ($name =~ /([^:]*):(.*)/);
        my $tr_name = util_doc_name($spec, {verbose => 1});
        my $dependencies = 'dependencies';

        my $nrow = {name => $name_only,
                    file => $file,
                    type => $rootserv,
                    version => $version,
                    tr_name => $tr_name,
                    dependencies => $dependencies,
                    mrowspan => 0};

        # mrow is the first row for this data model
        my $mrow = $mrows->{$nrow->{name}};
        $mrow = $nrow if !$mrow || $nrow->{name} ne $mrow->{name};
        $nrow->{mrow} = $mrow;
        $mrow->{mrowspan}++;
        $mrows->{$nrow->{name}} = $mrow;

        push @$rows, $nrow;
    }

    print <<END;
      <ul>
END
    my $first = 1;
    foreach my $row (@$rows) {
        my $mrowspan = $row->{mrowspan};
        my $moc = $mrowspan ? '' : '<!-- ';
        my $mcc = $mrowspan ? '' : ' -->';

        if ($row == $row->{mrow}) {
            print <<END;
        <li><a href="#D:$row->{name}">$row->{name}</a></li>
END

            # XXX hacked separator row
            if (!$first) {
                $text .= <<END;
        <tr>
          <td colspan="6"></td>
        </tr>
END
            }
            $first = 0;
        }

        # XXX hack: we currently KNOW that 143 and 157 define both root
        #     objects so the HTML includes "-dev" or "-igd"
        my $htmlsuff =
            $row->{file} !~ /^tr-(143|157)/ ? '' :
            $row->{name} =~ /^Internet/ ? '-igd' :
            $row->{name} =~ /^Device/ ? '-dev' : '';

        my $version = $row->{version};
        my $version_entry = qq{<a href="cwmp/$row->{file}.xml">$version</a>};

        my $version_update = $version eq '1.0' ? 'Initial' :
            $version =~ /^\d+\.0$/ ? 'Major' : 'Minor';
        my $version_update_entry =
            qq{<a href="cwmp/$row->{file}$htmlsuff.html">$version_update</a>};

        # XXX not quite the same as in PD-148 because ALL XML minor versions
        #     are incremental (not worth keeping this column?)
        my $update_type = $version_update eq 'Initial' ? '-' :
            $version_update eq 'Major' ? 'Replacement' : 'Incremental';
        my $update_type_entry = $update_type eq '-' ? '-' :
            qq{<a href="cwmp/$row->{file}$htmlsuff-last.html">$update_type</a>};

        $text .= <<END;
        <tr>
          $moc<td rowspan="$mrowspan"><a name="D:$row->{name}">$row->{name}</a></td>$mcc
          $moc<td rowspan="$mrowspan">$row->{type}</td>$mcc
          <td>$version_entry</td>
          <td>$version_update_entry</td>
          <td>$update_type_entry</td>
          <td>$row->{tr_name}</td>
          <!-- <td>$row->{dependencies}</td> -->
        </tr>
END
    }
    print <<END;
      </ul>
END

    # end of summary table and profile table header
    print <<END;
      <li><a href="#Profiles">Profiles</a></li>
      <ul>
END
    $text .= <<END;
      </tbody>
    </table>
    <h1><a name="Profiles">Profiles</a></h1>
    <p>The following table lists all data model profiles defined in Broadband Forum Technical Reports.</p>
    <table width="100%" $tabopts>
      <tbody>
        <tr>
          <th class="g">Data Model</th>
          <th class="g">Profile Name</th>
          <th class="g">Profile Version</th>
          <th class="g">Min Data Model Version</th>
          <th class="g">Technical Report(s)</th>
        </tr>
END

    # profile table rows
    $rows = [];
    $mrows = {};
    my $prows = {};
    foreach my $model (@$html148) {
        my $mname = $model->{name};
        my $spec = $model->{spec};
        my $profs = $model->{profs};

        my ($mname_only, $mversion_major, $mversion_minor) =
            ($mname =~ /([^:]*):(\d+)\.(\d+)/);

        foreach my $prof (@$profs) {
            my $name = $prof->{name};
            my $spec = $prof->{spec};

            my ($name_only, $version) = ($name =~ /([^:]*):(.*)/);
            my $tr_name = util_doc_name($spec, {verbose => 1});

            my $nrow = {model => qq{$mname_only:$mversion_major},
                        prof => $name_only,
                        prof_version => $version,
                        model_version => qq{$mversion_major.$mversion_minor},
                        tr_name => $tr_name,
                        mrowspan => 0,
                        prow => undef, prowspan => 0};

            # mrow is the first row for this data model
            my $mrow = $mrows->{$nrow->{model}};
            $mrow = $nrow if !$mrow || $nrow->{model} ne $mrow->{model};
            $nrow->{mrow} = $mrow;
            $mrow->{mrowspan}++;
            $mrows->{$nrow->{model}} = $mrow;

            # prow is the first row for this data model and profile
            my $prow = $prows->{$nrow->{model}}->{$nrow->{prof}};
            $prow = $nrow if !$prow || $nrow->{prof} ne $prow->{prof};
            $nrow->{prow} = $prow;
            $prow->{prowspan}++;
            $prows->{$nrow->{model}}->{$nrow->{prof}} = $prow;

            # insert after previous profile for this model, if any, else
            # at the end
            my $index;
            for (0 .. @$rows-1) {
                my $row = @$rows[$_];
                $index = $_ + 1 if $row->{model} eq $nrow->{model} &&
                    $row->{prof} eq $nrow->{prof};
            }
            $index = @$rows unless defined $index;
            splice @$rows, $index, 0, $nrow;
        }
    }

    $first = 1;
    foreach my $row (@$rows) {
        my $mrowspan = $row->{mrowspan};
        my $moc = $mrowspan ? '' : '<!-- ';
        my $mcc = $mrowspan ? '' : ' -->';
        my $prowspan = $row->{prowspan};
        my $poc = $prowspan ? '' : '<!-- ';
        my $pcc = $prowspan ? '' : ' -->';

        if ($row == $row->{mrow}) {
            print <<END;
        <li><a href="#P:$row->{model}">$row->{model}</a></li>
END
            # XXX hacked separator row
            if (!$first) {
                $text .= <<END;
        <tr>
          <td colspan="5"></td>
        </tr>
END
            }
            $first = 0;
        }

# XXX suppress the individual profile entries in the TOC (there are too many
#     of them
#        if ($row == $row->{prow}) {
#            print <<END;
#        <ul><li><a href="#P:$row->{model}.$row->{prof}">$row->{prof}</a></li></ul>
#END
#        }

        $text .= <<END;
        <tr>
          $moc<td rowspan="$mrowspan"><a name="P:$row->{model}">$row->{model}</a></td>$mcc
          $poc<td rowspan="$prowspan"><a name="P:$row->{model}.$row->{prof}">$row->{prof}</a></td>$pcc
          <td>$row->{prof_version}</td>
          <td>$row->{model_version}</td>
          <td>$row->{tr_name}</td>
        </tr>
END
    }
    print <<END;
      </ul>
    </ul>
END

    # end of profile table and document
    $text .= <<END;
      </tbody>
    </table>
  </body>
</html>
END

    # output document body
    print $text;
}

# Excel report of node.
sub xls_node
{
    my ($node, $indent) = @_;

    # use indent as a first-time flag
    # (assume that first line describes the model)
    if (!$indent) {
	my $title = $node->{name};
	$title .= " ($objpat)" if $objpat ne '';
        # XXX worksheet names can't contain ":" (altho' the schema permits it)
        $title =~ s/:/ /g;
	my $lstyle = 'Header';
	my $cstyle = 'HeaderCenter';
	print <<END;
 <Worksheet ss:Name="$title (model)">
  <Table>
   <Column ss:Width="120"/> <!-- Name -->
   <Column ss:Width="60"/>  <!-- Type -->
   <Column ss:Width="30"/>  <!-- Write -->
   <Column ss:Width="300"/> <!-- Description -->
   <!-- <Column ss:Width="120"/> --> <!-- Values -->
   <Column ss:Width="40"/>  <!-- Object Default -->
   <Column ss:Width="40"/>  <!-- Version -->
   <Column ss:Width="50"/>  <!-- Spec -->
   <Row>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">Name</Data></Cell>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">Type</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">Write</Data></Cell>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">Description</Data></Cell>
    <!-- <Cell ss:StyleID="$lstyle"><Data ss:Type="String">Values</Data></Cell> -->
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">Object Default</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">Version</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">Spec</Data></Cell>
   </Row>
END
    }

    my $auto = $node->{auto};
    if ($indent && !$auto) {
	my $object = ($node->{type} eq 'object');
	my $name = xls_escape($object ? $node->{path} : $node->{name});
	my $spec = xls_escape($node->{spec});
	my $type = xls_escape(type_string($node->{type}, $node->{syntax}));
	my $write = xls_escape($node->{access} ne 'readOnly' ? 'W' : '-');
        # is escaped later
	my $description = add_values($node->{description},
                                     get_values($node->{values}));
	my $values = ''; #xls_escape(get_values($node->{values}));
	my $default =  xls_escape($node->{default});
	my $version =
	    xls_escape(version($node->{majorVersion}, $node->{minorVersion}));
        my $descact = xls_escape($node->{descact});
	($description, $descact) = remove_descact($description, $descact);
        $description = xls_escape($description);

	my $lstyle = $object ? 'Object' : 'Default';
	my $cstyle = $lstyle . 'Center';

	print <<END;
   <Row>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">$name</Data></Cell>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">$type</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">$write</Data></Cell>
    <Cell ss:StyleID="$lstyle"><Data ss:Type="String">$description</Data></Cell>
    <!-- <Cell ss:StyleID="$lstyle"><Data ss:Type="String">$values</Data></Cell> -->
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">$default</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">$version</Data></Cell>
    <Cell ss:StyleID="$cstyle"><Data ss:Type="String">$spec</Data></Cell>
   </Row>
END
    }
    
    foreach my $child (@{$node->{nodes}}) {
	my $object = ($child->{type} eq 'object');
	xls_node($child, 1) unless $object;
    }
    foreach my $child (@{$node->{nodes}}) {
	my $object = ($child->{type} eq 'object');
	xls_node($child, 1) if $object;
    }
    
    if (!$indent) {
	print <<END;
  </Table>
 </Worksheet>
END
    }
}

sub xls_end
{
    print <<END;
</Workbook>
END
}

# Escape a value suitably for exporting as Excel XML.
sub xls_escape {
    my ($value) = @_;

    $value = util_default($value);

    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    # XXX should do this for all report types; should also use appropriate
    #     string sub-type to get appropriate white space treatment
    $value =~ s/^\n[ \t]*//;
    $value =~ s/\n[ \t]*/\n/g;
    $value =~ s/\n$//;

    $value =~ s/\n/\&#10;\&#10;/g;
    # XXX but not when separating enumerations (very heuristic)
    $value =~ s/\&#10;(\&#10;\* \")/$1/g;

    # XXX poor man's list
    $value =~ s/\&#10;\"/\&#10;    \"/g;

    return $value;
}

# W3C schema report of node.
# XXX makes all sorts of arbitrary assumptions
my $xsd_flag = 0;

sub xsd_begin
{
    print qq{<?xml version="1.0"?>\n};
}

sub xsd_node
{
    my ($node, $indent) = @_;

    my $object = ($node->{type} eq 'object');
    my $name = xsd_escape($node->{name});
    my $description = $node->{description};

    # XXX taken from xls_escape; should do more generically
    $description =~ s/^\n[ \t]*//;
    $description =~ s/\n[ \t]*/\n/g;
    $description =~ s/\n$//;
    my $documentation = xsd_escape(type_string($node->{type}, $node->{syntax}) .
				   ' (' . ($node->{access} ne 'readOnly' ? 'W' : 'R') . ')' .
				   "\n" .
				   add_values($description,
					      get_values($node->{values})));

    # XXX taken from xls_escape; should do more generically
    $documentation =~ s/^\n[ \t]*//;
    $documentation =~ s/\n[ \t]*/\n/g;
    $documentation =~ s/\n$//;

    if ($xsd_flag) {
	print STDERR "ignored second and subsequent data model: " .
	    "$node->{name}\n";

    } elsif (!$indent) {
	print qq{<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"\n};
	print qq{           elementFormDefault="qualified"\n};
	print qq{           attributeFormDefault="unqualified">\n};
	foreach my $child (@{$node->{nodes}}) {
	    xsd_node($child, 1);
	}
	print qq{</xs:schema>\n};
	$xsd_flag = 1;

    } elsif ($object) {
	my $minEntries = $indent > 1 ? qq{ minEntries="0"} : qq{};
	print "  "x$indent . qq{<xs:element name="$name"$minEntries>\n};
        print "  "x$indent . qq{  <xs:annotation>\n};
        print "  "x$indent . qq{    <xs:documentation>$documentation</xs:documentation>\n};
        print "  "x$indent . qq{  </xs:annotation>\n};
	print "  "x$indent . qq{  <xs:complexType>\n};
	# XXX did have maxEntries="unbounded" here (allows order not to be
	#     significant, but also allows duplication)
	print "  "x$indent . qq{    <xs:sequence minEntries="0">\n};
	foreach my $child (@{$node->{nodes}}) {
	    xsd_node($child, $indent + 3);
	}
	print "  "x$indent . qq{    </xs:sequence>\n};
	print "  "x$indent . qq{  </xs:complexType>\n};
	print "  "x$indent . qq{</xs:element>\n};

    } else {
	my $minEntries = $indent > 1 ? qq{ minEntries="0"} : qq{};
	print "  "x$indent . qq{<xs:element name="$name"$minEntries>\n};
        print "  "x$indent . qq{  <xs:annotation>\n};
        print "  "x$indent . qq{    <xs:documentation>$documentation</xs:documentation>\n};
        print "  "x$indent . qq{  </xs:annotation>\n};
	print "  "x$indent . qq{</xs:element>\n};
    }    
}

sub xsd_end {}

# Escape a value suitably for exporting as W3C XSD.
# XXX currently used only for names
sub xsd_escape {
    my ($value) = @_;

    $value = util_default($value);

    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    # XXX should use table syntax
    $value =~ s/\{i\}/i/g;

    # XXX this is for profile names
    $value =~ s/:/_/g;

    # remove trailing dot
    $value =~ s/\.$//;

    $value = util_lines($value);

    return $value;
}

# special report of node.
my $special_object = '';
my $special_profile = '';
my $special_profiles = {};
my $special_newitems = [];
my $special_items = [];

sub special_node
{
    my ($node, $pnode) = @_;

    my $type = $node->{type};
    my $path = $node->{path};
    my $name = $node->{name};
    my $majorVersion = $node->{majorVersion} || 0;
    my $minorVersion = $node->{minorVersion} || 0;

    # check for new profile
    if ($type eq 'profile') {
        $special_profile = $name;
    }

    # collect current profile definition
    elsif ($special_profile) {
        if ($type eq 'objectRef') {
            $special_object = $name;
            $special_profiles->{$special_profile}->{$special_object} = 1;
        } else {
            $special_profiles->{$special_profile}->{$special_object.$name} = 1;
        }
    }

    # make a list of all items added at the highest encountered version
    elsif ($majorVersion == $highestMajor && $minorVersion == $highestMinor) {
        push @$special_newitems, $node;
    }

    # unconditionally collect a list of all items
    # XXX should include values too but these don't currently support the
    #     same interface
    push @$special_items, $node;
}

sub special_end
{
    # deprecated/obsoleted: for each profile item (object, parameter) report
    # if it is deprecated or obsoleted
    if ($special =~ /deprecated|obsoleted/) {
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            next unless $path; # profile items have no path
            if ($item->{status} &&
                $item->{status} =~ /$special/) {
                print STDERR "$path\n" if $verbose;
                my $found = [];
                # XXX could check just new profiles?
                foreach my $profile (keys %$special_profiles) {
                    print STDERR "  checking $profile\n" if $verbose;
                    if ($special_profiles->{$profile}->{$path}) {
                        print STDERR "  found in $profile\n" if $verbose;
                        push @$found, $profile;
                    }
                }
                if (@$found) {
                    print "$path\t" . join(",", @$found) . "\n";
                }            
            }
        }
    }

    # nonascii: for each item (model, object, parameter, value or profile),
    # report use of non-ASCII characters
    # XXX really should simply check all instances of the "description"
    #     element
    elsif ($special eq 'nonascii') {
        # ref. TR-106a2 A.2.2.1: ASCII range 9-10 and 32-126
        my $patt = q{[^\x09-\x0a\x20-\x7e]};
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            #next unless $path; # profile items have no path
            my $description = $item->{description};
            next unless $description; # some parameters and objects omit it
            $description =~ s/\s+/ /g;
            if ($description =~ /$patt/) {
                $description =~ s/($patt)/**$1**/g;
                print "$path\t$description\n";
            }
        }
    }

    # normative: for each item (model, object, parameter, value or profile),
    # report use of lower-case normative language
    # XXX really should simply check all instances of the "description"
    #     element
    elsif ($special eq 'normative') {
        # also check for 'MAY NOT', which should NEVER be used
        my $terms = ['(M|m)ust( not)?', '(R|r)equired', '(S|s)hall( not)?',
                     '(S|s)hould( not)?', '(R|r)ecommended', '(M|m)ay( not)?',
                     '(O|o)ptional', '(D|d)eprecated', '(O|o)obsoleted',
                     'MAY NOT'];
        my $patt = '';
        foreach my $term (@$terms) {
            $patt .= qq{|} if $patt;
            $patt .= qq{\\b$term\\b};
        }
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            #next unless $path; # profile items have no path
            my $description = $item->{description};
            next unless $description; # some parameters and objects omit it
            $description =~ s/\s+/ /g;
            if ($description =~ /$patt/) {
                foreach my $term (@$terms) {
                    $description =~ s/\b($term)\b/**$1**/g;
                }
                print "$path\t$description\n";
            }
        }
    }

    # notify: for each new parameter, check whether it is read-only and in
    # the "can deny active notify" table; report those which aren't
    elsif ($special eq 'notify') {
        foreach my $item (@$special_newitems) {
            my $type = $item->{type};
            next if $type =~ 'model|object|profile';
            my $path = $item->{path};
            my $access = $item->{access};
            my $activeNotify = $item->{activeNotify};
            print STDERR "$path\n" if $verbose;
            print "$path\n"
                if $access eq 'readOnly' && $activeNotify ne 'canDeny';
        }
    }

    # profile: for each new parameter, check whether it is in a profile;
    # report those which aren't
    elsif ($special eq 'profile') {
        foreach my $item (@$special_newitems) {
            my $type = $item->{type};
            next if $type =~ 'model|object|profile';
            my $path = $item->{path};
            print STDERR "$path\n" if $verbose;
            my $found = 0;
            foreach my $profile (keys %$special_profiles) {
                if ($special_profiles->{$profile}->{$path}) {
                    print STDERR "  found in $profile\n" if $verbose;
                    $found = 1;
                    last;
                }
            }
            unless ($found) {
                print "$path\n";
            }
        }
    }

    # rfc: for each item (model, object, parameter, value or profile),
    # report RFCs without references
    # XXX really should simply check all instances of the "description"
    #     element
    elsif ($special eq 'rfc') {
        my $patt = '(RFC\s*[0-9]++)(\s?[^\s\[])';
        my $rfcs = {};
        foreach my $item (@$special_items) {
            my $path = $item->{path};
            next unless $path; # profile items have no path
            my $description = $item->{description};
            next unless $description; # some parameters and objects omit it
            $description =~ s/\s+/ /g;
            if ($description =~ /$patt/) {
                $description =~ s/$patt/**$1**$2/g;
                my $rfc = $1;
                $rfc =~ s/RFC([^ ])/RFC $1/;
                $rfcs->{$rfc} = 1;
                print "$path\t$description\n";
            }
        }
        print join(",", sort(keys %$rfcs)) . "\n";
    }

    # invalid
    else {
        print STDERR "$special: invalid special option\n";
    }
}

# Heuristic insertion of blank lines
sub util_lines
{
    my ($inval) = @_;

    my $outval = '';
    my @lines = split /\n/, $inval;
    my $last = pop @lines;
    my $prevstar = 0;
    foreach my $line (@lines) {
	my $star = $line =~ /^\*/;
	$outval .= "\n" if $prevstar && !$star;
	$outval .= $line;
	$outval .= "\n" unless $star;
	$outval .= "\n";
	$prevstar = $star;
    }
    $outval .= $last if $last;
    return $outval;
}

# Set value to "-" (or supplied default) if undefined or to "<Empty>" (or
# supplied value) if defined and empty
sub util_default {
    my ($value, $default, $empty) = @_;

    if (!defined $value) {
        $value = defined $default ? $default : '-';
    } elsif ($value eq '') {
        $value = defined $empty ? $empty : '<Empty>';
    }

    return $value;
}

# Convert list to string of the form "a, b and c", optionally supplying
# template containing "$1" to be substituted for each item.
sub util_list
{
    my ($list, $template) = @_;

    $template = qq{\$1} unless $template;

    my $i = 0;
    my $text = qq{};
    foreach my $item (@$list) {
        $text .= (($i < @$list - 1) ? ', ' : ' and ') if $i > 0;
        my $temp = $template;
        $temp =~ s/\$1/$item/g;
        $text .= $temp;
        $i++;
    }

    return $text;
}

# Return all the historical values of a node's specified attribute
sub util_history_values
{
    my ($node, $attr) = @_;

    my $history = $node->{history};

    my $list = [];

    if ($history) {
        foreach my $item (reverse @$history) {
            push @$list, $item->{$attr};
        }
    }

    push @$list, $node->{$attr};

    return $list;
}

# Copy of all elements of a hash except for those explicitly excluded
sub util_copy
{
    my ($in, $not) = @_;

    my $out = {};
    foreach my $key (keys %$in) {
        $out->{$key} = clone($in->{$key}) unless grep {$_ eq $key} @$not;
    }

    return $out;
}

# Determine differences between two strings
sub util_diffs
{
    my ($old, $new) = @_;
    
    my @old = split "\n", $old;
    my @new = split "\n", $new;
    my $diff = Algorithm::Diff->new(\@old, \@new);
    my $diffs = '';
    while($diff->Next()) {
        next if  $diff->Same();
        my $sep = '';
        if (!$diff->Items(2)  ) {
            $diffs .=
                sprintf("%d,%dd%d\n", $diff->Get(qw(Min1 Max1 Max2)));
        } elsif (!$diff->Items(1)) {
            $diffs .=
                sprintf("%da%d,%d\n", $diff->Get(qw(Max1 Min2 Max2)));
        } else {
            # XXX XML comment can't contain "--" (or "---")
            $sep = "===\n";
            $diffs .= sprintf("%d,%dc%d,%d\n",
                              $diff->Get(qw(Min1 Max1 Min2 Max2)));
        }
        # XXX these have to be escaped in the XML (better presentation?)
        $diffs .= "- $_\n" for $diff->Items(1);
        $diffs .= $sep;
        $diffs .= "+ $_\n" for $diff->Items(2);
    }
    return $diffs;
}

# Convert spec to document name
sub util_doc_name
{
    my ($spec, $opts) = @_;

    my $verbose = $opts->{verbose};

    # XXX not sure quite why it's ever blank; something to do with profiles?
    return $spec unless $spec;

    # urn:broadband-forum-org:rest -> rest
    my $text = $spec;
    $text =~ s/.*://;

    # support names of form name-i-a[-c][label] where name is of the form
    # "cat-n", i, a and c are numeric and label can't begin with a digit
    my ($cat, $n, $i, $a, $c, $label) =
        $text =~ /^([^-]+)-(\d+)-(\d+)?-(\d+)(?:-(\d+))?(-\D.*)?$/;

    # if doesn't match, apply heuristics
    if (!$cat) {
        return uc $text;
    }
    
    $text = '';
    if ($cat =~ /^(dsl|bbf)$/) {
        $text .= qq{$cat};
        $text .= qq{$n}; # year
        $i = 0 unless defined $i;
        $text .= sprintf(".%.3d", $i); # number
        $a = 0 unless defined $a;
        $text .= sprintf(".%.2d", $a); # version
        # $c and $label are ignored
    } elsif ($cat =~ /tr/i) {
        $cat = uc $cat;
        $text .= qq{$cat-$n};
        $text .= $verbose ? qq{ Issue $i} : qq{i$i} if defined $i && $i > 1;
        $text .= $verbose ? qq{ Amendment $a} : qq{a$a} if $a;
        $text .= $verbose ? qq{ Corrigendum $c} : qq{c$c} if $c;
        # $label is ignored
    } else {
        $cat = uc $cat;
        $text .= qq{$cat-$n};
        $text .= qq{v$i} if defined $i && $i > 1; # version
        $text .= sprintf("_Rev-%.2d", $a) if $a; # revision (major)
        $text .= qq{.$c} if $c; # revision (minor)
        # $label is ignored
    }

    return $text;
}

# Delete deprecated or obsoleted items if $deletedeprecated
sub util_maybe_deleted
{
    my ($status) = @_;

    $status = 'deleted'
        if $deletedeprecated && $status =~ /deprecated|obsoleted/;

    return $status;
}

# Determine whether a node has been deleted
sub util_is_deleted
{
    my ($node) = @_;

    for (; $node; $node = $node->{pnode}) {
        if ($node->{status} && $node->{status} eq 'deleted') {
            return 1;
        }
    }

    return 0;
}

# Expand all data model definition files.
foreach my $file (@ARGV) {
    expand_toplevel($file);
}

# Perform sanity checks etc, e.g. prune empty objects if --writonly
# XXX should be using the standard report_node framework?
sub sanity_node
{
    my ($node) = @_;

    # no warnings for deleted items
    return if util_is_deleted($node);

    my $path = $node->{path};
    my $name = $node->{name};
    my $type = $node->{type};
    my $hidden = $node->{hidden};
    my $access = $node->{access};
    my $status = $node->{status};
    my $syntax = $node->{syntax};
    my $values = $node->{values};
    my $default = $node->{default};
    my $deftype = $node->{deftype};
    my $dynamic = $node->{dynamic};
    my $minEntries = $node->{minEntries};
    my $maxEntries = $node->{maxEntries};
    my $numEntriesParameter = $node->{numEntriesParameter};
    my $enableParameter = $node->{enableParameter};
    my $description = $node->{description};

    # XXX not sure that I should have to do this (is needed for auto-created
    #     objects, for which minEntries and maxEntries are undefined)
    $minEntries = '1' unless defined $minEntries;
    $maxEntries = '1' unless defined $maxEntries;

    my $object = ($type && $type eq 'object');
    my $parameter = ($type &&
                     $type !~ /model|object|profile|parameterRef|objectRef/);
    my $profile = ($type && $type eq 'profile');

    $default = undef
        if defined $node->{defstat} && $node->{defstat} eq 'deleted';
    my $udefault = util_default($default);

    # prune empty objects if --writonly
    if ($object && $writonly) {
	# XXX need actually to prune such nodes; for now set type to '',
	#     which isn't clever enough (need to do bottom up or multi pass)
	$node->{type} = '' unless $node->{nodes};
    }

    # object / parameter sanity checks
    if ($object || $parameter) {
        my $objpar = $object ? 'object' : 'parameter';
        print STDERR "$path: $objpar has empty description\n"
            if $pedantic > 1 && defined($description) && $description eq '';
        # XXX should check all descriptions, not just obj / par ones (now
        #     better: checking enumeration descriptions)
        my $ibr = invalid_bibrefs($description);
        print STDERR "$path: invalid bibrefs: " . join(', ', @$ibr) . "\n" if
            @$ibr;
        foreach my $value (keys %$values) {
            my $cvalue = $values->{$value};

            my $description = $cvalue->{description};
            my $ibr = invalid_bibrefs($description);
            print STDERR "$path: invalid bibrefs: " . join(', ', @$ibr) .
                "\n" if @$ibr;
        }
    }

    # object sanity checks
    # XXX for DT, need to check that things are not only defined but are not
    #     hidden
    if ($object) {
        my $ppath = $node->{pnode}->{path};

        print STDERR "$path: object is writable but not a table\n" if
            $access ne 'readOnly' && $maxEntries eq '1';

        print STDERR "$path: object is not writable and multi-instance but " .
            "has enableParameter\n" if
            !($access ne 'readOnly' && $maxEntries eq 'unbounded') &&
            $enableParameter;

        print STDERR "$path: enableParameter ($enableParameter) doesn't ".
            "exist\n"
            if $enableParameter && !$parameters->{$path.$enableParameter};

        # XXX this is questionable use of "hidden" (TR-196?)
        my $temp = $numEntriesParameter || '';
        $numEntriesParameter = $parameters->{$ppath.$numEntriesParameter} if
            $numEntriesParameter;
        if (($maxEntries eq 'unbounded' || 
             ($maxEntries > 1 && $maxEntries > $minEntries)) &&
            (!$numEntriesParameter ||
             (!$hidden && $numEntriesParameter->{hidden}))) {
            print STDERR "$path: missing or invalid numEntriesParameter ".
                "($temp)\n";
            # XXX should filter out only parameters (use grep)
            print STDERR "\t" .
                join(", ", map {$_->{name}} @{$node->{pnode}->{nodes}}) . "\n"
                if $pedantic > 2;
        }

        # XXX old test for enableParameter considered "hidden"; why?
        #$enableParameter =
        #    $parameters->{$path.$enableParameter} if $enableParameter;
        #(!$enableParameter || (!$hidden && $enableParameter->{hidden}))

        print STDERR "$path: missing enableParameter\n" if
            $access ne 'readOnly' && $maxEntries eq 'unbounded' &&
            @{$node->{uniqueKeys}} && !$enableParameter;

        # XXX could be cleverer re checking for read-only / writable unique
        #     keys
        print STDERR "$path: no unique keys are defined\n" if
            $pedantic && ($maxEntries eq 'unbounded' || $maxEntries > 1) &&
            !$node->{noUniqueKeys} && !@{$node->{uniqueKeys}};
    }

    # parameter sanity checks
    if ($parameter) {
        # XXX this one is useless
	#print STDERR "$path: parameter is an enumeration but has " .
	#    "no values\n" if $pedantic && values_appropriate($name, $type) &&
	#    !has_values($values);

        # XXX this isn't always an error; depends on whether table entries
        #     correspond to device configuration
        print STDERR "$path: writable parameter in read-only table\n" if
            $pedantic > 1 && $access ne 'readOnly' &&
            defined $node->{pnode}->{access} &&
            $node->{pnode}->{access} eq 'readOnly' &&
            defined $node->{pnode}->{maxEntries} &&
            $node->{pnode}->{maxEntries} eq 'unbounded' &&
            !$node->{pnode}->{fixedObject};

        # XXX should also check that it's legal for the data type, e.g. a
        #     valid integer
	print STDERR "$path: default $udefault is not one of the enumerated " .
	    "values\n" if $pedantic && defined $default &&
            !($syntax->{list} && $default eq '') && has_values($values) &&
            !has_value($values, $default);

	print STDERR "$path: default $udefault is inappropriate\n"
            if $pedantic && defined($default) && $default =~ /\<Empty\>/i;

	print STDERR "$path: string parameter has no maximum " .
	    "length specified\n" if $pedantic > 1 &&
	    maxlength_appropriate($path, $name, $type) &&
            !has_values($values) && !$syntax->{maxLength};

	print STDERR "$path: enumeration has unnecessary maximum " .
	    "length specified\n" if $pedantic > 1 &&
	    maxlength_appropriate($path, $name, $type) &&
            has_values($values) && $syntax->{maxLength};

        # XXX why the special case for lists?
	print STDERR "$path: parameter within static object has " .
		"a default value\n" if $pedantic && !$dynamic &&
                defined($default) && $deftype eq 'object' &&
                !($syntax->{list} && $default eq '');

	# XXX other checks to make: profiles reference valid parameters,
	#     reference types, default is valid for type, other facets are
        #     valid for type (valid narrowing checks could be done here too,
        #     but would need to use history)
    }

    # profile sanity checks
    if ($profile) {
        foreach my $path (sort keys %{$node->{errors}}) {
            print STDERR "profile $name references invalid $path\n";
        }
    }

    foreach my $child (@{$node->{nodes}}) {
	sanity_node($child);
    }    
}

if ($root->{bibliography}) {
    foreach my $reference (sort {$a->{id} cmp $b->{id}}
                           @{$root->{bibliography}->{references}}) {
        my $id = $reference->{id};
        my $spec = $reference->{spec};
        
        next if ($spec ne $lspec);    
        print STDERR "reference $id not used\n" unless $bibrefs->{$id};
    }
}
            
sanity_node($root);

# Report top-level nodes.
# XXX probably want to output fully expanded XML file of the same format as
#     the input file (i.e. just object and parameter definitions)
# XXX now that report_node is called for the root node too, can dispense with
#     _begin and _end and use _node (indent=0) and _post (indent=0)
# XXX currently doesn't work for all report types (haven't updated them all for
#     the new interface)
# XXX need to re-think "hidden" versus use of "lspec"
"${report}_begin"->($root) if defined &{"${report}_begin"};
report_node($root);
"${report}_end"->($root) if defined &{"${report}_end"};

sub report_node
{    
    my $node = shift;
    return if $node->{hidden};

    if ($lastonly) {
        return if $node->{type} =~ 'model|profile' && $node->{spec} ne $lspec;
        return if $node->{type} !~ 'model|profile' && $node->{lspec} &&
            $node->{lspec} ne $lspec;
    }

    my $indent = shift;
    $indent = 0 unless $indent;

    unshift @_, $node, $indent;
    "${report}_node"->(@_);
    shift; shift;

    $indent++;

    # always report parameter children before other types of children
    # XXX really shouldn't overload type in this way

    foreach my $child (@{$node->{nodes}}) {
        unshift @_, ($child, $indent);
	report_node(@_) if
            (!$nomodels && $child->{type} !~ /^(model|object|profile|objectRef|parameterRef)$/) ||
            (!$noprofiles && $child->{type} =~ /^parameterRef$/);
        shift; shift;
    }

    # XXX it's convenient to have a hook that is called after the parameter
    #     children and before the object children, e.g. where the report does
    #     not nest objects (need to integrate this properly)
    unshift @_, $node, $indent;
    "${report}_postpar"->(@_) if
        $node->{type} =~ /^object/ && defined &{"${report}_postpar"};
    shift; shift;

    foreach my $child (@{$node->{nodes}}) {
        unshift @_, ($child, $indent);
	report_node(@_) if
            (!$nomodels && $child->{type} =~ /^(model|object)$/) ||
            (!$noprofiles && $child->{type} =~ /^(model|profile|objectRef)$/);
        shift; shift;
    }

    $indent--;

    unshift @_, $node, $indent;
    "${report}_post"->(@_) if defined &{"${report}_post"};
    shift; shift;
}

# Count total number of occurrences of each spec
my $spectotal = {};

sub spec_node
{
    my ($node, $indent) = @_;

    # XXX don't count root node (it confuses people, e.g. me)
    # XXX this gives the wrong answer for "xml2" output
    $spectotal->{$node->{spec}}++ if $indent && $node->{spec};
}

# XXX would be nice to avoid use of the global variable here (just pass
#     the report type as the first argument!)
$report = 'spec';
report_node($root);

foreach my $spec (sort @$specs) {
    print STDERR "$spec: $spectotal->{$spec}\n" if
        defined $spectotal->{$spec} && !$quiet;
}

# documentation
=head1 NAME

report.pl - generate report on TR-069 DM instances (data model definitions)

=head1 SYNOPSIS

B<report.pl> [--autobase] [--autodatatype] [--canonical] [--components] [--debugpath=pattern("")] [--deletedeprecated] [--dtprofile=s]... [--dtspec[=s]] [--help] [--ignore=pattern("")] [--importsuffix=string("")] [--include=d]... [--info] [--lastonly] [--marktemplates] [--noautomodel] [--nocomments] [--nohyphenate] [--nolinks] [--nomodels] [--noobjects] [--noparameters] [--noprofiles] [--notemplates] [--nowarnredef] [--nowarnprofbadref] [--objpat=pattern("")] [--pedantic[=i(1)]] [--quiet] [--report=html|(null)|tab|text|xls|xml|xml2|xsd] [--showspec] [--showsyntax] [--special=deprecated|nonascii|normative|notify|obsoleted|profile|rfc] [--thisonly] [--ugly] [--upnpdm] [--verbose[=i(1)]] [--warnbibref[=i(1)]] [--writonly] DM-instance...

=over

=item * cannot specify both --report and --special

=back

=head1 DESCRIPTION

The files specified on the command line are assumed to be XML TR-069 data model definitions compliant with the I<cwmp:datamodel> (DM) XML schema.

The script parses, validates (ahem) and reports on these files, generating output in various possible formats to I<stdout>.

There are a large number of options but in practice only a few need to be used.  For example:

./report.pl --pedantic --report html tr-098-1-2-0.xml >tr-098-1-2-0.html

=head1 OPTIONS

=over

=item B<--autobase>

causes automatic addition of B<base> attributes when models, parameters and objects are re-defined, and suppression of redefinition warnings (useful when processing auto-generated data model definitions)

=item B<--autodatatype>

causes the B<{{datatype}}> template to be automatically prefixed for parameters with named data types

=item B<--canonical>

affects only the B<xml2> report; causes descriptions to be processed into a canonical form that eases comparison with the original Microsoft Word descriptions

=item B<--components>

affects only the B<xml2> report; generates a component for each object; if B<--noobjects> is also specified, the component omits the object definition and consists only of parameter definitions

=item B<--debugpath=pattern("")>

outputs debug information for parameters and objects whose path names match the specified pattern

=item B<--deletedeprecated>

mark all deprecated or obsoleted items as deleted

=item B<--dtprofile=s>...

affects only the B<xml2> report; can be specified multiple times; defines names of profiles to be used to generate an example DT instance

=item B<--dtspec=s>

affects only the B<xml2> report; has an affect only when B<--dtprofile> is also present; specifies the value of the top-level B<spec> attribute in the generated DT instance; if not specified, the spec defaults to B<urn:example-com:device-1-0-0>

=item B<--help>

requests output of usage information

=item B<--ignore>

specifies a pattern; data models whose names begin with the pattern will be ignored

=item B<--importsuffix=string("")>

specifies a suffix which, if specified, will be appended (preceded by a hyphen) to the name part of any imported files in b<xml> reports

=item B<--include=d>...

can be specified multiple times; specifies directories to search for files specified on the command line or included from other files; the current directory is always searched first

no search is performed for files that already include directory names

=item B<--info>

output details of author, date, version etc

=item B<--lastonly>

reports only on items that were defined or modified in the last file that was specified on the command line

note that the B<xml> report always does something similar but might not work properly if this option is specified

=item B<--marktemplates>

mark selected template expansions with B<&&&&> followed by the template name and a colon

=item B<--noautomodel>

disables the auto-generation, if no B<model> element was encountered, of a B<Components> model that references each component

=item B<--nocomments>

disables generation of XML comments showing what changed etc (B<--verbose> always switches it off)

=item B<--nohyphenate>

prevents automatic insertion of soft hyphens

=item B<--nolinks>

affects only the B<html> report; disables generation of hyperlinks (which makes it easier to import HTML into Word documents)

=item B<--nomodels>

specifies that model definitions should not be reported

=item B<--noobjects>

affects only the B<xml2> report when B<--components> is specified; omits objects from component definitions

=item B<--noparameters>

affects only the B<xml2> report when B<--components> is specified; omits parameters from component definitions

B<NOT YET IMPLEMENTED>

=item B<--noprofiles>

specifies that profile definitions should not be reported

=item B<--notemplates>

suppresses template expansion (currently affects only B<html> reports

=item B<--nowarnredef>

disables parameter and object redefinition warnings (these warnings are also output if B<--verbose> is specified)

there are some circumstances under which parameter or object redefinition is not worthy of comment

=item B<--nowarnprofbadref>

disables warnings when a profile references an invalid object or parameter

there are some circumstances under which it's useful to use an existing profile definition where some objects or parameters that it references have been (deliberately) deleted

this is deprecated because it is no longer needed (use status="deleted" as appropriate to suppress such errors)

=item B<--objpat=pattern>

specifies an object name pattern (a regular expression); objects that do not match this pattern will be ignored (the default of "" matches all objects)

=item B<--pedantic=[i(1)]>

enables output of warnings to I<stderr> when logical inconsistencies in the XML are detected; if the option is specified without a value, the value defaults to 1

=item B<--quiet>

suppresses informational messages

=item B<--report=html|(null)|tab|text|xls|xml|xml2|xsd>

specifies the report format; one of the following:

=over

=item B<html>

HTML document; see also B<--nolinks> and B<--notemplates>

=item B<null>

no output; errors go to I<stdout> rather than I<stderr> (default)

=item B<tab>

tab-separated list, one object or parameter per line

=item B<text>

indented text

=item B<xls>

Excel XML spreadsheet

=item B<xml>

if B<--lastonly> is specified, DM XML containing only the changes made by the final file on the command line; see also B<--autobase>

if B<--lastonly> is not specified, DM XML with all imports resolved (apart from bibliographic references and data type definitions); use B<--dtprofile>, optionally with B<--dtspec>, to generate DT XML for the specified profiles; use B<--canonical> to generate canonical and more easily compared descriptions; use B<--components> (perhaps with B<--noobjects> or B<--noparameters>) to generate component definitions

=item B<xml2>

same as the B<xml> report with B<--lastonly> not specified; deprecated (use B<xml> instead)

=item B<xsd>

W3C schema

=back

=item B<--showspec>

currently affects only the B<html> report; generates a B<Spec> rather than a B<Version> column

=item B<--showsyntax>

adds an extra column containing a summary of the parameter syntax; is like the Type column for simple types, but includes additional details for lists

=item B<--special=deprecated|nonascii|normative|notify|obsoleted|profile|rfc>

performs special checks, most of which assume that several versions of the same data model have been supplied on the command line, and many of which operate only on the highest version of the data model

=over

=item B<deprecated>, B<obsoleted>

for each profile item (object or parameter) report if it is deprecated or obsoleted

=item B<nonascii>

check which model, object, parameter or profile descriptions contain characters other than ASCII 9-10 or 32-126; the output is the full path names of all such items, together with the offending descriptions with the invalid characters surrounded by pairs of asterisks

=item B<normative>

check which model, object, parameter or profile descriptions contain inappropriate use of normative language, i.e. lower-case normative words, or B<MAY NOT>; the output is the full path names of all such items, together with the offending descriptions with the normative words surrounded by pairs of asterisks

=item B<notify>

check which parameters in the highest version of the data model are not in the "can deny active notify request" table; the output is the full path names of all such parameters, one per line

=item B<profile>

check which parameters defined in the highest version of the data model are not in profiles; the output is the full path names of all such parameters, one per line

=item B<rfc>

check which model, object, parameter or profile descriptions mention RFCs without giving references; the output is the full path names of all such items, together with the offending descriptions with the normative words surrounded by pairs of asterisks

=back

=item B<--thisonly>

outputs only definitions defined in the files on the command line, not those from imported files

=item B<--upnpdm>

transforms output (currently HTML only) so it looks like a B<UPnP DM> (Device Management) data model definition

=item B<--ugly>

disables some prettifications, e.g. inserting spaces to encourage line breaks

this is deprecated because it has been replaced with the more specific B<--nohyphenate> and B<--showsyntax>

=item B<--verbose[=i(1)]>

enables verbose output; the higher the level the more the output

=item B<--warnbibref[=i(1)]>

enables bibliographic reference warnings (these warnings are also output if B<--verbose> is specified); the higher the level the more warnings

previously known as B<--warndupbibref>, which is now deprecated (and will be removed in a future release) because it covers more than just duplicate bibliographic references

=item B<--writonly>

reports only on writable parameters (should, but does not, suppress reports of read-only objects that contain no writable parameters)

=back

=head1 LIMITATIONS

This script is only for illustration of concepts and has many shortcomings.

=head1 AUTHOR

William Lupton E<lt>wlupton@2wire.comE<gt>

$Date: 2010/01/20 $
$Id: //depot/users/wlupton/cwmp-datamodel/report.pl#150 $

=cut
