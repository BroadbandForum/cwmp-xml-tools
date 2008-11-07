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

use strict;
no strict "refs";

use Algorithm::Diff;
use Clone qw{clone};
use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use URI::Escape;
use XML::LibXML;

# XXX this prevents warnings about wide characters, but still not handling
#     them properly (see tr2dm.pl, which now does a better job)
binmode STDOUT, ":utf8";

# Command-line options
my $autobase = 0;
my $count = 1; # XXX always 1 for now
my $debugpath = '';
my $detail = 0;
my $help = 0;
my $ignore = '';
my $importsuffix = '';
my $lastonly = 0;
my $modelonly = 0; # XXX deprecated
my $noautomodel = 0;
my $nocomments = 0;
my $nodescriptions = 0;
my $nomodels = 0;
my $noprofiles = 0;
my $objpat = '';
my $pedantic;
my $profileonly = 0; # XXX deprecated
my $quiet = 0;
my $report = '';
my $special = '';
my $thisonly = 0;
my $ugly = 0;
my $verbose;
my $writonly = 0;
GetOptions('autobase' => \$autobase,
           'count' => \$count,
           'debugpath:s' => \$debugpath,
	   'detail' => \$detail,
	   'help' => \$help,
           'ignore:s' => \$ignore,
           'importsuffix:s' => \$importsuffix,
           'lastonly' => \$lastonly,
	   'modelonly' => \$modelonly,
	   'noautomodel' => \$noautomodel,
	   'nocomments' => \$nocomments,
	   'nodescriptions' => \$nodescriptions,
	   'nomodels' => \$nomodels,
	   'noprofiles' => \$noprofiles,
	   'objpat:s' => \$objpat,
	   'pedantic:i' => \$pedantic,
	   'profileonly' => \$profileonly,
	   'quiet' => \$quiet,
	   'report:s' => \$report,
           'special:s' => \$special,
	   'thisonly' => \$thisonly,
           'ugly' => \$ugly,
	   'verbose:i' => \$verbose,
	   'writonly' => \$writonly) or pod2usage(2);
pod2usage(2) if $report && $special;
pod2usage(1) if $help;

$report = 'special' if $special;
$report = 'null' unless $report;

unless (defined &{"${report}_node"}) {
    print STDERR "unsupported report format: $report\n";
    pod2usage(2);
}

*STDERR = *STDOUT if $report eq 'null';

$nomodels = 1 if $profileonly;
$noprofiles = 1 if $modelonly;

$pedantic = 1 if defined($pedantic) and !$pedantic;
$pedantic = 0 unless defined($pedantic);

$verbose = 1 if defined($verbose) and !$verbose;
$verbose = 0 unless defined($verbose);

$nocomments = 0 if $verbose;

# Globals.
my $specs = [];
my $lfile = ''; # last command-line-specified file
my $lspec = ''; # spec from last command-line-specified file
my $files = {};
my $imports = {}; # XXX not a good name, because it includes main file defns
my $imports_i = 0;
my $bibrefs = {};
my $objects = {};
my $parameters = {};
my $root = {spec => '', path => '', name => '', type => '',
            status => 'current', dynamic => 0};
my $highestMajor = 0;
my $highestMinor = 0;

# Parse and expand a data model definition file.
# XXX need to support description
sub expand_toplevel
{
    my ($file)= @_;

    # parse file (update lspec even if have already parsed it; needed so
    # generated XML will have the correct spec)
    my $toplevel = parse_file($file);
    my $spec = $toplevel->findvalue('@spec');

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
    my $toplevel = parse_file($tfile);
    my $fspec = $toplevel->findvalue('@spec');
    push @$specs, $fspec unless grep {$_ eq $fspec} @$specs;

    # check spec (if supplied)
    $spec = $fspec unless $spec;
    print STDERR "import $file: spec is $fspec (expected $spec)\n"
        if $fspec ne $spec;

    # collect top-level item declarations
    foreach my $item ($toplevel->findnodes('dataType|component|model')) {
        my $element = $item->findvalue('local-name()');
        my $name = $item->findvalue('@name');
        my $ref = $item->findvalue('@base');
        
        update_imports($file, $fspec, $file, $fspec, $element, $name, $ref,
                       $item);
    }

    unshift @$context, {file => $file, spec => $fspec, path => '', name => ''};

    # expand imports in the imported file
    foreach my $item ($toplevel->findnodes('import')) {
	expand_import($context, $root, $item);
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

        my ($fitem) = $toplevel->findnodes(qq{$element\[\@name="$ref"\]});
        # XXX warning here could give multiple warnings if also warn when try
        #     to reference (but not warning at all is worse?)
        print STDERR "{$file}$ref: $element not found\n" unless $fitem;

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
    print STDERR "added $element {$file}$name$alias\n" if $verbose;
}

# Expand a dataType definition.
# XXX does the minimum to support TR-106
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

    update_bibrefs($description);

    print STDERR "expand_dataType name=$name base=$base\n" if $verbose > 1;

    my $node = {name => $name, base => $base, spec => $spec,
                status => $status, description => $description,
                descact => $descact, minLength => $minLength,
                maxLength => $maxLength, patterns => []};

    foreach my $pattern (@$patterns) {
        my $value = $pattern->findvalue('@value');
        my $description = $pattern->findvalue('description');
        my $descact = $pattern->findvalue('description/@action');

        update_bibrefs($description);

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

    update_bibrefs($description);

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
                print STDERR "$id: duplicate bibref {$file}$name\n";
            } elsif ($dupref->{name} ne $name) {
                print STDERR "$id: ambiguous bibref: $dupref->{name}, $name\n";
            }
        }

        print STDERR "expand_bibliography_reference id=$id name=$name\n" if
            $verbose > $vlevel;

        my $hash = {id => $id, name => $name};
        foreach my $element (qw{title organization category date hyperlink}) {
            my $value = $reference->findvalue($element);
            $hash->{$element} = $value ? $value : '';
        }

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

    my $name = $model->findvalue('@name');
    my $ref = $model->findvalue('@ref');
    $ref = $model->findvalue('@base') unless $ref;
    my $status = $model->findvalue('@status');
    my $isService = boolean($model->findvalue('@isService'));
    my $description = $model->findvalue('description');
    my $descact = $model->findvalue('description/@action');

    # XXX fudge it if in a DT instance (ref but no name or base)
    $name = $ref if $ref && !$name;

    update_bibrefs($description);

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

    my $path = $component->findvalue('@path');
    $path = '' unless defined $path;
    my $name = $component->findvalue('@ref');

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
    my $spath = $path;
    ($pnode, $path) = add_path($context, $mnode, $pnode, $path, 0);

    # pass information from caller to the new component context
    # XXX path is used only by profile components, which is a bit of a hack
    unshift @$context, {file => $file, spec => $spec, path => $spath,
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

    update_bibrefs($description);

    $minEntries = 1 unless defined $minEntries && $minEntries ne '';
    $maxEntries = 1 unless defined $maxEntries && $maxEntries ne '';

    # XXX majorVersion and minorVersion are no longer in the schema
    #my $majorVersion = $object->findvalue('@majorVersion');
    #my $minorVersion = $object->findvalue('@minorVersion');
    my ($majorVersion, $minorVersion) = dmr_version($object);

    # XXX this is incomplete name / ref handling
    my $tname = $name ? $name : $ref;
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
        $name = '';
    }

    # if this is a variable-size table, check that there is a
    # numEntriesParameter attribute and that the referenced parameter exists
    # XXX numEntriesParameter is checked only when object is defined; this
    #     means that no check is made when processing DT instances
    if ($name && ($maxEntries eq 'unbounded' || 
                  ($maxEntries > 1 && $maxEntries > $minEntries))) {
	if (!$numEntriesParameter) {
            print STDERR "$path: missing numEntriesParameter\n" if $pedantic;
        } else {
	    unless (grep {$_->{name} =~ /$numEntriesParameter/}
		    @{$pnode->{nodes}}) {
                # XXX can this diagnostic be deferred until the "sanity" pass?
		print STDERR "missing NumberOfEntries parameter " .
		    "($numEntriesParameter) for $path\n" if $pedantic;
		print STDERR "\t" .
		    join(", ",
			 map {$_->{name}} @{$pnode->{nodes}}) .
			 "\n" if $pedantic > 2;
	    }
	}
    }

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

    # create the new object
    my $nnode = add_object($context, $mnode, $pnode, $name, $ref, 0, $access,
			   $status, $description, $descact, $majorVersion,
			   $minorVersion, $previous);

    # XXX add some other stuff (really should be handled by add_object)
    $nnode->{minEntries} = $minEntries unless
        defined $nnode->{minEntries};
    $nnode->{maxEntries} = $maxEntries unless
        defined $nnode->{maxEntries};
    $nnode->{numEntriesParameter} = $numEntriesParameter unless
        defined $nnode->{numEntriesParameter};
    $nnode->{enableParameter} = $enableParameter unless
        defined $nnode->{enableParameter};
    $nnode->{uniqueKeys} = [] unless
        defined $nnode->{uniqueKeys};

    # expand nested components, parameters and objects
    foreach my $item ($object->findnodes('component|uniqueKey|parameter|'.
                                         'object')) {
	my $element = $item->findvalue('local-name()');
	"expand_model_$element"->($context, $mnode, $nnode, $item);
    }
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
    my $default = $parameter->findvalue('syntax/default/@type') eq 'object' ?
        $parameter->findvalue('syntax/default/@value') : undef;
    my $defstat = $parameter->findvalue('syntax/default/@status');

    # XXX majorVersion and minorVersion are no longer in the schema
    #my $majorVersion = $parameter->findvalue('@majorVersion');
    #my $minorVersion = $parameter->findvalue('@minorVersion');
    my ($majorVersion, $minorVersion) = dmr_version($parameter);

    update_bibrefs($description);

    # XXX I have a feeling that I need to be more rigorous re the distinction
    #     between nodes being absent and nodes having blank values (see the
    #     descdef handling here)

    # XXX maxLength handling is suspect here; also minLength handling should be
    #     consistent with maxLength (but minLength isn't really used...)

    my $syntax;
    if (defined($type)) {
        # XXX not handling multiple ranges or sizes
        # XXX for a list, minLength and maxLength refer to the item
	foreach my $attr (('@ref', '@base', '@maxLength',
                           'range/@minInclusive', 'range/@maxInclusive',
                           'size/@minLength', 'size/@maxLength')) {
	    my $val = $type->findvalue($attr);
            my $tattr = $attr;
            $tattr =~ s/.*@//;
	    $syntax->{$tattr} = $val if $val ne '';
	}
    }
    $syntax->{hidden} = defined(($parameter->findnodes('syntax/@hidden'))[0]);
    $syntax->{list} = defined(($parameter->findnodes('syntax/list'))[0]);
    if ($syntax->{list}) {
        my $minItems = $parameter->findvalue('syntax/list/@minItems');
        $syntax->{minItems} = $minItems if $minItems;
        my $maxItems = $parameter->findvalue('syntax/list/@maxItems');
        $syntax->{maxItems} = $maxItems if $maxItems;
        my $maxLength = $parameter->findvalue('syntax/list/size/@maxLength');
        $syntax->{maxListLength} = $maxLength if $maxLength;
    }

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
        
        update_bibrefs($description);

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
    if ($writonly && $access ne 'readWrite') {
	print STDERR "\tdoesn't match write-only criterion\n" if $verbose > 1;
	return;
    }

    # XXX this is incomplete name / ref handling
    my $tname = $name ? $name : $ref;
    my $path = $pnode->{path}.$tname;

    # the name may consist of multiple components; create any intervening
    # objects, returning the new parent and the last component of the name
    ($pnode, $name) = add_path($context, $mnode, $pnode, $tname, 1);
    # XXX this is more of the incomplete name / ref handling
    if ($ref) {
        $ref = $name;
        $name = '';
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
                  $defstat, $majorVersion, $minorVersion, $activeNotify,
                  $forcedInform, $units, $previous);
}

