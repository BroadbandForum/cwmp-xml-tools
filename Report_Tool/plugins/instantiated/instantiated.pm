# BBF report tool plugin to check instantiated data models
#
# supply a data model and (via --configfile) a JSON / YAML dump of what's
# actually instantiated; for example:
# TBD
#
# the plugin compares the information from the JSON dump with the information
# from the data model definition and notes any incompatibilities or anything
# else that is surprising

# JSON config file format is influenced by the PH5 "tr069" library but is
#      actually pretty generic, and similar to the YAML config file format

# XXX should define canonical desired "instantiated data model" structure and
#     importers to import and convert to it

# XXX should define standard interchange format for instantiated data models?
#     should include the full results from GPN, GPV and GPA (like the PH5 one)

# XXX the above two are to some extent rendered irrelevant by the supported
#     YAML format?

# XXX should make the error report more intelligent, so can collapse multiple
#     similar errors etc; possibly generate HTML or MD or similar?

# XXX should be able to include some errors in the tree report (so see them in
#     context)

# XXX annotate error messages with a reference to where the rule is defined

# XXX should check for read-only Alias parameters

# XXX can a bridge have multiple management ports? not clear...

# XXX the tool doesn't detect missing unique key parameters, e.g. omitted
#     Process.{i}.PID; should it? sometimes? if the key has only a single
#     parameter; only for functional keys?

# XXX should check for inappropriate interface stack n:1 references; this is
#     valid only (a) if lower layer supports a "channel" concept, e.g.
#     DSL.Line or WiFi.Radio, or (b) if <=1 higher layer is enabled

# XXX detect attempt to use a zero or negative instance number

# XXX support Alias-Based Addressing

# XXX base #entries checks on the node (so can check if there are none when
#     there should be, rather than the item (so never check if there are none);
#     this same philosophical point might apply more generally

# XXX deal intelligently with missing values; treat similarly to missing
#     objects and parameters

package instantiated;

use strict;

# XXX uncomment to enable traceback on warnings and errors
#use Carp::Always;

use Data::Compare;
use Data::Dumper;
use Data::Validate::IP qw{is_ipv4 is_ipv6};
use File::Basename;
use File::Spec;
use JSON::Parse qw{json_file_to_perl};
use YAML qw{LoadFile};

# hash keyed by actual path names of instantiated objects and parameters;
# has the following members (only value and writable are used):
# * value: string (not native type)
# * writable: boolean
# * attributes:
# ** accessList: array of strings
# ** notification: unsigned int
# XXX it's more complicated than this, e.g. it can indicate errors encountered
#     while trying to collect the data
# XXX the YAML format is more permissive and is converted to the above
my $items = {};

# map from DM Instance path (with {i}) to array of corresponding instantiated
# paths
my $ipath_map = {};

# DM Instance paths to ignore when considering unvisited nodes (this is
# necessary because table nodes don't exist in the DM tree)
my $ipath_ignore = {};

########################################################################
# init: read and parse config file
sub instantiated_init {
    # find config file
    my $configfile = $main::configfile;
    my $suffix = undef; 
    if ($configfile) {
        (my $name, my $path, $suffix) =
            fileparse($configfile, '\.json$', '\.yaml$');
        my ($dir, $file) = main::find_file($configfile, "");
        $configfile = File::Spec->catfile($dir, $file) if $dir;
    }

    # parse config file
    if ($suffix eq '.json') {
        $items = json_file_to_perl($configfile);
    } else {
        $items = LoadFile($configfile);
    }

    # XXX should detect common errors like omitting periods at the end of
    #     names; use heuristic that anything with non-lower-case children is
    #     intended to be an object

    # the config file might contain nested items (as a syntactic convenience),
    # so flatten them
    flatten_items($configfile);

    # the config file might omit the root item or some intermediate object
    # object nodes, so fill in such gaps
    add_missing_items($configfile);

    # convert to a tree, adding path, name and children attributes
    my $root = create_tree();

    # if --option dump is specified, dump and exit
    my $dump = $main::options->{dump};
    if (defined $dump) {
        if ($dump eq 'tree') {
            dump_tree($root, 0);
        } elsif ($dump eq 'ifstack') {
            dump_ifstack();
        } else {
            main::emsg "invalid dump type: $dump (supported: tree, ifstack)";
        }
        exit;
    }

    # otherwise populate the ipath map
    populate_ipath_map();
}

sub flatten_items {
    my ($configfile) = @_;
    
    # note: this is repeated until there are no changes, to allow multiple
    #       levels of indentation
    # XXX there must be a better way to do this?
    my $any = 1;
    while ($any) {
        $any = 0;

        # first pass: keys starting with non-lower-case letters are moved to
        # their parents
        # XXX this assumes that the parent item doesn't exist; if it does it
        #     will be overwritten
        foreach my $path (keys %$items) {
            my $item = $items->{$path};
            my @names = grep { $_ !~ /^[a-z]/ } keys %$item;
            foreach my $name (@names) {
                my $ppath = qq{$path$name};
                main::w0msg "$configfile: $ppath already exists; will be " .
                    "overwritten" if exists $items->{$ppath};
                $items->{$ppath} = $item->{$name};
                delete $item->{$name};
                $any = 1;
            }
        }
    
        # second pass: items that are not references are converted to
        # {writable => 0, value => $item} hashes
        foreach my $path (keys %$items) {
            my $item = $items->{$path};
            $items->{$path} = {writable => 0, value => $item} unless ref $item;
        }
    }
}

sub add_missing_items {
    my ($configfile) = @_;
    
    foreach my $path (keys %$items) {
        my $ppath = util_ppath($path);
        $items->{$ppath} = {} unless defined $items->{$ppath};
    }
}

sub create_tree {
    my $root = undef;

    foreach my $path (keys %$items) {
        my $item = $items->{$path};

        $item->{path} = $path;

        # name is the last component of the path
        my $name = util_name($path);
        $item->{name} = $name;

        # ppath is the parent path (counting A.n as two levels)
        my $ppath = util_ppath($path);
        if (!$ppath) {
            $root = $item;
        } else {
            push @{$items->{$ppath}->{children}}, $item;
        }
    }

    return $root;
}

sub dump_tree {
    my ($item, $indent) = @_;

    my $i = '  ' x $indent;
    my $name = $item->{path} =~ /\.$/ ? $item->{path} : $item->{name};
    my $access = $item->{writable} ? 'W' : 'R';
    my $value = $item->{value};

    util_msg("_info", "tree", "$i$name = $value ($access)");

    my $children = $item->{children};
    if ($children && @$children) {
        foreach my $child (sort util_item_cmp @$children) {
            dump_tree($child, $indent+1);
        }
    }
}

# XXX this is very basic; could add rank information and maybe more colours?
sub dump_ifstack {
    print qq{digraph ifstack \{\n};
    print qq{  nodesep=0.35 node [shape=box style=filled fillcolor=tan]\n};

    foreach my $path (grep { $_ =~ /^Device\.InterfaceStack\.\d+\.$/ }
                      sort util_path_cmp keys %$items) {
        my $hlItem = $items->{$path.'HigherLayer'};
        my $llItem = $items->{$path.'LowerLayer'};

        my $hlValue = $hlItem->{value};
        my $llValue = $llItem->{value};

        $hlValue .= '.' if $hlValue && $hlValue !~ /\.$/;
        $llValue .= '.' if $llValue && $llValue !~ /\.$/;

        if ($hlValue && $llValue) {
            my $hlNameItem = $items->{$hlValue.'Name'};
            my $llNameItem = $items->{$llValue.'Name'};

            my $hlName = $hlNameItem->{value};
            my $llName = $llNameItem->{value};

            print qq{  "$hlValue\\n($hlName)" -> "$llValue\\n($llName)"\n};
        }
    }

    print qq{\}\n};
}

