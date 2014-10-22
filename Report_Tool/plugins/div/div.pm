# XXX comment this before I forget!

package div;

use strict;

use Data::Dumper;
use File::Spec;

my $settings = {};
my $groups = [];
my $curgroup = undef;

# 16 colors
# XXX take from config file?
# XXX not currently using these
my $colors = ['white', 'aqua', 'silver', 'teal', 'gray', 'olive', 'orange',
              'green', 'fuchsia', 'yellow', 'blue', 'black', 'black',
              'black', 'black', 'black'];

# nesting level
my $n;

# indent lines and return as string
# note that everything up to the first newline is discarded; this is because
# it's assumed called with qq{} with the text starting on the next line
sub output {
    my ($i, $lines) = @_;

    my $text = '';

    $lines =~ s/.*\n//;

    my $j = '  ' x $i;
    foreach my $line (split /\n/, $lines) {
        $text .= qq{$j$line\n};
    }

    return $text;
}

# helper for setting global settings
sub setting
{
    my ($name, $default) = @_;

    if (defined $main::options->{$name}) {
        $settings->{$name} = $main::options->{$name};
    } elsif (!defined $settings->{$name}) {
        $settings->{$name} = $default;
    }

    #print STDERR "$name = $settings->{$name}\n";
}

# helper for setting group settings (group name "." setting name)
sub gsetting
{
    my ($group, $name, $default) = @_;

    my $gname = $group->{name};
    my $gsname = qq{$gname.$name};

    if (defined $main::options->{$gsname}) {
        $group->{$name} = $main::options->{$gsname};
    } elsif (!defined $group->{$name}) {
        $group->{$name} = $default;
    }
    
    #print STDERR "$gsname = $group->{$name}\n";    
}

# parse config file and define groups
sub parse
{
    require Config::IniFiles;

    # determine config file name
    my $configfile = defined $main::options->{configfile} ?
        $main::options->{configfile} : qq{$main::report.ini};

    # find config file
    if ($configfile) {
        my ($dir, $file) = main::find_file($configfile);
        $configfile = File::Spec->catfile($dir, $file) if $dir;
    }

    # parse config file
    my $config = {};
    if ($configfile) {
        my %config;
        tie %config, 'Config::IniFiles', ( -file => $configfile,
                                           -allowcontinue => 1 );
        $config = \%config;
        if (@Config::IniFiles::errors) {
            foreach my $error (@Config::IniFiles::errors) {
                #print STDERR "$configfile: $error\n";
            }
            return;
        }
    }

    push @$groups, {name => '_top_', label => undef, ignore => 0, enable => 1,
                    text => ''};

    $config = {settings => {}} unless %$config;
    foreach my $section (keys %$config) {
        my $values = $config->{$section};

        # global settings
        if ($section eq 'settings') {
            $settings = $values;
            setting('border',  '1px');
            setting('colgap',  '5px');
            setting('columns', '1');
            setting('depth',   '0');
            setting('margin',  '5px');
            setting('pad',     '2px');
            setting('width',   '150px');
        }

        # groups
        else {
            push @$groups, $values;
            my $group = $groups->[-1];
            $group->{name} = $section;
            gsetting($group, 'ignore', '0');
            gsetting($group, 'enable', '1');
            gsetting($group, 'label', '');
            gsetting($group, 'text', '');
        }
    }

    push @$groups, {name => '_bot_', label => undef, ignore => 0, enable => 1,
                    text => ''};
}

# whether to ignore this node
sub ignore
{
    my ($node, $i) = @_;

    # ignore all but models and objects
    # XXX including models is an experiment
    return 1 if $node->{type} !~ /^(model|object)$/;

    # $i is depth (0=top, 1=model, 2=root); depth=1 is root
    return 1 if $settings->{depth} && $i > $settings->{depth} + 1;
}

# a list of the paths of this node's descendants
sub children
{
    my ($node) = @_;

    my $result = [];
    
    foreach my $child (@{$node->{nodes}}) {
        push @$result, $child->{path};
        push @$result, @{children($child)};
    }

    return $result;
}

