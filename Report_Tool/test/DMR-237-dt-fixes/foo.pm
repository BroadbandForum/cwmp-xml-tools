package foo;

sub foo_node {
    my ($node) = @_;
    my $path = $node->{path};
    my $minEntries = $node->{minEntries};
    my $maxEntries = $node->{maxEntries};
    #main::tmsg "$path $minEntries $maxEntries" if $minEntries || $maxEntries;
    my ($multi, $fixed, $union) =
        main::util_is_multi_instance($minEntries, $maxEntries);
    main::tmsg "$path ($minEntries, $maxEntries) -> ($multi, $fixed, $union)"
        if $fixed;
}

1;