sub populate_ipath_map {
    # each path is of a real instantiated object or parameter
    foreach my $path (keys %$items) {
        
        # convert to an "ipath" in which instance numbers are "{i}", as in
        # DM Instances
        my $ipath = util_ipath($path);

        # add to ipath map
        push @{$ipath_map->{$ipath}}, $path;
    }
}

########################################################################
# node:
# note: all instantiated items for a given ipath are checked before the
#       next ipath, which can result in error messages being apparently
#       out of order, e.g. {A.1, A.2, A.1.B} for ipaths {A.{i}, A.{i}.B}
sub instantiated_node {
    my ($node) = @_;

    # consider only objects and parameters
    my $object = ($node->{type} eq 'object');
    my $parameter = (defined $node->{syntax});
    if ($object || $parameter) {

        # this is an ipath, i.e. contains "{i}", as used in DM Instances
        # XXX amazingly some of the paths in published DM Instances contain
        #     spaces
        my $ipath = $node->{path};
        $ipath =~ s/^\s*//;
        $ipath =~ s/\s*$//;

        # as a special case, if this is a table, add the table name to the
        # list of ignored ipaths
        # note: this is necessary because table names are not in the BBF
        #       Report Tool node tree
        $ipath_ignore->{util_ppath($ipath)} = 1 if util_is_table($ipath);

        # check each instantiated item
        my $paths = $ipath_map->{$ipath};
        if ($paths && @$paths) {
            my @sorted_paths = sort util_path_cmp @$paths;
            foreach my $path (@sorted_paths) {
                my $item = $items->{$path};

                # calculate the number of instances and the corresponding
                # zero-based entry index
                my $ppath = util_ppath($path);
                my @entries = grep { /$ppath\d+\.$/ } @sorted_paths;
                $item->{numEntries} = scalar @entries;
                ($item->{entry}) = grep { $entries[$_] eq $path } 0..$#entries;

                # perform checks
                general_checks($node, $item);
                object_checks($node, $item) if $object;
                parameter_checks($node, $item) if $parameter;
                
                # note that the item was visited
                $item->{visited} = 1;
            }
        }
    }
}

# checks that apply to all items
sub general_checks {
    my ($node, $item) = @_;

    # node attributes
    my $ipath = $node->{path};
    my $access = $node->{access};
    my $type = $node->{type};

    # item attributes
    my $path = $item->{path};
    my $writable = $item->{writable};
    my $entry = $item->{entry};

    # the tricky bit: if the node is a table, the item is an instance so also
    # check the parent item
    # note: this check is performed only for the first entry in each table
    my $ppath = util_ppath($path);
    my $pwritable = $entry == 0 && util_is_table($ipath) ?
        $items->{$ppath}->{writable} : undef;
    $writable = $writable || $pwritable;

    # check access
    my $objpar = ($type eq 'object') ? 'object' : 'parameter';
    util_msg("error", "writable-invalid", "$path: read-only $objpar is " .
             "writable")
        if $access eq 'readOnly' && $writable;
}

# this keeps track of various pieces of TR-181 (i2) specific state
my $tr181 = {};

