# Copyright (C) 2011, 2012  Pace Plc
# Copyright (C) 2012, 2013, 2014  Cisco Systems
# Copyright (C) 2016, 2017  Honu Ltd
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

# BBF report tool plugin to process a DM Instance and (as far as possible) map
# its parameters and objects to a supplied data model, e.g. to TR-181i2, TR-135
# or TR-140
#
# based on ../report-tool/plugins/tr98map/tr98map.pm and
#          ../data-models/nds-panorama/ndsmap.pm

# example invocation: (the first model is mapped to the second model,
# according to mapping rules specified in the supplied configuration file)
#
# ../report-tool/report.pl --include=../data-models/bbf-published \
#                          --plugin map --report=map \
#                          --configfile=tr98map.ini --outfile=tr98map.txt \
#                          tr-098-1-6.xml tr-181-2-6.xml

# if the first and second models are the same this provides a way of copying
# objects and their parameters, e.g. of deriving a vendor extension object
# from a standard object

# XXX how to document plugins?

# XXX how to signal errors in plugins? via die (caught by caller)?

# XXX how to support "first class" options in plugins?

# XXX warn of invalid or unusual use/absence of vendor prefixes

# XXX consider HOCON or YAML for the config file (YAML has better Perl
#     support?)

# XXX a common syntax error is to place "="/"+" before the patterns;
#     should detect and warn about this

# XXX should check that all config file entries are used; if not used they
#     probably contain typos

package map;

use strict;

# XXX uncomment to enable traceback on warnings and errors
#use Carp::Always;

use Data::Dumper;
use List::MoreUtils qw{uniq};

# forward declarations
sub action;
sub output;
sub output_root_open;
sub output_root_close;
sub output_datatypes;
sub output_model_open;
sub output_model_close;
sub output_object_open;
sub output_object_close;
sub output_parameter;

# command-line options (passed via --option mode=xml etc)
my $options = {
    mode => 'text'
};

# config file globals (defaults can be placed here)
# XXX it's expedient to take these from the config file but some should
#     really come from command-line options (or be overrideable via
#     command-line options)
my $globals = {
    'noarrays' => 0,
    'noautocreate' => 0,
    'nodefaultname' => 0,
    'tr98map' => 0
};

# config file object and parameter mappings
my $object_mappings = {};
my $parameter_mappings = {};