# determine which group this top-level child, e.g. Device.DeviceInfo., is in
sub check
{
    my ($node) = @_;

    my $path = $node->{path};
    my $qpath = quotemeta($path);

    # e.g. root=Device. or STBService.{i}.
    my $root = $path;
    $root =~ s/\.\{/\{/g;
    $root =~ s/\..*/\./;
    $root =~ s/\{/\.\{/g;

    # XXX for both paths and patterns, should have done the scalar to array
    #     logic earlier

    foreach my $group (@$groups) {
        next if $group->{ignore};
        my $gname = $group->{name};
        my $gpaths = $group->{paths};
        $gpaths = [$gpaths] if defined $gpaths && ref($gpaths) ne 'ARRAY';
        next unless $gpaths && @$gpaths;
        foreach my $gpath (@$gpaths) {
            # e.g. gpath=DeviceInfo.
            my $fpath = qq{$root$gpath};
            # e.g. fpath=Device.DeviceInfo.
            if ($path eq $fpath) {
                #print STDERR "$gname: $path matches exactly\n";
                return $group;
            }
        }
    }
    
    foreach my $group (@$groups) {
        next if $group->{ignore};
        my $gname = $group->{name};
        my $gpatts = $group->{patts};
        $gpatts = [$gpatts] if defined $gpatts && ref($gpatts) ne 'ARRAY';
        next unless $gpatts && @$gpatts;
        # e.g. path=Device.DSL.
        my $cpaths = children($node);
        # e.g. cpath=Device.DSL.Line.{i}.LowerLayers
        foreach my $cpath (@$cpaths) {
            # e.g. gpatt=Line.{i}.LowerLayers
            foreach my $gpatt (@$gpatts) {
                # e.g. ppath=Device.DSL.Line.{i}.LowerLayers
                my $ppath = qq{$qpath$gpatt};
                if ($cpath =~ /$ppath/) {
                    #print STDERR "$gname: $path matches pattern\n";
                    return $group;
                }
            }
        }
    }

    # if doesn't match a group, it goes into the first group
    #print STDERR "$path doesn't match any group\n";
    return $groups->[0];
}

# determine minimum element width at this level
# assumes that the parent node width is in pnode->{div_width}
sub minwidth
{
    my ($node) = @_;

    my $pnode = $node->{pnode};
    
    # fixed settings
    my $border = $settings->{border};
    my $margin = $settings->{margin};
    my $pad    = $settings->{pad};
    
    # parent width (or width setting if not defined)
    my $pwidth = $pnode->{div_width} || $settings->{width};
    return qq{} unless $pwidth;
    
    # determine number of object siblings
    my $nsibs = scalar grep {$_->{type} eq 'object'} @{$pnode->{nodes}};

    # total width  = width + left padding + right padding + left border +
    #                        right border + left margin + right margin
    # total height = height + top padding + bottom padding + top border +
    #                         bottom border + top margin + bottom margin
    # (from outside to inside: margin, border, pad, content)
    # XXX this assumes that all of these are measured in the same units
    my ($borval, $borunit) = ($border  =~ /(\d+\.?\d*)(.*)/);
    my ($marval, $marunit) = ($margin  =~ /(\d+\.?\d*)(.*)/);
    my ($padval, $padunit) = ($pad     =~ /(\d+\.?\d*)(.*)/);
    my ($widval, $widunit) = ($pwidth  =~ /(\d+\.?\d*)(.*)/);

    # XXX we can't predict how the text will flow so it's hard or impossible
    #     to guarantee that things will look good; probably the best is
    #     just to adjust the child width so that everything would line up
    #     if there was one sibling per line (hence commented-out code below)

    # subtract margins to give sibling border box width
    #$widval -= 2 * $nsibs * $marval;
    $widval -= 2 * $marval;

    # what remains is shared by the siblings
    #$widval /= $nsibs;

    # subtract border and pad to give content width
    $widval -= 2 * ($borval + $padval);

    # XXX should treat last child differently to correct rounding errors
    
    $widval = 0 if $widval < 0;
    my $width = sprintf('%.2f%s', $widval, $widunit);
    $node->{div_width} = $width;
    return $width;
}

# called at the start
sub div_init
{
    # parse options and config file and define settings and groups
    parse();
}

# called just before traversing the node tree
sub div_begin
{
    my ($root) = @_;

    my $border = $settings->{border};
    my $colgap = $settings->{colgap};
    my $margin = $settings->{margin};
    my $pad    = $settings->{pad};
    my $width  = $settings->{width};

    # output header (doctype makes IE behave better)
    $curgroup = $groups->[0];
    $curgroup->{text} .= output 0, qq{
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
          "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
  <head>
    <style type="text/css">
      div.border {margin:$margin $margin $margin $margin;
                  padding:$pad $pad $pad $pad;}
      div.center {text-align: center;}
      div.clear {clear: both;}
};

    # colors
    # all are light colors, roughly cycling W -> C -> B -> M -> R -> Y -> G
    # but forcing color 2 to be C (these numbers are in the range 0:4)
    #        W    C    B  M  R  Y  G    B2 M2 R2
    my @r = (4,4, 0,0, 1, 4, 4, 3, 1,1, 1, 2, 2);
    my @g = (4,4, 4,3, 2, 2, 2, 3, 3,2, 1, 1, 1);
    my @b = (4,4, 4,4, 4, 4, 2, 1, 1,1, 2, 2, 1);
    for (my $j = 0; $j < 16; $j++) {
        #my $col = $colors->{$j};
        #my $r = (255 - 16 * $j);
        #my $g = (255 - 12 * $j);
        #my $b = (255 -  8 * $j);
        my $k = ($j < @r) ? $j : (@r - 1);
        my $r = 127 + 32 * $r[$k];
        my $g = 127 + 32 * $g[$k];
        my $b = 127 + 32 * $b[$k];
        my $col = sprintf('#%02x%02x%02x', $r, $g, $b);
        $curgroup->{text} .= output 0, qq{
      div.color$j {background-color: $col}
};
    } 
    $curgroup->{text} .= output 0, qq{
      div.dashed {border:dashed gray $border;}
      div.float {float: left;}
      div.gray {color: gray;}
      div.moveup {position:relative; top: -0.3em;}
      div.multi {-moz-column-count:$settings->{columns};
                 -webkit-column-count:$settings->{columns};
                 -column-count:$settings->{columns};
                 -moz-column-gap:$colgap;
                 -webkit-column-gap:$colgap;
                 column-gap:$colgap}
      div.solid {border:solid black $border;}
};

    # minimum widths
    # total width  = width + left padding + right padding + left border +
    #                        right border + left margin + right margin
    # total height = height + top padding + bottom padding + top border +
    #                         bottom border + top margin + bottom margin
    # XXX this assumes that all of these are measured in the same units
    # XXX this didn't work too well because it didn't account for children
    #     (but accounting for children is hard; see sub minwidth())
    #my ($borval, $borunit) = ($border =~ /(\d+)(.*)/);
    #my ($marval, $marunit) = ($margin =~ /(\d+)(.*)/);
    #my ($padval, $padunit) = ($pad    =~ /(\d+)(.*)/);
    #my ($widval, $widunit) = ($width  =~ /(\d+)(.*)/);
    #for (my $j = 0; $j < 16; $j++) {
    #    $curgroup->{text} .= output 0, qq{
    #  div.width$j {min-width: $widval$widunit}
    #};
    #    $widval -= 2 * ($padval + $borval + $marval);
    #}

    $curgroup->{text} .= output 0, qq{
    </style>
  </head>
  <body>
};

    $n = 2;
}

# called for each node: before children
sub div_node
{
    my ($node, $i) = @_;

    return if ignore($node, $i);

    my $path = $node->{path};
    my $name = $node->{name};

    # top-level child: check for group
    # (0=root-of-tree, 1=model, 2=root-object, 3=top-level-child)
    if ($i == 3) {
        $curgroup = check($node);
        #print STDERR "$path: switched to $curgroup->{name}\n";
        if ($curgroup->{label} && !$curgroup->{opened}) {
            $curgroup->{text} .= output $n, qq{
<div class="border dashed color$n float">
  <div class="center clear gray moveup">$curgroup->{label}</div>
};
            $curgroup->{opened} = 1;
        }
        $n++ if $curgroup->{opened};
    }
    
    # all nodes
    my $class = qq{};
    my $style = qq{};
    if ($i == 1) {
        $class = qq{ center gray moveup};
        # XXX suppress this until check how to avoid inheritance by children
        $class = qq{};
    } elsif ($i >= 3) {
        my $width = minwidth($node);
        $style = qq{ style="min-width: $width;"} if $width;
    }
    $curgroup->{text} .= output $n, qq{
<div class="border solid color$n float$class"$style>
  <div class="clear">$name</div>
};
    $n++;

    # root object: start multi-column
    # (0=root-of-tree, 1=model, 2=root-object)
    if ($i == 2) {
        $curgroup->{text} .= output $n, qq{
<div class="multi">
};
        $n++;
    }
}

# called for each node: after children
sub div_post
{
    my ($node, $i) = @_;

    return if ignore($node, $i);

    my $name = $node->{name};

    # root object: end multi-column
    if ($i == 2) {
        $curgroup->{text} .= output --$n, qq{
</div> <!-- multi-column -->
};
    }

    # all nodes
    $curgroup->{text} .= output --$n, qq{
</div> <!-- $name -->
};

    # top-level child: revert to _top_ / _bot_ group as appropriate
    if ($i == 3) {
        --$n if $curgroup->{opened};
        # this is messy; if the group was opened then it matched a group
        # criterion and isn't the _top_ (or _bot_) group; in this case revert
        # to the _bot_ group so anything that doesn't match a group criterion
        # will follow anything that does; otherwise revert (in fact remain in)
        # the _top_ group
        my $index = $curgroup->{opened} ? -1 : 0;
        $curgroup = $groups->[$index];
        #print STDERR "$node->{path}: reverted to $curgroup->{name}\n";
    }
}

# called at the end
sub div_end
{
    for my $group (@$groups) {
        if ($group->{opened}) {
            $group->{text} .= output 4, qq{
</div> <!-- $group->{label} -->
};
        }
    }

    for my $group (@$groups) {
        print $group->{text} if $group->{enable};
    }

    print output 0, qq{
  </body>
</html>
};
}

1;