# checks that apply to objects
sub object_checks {
    my ($node, $item) = @_;

    # node attributes
    my $ipath = $node->{path};

    # item attributes
    my $path = $item->{path};
    my $numEntries = $item->{numEntries};
    my $entry = $item->{entry};

    # object checks are only for tables, i.e. the node is a table and the
    # item is a table entry (object instance)
    return unless util_is_table($ipath);

    # check that table with numEntriesParameter has such a parameter, that
    # it's read-only, that it's within range and that it matches the table
    # note: this check is performed only for the first entry in each table
    my $numEntriesParameter = $node->{numEntriesParameter};
    if ($numEntriesParameter && $entry == 0) {
        my $ppath = util_ppath(util_ppath($path));
        my $numEntriesPath = qq{$ppath$numEntriesParameter};
        my $numEntriesItem = $items->{$numEntriesPath};

        # check that it exists
        util_msg("error", "numentries-undefined", "$path: " .
                 "$numEntriesParameter parameter is undefined")
            if !defined $numEntriesItem;

        # check that it's read-only
        # XXX suppress this message because it should be caught by generic
        #     writable checks
        #util_msg("error", "numentries-writable", "$path: " .
        #         "$numEntriesParameter parameter is writable")
        #    if defined $numEntriesItem && $numEntriesItem->{writable};

        # check that it's within range
        my $minEntries = $node->{minEntries};
        my $maxEntries = $node->{maxEntries};
        my $value = $numEntriesItem ? $numEntriesItem->{value} : 0;
        util_msg("error", "numentries-outofrange", "$path: " .
                 "$numEntriesParameter ($value) is outside the valid range " .
                 "[$minEntries:$maxEntries]")
            if defined $numEntriesItem &&
            ($value < $minEntries ||
             ($maxEntries ne 'unbounded' && $value > $maxEntries));

        # check that it matches the table
        util_msg("error", "numentries-mismatch", "$path: " .
                 "$numEntriesParameter ($value) doesn't match table " .
                 "($numEntries)")
            if defined $numEntriesItem && $value != $numEntries;
    }

    # check that table with enableParameter has such a parameter and that it's
    # writable
    # note: we use the current value of the enableParameter below
    my $enableParameter = $node->{enableParameter};
    my $enableValue = undef;
    if ($enableParameter) {
        my $enablePath = qq{$path$enableParameter};
        my $enableItem = $items->{$enablePath};

        # check that it exists
        util_msg("warning", "enable-undefined", "$path: $enableParameter " .
                 "parameter is undefined")
            if !defined $enableItem;

        # check that it's writable
        util_msg("warning", "enable-readonly", "$path: $enableParameter " .
                 "parameter is read-only")
            if defined $enableItem && !$enableItem->{writable};

        # if it exists, note its value
        $enableValue = util_boolean($enableItem->{value}) if $enableItem;
    }

    # check that unique key constraints are met
    my $table = util_ppath($path);
    my $uniqueKeys = $node->{uniqueKeys};
    foreach my $uniqueKey (@$uniqueKeys) {
        my $functional = $uniqueKey->{functional};
        my $keyparams = $uniqueKey->{keyparams};

        # ignore if the key is functional, there is an enable parameter and
        # it's false
        next if $functional && defined($enableValue) && !$enableValue;

        # get the values of the key parameters
        # note: if key doesn't exist, assume an empty value
        # XXX note that we ignore the possibility of leading/trailing
        #     whitespace, canonical representations, list-valued parameters
        #     etc here (key parameters can't be list-valued)
        my $any = 0;
        my $keyvalues = [];
        foreach my $keyparam (@$keyparams) {
            my $keyPath = qq{$path$keyparam};
            my $keyItem = $items->{$keyPath};
            my $keyvalue = $keyItem ? $keyItem->{value} : '';
            push @$keyvalues, $keyvalue;
            $any = 1 if $keyItem;
        }

        # ignore the key if none of its parameters exist
        next unless $any;

        # use the concatenation of the key parameters as a label for this key
        my $label = join ',', @$keyparams;

        # similarly use the concatenation of the key values to represent the
        # value
        # XXX strictly should use something that can't occur in the value as
        #     the separator, or should use an array, but "it'll never happen"
        my $value = join ',', @$keyvalues;
        
        # use a state variable to keep track of key values already seen
        CORE::state $keyvalues_store;
        util_msg("error", "uniquekey-duplicate", "$path: duplicate value " .
                 "($value) for unique key ($label)")
            if grep { $_ eq $value } @{$keyvalues_store->{$table}->{$label}};
        push @{$keyvalues_store->{$table}->{$label}}, $value;
    }
    
    # could check that all entries of a table have the same structure
    # XXX the trouble is that they often won't, so this is of limited use

    # interface stack checks
    # note: we collect Device.InterfaceStack into $tr181->{ifstack}->{table}
    #       for later analysis
    if ($ipath eq 'Device.InterfaceStack.{i}.') {
        my $hlPath = qq{${path}HigherLayer};
        my $hlItem = $items->{$hlPath};
        my $hlValue = $hlItem->{value};
        my $hlTemp = $hlValue ? $hlValue :
            defined($hlValue) ? '<Empty>' : 'undefined';

        my $llPath = qq{${path}LowerLayer};
        my $llItem = $items->{$llPath};
        my $llValue = $llItem->{value};
        my $llTemp = $llValue ? $llValue :
            defined($llValue) ? '<Empty>' : 'undefined';

        $hlValue .= '.' if $hlValue && $hlValue !~ /\.$/;
        $llValue .= '.' if $llValue && $llValue !~ /\.$/;
        
        $tr181->{ifstack}->{table}->{$hlValue}->{$llValue}++
            if $hlValue && $llValue;

        # note: no need to report if HigherLayer or LowerLayer don't exist,
        #       because generic pathRef checks will take care of this

        # check that HigherLayer is an interface object
        # XXX there is some duplicate logic, both here and with LowerLayers
        util_msg("error", "ifstack-higherlayer-invalid", "$path: " .
                 "HigherLayer parameter is $hlTemp, which is not permitted")
            unless $hlValue;
        my $hlItem = $hlValue ? $items->{$hlValue} : undef;
        if (defined $hlItem) {
            my $hlNode = util_get_node($node, $hlValue);
            my $hlIsInterface = node_is_interface($hlNode, $hlItem);
            util_msg("error", "ifstack-higherlayer-notinterface", "$path: " .
                 "HigherLayer $hlValue is not an interface object")
                if !$hlIsInterface;
        }

        # check that LowerLayer is an interface object
        util_msg("error", "ifstack-lowerlayer-invalid", "$path: " .
                 "LowerLayer parameter is $llTemp, which is not permitted")
            unless $llValue;
        my $llItem = $llValue ? $items->{$llValue} : undef;
        if (defined $llItem) {
            my $llNode = util_get_node($node, $llValue);
            my $llIsInterface = node_is_interface($llNode, $llItem);
            util_msg("error", "ifstack-lowerlayer-notinterface", "$path: " .
                 "LowerLayer $llValue is not an interface object")
                if !$llIsInterface;
        }
    }
    
    # interface checks
    # note: we only check whether it's an interface for the first entry; this
    #       is partly an optimisation and partly to suppress unnecessary
    #       messages
    CORE::state $is_interface;
    $is_interface = node_is_interface($node, $item) if $entry == 0;
    if ($is_interface) {
        
        # check that interface object Enable/Status parameters are
        # consistent and that Status is consistent with other interfaces
        # in the interface stack

        # get Status
        # XXX should use a utility for this and similar cases
        my $statusPath = qq{${path}Status};
        my $statusItem = $items->{$statusPath};
        my $statusValue = $statusItem ? $statusItem->{value} : undef;
        util_msg("error", "interface-status-undefined", "$path: Status " .
                 "parameter is undefined") if !defined $statusValue;

        # Enable / Status consistency
        # XXX there are probably more meaningful combinations that could
        #     be checked
        util_msg("warning", "interface-status-inconsistent", "$path: Status " .
                 "($statusValue) is inconsistent with Enable ($enableValue)")
            if defined($enableValue) && defined($statusValue) &&
            ((!$enableValue && $statusValue eq 'Up') ||
             ($enableValue && $statusValue eq 'Down'));

        # LowerLayers checks
        my $lowerLayersPath = qq{${path}LowerLayers};
        my $lowerLayersItem = $items->{$lowerLayersPath};
        my $lowerLayersValue = $lowerLayersItem ? $lowerLayersItem->{value} :
            undef;
        util_msg("error", "interface-lowerlayers-undefined", "$path: " .
                 "LowerLayers parameter is undefined")
            if !defined $lowerLayersValue;
        $lowerLayersValue = '' unless $lowerLayersValue;
        
        # check for empty- or non-empty LowerLayers on unlikely objects
        # note: Ethernet and MoCA interfaces can be Upstream or Downstream
        # XXX I've obviously missed something about how the qr// operator is
        #     supposed to work; when I used it the patterns below didn't work
        # XXX the Bridge.Port pattern assumes use of Instance Number Instance
        #     Identifiers
        my $lowerLayerInterfacesAlwaysUpstream =
            q{DSL\.Line|(Optical|Cable|Cellular)\.Interface};
        my $lowerLayerInterfacesUsuallyDownstream =
            q{(USB|HPNA|Ghn|HomePlug|UPA)\.Interface|WiFi\.Radio};
        my $lowerLayerInterfacesUpstreamOrDownstream =
            q{(Ethernet|MoCA)\.Interface};
        my $lowerLayerInterfaces =
            qq{$lowerLayerInterfacesAlwaysUpstream|} .
            qq{$lowerLayerInterfacesUsuallyDownstream|} .
            qq{$lowerLayerInterfacesUpstreamOrDownstream};
        my $higherLayerInterfaces =
            q{DSL\.(Channel|BondingGroup)|(ATM|PTM|Ethernet)\.Link|} .
            q{Ethernet\.VLANTermination|WiFi\.SSID|Bridge\.\{i\}\.Port|} .
            q{(PPP|IP)\.Interface};
        my $allInterfaces =
            qq{$lowerLayerInterfaces|$higherLayerInterfaces};
        # XXX suppress this message because it should be caught by the
        #     lowerlayer_is_valid() check below
        #util_msg("warning", "interface-lowerlayers-nonempty", "$path: " .
        #         "LowerLayers is non-<Empty> for layer 1 interface; " .
        #         "probably incorrect?")
        #    if $lowerLayersValue && $ipath =~ /\.($lowerLayerInterfaces)\./;
        util_msg("warning", "interface-lowerlayers-empty", "$path: " .
                 "LowerLayers is <Empty> for higher-layer interface; " .
                 "probably incorrect?")
            if !$lowerLayersValue && $ipath =~ /\.($higherLayerInterfaces)\./;

        # XXX this is a sanity check (to check that all interface types are
        #     covered by the above patterns) that can be removed or commented
        #     out
        main::d0msg "$path: unexpected interface type"
            unless $ipath =~ /\.($allInterfaces)\./;

        my $lowerLayerPaths = util_list_values($lowerLayersValue, 1);

        # check for inappropriate multi-valued LowerLayers
        # XXX the Bridge.Port pattern assumes use of Instance Number Instance
        #     Identifiers
        # XXX the ManagementPort logic is bridge-port-specific; a management
        #     port will typically have multiple lower layers
        # XXX strictly there can be missing objects, so for example an IP
        #     Interface could sit on top of multiple Ethernet Interfaces
        #     (indicating that Ethernet.Link and bridging is not modeled); we
        #     don't support that; see the $validLowerLayers table below; this
        #     contains the necessary information!
        # XXX not accounting for vendor extension interfaces
        my $multiLowerLayerInterfaces =
            q{DSL\.BondingGroup|Bridge\.\{i\}\.Port};
        my $mpPath = qq{${path}ManagementPort};
        my $mpItem = $items->{$mpPath};
        my $mpValue = $mpItem ? util_boolean($mpItem->{value}) : undef;
        util_msg("error", "interface-lowerlayers-multiple", "$path: " .
                 "LowerLayers ($lowerLayersValue) is multi-valued, which is " .
                 "probably incorrect?")
            if @$lowerLayerPaths > 1 &&
            !($ipath =~ /\.($multiLowerLayerInterfaces)\./ && $mpValue);

        # individual LowerLayer checks
        foreach my $llPath (@$lowerLayerPaths) {
            # this, being the value of a pathRef shouldn't have a trailing
            # period, so add one if missing
            $llPath .= '.' unless $llPath =~ /\.$/;
            
            # note: we collect the (Interface,LowerLayer) relations into
            #       $tr181->{ifstack}->{links} for later analysis
            $tr181->{ifstack}->{links}->{$path}->{$llPath}++;

            # note: no need to report if LowerLayer doesn't exist, because
            #       generic pathRef checks will take care of this
            my $llItem = $items->{$llPath};
            next unless defined $llItem;

            # check that LowerLayer is an interface object
            my $llNode = util_get_node($node, $llPath);
            my $llIsInterface = node_is_interface($llNode, $llItem);
            util_msg("error", "interface-lowerlayer-notinterface", "$path: " .
                     "LowerLayer $llPath is not an interface object")
                if !$llIsInterface;

            # check that LowerLayer is an expected type for this object
            my $llIpath = util_ipath($llPath);
            util_msg("error", "interface-lowerlayer-invalid", "$path: " .
                     "LowerLayer $llPath is not valid for this type of " .
                     "interface")
                if $llIsInterface && !lowerlayer_is_valid($ipath, $llIpath, 0);

            # LowerLayer.Status
            # note: no need to report if LowerLayer.Status doesn't exist,
            #       because generic interface checks will take care of this
            my $llStatusPath = qq{${llPath}Status};
            my $llStatusItem = $items->{$llStatusPath};
            next unless defined $llStatusItem;

            # Status / LowerLayer.Status consistency
            # XXX we allow "Enabled" on LowerLayer.Status to avoid two error
            #     messages when the lower layer isn't an interface object
            # XXX there are probably more meaningful combinations that could
            #     be checked
            my $llStatusValue = $llStatusItem->{value};
            util_msg("warning", "interface-lowerlayer-status-inconsistent",
                     "$path: interface Status ($statusValue) and LowerLayer " .
                     "$llPath Status ($llStatusValue) are inconsistent")
                if defined($statusValue) && defined($llStatusValue) &&
                ($statusValue eq 'Up' && $llStatusValue !~ /^(Up|Enabled)$/);
        }

        # Upstream checks
        my $upstreamPath = qq{${path}Upstream};
        my $upstreamItem = $items->{$upstreamPath};
        if ($upstreamItem) {
            my $upstreamValue = util_boolean($upstreamItem->{value});

            # check that Upstream settings are suitable for interface type
            # (might need to check whether there is a Router instance)
            my $routerNode =
                util_get_node($node, 'Device.Routing.Router.{i}.');
            util_msg("warning", "interface-upstream-invalid", "$path: " .
                     "Upstream ($upstreamValue) is probably invalid?")
                if (!$upstreamValue &&
                    $ipath =~ /\.($lowerLayerInterfacesAlwaysUpstream)\./) ||
                    ($upstreamValue && $routerNode &&
                     $ipath =~ /\.($lowerLayerInterfacesUsuallyDownstream)\./);

            # check that at least one Upstream parameter is true
            # note: the actual check is in instantiated_end()
            $tr181->{upstream}->{seen} = 1;
            $tr181->{upstream}->{true} = 1 if $upstreamValue;
        }
    }
}

