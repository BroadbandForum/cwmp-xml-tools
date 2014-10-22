#!/usr/bin/perl -w
#
# Copyright (C) 2011, 2012  Pace Plc
# Copyright (C) 2012, 2013, 2014  Cisco Systems
# All Rights Reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# - Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# - Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# - Neither the names of the copyright holders nor the names of their
#   contributors may be used to endorse or promote products derived from this
#   software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# Parses MIB XML, conformant to http://www.ibr.cs.tu-bs.de/projects/nmrg/
# smi.xsd and generates XML output compliant with the CWMP data model XML
# Schema.  Each object is a component.

# XXX can this be a lot simpler? don't need to build a node tree; can just do
#     xpath expressions to extract what we are interested in

# XXX need to import type definitions from other MIBs (resolving {module,name})

# XXX need to have a proper way of handling versions for the main and included
#     MIBs

# XXX need to include references, history etc; in general, check that all
#     relevant information is copied, and consider cwmp-datamodel extensions,
#     e.g. more textual conventions or direct representation of references

# XXX and want to handle table _extension_? currently this information is lost

# XXX unique keys are generated but can reference parameters not in the table;
#     probably should embed such tables within the relevant other tables;
#     alternatively, add the parameter in question to the table

# XXX also (can't really do anything about it) there can be SNMP-specific
#     language in the descriptions...

# XXX need to think about further operations to perform, e.g. prefix removal
#     and more sophisticated name mapping (have only really tried to do this
#     for enumerated values)

# XXX various things don't work if there is more than one file, so should 
#     forbid this?

# XXX ranges in typedefs aren't handled as multi-valued; mins and maxes are
#     concatenated, e.g. for DateAndTime

# Begin documentation
=head1 NAME

mib2dm.pl - convert MIB XML to BBF DM Instances

=head1 SYNOPSIS

B<mib2dm.pl>
[--components]
[--noobjects]
[--noparameters]
[--pedantic[=i(1)]]
[--verbose]
[--help]
MIB-XML-file...

=over

=item * MIB XML must conform to
        http://www.ibr.cs.tu-bs.de/projects/nmrg/smi.xsd; the B<smidump> tool
        can be used to convert ASN.1 MIBs to such XML

=item * the most common option is --components

=back

=item B<--components>

causes components to be created (a) for top-level parameters (scalars) and (b) for each table; the generated data model then references these components

the component containing the top-level parameters has the same name as the MIB's first node, and the components containing table definitions are names the same as their tables

=item B<--noobjects>

suppresses generation of all objects, so the generated data model is flat and consists only of parameter definitions

=item B<--noparameters>

suppresses generation of all parameters (apart from NumberOfEntries parameters), so the generated data model is flat and consists only of object definitions

=item B<--pedantic[=i(1)]>

enables output of warnings to I<stderr> when logical inconsistencies in the XML are detected; if the option is specified without a value, the value defaults to 1

=item B<--verbose>

enables verbose output

=item B<--help>

requests output of usage information

=cut
# End documentation

use strict;
no strict "refs";

use Data::Dumper;
use File::Basename;
use Getopt::Long;
use Pod::Usage;
use XML::LibXML;

# cwmp-datamodel schema version
my $schema_version = "1-5";

# command-line options
my $components = 0;
my $help = 0;
my $noobjects = 0;
my $nooutput = 0;
my $noparameters = 0;
my $pedantic;
my $verbose = 0;
GetOptions('components' => \$components,
	   'help' => \$help,
	   'noobjects' => \$noobjects,
	   'nooutput' => \$nooutput,
	   'noparameters' => \$noparameters,
	   'pedantic:i' => \$pedantic,
	   'verbose' => \$verbose) or pod2usage(2);
pod2usage(1) if $help;

$pedantic = 1 if defined($pedantic) and !$pedantic;
$pedantic = 0 unless defined($pedantic);

# globals
my $root = {};

# pattern that matches TR-069 primitive types
my $primitive_patt = '(^base64|boolean|byte|dateTime|hexBinary|int|long|string|unsignedByte|unsignedInt|unsignedLong)$';

# well-known primitive type names will be mapped to TR-069 types
# XXX need to be careful to keep this list short and uncontroversial;
#     these are the four RFC 1155 primitive types plus Enumeration, plus...
# XXX Integer64, Unsigned32 and Unsigned64
# XXX OctetString isn't really a string; not sure about Bits
# XXX OctetString should sometimes be string, as a function of format?
my $primitive_map = {
    Bits => 'string',
    Enumeration => 'string',
    Integer => 'int',
    Integer32 => 'int',
    Integer64 => 'long',
    Null => 'int',
    ObjectIdentifier => 'string',
    OctetString => 'hexBinary',
    TruthValue => 'boolean',
    Unsigned32 => 'unsignedInt',
    Unsigned64 => 'unsignedLong',
};

# parse files specified on the command line
foreach my $file (@ARGV) {
    parse_file($file);
}

# output XML
output_xml();

# that's the end of the main program; all the rest is subroutines