# parse config file and process to generate object and parameter mappings of
# exactly the same format that was used when they were hard-coded Perl hashes
sub map_init {
    # determine output mode
    $options->{mode} = $main::options->{mode} if $main::options->{mode};
    die "invalid output mode $options->{mode}: specify --option mode=text|xml"
        unless $options->{mode} =~ /^(text|xml)$/;

    # find config file
    my $configfile = $main::configfile;
    if ($configfile) {
        my ($dir, $file) = main::find_file($configfile, "");
        $configfile = File::Spec->catfile($dir, $file) if $dir;
    }

    # parse config file
    my $config = {};
    if ($configfile) {
        require Config::IniFiles;

        my %config;
        tie %config, 'Config::IniFiles', ( -file => $configfile,
                                           -allowcontinue => 1 );
        $config = \%config;
        if (@Config::IniFiles::errors) {
            foreach my $error (@Config::IniFiles::errors) {
                main::emsg "$configfile: $error";
            }
            return;
        }    
    }

    # scan the resultant hash and convert to the original object and parameter
    # mappings
    foreach my $section (keys %$config) {
        # globals are handled separately; they aren't validated because we
        # don't want to need prior knowledge of what is permitted
        # XXX could/should check for invalid cases, e.g. attempt to define
        #     globals A and A.B (which is not permitted)
        if ($section eq 'Global') {
            foreach my $name (keys %{$config->{$section}}) {
                my $value = $config->{$section}->{$name};

                # allow one level of hierarchy within globals; the top-level
                # name should be one of the other section names but this isn't
                # checked
                my ($a, $b) = $name =~ /([^\.]+)\.(.+)/;
                if ($a && $b) {
                    $globals->{$a}->{$b} = $value;
                } else {
                    $globals->{$name} = $value;
                }
            }
            next;
        }

        # the section is expected to be "Device", the name of a Service model
        # with "Service" removed, e.g. "STB", or "Fallback"
        foreach my $name (keys %{$config->{$section}}) {
            my $value = $config->{$section}->{$name};

            # for object mappings the name always ends with a period;
            my $is_object = ($name =~ /\.$/);
            my $mappings = $is_object ? $object_mappings : $parameter_mappings;

            # scalar values have leading and trailing white space removed and
            # other white space collapsed
            if (ref($value) ne 'ARRAY') {
                $value =~ s/^\s*//;
                $value =~ s/\s*$//;
                $value =~ s/\s+/ /g;
            }

            # array values are (smartly) concatenated
            elsif (!$is_object && $globals->{noarrays}) {
                main::emsg "$configfile:$section:$name: array ignored: [" .
                    join(',', @$value) . "]";
            } else {
                my $text = qq{};
                my $comm = qq{};
                foreach my $val (@$value) {
                    # white space cleanup (as in the non-array case)
                    $val =~ s/^\s*//;
                    $val =~ s/\s*$//;
                    $val =~ s/\s+/ /g;

                    # comma separators aren't needed, so check for them
                    main::w0msg "$configfile:$section:$name: trailing comma ".
                        "ignored in $val" if $val =~ /,$/;
                    $val =~ s/,*$//;

                    # comment text is collected separately (comments are only
                    # expected at the end but are permitted anywhere)
                    my ($v, $c) = $val =~ /([^#]*)#?\s*(.*)/;
                    if ($v) {
                        # handle continuation
                        if ($text =~ /\\$/) {
                            $text =~ s/\s\\$//;
                        } elsif ($text) {
                            $text .= qq{,};
                        }
                        $text .= $v;
                    }
                    if ($c) {
                        $comm .= qq{; } if $comm;
                        $comm .= $c;
                    }
                }
                $value = $text;
                $value .= qq{ # $comm} if $comm;
            }

            # fallback mappings are identified by the name "Fallback" in the
            # config file but by the empty string in the original mappings
            $section = '' if $section eq 'Fallback';

            # add the mapping
            $mappings->{$section}->{$name} = $value;
        }
    }

    main::d0msg "globals: ", Dumper($globals);
    main::d0msg "object mappings: ", Dumper($object_mappings);
    main::d0msg "parameter mappings: ", Dumper($parameter_mappings);
}

# collect all objects and profiles, indexed by data model
my $model = -1;
my $nodes = [];
my $objects = [];
my $profiles = [];

# this is called for each node
sub map_node {
    my ($node, $indent) = @_;

    my $type = $node->{type};
    my $path = $node->{path};
    my $syntax = $node->{syntax};

    # models (derive relevant info and save in globals)
    if ($type eq 'model') {
        $globals->{bbffile} = $node->{file} . '.xml';
        $globals->{bbfspec} = $node->{spec};
        ($globals->{model}, $globals->{version}) =
            $node->{name} =~ /([^:]*):(.*)/;
        $model++;
    }

    # objects and parameters
    $nodes->[$model]->{$path} = $node if $type eq 'object' || $syntax;

    # objects
    push @{$objects->[$model]}, $node if $type eq 'object';

    # profiles
    if ($type eq 'profile') {
        foreach my $item (@{$node->{nodes}}) {
            update_profiles($node, $item);
        }
    }
}

# update list of profiles referenced by a given object or parameter
sub update_profiles {
    my ($profile, $item) = @_;

    my $path = $item->{path};
    my $access = $item->{access};

    # only use objects and parameters with specific requirements
    push @{$profiles->[$model]->{$path}}, $profile
        if $access =~ /^(create|delete|createDelete|readOnly|readWrite)$/;

    foreach my $child (@{$item->{nodes}}) {
        update_profiles($profile, $child);
    }
}

# process objects and parameters
sub map_end {
    # there have to be either one or two data models
    if (!@$objects || @$objects > 2) {
        main::emsg "there have to be either one or two data models\n";
        return;
    }

    # the output data model is determined by the last data model; determine
    # its root object name
    my $root = $objects->[-1]->[0]->{path};

    # this is "Device.", "STBService.{i}.", "StorageService.{i}." etc;
    # remove the trailing "Service.{i}" (if present) and ".", leaving
    # "Device", "STB", "Storage" etc
    $root =~ s/(Service\.\{i\})?\.//;

    # begin
    action {
        oper => 'Begin',
        root => $root
    };

    # process all objects from first data model
    foreach my $object (@{$objects->[0]}) {
        next if main::util_is_omitted($object);

        my $path = $object->{path};

        my ($path1s, $comment) = mapped_object_paths($root, $path);
        #main::tmsg "path $path -> path1s $path1s";
        $comment = $comment ? qq{ #comment $comment} : '';

        # ignore undefined or empty mapped paths
        if (!$path1s) {
            action {
                warn => $globals->{tr98map} || !defined($path1s),
                text => "$path ->$comment"
            };
            next;
        }

        # check whether the mapped path exists in the second data model
        #
        # a path beginning with "+" is not checked; it indicates an object
        # to be created in the second data model (with the name copied from
        # the first data model if not specified, i.e. if the path is "+")
        #
        # note:
        # * mismatch in number of indices can indicate a problem
        # * can map to multiple paths (parameters could be in any)
        # * can map to single parameter (collapsed table)
        # * multiple objects can map to a single object (duplication)
        # XXX also support "=" for backwards compatibility
        # XXX should warn on mismatch of number of indices
        my $cpath1s = [];
        my $npath1s = [];
        my $node1s = [];
        my $mult = ($path1s =~ /,/);
        my $anyobj = 0;
        foreach my $path1 (split /,/, $path1s) {
            if ($path1 =~ /^[+=]/) {
                $path1 =~ s/^[+=]//;
                push @$cpath1s, $path1;
            } else {            
                my $node1 = $nodes->[-1]->{$path1};
                if (!$node1) {
                    push @$npath1s, $path1;
                } else {
                    push @$node1s, $node1;
                    $anyobj = 1 if $node1->{type} eq 'object';
                }
            }
        }

        if (!@$node1s) {
            foreach my $path1 (@$npath1s) {
                action {
                    warn => 1,
                    text => "$path -> $path1 (doesn't exist)$comment"
                };
            }
        } else {
            $path1s = join ',', map {$_->{path}} @$node1s;
            action {
                warn => 0,
                text => "$path -> $path1s$comment",
                oper => 'CurrentParents',
                root => $root,
                par  => $node1s,
                rem  => $comment
            };
        }

        # XXX output is confusing if there is a mixture of existing and new
        #     objects (should try to combine the two?)
        my $newobj;
        foreach my $cpath1 (@$cpath1s) {
            action {
                warn => $newobj,
                text => "$path -> $cpath1 (new object)$comment",
                oper => 'NewObject',
                root => $root,
                old  => $object,
                new  => $cpath1,
                rem  => $comment
            };
            $newobj = $cpath1 unless $newobj;
        }

        check_profiles(@$node1s);

        # don't worry about children if the object maps only to parameters
        next if !$anyobj && !$newobj;

        # look for parameters in the second data model
        foreach my $child (grep {$_->{syntax}} @{$object->{nodes}}) {
            next if main::util_is_omitted($child);
            
            my $cpath = $child->{path};
            my $name = $child->{name};
            my $status = $child->{status};
            #main::tmsg "  cpath $cpath name $name status $status";

            # ignore deprecated, obsoleted or deleted parameters
            next if $status =~ /deprecated|obsoleted|deleted/;

            # ignore #entries parameters
            # XXX alternatively could use the "table" attribute
            next if $globals->{tr98map} && grep {
                $_->{numEntriesParameter} &&
                    $_->{numEntriesParameter} eq $name} @{$object->{nodes}};
            
            my ($patts, $name1s, $comment) =
                mapped_parameter_names($root, $path, $path1s,
                                       (join ',', @$cpath1s), $name);
            $comment = $comment ? qq{ #comment $comment} : '';
            #main::tmsg "    patts $patts name1s $name1s comment $comment";

            # ignore undefined or empty mapped parameter names
            if (!$name1s) {
                action {
                    warn => $globals->{tr98map} || !defined($name1s),
                    text => "  $cpath ->$comment"
                };
                next;
            }

            # first look in objects that exist in the second data model
            my $found = [];
            my $newpars = [];
            foreach my $node1 (@$node1s) {
                next if $patts &&
                    !path_matches_patterns($node1->{path}, $patts);

                foreach my $name1 (split /,/, $name1s) {
                    my $node1c = $node1;
                    my $name1c = $name1;

                    # a name beginning "+" indicates a parameter to be created
                    # in the second data model (with - unless disabled - the
                    # name copied from the first data model if not specified,
                    # i.e. if the name is "+")
                    # XXX also support "=" for backwards compatibility
                    if ($name1c =~ /^[+=]/) {
                        $name1c =~ s/^[+=]//;
                        my $newpar = $name1c ? $name1c :
                            !$globals->{nodefaultname} ? $name : '';
                        if ($newpar) {
                            # XXX this is messy; the idea is that, if there are
                            #     multiple mapped paths, need to disambiguate
                            $newpar = $node1c->{path} . $newpar if $mult;

                            # the parameters will be created below
                            #main::tmsg "    newpar $newpar";
                            push @$newpars, $newpar;
                        }
                    }

                    # the mapped parameter name can be of the form "A.B"
                    # XXX could make this more general... but don't need to?
                    # XXX want to allow it to map to an object too
                    # XXX something is wrong here; the results of the grep
                    #     aren't checked, and $node1c isn't used?
                    if ($name1c =~ /\./) {
                        my ($p, $c) = ($name1 =~ /([^\.]*\.)(.*)/);
                        ($node1c) = grep {$_->{name} eq $p} @{$node1->{nodes}};
                        $name1c = $c;
                    }

                    # XXX should warn where not found?
                    my ($node1cc) =
                        grep {$_->{name} eq $name1c} @{$node1c->{nodes}};
                    push @$found, $node1cc if $node1cc;
                }
            }

            # report if mapped parameter was found in an existing object
            # XXX should use a utility when checking for changes, and also
            #     do it more generally
            if (@$found) {
                my $where = join ',', map {$_->{path}} @$found;
                my @types = map {
                    main::syntax_string($_->{type}, $_->{syntax})
                } ($child, @$found);
                my @utypes = @types;
                @utypes = map {s/StatsCounter32/unsignedInt/r} @utypes;
                @utypes = map {s/StatsCounter64/unsignedLong/r} @utypes;
                @utypes = map {s/DisplayString/string/r} @utypes;
                @utypes = uniq sort @utypes;
                my $types = (@utypes > 1) ? ' #types '.join(',', @types) : '';
                my @accesses = map {$_->{access}} ($child, @$found);
                my @uaccesses = uniq sort @accesses;
                my $accesses = (@uaccesses > 1) ?
                    ' #access '.join(',', @accesses) : '';
                my $has_default = grep {
                    defined $_->{default}} ($child, @$found);
                my @defaults = map {$_->{default}} ($child, @$found);
                my @sdefaults = map {
                    !defined $_->{default} ? '<undef>' : $_->{default} eq "" ?
                        '<empty>' : $_->{default}} ($child, @$found);
                my $defaults = $has_default ?
                    ' #default '.join(',', @sdefaults) : '';
                #if ($has_default) {
                #    main::tmsg "  cpath $cpath name $name status $status";
                #    main::tmsg "    defaults ", Dumper(\@defaults);
                #    main::tmsg "    defaults(2)", $defaults;
                #}
                action {
                    warn => 0,
                    text => "  $cpath -> $where$comment$types$accesses" .
                        "$defaults"
                };
                foreach my $f (@$found) {
                    action {
                        oper => 'ExistingParameter',
                        root => $root,
                        old  => $child,
                        new  => $f->{path},
                        acc  => $f->{access},
                        rem  => "$comment$types$accesses$defaults"
                    };
                }

                check_profiles(@$found);
            }

            # otherwise repeat essentially the same logic for objects that are
            # to be created
            else {
                foreach my $cpath1 (@$cpath1s) {
                    next if $patts && !path_matches_patterns($cpath1, $patts);

                    foreach my $name1 (split /,/, $name1s) {
                        my $name1c = $name1;
                        if ($name1c =~ /^[+=]/) {
                            $name1c =~ s/^[+=]//;
                            my $newpar = $name1c ? $name1c :
                                !$globals->{nodefaultname} ? $name : '';
                            if ($newpar) {
                                $newpar = $cpath1 . $newpar if $mult;
                                push @$newpars, $newpar;
                            }
                        }
                    }
                }
            }

            # if no existing parameter was found, and no parameters are yet
            # marked for creation, and if a new object is being created,
            # create a parameter with the same name as the original
            #main::tmsg "    found " . @$found . " newpars " . @$newpars .
            #" newobj $newobj";
            if (!@$found && !@$newpars) {
                if ($newobj && !$globals->{noautocreate}) {
                    push @$newpars, $name;
                } else {
                    # this is just for reporting purposes; it is similar to
                    # the config file entry (minus any comment)
                    my $newpar = ($patts ? '(' . $patts . ')' : '') . $name1s;
                    action {
                        warn => 1,
                        text => "  $cpath -> $newpar (doesn't exist)$comment",
                    };
                }
            }

            # create new parameters
            foreach my $newpar (@$newpars) {
                action {
                    warn => $globals->{tr98map},
                    text => "  $cpath -> $newpar (new parameter)$comment",
                    oper => 'NewParameter',
                    root => $root,
                    old  => $child,
                    new  => $newpar,
                    rem  => $comment
                };
            }
        }
    }

    report_profiles();

    # end
    action {
        oper => 'End',
        root => $root
    };
}

# mapped object paths in second data model
sub mapped_object_paths {
    my ($root, $path) = @_;

    # XXX should check that all mappings are used? that depends...

    my $path1s = lookup_mapping($object_mappings, $root, $path);

    # the mapped object path can be of the form "path#comment"
    my $comment = undef;
    if ($path1s && $path1s =~ /\#/) {
        ($path1s, $comment) = ($path1s =~ /\s*([^\s\#]*)\s*\#\s*(.*)/);
    }

    $path1s = default_mapped_object_paths($root, $path) if !defined $path1s;

    return ($path1s, $comment);
}

# mapped parameter names in second data model
sub mapped_parameter_names {
    my ($root, $path, $path1s, $cpath1s, $name) = @_;

    # lookup name is usually just the parameter name but can be a trailing
    # suffix of the path name; specifically, for A.B.C.P, B.C.P, C.P and P
    # are tried in that order (.{i} strings are omitted)
    # XXX there is some overlap here with the RHS (A|B|...) syntax, but we need
    #     both
    my $suffixes = [];
    my $tpath = $path;
    $tpath =~ s/\.\{i\}//g;
    my @comps = split /\./, $tpath;
    push @$suffixes, qq{$comps[-2].$comps[-1].$name};
    push @$suffixes, qq{$comps[-1].$name};
    push @$suffixes, qq{$name};

    my $name1 = undef;
    foreach my $suffix (@$suffixes) {
        $name1 = lookup_mapping($parameter_mappings, $root, $suffix);
        last if defined $name1;
    }

    # the mapped parameter name can be of the form "(A|B|...)C", in which case
    # it is used only when A, B, ... occurs within any of the first or second
    # data model paths (C)
    # XXX this stops on the first match; faulty logic; should return a list;
    #     ref WANCommonInterfaceConfig
    my (@patts, $patts);
    if ($name1 && $name1 =~ /^\(/) {
        my ($ss, $c) = ($name1 =~ /\(([^\)]*)\)(.*)/);
        my $match = 0;
        foreach my $p (split /,/, qq{$path,$path1s,$cpath1s}) {
            foreach my $s (split /\|/, $ss) {
                if (path_matches_pattern($p, $s)) {
                    push @patts, $s;
                }
            }
        }
        ($patts, $name1) = @patts ? (join(',', @patts), $c) : (undef, undef);
    }

    # the mapped parameter name can be of the form "name#comment"
    my $comment = undef;
    if ($name1 && $name1 =~ /\#/) {
        ($name1, $comment) = ($name1 =~ /\s*([^\s\#]*)\s*\#\s*(.*)/);
    }

    $name1 = default_mapped_parameter_names($root, $path, $path1s, $name)
        if !defined $name1;

    return ($patts, $name1, $comment);
}

# look up mapping, including fallback; supplied hash is two level, with
# primary level given as an argument
sub lookup_mapping {
    my ($mappings, $key, $name) = @_;

    # try supplied key
    my $value = $mappings->{$key}->{$name};
    return $value if defined $value;

    # if not defined, try the other non-empty keys; if defined, ignore the
    # value and return an empty string (indicating map to nothing)
    foreach my $k (keys %$mappings) {
        next if !$k || $k eq $key;
        $value = $mappings->{$k}->{$name};
        return '# Defined in ' . $k if defined $value;
    }

    # if not defined, try the empty (fallback) key; if defined, treat the same
    # as the other non-empty keys
    $value = $mappings->{''}->{$name};
    return '# Defined in fallback' if defined $value;

    # if no fallback, undefined
    return undef;
}

# default mapped object path in second data model
sub default_mapped_object_paths {
    my ($root, $path) = @_;

    my $path1s = $path;

    return $path1s unless $globals->{tr98map};

    if ($path =~ /^InternetGatewayDevice\./) {
        $path1s =~ s/^InternetGateway//;
    } elsif ($path =~ /^Device\./) {
        $path1s =~ s/^/InternetGateway/;
    } else {
        $path1s = '';
    }

    return $path1s;
}

# default mapped parameter names in second data model
sub default_mapped_parameter_names {
    my ($root, $path, $path1s, $name) = @_;

    my $name1 = $name;

    return $name1 unless $globals->{tr98map};

    # paths are candidate object paths in the second data model; determine
    # parent and grandparent object names as candidate strings to remove from
    # the start of the name
    my $prefixes = [];
    foreach my $path (split /,/, qq{$path,$path1s}) {
        $path =~ s/\.\{i\}//g;
        my @comps = split /\./, $path;
        push @$prefixes, $comps[-1], $comps[-2];
    }
   
    # only remove prefix if it's followed by upper-case character (avoids
    # things like removing "PPP" from "PPPoE..."
    foreach my $prefix (@$prefixes) {
        if ($name1 =~ /^\Q$prefix\E[A-Z]/) {
            $name1 =~ s/^\Q$prefix\E//;
            last;
        }
    }
   
    return $name1;
}

# check whether path matches one of the supplied patterns
sub path_matches_patterns
{
    my ($path, $patts) = @_;

    # the patterns are a comma-separated list of individual patterns
    my @patts = split /,/, $patts;

    foreach my $patt (@patts) {
        return 1 if path_matches_pattern($path, $patt);
    }

    # fall through; no match
    return 0;
}

# check whether path matches the supplied pattern
sub path_matches_pattern
{
    my ($path, $patt) = @_;

    # the match is a sub-string match except that "$" is honoured
    my $dollar = $patt =~ /\$$/;
    $patt =~ s/\$$//;

    # XXX I'm not 100% confident that I can use a variable that expands to ''
    #     or '$' here
    return (!$dollar && ($path =~ /\Q$patt\E/)) ||
        ($dollar && ($path =~ /\Q$patt\E$/));
}

# this is called for every object or parameter in the second data model to
# which an object or parameter in the first data model maps; it does two
# things:
# 1. notes that the object or parameter was mapped to
# 2. creates a list of all the profiles that are referenced ("touched") by
#    any of these objects or parameters
my $mapped_items = {};
my $touched_profiles = [];
sub check_profiles {
    my @nodes = @_;

    foreach my $node (@nodes) {
        my $path = $node->{path};

        $mapped_items->{$path}++;

        if (@$profiles) {
            my $profs = $profiles->[-1]->{$path};
            foreach my $prof (@$profs) {
                add_profile($prof);
            }
        }
    }
}

# this is called when the list of touched profiles is complete
sub report_profiles {

    # If profile PPP:2 is included then PPP:1 must be included (etc)
    foreach my $profile (@$touched_profiles) {
        add_base_profile($profile);
    }

    # for each profile, report objects and parameters that are in the profile
    # but no object or parameter in the first data model has mapped to it
    foreach my $profile (@$touched_profiles) {
        foreach my $item (@{$profile->{nodes}}) {
            report_profile_item($profile, $item);
        }
    }
}

# this is called for each profile item
sub report_profile_item {
    my ($profile, $item) = @_;

    my $name = $profile->{path};

    my $path = $item->{path};

    # ignore if already mapped, is an object, or is a #entries parameter
    # XXX it's not obvious, but only #entries parameters have a "table" attr
    my $ignore = $mapped_items->{$path} ||
        (!$globals->{tr98map} && ($path =~ /\.$/ ||
                                  $nodes->[-1]->{$path}->{table}));

    action {
        warn => 2,
        text => "$name -> $path"
    } unless $ignore;

    foreach my $child (@{$item->{nodes}}) {
        report_profile_item($profile, $child);
    }
}

# add the base profile (or the extended profiles) to the touched profiles
sub add_base_profile {
    my ($profile) = @_;

    my $baseprof = $profile->{baseprof};
    my $extendsprofs = $profile->{extendsprofs};

    if ($baseprof) {
        add_profile($baseprof);
        add_base_profile($baseprof);
    }

    foreach my $extendsprof (@$extendsprofs) {
        if ($extendsprof) {
            add_profile($extendsprof);
            add_base_profile($extendsprof);
        }
    }
}

# add a profile to the touched profiles if not already there
sub add_profile {
    my ($profile) = @_;

    push @$touched_profiles, $profile
        unless grep {$_ == $profile} @$touched_profiles;
}

# global data used by the action routine and the routines that it calls
my $datatype_map = {};
my $output_objects = [];
my $current_parents = [];
my $name_count = 0;

# perform action; argument is hash with the following members:
#
# used in text mode:
# * warn: whether it's a warning (or 2 for profile messages)
# * text: text (newline will be added)
#
# used in xml mode:
# * oper: Begin, CurrentParents, NewObject, NewParameter, End
# * root: root name as used in config file, e.g. "Device", "STB", "Storage"
# * par:  (op=CurrentParents) list of existing objects in which new
#         parameter(s) will be created; is overridden by subsequent NewObject
# * old:  (op=NewObject) existing object from which new object definition
#         will be derived
#         (op=NewParameter) existing parameter from which new parameter
#         definition will be derived
# * new:  (op=NewObject) new object's path name
#         (op=NewParameter) new parameter name or path name
#         XXX when there are patterns the above can be more complex than this
sub action {
    my ($opts) = @_;
    my $oper = $opts->{oper};

    # XXX note that $options contains global command-line options, whereas
    #     $opts is a local hash passed as an argument; naming is unfortunate...

    # ----------
    # text mode:

    # report to stdout (if text has been supplied)
    # XXX $warn=2 is a special case for profile messages: use '#' prefix
    if ($options->{mode} eq 'text') {
        my $warn = $opts->{warn};
        my $text = $opts->{text};
        my $pfx = $warn == 0 ? ' ' : $warn == 1 ? '!' : '#'; 
        output 0, "$pfx $text" if defined $text;
    }

    # ---------
    # xml mode:
    # XXX various things are copied from import.pl; there should be a reusable
    #     library for generating various flavours of XML
    # XXX are such things best done in plugins? it gives instant access to the
    #     node tree but complicates things like specifying options, handling
    #     errors, documentation, ...

    # no operation
    elsif (!$oper) {
    }

    # begin generating the XML
    elsif ($oper eq 'Begin') {
        action_begin($opts->{root});
    }

    # note existing objects in which any new parameters will be created
    elsif ($oper eq 'CurrentParents') {
        action_current_parents($opts->{par}, $opts->{rem});
    }

    # create a new object (it might already exist)
    elsif ($oper eq 'NewObject') {
        action_new_object($opts->{root}, $opts->{old}, $opts->{new},
            $opts->{rem});
    }

    # create a new parameter
    elsif ($oper eq 'NewParameter') {
        action_new_parameter($opts->{old}, $opts->{new}, $opts->{rem});
    }

    # modify an existing parameter
    elsif ($oper eq 'ExistingParameter') {
        action_existing_parameter($opts->{old}, $opts->{new}, $opts->{acc},
                                  $opts->{rem});
    }

    # end generating the XML
    elsif ($oper eq 'End') {
        action_end($opts->{root});
    }

    # invalid operation
    else {
        main::emsg "ignored invalid $oper operation";
    }
}

# begin generating the XML
sub action_begin
{
    my ($root) = @_;
}

# note existing objects in which any new parameters will be created
sub action_current_parents
{
    my ($parents, $remark) = @_;

    #main::tmsg "action_current_parents: " .
    #join(',', map {$_->{path}} @$parents) . "$remark";

    # these objects will be output only if child parameters are created
    foreach my $parent (@$parents) {
        $parent->{map_create} = 0;
        push @{$parent->{map_remarks}}, $remark;
        push @$output_objects, $parent
            unless grep {$_->{path} eq $parent->{path}} @$output_objects;
    }

    $current_parents = $parents;
}

# create a new object (it might already exist)
sub action_new_object
{
    my ($root, $node, $path, $remark) = @_;

    #main::tmsg "action_new_object: $path $remark";

    # check whether object already exists and, if not, create it
    # XXX if it exists should check that nothing has changed (it hasn't)
    my ($object) = grep {$_->{path} eq $path} @$output_objects;
    if (!$object) {
        my $numEntriesParameter = $node->{numEntriesParameter};
        my $enableParameter = $node->{enableParameter};
        my $uniqueKeys = $node->{uniqueKeys};

        # check for mapped #entries, enable and unique key parameters
        my $param_list = [];
        push @$param_list, \$numEntriesParameter if $numEntriesParameter;
        push @$param_list, \$enableParameter if $enableParameter;
        foreach my $uniqueKey (@$uniqueKeys) {
            my $keyparams = $uniqueKey->{keyparams};
            for (my $i = 0; $i < @$keyparams; $i++) {
                push @$param_list, \$keyparams->[$i];
            }
        }

        # XXX oh so horrible, e.g. need to parse the result of the lookup
        #     (look only for a leading "+" or "=")
        foreach my $param (@$param_list) {
            my $mapping = lookup_mapping($parameter_mappings, $root, $$param);
            if ($mapping) {
                $mapping =~ s/^[+=]//;
                $$param = $mapping;
            }
        }
        
        # XXX the two special cases below can interact; are they in the correct
        #     order?

        # special case if old object is multi-instance and new object is
        # single-instance; quietly change to single instance; the most likely
        # reason for this is that a table is being mapped to a new single-
        # instance object and a child table
        my $minEntries = $node->{minEntries};
        my $maxEntries = $node->{maxEntries};
        if ($numEntriesParameter && $path !~ /\Q.{i}.\E$/) {
            $minEntries = '1';
            $maxEntries = '1';
            $numEntriesParameter = undef;
            $uniqueKeys = undef;
        }

        # special case if old object is single-instance (has no #entries
        # parameter) and new object is multi-instance: create #entries param
        # XXX should invoke action_current_parents() (or variant?) to ensure
        #     that the #entries parameter parent is known (workaround: specify
        #     it in the config file)
        if (!$numEntriesParameter && $path =~ /\Q.{i}.\E$/) {
            my $tpath = $path;
            $tpath =~ s/\Q.{i}.\E$/NumberOfEntries/;

            my $told = {path => 'fake', name => 'fake', access => 'readOnly',
                        status => $node->{status},
                        majorVersion => $node->{majorVersion},
                        minorVersion => $node->{minorVersion},
                        description => '{{numentries}}',
                        type => 'unsignedInt'};
            action_new_parameter($told, $tpath);

            $minEntries = '0';
            $maxEntries = 'unbounded';
            ($numEntriesParameter) = $tpath =~ /([^\.]*)$/;
        }

        # populate new object node from old (template) node and new path
        # XXX should have a proper way of cloning an object in this way
        # XXX note that report.pl's xml reports don't propagate the id
        # XXX should have a go at merging comments etc into the description
        # XXX descact, changed and history are there so the correct description
        #     can be derived, but this is pretty hairy
        my $access = $node->{access};
        my $enableParameter = $node->{enableParameter};
        my $id = $node->{id};
        my $status = $node->{status};
        my $majorVersion = $node->{majorVersion};
        my $minorVersion = $node->{minorVersion};
        my $noUniqueKeys = $node->{noUniqueKeys};
        my $fixedObject = $node->{fixedObject};
        my $description = $node->{description};
        my $descact = $node->{descact};
        my $changed = $node->{changed};
        my $history = $node->{history};

        $object = {path => $path, access => $access,
                   minEntries => $minEntries, maxEntries => $maxEntries,
                   numEntriesParameter => $numEntriesParameter,
                   enableParameter => $enableParameter, id => $id,
                   status => $status, majorVersion => $majorVersion,
                   minorVersion => $minorVersion,
                   noUniqueKeys => $noUniqueKeys, fixedObject => $fixedObject,
                   description => $description, descact => $descact,
                   uniqueKeys => $uniqueKeys, changed => $changed,
                   history => $history, map_remarks => [$remark],
                   map_create => 1};
        
        push @$output_objects, $object;
    }

    $current_parents = [$object];
}

# create a new parameter
sub action_new_parameter
{
    my ($node, $name, $remark) = @_;

    #main::tmsg "action_new_parameter: $name $remark";

    # find object
    (my $object_name, $name) = get_object_name($node, $name);
    my ($object) = grep {$_->{path} eq $object_name} @$output_objects;
    if (!$object) {
        main::emsg "$object_name not in list of candidate parents for $name";
        return;
    }

    # parameter path
    my $path = qq{$object_name$name};

    # populate new parameter node from old (template) node and new name
    # XXX should have a proper way of cloning a parameter in this way
    # XXX note that report.pl's xml reports don't propagate the id
    # XXX should have a go at merging comments etc into the description
    # XXX descact, changed and history are there so the correct description
    #     can be derived, but this is pretty hairy
    my $access = $node->{access};
    my $id = $node->{id};
    my $status = $node->{status};
    my $activeNotify = $node->{activeNotify};
    my $forcedInform = $node->{forcedInform};
    my $majorVersion = $node->{majorVersion};
    my $minorVersion = $node->{minorVersion};
    my $description = $node->{description};
    my $descact = $node->{descact};
    my $syntax = $node->{syntax};
    my $hidden = $node->{hidden};
    my $command = $node->{command};
    my $type = $node->{type};
    my $values = $node->{values};
    my $units = $node->{units};
    my $default = $node->{default};
    my $deftype = $node->{deftype};
    my $defstat = $node->{defstat};
    my $changed = $node->{changed};
    my $history = $node->{history};

    # keep track of where referenced named data types are defined
    # XXX obviously we'd like an accessible API for such imports
    my $datatype = $syntax->{ref} || $syntax->{base};
    if ($datatype) {
        while (my ($file, $impfile) = each %$main::imports) {
            foreach my $imp (@{$impfile->{imports}}) {
                if ($imp->{element} eq 'dataType' &&
                    $imp->{name} eq $datatype && $imp->{file} eq $file) { 
                    $datatype_map->{$file}->{spec} = $imp->{spec};
                    $datatype_map->{$file}->{datatypes}->{$datatype} = 1;
                }
            }
        }
    }

    my $parameter = {path => $path, name => $name, access => $access,
                     id => $id, status => $status,
                     activeNotify => $activeNotify,
                     forcedInform => $forcedInform,
                     majorVersion => $majorVersion,
                     minorVersion => $minorVersion,
                     description => $description, descact => $descact,
                     syntax => $syntax, hidden => $hidden, command => $command,
                     type => $type, values => $values, units => $units,
                     default => $default, deftype => $deftype,
                     defstat => $defstat, changed => $changed,
                     history => $history, map_remarks => [$remark],
                     map_create => 1};

    push @{$object->{map_parameters}}, $parameter;
}

# modify an existing parameter
sub action_existing_parameter
{
    my ($node, $name, $access, $remark) = @_;

    #main::tmsg "action_existing_parameter: $node->{name} -> $name $remark";

    # find object
    (my $object_name, $name) = get_object_name($node, $name);
    my ($object) = grep {$_->{path} eq $object_name} @$output_objects;
    if (!$object) {
        main::emsg "$object_name not in list of candidate parents for $name";
        return;
    }

    my $path = qq{$object_name$name};
    my $id = $node->{id};

    # XXX this is minimal; currently just the id and remark are propagated
    my $parameter = {
        path => $path, name => $name, access => $access, id => $id,
        map_remarks => [$remark], map_create => 0};

    push @{$object->{map_parameters}}, $parameter;    
}

# determine object name (common code taken from action_new_parameter)
sub get_object_name
{
    my ($node, $name) = @_;

    #main::tmsg "get_object_name: node $node->{path} name $name";

    # XXX name can start with a pattern, which can be followed by a list;
    #     for now, ignore (and note) such cases; IS THIS STILL TRUE?
    main::w0msg "ignoring pattern/list in $name"
        if $name =~ /^\(/ || $name =~ /,/;

    # name might be full path (where there are multiple candidate parents)
    my ($object_name, $tname) = $name =~ /(.*\.)(.*)/;
    $name = $tname if $tname;
    #main::tmsg "  -> $object_name + $name" if $tname;

    # if name was not a full path (so $object_name is undefined), determine
    # which object should be the parent
    # XXX a parameter should be created in each such object, but for
    #     now we just warn when this should happen; IS THIS STILL A PROBLEM?
    if (!$object_name) {
        my $notpaths = [];
        foreach my $parent (@$current_parents) {
            if (!$object_name) {
                $object_name = $parent->{path};
            } else {
                push @$notpaths, $parent->{path};
            }
        }
        if (@$notpaths) {
            my $paths = join ', ', @$notpaths;
            $paths =~ s/(.*), (.*)/\1 or \2/;
            main::w0msg "$name: creating in $object_name and not in " .
                "$paths";
        }
    }

    return ($object_name, $name);
}

# end generating the XML
sub action_end
{
    my ($root) = @_;

    # open root element
    output_root_open 0, $root;

    # output data types
    output_datatypes 1;

    # open model element
    output_model_open 1, $root;

    # output objects and their parameters
    foreach my $object (@$output_objects) {
        my $create = $object->{map_create};
        my $parameters = $object->{map_parameters};

        if ($create || ($parameters && @$parameters)) {
            my $path =
                output_object_open 2, $root, $object, {create => $create};
            foreach my $parameter (@$parameters) {
                output_parameter 3, $root, $path, $parameter,
                    {create => $parameter->{map_create}};
            }
            output_object_close 2, $object;
        }
    }

    # close model element
    output_model_close 1;
    
    # close root element
    output_root_close 0;
}

# XXX we are proliferating various different ways of outputting DM and/or DT
#     XML; report.pl (xml and xml2 reports), import.pl, map.pm; we need a
#     proper way of sharing such code, which is something that i have resisted
#     mostly because of not wanting to complicate the "report.pl" distribution;
#     but perhaps now is the time to look into using CPAN's Par and/or simple
#     file concatenation rules

# XXX any new utilities should be properly object-oriented, with shims as
#     necessary to make things work properly

# XXX currently there is some duplication for attributes and elements that are
#     common to objects and parameters; the object-oriented version should
#     avoid this

# output root element
sub output_root_open
{
    my ($i, $root) = @_;

    # these come from the config file
    my $vendorfile = $globals->{$root}->{vendorfile};
    my $vendorspec = $globals->{$root}->{vendorspec};
    
    # XXX should check that all the above are defined

    # output DM header
    # XXX shouldn't hard-code DM version
    output $i, qq{<?xml version="1.0" encoding="UTF-8"?>};
    output $i, qq{
<dm:document xmlns:dm="urn:broadband-forum-org:cwmp:datamodel-1-5"
             xmlns:dmr="urn:broadband-forum-org:cwmp:datamodel-report-0-1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="urn:broadband-forum-org:cwmp:datamodel-1-5
                 http://www.broadband-forum.org/cwmp/cwmp-datamodel-1-5.xsd
                              urn:broadband-forum-org:cwmp:datamodel-report-0-1
                 http://www.broadband-forum.org/cwmp/cwmp-datamodel-report.xsd"
             file="$vendorfile" spec="$vendorspec">
};

    # output top-level description
    # XXX shouldn't be hard-coded
    output $i+1, qq{
<description>
  XXX vendor extensions
</description>
};
    # XXX hard-code bibref import
    output $i+1, qq{
<import file="tr-069-biblio.xml" spec="urn:broadband-forum-org:tr-069-biblio"/>
};

}

sub output_root_close
{
    my ($i) = @_;

    output 0, qq{</dm:document>};
}

# sort file names alphabetically but with files whose names begin "tr-" coming
# first (because we prefer to import data type definitions from standard BBF
# files)
sub datatype_file_cmp
{
    my $atr = $a =~ /^tr-/;
    my $btr = $b =~ /^tr-/;

    return +1 if !$atr &&  $btr; # xx > tr
    return -1 if  $atr && !$btr; # tr < xx
    return $a cmp $b;
}

# output data types
sub output_datatypes
{
    my ($i) = @_;

    # datatypes that have already been seen
    my $datatypes_seen = {};

    # output data type import elements (the sort order causes standard BBF
    # files to be used first)
    foreach my $file (sort datatype_file_cmp keys %$datatype_map) {
        my $hash = $datatype_map->{$file};
        my $spec = $hash->{spec};
        my $datatypes = $hash->{datatypes};

        # a given data type might (although should not) be defined in
        # multiple files, so check for this
        my @datatypes_left = grep {!$datatypes_seen->{$_}} keys %$datatypes;
        if (@datatypes_left) {

            # remove corrigendum number from file and spec (note that the file
            # name doesn't include the extension)
            my $file = remove_corrigendum($file);
            my $spec = remove_corrigendum($spec);

            output $i, qq{<import file="$file.xml" spec="$spec">};
            foreach my $datatype (@datatypes_left) {
                output $i+1, qq{<dataType name="$datatype"/>};
                $datatypes_seen->{$datatype} = 1;
            }
            output $i, qq{</import>};
        }
    }
}

# output model
sub output_model_open
{
    my ($i, $root) = @_;

    # these come from the last-processed (second) data model
    my $bbffile = $globals->{bbffile};
    my $bbfspec = $globals->{bbfspec};
    my $model = $globals->{model};
    my $version = $globals->{version};

    # these come from the config file
    my $vendorprefix = $globals->{$root}->{vendorprefix};
    my $vendormodel = $globals->{$root}->{vendormodel};
    my $vendorversion = $globals->{$root}->{vendorversion};
    
    # XXX should check that all the above are defined

    # remove corrigendum number from file and spec
    my $file = remove_corrigendum($bbffile);
    my $spec = remove_corrigendum($bbfspec);

    # import existing model
    output 1, qq{
<import file="$file" spec="$spec">
  <model name="$model:$version"/>
</import>
};

    # open new model
    output 1, qq{
<model name="$vendorprefix$vendormodel:$vendorversion" base="$model:$version">
};
}

sub output_model_close
{
    my ($i) = @_;

    output 1, qq{</model>};
}

# output object
sub output_object_open
{
    my ($i, $root, $node, $opts) = @_;

    my $create = $opts->{create};

    my $vendorprefix = $globals->{$root}->{vendorprefix};

    # <object>
    my $basename = $create ? 'name' : 'base';

    # XXX Hmm... I thought that object names were the same as their paths...
    my $path = $node->{path};
    my $name = add_vendor_prefix($vendorprefix, $path, $path, $create);

    my $access = $node->{access};
    $access = 'readOnly' unless $access;

    # XXX this logic should be on node creation, if at all?
    my $minEntries = $node->{minEntries};
    my $maxEntries = $node->{maxEntries};
    unless (defined $minEntries && defined $maxEntries) {
        my $multi = ($path =~ /\.\{i\}\.$/);
        $minEntries = $multi ? qq{0} : qq{1} unless
            defined $minEntries;
        $maxEntries = $multi ? qq{unbounded} : qq{1} unless
            defined $maxEntries;
    }

    my $numEntriesParameter = $node->{numEntriesParameter};
    $numEntriesParameter =
        add_vendor_prefix($vendorprefix, $path,
                          $numEntriesParameter, 1) if $numEntriesParameter;
    $numEntriesParameter = '' unless $create;
    $numEntriesParameter = $numEntriesParameter ?
        qq{ numEntriesParameter="$numEntriesParameter"} : qq{};

    my $enableParameter = $node->{enableParameter};
    $enableParameter =
        add_vendor_prefix($vendorprefix, $path,
                          $enableParameter, 1) if $enableParameter;
    $enableParameter = '' unless $create;
    $enableParameter = $enableParameter ?
        qq{ enableParameter="$enableParameter"} : qq{};

    my $id = $node->{id};
    $id = $id ? qq{ id="$id"} : qq{};

    my $status = $node->{status};
    $status = ($status && $status ne 'current') ?
        qq{ status="$status"} : qq{};

    my $majorVersion = $node->{majorVersion};
    my $minorVersion = $node->{minorVersion};
    my $version = main::version($majorVersion, $minorVersion);
    $version = '' unless $create;
    $version = $version ? qq{ dmr:version="$version"} : qq{};

    my $noUniqueKeys = $node->{noUniqueKeys};
    $noUniqueKeys = '' unless $create;
    $noUniqueKeys = $noUniqueKeys ? qq{ dmr:noUniqueKeys="$noUniqueKeys"} :
        qq{};

    my $fixedObject = $node->{fixedObject};
    $fixedObject = '' unless $create;
    $fixedObject = $fixedObject ? qq{ dmr:fixedObject="$fixedObject"} : qq{};

    output $i, qq{<object $basename="$name" access="$access" }.
        qq{minEntries="$minEntries" maxEntries="$maxEntries"}.
        qq{$numEntriesParameter$enableParameter$id$status$version}.
        qq{$noUniqueKeys$fixedObject>};

    # <description>
    # XXX this might not be perfect...
    my $description;
    my $descact;
    my $remark = get_remark($node);
    if ($create) {
        ($description, $descact) = get_description($node);
    } else {
        $description = '';
        $descact = $remark ? 'append' : $node->{descact};
    }
    $description = xml_escape($description);
    $descact = $descact && $descact ne 'create' ?
        qq{ action="$descact"} : qq{};

    if ($description || $remark) {
        output $i+1, qq{<description$descact>};
        output $i+2, $description if $description;
        output $i+2, $remark if $remark;
        output $i+1, qq{</description>};
    }

    # <uniqueKey>
    my $uniqueKeys = $node->{uniqueKeys};
    $uniqueKeys = [] unless $create;
    foreach my $uniqueKey (@$uniqueKeys) {
        my $functional = $uniqueKey->{functional};
        my $keyparams = $uniqueKey->{keyparams};
        $functional = !$functional ? qq{ functional="false"} : qq{};
        output $i+1, qq{<uniqueKey$functional>};
        foreach my $parameter (@$keyparams) {
            output $i+2, qq{<parameter ref="$parameter"/>};
        }
        output $i+1, qq{</uniqueKey>};
    }

    return $name;
}

sub output_object_close
{
    my ($i, $node, $opts) = @_;

    output $i, qq{</object>};
}

# output parameter
sub output_parameter
{
    my ($i, $root, $parent_path, $node, $opts) = @_;

    my $create = $opts->{create};

    my $path = $node->{path};
    my $name = $node->{name};
    $name = add_vendor_prefix($globals->{$root}->{vendorprefix},
                              $parent_path, $name, $create);
    
    # <parameter>
    my $basename = $create ? 'name' : 'base';
    my $access = $node->{access};

    # XXX check for "?" names
    # XXX should have done this during an earlier phase
    if ($name eq '?') {
        $name_count++;
        $name = "Name$name_count";
        main::w0msg "$path: anonymous parameter named $name";
    }

    # check for and remove any leading or trailing white space in name
    # XXX should have done this during an earlier phase
    my $oname = $name;
    $name =~ s/^\s*//;
    $name =~ s/\s*$//;
    main::w0msg "$path: removed leading/trailing white space from \"$oname\""
        if $name ne $oname;
    
    my $id = $node->{id};
    $id = $id ? qq{ id="$id"} : qq{};

    my $status = $node->{status};
    $status = ($status && $status ne 'current') ?
        qq{ status="$status"} : qq{};

    my $activeNotify = $node->{activeNotify};
    $activeNotify = (defined $activeNotify && $activeNotify ne 'normal') ?
        qq{ activeNotify="$activeNotify"} : qq{};

    my $forcedInform = $node->{forcedInform};
    $forcedInform = $forcedInform ? qq{ forcedInform="true"} : qq{};

    my $majorVersion = $node->{majorVersion};
    my $minorVersion = $node->{minorVersion};
    my $version = main::version($majorVersion, $minorVersion);
    $version = $version ? qq{ dmr:version="$version"} : qq{};

    # XXX for now, omit the version (this is a new parameter) pending further
    #     consideration of how to handle version numbers for mapped parameters
    $version = '';

    output $i, qq{<parameter $basename="$name" access="$access"}.
        qq{$id$status$activeNotify$forcedInform$version>};

    # <description>
    # XXX this might not be perfect...
    my $description;
    my $descact;
    my $remark = get_remark($node);
    if ($create) {
        ($description, $descact) = get_description($node);
    } else {
        $description = '';
        $descact = $remark ? 'append' : $node->{descact};
    }
    $description = xml_escape($description);
    $descact = $descact && $descact ne 'create' ?
        qq{ action="$descact"} : qq{};

    if ($description || $remark) {
        output $i+1, qq{<description$descact>};
        output $i+2, $description if $description;
        output $i+2, $remark if $remark;
        output $i+1, qq{</description>};
    }

    # XXX for now don't do anything further for modified parameters
    if ($create) {
        # <syntax>
        my $syntax = $node->{syntax};
        my $hidden = $syntax->{hidden};
        my $command = $syntax->{command};
        
        $hidden = $hidden ? qq{ hidden="true"} : qq{};
        $command = $command ? qq{ command="true"} : qq{};
        
        output $i+1, qq{<syntax$hidden$command>};
        
        # <list>
        my $list = $syntax->{list};
        if ($list) {
            # XXX not supporting multiple list sizes or ranges
            my $minListLength = $syntax->{listSizes}->[0]->{minLength};
            my $maxListLength = $syntax->{listSizes}->[0]->{maxLength};
            my $minListItems = $syntax->{listRanges}->[0]->{minInclusive};
            my $maxListItems = $syntax->{listRanges}->[0]->{maxInclusive};
            
            $minListLength = defined $minListLength && $minListLength ne '' ?
                qq{ minLength="$minListLength"} : qq{};
            $maxListLength = defined $maxListLength && $maxListLength ne '' ?
                qq{ maxLength="$maxListLength"} : qq{};
            $minListItems = defined $minListItems && $minListItems ne '' ?
                qq{ minItems="$minListItems"} : qq{};
            $maxListItems = defined $maxListItems && $maxListItems ne '' ?
                qq{ maxItems="$maxListItems"} : qq{};
            
            my $ended = ($minListLength || $maxListLength ||
                         $minListItems || $maxListItems) ? '' : '/';
            output $i+2, qq{<list$minListItems$maxListItems$ended>};
            output $i+3, qq{<size$minListLength$maxListLength/>} unless $ended;
            output $i+2, qq{</list>} unless $ended;
        }

        # <$type>
        my $type = $node->{type};
        my $ref = $syntax->{ref};
        my $base = $syntax->{base};
        
        $type = 'dataType' if $ref; # XXX a bit of a kludge...
        $ref = $ref ? qq{ ref="$ref"} : qq{};
        $base = $base ? qq{ base="$base"} : qq{};
        
        my $sizes = $syntax->{sizes};
        my $ranges = $syntax->{ranges};
        my $reference = $syntax->{reference};
        my $values = $node->{values};
        my $units = $node->{units};
        my $ended = (($sizes && @$sizes) || ($ranges && @$ranges) ||
                     $reference || ($values && %$values) || $units) ? '' : '/';
        
        output $i+2, qq{<$type$ref$base$ended>};
        
        # <size>
        foreach my $size (@{$syntax->{sizes}}) {
            my $minLength = $size->{minLength};
            my $maxLength = $size->{maxLength};
            
            $minLength = defined $minLength && $minLength ne '' ?
                qq{ minLength="$minLength"} : qq{};
            $maxLength = defined $maxLength && $maxLength ne '' ?
                qq{ maxLength="$maxLength"} : qq{};
            
            output $i+3, qq{<size$minLength$maxLength/>} if
                $minLength || $maxLength;
        }
        
        # <range>
        foreach my $range (@{$syntax->{ranges}}) {
            my $minInclusive = $range->{minInclusive};
            my $maxInclusive = $range->{maxInclusive};
            my $step = $range->{step};
            
            $minInclusive = defined $minInclusive && $minInclusive ne '' ?
                qq{ minInclusive="$minInclusive"} : qq{};
            $maxInclusive = defined $maxInclusive && $maxInclusive ne '' ?
                qq{ maxInclusive="$maxInclusive"} : qq{};
            $step = defined $step && $step ne '' ? qq{ step="$step"} : qq{};
            
            output $i+3, qq{<range$minInclusive$maxInclusive$step/>} if
                $minInclusive || $maxInclusive || $step;
        }
        
        # <pathRef>, <instanceRef>, <enumerationRef>
        if ($reference) {
            my $refType = $syntax->{refType};
            my $targetParent = $syntax->{targetParent};
            my $targetParentScope = $syntax->{targetParentScope};
            my $targetType = $syntax->{targetType};
            my $targetDataType = $syntax->{targetDataType};
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
            
            output $i+3, qq{<$reference$refType$targetParam$targetParent}.
                qq{$targetParamScope$targetParentScope$targetType$targetDataType}.
                qq{$nullValue/>};
        }
        
        # <enumeration>, <pattern>
        foreach my $value (sort {$values->{$a}->{i} <=>
                                     $values->{$b}->{i}} keys %$values) {
            my $evalue = xml_escape($value);
            my $cvalue = $values->{$value};
            
            my $facet = $cvalue->{facet};
            my $access = $cvalue->{access};
            my $status = $cvalue->{status};
            my $optional = main::boolean($cvalue->{optional});
            
            my $description = get_description_value($node, $value);
            $description = xml_escape($description);
            
            $optional = $optional ? qq{ optional="true"} : qq{};
            $access = $access ne 'readWrite' ? qq{ access="$access"} : qq{};
            $status = $status ne 'current' ? qq{ status="$status"} : qq{};
            my $ended = $description ? '' : '/';
            
            output $i+3, qq{<$facet value="$evalue"$access$status$optional$ended>};
            output $i+4, qq{<description>$description</description>} if
                $description;
            output $i+3, qq{</$facet>} unless $ended;
        }
        
        # <units>
        if ($units) {
            output $i+3, qq{<units value="$units"/>};
        }
        
        # </$type>
        output $i+2, qq{</$type>} unless $ended;
        
        # <default>
        my $default = $node->{default};
        if (defined $default) {
            my $deftype = $node->{deftype};
            my $defstat = $node->{defstat};
            
            $defstat = $defstat ne 'current' ? qq{ status="$defstat"} : qq{};
            
            output $i+2, qq{<default type="$deftype" value="$default"$defstat/>};
        }
        
        # </syntax>
        output $i+1, qq{</syntax>};
    }
    
    # </parameter>
    output $i, qq{</parameter>};
}

# add vendor prefix to object or parameter name (if necessary)
# XXX also in theory could apply to data types, components, profiles, values?
sub add_vendor_prefix
{
    my ($vendorprefix, $path, $name, $create) = @_;

    # only ever add a prefix if creating, and there's anything to add
    return $name unless $create and $vendorprefix;

    # don't add prefix if it's already present in the path
    # XXX this isn't a perfect test but it should be good enough
    return $name if $path =~ /\Q$vendorprefix\E/;

    # add prefix before final component of name
    # XXX could probably do this with a single regex but this is clearer (!)
    if ($name !~ /\./) {
        $name = $vendorprefix . $name;
    } else {
        $name =~ s/^(.*?)\.([^\.]+)(\.\{i\})?\.$/$1.$vendorprefix$2$3./;
    }

    return $name;
}


# similar to (and invokes) report.pl's get_description, but does a bit more
sub get_description
{
    my ($node) = @_;

    my $changed = $node->{changed};
    my $history = $node->{history};
    my $description = $node->{description};
    my $descact = $node->{descact};

    my $dchanged = main::util_node_is_modified($node) &&
        $changed->{description};

    ($description, $descact) = main::get_description($description, $descact,
                                                     $dchanged, $history, 1);

    return ($description, $descact);
}

# as above but for enumeration values
# XXX similar logic but changed comes from elsewhere; not worth generalising
sub get_description_value
{
    my ($node, $value) = @_;

    my $changed = $node->{changed};

    my $cvalue = $node->{values}->{$value};
    my $history = $cvalue->{history};
    my $description = $cvalue->{description};
    my $descact = $cvalue->{descact};

    my $dchanged = main::util_node_is_modified($node) &&
        $changed->{values}->{$value}->{description};

    ($description, $descact) = main::get_description($description, $descact,
                                                     $dchanged, $history, 1);

    return $description;
}

sub get_remark
{
    my ($node) = @_;

    my $text = qq{};
    foreach my $remark (@{$node->{map_remarks}}) {
        $remark = xml_escape($remark);
        $remark =~ s/^\s*//;
        $remark =~ s/\s*$//;
        if ($remark) {
            $text .= qq{\n} if $text;
            my $term = ($remark =~ /[.!?]$/ ? '' : '.');
            $text .= qq{{{issue|$remark$term}}};
        }
    }

    return $text;
} 
   
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

# remove the corrigendum number (and its preceding hyphen) from a file name
# (possibly including file extension) or a spec
sub remove_corrigendum
{
    my ($text) = @_;

    #main::tmsg "remove_corrigendum from $text";

    # don't try to remove corrigendum number on non-BBF specs
    # in tr-nnn-i-a-c-label.ext,
    # $1=-nnn, $2=-i, $3=-a, $4=-c, $5=-label, $6=.ext
    $text =~ s/(-\d+)(-\d+)(-\d+)(-\d+)(-[^-\d]*)?(\.\w+)?$/$1$2$3$5$6/
        unless $text =~ /^urn:/ && $text !~ /^urn:broadband-forum-org/;

    #main::tmsg " --> $text";
    
    return $text;
}

# output multi-line string to stdout, handling indentation
# or if evaluated in scalar context, return a string instead (with newlines)
# or if evaluated in list context, return a list of lines (no newlines)
sub output
{
    my ($indent, $lines) = @_;

    # ignore initial and final newlines (cosmetic)
    $lines =~ s/^\n?//;
    $lines =~ s/\n?$//;

    # collect output lines in a list (no newlines)
    my @lines = ();
    foreach my $line (split /\n/, $lines) {
        push @lines, '  ' x $indent . $line;
    }

    # if the caller wants no value, output to stdout with newlines
    if (!defined wantarray) {
        foreach my $line (@lines) {
            print $line, "\n";
        }
    }

    # if the caller wants a scalar, join with newlines, including trailing one
    elsif (!wantarray) {
        my $text = join "\n", @lines;
        $text .= "\n" if $text;
        return $text;
    }

    # if the caller wants a list, return the list
    else {
        return @lines;
    }
}

# end of plugin
1;