# determine whether a (DM) node represents an interface object
# note: not all interface object "Enable" parameters are declared in the
#       XML as enableParameter (possibly an error) so this isn't checked
# note: interface objects should have a "LowerLayers" parameter and a "Stats."
#       object but this might not absolutely always be the case; so they aren't
#       checked
sub node_is_interface {
    my ($node, $item) = @_;

    # item attributes
    my $path = $item->{path};

    # Enable?
    my ($enableNode) = grep { $_->{name} eq 'Enable' } @{$node->{nodes}};
    return 0 unless $enableNode;

    # Status
    my ($statusNode) = grep { $_->{name} eq 'Status' } @{$node->{nodes}};
    return 0 unless $statusNode;

    # Status values?
    my $statusValues = $statusNode->{values};
    return 0 unless $statusValues && %$statusValues;
    
    my @statusEnums = grep
    {$_ =~ /^(Up|Down|Unknown|Dormant|NotPresent|LowerLayerDown|Error)$/}
    keys %$statusValues;
    return 0 unless @statusEnums == 7;

    # Alias?
    my ($aliasKey) = grep { !$_->{functional} && @{$_->{keyparams}} == 1 &&
                                $_->{keyparams}->[0] eq 'Alias'}
    @{$node->{uniqueKeys}};
    return 0 unless $aliasKey;

    # Name?
    my ($nameKey) = grep { !$_->{functional} && @{$_->{keyparams}} == 1 &&
                                $_->{keyparams}->[0] eq 'Name'}
    @{$node->{uniqueKeys}};
    return 0 unless $nameKey;

    # LastChange?
    my ($lastChangeNode) =
        grep { $_->{name} eq 'LastChange' } @{$node->{nodes}};
    return 0 unless $lastChangeNode;

    # yes it looks like an interface object
    return 1;
}

