# BBF report tool plugin for illustrating data model references
#
# generates a dot (http://www.graphviz.org/Documentation/dotguide.pdf) graph
#
# example invocation:
#   ../../report.pl --plugin=ref --report=ref --include $HOME/bin/cwmp \
#                   --include ../.. tr-104-2-0-0.xml | dot -Tpng >ref.png

package ref;

use strict;

# called at the start
sub ref_init {
}

# called just before traversing the node tree
sub ref_begin {
    print qq{digraph ref \{\n};
    print qq{  rankdir=LR;\n};
    print qq{  node [shape=box];\n};
}

# called for each node: before children
sub ref_node {
    my ($node) = @_;

    my $path = $node->{path};
    my $name = $node->{name};

    # ignore unless it's a parameter and a pathRef
    my $syntax = $node->{syntax};
    my $reference = $syntax->{reference};
    return unless $syntax && $reference && $reference eq 'pathRef';
    
    # ignore unless it references something specific
    my $targetParent = $syntax->{targetParent};
    return unless $targetParent;

    # determine full path names of referenced objects / parameters
    # (logic taken from BBF report tool html_template_reference routine)
    my $object = $node->{pnode}->{path};
    my $targetParent = $syntax->{targetParent};
    my $targetParentScope = $syntax->{targetParentScope};
    my $targetType = $syntax->{targetType};
    foreach my $tp (split ' ', $targetParent) {
        my ($tpp) = main::relative_path($object, $tp, $targetParentScope);

        # check for (and ignore) spurious trailing "{i}." when
        # targetType is "row" (it's a common error)
        if ($targetType eq 'row') {
            if ($tpp =~ /\{i\}\.$/) {
                main::w0msg "$path: trailing \"{i}.\" ignored in ".
                    "targetParent (targetType \"row\"): $tp";
            } else {
                $tpp .= '{i}.';
            }
            # $tpp is now the table object (including "{i}.")
        }

        print qq{  "$object" -> "$tpp" [label="$name"];\n};
    }
}

# called for each node: after children
sub ref_post {
}

# called at the end
sub ref_end {
    print qq{\}\n};
}

1;