# Expand a data model profile.
sub expand_model_profile
{
    my ($context, $mnode, $pnode, $profile) = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};

    my $name = $profile->findvalue('@name');
    my $base = $profile->findvalue('@base');
    # XXX model no longer used
    my $model = $profile->findvalue('@model');
    my $status = $profile->findvalue('@status');
    my $description = $profile->findvalue('description');
    # XXX descact too

    update_bibrefs($description);

    # XXX want to do this consistently; really want to get defaults from
    #     somewhere (not hard-coded)
    $status = 'current' unless $status;

    print STDERR "expand_model_profile name=$name base=$base\n"
        if $verbose > 1;

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
        $previous = $context->[0]->{previousProfile} unless defined $previous;
        undef $context->[0]->{previousProfile};
    }

    # XXX use mnode rather than pnode, because of problems when expanding
    #     profile components with paths (need to explain this!)

    # check whether profile already exists
    my ($nnode) = grep {
        $_->{type} eq 'profile' && $_->{name} eq $name; } @{$mnode->{nodes}};
    if ($nnode) {
        # XXX don't automatically report this until have sorted out profile
        #     re-definition
        print STDERR "$name: profile already defined\n" if
            $pedantic && !$autobase;
        # XXX profiles can never change, so just give up; BUT this means that
        #     we won't detect corrections, deprecations etc, so is not good
        #     enough
        return;
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
        # versions to be defined both using base and standalone
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
        $nnode = {path => $name, name => $name, base => $base, spec => $spec,
                  type => 'profile', access => '', status => $status,
                  description => $description, model => $model, nodes => [],
                  baseprof => $baseprof};
        # determine where to insert the new node; after base profile first;
        # after previous node otherwise
        my $index = @{$mnode->{nodes}};
        if ($base) {
            for (0..$index-1) {
                if (@{$mnode->{nodes}}[$_]->{name} eq $base) {
                    $index = $_+1;
                    last;
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

    print STDERR "expand_model_profile_object path=$Path ref=$name\n" if
        $verbose > 1;

    $name = $Path . $name if $Path;

    unless ($objects->{$name}) {
	print STDERR "profile $Pnode->{name} references invalid $name\n";
    }

    # XXX should check that access matches the referenced object's access

    # if requirement is not greater than that of the base profile, reduce
    # it to 'notSpecified'
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

    # node shouldn't already exist, but check anyway
    my $push_deferred = 0;
    my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
    my $nnode;
    if (@match) {
	$nnode = $match[0];
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
    if ($can_ignore && $push_deferred && !@{$nnode->{nodes}}) {
        print STDERR "profile $Pnode->{name} will ignore object $name\n" if
            $verbose;
    } else {
        push(@{$pnode->{nodes}}, $nnode);
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

    print STDERR "expand_model_profile_parameter path=$Path ref=$name\n" if
        $verbose > 1;

    my $path = $pnode->{type} eq 'profile' ? $name : $pnode->{name}.$name;
    # special case for parameter at top level of a profile
    $path = $Path . $path if $Path && $Pnode == $pnode;

    unless ($parameters->{$path}) {
	print STDERR "profile $Pnode->{name} references invalid $path\n";
    } elsif ($access eq 'readWrite' &&
             $parameters->{$path}->{access} ne 'readWrite') {
	print STDERR "profile $Pnode->{name} has invalid requirement ".
            "($access) for $path ($parameters->{$path}->{access})\n";
    }

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

    # node shouldn't already exist, but check anyway
    my @match = grep {$_->{name} eq $name} @{$pnode->{nodes}};
    my $nnode;
    if (@match) {
	$nnode = $match[0];
    } else {
        push(@{$pnode->{nodes}},
             {pnode => $pnode, name => $name, type => 'parameterRef',
              access => $access, status => $status, nodes => []});
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

    # if ref, find the referenced model
    my $nnode;
    if ($ref) {
        my @match = grep {
            my ($a) = ($name =~ /([^:]*)/);
            my ($b) = ($_->{name} =~ /([^:]*)/);
            $_->{type} eq 'model' && $a eq $b;
        } @{$root->{nodes}};
        # there can't be more than one match
        if (@match) {
            $nnode = $match[0];
            print STDERR "reusing node $nnode->{name}\n" if $verbose > 1;
        } elsif (load_model($context, $file, $spec, $ref)) {
            @match = grep {
                my ($a) = ($name =~ /([^:]*)/);
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
        print STDERR "unnamed model\n" unless $name;
        my $dynamic = $pnode->{dynamic};
	$nnode = {name => $name, path => '', file => $file, spec => $spec,
                  type => 'model', access => undef,
                  isService => $isService, status => $status,
                  description => $description, descact => $descact,
                  default => undef, dynamic => $dynamic,
                  majorVersion => $majorVersion, minorVersion => $minorVersion,
                  nodes => [], history => undef};
        push @{$pnode->{nodes}}, $nnode;
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

    print STDERR "add_path name=$name\n" if $verbose > 1;

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
        $previous = $context->[0]->{previousObject} unless defined $previous;
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
        print STDERR "$path: object already defined\n"
            if @match && !$autobase;
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
        if (($pnode->{dynamic} || $nnode->{access} eq 'readWrite') !=
            $nnode->{dynamic}) {
            print STDERR "$path: dynamic: $nnode->{dynamic} -> ".
                "$pnode->{dynamic}\n" if $verbose;
            $nnode->{dynamic} = $pnode->{dynamic} || $access eq 'readWrite';
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
        print STDERR "$path: unnamed object\n" unless $name;

        # XXX this is still how we're handling the version number...
	$majorVersion = $mnode->{majorVersion} unless defined $majorVersion;
	$minorVersion = $mnode->{minorVersion} unless defined $minorVersion;

        print STDERR "$path: added\n" if
            $verbose && $mnode->{history} && @{$mnode->{history}} && !$auto;

        mark_changed($pnode, $spec);
        
        my $dynamic = $pnode->{dynamic} || $access eq 'readWrite';

	$nnode = {pnode => $pnode, name => $name, path => $path, file => $file,
                  spec => $spec, lspec => $spec, type => 'object',
                  auto => $auto, access => $access, status => $status,
                  description => $description, descact => $descact,
                  default => undef, dynamic => $dynamic,
                  majorVersion => $majorVersion, minorVersion => $minorVersion,
                  nodes => [], history => undef};
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
        $status, $description, $descact, $values, $default, $defstat,
        $majorVersion, $minorVersion, $activeNotify, $forcedInform, $units,
        $previous)
        = @_;

    my $file = $context->[0]->{file};
    my $spec = $context->[0]->{spec};

    # if the context contains "previousParameter", it's from a component
    # reference, and applies only to the first parameter
    if ($context->[0]->{previousParameter}) {
        $previous = $context->[0]->{previousParameter} unless
            defined $previous;
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
        print STDERR "$path: parameter already defined\n"
            if @match && !$autobase;
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
        if ($activeNotify ne $nnode->{activeNotify}) {
            print STDERR "$path: activeNotify: $nnode->{activeNotify} -> " .
                "$activeNotify\n" if $verbose;
            $nnode->{activeNotify} = $activeNotify;
            $changed->{activeNotify} = 1;
        }
        if (boolean($forcedInform) ne boolean($nnode->{forcedInform})) {
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
            print STDERR "$path: type: $nnode->{type} -> $type\n"
                if $verbose;
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
	while (my ($key, $value) = each %$syntax) {
            if ($value && (!defined $nnode->{syntax}->{$key} ||
                           $value ne $nnode->{syntax}->{$key})) {
                my $old = defined $nnode->{syntax}->{$key} ?
                    $nnode->{syntax}->{$key} : '<none>';
                print STDERR "$path: $key: $old -> $value\n" if $verbose;
                $nnode->{syntax}->{$key} = $value;
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
        #     only to components but to imported models :) (need a more direct
        #     test)
        #$default = undef if !$dynamic && @$context > 1;

	$nnode = {pnode => $pnode, name => $name, path => $path, file => $file,
		  spec => $spec, lspec => $spec, type => $type,
                  syntax => $syntax, access => $access, status => $status,
		  description => $description, descact => $descact,
                  values => $values, default => $default, defstat => $defstat,
                  dynamic => $dynamic, majorVersion => $majorVersion,
                  minorVersion => $minorVersion, activeNotify => $activeNotify,
                  forcedInform => $forcedInform, units => $units, nodes => [],
                  history => undef};
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

# Update list of bibrefs that are actually used
# XXX not as intelligent as it might be
sub update_bibrefs
{
    my ($value) = @_;

    my @ids = ($value =~ /\{\{bibref\|([^\|\}]+)/g);
    foreach my $id (@ids) {
        $bibrefs->{$id} = 1;
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

	my $any = $description || $optional || $deprecated || $obsoleted;

	#my $quote = $report ne 'xls' && $value !~ /^</;
	my $quote = $cvalue !~ /^</;

	#$list .= '* ' unless $report eq 'xls';
	$list .= '* ';
	#$list .= '"' if $quote;
	$list .= "''";
        $list .= '%%' if $anchor;
	$list .= $value;
        $list .= '%%' if $anchor;
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

# Form a "type", "string(maxLength)" or "int[minInclusive:maxInclusive]" type
# string
sub type_string
{
    my ($type, $syntax) = @_;

    my $value = $type;

    if ($syntax->{ref}) {
        $value = $syntax->{ref};
    } elsif ($syntax->{base}) {
        $value = $syntax->{base};
    }

    # note that zero minLength is not displayed
    if ($syntax->{minLength} || defined $syntax->{maxLength}) {
	$value .= '(';
	$value .= $syntax->{minLength} if $syntax->{minLength};
	$value .= ':' if $syntax->{minLength};
	$value .= $syntax->{maxLength} if defined $syntax->{maxLength};
	$value .= ')';
    }

    # old style list
    if ($syntax->{list} && !$detail) {
        if ($syntax->{minListLength} || defined $syntax->{maxListLength}) {
            $value .= '(';
            $value .= $syntax->{minListLength} if $syntax->{minListLength};
            $value .= ':' if $syntax->{minListLength};
            $value .= $syntax->{maxListLength} if
                defined $syntax->{maxListLength};
            $value .= ')';
        }
    }

    if (defined $syntax->{minInclusive} || defined $syntax->{maxInclusive}) {
	$value .= '[';
	$value .= $syntax->{minInclusive} if defined $syntax->{minInclusive};
	$value .= ':';
	$value .= $syntax->{maxInclusive} if defined $syntax->{maxInclusive};
	$value .= ']';
    }

    # old style list
    if ($syntax->{list} && !$detail) {
        $value .= '[]';
    }

    # new style list
    if ($syntax->{list} && $detail) {
        my $list = 'list';
        if ($syntax->{minListLength} || defined $syntax->{maxListLength}) {
            $list .= '(';
            $list .= $syntax->{minListLength} if $syntax->{minListLength};
            $list .= ':' if $syntax->{minListLength};
            $list .= $syntax->{maxListLength} if
                defined $syntax->{maxListLength};
            $list .= ')';
        }
        if (defined $syntax->{minItems} || defined $syntax->{maxItems}) {
            $list .= '[';
            $list .= $syntax->{minItems} if defined $syntax->{minItems};
            $list .= ':';
            $list .= $syntax->{maxItems} if defined $syntax->{maxItems};
            $list .= ']';
        }
        $list .= ' of ';
        $value = $list . $value;
    }

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
    my ($file)= @_;

    print STDERR "parsing file: $file\n" if $verbose;

    # parse file
    # XXX need to search for file (a) search path, and (b) searching for
    #     highest corrigendum number
    my $parser = XML::LibXML->new();
    my $tree = $parser->parse_file($file);
    my $toplevel = $tree->getDocumentElement;

    # XXX expect these all to be the same if processing multiple documents,
    #     but should check; really should keep separate for each document
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

    return $toplevel;
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
        print "  "x$indent . "$type $node->{name}" .
            ($node->{access} eq 'readWrite' ? ' (W)' : '') .
            ($node->{model} ? (' ' . $node->{model}) : '') .
            ($detail && $node->{changed} ?
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

        if ($bibliography) {
            my $description = $bibliography->{description};
            my $descact = $bibliography->{descact} || 'create';
            my $references = $bibliography->{references};

            $descact = $descact ne 'create' ? qq{ action="$descact"} : qq{};

            print qq{$i  <bibliography>\n};
            print qq{$i    <description$descact>$description</description>\n}
            if $description;

            foreach my $reference (sort {$a->{id} cmp $b->{id}} @$references) {
                my $id = $reference->{id};
                my $spec = $reference->{spec};

                if ($spec ne $lspec) {
                    print STDERR "reference $id defined in {$file}\n" if
                        $verbose > 1;
                    next;
                }

                if (!$bibrefs->{$id}) {
                    # XXX dangerous to omit it since it might be defined here
                    #     in order to make it available to later versions
                    # XXX for now, have hard-list of things not to omit
                    my $omit = ($id !~ /TR-069|TR-106/);
                    if ($omit) {
                        print STDERR "reference $id not used (omitted)\n"
                            if $verbose;
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
            my $minLength = $syntax->{minLength};
            my $maxLength = $syntax->{maxLength};
            my $minInclusive = $syntax->{minInclusive};
            my $maxInclusive = $syntax->{maxInclusive};
            my $values = $node->{values};
            my $default = $node->{default};
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
                         $maxInclusive || %$values) ? '' : '/';
            print qq{$i    <$type$ref$base$ended>\n};
            print qq{$i      <size$minLength$maxLength/>\n} if
                $minLength || $maxLength;
            print qq{$i      <range$minInclusive$maxInclusive/>\n} if
                $minInclusive || $maxInclusive;
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
            print qq{$i    <default type="object" value="$default"$defstat/>\n}
            if defined $default && ($basename eq 'name' ||
                                    $changed->{default});
            print qq{$i  </syntax>\n};
        }
        print qq{$i</parameter>\n};
        $node->{xml}->{action} = 'none';
    }
}

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
# XXX objact (etc) is horrible but is necessary to force all objects to be
#     defined at the top level
my $xml2_objact = undef;

sub xml2_node
{
    my ($node, $indent) = @_;

    $indent = 0 unless $indent;

    my $type = $node->{type};
    my $element = $type;

    my $i = "  " x $indent;

    $node->{xml2} = {action => 'close', element => $type};

    # use indent as a first-time flag
    if (!$indent) {
        my $dm = $node->{dm};
        my $dmr = $node->{dmr};
        my $xsi = $node->{xsi};
        my $schemaLocation = $node->{schemaLocation};

        $element = 'dm:document';
        # XXX for now hard-code bibliography and data type imports
        print qq{$i<?xml version="1.0" encoding="UTF-8"?>
$i<!-- \$Id\$ -->
$i<!-- note: this is an automatically generated XML report -->
$i<dm:document xmlns:dm="$dm"
$i             xmlns:dmr="$dmr"
$i             xmlns:xsi="$xsi"
$i             xsi:schemaLocation="$schemaLocation"
$i             spec="$lspec">
$i  <import file="tr-069-biblio.xml" spec="urn:broadband-forum-org:tr-069-biblio"/>
$i  <import file="tr-106-1-0-types.xml" spec="urn:broadband-forum-org:tr-106-1-0">
$i    <dataType name="IPAddress"/>
$i    <dataType name="MACAddress"/>
$i  </import>
};
    }

    if ($indent) {
        my $history = $node->{history};
        my $name = $type eq 'object' ? $node->{path} : $node->{name};
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
        my $syntax = $node->{syntax};
        my $majorVersion = $node->{majorVersion};
        my $minorVersion = $node->{minorVersion};

        my $requirement = '';
        my $version = version($majorVersion, $minorVersion);

        if ($element eq 'model') {
            $version = '';
        } elsif ($element eq 'object') {
            $i = '    ';
            if ($xml2_objact) {
                #my $version = $xml2_objact->{xml2}->{version};
                #print qq{$i  <dmr:version>$version</dmr:version>\n} if
                #    $version;
                print qq{$i</object>\n};
            }
            $node->{xml2}->{action} = 'object' unless $indent == 2;
            $xml2_objact = $node;
        } elsif ($syntax) {
            $i = $xml2_objact ? '      ' : '    ';
            $element = 'parameter';
            $node->{xml2}->{action} = 'none';
        } elsif ($element =~ /(\w+)Ref/) {
            $ref = $name;
            $name = '';
            $requirement = $access;
            $access = '';
            $element = $1; # parameter or object
            $node->{xml2}->{action} = 'none' if $element eq 'parameter';
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
        $version = $version ? qq{ dmr:version="$version"} : qq{};

        ($description, $descact) = get_description($description, $descact,
                                                   $history, 1);
        $description = clean_description($description, $node->{name});
        $description = xml_escape($description);

        my $end_element = (@{$node->{nodes}} || $description || $syntax ||
                           $version) ? '' : '/';

        print qq{$i<$element$name$base$ref$access$numEntriesParameter$enableParameter$status$activeNotify$forcedInform$requirement$minEntries$maxEntries$version$end_element>\n};
        print qq{$i  <description>$description</description>\n} if
            $description;

        # XXX this is almost verbatim from xml_node
        if ($syntax) {
            my $hidden = $syntax->{hidden};
            my $base = $syntax->{base};
            my $ref = $syntax->{ref};
            my $list = $syntax->{list};
            my $minLength = $syntax->{minLength};
            my $maxLength = $syntax->{maxLength};
            my $minInclusive = $syntax->{minInclusive};
            my $maxInclusive = $syntax->{maxInclusive};
            my $values = $node->{values};
            my $default = $node->{default};
            my $defstat = $node->{defstat};

            # XXX a bit of a kludge...
            $type = 'dataType' if $ref;

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
                         $maxInclusive || %$values) ? '' : '/';
            print qq{$i    <$type$ref$base$ended>\n};
            print qq{$i      <size$minLength$maxLength/>\n} if
                $minLength || $maxLength;
            print qq{$i      <range$minInclusive$maxInclusive/>\n} if
                $minInclusive || $maxInclusive;
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
                $description = clean_description($description, $node->{name});
                $description = xml_escape($description);

                $optional = $optional ? qq{ optional="true"} : qq{};
                $access = $access ne 'readOnly' ? qq{ access="$access"} : qq{};
                $status = $status ne 'current' ? qq{ status="$status"} : qq{};
                my $ended = $description ? '' : '/';

                print qq{$i      <$facet value="$evalue"$access$status$optional$ended>\n};
                print qq{$i        <description>$description</description>\n} if $description;
                print qq{$i      </$facet>\n} unless $ended;
            }
            print qq{$i    </$type>\n} unless $ended;
            print qq{$i    <default type="object" value="$default"$defstat/>\n}
            if defined $default;
            print qq{$i  </syntax>\n};
        }

        $node->{xml2}->{action} = ($node->{xml2}->{action} eq 'object' ||
                                   $end_element) ? 'none' : 'close';
    }
    $node->{xml2}->{indent} = $i;
    $node->{xml2}->{element} = $element;
}

sub xml2_post
{
    my ($node) = @_;

    my $xml2 = $node->{xml2};
    my $action = $xml2->{action};
    my $element = $xml2->{element};
    my $i = $xml2->{indent};

    if ($action eq 'close') {
        print qq{$i</$element>\n};
        $xml2_objact = {} if $element eq 'object';
    }
}

# Heuristic changes to description to get rid of formatting etc and increase
# chances that description strings will compare as equal.
# XXX some of these things should be done on initial Word conversion...
sub clean_description
{
    my ($description, $name) = @_;

    # XXX sometimes convenient just to ignore the description?
    #return '' unless $detail;

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

    # options
    #my $options = qq{border="1" cellpadding="2" cellspacing="2"};
    my $options = qq{border="1" cellpadding="2" cellspacing="0"};

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

    # oc (open comment) and cc (close comment) are used for suppressing things
    # (e.g. the spec column) when not generating ugly output
    my $oc = $ugly ? '' : '<!-- ';
    my $cc = $ugly ? '' : ' -->';

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
      td.o { $row $font $object_bg }
      td, td.p { $row $font }
      td.oc { $row $font $object_bg $center }
      td.pc { $row $font $center }
    </style>
  </head>
  <body>
    <h1>Table of Contents</h1>
    <ul> <!-- Table of Contents -->
END
        $html_buffer .= <<END;
    </ul> <!-- Table of Contents -->
END
        my $bibliography = $node->{bibliography};
        if ($bibliography) {
            print <<END;
      <li><a href="#References">References</a></li>
END
            $html_buffer .= <<END;
    <h1><a name="References">References</a></h1>
    <table border="0"> <!-- References -->
END
            my $references = $bibliography->{references};
            foreach my $reference (sort {$a->{id} cmp $b->{id}} @$references) {
                my $id = $reference->{id};
                next unless $bibrefs->{$id};
                
                my $name = xml_escape($reference->{name});
                my $title = xml_escape($reference->{title});
                my $organization = xml_escape($reference->{organization});
                my $category = xml_escape($reference->{category});
                my $date = xml_escape($reference->{date});
                my $hyperlink = xml_escape($reference->{hyperlink});
                
                $id = qq{<a name="$id">[$id]</a>};
                
                $title = $title ? qq{, <em>$title</em>} : qq{};
                $organization = $organization ? qq{, $organization} : qq{};
                $category = $category ? qq{ $category} : qq{};
                $date = $date ? qq{, $date} : qq{};
                $hyperlink = $hyperlink ?
                    qq{, <a href="$hyperlink">$hyperlink</a>} : qq{};
                
                $html_buffer .= <<END;
      <tr>
        <td>$id</td>
        <td>$name$title$organization$category$date$hyperlink.</td>
      </tr>
END
            }
            $html_buffer .= <<END;
    </table> <!-- References -->
END
        }
    }

    if ($indent) {
	my $model = ($node->{type} =~ /model/);
	my $object = ($node->{type} =~ /object/);
	my $profile = ($node->{type} =~ /profile/);
        my $parameter = $node->{syntax}; # pretty safe? not profile params...
        my $history = $node->{history};
        my $path = $node->{path};
	my $name = html_escape($object ? $path : $node->{name}, {fudge => 1});
        my $base = html_escape($node->{base}, {default => '', empty => ''});
	my $type = html_escape(type_string($node->{type}, $node->{syntax}),
			       {fudge => 1});
        # XXX need to handle access / requirement more generally
        my $access = html_escape($node->{access});
	my $write = $access eq 'readWrite' ? 'W' :
            $access eq 'present' ? 'P' :
            $access eq 'create' ? 'A' :
            $access eq 'delete' ? 'D' :
            $access eq 'createDelete' ? 'C' : '-';
        my $description = $node->{description};
        my $descact = $node->{descact};
        ($description, $descact) = get_description($description, $descact,
                                                   $history, 1);
	$description =
            html_escape($description,
                        {default => '', empty => '',
                         path => $node->{path},
                         param => $parameter ? $node->{name} : '',
                         object => $parameter ? $node->{pnode}->{path} :
                             $object ? $path : undef,
                         access => $node->{access},
                         uniqueKeys => $node->{uniqueKeys},
                         enableParameter => $node->{enableParameter},
                         hidden => $node->{syntax}->{hidden},
                         reference => $node->{reference},
                         list => $node->{syntax}->{list},
                         values => $node->{values},
                         units => $node->{units},
                         nbsp => $object || $parameter});
        $description = '' if $nodescriptions;

        my $default = (defined $node->{defstat} && $node->{defstat} eq
                       'deleted') ? undef : $node->{default};
	$default = html_escape($default,
                               {quote => scalar($type =~ /^string/),
                                hyphenate => 1});
	my $version =
	    html_escape(version($node->{majorVersion}, $node->{minorVersion}));
	my $spec = html_escape($node->{spec});

	my $class = ($model | $object | $profile) ? 'o' : 'p';

        if ($model) {
            my $title = qq{$name Data Model};
            print <<END;
      <li><a href="#$title">$title</a></li>
      <ul> <!-- $title -->
        <li><a href="#$title">Data Model Definition</a></li>
        <ul> <!-- Data Model Definition -->
END
            $html_buffer .= <<END;
    <h1><a name="$title">$title</a></h1>
    $description<p>
    <table width="100%" $options> <!-- Data Model Definition -->
      <tbody>
        <tr>
          <th width="10%">Name</th>
          <th width="10%">Type</th>
          <th width="10%" class="c">Write</th>
          <th width="50%">Description</th>
          <th width="10%" class="c">Object Default</th>
          <th width="10%" class="c">Version</th>
          $oc<th class="c">Spec</th>$cc
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
                my $title = qq{Forced Inform Parameters};
                print <<END;
        </ul> <!-- Data Model Definition -->
        <li><a href="#Inform and Notification Requirements">Inform and Notification Requirements</a></li>
        <ul> <!-- Inform and Notification Requirements -->
          <li><a href="#$title">$title</a></li>
END
                $html_buffer .= <<END;
      </tbody>
    </table> <!-- Data Model Definition -->
    <h2><a name="Inform and Notification Requirements">Inform and Notification Requirements</a></h2>
    <h3><a name="$title">$title</a></h3>
    <table width="60%" $options> <!-- $title -->
      <tbody>
        <tr>
          <th style="$theader_bg">Parameter</th>
        </tr>
END
                foreach my $parameter
                (grep {$_->{forcedInform}} @$html_parameters) {
                    $html_buffer .= <<END;
        <tr>
          <td><a href="#$parameter->{path}">$parameter->{path}</a></td>
        </tr>
END
                }
                my $ptitle = $title;
                $title = qq{Forced Active Notification Parameters};
                print <<END;
          <li><a href="#$title">$title</a></li>
END
                $html_buffer .= <<END;
      </tbody>
    </table> <!-- $ptitle -->
    <h3><a name="$title">$title</a></h3>
    <table width="60%" $options> <!-- $title -->
      <tbody>
        <tr>
          <th style="$theader_bg">Parameter</th>
        </tr>
END
                foreach my $parameter
                (grep {$_->{activeNotify} eq 'forceEnabled'}
                 @$html_parameters) {
                    $html_buffer .= <<END;
        <tr>
          <td><a href="#$parameter->{path}">$parameter->{path}</a></td>
        </tr>
END
                }
                $ptitle = $title;
                $title = qq{Default Active Notification Parameters};
                print <<END;
          <li><a href="#$title">$title</a></li>
END
                $html_buffer .= <<END;
      </tbody>
    </table> <!-- $ptitle -->
    <h3><a name="$title">$title</a></h3>
    <table width="60%" $options> <!-- $title -->
      <tbody>
        <tr>
          <th style="$theader_bg">Parameter</th>
        </tr>
END
                foreach my $parameter
                (grep {$_->{activeNotify} eq 'forceDefaultEnabled'}
                 @$html_parameters) {
                    $html_buffer .= <<END;
        <tr>
          <td><a href="#$parameter->{path}">$parameter->{path}</a></td>
        </tr>
END
                }
                $ptitle = $title;
                $title =
                    qq{Parameters for which Active Notification MAY be Denied};
                print <<END;
          <li><a href="#$title">$title</a></li>
END
                $html_buffer .= <<END;
      </tbody>
    </table> <!-- $ptitle -->
    <h3><a name="$title">$title</a></h3>
    <table width="60%" $options> <!-- $title -->
      <tbody>
        <tr>
          <th style="$theader_bg">Parameter</th>
        </tr>
END
                foreach my $parameter
                (grep {$_->{activeNotify} eq 'canDeny'} @$html_parameters) {
                    $html_buffer .= <<END;
        <tr>
          <td><a href="#$parameter->{path}">$parameter->{path}</a></td>
        </tr>
END
                }
                $ptitle = $title;
                $title = qq{Profile Definitions};
                print <<END;
        </ul> <!-- Inform and Notification Requirements -->
        <li><a href="#$title">$title</a></li>
        <ul> <!-- $title -->
END
                $html_buffer .= <<END;
      </tbody>
    </table> <!-- $ptitle -->
    <h2><a name="$title">$title</a></h2>
END
                $html_profile_active = 1;
            }
            my $title = qq{$name Profile};
            $description = qq{This profile extends the requirements of the $base profile as follows:} if !$description && $base;
            print <<END;
          <li><a href="#$title">$title</a></li>
END
            $html_buffer .= <<END;
    <h3><a name="$title">$title</a></h3>
    $description<p>
    <table width="60%" $options> <!-- $title -->
      <tbody>
        <tr>
          <th width="80%">Name</th>
          <th width="20%" class="c">Requirement</th>
        </tr>
END
        }

        if ($model || $profile) {
        } elsif (!$html_profile_active) {
            # XXX should verify that all links have defined anchors
            # note that the second anchor does NOT have a trailing dot;
            # this is to allow use of {{object|table}}
            my $anchor2 = qq{};
            if ($path =~ /\{i\}\.$/) {
                my $table = $path;
                $table =~ s/\.\{i\}\.$//;
                $anchor2 = qq{<a name="$table"/>};
            }
            print <<END if $object;
          <li><a href="#$path">$path</a></li>
END
            $html_buffer .= <<END;
        <tr>
          <td class="${class}"><a name="$path">$name</a>$anchor2</td>
          <td class="${class}">$type</td>
          <td class="${class}c">$write</td>
          <td class="${class}">$description</td>
          <td class="${class}c">$default</td>
          <td class="${class}c">$version</td>
          $oc<td class="${class}c">$spec</td>$cc
	</tr>
END
        } else {
            my $path = $object ? $node->{name} :
                ($node->{pnode}->{name} . $node->{name});
            $html_buffer .= <<END;
        <tr>
          <td class="${class}"><a href="#$path">$name</a></td>
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

    # process markup
    # XXX whitespace and template processing is generic; shouldn't be done
    #     here
    unless ($opts->{nomarkup}) {
        $value = html_whitespace($value);
        $value = html_template($value, $opts);
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

    # XXX fudge wrap of very long names and types
    #$value =~ s/([^\d]\.)/$1 /g if $opts->{fudge} && !$ugly;
    #$value =~ s/\(/ \(/g if $opts->{fudge} && !$ugly;
    #$value =~ s/\[/ \[/g if $opts->{fudge} && !$ugly;
    # firefox 3 supports &shy;
    $value =~ s/([^\d]\.)/$1&shy;/g if $opts->{fudge} && !$ugly;
    $value =~ s/&shy;$// if $opts->{fudge} && !$ugly;
    $value =~ s/\(/&shy;\(/g if $opts->{fudge} && !$ugly;
    $value =~ s/\[/&shy;\[/g if $opts->{fudge} && !$ugly;

    # XXX try to hyphenate long words
    #$value =~ s/([a-z_])([A-Z])/$1<br>$2/g if $opts->{hyphenate} && !$ugly;
    # firefox 3 supports &shy;
    $value =~ s/([a-z_])([A-Z])/$1&shy;$2/g if $opts->{hyphenate} && !$ugly;

    $value = '&nbsp;' if $opts->{nbsp} && $value eq '';

    return $value;
}

# Process whitespace
sub html_whitespace
{
    my ($inval) = @_;

    # remove any leading whitespace up to and including the first line break
    $inval =~ s/^[ \t]*\n//;

    # remove any trailing whitespace (necessary to avoid polluting the prefix
    # length)
    $inval =~ s/\s*$//;

    # determine longest common whitespace prefix
    my $len = 0;
    my @lines = split /\n/, $inval;
    foreach my $line (@lines) {
        my ($pre) = $line =~ /^(\s*)/;
        $len = length($pre) if !$len || length($pre) < $len;
        if ($line =~ /\t/) {
            my $tline = $line;
            $tline =~ s/\t/\\t/g;
            print STDERR "replace tab(s) in \"$tline\" with spaces!\n";
        }
    }

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

    # auto-append {{enum}} or {{pattern}} if there are values and it's not
    # already there (put it on the same line if the value is empty or ends
    # with a sentence terminator)
    # "{{}}" is an empty template reference that will be removed; it prevents
    # special "after newline" template expansion behavior
    if ($p->{values} && %{$p->{values}}) {
        my ($key) = keys %{$p->{values}};
        my $facet = $p->{values}->{$key}->{facet};
        my $sep = !$inval ? "" : $inval =~ /[\.\?\!]$/ ? "  " : "\n{{}}";
        $inval .= $sep . "{{enum}}" if
            $facet eq 'enumeration' && $inval !~ /\{\{enum\}\}/;
        $inval .= $sep . "{{pattern}}" if
            $facet eq 'pattern' && $inval !~ /\{\{pattern\}\}/;
    }

    # similarly auto-append {{hidden}}, {{keys}} and {{reference}} if
    # appropriate
    if ($p->{hidden} && $inval !~ /\{\{hidden\}\}/) {
        my $sep = $inval ? "\n" : "";
        $inval .= $sep . "{{hidden}}";
    }
    if ($p->{uniqueKeys} && @{$p->{uniqueKeys}}&& $inval !~ /\{\{keys\}\}/) {
        my $sep = $inval ? "\n" : "";
        $inval .= $sep . "{{keys}}";
    }
    if ($p->{reference} && $inval !~ /\{\{reference\}\}/) {
        my $sep = $inval ? "\n" : "";
        $inval .= $sep . "{{reference}}";
    }

    # in template expansions, the @a array is arguments and the %p hash is
    # parameters (options)
    # XXX don't handle "{{}}" here because it needs to be done last
    # XXX hyperlink generation needs to be cleverer and to understand the
    #     rules for relative paths, e.g. if begins "Device." it's absolute    
    my $templates =
        [
         {name => 'bibref',
          text1 => q{[<a href="#$a[0]">$a[0]</a>]},
          text2 => q{[<a href="#$a[0]">$a[0]</a>] $a[1]}},
         {name => 'section', text => q{}},
         {name => 'param',
          text0 => q{''$p->{param}''},
          text1 => q{<a href="#$p->{object}$a[0]">''$a[0]''</a>}},
         {name => 'object',
          text0 => q{''$p->{object}''},
          text1 => q{<a href="#$p->{object}$a[0]">''$a[0]''</a>}},
         {name => 'keys',
          text0 => \&html_template_keys},
         {name => 'hidden', text0 => q{When read, this parameter returns {{empty}}, regardless of the actual value.}},
         {name => 'enum',
          text0 => \&html_template_enum,
          text1 => q{''$a[0]''},
          text2 => q{<a href="#$p->{object}$a[1].$a[0]">''$a[0]''</a>}},
         {name => 'pattern',
          text0 => \&html_template_pattern,
          text1 => q{''$a[0]''},
          text2 => q{<a href="#$p->{object}$a[1].$a[0]">''$a[0]''</a>}},
         {name => 'reference',
          text0 => \&html_template_reference},
         {name => 'units', text0 => q{''$p->{units}''}},
         {name => 'empty', text0 => q{an empty string}, ucfirst => 1},
         {name => 'false', text0 => q{''false''}},
         {name => 'true', text0 => q{''true''}}
         ];

    # XXX need to allow args to contain matched braces, e.g. "{i}" in a path
    #     name
    # XXX to allow "{i}" in macro arguments, fudge it
    $inval =~ s/\{i\}/\[\[i\]\]/g;
    while (my ($newline, $period, $name, $args) =
           $inval =~ /(\n?)[ \t]*([\.\?\!]?)[ \t]*\{\{([^\|\}]*)\|?([^\}]*)\}\}/) {
        # XXX atstart is possibly useful for descriptions that consist only of
        #     {{enum}} or {{pattern}}?
        my $atstart = $inval =~ /^\{\{$name[\|\}]/;
        $p->{atstart} = $atstart;
        $p->{newline} = $newline;
        $p->{period} = $period;
        my @a = split /\|/, $args;
        my $n = @a;
        #print STDERR "$name: $n\n";
        #foreach my $a (@a) {
        #    print STDERR "  $a\n";
        #}
        my $template = (grep {$_->{name} eq $name} @$templates)[0];
        my $tref = "$name" . (@a ? ("|".join('|', @a)): "");
        my $text = "[[$tref]]";
        if ($template) {
            my $cmd = $template->{'text'.$n} ? $template->{'text'.$n} :
                $template->{text};
            if (ref($cmd)) {
                $text = &$cmd($p);
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
            print STDERR "$p->{path}: invalid template reference: {{$tref}}\n";
        }
        $inval =~ s/\{\{$name[^\}]*\}\}/$text/;
    }
    $inval =~ s/\[\[i\]\]/\{i\}/g;

    # remove null template references (which are used as separators)
    $inval =~ s/\[\[\]\]//g;

    # restore unexpanded templates
    $inval =~ s/\[\[([^\]]*)\]\]/\{\{$1\}\}/g;

    return $inval;
}

sub html_template_keys
{
    my ($opts) = @_;

    my $access = $opts->{access};
    my $uniqueKeys = $opts->{uniqueKeys};
    my $enableParameter = $opts->{enableParameter};

    my $text;
    $text = qq{The following parameter(s) define this table\'s unique key:\n} if @$uniqueKeys == 1;
    $text = qq{The following sets of parameter(s) each define one of this table\'s unique keys:\n} if @$uniqueKeys > 1;

    my $i = 1;
    my $stars = @$uniqueKeys > 1 ? qq{**} : qq{*};
    foreach my $uniqueKey (@$uniqueKeys) {
        $text .= qq{* $i:\n} if @$uniqueKeys > 1;
        foreach my $parameter (@$uniqueKey) {
            $text .= qq{$stars {{param|$parameter}}\n};
        }
        $i++;
    }

    my $enabled = $enableParameter ? qq{ enabled} : qq{};
    my $athe = @$uniqueKeys > 1 ? qq{a} : qq{the};
    $text .= qq{At most one$enabled entry can exist with all the same values for $athe unique key\'s parameter(s).};
    # XXX the next bit is needed only if one or more of the unique key
    #     parameters is writable; currently we don't have access to this
    #     information here
    #$text .= qq{  If the ACS attempts to set the parameters of an existing entry such that this requirement would be violated, the CPE MUST reject the request. In this case, the SetParameterValues response MUST include a SetParameterValuesFault element for each parameter in the corresponding request whose modification would have resulted in such a violation.\n};
    $text .= qq{\n};
    $text .= qq{On creation of a new table entry, the CPE MUST choose initial values for $athe unique key\'s parameter(s) such that the new entry does not conflict with any existing entry.\n} if $access eq 'readWrite' && !$enableParameter;

    return $text;
}

sub html_template_enum
{
    my ($opts) = @_;
    my $pref = ($opts->{atstart} || $opts->{newline}) ? "" : $opts->{list} ?
        "Each entry in the list is an enumeration of:\n" : "Enumeration of:\n";
    return $pref . xml_escape(get_values($opts->{values}, 1));
}

sub html_template_pattern
{
    my ($opts) = @_;
    my $pref = ($opts->{atstart} || $opts->{newline}) ? "" : $opts->{list} ?
        "Each entry in the list matches one of:\n" :
        "Possible patterns:\n";
    return $pref . xml_escape(get_values($opts->{values}, 1));
}

sub html_template_reference
{
    my ($opts) = @_;

    return qq{\'\'\'reference template not yet supported\'\'\'};
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
            $outval .= '  ' x $depth . "</$type>\n";
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
	$outval .= '  ' x $depth . "</$type>\n";
    }
    chomp $outval;
    return $outval;
}

# Process hyperlinks
sub html_hyperlink
{
    my ($inval) = @_;

    # XXX need better set of URL characters
    $inval =~ s|([a-z]+://[\w\d\.\:\/\?\&\=]+)|<a href="$1">$1</a>|g;

    return $inval;
}

# Process font markup
sub html_font
{
    my ($inval, $opts) = @_;

    $inval =~ s|'''([^']*)'''|<b>$1</b>|g;
    $inval =~ s|''([^']*)''|<i>$1</i>|g;

    # XXX "%%" anchor expansion should be elsewhere (hyperlink?)
    # XXX need to escape special characters out of anchors and references
    if ($opts->{object} && $opts->{param}) {
        my $path = $opts->{object} . $opts->{param};
        $inval =~ s|%%([^%]*)%%|<a name="$path.$1">$1</a>|g;
    }

    return $inval;
}

# Process paragraph breaks
# XXX this assumes that leading spaces are left on verbatim lines
sub html_paragraph
{
    my ($inval) = @_;

    my $outval = '';
    my @lines = split /\n/, $inval;
    foreach my $line (@lines) {
        $line =~ s/$/<p>/ if $line !~ /^(\s|\s*<)/;

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
	my $write = xls_escape($node->{access} eq 'readWrite' ? 'W' : '-');
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
				   ' (' . ($node->{access} eq 'readWrite' ? 'W' : 'R') . ')' .
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
	if ($detail) {
	    print "  "x$indent . qq{  <xs:annotation>\n};
	    print "  "x$indent . qq{    <xs:documentation>$documentation</xs:documentation>\n};
	    print "  "x$indent . qq{  </xs:annotation>\n};
	}
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
	if ($detail) {
	    print "  "x$indent . qq{  <xs:annotation>\n};
	    print "  "x$indent . qq{    <xs:documentation>$documentation</xs:documentation>\n};
	    print "  "x$indent . qq{  </xs:annotation>\n};
	}
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
my $special_profiles = {};
my $special_newitems = [];
my $special_items = [];

sub special_begin {}

sub special_node
{
    my ($node, $pnode, $profile, $object) = @_;

    my $type = $node->{type};
    my $path = $node->{path};
    my $name = $node->{name};
    my $majorVersion = $node->{majorVersion} || 0;
    my $minorVersion = $node->{minorVersion} || 0;

    # check for new profile
    if ($type eq 'profile') {
        $profile = $name;
    }

    # collect current profile definition
    elsif ($profile) {
        if ($type eq 'object') {
            $object = $name;
            $special_profiles->{$profile}->{$object} = 1;
        } else {
            $special_profiles->{$profile}->{$object.$name} = 1;
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

    foreach my $child (@{$node->{nodes}}) {
        special_node($child, $node, $profile, $object);
    }
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
                if $access ne 'readWrite' && $activeNotify ne 'canDeny';
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

# Expand all data model definition files.
foreach my $file (@ARGV) {
    expand_toplevel($file);
}

# Perform sanity checks etc, e.g. prune empty objects if --writonly
# XXX should be using the standard report_node framework?
sub sanity_node
{
    my ($node) = @_;

    my $path = $node->{path};
    my $name = $node->{name};
    my $type = $node->{type};
    my $access = $node->{access};
    my $syntax = $node->{syntax};
    my $values = $node->{values};
    my $default = $node->{default};
    my $dynamic = $node->{dynamic};
    my $minEntries = $node->{minEntries};
    my $maxEntries = $node->{maxEntries};
    my $description = $node->{description};

    my $object = ($type && $type eq 'object');
    my $parameter = ($type &&
                     $type !~ /model|object|profile|parameterRef|objectRef/);

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
        # XXX should check all descriptions, not just obj / par ones
        my $ibr = invalid_bibrefs($description);
        print STDERR "$path: invalid bibrefs: " . join(', ', @$ibr) . "\n" if
            @$ibr;
    }

    # object sanity checks
    if ($object) {
        print STDERR "$path: object is writable but not a table\n" if
            $access eq 'readWrite' && $maxEntries eq '1';
    }

    # parameter sanity checks
    if ($parameter) {
        # XXX this one is useless
	#print STDERR "$path: parameter is an enumeration but has " .
	#    "no values\n" if $pedantic && values_appropriate($name, $type) &&
	#    !has_values($values);

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

	print STDERR "$path: parameter within static object has " .
		"a default value\n" if $pedantic && !$dynamic &&
                defined($default) && !($syntax->{list} && $default eq '');

	# XXX other checks to make: profiles reference valid parameters,
	#     reference types, default is valid for type, other facets are
        #     valid for type (valid narrowing checks could be done here too,
        #     but would need to use history)
    }

    foreach my $child (@{$node->{nodes}}) {
	sanity_node($child);
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
# XXX when processing multiple files, this isn't currently reliable
my $spectotal = {};

sub spec_node
{
    my ($node) = @_;    
    $spectotal->{$node->{spec}}++ if $node->{spec};
}

if ($count) {
    # XXX would be nice to avoid use of the global variable here
    $report = 'spec';
    report_node($root);

    foreach my $spec (@$specs) {
	print STDERR "$spec: $spectotal->{$spec}\n" if
            defined $spectotal->{$spec} && !$quiet;
    }
}

# documentation
=head1 NAME

B<report.pl> - generate report on XML TR-069 data model definitions

=head1 SYNOPSIS

B<report.pl> [--autobase] [--count] [--debugpath=pattern("")] [--detail] [--help] [--ignore=pattern("")] [--importsuffix=string("")] [--lastonly] [--modelonly] [--noautomodel] [--nocomments] [--nomodels] [--noprofiles] [--objpat=pattern("")] [--pedantic[=i(1)] [--profileonly] [--quiet] [--report=html|(null)|tab|text|xls|xml|xsd] [--special=deprecated|normative|notify|obsoleted|profile|rfc] [--thisonly] [--ugly] [--verbose] [--writonly] data-model-definition-xml-file...

=over

=item * cannot specify both --report and --special

=back

=head1 DESCRIPTION

The files specified on the command line are assumed to be XML TR-069 data model definitions compliant with the I<cwmp:datamodel> XML schema.

The script parses, validates (ahem) and reports on these files, generating output in various possible formats to I<stdout>.

=head1 OPTIONS

=over

=item B<--autobase>

causes automatic addition of B<base> attributes when models, parameters and objects are re-defined, and suppression of redefinition warnings (useful when processing auto-generated data model definitions)

=item B<--count>

causes counts of total numbers of objects / parameters for each spec to be output

=item B<--debugpath=pattern("")>

outputs debug information for parameters and objects whose path names match the specified pattern

=item B<--detail>

causes more detail in the report, e.g. documentation in the generated B<xsd> file

=item B<--help>

requests output of usage information

=item B<--ignore>

specifies a pattern; matching data models will be ignored

=item B<--importsuffix=string("")>

specifies a suffix which, if specified, will be appended (preceded by a hyphen) to the name part of any imported files in b<xml> reports

=item B<--lastonly>

reports only on items that were defined or modified in the last file that was specified on the command line

note that the B<xml> report always does something similar but might not work properly if this option is specified

=item B<--noautomodel>

disables the auto-generation, if no B<model> element was encountered, of a B<Components> model that references each component

=item B<--nocomments>

disables generation of XML comments showing what changed etc (B<--verbose> always switches it off)

=item B<--nomodels>, B<--profileonly>

specifies that model definitions should not be reported (B<--profileonly> is deprecated)

=item B<--noprofiles>, B<--modelonly>

specifies that profile definitions should not be reported (B<--modelonly> is deprecated)

=item B<--objpat=pattern>

specifies an object name pattern (a regular expression); objects that do not match this pattern will be ignored (the default of "" matches all objects)

=item B<--pedantic=[i(1)]>

enables output of warnings to I<stderr> when logical inconsistencies in the XML are detected; if the option is specified without a value, the value defaults to 1

=item B<--quiet>

suppresses informational messages

=item B<--report=html|(null)|tab|text|xls|xml|xsd>

specifies the report format; one of the following:

=over

=item B<html>

HTML table

=item B<null>

no output; errors go to I<stdout> rather than I<stderr> (default)

=item B<tab>

tab-separated list, one object or parameter per line

=item B<text>

indented text

=item B<xls>

Excel XML spreadsheet

=item B<xml>

DM XML containing only the changes made by the final file on the command line; see also B<--autobase> and B<--lastonly>

=item B<xsd>

W3C schema; see also B<--detail>

=back

=item B<--special=normative|notify|profile|rfc>

performs special checks, most of which assume that several versions of the same data model have been supplied on the command line, and many of which operate only on the highest version of the data model

=over

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

=item B<--ugly>

disables some prettifications, e.g. inserting spaces to encourage line breaks, and omitting the B<spec> column in HTML reports

=item B<--verbose>

enables verbose output

=item B<--writonly>

reports only on writable parameters (should, but does not, suppress reports of read-only objects that contain no writable parameters)

=back

=head1 LIMITATIONS

This script is only for illustration of concepts and has many shortcomings.

=head1 AUTHOR

William Lupton E<lt>wlupton@2wire.comE<gt>

$Date: 2008/11/06 $

=cut