# check whether LowerLayer is valid for this item
# XXX this is currently disappointing because it allows all interface objects
#     between the source and the target to be omitted, which probably
#     suppresses a lot of true errors
# XXX also bridge ports are annoying because of management ports; to avoid
#     an infinite loop "Portx" is used (with a hack so Port -> Port references
#     work
# XXX it might be better to work with full ipaths or with paths (so can check
#     actual ManagementPort parameters)?
sub lowerlayer_is_valid {
    my ($ipath, $target, $indent) = @_;

    my $i = '  ' x $indent;

    main::d0msg $i, "lowerlayer_is_valid: $ipath $target";

    # XXX the "Portx" hack requires the target to be changed in the
    #     Port -> Port case
    $target =~ s/\.Port\./\.Portx\./
        if $ipath =~ /\.Port\./ && $target =~ /\.Port\./;

    # note: this information comes from TR-181i2 Figure 5
    # XXX there is no information about whether LowerLayers can be multi-
    #     valued; this would be useful to include here (currently it's checked
    #     separately); would like all known info about interface objects
    #     to be defined in data structures rather than code
    # XXX logic needs to be able to skip missing interfaces, not only because
    #     of vendor interfaces but because some of the standard interfaces
    #     (maybe all of them?) are optional
    # XXX this ignores the possibility of vendor interface objects
    my $figure5 = {
        'IP.Interface' => ['PPP.Interface'],
        'PPP.Interface' => ['Ethernet.VLANTermination'],
        'Ethernet.VLANTermination' => ['Ethernet.Link'],
        'Ethernet.Link' => ['Bridge.{i}.Port'],
        'Bridge.{i}.Port' => ['Bridge.{i}.Portx'],
        'Bridge.{i}.Portx' =>
            ['ATM.Link', 'PTM.Link', 'Optical.Interface',
             'Cellular.Interface', 'Ethernet.Interface',
             'USB.Interface', 'HPNA.Interface', 'MoCA.Interface',
             'Ghn.Interface', 'HomePlug.Interface', 'UPA.Interface',
             'WiFi.SSID'],
        'ATM.Link' => ['DSL.Channel', 'DSL.BondingGroup'],
        'PTM.Link' => ['DSL.Channel', 'DSL.BondingGroup'],
        'DSL.BondingGroup' => ['DSL.Channel'],
        'DSL.Channel' => ['DSL.Line'],
        'WiFi.SSID' => ['WiFi.Radio'],
        'DSL.Line' => [],
        'Optical.Interface' => [],
        'Cellular.Interface' => [],
        'Ethernet.Interface' => [],
        'USB.Interface' => [],
        'HPNA.Interface' => [],
        'MoCA.Interface' => [],
        'Ghn.Interface' => [],
        'HomePlug.Interface' => [],
        'UPA.Interface' => [],
        'WiFi.Radio' => []
    };
    
    # find the item's Figure 5 entry
    my ($key) = grep { $ipath =~ /(^|\.)\Q$_\E(\.|$)/ } keys %$figure5;

    # if not found, this is either not an interface object (assume that this
    # has already been reported) or else the interface object isn't in Figure
    # 5; in either case assume that it is valid
    main::d0msg $i, "  not found in Figure 5" unless defined $key;
    return 1 unless $key;
    
    # get the valid next layer objects
    my $nextLayers = $figure5->{$key};

    # if the list is empty, we got to the PHY layer without finding the target,
    # so it's not valid
    main::d0msg $i, "  empty list so not found" unless @$nextLayers;
    return 0 unless @$nextLayers;

    # if the target is in the list, we are done
    # XXX I don't like the way that we have to do two lookups; this indicates
    #     that the logic is faulty
    my ($found) = grep { $target =~ /(^|\.)\Q$_\E(\.|$)/ } @$nextLayers;
    main::d0msg $i, "  $target found" if $found;
    return 1 if $found;

    # loop through the valid next layers
    foreach my $nextLayer (@$nextLayers) {
        return 1 if lowerlayer_is_valid($nextLayer, $target, $indent+1);
    }

    # not found
    main::d0msg $i, "  $target not found";
    return 0;
}

# checks that apply to parameters
sub parameter_checks {
    my ($node, $item) = @_;

    # node attributes
    my $type = $node->{type};
    my $access = $node->{access};
    my $values = $node->{values};
    my $syntax = $node->{syntax};

    # item attributes
    my $path = $item->{path};
    my $writable = $item->{writable};
    my $value = $item->{value};

    # if value is undefined, assume an empty string
    # XXX should handle this better; undefined value probably indicates
    #     an error retrieving it, so should discard?
    $value = '' unless defined $value;
    my $tval = $value ? $value : '<Empty>';

    # create readable representation of data type (including enumerations)
    my $dmvalues = $values ? join ', ', keys %$values : '';
    my $details = $dmvalues ? ('enum {' . $dmvalues . '}') :
        main::syntax_string($type, $syntax);

    # extract individual values from lists
    my $is_list = $syntax->{list};
    my $listvals = util_list_values($value, $is_list);

    # check that the number of list items is valid
    if ($is_list) {
        my $numItems = @$listvals;
        my $listRanges = $syntax->{listRanges};
        my $valid = ($listRanges && @$listRanges) ? 0 : 1;
        foreach my $listRange (@$listRanges) {
            my $minItems = $listRange->{minInclusive};
            my $maxItems = $listRange->{maxInclusive};
            $valid = ((!defined $minItems || $numItems >= $minItems) &&
                      (!defined $maxItems || $numItems <= $maxItems));
        }
        util_msg("error", "badval-list-items", "$path: value $tval " .
                 "is invalid; should be $details") unless $valid;
    }
    
    # check the individual values
    # XXX $details refers to the entire parameter value, which could be
    #     confusing for lists
    my $hidden = $syntax->{hidden};
    my ($has_pattern) = $values && %$values &&
        grep {$values->{$_}->{facet} eq 'pattern'} keys %$values;
    foreach my $val (@$listvals) {
        my $tval = $val ? $val : '<Empty>';

        # XXX this is messy because values aren't necessarily canonical
        if ($hidden) {
            my $nullval = util_null_value($node);
            my $tnullval = $nullval ? $nullval : '<Empty>';
            util_msg("error", "badval-hidden", "$path: value $tval is " .
                     "invalid; should be hidden, i.e. be $tnullval")
                if $val ne $nullval;
        }

        # XXX not yet checking patterns
        elsif ($has_pattern) {
        }

        else {
            my ($ignore, $msgs) = util_valid_value($node, $val);
            foreach my $msg (@$msgs) {
                my ($reason, $mdetails, $warning) =
                    ($msg->{reason}, $msg->{details}, $msg->{warning});
                my $severity = $warning ? "warning" : "error";
                my $probably = $warning ? "probably " : "";
                # we figure that for errors we need to provide full details,
                # but for warnings only a hint is necessary
                $mdetails =
                    $warning ? ($mdetails ? $mdetails : $details) :
                    ($mdetails ? qq{$details ($mdetails)} : $details);
                util_msg($severity, "badval-$reason", "$path: value $tval " .
                         "is ${probably}invalid; should be $mdetails");
            }

            # check Alias parameters (if possible)
            # XXX I don't think anything is possible, because we don't know
            #     which values have been assigned by the ACS; there could be
            #     a flag that asserts that all values are CPE-assigned;
            #     uniqueness is already checked
            
            # check Order parameters
            # XXX I don't think that anything is possible, because there is
            #     no specific DM support for Order parameters; I have noted
            #     that they should use a named data type and should be
            #     non-functional unique keys
            
            # check time zone parameters
            # XXX this is a check of a specific parameter; could generalise
            #     it a bit, e.g. by checking parameters whose names end with
            #     "TimeZone" and are strings; I have noted that they should
            #     use a named data type
            
            # check references
            my $reference = $syntax->{reference};
            if ($reference) {

                # pathRef
                if ($reference eq 'pathRef') {
                    my $refType = $syntax->{refType};

                    util_msg("warning", "badval-trailing-period", "$path: " .
                             "value $tval has invalid trailing period")
                        if $val =~ /\.$/;

                    # create values with and without the trailing period
                    my $valNoPeriod = $val;
                    my $valWithPeriod = $val;
                    $valNoPeriod =~ s/\.?$// if $val;
                    $valWithPeriod =~ s/\.?$/\./ if $val;

                    # determine whether actual item name must not / must /
                    # might have a period
                    my $targetType = $syntax->{targetType};
                    my $mustNotHavePeriod = $targetType eq 'parameter';
                    my $mustHavePeriod =
                        $targetType ne 'parameter' && $targetType ne 'any';
                    my $mightHavePeriod = $targetType eq 'any';

                    # check whether the referenced item exists
                    # XXX for weak references could still check the syntax
                    my $refitemNoPeriod = $items->{$valNoPeriod};
                    my $refitemWithPeriod = $items->{$valWithPeriod};
                    my $found =
                        ($mustNotHavePeriod && $refitemNoPeriod) ||
                        ($mustHavePeriod && $refitemWithPeriod) ||
                        ($mightHavePeriod &&
                         ($refitemNoPeriod || $refitemWithPeriod));
                    util_msg("error", "badval-refnonex", "$path: $refType " .
                             "$targetType reference $tval doesn't exist")
                        if $refType eq 'strong' && $val && !$found;

                    # if the referenced item exists...
                    # XXX could check this anyway, since the reference could
                    #     be to an invalid instance of a valid object
                    if ($found) {
                        my $refitem = $refitemNoPeriod || $refitemWithPeriod;
                        my $refitemPath = $refitem->{path};

                        # get its parent path and convert it to an "ipath"
                        my $refitemPpath = util_ppath($refitemPath);
                        my $refitemIppath = util_ipath($refitemPpath);
                    
                        # check that it's permitted
                        my $targetParent = $syntax->{targetParent};
                        if ($targetParent) {
                            my $parent = $node->{pnode}->{path};
                            my $targetParentScope =
                                $syntax->{targetParentScope};
                            my $tpps = [];
                            my $found = 0;
                            foreach my $tp (split ' ', $targetParent) {
                                my ($tpp) = main::relative_path(
                                    $parent, $tp, $targetParentScope);
                                push @$tpps, $tpp;
                                $found = 1 if $tpp eq $refitemIppath;
                            }
                            my $validParents = '(' . join(', ', @$tpps) . ')';
                            util_msg("error", "badval-refwrongobj", "$path: " .
                                     "referenced item $refitemPath is " .
                                     "invalid; should be a child of one of " .
                                     "$validParents")
                                if !$found;
                        }
                    }
                }

                # instanceRef (not very important; TR-181 contains no
                # instanceRefs)
                # XXX TBD
                elsif ($reference eq 'instanceRef') {
                }

                # enumerationRef
                # XXX TBD
                elsif ($reference eq 'enumerationRef') {
                }
            }
        }
    }
}