# parse a MIB XML file
sub parse_file
{
    my ($file)= @_;

    print STDERR "processing file: $file\n" if $verbose;

    # parse file
    my $parser = XML::LibXML->new();
    my $tree = $parser->parse_file($file);
    my $toplevel = $tree->getDocumentElement;

    foreach my $thing ($toplevel->findnodes('*')) {
	my $element = findvalue($thing, 'local-name()');
	"expand_$element"->($thing);
    }

    # XXX this assumes that the output file will be named based on the input
    #     file; should add an --outfile option
    (my $vol, my $dir, $file) = File::Spec->splitpath($file);
    ($file, my $dirs, my $suff) = fileparse($file, '.xsm');
    $root->{file} = qq{$file.xml} unless $root->{file};
}

# expand module
sub expand_module
{
    my ($module) = @_;

    my $name = findvalue($module, '@name');
    my $language = findvalue($module, '@language');
    my $organization = findvalue($module, 'organization');
    my $contact = findvalue($module, 'contact');
    my $description = findvalue($module, 'description', {descr => 1});
    my $reference = findvalue($module, 'reference');
    my $identity_node = findvalue($module, 'identity/@node');

    print STDERR "expand_module name=$name organization=$organization\n"
	if $verbose;

    my $revisions = [];
    foreach my $revision ($module->findnodes('revision')) {
	push @$revisions, expand_revision($revision);
    }

    # try to derive meaningful spec from name, organization and latest
    # (lexically first) revision date
    # XXX there are various heuristics...

    # these are gen-delims and sub-delims from RFC 3986 (plus double quote,
    # which is omitted, maybe because single and double quote are elsewhere
    # stated to be equivalent)
    my $delims = qr{[\:\/\?\#\[\]\@\$\&\'\"\(\)\*\+\,\;\=]+};

    $name = lc $name;
    $name =~ s/_/-/g;
    $name =~ s/\s+/-/g;
    $name =~ s/\.//g;
    $name =~ s/$delims//g;

    $organization = lc $organization;
    $organization =~ s/.*\bcable television laboratories\b.*/cablelabs-org/;
    $organization =~ s/.*\bcablelabs\b.*/cablelabs-org/;
    $organization =~ s/.*\bieee\b.*/ieee-org/;
    $organization =~ s/.*\bietf\b.*/ietf-org/;
    $organization =~ s/.*\bmultimedia over coax\b.*/mocalliance-org/;
    $organization =~ s/_/-/g;
    $organization =~ s/\s+/-/g;
    $organization =~ s/\.//g;
    $organization =~ s/$delims//g;

    my $date = $revisions->[0]->{date};
    $date = '' unless $date;
    $date =~ s/\s.*// if $date;
    $date = qq{-$date} if $date;

    $root->{spec} = "urn:$organization:$name$date";
}

# expand revision
sub expand_revision
{
   my ($revision) = @_;

   my $date = findvalue($revision, '@date');
   my $description = findvalue($revision, 'description');

   print STDERR "expand_revision date=$date\n" if $verbose;

   return {date => $date, description => $description};
}

# expand imports
sub expand_imports
{
    my ($imports) = @_;

    print STDERR "expand_imports\n" if $verbose;

    foreach my $import ($imports->findnodes('import')) {
	push @{$root->{imports}}, expand_import($import);
    }
}

# expand import
sub expand_import
{
    my ($import) = @_;

    my ($module, $name) = get_module_and_name($import);

    print STDERR "expand_import module=$module name=$name\n" if $verbose;

    return {module => $module, name => $name};
}

# expand typedefs
sub expand_typedefs
{
    my ($typedefs) = @_;

    print STDERR "expand_typedefs\n" if $verbose;

    foreach my $typedef ($typedefs->findnodes('typedef')) {
        push @{$root->{typedefs}}, expand_typedef($typedef);
    }
}

# expand typedef
sub expand_typedef
{
    my ($typedef) = @_;

    my $name = findvalue($typedef, '@name');
    my $basetype = findvalue($typedef, '@basetype');
    my $status = findvalue($typedef, '@status');
    my $default = findvalue($typedef, 'default');
    my $format = findvalue($typedef, 'format');
    my $units = findvalue($typedef, 'units');
    my $description = findvalue($typedef, 'description', {descr => 1});
    my $reference = findvalue($typedef, 'reference');

    # XXX do we need to do this?
    $status = 'current' unless $status;

    print STDERR "expand_typedef name=$name basetype=$basetype " .
	"status=$status format=$format\n" if $verbose;

    my $hash = {};
    $hash->{name} = $name if $name;
    $hash->{basetype} = $basetype if $basetype;
    $hash->{status} = $status if $status;
    $hash->{default} = $default if $default;
    $hash->{format} = $format if $format;
    $hash->{units} = $units if $units;
    $hash->{description} = $description if $description;
    $hash->{reference} = $reference if $reference;

    foreach my $thing ($typedef->findnodes('parent|range|namednumber')) {
	my $element = findvalue($thing, 'local-name()');
	push @{$hash->{$element}}, "expand_$element"->($thing);
    }

    # XXX this avoids special case in loop above (better to treat parent
    #     separately)
    $hash->{parent} = $hash->{parent}->[0] if $hash->{parent};

    return $hash;
}

# expand parent
sub expand_parent
{
    my ($parent) = @_;

    my ($module, $name) = get_module_and_name($parent);

    print STDERR "expand_parent module=$module name=$name\n" if $verbose;

    return {module => $module, name => $name};
}

# expand range
sub expand_range
{
    my ($range) = @_;

    my $min = findvalue($range, '@min');
    my $max = findvalue($range, '@max');

    print STDERR "expand_range min=$min max=$max\n" if $verbose;

    return {min => $min, max => $max};
}

# expand namednumber
sub expand_namednumber
{
    my ($namednumber) = @_;

    my $name = findvalue($namednumber, '@name');
    my $number = findvalue($namednumber, '@number');

    print STDERR "expand_namednumber name=$name number=$number\n" if $verbose;

    return {name => $name, number => $number};
}

# expand nodes
sub expand_nodes
{
    my ($nodes) = @_;

    print STDERR "expand_nodes\n" if $verbose;

    foreach my $thing ($nodes->findnodes('node|scalar|table')) {
	my $element = findvalue($thing, 'local-name()');
	"expand_$element"->($thing);
    }
}

# expand node
sub expand_node
{
    my ($node) = @_;

    my ($name, $oid, $status) = get_name_oid_and_status($node);
    my $description = findvalue($node, 'description', {descr => 1});

    print STDERR "expand_node name=$name status=$status\n" if $verbose;

    # XXX currently ignore nodes except that note the name of the first one
    #     for use as the the component name for the scalars
    $root->{name} = $name unless $root->{name};
}

# expand scalar
sub expand_scalar
{
    my ($scalar) = @_;

    my ($name, $oid, $status) = get_name_oid_and_status($scalar);
    my $syntax = expand_syntax($scalar->findnodes('syntax'));
    my $access = findvalue($scalar, 'access');
    my $default = findvalue($scalar, 'default');
    my $format = findvalue($scalar, 'format');
    my $units = findvalue($scalar, 'units');
    my $description = findvalue($scalar, 'description',
				{descr => 1, values => $syntax->{values}});
    my $reference = findvalue($scalar, 'reference');

    print STDERR "expand_scalar name=$name status=$status\n" if $verbose;

    my $snode = {
	name => $name,
        oid => $oid,
	syntax => $syntax,
	status => $status,
	access => $access,
	default => $default,
	units => $units,
	description => $description,
        reference => $reference,
    };
    push @{$root->{scalars}}, $snode;
}

# expand syntax
sub expand_syntax
{
    my ($syntax) = @_;

    print STDERR "expand_syntax\n" if $verbose;

    foreach my $thing ($syntax->findnodes('type|typedef')) {
	my $element = findvalue($thing, 'local-name()');
	return convert_syntax("expand_$element"->($thing));
    }
}

# expand type
sub expand_type
{
    my ($type) = @_;

    my ($module, $name) = get_module_and_name($type);

    print STDERR "expand_type module=$module name=$name\n" if $verbose;

    return {module => $module, name => $name};
}

# expand table
sub expand_table
{
    my ($table) = @_;

    my ($name, $oid, $status) = get_name_oid_and_status($table);
    my $description = findvalue($table, 'description', {descr => 1});
    my $reference = findvalue($table, 'reference');

    print STDERR "expand_table name=$name status=$status\n" if $verbose;

    my $tnode = {
	name => $name,
        oid => $oid,
	status => $status,
	description => $description,
        reference => $reference,
	row => {},
    };
    push @{$root->{tables}}, $tnode;

    expand_row($tnode, $table->findnodes('row'));
}

# expand row
sub expand_row
{
    my ($tnode, $row) = @_;

    my ($name, $oid, $status) = get_name_oid_and_status($row);
    my $create = findvalue($row, '@create', {boolean => 1});
    my $linkage = expand_linkage($row->findnodes('linkage'));
    my $description = findvalue($row, 'description', {descr => 1});
    my $reference = findvalue($row, 'reference');

    print STDERR "expand_row name=$name create=$create status=$status\n"
	if $verbose;

    my $rnode = $tnode->{row} = {
	name => $name,
        oid => $oid,
	status => $status,
	create => $create,
	linkage => $linkage,
	description => $description,
        reference => $reference,
	columns => [],
    };

    foreach my $column ($row->findnodes('column')) {
	expand_column($rnode, $column);
    }
}

# expand linkage
sub expand_linkage
{
    my ($linkage) = @_;

    my $implied = findvalue($linkage, '@implied', {boolean => 1});

    print STDERR "expand_linkage implied=$implied\n" if $verbose;

    my $hash = {};
    $hash->{implied} = $implied if $implied;

    # XXX ignoring reorders, sparse and expands
    foreach my $thing ($linkage->findnodes('index|augments')) {
	my $element = findvalue($thing, 'local-name()');
	push @{$hash->{$element}}, "expand_$element"->($thing);
    }

    # XXX this avoids special case in loop above (better to treat augments
    #     separately)
    $hash->{augments} = $hash->{augments}->[0] if $hash->{augments};

    return $hash;
}

# expand index
sub expand_index
{
    my ($index) = @_;

    my ($module, $name) = get_module_and_name($index);

    print STDERR "expand_index module=$module name=$name\n" if $verbose;

    return {module => $module, name => $name};
}

# expand augments
sub expand_augments
{
    my ($augments) = @_;

    my ($module, $name) = get_module_and_name($augments);

    print STDERR "expand_augments module=$module name=$name\n" if $verbose;

    return {module => $module, name => $name};
}

# expand column
sub expand_column
{
    my ($rnode, $column) = @_;

    my ($name, $oid, $status) = get_name_oid_and_status($column);
    my $syntax = expand_syntax($column->findnodes('syntax'));
    my $access = findvalue($column, 'access');
    my $default = findvalue($column, 'default');
    my $format = findvalue($column, 'format');
    my $units = findvalue($column, 'units');
    my $description = findvalue($column, 'description',
				{descr => 1, values => $syntax->{values}});
    my $reference = findvalue($column, 'reference');

    print STDERR "expand_column name=$name status=$status access=$access\n"
	if $verbose;

    my $cnode = {
	name => $name,
        oid => $oid,
	syntax => $syntax,
	status => $status,
	access => $access,
	default => $default,
	units => $units,
	description => $description,
        reference => $reference,
    };
    push @{$rnode->{columns}}, $cnode;
}

# expand notifications
sub expand_notifications
{
    my ($notifications) = @_;

    print STDERR "expand_notifications\n" if $verbose;

    foreach my $notification ($notifications->findnodes('notification')) {
	expand_notification($notification);
    }
}

# expand notification
sub expand_notification
{
    my ($notification) = @_;

    my ($name, $oid, $status) = get_name_oid_and_status($notification);
    my $description = findvalue($notification, 'description');
    my $reference = findvalue($notification, 'reference');

    print STDERR "expand_notification name=$name status=$status\n" if $verbose;

    expand_objects($notification->findnodes('objects'));
}

# expand objects
sub expand_objects
{
    my ($objects) = @_;

    print STDERR "expand_objects\n" if $verbose;

    foreach my $object ($objects->findnodes('object')) {
	expand_object($object);
    }
}

# expand object
sub expand_object
{
    my ($object) = @_;

    my ($module, $name) = get_module_and_name($object);

    print STDERR "expand_object module=$module name=$name\n" if $verbose;
}

# expand groups
sub expand_groups
{
    my ($groups) = @_;

    print STDERR "expand_groups\n" if $verbose;

    foreach my $group ($groups->findnodes('group')) {
	expand_group($group);
    }
}

# expand group
sub expand_group
{
    my ($group) = @_;

    my ($name, $oid, $status) = get_name_oid_and_status($group);
    my $description = findvalue($group, 'description', {descr => 1});
    my $reference = findvalue($group, 'reference');

    print STDERR "expand_group name=$name status=$status\n" if $verbose;

    expand_members($group->findnodes('members'));
}

# expand members
sub expand_members
{
    my ($members) = @_;

    print STDERR "expand_members\n" if $verbose;

    foreach my $member ($members->findnodes('member')) {
	expand_member($member);
    }
}

# expand member
sub expand_member
{
    my ($member) = @_;

    my ($module, $name) = get_module_and_name($member);

    print STDERR "expand_member module=$module name=$name\n" if $verbose;
}

# expand compliances
sub expand_compliances
{
    my ($compliances) = @_;

    print STDERR "expand_compliances\n" if $verbose;

    foreach my $compliance ($compliances->findnodes('compliance')) {
	expand_compliance($compliance);
    }
}

# expand compliance
sub expand_compliance
{
    my ($compliance) = @_;

    my ($name, $oid, $status) = get_name_oid_and_status($compliance);
    my $description = findvalue($compliance, 'description', {descr => 1});

    print STDERR "expand_compliance name=$name status=$status\n" if $verbose;

    foreach my $thing ($compliance->findnodes('requires|refinements')) {
	my $element = findvalue($thing, 'local-name()');
	"expand_$element"->($thing);
    }
}

# expand requires
sub expand_requires
{
    my ($requires) = @_;

    print STDERR "expand_requires\n" if $verbose;

    foreach my $thing ($requires->findnodes('mandatory|option')) {
	my $element = findvalue($thing, 'local-name()');
	"expand_$element"->($thing);
    }
}

# expand mandatory
sub expand_mandatory
{
    my ($mandatory) = @_;

    my ($module, $name) = get_module_and_name($mandatory);

    print STDERR "expand_mandatory module=$module name=$name\n" if $verbose;
}

# expand option
sub expand_option
{
    my ($option) = @_;

    my ($module, $name) = get_module_and_name($option);
    my $description = findvalue($option, 'description', {descr => 1});

    print STDERR "expand_option module=$module name=$name\n" if $verbose;
}

# expand refinements
sub expand_refinements
{
    my ($refinements) = @_;

    print STDERR "expand_refinements\n" if $verbose;

    foreach my $refinement ($refinements->findnodes('refinement')) {
	expand_refinement($refinement);
    }
}

# expand refinement
sub expand_refinement
{
    my ($refinement) = @_;

    my ($module, $name) = get_module_and_name($refinement);
    my $access = findvalue($refinement, 'access');
    my $description = findvalue($refinement, 'description', {descr => 1});

    print STDERR "expand_refinement module=$module name=$name access=$access\n"
	if $verbose;

    my $syntax = ($refinement->findnodes('syntax'))[0];
    expand_syntax($syntax) if $syntax;
}

# convert syntax from one of the following forms:
#  type:    {module => m, name => n}
#  typedef: {name => n, basetype => b, status => s,
#            parent => {module => n, name => n},
#            range => [{min => m, max => m}, ...],
#            namednumber => [{number => n, name => n}, ...],
#            default => d, format => f, units => u,
#            description => d, reference => r}
#
# to the following more convenient form:
# XXX need to fix list in the same way that have done in tr2dm.pl
#  {type => t, base => b, ref => r, description => d,
#   values => {list => l,
#              [{optional => o, description => d, value => v}, ...]},
#   sizes  => [{min => m, max => m}, ...],
#   ranges => [{min => m, max => m}, ...]}
#
# 'type' is always a reference to a type defined in another module
# 'typedef' defines a new type, either named or anonymous, and always has a
#           basetype
#
# 'basetype' is the primitive base type (I think)
# 'parent' is the type from which this one is derived
# 'range' indicates the length range (for octet/string types) or the
#         value range (for numeric types)
# 'format' distinguishes between binary and string types (do any binary types
#          have formats... presumably not?)
#
# the ASN.1 primitive types (RFC 1155) are Integer, OctetString,
# ObjectIdentifier and Null; all other types are derived from them
# (actually some other types seem to be treated as primitive, e.g.
# Integer32 and Enumeration)
sub convert_syntax
{
    my ($in) = @_;

    # XXX should be able to leave name blank; should call it "name"?
    # XXX need to be more rigorous wrt name, base and ref
    my $name = $in->{name} ? $in->{name} : '';
    my $ref = $in->{parent}->{name} ? $in->{parent}->{name} : '';
    $ref = $in->{basetype} if !$ref && $in->{basetype};
    $name = $ref unless $name;
    $name = $primitive_map->{$name} if $primitive_map->{$name};
    my $out = {type => $name, base => $ref, ref => $ref};

    foreach my $item (@{$in->{namednumber}}) {
	my $value = ucfirst $item->{name};
        my $code = $item->{number};
	push @{$out->{values}->{values}}, {value => $value, code => $code};
    }

    # XXX for now, if there are values, force the type to be 'string'
    #     (do we need values on imported data types? if so, facet is looking
    #     more attractive)
    # XXX no
    #$out->{type} = 'string' if $out->{values};

    # range refers to string length for strings and to numeric range otherwise
    # XXX this is problematic, since can't necessarily tell this, so have to
    #     apply heuristics
    # XXX including DisplayString and SnmpAdminString here is a hack, because I
    #     don't really understand the ASN.1/SMI logic
    foreach my $item (@{$in->{range}}) {
        if ($out->{values} || $out->{type}
            =~ /^(base64|hexBinary|string|DisplayString|SnmpAdminStrin)$/) {
            push @{$out->{sizes}}, $item;
        } else {
            push @{$out->{ranges}}, $item;
        }
    }

    $out->{description} = $in->{description};
    $out->{reference} = $in->{reference};
    $out->{units} = $in->{units};

    # XXX similarly should force a numeric type if there are ranges, but which
    #     type?
    # XXX no

    return $out;
}

# get module and name attributes
sub get_module_and_name
{
    my ($node) = @_;

    my $module = findvalue($node, '@module');
    my $name = findvalue($node, '@name');

    return ($module, $name);
}

# get name, oid and status
sub get_name_oid_and_status
{
    my ($node) = @_;

    my $name = findvalue($node, '@name');
    my $oid = findvalue($node, '@oid');
    my $status = findvalue($node, '@status');

    # XXX do we need to do this?
    $status = 'current' unless $status;

    return ($name, $oid, $status);
}

# find a value and tidy the resulting string
#
# white space options are passed to white_strip; other options processed
# here are:
#  - boolean: convert to boolean 0/1
#  - descr: special processing for descriptions
sub findvalue
{
    my ($node, $xpath, $opts) = @_;

    $opts->{ignoremultiblank} = $opts->{descr};
    my $string = white_strip($node->findvalue($xpath), $opts);

    # optionally convert to boolean 0/1
    if ($opts->{boolean}) {
	$string = boolean($string);
    }

    # optionally remove single newlines, change leading "-" to "*",
    # change 'value(n)' strings to 'Value' where "value" is one of the
    # possible enumerated values, and other sundry edits
    if ($opts->{descr}) {
	# XXX need to be a bit cleverer, e.g. retaining the list nature where
	#     indentation is used to set off items (including use of leading
	#     "--" characters)
	# XXX also doesn't catch cases where an enumerated value is referenced
	#     in another parameter's description
        # XXX also newline handling needs to be cleverer; need heuristic to
        #     determine when it's the end of a paragraph
	$string =~ s/([^\n])\n/$1 /g;
	$string =~ s/\n-/\n*/g;
	foreach my $tvalue (@{$opts->{values}->{values}}) {
	    my $value = $tvalue->{value};
	    $string =~ s/(\s+)$value\(\d+\)/$1\"$value\"/ig;
	    $string =~ s/[\'\"]$value[\'\"]/\"$value\"/ig;
	}
        # change `word' and 'word' to "word"
        # XXX doesn't catch 'on top of' (for example)
        $string =~ s/(\W)[\`\'](\S+)\'(\W)/$1\"$2\"$3/g;

	$string =~ s/(false|true)\(\d+\)/$1/g;
	$string =~ s/\bdeprecated\b/DEPRECATED/g;
    }

    return $string;
}

# strip leading and trailing white space and, optionally, other space
sub white_strip
{
    my ($string, $opts) = @_;

    # always remove leading and trailing white space
    $string =~ s/^\s*//g;
    $string =~ s/\s*$//g;

    # also any spaces or tabs after newlines
    $string =~ s/\n[ \t]*/\n/g;

    # optionally ignore multiple blank lines (usually a formatting error)
    $string =~ s/\n([ \t]*\n){2,}/ /gs if $opts->{ignoremultiblank};

    # optionally collapse multiple spaces
    $string =~ s/\s+/ /g if $opts->{collapse};

    # optionally remove all white space
    if ($opts->{black}) {
	my $orig = $string;
	$string =~ s/\s+//g;
	print STDERR "white_strip: had to remove extra spaces in $orig\n" if
	    $pedantic && $opts->{blackwarn} && $string ne $orig;
    }

    return $string;
}

# return 0/1 given string representation of boolean
sub boolean
{
    my ($value) = @_;
    return ($value =~ /1|t|true/i) ? 1 : 0;
}

# output multi-line string to stdout, handling indentation
sub output
{
    my ($indent, $lines) = @_;

    return if $nooutput;

    foreach my $line (split /\n/, $lines) {
        print '  ' x $indent, $line, "\n";
	$indent = 0;
    }
}

# output XML
sub output_xml
{
    my $i = 0;

    # start of XML
    my $spec = $root->{spec};
    my $file = $root->{file};
    output $i, qq{<?xml version="1.0" encoding="UTF-8"?>};
    output $i, qq{<dm:document xmlns:dm="urn:broadband-forum-org:cwmp:datamodel-$schema_version"};
    output $i, qq{             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"};
    output $i, qq{             xsi:schemaLocation="urn:broadband-forum-org:cwmp:datamodel-$schema_version http://www.broadband-forum.org/cwmp/cwmp-datamodel-$schema_version.xsd"};
    output $i, qq{             spec="$spec" file="$file">};

    # output imports (need to be grouped by module)
    my $modules = {};
    my $index = 0;
    # XXX always import fundamental types (not all are needed because some are
    #     mapped to primitive types); these should be imported from RFC 1155
    #     (or avoid the need, by never referencing them directly?)
    #foreach my $name (('Integer|Null|ObjectIdentifier|OctetString')) {
    #    push @{$modules->{'SNMPv2-SMI'}}, {name => $name, index => $index++};
    #}
    foreach my $import (@{$root->{imports}}) {
        my $module = $import->{module};
        my $name = $import->{name};
        # XXX this is rather heuristic; how to tell which are data types to be
        #     imported?
        next if $name =~ /MODULE-COMPLIANCE|MODULE-IDENTITY|NOTIFICATION-GROUP|NOTIFICATION-TYPE|OBJECT-GROUP|OBJECT-IDENTITY|OBJECT-TYPE|TEXTUAL-CONVENTION|mib-2/;
        next if $name =~ /^[a-z]/;
        push @{$modules->{$module}}, {name => $name, index => $index++};
    }
    foreach my $module (sort {$modules->{$a}->[0]->{index} <=> $modules->{$b}->[0]->{index}} keys %$modules) {
        $i++;
        output $i, qq{<import file="$module.xml">};
        foreach my $import (@{$modules->{$module}}) {
            my $name = $import->{name};
            output $i+1, qq{<dataType name="$name"/>};
        }
        output $i, qq{</import>};
        $i--;
    }

    # output typedefs
    # XXX need to add status to the DM schema
    # XXX ignoring default, format and parent
    # XXX shouldn't ignore default, here or on parameters
    # XXX overlapping logic with convert_syntax (do without convert_syntax?)
    foreach my $typedef (@{$root->{typedefs}}) {
        my $name = $typedef->{name};
        my $basetype = $typedef->{basetype};
        my $status = $typedef->{status};
        my $description = $typedef->{description};
        my $reference = $typedef->{reference};
        my $range = $typedef->{range};
        my $namednumber = $typedef->{namednumber};
        my $units = $typedef->{units};

        $description = xml_escape($description);

        $reference = $reference ? qq{{{bibref|$reference}}} : qq{};

        $basetype = $primitive_map->{$basetype} if $primitive_map->{$basetype};

        my $base = ($basetype !~ /$primitive_patt/) ?
            qq{ base="$basetype"} : qq{};
        
        $status =~ s/obsolete/obsoleted/;
	$status = ($status ne 'current') ? qq{ status="$status"} : qq{};

        my $end_element = ($range || $namednumber || $units) ? '' : '/';

        $i++;
        output $i, qq{<dataType name="$name"$base$status>};
        output $i+1, qq{<description>$description$reference</description>} if $description;
        unless ($base) {
            $i++;
            output $i, qq{<$basetype$end_element>};
        }
        foreach my $range (@$range) {
            if ($basetype =~ /^(base64|hexBinary|string)$/) {
                output $i+1, qq{<size minLength="$range->{min}" maxLength="$range->{max}"/>};
            } else {
                output $i+1, qq{<range minInclusive="$range->{min}" maxInclusive="$range->{max}"/>};
            }
        }
        foreach my $item (@$namednumber) {
            # XXX duplicate code; not handling optional
            # XXX do we want this capitalisation logic?
            my $value = ucfirst $item->{name};
            my $code = $item->{number};
            output $i+1, qq{<enumeration value="$value" code="$code"/>};
        }
        if ($units) {
            output $i+1, qq{<units value="$units"/>};
        }
        unless ($base) {
            output $i, qq{</$basetype>} unless $end_element;
            $i--;
        }
        output $i, qq{</dataType>};
        $i--;
    }

    # determine whether will create top-level component and model
    my $scalars = defined $root->{scalars};
    my $model = $scalars || defined $root->{tables};

    # output top-level component or model
    $i++;
    if ($components) {
	output($i, qq{<component name="$root->{name}">}) if $scalars;
    } else {
	output($i, qq{<model name="$root->{name}:1.0">}) if $model;
    }

    # output scalars (top-level parameters)
    if ($scalars && @{$root->{scalars}} && !$noparameters) {
        unless ($noobjects) {
            output($i+1, qq{<object name="$root->{name}." access="readOnly" } .
                   qq{minEntries="1" maxEntries="1">});
            output($i+2, qq{<description>});
            output($i+3, qq{$root->{name} scalars.});
            output($i+2, qq{</description>});
        }
        foreach my $scalar (@{$root->{scalars}}) {
            output_parameter($scalar, $i + !$noobjects);
        }
        unless ($noobjects) {
            output($i+1, qq{</object>});
        }
    }

    # terminate top-level component or output #entries parameters
    if ($components) {
	output($i, qq{</component>}) if $scalars;
        $i--;
    } else {
        unless ($noobjects) {
            foreach my $table (@{$root->{tables}}) {
                my $name = $table->{name};
                $i++;
                output $i, qq{<parameter name="${name}NumberOfEntries" access="readOnly">};
                output $i+1, qq{<description>{{numentries}}</description>};
                output $i+1, qq{<syntax>};
                output $i+2, qq{<unsignedInt/>};
                output $i+1, qq{</syntax>};
                output $i, qq{</parameter>};
                $i--;
            }
        }
    }

    # output tables (note we use the row OID, not the table OID)
    foreach my $table (@{$root->{tables}}) {
	my $name = $table->{name};
	my $oid = $table->{row}->{oid};
	my $status = $table->{status};
	my $description = $table->{description};
        my $reference = $table->{reference};

        $description = xml_escape($description);

	# XXX is this what create means?
	my $access = $table->{row}->{create} ? 'readWrite' : 'readOnly';
        $status =~ s/obsolete/obsoleted/;
	$status = ($status ne 'current') ? qq{ status="$status"} : qq{};

        $reference = $reference ? qq{{{bibref|$reference}}} : qq{};

	if ($components) {
	    my $cname = $name;
	    $i++;
	    output $i, qq{<component name="$cname">};
            unless ($noobjects) {
                $i++;
                output $i, qq{<parameter name="${name}NumberOfEntries" access="readOnly">};
                output $i+1, qq{<description>{{numentries}}</description>};
                output $i+1, qq{<syntax>};
                output $i+2, qq{<unsignedInt/>};
                output $i+1, qq{</syntax>};
                output $i, qq{</parameter>};
                $i--;
            }
	}

	unless ($noobjects) {
	    my $oname = $name . '.{i}';
	    my $rowdesc = $table->{row}->{description};
	    my $rowref = $table->{row}->{reference};
            $rowref = $rowref ? qq{{{bibref|$rowref}}} : qq{};
	    $i++;
	    output $i, qq{<object name="$oname." id="$oid" access="$access" minEntries="0" maxEntries="unbounded" numEntriesParameter="${name}NumberOfEntries"$status>};
            my $augmentsdesc = '';
	    my $linkage = $table->{row}->{linkage};
            if ($linkage->{augments}) {
                my $module = $linkage->{augments}->{module};
                my $name = $linkage->{augments}->{name};
                $name =~ s/Entry/Table/;
                $augmentsdesc = qq{\nThis table augments the ''$module }.
                    qq{$name'', i.e. it conceptually includes everything }.
                    qq{in that table and adds additional parameters.};
            }
                
            my $shareddesc = '';
            my @unique = ();
	    if (defined $linkage->{index} && @{$linkage->{index}}) {
                my @shared = ();
		foreach my $index (@{$linkage->{index}}) {
		    # XXX should check module?
		    if (grep {$_->{name} eq $index->{name}}
                        @{$table->{row}->{columns}}) {
                        push @unique, $index->{name};
                    } else {
                        push @shared, $index->{name};
                    }
                }
                # XXX for shared indices, can add the index or can embed
                #     this table within the table that contains the
                #     index (the latter seems least invasive)
                if (@shared) {
                    my $list = join ', ', @shared;
                    $shareddesc = qq{\nThis table shares the following }.
                        qq{keys: ''$list'', i.e. it's conceptually a }.
                        qq{child of the table(s) that have those keys.};
                }
            }

	    output $i+1, qq{<description>{{section|table}}$description${reference}\n{{section|row}}$rowdesc$rowref$augmentsdesc$shareddesc</description>};

            if (@unique) {
                my $any = 0;
                foreach my $name (@unique) {
                    output $i+1, qq{<uniqueKey>} unless $any++;
                    output $i+2, qq{<parameter ref="$name"/>};
		}
		output $i+1, qq{</uniqueKey>} if $any;
	    }
	}

	unless ($noparameters) {
	    foreach my $column (@{$table->{row}->{columns}}) {
                output_parameter($column, $i);
	    }
	}

	unless ($noobjects) {
	    output $i, qq{</object>};
	    $i--;
	}

	if ($components) {
	    output $i, qq{</component>};
	    $i--;
	}
    }

    # if collected components, create super-component and output model now
    if ($components) {
        $i++;
	output($i, qq{<component name="$root->{name}All">});
        output($i+1, qq{<component ref="$root->{name}"/>}) if $scalars;
	foreach my $table (@{$root->{tables}}) {
	    output($i+1, qq{<component ref="$table->{name}"/>});
	}
	output($i, qq{</component>});
        if ($model) {
            output($i, qq{<model name="$root->{name}:1.0">});
            output($i+1, qq{<component ref="$root->{name}All"/>});
        }
    }

    # end of XML
    output($i, qq{</model>}) if $model;
    $i--;
    output $i, qq{</dm:document>};
}

# output parameter (either scalar or table column)
sub output_parameter
{
    my ($parameter, $i) = @_;

    my $name = $parameter->{name};
    my $oid = $parameter->{oid};
    my $status = $parameter->{status};
    my $syntax = $parameter->{syntax};
    my $access = $parameter->{access};
    my $units = $parameter->{units};
    my $description = xml_escape($parameter->{description});
    my $reference = $parameter->{reference};
    
    $description = xml_escape($description);
    
    # XXX for now treat 'noaccess' as 'readwrite' because it's used for table
    #     keys
    $access = ($access =~ 'readwrite|noaccess') ? 'readWrite' : 'readOnly';
    $status =~ s/obsolete/obsoleted/;
    $status = ($status ne 'current') ? qq{ status="$status"} : qq{};

    $reference = $reference ? qq{{{bibref|$reference}}} : qq{};

    my $type = $syntax->{type};
    my $sizes = $syntax->{sizes};
    my $ranges = $syntax->{ranges};
    my $values = $syntax->{values};

    my $list = ($values && defined $values->{list} &&
                boolean($values->{list}));
                
    my $end_element = ($sizes || $ranges || $values || $units) ? '' : '/';

    my $baseref = $end_element ? 'ref' : 'base';
    my $dataType = ($type =~ /$primitive_patt/) ? $type : 'dataType';
    $baseref = ($dataType eq 'dataType') ? qq{ $baseref="$type"} : qq{}; 

    output $i+1, qq{<parameter name="$name" id="$oid" access="$access"$status>};
    output $i+2, qq{<description>$description$reference</description>};
    output $i+2, qq{<syntax>};
    output $i+3, qq{<list/>} if $list;
    output $i+3, qq{<$dataType$baseref$end_element>};
    if ($sizes) {
        foreach my $size (@$sizes) {
            output $i+4, qq{<size minLength="$size->{min}" maxLength="$size->{max}"/>};
        }
    }
    if ($ranges) {
        foreach my $range (@$ranges) {
            output $i+4, qq{<range minInclusive="$range->{min}" maxInclusive="$range->{max}"/>};
        }
    }
    if ($values) {
        foreach my $value (@{$values->{values}}) {
            my $optional = $value->{optional};
            $optional = (defined($optional) && boolean($optional)) ?
                qq{ optional="true"} : qq{};
            if ($value->{description}) {
                output $i+4, qq{<enumeration value="$value->{value}" code="$value->{code}"$optional>};
                output $i+5, qq{<description>$description</description>};
                output $i+4, qq{</enumeration>};
            } else {
                output $i+4, qq{<enumeration value="$value->{value}" code="$value->{code}"$optional/>};
            }
        }
    }
    output $i+4, qq{<units value="$units"/>} if $units;
    output $i+3, qq{</$dataType>} unless $end_element;
    output $i+2, qq{</syntax>};
    output $i+1, qq{</parameter>};
}

# escape characters that are special to XML
sub xml_escape
{
    my ($value, $opts) = @_;

    # XXX probably needing to do this implies a bug elsewhere?
    $value = '' unless $value;

    $value =~ s/\&/\&amp;/g;
    $value =~ s/\</\&lt;/g;
    $value =~ s/\>/\&gt;/g;

    # only quote quotes in attribute values
    $value =~ s/\"/\&quot;/g if $opts->{attr};

    return $value;
}