########################################################################
# end:
sub instantiated_end {
    util_msg("_info", "general", "");
    util_msg("_info", "general", "The following are not specific to " .
        "individual objects and parameters:");

    # report on Upstream
    # note: $tr181->{upstream} was updated during the node traveral
    util_msg("error", "interface-upstream-none", "  No interface objects " .
             "have Upstream=1")
        if $tr181->{upstream}->{seen} && !$tr181->{upstream}->{true};
    
    # check that InterfaceStack matches LowerLayers
    # note: $tr181->{ifstack} was updated during the node traversal
    if (defined $tr181->{ifstack}->{table} &&
        defined $tr181->{ifstack}->{links}) {
        my $diffs = ifstack_diffs($tr181->{ifstack}->{table},
                                  $tr181->{ifstack}->{links});

        # XXX as a sanity check, verify that ifstack_diffs() and Data::Compare
        #     agree; can remove or comment out this check
        my $compare = Compare($tr181->{ifstack}->{table},
                              $tr181->{ifstack}->{links});
        main::emsg "Error! ifstack_diffs() and Data::Compare disagree"
            if (@$diffs ? 0 : 1) != $compare;

        # note: this is classed as "info" because each of the differences
        #       is classed as an error (i.e. it avoids an off-by-one error)
        util_msg("_info", "ifstack-inconsistent", "  Device.InterfaceStack " .
                 "and LowerLayers parameters are inconsistent") if @$diffs;
        foreach my $diff (@$diffs) {
            util_msg("fatal", "ifstack-inconsistent", qq{    $diff});
        }
    }

    # report on unvisited instantiated items
    my $unvisited = create_unvisited();
    report_unvisited($unvisited, 0, 0);
    
    # report message statistics
    util_msg_stats();
}

# compare two versions of the interface stack, one created from
# Device.InterfaceStack and the other created from LowerLayers parameters
#
# return a reference to an array containing an entry per difference (a text
# message that the caller might want to output)
sub ifstack_diffs {
    my ($table, $links) = @_;
    
    my $diffs = [];

    # go through "table" (created from Device.InterfaceStack) and note
    # things not in "links" (created from LowerLayers parameters)
    foreach my $higher (sort util_path_cmp keys %$table) {
        foreach my $lower (sort util_path_cmp keys %{$table->{$higher}}) {
            if (!grep { $_ eq $lower } keys %{$links->{$higher}}) {
                push @$diffs, "Only in InterfaceStack: $higher -> $lower";
            }
        }
    }
    
    # go through "links" and note things not in "table"
    foreach my $higher (sort util_path_cmp keys %$links) {
        foreach my $lower (sort util_path_cmp keys %{$links->{$higher}}) {
            if (!grep { $_ eq $lower } keys %{$table->{$higher}}) {
                push @$diffs, "Only in LowerLayers: $higher -> $lower";
            }
        }
    }
    
    return $diffs;
}

# XXX the tree structure is rather unconventional?  normally expect to deal
#     with the current node before dealing with the sub-tree; but it works,
#     so leave it as is
sub create_unvisited {
    my $unvisited = {};
    foreach my $path (keys %$items) {
        my $item = $items->{$path};

        my $ipath = util_ipath($path); 
        my $ipath_full = util_ipath($path, 1);

        if (!$ipath_ignore->{$ipath} && !$item->{visited}) {

            my @comps = split /\./, $ipath_full;
            
            my $node = $unvisited;
            for (my $i = 0; $i < @comps; $i++) {
                my $comp = $comps[$i];
                my $last = ($i == @comps - 1);

                # this is messy... it includes the period in the component
                # name so the concatenation of the components will be the path
                $comp .= '.' if !$last || $ipath =~ /\.$/;

                # this too is messy... it's purely to force the new object to
                # be created; is there a better way?
                $node->{$comp}->{_count}++;

                # this keeps track of whether this item is undefined
                $node->{$comp}->{_undefined} = 1 if $last;
                
                $node = $node->{$comp};
            }
        }
    }

    return $unvisited;
}

sub report_unvisited {
    my ($node, $indent, $force_info) = @_;

    my $i = '  ' x $indent;

    if ($indent == 0) {
        util_msg("_info", "data-model-missing", "");
        util_msg("_info", "data-model-missing", "The following objects and " .
                 "parameters were not checked because there are no " .
                 "available data model definitions:");
        return report_unvisited($node, $indent+1, $force_info);
    }

    foreach my $key (sort util_path_cmp keys %$node) {
        # keys whose names begin with underscore are used internally
        next if $key =~ /^_/;

        my $undefined = $node->{$key}->{_undefined} ? 1 : 0;
        my $vendor = ($key =~ /^X_/);

        my $severity = ($force_info || !$undefined) ? "_info" :
            $vendor ? "warning" : "error";

        util_msg($severity, "data-model-missing", "$i$key");

        report_unvisited($node->{$key}, $indent+1, $force_info || $vendor );
    }
}

########################################################################
# utilities

# convert path to an "ipath" in which instance numbers are "{i}", as in
# DM Instances
sub util_ipath {
    my ($path, $full) = @_;
    
    my $ipath = $path;
    $ipath =~ s/\.\d+/.{i}/g;

    # optionally remove leading <Root>.Services. because this isn't included in
    # DM Instances
    $ipath =~ s/^[\w-]+\.Services\.// unless $full;

    return $ipath;
}

# convert path to name, i.e. the last component of the path
sub util_name {
    my ($path) = @_;

    my $name = $path;
    $name =~ s/^.*?([\w-]+\.?)$/$1/;

    return $name;
}

# convert path to parent path (counting A.n as two levels)
sub util_ppath {
    my ($path) = @_;

    my $ppath = $path;
    $ppath =~ s/([\w-]+|\{i\})\.?$//;

    return $ppath;
}

# does ipath refer to a table?
sub util_is_table {
    my ($ipath) = @_;

    return ($ipath =~ /\{i\}\.$/);
}

# extract individual values from a list
sub util_list_values {
    my ($value, $is_list) = @_;
    
    my @values = ();

    if (!$is_list) {
        push @values, $value;
    }

    # note: we assume that an empty string is an empty list rather than a
    #       list with a single empty value
    elsif ($value ne '') {
        foreach my $val (split ',', $value) {
            # XXX not handling nested brackets or percent escapes
            $val =~ s/^\s*//;
            $val =~ s/\s*$//;
            push @values, $val;
        }
    }

    return \@values;
}

# given any node in the correct data model and an item path, get the
# corresponding node
# XXX this routine knows things that it shouldn't know
# XXX this routine doesn't work for "table" nodes, e.g. Device.IP.Interface.
#     because these aren't in the node tree
# XXX does this routine work for items in Service Objects?
sub util_get_node {
    my ($node, $itemPath) = @_;

    # get the item's "ipath"
    # note: it is also possible to supply an "ipath" in the first place
    my $itemIpath = util_ipath($itemPath);

    # the supplied node is from the correct data model; get its model name
    # prefix, i.e. a string like "Device:2."
    my $fpath = main::util_full_path($node, 1);

    # and append the item ipath to give the item's "full path"
    $fpath .= $itemIpath;

    # this "full path" can be used as an index into the global
    # "objects" or "parameters" hashes in order to retrieve the node
    my $hash = ($fpath =~ /\.$/) ? $main::objects : $main::parameters;
    my $itemNode = $hash->{$fpath};

    return $itemNode;
}

# determine a node value's primitive type and (if requested) named data type
# XXX this routine could be provided by report.pl
sub util_primitive_type {
    my ($node) = @_;

    my $type = $node->{type};
    my $syntax = $node->{syntax};

    my $typeinfo = main::get_typeinfo($type, $syntax);
    my $value = $typeinfo->{value};
    my $is_datatype = $typeinfo->{dataType};
    
    my ($primtype, $datatype) = $is_datatype ?
        (main::base_type($value, 1), $value) :
        ($value, undef);
    
    return wantarray ? ($primtype, $datatype) : $primtype;
}

# return the null value for the data type
sub util_null_value {
    my ($node) = @_;
   
    my $primtype = util_primitive_type($node);

    my $nullvalue = {
        base64 => '',
        boolean => 'false',
        hexBinary => '',
        int => -1,
        long => -1,
        string => '',
        unsignedInt => 0,
        unsignedLong => 0}->{$primtype};

    main::emsg "$node->{path}: unsupported type $primtype"
        unless defined $nullvalue;

    return $nullvalue;
}

# determine whether a value is valid for a given parameter
# XXX $ignore_ranges is for use (in report.pl) when checking that ranges are
#     valid; there should also be $ignore_sizes... so in fact both should be
#     handled via an options hash
# XXX based on the (incomplete) report.pl valid_value() routine, extended
#     to be more complete (and could potentially be moved back to report.pl);
#     report.pl of course only has limited need for such a routine, which it
#     uses mostly for checking ranges and defaults
sub util_valid_value {
    my ($node, $value, $ignore_ranges) = @_;

    # determine primitive and (if applicable) named data type
    my ($primtype, $datatype) = util_primitive_type($node);

    # create and return a list of messages explaining why the value is invalid;
    # each message is a hash with mandatory key 'reason' (short string) and
    # optional keys 'details' (longer string) and 'warning' (boolean; default is
    # error)
    my $msgs = [];

    # string
    # XXX need to extend to patterns; in the mean time, at least don't fail if
    #     a pattern fails to match
    if ($primtype eq 'string') {
        push @$msgs, {reason => 'size', details => 'invalid size'}
        if !util_valid_size($node, $value);

        my $values = $node->{values};
        push @$msgs, {reason => 'enum', details => 'not in list'}
        if main::has_values($values) && !main::has_value($values, $value);
    }

    # boolean
    elsif ($primtype eq 'boolean') {
        push @$msgs, {reason => 'syntax', details => 'invalid syntax'}
        if $value !~ /^(0|1|false|true)$/;
    }

    # numeric: int, long, unsignedInt, unsignedLong
    # XXX $ignore_ranges is currently ignored
    elsif ($primtype =~ /^(int|long|unsignedInt|unsignedLong)$/) {
        my $pattern_for_numeric_type = {
            int => qr/^(-?\d+)$/,
            long => qr/^(-?\d+)$/,
            unsignedInt => qr/^(\d+)$/,
            unsignedLong => qr/^(\d+)$/
        };
        if ($value !~ /$pattern_for_numeric_type->{$primtype}/) {
            push @$msgs, {reason => 'syntax', details => 'invalid syntax'};
        } else {
            push @$msgs, {reason => 'range', 'out of range'}
            if !util_valid_range($node, $value);
        }
    }

    # dateTime
    # XXX thanks to erik swanson for these regexes
    # XXX not validating the individual fields
    elsif ($primtype eq 'dateTime') {
        my $abspatt = qr/^[1-9]\d\d\d-\d\d-\d\dT/ .
            qr/\d\d:\d\d:\d\d(\.\d+)?(Z|-00:00|\+00:00)$/;
        my $relpatt = qr/^0\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?$/;

        # specific test for the unknown time is needed because it
        # doesn't match either of the above patterns (it has a "Z");
        my $unktime = q{0001-01-01T00:00:00Z};

        # specific test for the infinite time is not needed but it's
        # listed here because it is called out by the standard
        my $inftime = q{9999-12-31T23:59:59Z};

        push @$msgs, {reason => 'date-time'}
        unless $value =~ /$abspatt/ || $value =~ /$relpatt/ ||
            $value eq $unktime || $value eq $inftime;
    }

    # hexBinary
    elsif ($primtype eq 'hexBinary') {
        my $hexpatt = qr/^[0-9A-Fa-f]*$/;
        push @$msgs, {reason => 'hex-binary'}
        unless $value =~ /$hexpatt/ && length($value) % 2 == 0;
    }
            
    # base64
    # XXX TBD
    elsif ($primtype eq 'base64') {
    }

    # named data type checks
    if (!defined($datatype)) {
    }

    # IP address / prefix
    # XXX could clean this up plus check prefix length better
    elsif ($datatype =~ /^IP.*(Address|Prefix)$/) {
        my $v4 = ($datatype =~ /v4/);
        my $v6 = ($datatype =~ /v6/);
        my $address = ($datatype =~ /Address$/);
        my $prefix = ($datatype =~ /Prefix$/);
        my ($add, $pre) = ($value =~ /^([^\/]*)\/(\d+)$/);
        $add = $value unless defined $add;
        push @$msgs, {reason => 'ip-address'}
        if ($add &&
            (($v4 && !is_ipv4($add)) ||
             ($v6 && !is_ipv6($add)) ||
             (!$v4 && !$v6 && !is_ipv4($add) && !is_ipv6($add))))||
             ($prefix && $value && !defined $pre);
                    
        my $ipv4zero = qr/^(0+\.){3}0+$/;
        my $ipv6zero = qr/^(0*::){1,7}0*$/;
        push @$msgs, {reason => 'nonempty', details => '<Empty>?',
                      warning => 1}
        if $address && ($value =~ /$ipv4zero/ || $value =~ /$ipv6zero/);
    }
    
    # MAC address
    # XXX other suspicious MAC addresses, e.g. fe:ff:ff:00:00:00?
    elsif ($datatype eq 'MACAddress') {
        my $macpatt = qr/([0-9A-Fa-f][0-9A-Fa-f]:){5}/ .
            qr/([0-9A-Fa-f][0-9A-Fa-f])/;
        push @$msgs, {reason => 'mac-address'}
        unless $value eq '' || $value =~ /$macpatt/;

        push @$msgs, {reason => 'nonempty', details => '<Empty>?',
                      warning => 1}
        if $value eq '00:00:00:00:00:00';
    }
    
    # XXX more named data types
    
    # always indicate whether the value was valid plus, in array context,
    # return a reference to the list of messages
    my $valid = @$msgs ? 0 : 1;
    return wantarray ? ($valid, $msgs) : $valid;
}

# determine whether a string value has a valid size
# note: the sizes are assumed not to overlap
sub util_valid_size {
    my ($node, $value) = @_;

    my $syntax = $node->{syntax};
    my $sizes = $syntax->{sizes};

    return 1 unless $sizes && @$sizes;

    my $len = length $value;

    my $anygood = 0;
    foreach my $size (@$sizes) {
        my $minlen = $size->{minLength};
        my $maxlen = $size->{maxLength};
        
        $minlen =
            $main::range_for_type->{unsignedInt}->{min} unless defined $minlen;
        $maxlen =
            $main::range_for_type->{unsignedInt}->{max} unless defined $maxlen;

        $anygood++ if $len >= $minlen && $len <= $maxlen;
    }

    return $anygood ? 1 : 0;
}

# determine whether a numberic value is within range
# note: the ranges are assumed not to overlap
sub util_valid_range {
    my ($node, $value) = @_;

    my $syntax = $node->{syntax};
    my $ranges = $syntax->{ranges};

    return 1 unless $ranges && @$ranges;

    # XXX this is used when minInclusive or maxExclusive are undefined; would
    #     be better either to have these pre-filled-in (although for some
    #     purposes need to know whether they were specified) or else at least
    #     pass the range-for-type as a parameter
    my $primtype = util_primitive_type($node);
    my $min_for_type = $main::range_for_type->{$primtype}->{min};
    my $max_for_type = $main::range_for_type->{$primtype}->{max};
    return 1 unless defined $min_for_type && defined $max_for_type;

    # the ranges don't include the full range for the data type, so this
    # needs to be checked separately
    # XXX is it actually safe to compare against min/max for type?
    return 0 if $value < $min_for_type || $value > $max_for_type;
    
    my $anygood = 0;
    foreach my $range (@$ranges) {
        my $minval = $range->{minInclusive};
        my $maxval = $range->{maxInclusive};
        my $step = $range->{step};

        $minval = $min_for_type unless defined $minval;
        $maxval = $max_for_type unless defined $maxval;
        $step   = 1 unless defined $step;

        $anygood++ if
            $value >= $minval && $value <= $maxval &&
            ($value - $minval) % $step == 0;
    }

    return $anygood ? 1 : 0;
}

# sort compare function: compare items by path
sub util_item_cmp {
    return util_path_cmp_helper($a->{path}, $b->{path});
}

# sort compare function: compare paths
sub util_path_cmp {
    return util_path_cmp_helper($a, $b);
}

# compare path name helper, sorting alphabetically (ignoring case) on
# non-numeric components and numerically on numeric components (instance
# numbers)
sub util_path_cmp_helper {
    my ($ap, $bp) = @_;

    # split paths into components
    my @ac = split /\./, $ap;
    my @bc = split /\./, $bp;

    # compare component by component
    my $nc = @ac < @bc ? @ac : @bc;
    for (my $i = 0; $i < $nc; $i++) {
        my $ac = $ac[$i];
        my $bc = $bc[$i];
        
        # if they are different, sort alphabetically (ignoring case) or
        # numerically as appropriate
        # XXX also sort things that don't end with periods before things
        #     that do (this is to place parameters first when reporting
        #     unvisited items; should document it properly and/or use a
        #     separate routine - invoked by this - for sorting names)
        # XXX the messy use of $ap and $bp is because split will have
        #     discarded the periods! don't really need the $nc check...
        if ($ac ne $bc) {
            my $num = ($ac =~ /^\d+$/ && $bc =~ /^\d+$/);
            my $acp = ($i == $nc-1 && $ap !~ /\.$/);
            my $bcp = ($i == $nc-1 && $bp !~ /\.$/);
            
            if ($num) {
                return $ac <=> $bc;
            } elsif ($acp && !$bcp) {
                return -1;
            } elsif (!$acp && $bcp) {
                return +1;
            } else {
                return lc($ac) cmp lc($bc);
            }
        }
        
        # if they are the same, proceed to the next component
    }

    # if not all components have been compared, the shorter comes first
    return @ac <=> @bc;
}

# return 0/1 given string representation of boolean
# XXX modified from report.pl's sub boolean; report.pl version allows "t"
sub util_boolean
{
    my ($value, $default) = @_;
    $default = 0 unless defined $default;
    return (!$value) ? $default : ($value =~ /1|true/i) ? 1 : 0;
}

# message statistics
my $msgstats = {};

# basic message handling; can improve later
sub util_msg {
    my ($severity, $name, $text) = @_;

    my $sev = $severity;
    $sev =~ s/^_?(.).*$/$1/;
    $sev = uc $sev;
    $sev = "($sev) ";

    my $nl = ($text =~ /\n$/) ? "" : "\n";

    print "$sev$text$nl";

    # save for stats
    $msgstats->{$severity}->{$name}->{count}++ if $name;
}

sub util_msg_stats {
    util_msg("_info", "stats", "");
    util_msg("_info", "stats", "Message Summary:");

    my $grand_total = 0;
    # XXX how to control the order?
    foreach my $sevname (sort grep { $_ !~ /^_/ } keys %$msgstats) {
        my $Sevname = ucfirst $sevname;
        my $msgs_for_sev = $msgstats->{$sevname};
        
        util_msg("_info", "stats", "  ${Sevname}s:");

        my $total = 0;
        foreach my $msgname (sort keys %$msgs_for_sev) {
            my $count = $msgs_for_sev->{$msgname}->{count};
            util_msg("_info", "stats", "    $msgname: $count");
            $total += $count;
        }

        util_msg("_info", "stats", "    Total ${Sevname}s: $total");
        $grand_total += $total;
    }
    util_msg("_info", "stats", "  Grand Total: $grand_total");
}

########################################################################
1;
